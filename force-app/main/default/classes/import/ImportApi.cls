/**
 * The entry points the import component calls: the formats there are to choose from, and a run of
 * one of them over some CSV text.
 */
public with sharing class ImportApi {
  public class Format {
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String label;
    /** What the format does, in a sentence: "Creates or updates Contacts, matched on Email". */
    @AuraEnabled
    public String summary;
    /** The headers a file of this format has. Empty when the format reads whatever the file has. */
    @AuraEnabled
    public List<String> headers;
    @AuraEnabled
    public Boolean allOrNothing;
  }

  /** The formats that can run, in name order. */
  @AuraEnabled(cacheable=true)
  public static List<Format> formats() {
    List<Format> offered = new List<Format>();
    for (ImportPlan plan : ImportFormats.runnable()) {
      Format each = new Format();
      each.name = plan.format.name;
      each.label = plan.format.label;
      each.summary = plan.summary();
      each.headers = plan.headers();
      each.allOrNothing = plan.format.allOrNothing;
      offered.add(each);
    }
    return offered;
  }

  /**
   * Runs a format over CSV text: a whole file, or a part of one with the header row repeated and
   * `rowsBefore` saying how many rows the earlier parts held. With `save` false nothing is saved.
   */
  @AuraEnabled
  public static ImportResult run(String format, String text, Integer rowsBefore, Boolean save) {
    try {
      return Importer.run(format, text, rowsBefore, save);
    } catch (Exception failed) {
      AuraHandledException shown = new AuraHandledException(failed.getMessage());
      shown.setMessage(failed.getMessage());
      throw shown;
    }
  }
}
