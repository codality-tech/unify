/**
 * One object in a copy: which records of it are copied, and how each copy differs from its
 * original. A step with no parent starts a plan, which is called by that step's name; the steps
 * beneath it say which related records come along.
 *
 * A step is plain data, held as API names. It comes from a Clone_Step__mdt record or is built in
 * code; ClonePlan resolves the names and says what is wrong with them.
 *
 *   new CloneStep('Deal').copying(Opportunity.SObjectType).suffixed(' (copy)').setting('StageName = \'Prospecting\'');
 *   new CloneStep('Deal_Roles').under('Deal', OpportunityContactRole.OpportunityId);
 */
public class CloneStep {
  public String name;
  public String parentStep;
  public String objectName;
  public String lookupField;
  public String filter;
  public String leaveOut;
  public String values;
  public String nameSuffix;
  public Boolean active = true;

  public CloneStep(String name) {
    this.name = name;
  }

  public static CloneStep fromMetadata(Clone_Step__mdt stored) {
    CloneStep step = new CloneStep(stored.DeveloperName);
    step.parentStep = stored.Parent_Step__c;
    step.objectName = stored.Object__c;
    step.lookupField = stored.Lookup_Field__c;
    step.filter = stored.Filter__c;
    step.leaveOut = stored.Leave_Out__c;
    step.values = stored.Set_Values__c;
    step.nameSuffix = stored.Name_Suffix__c;
    step.active = stored.Active__c == true;
    return step;
  }

  /** Whether a plan starts here. */
  public Boolean startsAPlan() {
    return String.isBlank(parentStep);
  }

  // Building a step in code

  /** The step that starts a plan: records of this object are what gets copied. */
  public CloneStep copying(SObjectType copied) {
    objectName = String.valueOf(copied);
    return this;
  }

  /** A step beneath another: the records whose lookup points at a record that step copies. */
  public CloneStep under(String parentStepName, SObjectField lookup) {
    DescribeFieldResult shape = lookup.getDescribe();
    parentStep = parentStepName;
    objectName = String.valueOf(shape.getSObjectType());
    lookupField = shape.getName();
    return this;
  }

  /** Which records are copied, written like a SOQL WHERE clause. */
  public CloneStep matching(String whereText) {
    filter = whereText;
    return this;
  }

  /** Fields the copy does not take from its original. */
  public CloneStep leavingOut(Set<SObjectField> skipped) {
    List<String> names = new List<String>();
    for (SObjectField field : skipped) {
      names.add(field.getDescribe().getName());
    }
    leaveOut = String.join(names, ', ');
    return this;
  }

  /** Values every copy is given, written as a condition the copy must meet: Rating = 'Cold' AND NumberOfEmployees = 0 */
  public CloneStep setting(String conditionText) {
    values = conditionText;
    return this;
  }

  /** Added after the name of each copy, with a space between. */
  public CloneStep suffixed(String suffix) {
    nameSuffix = suffix;
    return this;
  }
}
