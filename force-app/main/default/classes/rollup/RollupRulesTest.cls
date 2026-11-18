/**
 * The registry of rules, and the Rollup_Rule__mdt records this org holds. The first test is the
 * guard for a deployment: a stored rule that cannot run fails it, with the reason.
 */
@IsTest
private class RollupRulesTest {
  private static RollupRule sampleRule(String name) {
    return new RollupRule(name).children(Rollup_Sample_Child__c.Parent__c).count().writeTo(Rollup_Sample_Parent__c.Child_Count__c);
  }

  @IsTest
  static void everyStoredRuleCanRun() {
    Map<String, List<String>> wrong = RollupRules.problems();
    Assert.isTrue(wrong.isEmpty(), 'Rollup rules that cannot run: ' + JSON.serialize(wrong));
  }

  @IsTest
  static void theStoredSampleRulesRun() {
    Rollup_Sample_Parent__c holder = new Rollup_Sample_Parent__c(Name = 'Holder');
    insert holder;
    Date due = Date.newInstance(2030, 1, 15);

    Test.startTest();
    insert new List<Rollup_Sample_Child__c>{
      new Rollup_Sample_Child__c(Parent__c = holder.Id, Amount__c = 10, Status__c = 'Open', Kind__c = 'a', Due__c = due),
      new Rollup_Sample_Child__c(Parent__c = holder.Id, Amount__c = 30, Status__c = 'Closed', Kind__c = 'b', Due__c = due.addDays(-7))
    };
    Test.stopTest();

    Rollup_Sample_Parent__c held = [
      SELECT Child_Count__c, Open_Amount__c, Average_Amount__c, Largest_Amount__c, Earliest_Due__c, Kinds__c
      FROM Rollup_Sample_Parent__c
      WHERE Id = :holder.Id
    ];
    Assert.areEqual(2, held.Child_Count__c);
    Assert.areEqual(10, held.Open_Amount__c, 'the closed child is left out');
    Assert.areEqual(20, held.Average_Amount__c);
    Assert.areEqual(30, held.Largest_Amount__c);
    Assert.areEqual(due, held.Earliest_Due__c, 'the earliest due date among the open children');
    Assert.areEqual(2, held.Kinds__c, 'the queued rule, once its job has run');
  }

  @IsTest
  static void activeRulesAreFoundByNameChildAndParent() {
    RollupRule off = sampleRule('Off');
    off.active = false;
    RollupRules.use(
      new List<RollupRule>{
        sampleRule('Zed'),
        off,
        sampleRule('Alpha'),
        new RollupRule('Contacts').children(Contact.AccountId).count().writeTo(Account.NumberOfEmployees)
      }
    );

    List<String> forChild = new List<String>();
    for (RollupPlan plan : RollupRules.forChild(Rollup_Sample_Child__c.SObjectType)) {
      forChild.add(plan.rule.name);
    }
    Assert.areEqual(new List<String>{ 'Alpha', 'Zed' }, forChild, 'in name order, without the inactive rule');
    Assert.areEqual(1, RollupRules.forParent(Account.SObjectType).size());
    Assert.areEqual(2, RollupRules.forParent(Rollup_Sample_Parent__c.SObjectType).size());
    Assert.isTrue(RollupRules.forChild(Account.SObjectType).isEmpty());
    Assert.areEqual(new List<String>{ 'Account', String.valueOf(Rollup_Sample_Parent__c.SObjectType) }, RollupRules.parentObjects());
    Assert.areEqual('Alpha', RollupRules.named('Alpha').rule.name);
    Assert.isNull(RollupRules.named('Off'), 'an inactive rule is not there at all');
    Assert.isNull(RollupRules.named('Unknown'));
    Assert.isTrue(RollupRules.problems().isEmpty());
  }

  @IsTest
  static void aRuleThatCannotRunIsReportedAndRefusedWhereItIsUsed() {
    RollupRule broken = sampleRule('Broken');
    broken.parentField = 'Nope__c';
    RollupRules.use(new List<RollupRule>{ broken, new RollupRule('Contacts').children(Contact.AccountId).count().writeTo(Account.NumberOfEmployees) });

    Assert.areEqual(new List<String>{ String.valueOf(Rollup_Sample_Parent__c.SObjectType) + ' has no field Nope__c' }, RollupRules.problems().get('Broken'));
    Assert.areEqual(1, RollupRules.problems().size());
    Assert.areEqual(1, RollupRules.forChild(Contact.SObjectType).size(), 'rules of other objects still run');

    String refusal;
    try {
      RollupRules.forChild(Rollup_Sample_Child__c.SObjectType);
    } catch (Rollups.RollupException refused) {
      refusal = refused.getMessage();
    }
    Assert.areEqual('Rollup rule Broken cannot run: ' + String.valueOf(Rollup_Sample_Parent__c.SObjectType) + ' has no field Nope__c', refusal);
  }
}
