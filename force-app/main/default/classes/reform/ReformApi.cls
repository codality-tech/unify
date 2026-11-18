/**
 * The entry points Lightning components call. Each takes a blueprint (a map naming a stored
 * blueprint, carrying its own definition, or both) and answers with a ReformView.
 */
public with sharing class ReformApi {
  /** The form for the values the component holds; with save, the record is written first. */
  @AuraEnabled
  public static ReformView.Form form(Map<String, Object> blueprint, Map<String, Object> values, Boolean save) {
    try {
      return engineFor(blueprint).form(values, save);
    } catch (Exception failed) {
      throw surfaced(failed);
    }
  }

  /** A page of the records the blueprint lists. */
  @AuraEnabled
  public static ReformView.Table table(Map<String, Object> blueprint, Integer pageSize, Integer skip) {
    try {
      return engineFor(blueprint).table(pageSize, skip);
    } catch (Exception failed) {
      throw surfaced(failed);
    }
  }

  /** The same page, cacheable, for a component that wires it. */
  @AuraEnabled(cacheable=true)
  public static ReformView.Table tableWired(Map<String, Object> blueprint, Integer pageSize, Integer skip) {
    return table(blueprint, pageSize, skip);
  }

  @AuraEnabled
  public static void remove(Map<String, Object> blueprint, Id recordId) {
    try {
      engineFor(blueprint).remove(recordId);
    } catch (Exception failed) {
      throw surfaced(failed);
    }
  }

  private static ReformEngine engineFor(Map<String, Object> blueprint) {
    return new ReformEngine(ReformPlan.compile(ReformDefinition.resolve(blueprint)));
  }

  // The message a component should show. A DML failure reads better as its first row's message.
  private static AuraHandledException surfaced(Exception failed) {
    String message = failed.getMessage();
    if (failed instanceof DmlException && ((DmlException) failed).getNumDml() > 0) {
      message = ((DmlException) failed).getDmlMessage(0);
    }
    AuraHandledException shown = new AuraHandledException(message);
    shown.setMessage(message);
    return shown;
  }
}
