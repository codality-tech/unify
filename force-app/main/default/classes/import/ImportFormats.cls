/**
 * The import formats this org holds. They are read from Import_Format__mdt and Import_Column__mdt
 * once per transaction, which costs no query, and a format is compiled the first time it is asked for.
 */
public class ImportFormats {
  @TestVisible
  private static List<ImportFormat> injected;
  private static Map<String, ImportFormat> activeByName;
  private static Map<String, ImportPlan> plansByName = new Map<String, ImportPlan>();

  /** Tests give the formats themselves, so they do not depend on the records the org happens to hold. */
  @TestVisible
  private static void use(List<ImportFormat> formats) {
    injected = formats;
    activeByName = null;
    plansByName = new Map<String, ImportPlan>();
  }

  private static Map<String, ImportFormat> formats() {
    if (activeByName == null) {
      activeByName = new Map<String, ImportFormat>();
      for (ImportFormat format : injected ?? stored()) {
        if (format.active == true) {
          activeByName.put(format.name.toLowerCase(), format);
        }
      }
    }
    return activeByName;
  }

  // A column belongs to the format its Format field points at. Columns come in the order of their
  // Position, then of their names.
  private static List<ImportFormat> stored() {
    List<Import_Column__mdt> everyColumn = new List<Import_Column__mdt>(Import_Column__mdt.getAll().values());
    everyColumn.sort(new ByPosition());
    Map<Id, List<Import_Column__mdt>> columnsByFormat = new Map<Id, List<Import_Column__mdt>>();
    for (Import_Column__mdt column : everyColumn) {
      if (!columnsByFormat.containsKey(column.Format__c)) {
        columnsByFormat.put(column.Format__c, new List<Import_Column__mdt>());
      }
      columnsByFormat.get(column.Format__c).add(column);
    }
    List<ImportFormat> found = new List<ImportFormat>();
    for (Import_Format__mdt each : Import_Format__mdt.getAll().values()) {
      found.add(ImportFormat.fromMetadata(each, columnsByFormat.get(each.Id) ?? new List<Import_Column__mdt>()));
    }
    return found;
  }

  @TestVisible
  private class ByPosition implements Comparator<Import_Column__mdt> {
    public Integer compare(Import_Column__mdt one, Import_Column__mdt other) {
      Decimal first = one.Position__c ?? 9999;
      Decimal second = other.Position__c ?? 9999;
      if (first != second) {
        return first < second ? -1 : 1;
      }
      return one.DeveloperName.compareTo(other.DeveloperName);
    }
  }

  private static ImportPlan planFor(ImportFormat format) {
    String key = format.name.toLowerCase();
    if (!plansByName.containsKey(key)) {
      plansByName.put(key, ImportPlan.compile(format));
    }
    return plansByName.get(key);
  }

  /** The format of that name, ready to run. Refuses a name no active format has, and a format that cannot run. */
  public static ImportPlan named(String formatName) {
    ImportFormat format = formatName == null ? null : formats().get(formatName.toLowerCase());
    if (format == null) {
      throw new Importer.ImportException('There is no import format named ' + formatName);
    }
    ImportPlan plan = planFor(format);
    if (!plan.isSound()) {
      throw new Importer.ImportException('Import format ' + format.name + ' cannot run: ' + String.join(plan.problems, '; '));
    }
    return plan;
  }

  /** The names of the active formats, in name order. */
  public static List<String> names() {
    List<String> found = new List<String>();
    for (ImportFormat format : formats().values()) {
      found.add(format.name);
    }
    found.sort();
    return found;
  }

  /** The active formats that can run, in name order. */
  public static List<ImportPlan> runnable() {
    List<ImportPlan> sound = new List<ImportPlan>();
    for (String name : names()) {
      ImportPlan plan = planFor(formats().get(name.toLowerCase()));
      if (plan.isSound()) {
        sound.add(plan);
      }
    }
    return sound;
  }

  /** What is wrong, by format name; a format with nothing wrong has no entry. */
  public static Map<String, List<String>> problems() {
    Map<String, List<String>> found = new Map<String, List<String>>();
    for (ImportFormat format : formats().values()) {
      ImportPlan plan = planFor(format);
      if (!plan.isSound()) {
        found.put(format.name, plan.problems);
      }
    }
    return found;
  }
}
