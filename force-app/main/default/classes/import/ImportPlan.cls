/**
 * A format with its names resolved: the object, the field rows are matched on, and for each column
 * the field it fills. A format that could not be resolved lists what is wrong in `problems` and
 * must not be run.
 *
 * `layout(header)` then fits the plan to one file: which cell of a row each column is, which of
 * the file's columns are not read, and what about the file does not fit.
 */
public class ImportPlan {
  public ImportFormat format { get; private set; }
  public inj.IModel model { get; private set; }
  public SObjectField matchOn { get; private set; }
  public List<String> problems { get; private set; }
  private List<Slot> slots;

  private ImportPlan(ImportFormat format) {
    this.format = format;
    problems = new List<String>();
    slots = new List<Slot>();
  }

  /** One column, resolved: the field it fills and, for a file, the cell it reads. */
  public class Slot {
    public String header { get; private set; }
    public String fallback { get; private set; }
    public Boolean required { get; private set; }
    public SObjectField field { get; private set; }
    public DescribeFieldResult shape { get; private set; }
    public inj.IModel related { get; private set; }
    public SObjectField relatedBy { get; private set; }
    public DescribeFieldResult relatedShape { get; private set; }
    public Integer position { get; private set; }
    public Boolean matches { get; private set; }

    private Slot(String header) {
      this.header = header;
      required = false;
      matches = false;
    }

    private Slot placed(Integer position) {
      Slot copy = (Slot) this.clone();
      copy.position = position;
      return copy;
    }

    /** What this column is called in a message: its header, or its field's label when it has none. */
    public String title() {
      return String.isBlank(header) ? shape.getLabel() : header;
    }

    /** How the column is read, for showing to the person: Company fills Account, matched by Account Name. */
    public String reading() {
      String text = title() + ' fills ' + shape.getLabel();
      if (related != null) {
        text += ', matched by ' + relatedShape.getLabel();
      }
      return text;
    }
  }

  /** A plan fitted to one file. */
  public class Layout {
    public List<Slot> slots { get; private set; }
    public Slot matching { get; private set; }
    public List<String> ignored { get; private set; }
    public List<String> problems { get; private set; }

    private Layout() {
      slots = new List<Slot>();
      ignored = new List<String>();
      problems = new List<String>();
    }

    public Boolean fits() {
      return problems.isEmpty();
    }
  }

  public static ImportPlan compile(ImportFormat format) {
    ImportPlan plan = new ImportPlan(format);
    plan.resolve();
    return plan;
  }

  public Boolean isSound() {
    return problems.isEmpty();
  }

  /** Whether the format names its columns. One that does not reads the file's headers as fields. */
  public Boolean namesItsColumns() {
    return !format.columns.isEmpty();
  }

  /** The headers a file of this format has, in the format's order. Empty when it names no columns. */
  public List<String> headers() {
    List<String> named = new List<String>();
    for (Slot slot : slots) {
      if (String.isNotBlank(slot.header)) {
        named.add(slot.header);
      }
    }
    return named;
  }

  /** What the format does, in a sentence: "Creates or updates Contacts, matched on Email". */
  public String summary() {
    String text;
    if (format.mode == ImportFormat.Writes.CREATE) {
      text = 'Creates ' + model.describe().getLabelPlural();
    } else {
      text = (format.mode == ImportFormat.Writes.CHANGE ? 'Updates ' : 'Creates or updates ') + model.describe().getLabelPlural();
      text += ', matched on ' + shapeOf(model, matchOn).getLabel();
    }
    return format.allOrNothing ? text + '. Saves every row or none' : text;
  }

  // Resolving the format

  private void resolve() {
    model = String.isBlank(format.objectName) ? null : App.s.model(format.objectName);
    if (model == null) {
      problems.add('unknown object ' + format.objectName);
      return;
    }
    resolveMatch();
    Set<SObjectField> filled = new Set<SObjectField>();
    Set<String> headersSeen = new Set<String>();
    for (ImportFormat.Column column : format.columns) {
      String about = 'column ' + (String.isBlank(column.header) ? column.fieldName : column.header);
      List<String> wrong = new List<String>();
      Slot slot = slotFor(column.header?.trim(), column.fieldName, column.relatedField, wrong);
      if (slot != null) {
        slot.required = column.required == true;
        slot.fallback = column.fallback;
        if (String.isBlank(column.header) && String.isBlank(column.fallback)) {
          wrong.add('it has neither a header nor a default, so nothing would fill it');
        }
        if (String.isNotBlank(column.header) && !headersSeen.add(column.header.trim().toLowerCase())) {
          wrong.add('another column has the same header');
        }
        if (!filled.add(slot.field)) {
          wrong.add('another column fills ' + slot.shape.getName() + ' too');
        }
        checkFallback(slot, wrong);
        slots.add(slot);
      }
      for (String problem : wrong) {
        problems.add(about + ': ' + problem);
      }
    }
    if (matchOn != null && namesItsColumns() && !filled.contains(matchOn)) {
      problems.add('no column fills ' + shapeOf(model, matchOn).getName() + ', which rows are matched on');
    }
  }

  private void resolveMatch() {
    if (format.mode == null) {
      problems.add('it does not say whether rows create records, change them or both');
      return;
    }
    Boolean creates = format.mode == ImportFormat.Writes.CREATE;
    if (creates && String.isNotBlank(format.matchField)) {
      problems.add('a format that only creates records has nothing to match on ' + format.matchField);
    } else if (!creates && String.isBlank(format.matchField)) {
      problems.add('it changes records, so it needs a field to match rows on');
    } else if (!creates) {
      matchOn = model.fieldMap().get(format.matchField.trim());
      if (matchOn == null) {
        problems.add('unknown match field ' + model.name() + '.' + format.matchField);
      } else if (!matchable(shapeOf(model, matchOn))) {
        problems.add(model.name() + '.' + shapeOf(model, matchOn).getName() + ' is not text or an Id, so rows cannot be matched on it');
        matchOn = null;
      }
    }
  }

  // The column for a field name, or null with the reason added to `wrong`.
  private Slot slotFor(String header, String fieldName, String relatedField, List<String> wrong) {
    SObjectField field = String.isBlank(fieldName) ? null : model.fieldMap().get(fieldName.trim());
    if (field == null) {
      wrong.add('unknown field ' + model.name() + '.' + fieldName);
      return null;
    }
    Slot slot = new Slot(header);
    slot.field = field;
    slot.shape = shapeOf(model, field);
    slot.matches = field == matchOn;
    if (slot.matches) {
      // Rows are found by this field; whether it is also written is settled when the file is run.
      if (String.isNotBlank(relatedField)) {
        wrong.add('rows are matched on ' + slot.shape.getName() + ', so its cells hold its own values, not ' + relatedField);
      }
      return slot;
    }
    if (slot.shape.isCalculated() || slot.shape.isAutoNumber()) {
      wrong.add(slot.shape.getName() + ' is worked out by the org and cannot be filled in');
    } else if (!inj.FieldUtil.takesText(slot.shape)) {
      wrong.add(slot.shape.getName() + ' cannot be filled in from text');
    }
    if (String.isNotBlank(relatedField)) {
      resolveRelated(slot, relatedField.trim(), wrong);
    }
    return slot;
  }

  private void resolveRelated(Slot slot, String relatedField, List<String> wrong) {
    List<SObjectType> targets = slot.shape.getReferenceTo();
    if (targets.isEmpty()) {
      wrong.add(slot.shape.getName() + ' is not a lookup, so it has no related record to match by ' + relatedField);
    } else if (targets.size() > 1) {
      wrong.add(slot.shape.getName() + ' can point at more than one object, so its cells must hold Ids');
    } else {
      inj.IModel target = App.s.model(targets[0]);
      SObjectField finder = target.fieldMap().get(relatedField);
      if (finder == null) {
        wrong.add('unknown field ' + target.name() + '.' + relatedField);
      } else if (shapeOf(target, finder).getSoapType() != SoapType.STRING) {
        wrong.add(target.name() + '.' + shapeOf(target, finder).getName() + ' is not text, so records cannot be matched by it');
      } else {
        slot.related = target;
        slot.relatedBy = finder;
        slot.relatedShape = shapeOf(target, finder);
      }
    }
  }

  // A default is written by an admin once, so a bad one is the format's mistake, not a row's.
  private void checkFallback(Slot slot, List<String> wrong) {
    if (String.isBlank(slot.fallback) || slot.related != null || !inj.FieldUtil.takesText(slot.shape)) {
      return;
    }
    try {
      inj.FieldUtil.fromText(slot.shape, slot.fallback);
    } catch (inj.FieldUtil.GeneralException unreadable) {
      wrong.add('default ' + unreadable.getMessage());
    }
  }

  private static Boolean matchable(DescribeFieldResult shape) {
    return shape.getSoapType() == SoapType.STRING || shape.getSoapType() == SoapType.ID;
  }

  private static DescribeFieldResult shapeOf(inj.IModel owner, SObjectField field) {
    return owner.scheme().getFieldDescribe(field);
  }

  // Fitting a file

  /** The plan fitted to a file with this header. */
  public Layout layout(List<String> header) {
    Layout layout = new Layout();
    if (namesItsColumns()) {
      placeNamedColumns(layout, header);
    } else {
      placeByHeader(layout, header);
    }
    for (Slot slot : layout.slots) {
      if (slot.matches) {
        layout.matching = slot;
      }
    }
    if (matchOn != null && layout.matching == null && layout.problems.isEmpty()) {
      layout.problems.add('it has no column for ' + shapeOf(model, matchOn).getLabel() + ', which rows are matched on');
    }
    if (layout.slots.isEmpty() && layout.problems.isEmpty()) {
      layout.problems.add('none of its columns is one this format reads');
    }
    return layout;
  }

  private void placeNamedColumns(Layout layout, List<String> header) {
    Map<String, Integer> positions = new Map<String, Integer>();
    Set<String> repeated = new Set<String>();
    for (Integer at = 0; at < header.size(); at++) {
      String key = header[at].toLowerCase();
      if (positions.containsKey(key)) {
        repeated.add(key);
      }
      positions.put(key, at);
    }
    Set<Integer> read = new Set<Integer>();
    for (Slot slot : slots) {
      Integer position = String.isBlank(slot.header) ? null : positions.get(slot.header.toLowerCase());
      if (position != null && repeated.contains(slot.header.toLowerCase())) {
        layout.problems.add('it has two columns headed ' + slot.header);
      } else if (position != null) {
        read.add(position);
        layout.slots.add(slot.placed(position));
      } else if (String.isBlank(slot.header) || (String.isNotBlank(slot.fallback) && !slot.matches)) {
        layout.slots.add(slot.placed(null));
      } else if (slot.required || slot.matches) {
        layout.problems.add('it has no column headed ' + slot.header);
      }
    }
    for (Integer at = 0; at < header.size(); at++) {
      if (!read.contains(at) && String.isNotBlank(header[at])) {
        layout.ignored.add(header[at]);
      }
    }
  }

  // A header is a field's API name, its label, or Relationship.Field for a lookup matched by a field.
  private void placeByHeader(Layout layout, List<String> header) {
    Map<String, SObjectField> byLabel = new Map<String, SObjectField>();
    Map<String, SObjectField> byRelationship = new Map<String, SObjectField>();
    Set<String> sharedLabels = new Set<String>();
    for (SObjectField field : model.fieldMap().values()) {
      DescribeFieldResult shape = shapeOf(model, field);
      String label = shape.getLabel().toLowerCase();
      if (byLabel.containsKey(label)) {
        sharedLabels.add(label);
      }
      byLabel.put(label, field);
      if (shape.getRelationshipName() != null) {
        byRelationship.put(shape.getRelationshipName().toLowerCase(), field);
      }
    }
    Set<SObjectField> filled = new Set<SObjectField>();
    for (Integer at = 0; at < header.size(); at++) {
      String title = header[at];
      if (String.isBlank(title)) {
        continue;
      }
      String key = title.toLowerCase();
      SObjectField field = model.fieldMap().get(title);
      String relatedField;
      if (field == null && title.contains('.')) {
        field = byRelationship.get(key.substringBefore('.').trim());
        relatedField = title.substringAfter('.');
      }
      if (field == null && !sharedLabels.contains(key)) {
        field = byLabel.get(key);
      }
      List<String> wrong = new List<String>();
      Slot slot = field == null ? null : slotFor(title, shapeOf(model, field).getName(), relatedField, wrong);
      if (slot == null || (!slot.matches && (slot.shape.isCalculated() || slot.shape.isAutoNumber()))) {
        layout.ignored.add(title);
      } else if (!wrong.isEmpty()) {
        layout.problems.add('column ' + title + ': ' + String.join(wrong, '; '));
      } else if (!filled.add(slot.field)) {
        layout.problems.add('column ' + title + ': another column fills ' + slot.shape.getName() + ' too');
      } else {
        layout.slots.add(slot.placed(at));
      }
    }
  }
}
