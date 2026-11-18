/**
 * What an import did, or for a check, what it would do.
 *
 * `created` and `updated` count the rows that were saved. After a check nothing is saved, and they
 * count the rows that got as far as being ready to save: a check cannot see what validation rules,
 * triggers and duplicate rules would say.
 */
public class ImportResult {
  public class Failure {
    @AuraEnabled
    public Integer row;
    @AuraEnabled
    public String message;

    public Failure(Integer row, String message) {
      this.row = row;
      this.message = message;
    }
  }

  @AuraEnabled
  public String format;
  /** False for a check, and for an all-or-nothing format when a row failed. */
  @AuraEnabled
  public Boolean saved = false;
  /** The rows read, blank ones not counted. */
  @AuraEnabled
  public Integer rows = 0;
  @AuraEnabled
  public Integer created = 0;
  @AuraEnabled
  public Integer updated = 0;
  @AuraEnabled
  public Integer failed = 0;
  /** Rows with nothing wrong that were not saved, because another row failed and the format is all or nothing. */
  @AuraEnabled
  public Integer held = 0;
  /** How each column was read: "Company fills Account, matched by Account Name". */
  @AuraEnabled
  public List<String> columns = new List<String>();
  /** The file's columns that were not read. */
  @AuraEnabled
  public List<String> ignored = new List<String>();
  @AuraEnabled
  public List<String> notes = new List<String>();
  @AuraEnabled
  public List<Failure> failures = new List<Failure>();
  /** The rows that failed as CSV text: the file's own columns and one more, Error. Null when none failed. */
  @AuraEnabled
  public String failuresCsv;

  /** The Id of the record each saved row made or changed, by the row's number in the file. */
  public Map<Integer, Id> idsByRow = new Map<Integer, Id>();
}
