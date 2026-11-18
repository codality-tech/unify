/**
 * A blueprint definition checked against the schema and made ready to use.
 *
 * Compiling resolves the object, every field, every visibility rule, every {!merge.field} and every
 * column through the framework: rules become conditions (the same condition filters a table in SOQL
 * and shows or hides an element in memory), and merge fields and columns become paths, which can
 * cross lookups.
 *
 * Nothing here throws for a mistake in a blueprint. A part or column that cannot be resolved keeps
 * its problems and is left out of the work, so the rest of the form or table still renders.
 */
public with sharing class ReformPlan {
  public enum Kind {
    FIELD,
    HEADING,
    RICH_TEXT,
    SPACER,
    INVALID
  }

  private static final Integer FULL_WIDTH = 12;
  private static final Pattern MERGE_FIELD = Pattern.compile('\\{!\\s*([A-Za-z0-9_.]+)\\s*\\}');

  /** One slot of a form, resolved. */
  public class Part {
    public Kind kind;
    public Integer width = FULL_WIDTH;
    public unif.ICondition showWhen;
    public List<String> problems = new List<String>();

    // Field parts
    public SObjectField field;
    public DescribeFieldResult describe;
    public String label;
    public Boolean required = false;
    public Boolean hidden = false;
    public Boolean onCreate = true;
    public Boolean onUpdate = true;
    public Boolean isFixed = false;
    public Object fixedValue;
    public Boolean hasDefault = false;
    public Object defaultValue;
    /** True when a rule or merge field reads this field, so a form should recompute when it changes. */
    public Boolean reactive = false;

    // Heading and rich text parts
    public String content;
    /** The merge fields in the content: the text between {! and }, and the path it names. */
    public Map<String, unif.IPath> mergePaths = new Map<String, unif.IPath>();

    public Boolean usable() {
      return problems.isEmpty() && kind != ReformPlan.Kind.INVALID;
    }
  }

  public class Column {
    public String name;
    public String label;
    public unif.IPath path;
    public List<String> problems = new List<String>();
  }

  public ReformDefinition definition;
  public unif.IModel model;
  public String label;
  public String pluralLabel;
  public Id recordTypeId;
  public List<Part> parts = new List<Part>();
  public List<Column> columns = new List<Column>();
  /** Which rows a table lists: the filters, the fixed field values and the record type. */
  public List<unif.ICondition> rowConditions = new List<unif.ICondition>();
  /**
   * For every lookup on the object that a rule or merge field reads through: the paths to read,
   * as seen from the parent. Account.Owner.Name on an opportunity is Owner.Name under AccountId.
   */
  public Map<SObjectField, Set<unif.IPath>> parentPaths = new Map<SObjectField, Set<unif.IPath>>();
  /** The object's own fields that a rule or merge field reads, lookups walked through included. */
  public Set<SObjectField> fieldsRead = new Set<SObjectField>();
  public List<String> problems = new List<String>();

  private Map<SObjectField, Part> partByField = new Map<SObjectField, Part>();

  public static ReformPlan compile(ReformDefinition definition) {
    ReformPlan plan = new ReformPlan();
    plan.definition = definition;
    plan.problems.addAll(definition.problems);
    plan.bindObject();
    if (plan.model != null) {
      plan.bindRecordType();
      for (ReformDefinition.Element element : definition.elements) {
        plan.add(plan.partFor(element));
      }
      plan.applyParameters();
      plan.bindColumns();
      plan.bindRowConditions();
      plan.traceWhatIsRead();
    }
    return plan;
  }

  public Boolean isUsable() {
    return model != null;
  }

  /** The field part for a field, or null when the blueprint has none. */
  public Part partFor(SObjectField field) {
    return partByField.get(field);
  }

  /** Every problem in the blueprint, each saying where it is. */
  public List<String> allProblems() {
    List<String> found = new List<String>(problems);
    for (Integer at = 0; at < parts.size(); at++) {
      for (String problem : parts[at].problems) {
        found.add('Element ' + (at + 1) + ': ' + problem);
      }
    }
    for (Integer at = 0; at < columns.size(); at++) {
      for (String problem : columns[at].problems) {
        found.add('Column ' + (at + 1) + ': ' + problem);
      }
    }
    return found;
  }

  // Object and record type

  private void bindObject() {
    if (definition.objectName == null) {
      problems.add('A blueprint needs an object (sobjectName)');
      return;
    }
    model = App.s.model(definition.objectName);
    if (model == null) {
      problems.add('There is no object named ' + definition.objectName);
      return;
    }
    DescribeSObjectResult described = model.describe();
    label = definition.label ?? described.getLabel();
    pluralLabel = definition.pluralLabel ?? described.getLabelPlural();
  }

  private void bindRecordType() {
    if (definition.recordType == null) {
      return;
    }
    try {
      recordTypeId = model.recordTypeId(definition.recordType);
    } catch (Exception unknown) {
      problems.add(model.name() + ' has no record type ' + definition.recordType);
    }
  }

  // Parts

  private Part partFor(ReformDefinition.Element element) {
    Part part = new Part();
    Integer asked = element.width;
    part.width = asked != null && asked >= 1 && asked <= FULL_WIDTH ? asked : FULL_WIDTH;
    if (element.conflicting) {
      part.kind = Kind.INVALID;
      part.problems.add('An element holds one of field, heading or richtext, not several');
    } else if (element.field != null) {
      part.kind = Kind.FIELD;
      bindField(part, element.field);
    } else if (element.heading != null) {
      part.kind = Kind.HEADING;
      bindContent(part, element.heading);
    } else if (element.richText != null) {
      part.kind = Kind.RICH_TEXT;
      bindContent(part, element.richText);
    } else {
      part.kind = Kind.SPACER;
    }
    if (element.showWhen != null) {
      part.showWhen = rule(element.showWhen, part.problems, 'visible');
    }
    return part;
  }

  private void add(Part part) {
    if (part.kind == Kind.FIELD && part.field != null) {
      if (partByField.containsKey(part.field)) {
        part.problems.add(part.describe.getName() + ' already has an element');
      } else {
        partByField.put(part.field, part);
      }
    }
    parts.add(part);
  }

  private void bindField(Part part, ReformDefinition.FieldSpec spec) {
    part.field = spec.name == null ? null : model.fieldMap().get(spec.name);
    if (part.field == null) {
      part.problems.add(model.name() + ' has no field named ' + spec.name);
      return;
    }
    part.describe = part.field.getDescribe();
    part.label = part.describe.getLabel();
    // A lookup is labelled for its Id ("Account ID"), but a form shows the record: "Account".
    if (part.describe.getType() == Schema.DisplayType.REFERENCE) {
      part.label = part.label.removeEndIgnoreCase(' ID');
    }
    // Required by the schema unless the blueprint says otherwise: must be given on create.
    part.required = part.describe.isCreateable() && !part.describe.isNillable() && !part.describe.isDefaultedOnCreate();
    overlay(part, spec);
  }

  // What a blueprint may say about a field, over what the schema says.
  private void overlay(Part part, ReformDefinition.FieldSpec spec) {
    part.label = spec.label ?? part.label;
    part.required = spec.required ?? part.required;
    part.hidden = spec.hidden ?? part.hidden;
    part.onCreate = spec.createable ?? part.onCreate;
    part.onUpdate = spec.updateable ?? part.onUpdate;
    if (spec.fixedValue != null) {
      part.isFixed = true;
      part.fixedValue = typed(spec.fixedValue, part, 'fixedValue');
    }
    if (spec.defaultValue != null) {
      part.hasDefault = true;
      part.defaultValue = typed(spec.defaultValue, part, 'defaultValue');
    }
  }

  // Parameters adjust the element of a field that has one, and otherwise add the field.
  private void applyParameters() {
    for (ReformDefinition.FieldSpec spec : definition.parameters) {
      SObjectField field = spec.name == null ? null : model.fieldMap().get(spec.name);
      Part existing = field == null ? null : partByField.get(field);
      if (existing != null) {
        overlay(existing, spec);
      } else {
        Part added = new Part();
        added.kind = Kind.FIELD;
        bindField(added, spec);
        add(added);
      }
    }
  }

  private void bindContent(Part part, String content) {
    part.content = content;
    if (String.isBlank(content)) {
      part.problems.add('Content must not be blank');
      return;
    }
    Matcher found = MERGE_FIELD.matcher(content);
    while (found.find()) {
      String named = found.group(1);
      unif.IPath path = model.path(named);
      if (path == null) {
        part.problems.add('{!' + named + '} is not a field path on ' + model.name());
      } else {
        part.mergePaths.put(found.group(0), path);
      }
    }
  }

  // Columns

  private void bindColumns() {
    List<ReformDefinition.ColumnSpec> asked = definition.columns;
    if (asked.isEmpty()) {
      asked = defaultColumns();
    }
    for (ReformDefinition.ColumnSpec spec : asked) {
      Column column = new Column();
      column.name = spec.name;
      column.path = spec.name == null ? null : model.path(spec.name);
      if (column.path == null) {
        column.problems.add(spec.name + ' is not a field path on ' + model.name());
      } else {
        column.name = column.path.name();
        column.label = spec.label ?? column.path.label();
      }
      columns.add(column);
    }
  }

  // With no columns asked for: the record's name and when it was made and last changed.
  private List<ReformDefinition.ColumnSpec> defaultColumns() {
    List<String> names = new List<String>{ 'CreatedDate', 'LastModifiedDate' };
    SObjectField titleField = definition.namingField == null ? model.nameField() : model.fieldMap().get(definition.namingField);
    if (titleField != null) {
      names.add(0, titleField.getDescribe().getName());
    }
    List<ReformDefinition.ColumnSpec> made = new List<ReformDefinition.ColumnSpec>();
    for (String name : names) {
      if (model.fieldMap().containsKey(name)) {
        ReformDefinition.ColumnSpec spec = new ReformDefinition.ColumnSpec();
        spec.name = name;
        made.add(spec);
      }
    }
    return made;
  }

  // Rows

  private void bindRowConditions() {
    for (String filter : definition.filters) {
      unif.ICondition parsed = rule(filter, problems, 'filter');
      if (parsed != null) {
        rowConditions.add(parsed);
      }
    }
    for (Part part : parts) {
      if (part.usable() && part.isFixed) {
        rowConditions.add(App.s.eq(part.field, part.fixedValue));
      }
    }
    if (recordTypeId != null) {
      rowConditions.add(App.s.eq('RecordTypeId', recordTypeId));
    }
  }

  // A rule written as a condition, e.g. StageName != 'Closed Won' AND Amount > 1000.
  private unif.ICondition rule(String written, List<String> report, String what) {
    try {
      return model.parseCondition(written);
    } catch (Exception unreadable) {
      report.add('Cannot read the ' + what + ' rule "' + written + '": ' + unreadable.getMessage());
      return null;
    }
  }

  // What the form reads

  // Finds every path a rule or merge field reads. Fields of the object itself make their parts
  // reactive; paths through a lookup are remembered under that lookup, as seen from the parent.
  private void traceWhatIsRead() {
    Set<unif.IPath> read = new Set<unif.IPath>();
    for (Part part : parts) {
      if (!part.usable()) {
        continue;
      }
      read.addAll(part.mergePaths.values());
      if (part.showWhen != null) {
        read.addAll(model.compileCondition(part.showWhen).getPaths());
      }
    }
    for (unif.IPath path : read) {
      List<SObjectField> steps = path.fieldSequence();
      fieldsRead.add(steps[0]);
      Part first = partByField.get(steps[0]);
      if (first != null) {
        first.reactive = true;
      }
      if (steps.size() > 1) {
        SObjectField lookup = steps.remove(0);
        if (!parentPaths.containsKey(lookup)) {
          parentPaths.put(lookup, new Set<unif.IPath>());
        }
        parentPaths.get(lookup).add(App.s.path(steps));
      }
    }
  }

  // Values

  // A fixed or default value, written as text, as the field's own type. Blank text means null.
  private Object typed(String written, Part part, String what) {
    if (String.isBlank(written)) {
      return null;
    }
    Object value = written;
    Schema.SoapType wanted = part.describe.getSoapType();
    try {
      if (wanted == Schema.SoapType.BOOLEAN) {
        value = Boolean.valueOf(written);
      } else if (wanted == Schema.SoapType.INTEGER) {
        value = Integer.valueOf(written);
      } else if (wanted == Schema.SoapType.DOUBLE) {
        value = Decimal.valueOf(written);
      } else if (wanted == Schema.SoapType.DATE) {
        value = Date.valueOf(written);
      } else if (wanted == Schema.SoapType.DATETIME) {
        value = Datetime.valueOfGmt(written.replace('T', ' ').removeEnd('Z'));
      } else if (wanted == Schema.SoapType.ID) {
        value = Id.valueOf(written);
      }
    } catch (Exception wrongType) {
      value = null;
      part.problems.add(what + ' "' + written + '" is not a valid ' + part.describe.getType() + ' for ' + part.describe.getName());
    }
    return value;
  }
}
