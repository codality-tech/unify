/** A rule built in code, and a rule read from a metadata record. */
@IsTest
private class RollupRuleTest {
  @IsTest
  static void aRuleBuiltInCodeHoldsApiNames() {
    RollupRule rule = new RollupRule('Open_Amount')
      .children(Rollup_Sample_Child__c.Parent__c)
      .sum(Rollup_Sample_Child__c.Amount__c)
      .matching('Status__c != \'Closed\'')
      .writeTo(Rollup_Sample_Parent__c.Open_Amount__c)
      .queued()
      .guardingDelete();

    Assert.areEqual('Open_Amount', rule.name);
    Assert.areEqual('Rollup_Sample_Child__c', rule.childObject);
    Assert.areEqual('Parent__c', rule.lookupField);
    Assert.areEqual(inj.Enums.Aggregate.SUM, rule.operation);
    Assert.areEqual('Amount__c', rule.sourceField);
    Assert.areEqual('Status__c != \'Closed\'', rule.filter);
    Assert.areEqual('Open_Amount__c', rule.parentField);
    Assert.areEqual(RollupRule.Timing.QUEUED, rule.runs);
    Assert.isTrue(rule.guardsDelete);
    Assert.isTrue(rule.active);
  }

  @IsTest
  static void everyOperationHasABuilder() {
    RollupRule rule = new RollupRule('Any');
    SObjectField amount = Rollup_Sample_Child__c.Amount__c;

    Assert.areEqual(inj.Enums.Aggregate.COUNT, rule.count().operation);
    Assert.isNull(rule.sourceField, 'a plain count reads no field');
    Assert.areEqual('Amount__c', rule.count(amount).sourceField);
    Assert.areEqual(inj.Enums.Aggregate.COUNT_DISTINCT, rule.countDistinct(amount).operation);
    Assert.areEqual(inj.Enums.Aggregate.AVG, rule.avg(amount).operation);
    Assert.areEqual(inj.Enums.Aggregate.MIN, rule.min(amount).operation);
    Assert.areEqual(inj.Enums.Aggregate.MAX, rule.max(amount).operation);
    Assert.areEqual(RollupRule.Timing.IMMEDIATE, rule.runs, 'immediate unless queued');
    Assert.isFalse(rule.guardsDelete);
  }

  @IsTest
  static void aMetadataRecordBecomesARule() {
    RollupRule rule = RollupRule.fromMetadata(
      new Rollup_Rule__mdt(
        DeveloperName = 'Stored',
        Child_Object__c = 'Opportunity',
        Lookup_Field__c = 'AccountId',
        Parent_Field__c = 'AnnualRevenue',
        Operation__c = 'SUM',
        Source_Field__c = 'Amount',
        Filter__c = 'IsWon = TRUE',
        Timing__c = 'QUEUED',
        Active__c = true,
        Guard_Parent_Delete__c = true
      )
    );

    Assert.areEqual('Stored', rule.name);
    Assert.areEqual('Opportunity', rule.childObject);
    Assert.areEqual('AccountId', rule.lookupField);
    Assert.areEqual('AnnualRevenue', rule.parentField);
    Assert.areEqual(inj.Enums.Aggregate.SUM, rule.operation);
    Assert.areEqual('Amount', rule.sourceField);
    Assert.areEqual('IsWon = TRUE', rule.filter);
    Assert.areEqual(RollupRule.Timing.QUEUED, rule.runs);
    Assert.isTrue(rule.active);
    Assert.isTrue(rule.guardsDelete);
    Assert.isTrue(RollupPlan.compile(rule).isSound(), String.join(RollupPlan.compile(rule).problems, '; '));
  }

  @IsTest
  static void aRecordThatLeavesThingsOutGetsTheDefaults() {
    RollupRule rule = RollupRule.fromMetadata(new Rollup_Rule__mdt(DeveloperName = 'Bare'));

    Assert.isNull(rule.operation, 'left for the plan to report');
    Assert.areEqual(RollupRule.Timing.IMMEDIATE, rule.runs);
    Assert.isFalse(rule.active);
    Assert.isFalse(rule.guardsDelete);
  }
}
