/** A step built in code, and a step read from a metadata record. */
@IsTest
private class CloneStepTest {
  @IsTest
  static void aStepThatStartsAPlanNamesItsObject() {
    CloneStep step = new CloneStep('Firm')
      .copying(Account.SObjectType)
      .suffixed(' (copy)')
      .leavingOut(new Set<SObjectField>{ Account.AnnualRevenue })
      .setting('Rating = \'Cold\'');

    Assert.areEqual('Firm', step.name);
    Assert.areEqual('Account', step.objectName);
    Assert.isTrue(step.startsAPlan());
    Assert.isNull(step.lookupField);
    Assert.areEqual(' (copy)', step.nameSuffix);
    Assert.areEqual('AnnualRevenue', step.leaveOut);
    Assert.areEqual('Rating = \'Cold\'', step.values);
    Assert.isTrue(step.active);
  }

  @IsTest
  static void aStepBeneathAnotherTakesItsObjectFromItsLookup() {
    CloneStep step = new CloneStep('People').under('Firm', Contact.AccountId).matching('Email != NULL');

    Assert.areEqual('Firm', step.parentStep);
    Assert.areEqual('Contact', step.objectName);
    Assert.areEqual('AccountId', step.lookupField);
    Assert.areEqual('Email != NULL', step.filter);
    Assert.isFalse(step.startsAPlan());
  }

  @IsTest
  static void aMetadataRecordBecomesAStep() {
    CloneStep step = CloneStep.fromMetadata(
      new Clone_Step__mdt(
        DeveloperName = 'Deal_Roles',
        Parent_Step__c = 'Deal',
        Object__c = 'OpportunityContactRole',
        Lookup_Field__c = 'OpportunityId',
        Filter__c = 'IsPrimary = TRUE',
        Leave_Out__c = 'Role',
        Set_Values__c = 'IsPrimary = FALSE',
        Name_Suffix__c = ' II',
        Active__c = true
      )
    );

    Assert.areEqual('Deal_Roles', step.name);
    Assert.areEqual('Deal', step.parentStep);
    Assert.areEqual('OpportunityContactRole', step.objectName);
    Assert.areEqual('OpportunityId', step.lookupField);
    Assert.areEqual('IsPrimary = TRUE', step.filter);
    Assert.areEqual('Role', step.leaveOut);
    Assert.areEqual('IsPrimary = FALSE', step.values);
    Assert.areEqual(' II', step.nameSuffix);
    Assert.isTrue(step.active);
    Assert.isFalse(CloneStep.fromMetadata(new Clone_Step__mdt(DeveloperName = 'Bare')).active, 'a record that does not say is not active');
  }
}
