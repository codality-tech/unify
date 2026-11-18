/**
 * Stored blueprints. A blueprint is checked when it is saved: its object, fields, rules, merge
 * fields and columns must all resolve, so a mistake is caught by the admin who made it and not by
 * the user who opens the form.
 */
global class ReformBlueprints extends inj.BaseDomain {
  global ReformBlueprints() {
    super();
  }

  public ReformBlueprints(List<Reform_Blueprint__c> records) {
    super(App.s.model(Reform_Blueprint__c.SObjectType), records);
  }

  /** The stored blueprints with these API names, keyed by API name in lower case. */
  public static Map<String, Reform_Blueprint__c> stored(Set<String> apiNames) {
    ReformBlueprintQuery wanted = ((ReformBlueprintQuery) App.s.qf().make(Reform_Blueprint__c.SObjectType)).named(apiNames);
    Map<String, Reform_Blueprint__c> byName = new Map<String, Reform_Blueprint__c>();
    for (SObject row : wanted.base().run()) {
      Reform_Blueprint__c blueprint = (Reform_Blueprint__c) row;
      byName.put(blueprint.Api_Name__c.toLowerCase(), blueprint);
    }
    return byName;
  }

  /** What is wrong with each blueprint, by position; a blueprint with nothing wrong has no entry. */
  public Map<Integer, List<String>> problems() {
    Map<Integer, List<String>> found = new Map<Integer, List<String>>();
    List<SObject> rows = base().records();
    for (Integer at = 0; at < rows.size(); at++) {
      List<String> wrong = problemsOf((Reform_Blueprint__c) rows[at]);
      if (!wrong.isEmpty()) {
        found.put(at, wrong);
      }
    }
    return found;
  }

  // Only blueprints whose definition changed are checked again; on insert that is all of them.
  public override void onBeforeUpsert(Map<Id, SObject> oldMap) {
    Set<SObjectField> defining = new Set<SObjectField>{
      Reform_Blueprint__c.Sobject_Name__c,
      Reform_Blueprint__c.Record_Type_Developer_Name__c,
      Reform_Blueprint__c.Naming_Field__c,
      Reform_Blueprint__c.Elements__c,
      Reform_Blueprint__c.Columns__c
    };
    for (SObject changed : base().getChangedRecords(oldMap, defining)) {
      List<String> wrong = problemsOf((Reform_Blueprint__c) changed);
      if (!wrong.isEmpty()) {
        changed.addError(String.join(wrong, '; '));
      }
    }
  }

  private static List<String> problemsOf(Reform_Blueprint__c blueprint) {
    return ReformPlan.compile(ReformDefinition.fromRecord(blueprint)).allProblems();
  }
}
