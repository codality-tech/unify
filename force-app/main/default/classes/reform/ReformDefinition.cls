/**
 * What a blueprint says, before any of it is checked against the schema: which object it is for,
 * which elements a form shows, which columns a table shows, and which rows the table lists.
 *
 * A definition is read from a stored Reform_Blueprint__c record, from a map sent by a component,
 * or from both: a sent definition that names a stored blueprint is laid over it (resolve).
 *
 * The map uses the same keys as the stored JSON:
 *
 *   { "name": "deal_form", "sobjectName": "Opportunity", "recordTypeDeveloperName": "...",
 *     "elements": [ { "width": 6, "visible": "Amount > 1000",
 *                     "field": { "name": "NextStep", "label": "...", "required": true,
 *                                "defaultValue": "...", "fixedValue": "...", "hidden": false } },
 *                   { "field": { "name": "ContactId",
 *                                "create": { "blueprint": "new_person", "fill": "PersonContactId" } } },
 *                   { "heading": { "content": "About {!Account.Name}" } },
 *                   { "richtext": { "content": "<b>{!Owner.Name}</b>" } },
 *                   { } ],
 *     "columns": [ { "name": "Account.Name", "label": "Account" } ],
 *     "parameters": [ { "name": "AccountId", "fixedValue": "001..." } ],
 *     "filters": [ "StageName != 'Closed Lost'" ] }
 */
public class ReformDefinition {
  public class FieldSpec {
    public String name;
    public String label;
    public String fixedValue;
    public String defaultValue;
    public Boolean required;
    public Boolean hidden;
    public Boolean createable;
    public Boolean updateable;
    /**
     * For a lookup: the stored blueprint of a record the user may make from the lookup instead of
     * picking one, saved with this record. Fill is the new record's field the lookup takes, when not
     * its Id: a Person Account fills a Contact lookup from its PersonContactId.
     */
    public String createBlueprint;
    public String createFill;
  }

  /** One slot of a form. At most one of field, heading and richText is set; none means a spacer. */
  public class Element {
    public Integer width;
    public String showWhen;
    public FieldSpec field;
    public String heading;
    public String richText;
    // True when the element named more than one kind of content.
    public Boolean conflicting = false;
  }

  public class ColumnSpec {
    public String name;
    public String label;
  }

  public String name;
  public String objectName;
  public String label;
  public String pluralLabel;
  public String recordType;
  public String namingField;
  public String iconName;
  public Boolean createable;
  public Boolean updateable;
  public Boolean deleteable;
  public List<Element> elements = new List<Element>();
  public List<ColumnSpec> columns = new List<ColumnSpec>();
  public List<FieldSpec> parameters = new List<FieldSpec>();
  public List<String> filters = new List<String>();
  /** What could not be read: stored JSON that does not parse, a list where an object belongs. */
  public List<String> problems = new List<String>();

  /** From a map as a component sends it, or as JSON.deserializeUntyped returns it. */
  public static ReformDefinition fromMap(Map<String, Object> sent) {
    ReformDefinition definition = new ReformDefinition();
    Map<String, Object> source = sent == null ? new Map<String, Object>() : sent;
    definition.name = text(source.get('name'));
    definition.objectName = text(source.get('sobjectName'));
    definition.label = text(source.get('label'));
    definition.pluralLabel = text(source.get('pluralLabel'));
    definition.recordType = text(source.get('recordTypeDeveloperName'));
    definition.namingField = text(source.get('namingField'));
    definition.iconName = text(source.get('iconName'));
    definition.createable = flag(source.get('createable'));
    definition.updateable = flag(source.get('updateable'));
    definition.deleteable = flag(source.get('deleteable'));
    definition.readElements(source.get('elements'));
    definition.readColumns(source.get('columns'));
    for (Object each : items(source.get('parameters'))) {
      definition.parameters.add(fieldSpec(each));
    }
    for (Object each : items(source.get('filters'))) {
      String filter = text(each);
      if (filter != null) {
        definition.filters.add(filter);
      }
    }
    return definition;
  }

  /** From a stored blueprint. Elements and columns that are not valid JSON become problems. */
  public static ReformDefinition fromRecord(Reform_Blueprint__c stored) {
    ReformDefinition definition = new ReformDefinition();
    definition.name = text(stored.Api_Name__c);
    definition.objectName = text(stored.Sobject_Name__c);
    definition.label = text(stored.Label__c);
    definition.pluralLabel = text(stored.Label_Plural__c);
    definition.recordType = text(stored.Record_Type_Developer_Name__c);
    definition.namingField = text(stored.Naming_Field__c);
    definition.iconName = text(stored.Icon_Name__c);
    definition.readElements(definition.parsed(stored.Elements__c, 'Elements'));
    definition.readColumns(definition.parsed(stored.Columns__c, 'Columns'));
    return definition;
  }

  /**
   * A sent definition, laid over the stored blueprint it names when there is one. A name with no
   * stored blueprint behind it is just a name.
   */
  public static ReformDefinition resolve(Map<String, Object> sent) {
    ReformDefinition definition = fromMap(sent);
    if (definition.name != null) {
      Reform_Blueprint__c stored = ReformBlueprints.stored(new Set<String>{ definition.name }).get(definition.name.toLowerCase());
      if (stored != null) {
        definition.over(fromRecord(stored));
      }
    }
    return definition;
  }

  /**
   * Lays this definition over another: single values this one leaves blank are taken from the
   * base, and the base's elements, columns, parameters and filters follow this one's.
   */
  public ReformDefinition over(ReformDefinition base) {
    name = name ?? base.name;
    objectName = objectName ?? base.objectName;
    label = label ?? base.label;
    pluralLabel = pluralLabel ?? base.pluralLabel;
    recordType = recordType ?? base.recordType;
    namingField = namingField ?? base.namingField;
    iconName = iconName ?? base.iconName;
    createable = createable ?? base.createable;
    updateable = updateable ?? base.updateable;
    deleteable = deleteable ?? base.deleteable;
    elements.addAll(base.elements);
    columns.addAll(base.columns);
    parameters.addAll(base.parameters);
    filters.addAll(base.filters);
    problems.addAll(base.problems);
    return this;
  }

  private void readElements(Object listed) {
    for (Object each : items(listed)) {
      Map<String, Object> raw = keyed(each);
      Element element = new Element();
      element.width = whole(raw.get('width'));
      element.showWhen = text(raw.get('visible'));
      Integer kinds = 0;
      if (raw.get('field') != null) {
        element.field = fieldSpec(raw.get('field'));
        kinds++;
      }
      if (raw.get('heading') != null) {
        element.heading = content(raw.get('heading'));
        kinds++;
      }
      if (raw.get('richtext') != null) {
        element.richText = content(raw.get('richtext'));
        kinds++;
      }
      element.conflicting = kinds > 1;
      elements.add(element);
    }
  }

  private void readColumns(Object listed) {
    for (Object each : items(listed)) {
      Map<String, Object> raw = keyed(each);
      ColumnSpec column = new ColumnSpec();
      column.name = text(raw.get('name'));
      column.label = text(raw.get('label'));
      columns.add(column);
    }
  }

  // Stored JSON as a list, or null (with a problem recorded) when it is not one.
  private Object parsed(String written, String what) {
    if (String.isBlank(written)) {
      return null;
    }
    try {
      Object value = JSON.deserializeUntyped(written);
      if (value instanceof List<Object>) {
        return value;
      }
      problems.add(what + ' must be a JSON list');
    } catch (JSONException malformed) {
      problems.add(what + ' is not valid JSON: ' + malformed.getMessage());
    }
    return null;
  }

  private static FieldSpec fieldSpec(Object value) {
    Map<String, Object> raw = keyed(value);
    FieldSpec spec = new FieldSpec();
    spec.name = text(raw.get('name'));
    spec.label = text(raw.get('label'));
    spec.required = flag(raw.get('required'));
    spec.hidden = flag(raw.get('hidden'));
    spec.createable = flag(raw.get('createable'));
    spec.updateable = flag(raw.get('updateable'));
    // A fixed or default value may be blank on purpose (fix the field to empty), so only null is "unset".
    spec.fixedValue = raw.get('fixedValue') == null ? null : String.valueOf(raw.get('fixedValue'));
    spec.defaultValue = raw.get('defaultValue') == null ? null : String.valueOf(raw.get('defaultValue'));
    if (raw.get('create') != null) {
      Map<String, Object> create = keyed(raw.get('create'));
      spec.createBlueprint = text(create.get('blueprint')) ?? '';
      spec.createFill = text(create.get('fill'));
    }
    return spec;
  }

  // The text of a heading or rich text, written either as { "content": "..." } or as a plain string.
  private static String content(Object value) {
    if (value instanceof String) {
      return (String) value;
    }
    Object held = keyed(value).get('content');
    return held == null ? '' : String.valueOf(held);
  }

  // Readers that take whatever a component or untyped JSON hands over.

  private static List<Object> items(Object value) {
    return value instanceof List<Object> ? (List<Object>) value : new List<Object>();
  }

  /** A map from a component or untyped JSON, whichever kind of map it arrived as. */
  public static Map<String, Object> keyed(Object value) {
    Map<String, Object> byName = new Map<String, Object>();
    if (value instanceof Map<String, Object>) {
      byName = (Map<String, Object>) value;
    } else if (value instanceof Map<Object, Object>) {
      Map<Object, Object> loose = (Map<Object, Object>) value;
      for (Object key : loose.keySet()) {
        byName.put(String.valueOf(key), loose.get(key));
      }
    }
    return byName;
  }

  private static String text(Object value) {
    String written = value == null ? null : String.valueOf(value).trim();
    return String.isBlank(written) ? null : written;
  }

  private static Boolean flag(Object value) {
    if (value instanceof Boolean) {
      return (Boolean) value;
    }
    String written = text(value);
    return written == null ? null : written.equalsIgnoreCase('true');
  }

  private static Integer whole(Object value) {
    String written = text(value);
    try {
      return written == null ? null : Decimal.valueOf(written).intValue();
    } catch (TypeException notANumber) {
      return null;
    }
  }
}
