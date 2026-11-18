/**
 * Reform and record sharing: records a user cannot see, can see but not change, and can change but
 * not delete. ReformAccessTest covers object and field permissions.
 *
 * Reform_Private_Sample__c is shared privately, so a record belongs to its owner until it is
 * shared. The user here may read, create, edit and delete the object; only sharing stands between
 * them and another person's record.
 */
@IsTest
private class ReformSharingTest {
  private static final String SAMPLES =
    '{"sobjectName":"Reform_Private_Sample__c","elements":[{"field":{"name":"Name"}}],"columns":[{"name":"Name"}]}';

  private static ReformEngine engine() {
    return new ReformEngine(ReformPlan.compile(ReformDefinition.fromMap((Map<String, Object>) JSON.deserializeUntyped(SAMPLES))));
  }

  private static User colleague() {
    User made = new User(
      ProfileId = [SELECT Id FROM Profile WHERE Name = 'Minimum Access - Salesforce'].Id,
      LastName = 'Colleague',
      Alias = 'collg',
      Email = 'colleague@reform.example.com',
      Username = 'colleague.' + UserInfo.getOrganizationId() + '.' + System.now().getTime() + '@reform.example.com',
      TimeZoneSidKey = 'GMT',
      LocaleSidKey = 'en_US',
      EmailEncodingKey = 'UTF-8',
      LanguageLocaleKey = 'en_US'
    );
    // Users and permission sets are setup objects: saved as another "user" so the test can save records afterwards.
    System.runAs(new User(Id = UserInfo.getUserId())) {
      insert made;
      PermissionSet granted = new PermissionSet(Name = 'Reform_Sharing_Test', Label = 'Reform Sharing Test');
      insert granted;
      insert new ObjectPermissions(
        ParentId = granted.Id,
        SobjectType = 'Reform_Private_Sample__c',
        PermissionsRead = true,
        PermissionsCreate = true,
        PermissionsEdit = true,
        PermissionsDelete = true
      );
      insert new PermissionSetAssignment(AssigneeId = made.Id, PermissionSetId = granted.Id);
    }
    return made;
  }

  // A record owned by the user running the test, shared with the colleague at the level given (or not at all).
  private static Reform_Private_Sample__c someoneElses(User colleague, String sharedAs) {
    Reform_Private_Sample__c made = new Reform_Private_Sample__c(Name = 'Theirs');
    insert made;
    if (sharedAs != null) {
      insert new Reform_Private_Sample__Share(ParentId = made.Id, UserOrGroupId = colleague.Id, AccessLevel = sharedAs, RowCause = 'Manual');
    }
    return made;
  }

  private static String nameOf(Id recordId) {
    List<Reform_Private_Sample__c> found = [SELECT Name FROM Reform_Private_Sample__c WHERE Id = :recordId];
    return found.isEmpty() ? null : found[0].Name;
  }

  private static String refusal(ReformEngine engine, String action, Id recordId) {
    try {
      if (action == 'show') {
        engine.form(new Map<String, Object>{ 'Id' => recordId }, false);
      } else if (action == 'save') {
        engine.form(new Map<String, Object>{ 'Id' => recordId, 'Name' => 'Renamed' }, true);
      } else {
        engine.remove(recordId);
      }
    } catch (ReformEngine.ReformException refused) {
      return refused.getMessage();
    }
    return null;
  }

  @IsTest
  static void aRecordTheUserCannotSeeIsNotListedOpenedOrChanged() {
    User colleague = colleague();
    Reform_Private_Sample__c theirs = someoneElses(colleague, null);

    System.runAs(colleague) {
      ReformEngine engine = engine();
      Assert.areEqual(0, engine.table(10, 0).total);
      String unseen = 'That Reform Private Sample does not exist, or you cannot see it';
      Assert.areEqual(unseen, refusal(engine, 'show', theirs.Id));
      Assert.areEqual(unseen, refusal(engine, 'save', theirs.Id));
      Assert.areEqual(unseen, refusal(engine, 'remove', theirs.Id));
    }

    Assert.areEqual('Theirs', nameOf(theirs.Id));
  }

  @IsTest
  static void aRecordSharedForReadingCanBeOpenedButNotChanged() {
    User colleague = colleague();
    Reform_Private_Sample__c theirs = someoneElses(colleague, 'Read');

    System.runAs(colleague) {
      ReformEngine engine = engine();
      ReformView.Table listed = engine.table(10, 0);
      Assert.areEqual(1, listed.total);
      Assert.areEqual('Theirs', listed.rows[0].get('Name'));
      Assert.isNull(refusal(engine, 'show', theirs.Id), 'it opens');
      Assert.areEqual('You cannot edit this Reform Private Sample', refusal(engine, 'save', theirs.Id));
      Assert.areEqual('You cannot delete this Reform Private Sample', refusal(engine, 'remove', theirs.Id));
    }

    Assert.areEqual('Theirs', nameOf(theirs.Id));
  }

  @IsTest
  static void aRecordSharedForEditingCanBeChangedButNotDeleted() {
    User colleague = colleague();
    Reform_Private_Sample__c theirs = someoneElses(colleague, 'Edit');

    System.runAs(colleague) {
      ReformEngine engine = engine();
      Assert.isNull(refusal(engine, 'save', theirs.Id), 'it saves');
      Assert.areEqual('You cannot delete this Reform Private Sample', refusal(engine, 'remove', theirs.Id));
    }

    Assert.areEqual('Renamed', nameOf(theirs.Id));
  }

  @IsTest
  static void theUsersOwnRecordsAreTheirsToChange() {
    User colleague = colleague();
    someoneElses(colleague, null);
    Id mine;

    System.runAs(colleague) {
      ReformEngine engine = engine();
      mine = engine.form(new Map<String, Object>{ 'Name' => 'Mine' }, true).recordId;
      Assert.areEqual(1, engine.table(10, 0).total, 'their own record, and not the other');
      Assert.isNull(refusal(engine, 'save', mine));
      Assert.areEqual('Renamed', nameOf(mine));
      Assert.isNull(refusal(engine, 'remove', mine));
    }

    Assert.isNull(nameOf(mine));
  }

  // Beneath the engine's own checks: what a unit of work does with a record shared for reading only.
  // A work inherits the sharing of the class that calls it, and user mode enforces sharing whoever calls.

  private static String rename(Id recordId, Boolean asUser) {
    try {
      App.s.work().withSharing(asUser).track(new Reform_Private_Sample__c(Id = recordId, Name = 'Forced')).apply();
    } catch (Exception refused) {
      return refused.getTypeName() + ': ' + refused.getMessage().substringAfter('first error: ').substringBefore(',');
    }
    return null;
  }

  private with sharing class Sharing {
    private String rename(Id recordId, Boolean asUser) {
      return ReformSharingTest.rename(recordId, asUser);
    }
  }

  private without sharing class NotSharing {
    private String rename(Id recordId, Boolean asUser) {
      return ReformSharingTest.rename(recordId, asUser);
    }
  }

  @IsTest
  static void theUnitOfWorkRefusesWhatSharingForbids() {
    User colleague = colleague();
    Reform_Private_Sample__c theirs = someoneElses(colleague, 'Read');
    String refused = 'System.DmlException: INSUFFICIENT_ACCESS_ON_CROSS_REFERENCE_ENTITY';

    System.runAs(colleague) {
      Assert.areEqual(refused, new Sharing().rename(theirs.Id, true), 'user mode');
      Assert.areEqual(refused, new Sharing().rename(theirs.Id, false), 'system mode, called with sharing');
      Assert.areEqual(refused, new NotSharing().rename(theirs.Id, true), 'user mode, called without sharing');
      Assert.areEqual('Theirs', nameOf(theirs.Id));

      Assert.isNull(new NotSharing().rename(theirs.Id, false), 'system mode without sharing is the only way through');
    }

    Assert.areEqual('Forced', nameOf(theirs.Id));
  }
}
