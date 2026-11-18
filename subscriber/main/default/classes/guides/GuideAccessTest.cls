/**
 * What the guides say about running as the user, about searches and schemes, and about a batch
 * that starts a batch, run as subscriber code. Each test is named for what a guide says; when one
 * fails, either the framework changed or the guide is wrong.
 */
@IsTest
private class GuideAccessTest {
  // The example triggers on Account do work of their own; these tests are not about them.
  private static void quietAccountTriggers() {
    App.s.tf().disable(new List<SObjectType>{ Account.SObjectType });
    App.b.tf().disable();
  }

  /** A user on the Minimum Access profile, given the Account access named through a permission set. */
  private static User userWith(ObjectPermissions onAccount, Map<String, Boolean> editByField) {
    User made = new User(
      ProfileId = [SELECT Id FROM Profile WHERE Name = 'Minimum Access - Salesforce'].Id,
      LastName = 'Restricted',
      Alias = 'gdaccess',
      Email = 'restricted@guides.example.com',
      Username = 'restricted.' + UserInfo.getOrganizationId() + '.' + System.now().getTime() + '@guides.example.com',
      TimeZoneSidKey = 'GMT',
      LocaleSidKey = 'en_US',
      EmailEncodingKey = 'UTF-8',
      LanguageLocaleKey = 'en_US'
    );
    // Users and permission sets are setup objects: saved as another "user" so the test can save records afterwards.
    System.runAs(new User(Id = UserInfo.getUserId())) {
      insert made;
      PermissionSet granted = new PermissionSet(Name = 'Guide_Access_Test', Label = 'Guide Access Test');
      insert granted;
      onAccount.ParentId = granted.Id;
      onAccount.SobjectType = 'Account';
      insert onAccount;
      List<FieldPermissions> fields = new List<FieldPermissions>();
      for (String fieldName : editByField.keySet()) {
        fields.add(
          new FieldPermissions(
            ParentId = granted.Id,
            SobjectType = 'Account',
            Field = 'Account.' + fieldName,
            PermissionsRead = true,
            PermissionsEdit = editByField.get(fieldName)
          )
        );
      }
      insert fields;
      insert new PermissionSetAssignment(AssigneeId = made.Id, PermissionSetId = granted.Id);
    }
    return made;
  }

  private static User editor() {
    return userWith(
      new ObjectPermissions(PermissionsRead = true, PermissionsCreate = true, PermissionsEdit = true),
      new Map<String, Boolean>{ 'Industry' => true, 'Rating' => false }
    );
  }

  private static String refusal(inj.IWork work) {
    try {
      work.apply();
    } catch (Exception refused) {
      return refused.getTypeName() + ': ' + refused.getMessage();
    }
    return null;
  }

  // Work guide: Running as the user

  @IsTest
  static void aWorkSavesInSystemModeUnlessAskedToRunAsTheUser() {
    quietAccountTriggers();
    User editor = editor();
    Account stored = new Account(Name = 'Acme', Rating = 'Hot', OwnerId = editor.Id);
    insert stored;

    System.runAs(editor) {
      // System mode: the user's permissions are not checked.
      Assert.isNull(refusal(App.s.work().track(new Account(Id = stored.Id, Rating = 'Warm'))));

      // User mode: the rows of the guide's table.
      Assert.areEqual(
        'System.TypeException: DML operation DELETE not allowed on Account',
        refusal(App.s.work().withSharing(true).purge(stored))
      );
      String field = refusal(App.s.work().withSharing(true).track(new Account(Id = stored.Id, Rating = 'Cold')));
      Assert.isTrue(field.startsWith('System.DmlException: Operation failed due to fields being inaccessible on Sobject Account'), field);

      // What the user may do goes through.
      Assert.isNull(refusal(App.s.work().withSharing(true).track(new Account(Id = stored.Id, Industry = 'Banking'))));

      // Leaving the field off the record is the way round a refusal.
      Account sent = new Account(Id = stored.Id, Industry = 'Energy', Rating = 'Cold');
      SObject cropped = inj.FieldUtil.crop(sent, new Set<SObjectField>{ Account.Id, Account.Industry });
      Assert.isNull(refusal(App.s.work().withSharing(true).track(cropped)));
    }

    Account after = [SELECT Industry, Rating FROM Account WHERE Id = :stored.Id];
    Assert.areEqual('Energy', after.Industry);
    Assert.areEqual('Warm', after.Rating, 'only the system-mode work changed it');
  }

  @IsTest
  static void aUserWithNoAccessToTheObjectIsRefusedDifferently() {
    quietAccountTriggers();
    Account stored = new Account(Name = 'Acme');
    insert stored;
    User stranger = new User(
      ProfileId = [SELECT Id FROM Profile WHERE Name = 'Minimum Access - Salesforce'].Id,
      LastName = 'Stranger',
      Alias = 'gdnone',
      Email = 'stranger@guides.example.com',
      Username = 'stranger.' + UserInfo.getOrganizationId() + '.' + System.now().getTime() + '@guides.example.com',
      TimeZoneSidKey = 'GMT',
      LocaleSidKey = 'en_US',
      EmailEncodingKey = 'UTF-8',
      LanguageLocaleKey = 'en_US'
    );
    System.runAs(new User(Id = UserInfo.getUserId())) {
      insert stranger;
    }

    System.runAs(stranger) {
      // An upsert is held to the user's permissions like the other statements.
      List<Rollup_Sample_Parent__c> incoming = new List<Rollup_Sample_Parent__c>{ new Rollup_Sample_Parent__c(Name = 'Mine', Code__c = 'M-1') };
      inj.IWork lenient = App.s.work().withSharing(true).track(incoming, Rollup_Sample_Parent__c.Code__c);
      lenient.options().optAllOrNone = false;
      lenient.apply();
      Assert.areEqual('Access to entity \'Rollup_Sample_Parent__c\' denied', lenient.failureOf(incoming[0]).getMessage());
      Assert.isNull(refusal(App.s.work().track(incoming, Rollup_Sample_Parent__c.Code__c)), 'in system mode it goes through');

      List<String> seen = new List<String>{
        'insert ' + refusal(App.s.work().withSharing(true).track(new Account(Name = 'Mine'))),
        'update ' + refusal(App.s.work().withSharing(true).track(new Account(Id = stored.Id, Name = 'Renamed'))),
        'delete ' + refusal(App.s.work().withSharing(true).purge(stored))
      };
      try {
        App.s.model(Account.SObjectType).query().withSharing(true).run();
        seen.add('query ran');
      } catch (Exception refused) {
        seen.add('query ' + refused.getTypeName());
      }
      Assert.areEqual(
        'insert System.SecurityException: Access to entity \'Account\' denied\n' +
          'update System.SecurityException: Access to entity \'Account\' denied\n' +
          'delete System.SecurityException: Access to entity \'Account\' denied\n' +
          'query System.QueryException',
        String.join(seen, '\n')
      );
    }
  }

  @IsTest
  static void withPartialSuccessARefusedRecordIsLeftOutAndListed() {
    quietAccountTriggers();
    User editor = editor();

    System.runAs(editor) {
      inj.IWork partial = App.s.work().withSharing(true);
      partial.options().optAllOrNone = false;
      Account initech = new Account(Name = 'Initech', Rating = 'Hot');
      partial.track(initech);
      Assert.isNull(refusal(partial));
      Assert.areEqual(1, partial.failures().size());
      Assert.isNotNull(partial.failureOf(initech));
    }

    Assert.areEqual(0, [SELECT COUNT() FROM Account]);
  }

  // Query guide: Security

  @IsTest
  static void inUserModeADefaultFieldTheUserCannotReadIsLeftOut() {
    quietAccountTriggers();
    User editor = editor();
    insert new Account(Name = 'Acme', Industry = 'Energy', AnnualRevenue = 5, OwnerId = editor.Id);

    System.runAs(editor) {
      // GuideApp registers a query class for Account whose defaults include AnnualRevenue.
      inj.IQuery asUser = GuideApp.s.qf().make(Account.SObjectType).withSharing(true);
      Assert.areEqual('SELECT Id, Name, Industry FROM Account', asUser.toSoql());
      Assert.areEqual('Energy', ((Account) asUser.fetch()).Industry);

      Assert.areEqual('SELECT Id, Name, Industry, AnnualRevenue FROM Account', GuideApp.s.qf().make(Account.SObjectType).toSoql());

      // A field added by name is kept, and the platform refuses the query.
      inj.IQuery named = GuideApp.s.model(Account.SObjectType).query().withSharing(true);
      named.fields().add(new Set<SObjectField>{ Account.AnnualRevenue });
      try {
        named.run();
        Assert.fail('A field the user cannot read was returned');
      } catch (QueryException refused) {
        Assert.isTrue(refused.getMessage().contains('AnnualRevenue'), refused.getMessage());
      }
    }
  }

  // Query guide: Security. In system mode a query has the sharing of the class that builds it,
  // unless the scheme that runs it declares a sharing keyword of its own.

  // The same count as an aggregate query. This method has no sharing of its own: it takes its caller's.
  private static Object countedBy(inj.IApplication through) {
    inj.IAggregateQuery tally = through.model(Reform_Private_Sample__c.SObjectType).aggregateQuery();
    tally.aggregates().add(through.aggregate(inj.Enums.Aggregate.COUNT, null));
    return tally.run()[0].get('cnt');
  }

  private without sharing class BuiltWithoutSharing {
    private Integer samples(inj.IApplication through) {
      return through.model(Reform_Private_Sample__c.SObjectType).query().count();
    }

    private Object counted(inj.IApplication through) {
      return GuideAccessTest.countedBy(through);
    }
  }

  private with sharing class BuiltWithSharing {
    private Integer samples(inj.IApplication through) {
      return through.model(Reform_Private_Sample__c.SObjectType).query().count();
    }

    private Object counted(inj.IApplication through) {
      return GuideAccessTest.countedBy(through);
    }
  }

  @IsTest
  static void inSystemModeAQueryHasTheSharingOfItsBuilderUnlessTheSchemeSaysOtherwise() {
    User editor = editor();
    System.runAs(new User(Id = UserInfo.getUserId())) {
      insert new ObjectPermissions(
        ParentId = [SELECT Id FROM PermissionSet WHERE Name = 'Guide_Access_Test'].Id,
        SobjectType = 'Reform_Private_Sample__c',
        PermissionsRead = true,
        PermissionsCreate = true
      );
    }
    // Shared privately: this one belongs to the user running the test, and the editor cannot see it.
    insert new Reform_Private_Sample__c(Name = 'Someone else\'s');

    System.runAs(editor) {
      insert new Reform_Private_Sample__c(Name = 'Mine');
      inj.IApplication packageDefault = inj.Application.make();

      // App's scheme has no sharing keyword, and the scheme the package uses when given none
      // inherits: the query has the sharing of the class that builds it.
      Assert.areEqual(2, new BuiltWithoutSharing().samples(App.s));
      Assert.areEqual(1, new BuiltWithSharing().samples(App.s));
      Assert.areEqual(2, new BuiltWithoutSharing().samples(packageDefault));
      Assert.areEqual(1, new BuiltWithSharing().samples(packageDefault));

      // An aggregate query does the same.
      Assert.areEqual(2, new BuiltWithoutSharing().counted(App.s));
      Assert.areEqual(1, new BuiltWithSharing().counted(App.s));

      // A scheme with a keyword of its own settles it. RollupScheme is declared without sharing.
      Assert.areEqual(2, new BuiltWithoutSharing().samples(RollupScheme.app));
      Assert.areEqual(2, new BuiltWithSharing().samples(RollupScheme.app));

      // User mode applies sharing whatever the scheme.
      Assert.areEqual(1, RollupScheme.app.model(Reform_Private_Sample__c.SObjectType).query().withSharing(true).count());
    }
  }

  // Testing guide: Mocking queries with MockScheme; query guide: Searches

  @IsTest
  static void aSearchIsMockedLikeAQuery() {
    List<Account> canned = new List<Account>{ new Account(Name = 'Acme') };
    inj.MockScheme scheme = new inj.MockScheme().returning(Account.SObjectType, canned);
    inj.IApplication app = inj.Application.make(scheme);
    inj.IQuery accounts = app.qf().make(Account.SObjectType);
    inj.IQuery contacts = app.qf().make(Contact.SObjectType);

    List<List<SObject>> found = app.searchQuery(new List<inj.IQuery>{ accounts, contacts }).run('Acme');

    Assert.areEqual(2, found.size());
    Assert.areEqual('Acme', ((Account) found[0][0]).Name);
    Assert.isTrue(found[1].isEmpty());
    Assert.isInstanceOfType(found[1], List<Contact>.class);
    Assert.isTrue(scheme.queries()[0].startsWith('FIND {Acme} RETURNING Account('), scheme.queries()[0]);
    Assert.isTrue(scheme.bindMaps()[0].isEmpty());
  }

  @IsTest
  static void aSchemeThatDoesNotSearchLeavesTheSearchToThePlatform() {
    quietAccountTriggers();
    Account acme = new Account(Name = 'Acme');
    insert acme;
    Test.setFixedSearchResults(new List<Id>{ acme.Id });

    // App's scheme is this repository's own, written before schemes could search.
    inj.IQuery accounts = App.s.model(Account.SObjectType).query();
    List<List<SObject>> found = App.s.searchQuery(new List<inj.IQuery>{ accounts }).run('Acme');

    Assert.areEqual(acme.Id, found[0][0].Id);
  }

  // Async guide: a batch released while another batch is in its execute step

  @IsTest
  static void aBatchStartedInsideABatchRuns() {
    inj.Async.synchronousInTests = true;

    inj.Async.iterable(new GuideExamples.StartsABatch('guide mark')).run();

    Assert.areEqual(1, [SELECT COUNT() FROM Reform_Private_Sample__c WHERE Name = 'guide mark']);
  }

  // Async guide: Shared values

  @IsTest
  static void aSharedValueNobodySetIsNull() {
    inj.IJob job = inj.Async.iterable(new GuideExamples.LeavesAMark('unused'));

    Assert.isNull(job.getShared('never set'));
    Assert.areEqual(3, job.setShared('count', 3).getShared('count'));
  }
}
