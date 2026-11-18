/**
 * Loads CSV text into records, as an import format describes.
 *
 *   ImportResult done = Importer.load('Contacts', csvText);
 *   ImportResult wouldBe = Importer.check('Contacts', csvText); // everything but the save
 *
 * A row that cannot be read or saved fails by itself, with a message that names its row and
 * column, and the rest are saved. A format that is all or nothing saves no row unless every row
 * can be saved, and still says what is wrong with each one.
 *
 * The import is made as the person asking for it: rows are matched against the records they can
 * see, and saved with their permissions. An object or field they may not write stops the file,
 * with a message, before anything is saved.
 *
 * What it costs, however many rows: one query for each column that finds a related record, one to
 * match the rows against existing records, one insert and one update.
 */
public with sharing class Importer {
  public class ImportException extends Exception {
  }

  /** The column of a failures file that says why each row failed. */
  public static final String ERROR_COLUMN = 'Error';

  /** A cell holding this empties its field. An empty cell leaves the field alone. */
  public static final String CLEAR = '#N/A';

  /** Tests lower this to see a file too large for one transaction refused. */
  @TestVisible
  private static Integer rowsPerTransaction;

  public static ImportResult load(String formatName, String csvText) {
    return run(formatName, csvText, 0, true);
  }

  public static ImportResult check(String formatName, String csvText) {
    return run(formatName, csvText, 0, false);
  }

  /**
   * A file too large for one transaction is sent in parts, each with the header row. `rowsBefore`
   * is how many rows came in the parts already sent, so a message names the row as the file has it.
   */
  public static ImportResult run(String formatName, String csvText, Integer rowsBefore, Boolean save) {
    ImportPlan plan = ImportFormats.named(formatName);
    inj.CsvUtil.Table table;
    try {
      table = inj.CsvUtil.read(csvText);
    } catch (inj.CsvUtil.GeneralException unreadable) {
      throw new ImportException('The file cannot be read: ' + unreadable.getMessage());
    }
    if (table.header.isEmpty()) {
      throw new ImportException('The file is empty');
    }
    ImportPlan.Layout layout = plan.layout(table.header);
    if (!layout.fits()) {
      throw new ImportException('The file does not fit the format ' + plan.format.label + ': ' + String.join(layout.problems, '; '));
    }
    return new Loading(plan, layout, table, rowsBefore ?? 0).run(save == true);
  }

  // One row of the file on its way to being a record.
  private class Entry {
    Integer row;
    List<String> cells;
    Map<Integer, Object> values = new Map<Integer, Object>();
    Map<Integer, String> lookups = new Map<Integer, String>();
    List<String> problems = new List<String>();
    String matchKey;
    Id existing;
    Boolean creates = true;
    SObject record;

    Entry(Integer row, List<String> cells) {
      this.row = row;
      this.cells = cells;
    }

    Boolean isGood() {
      return problems.isEmpty();
    }
  }

  private with sharing class Loading {
    final ImportPlan plan;
    final ImportPlan.Layout layout;
    final inj.CsvUtil.Table table;
    final List<ImportPlan.Slot> slots;
    final DescribeSObjectResult shape;
    final List<Entry> entries = new List<Entry>();
    final ImportResult result = new ImportResult();
    final Integer rowsBefore;
    List<Boolean> filledOnNew;
    List<Boolean> filledOnExisting;

    Loading(ImportPlan plan, ImportPlan.Layout layout, inj.CsvUtil.Table table, Integer rowsBefore) {
      this.plan = plan;
      this.layout = layout;
      this.table = table;
      this.rowsBefore = rowsBefore;
      slots = layout.slots;
      shape = plan.model.describe();
    }

    ImportResult run(Boolean save) {
      readRows();
      Integer room = rowsPerTransaction ?? (Limits.getLimitDmlRows() - Limits.getDmlRows());
      if (save && entries.size() > room) {
        throw new ImportException('The text has ' + entries.size() + ' rows, and ' + room + ' is the most one transaction can save. Send it in parts.');
      }
      findRelatedRecords();
      matchRows();
      settleAccess();
      buildRecords();
      if (save) {
        saveRecords();
      }
      return report(save);
    }

    // Reading

    private void readRows() {
      for (Integer index = 0; index < table.rows.size(); index++) {
        List<String> cells = table.rows[index];
        if (inj.CsvUtil.isBlank(cells)) {
          continue;
        }
        Entry entry = new Entry(rowsBefore + table.rowNumber(index), cells);
        for (Integer at = 0; at < slots.size(); at++) {
          readCell(entry, at);
        }
        entries.add(entry);
      }
    }

    private void readCell(Entry entry, Integer at) {
      ImportPlan.Slot slot = slots[at];
      String text = slot.position != null && slot.position < entry.cells.size() ? entry.cells[slot.position].trim() : '';
      if (text == '' && String.isNotBlank(slot.fallback)) {
        text = slot.fallback.trim();
      }
      if (text == '') {
        if (slot.required) {
          entry.problems.add(slot.title() + ' is empty');
        }
      } else if (text == CLEAR) {
        if (slot.required || slot.matches) {
          entry.problems.add(slot.title() + ' cannot be emptied');
        } else {
          entry.values.put(at, null);
        }
      } else if (slot.related != null) {
        entry.lookups.put(at, text);
      } else {
        try {
          entry.values.put(at, inj.FieldUtil.fromText(slot.shape, text));
        } catch (inj.FieldUtil.GeneralException unreadable) {
          entry.problems.add(slot.title() + ': ' + unreadable.getMessage());
        }
      }
    }

    // Related records: one query for each column that names them by a field.

    private void findRelatedRecords() {
      for (Integer at = 0; at < slots.size(); at++) {
        ImportPlan.Slot slot = slots[at];
        Set<String> wanted = new Set<String>();
        for (Entry entry : entries) {
          if (entry.lookups.containsKey(at)) {
            wanted.add(entry.lookups.get(at));
          }
        }
        if (wanted.isEmpty()) {
          continue;
        }
        DescribeSObjectResult relatedShape = slot.related.describe();
        if (!relatedShape.isAccessible() || !slot.relatedShape.isAccessible()) {
          throw new ImportException('You cannot read ' + relatedShape.getLabelPlural() + ', which the column ' + slot.title() + ' looks up');
        }
        Map<String, List<Id>> found = idsByValue(slot.related, slot.relatedBy, wanted);
        for (Entry entry : entries) {
          String text = entry.lookups.get(at);
          List<Id> ids = text == null ? null : found.get(text.toLowerCase());
          if (text == null) {
            continue;
          } else if (ids == null) {
            entry.problems.add(slot.title() + ': no ' + relatedShape.getLabel() + ' you can see has ' + slot.relatedShape.getLabel() + ' ' + quoted(text));
          } else if (ids.size() > 1) {
            entry.problems.add(slot.title() + ': ' + ids.size() + ' ' + relatedShape.getLabelPlural() + ' have ' + slot.relatedShape.getLabel() + ' ' + quoted(text));
          } else {
            entry.values.put(at, ids[0]);
          }
        }
      }
    }

    // The records of an object the person can see, by the value one field holds, in lower case.
    private Map<String, List<Id>> idsByValue(inj.IModel model, SObjectField field, Set<String> values) {
      inj.IQuery reading = model.query().withSharing(true);
      reading.fields().add(new Set<SObjectField>{ model.fieldMap().get('Id'), field });
      reading.addCondition(App.s.iin(field, values));
      Map<String, List<Id>> found = new Map<String, List<Id>>();
      for (SObject record : reading.run()) {
        String key = String.valueOf(record.get(field)).toLowerCase();
        if (!found.containsKey(key)) {
          found.put(key, new List<Id>());
        }
        found.get(key).add(record.Id);
      }
      return found;
    }

    // Existing records: one query, by the field the format matches on.

    private void matchRows() {
      ImportPlan.Slot slot = layout.matching;
      if (slot == null) {
        return;
      }
      if (!shape.isAccessible() || !slot.shape.isAccessible()) {
        throw new ImportException('You cannot read ' + slot.shape.getLabel() + ' on ' + shape.getLabelPlural() + ', which rows are matched on');
      }
      Integer at = slots.indexOf(slot);
      Boolean blankMakesNew = slot.shape.getType() == DisplayType.ID && plan.format.mode == ImportFormat.Writes.BOTH;
      Map<String, Integer> firstRowWith = new Map<String, Integer>();
      Set<String> wanted = new Set<String>();
      for (Entry entry : entries) {
        Object value = entry.values.get(at);
        if (!entry.isGood()) {
          continue;
        } else if (value == null) {
          if (!blankMakesNew) {
            entry.problems.add(slot.title() + ' is empty, and rows are matched on it');
          }
          continue;
        }
        String key = String.valueOf(value).toLowerCase();
        if (firstRowWith.containsKey(key)) {
          entry.problems.add(slot.title() + ': row ' + firstRowWith.get(key) + ' has ' + quoted(String.valueOf(value)) + ' too');
        } else {
          firstRowWith.put(key, entry.row);
          entry.matchKey = key;
          wanted.add(String.valueOf(value));
        }
      }
      if (wanted.isEmpty()) {
        return;
      }
      Map<String, List<Id>> found = idsByValue(plan.model, slot.field, wanted);
      for (Entry entry : entries) {
        if (entry.matchKey == null) {
          continue;
        }
        List<Id> ids = found.get(entry.matchKey);
        String sought = slot.shape.getLabel() + ' ' + quoted(String.valueOf(entry.values.get(at)));
        if (ids == null) {
          // A row with an Id says it is an existing record, so one that is not found is never made new.
          if (plan.format.mode == ImportFormat.Writes.CHANGE || slot.shape.getType() == DisplayType.ID) {
            entry.problems.add(slot.title() + ': no ' + shape.getLabel() + ' you can see has ' + sought);
          }
        } else if (ids.size() > 1) {
          entry.problems.add(slot.title() + ': ' + ids.size() + ' ' + shape.getLabelPlural() + ' have ' + sought);
        } else {
          entry.existing = ids[0];
          entry.creates = false;
        }
      }
    }

    // Access: what the person may write, settled before anything is saved.

    private void settleAccess() {
      Boolean makesNew = false;
      Boolean changesExisting = false;
      for (Entry entry : entries) {
        makesNew = makesNew || (entry.isGood() && entry.creates);
        changesExisting = changesExisting || (entry.isGood() && !entry.creates);
      }
      if (makesNew && !shape.isCreateable()) {
        throw new ImportException('You cannot create ' + shape.getLabelPlural());
      }
      if (changesExisting && !shape.isUpdateable()) {
        throw new ImportException('You cannot change ' + shape.getLabelPlural());
      }
      filledOnNew = new List<Boolean>();
      filledOnExisting = new List<Boolean>();
      for (ImportPlan.Slot slot : slots) {
        Boolean isTheId = slot.shape.getType() == DisplayType.ID;
        Boolean onNew = !isTheId && slot.shape.isCreateable();
        Boolean onExisting = !isTheId && slot.shape.isUpdateable();
        filledOnNew.add(onNew);
        filledOnExisting.add(onExisting);
        if (slot.matches || !(makesNew || changesExisting)) {
          continue;
        }
        if (!(makesNew && onNew) && !(changesExisting && onExisting)) {
          throw new ImportException('You cannot fill in ' + slot.shape.getLabel() + ' on ' + shape.getLabelPlural());
        }
        if (makesNew && !onNew) {
          result.notes.add(slot.shape.getLabel() + ' is not filled in on new records: it can only be changed on existing ones');
        }
        if (changesExisting && !onExisting) {
          result.notes.add(slot.shape.getLabel() + ' is left as it is on existing records: it can only be filled in on new ones');
        }
      }
    }

    private void buildRecords() {
      for (Entry entry : entries) {
        if (!entry.isGood()) {
          continue;
        }
        entry.record = entry.creates ? plan.model.token().newSObject() : plan.model.token().newSObject(entry.existing);
        List<Boolean> filled = entry.creates ? filledOnNew : filledOnExisting;
        for (Integer at : entry.values.keySet()) {
          if (filled[at]) {
            entry.record.put(slots[at].field, entry.values.get(at));
          }
        }
      }
    }

    // Saving: one insert and one update, each row passing or failing by itself.

    private void saveRecords() {
      Boolean whole = plan.format.allOrNothing;
      List<Entry> good = new List<Entry>();
      for (Entry entry : entries) {
        if (entry.isGood()) {
          good.add(entry);
        }
      }
      if (whole && good.size() < entries.size()) {
        return;
      }
      Savepoint before = whole ? Database.setSavepoint() : null;
      // The framework's unit of work, as the person and with partial success: it inserts the new
      // records in one statement, updates the others in one, and says which it could not save.
      inj.IWork work = App.s.work().withSharing(true);
      work.options().optAllOrNone = false;
      for (Entry entry : good) {
        work.track(entry.record);
      }
      work.apply();
      Boolean allSaved = work.failures().isEmpty();
      for (Entry entry : good) {
        inj.IWorkFailure failure = allSaved ? null : work.failureOf(entry.record);
        if (failure != null) {
          entry.problems.add(failure.getMessage());
        }
      }
      if (whole && !allSaved) {
        Database.rollback(before);
      } else {
        result.saved = true;
      }
    }

    // Reporting

    private ImportResult report(Boolean save) {
      result.format = plan.format.name;
      result.rows = entries.size();
      result.ignored = layout.ignored;
      for (ImportPlan.Slot slot : slots) {
        result.columns.add(slot.reading());
      }
      List<Entry> failed = new List<Entry>();
      for (Entry entry : entries) {
        if (!entry.isGood()) {
          failed.add(entry);
          result.failures.add(new ImportResult.Failure(entry.row, String.join(entry.problems, '; ')));
        } else if (save && !result.saved) {
          result.held++;
        } else {
          if (entry.creates) {
            result.created++;
          } else {
            result.updated++;
          }
          if (result.saved) {
            result.idsByRow.put(entry.row, entry.record.Id);
          }
        }
      }
      result.failed = failed.size();
      if (result.held > 0) {
        result.notes.add('Nothing was saved: this format saves every row or none, and ' + result.failed + (result.failed == 1 ? ' row' : ' rows') + ' failed');
      }
      if (!failed.isEmpty()) {
        result.failuresCsv = failuresFile(failed);
      }
      return result;
    }

    // The failed rows as they came, with a column saying why: a new last column, or the file's own
    // Error column when it has one, as a failures file that was corrected and sent again does.
    // Written by the framework's CsvUtil.
    private String failuresFile(List<Entry> failed) {
      List<String> titles = new List<String>();
      String errorTitle;
      for (Integer at = 0; at < table.header.size(); at++) {
        String title = String.isBlank(table.header[at]) ? 'Column ' + (at + 1) : table.header[at].replace('\n', ' ');
        titles.add(titles.contains(title) ? title + ' (' + (at + 1) + ')' : title);
        if (errorTitle == null && title.equalsIgnoreCase(ERROR_COLUMN)) {
          errorTitle = title;
        }
      }
      if (errorTitle == null) {
        errorTitle = ERROR_COLUMN;
        titles.add(errorTitle);
      }
      List<Map<String, Object>> lines = new List<Map<String, Object>>();
      for (Entry entry : failed) {
        Map<String, Object> line = new Map<String, Object>();
        for (Integer at = 0; at < table.header.size() && at < entry.cells.size(); at++) {
          line.put(titles[at], entry.cells[at]);
        }
        line.put(errorTitle, String.join(entry.problems, '; '));
        lines.add(line);
      }
      return inj.CsvUtil.toCsv(titles, lines);
    }

    private String quoted(String text) {
      return '"' + text.abbreviate(60) + '"';
    }
  }
}
