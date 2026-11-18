/**
 * The trigger switch an administrator can assign: a user holding the custom permission
 * Bypass_Triggers saves records without the triggers running; any other user does not.
 *
 * The rollup sample is the witness. Its child trigger keeps Child_Count__c on the parent, so the
 * count says whether the trigger ran.
 */
@IsTest
private class BypassTriggersTest {
  private static Integer made = 0;

  // A user on the Minimum Access profile who can work with the rollup sample, with or without the bypass.
  private static User loader(Boolean withBypass) {
    User loader = new User(
      ProfileId = [SELECT Id FROM Profile WHERE Name = 'Minimum Access - Salesforce'].Id,
      LastName = 'Loader',
      Alias = 'loader',
      Email = 'loader@bypass.example.com',
      Username = 'loader' + (made++) + '.' + UserInfo.getOrganizationId() + '.' + System.now().getTime() + '@bypass.example.com',
      TimeZoneSidKey = 'GMT',
      LocaleSidKey = 'en_US',
      EmailEncodingKey = 'UTF-8',
      LanguageLocaleKey = 'en_US'
    );
    Set<String> permissionSets = new Set<String>{ 'Rollup_Sample' };
    if (withBypass) {
      permissionSets.add('Bypass_Triggers');
    }
    // Users and assignments are setup objects: saved as another "user" so the test can save records afterwards.
    System.runAs(new User(Id = UserInfo.getUserId())) {
      insert loader;
      List<PermissionSetAssignment> assignments = new List<PermissionSetAssignment>();
      for (PermissionSet granted : [SELECT Id FROM PermissionSet WHERE Name IN :permissionSets AND NamespacePrefix = NULL]) {
        assignments.add(new PermissionSetAssignment(AssigneeId = loader.Id, PermissionSetId = granted.Id));
      }
      Assert.areEqual(permissionSets.size(), assignments.size(), 'the permission sets are in the org');
      insert assignments;
    }
    return loader;
  }

  // Saves a parent with one child as the user, and returns the parent's count as the rollup left it.
  private static Decimal childCountAfterSavingAs(User who) {
    Id parentId;
    System.runAs(who) {
      Rollup_Sample_Parent__c parent = new Rollup_Sample_Parent__c(Name = 'North');
      insert parent;
      insert new Rollup_Sample_Child__c(Name = 'First', Parent__c = parent.Id, Amount__c = 10);
      parentId = parent.Id;
    }
    return [SELECT Child_Count__c FROM Rollup_Sample_Parent__c WHERE Id = :parentId].Child_Count__c;
  }

  @IsTest
  static void aUserWithoutThePermissionFiresTheTriggers() {
    User plain = loader(false);

    System.runAs(plain) {
      Assert.isFalse(new BypassTriggers().bypasses(Rollup_Sample_Child__c.SObjectType, TriggerOperation.AFTER_INSERT));
    }
    Assert.areEqual(1, childCountAfterSavingAs(plain), 'the child trigger rolled the count up');
  }

  @IsTest
  static void aUserWithThePermissionSavesWithoutThem() {
    User integration = loader(true);

    System.runAs(integration) {
      Assert.isTrue(new BypassTriggers().bypasses(Rollup_Sample_Child__c.SObjectType, TriggerOperation.AFTER_INSERT));
    }
    Decimal counted = childCountAfterSavingAs(integration);
    Assert.isTrue(counted == null || counted == 0, 'the child trigger did not run, so nothing was rolled up: ' + counted);
  }

  @IsTest
  static void thePermissionIsReadEachTimeSoItFollowsTheRunningUser() {
    User integration = loader(true);
    User plain = loader(false);

    // Same transaction, same application: the answer changes with the user.
    Decimal skipped = childCountAfterSavingAs(integration);
    Decimal counted = childCountAfterSavingAs(plain);

    Assert.isTrue(skipped == null || skipped == 0, 'skipped for the integration user: ' + skipped);
    Assert.areEqual(1, counted, 'and run for the next user');
  }
}
