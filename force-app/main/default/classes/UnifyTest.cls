/** The package's application: one instance, with the package's own classes registered. */
@IsTest
private class UnifyTest {
  @IsTest
  static void theSolutionsShareOneApplication() {
    Assert.isNotNull(Unify.s);
    Assert.isTrue(Unify.s === Unify.s, 'made once');
  }

  @IsTest
  static void storedBlueprintsHaveTheirQueryAndDomainClasses() {
    Assert.isInstanceOfType(Unify.s.qf().make(Reform_Blueprint__c.SObjectType), ReformBlueprintQuery.class);
    Assert.isInstanceOfType(Unify.s.df().make(Reform_Blueprint__c.SObjectType), ReformBlueprints.class);
  }

  @IsTest
  static void theSampleObjectsAreWiredToTheRollupHandler() {
    Assert.isInstanceOfType(Unify.s.tf().make(Rollup_Sample_Child__c.SObjectType), RollupHandler.class);
    Assert.isInstanceOfType(Unify.s.tf().make(Rollup_Sample_Parent__c.SObjectType), RollupHandler.class);
  }
}
