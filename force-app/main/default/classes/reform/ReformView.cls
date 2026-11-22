/**
 * What the server hands a component: a form or a table, ready to draw. Plain data, so it crosses to
 * Lightning as it is.
 */
public class ReformView {
  /** One slot of a form. Which members are set depends on the kind. */
  public class Part {
    /** FIELD, HEADING, RICH_TEXT, SPACER or INVALID. */
    @AuraEnabled
    public String kind;
    /** Columns of a twelve-column grid. */
    @AuraEnabled
    public Integer width;
    @AuraEnabled
    public Boolean visible;
    /** Why the blueprint's element could not be used; empty when it could. */
    @AuraEnabled
    public List<String> problems;

    // Field parts
    @AuraEnabled
    public String dataType;
    @AuraEnabled
    public Boolean required;
    @AuraEnabled
    public String label;
    @AuraEnabled
    public String helpText;
    @AuraEnabled
    public String name;
    /** The running user may see the field but not write it. */
    @AuraEnabled
    public Boolean readOnly;
    /** A rule or merge field reads this field: ask for the form again when it changes. */
    @AuraEnabled
    public Boolean reactive;
    @AuraEnabled
    public Object value;
    /** For a picklist: the active values to choose from. */
    @AuraEnabled
    public List<Choice> options;
    /** For a lookup: the API name of the object it points at (the first, when it can point at several). */
    @AuraEnabled
    public String lookupTo;
    /**
     * For a lookup that can make its record instead: the stored blueprint of that record, and what
     * to call the offer ("New Person"). The record is sent with this form's values under the
     * lookup's name, as { "create": { ...its values } }, and saved with this record.
     */
    @AuraEnabled
    public String createBlueprint;
    @AuraEnabled
    public String createLabel;

    /** Heading or rich text, with its merge fields filled in. */
    @AuraEnabled
    public String content;
  }

  public class Choice {
    @AuraEnabled
    public String value;
    @AuraEnabled
    public String label;
  }

  public class Form {
    @AuraEnabled
    public String objectName;
    @AuraEnabled
    public String label;
    @AuraEnabled
    public Id recordId;
    @AuraEnabled
    public Id recordTypeId;
    /** True when this view follows a save. */
    @AuraEnabled
    public Boolean saved;
    @AuraEnabled
    public List<Part> parts;
    @AuraEnabled
    public List<String> problems;
  }

  public class Column {
    @AuraEnabled
    public String label;
    @AuraEnabled
    public List<String> problems;
    /** The path, as SOQL writes it: Account.Owner.Name. Also the key of the column's cell in a row. */
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String dataType;
  }

  public class Table {
    @AuraEnabled
    public String label;
    @AuraEnabled
    public String objectName;
    @AuraEnabled
    public List<Column> columns;
    @AuraEnabled
    public String pluralLabel;
    /** One map per record: Id, plus a value for each usable column under the column's name. */
    @AuraEnabled
    public List<Map<String, Object>> rows;
    /** How many records match, across all pages. */
    @AuraEnabled
    public Integer total;
    /** What the blueprint and the user's permissions allow here, so a component can offer only that. */
    @AuraEnabled
    public Boolean canCreate;
    @AuraEnabled
    public Boolean canEdit;
    @AuraEnabled
    public Boolean canDelete;
    @AuraEnabled
    public Integer pageSize;
    @AuraEnabled
    public Integer skip;
    @AuraEnabled
    public List<String> problems;
  }
}
