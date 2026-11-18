/**
 * A kind of file that can be imported: which object its rows become, whether they create records,
 * change them or both, and which column fills which field.
 *
 * A format is plain data, held as API names. It comes from an Import_Format__mdt record with its
 * Import_Column__mdt records, or is built in code; ImportPlan resolves the names and says what is
 * wrong with them.
 *
 *   new ImportFormat('Contacts')
 *     .into(Contact.SObjectType)
 *     .creatingOrChanging(Contact.Email)
 *     .column('Email', Contact.Email)
 *     .column('Surname', Contact.LastName).required()
 *     .column('Company', Contact.AccountId, Account.Name)
 *     .constant(Contact.LeadSource, 'Import');
 *
 * A format with no columns reads whatever the file has: a header that is a field's API name or its
 * label fills that field, and a header like Account.Name fills a lookup by matching the related
 * record on that field.
 */
public class ImportFormat {
  /** What a row may do: make a new record, change one that exists, or whichever applies. */
  public enum Writes {
    CREATE,
    CHANGE,
    BOTH
  }

  public class Column {
    public String header;
    public String fieldName;
    public String relatedField;
    public String fallback;
    public Boolean required = false;
  }

  public String name;
  public String label;
  public String objectName;
  public Writes mode = Writes.CREATE;
  public String matchField;
  public Boolean allOrNothing = false;
  public Boolean active = true;
  public List<Column> columns = new List<Column>();

  public ImportFormat(String name) {
    this.name = name;
    this.label = name;
  }

  public static ImportFormat fromMetadata(Import_Format__mdt stored, List<Import_Column__mdt> itsColumns) {
    ImportFormat format = new ImportFormat(stored.DeveloperName);
    format.label = stored.MasterLabel;
    format.objectName = stored.Object__c;
    format.mode = writesNamed(stored.Operation__c);
    format.matchField = stored.Match_Field__c;
    format.allOrNothing = stored.All_Or_Nothing__c == true;
    format.active = stored.Active__c == true;
    for (Import_Column__mdt each : itsColumns) {
      Column made = new Column();
      made.header = each.Header__c;
      made.fieldName = each.Field__c;
      made.relatedField = each.Match_Related_By__c;
      made.fallback = each.Default__c;
      made.required = each.Required__c == true;
      format.columns.add(made);
    }
    return format;
  }

  // A stored value that names no operation is left null, for ImportPlan to report.
  private static Writes writesNamed(String stored) {
    for (Writes known : Writes.values()) {
      if (known.name() == stored) {
        return known;
      }
    }
    return null;
  }

  // Building a format in code

  public ImportFormat into(SObjectType target) {
    objectName = String.valueOf(target);
    return this;
  }

  /** Every row makes a new record. This is where a format starts. */
  public ImportFormat creating() {
    mode = Writes.CREATE;
    matchField = null;
    return this;
  }

  /** Every row changes the record that holds the row's value in this field. */
  public ImportFormat changing(SObjectField matchedOn) {
    mode = Writes.CHANGE;
    matchField = matchedOn.getDescribe().getName();
    return this;
  }

  /** A row changes the record that holds its value in this field, and makes one when there is none. */
  public ImportFormat creatingOrChanging(SObjectField matchedOn) {
    mode = Writes.BOTH;
    matchField = matchedOn.getDescribe().getName();
    return this;
  }

  /** One row that cannot be saved stops the whole file. */
  public ImportFormat allOrNothing() {
    allOrNothing = true;
    return this;
  }

  public ImportFormat column(String header, SObjectField field) {
    Column made = new Column();
    made.header = header;
    made.fieldName = field.getDescribe().getName();
    columns.add(made);
    return this;
  }

  /** A column that fills a lookup: its cell is matched against this field of the related object. */
  public ImportFormat column(String header, SObjectField lookup, SObjectField relatedBy) {
    column(header, lookup);
    columns[columns.size() - 1].relatedField = relatedBy.getDescribe().getName();
    return this;
  }

  /** A value every row is given, with no column in the file. */
  public ImportFormat constant(SObjectField field, String value) {
    column(null, field);
    columns[columns.size() - 1].fallback = value;
    return this;
  }

  /** The column just added must have a value in every row. */
  public ImportFormat required() {
    columns[columns.size() - 1].required = true;
    return this;
  }

  /** The column just added takes this value where its cell is empty. */
  public ImportFormat otherwise(String value) {
    columns[columns.size() - 1].fallback = value;
    return this;
  }
}
