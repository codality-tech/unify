/**
 * Copies made through real saves. The plans are given by each test, apart from the last, which
 * runs the sample plan stored in the org.
 */
@IsTest
private class ClonerTest {
  // An account, its contacts, its opportunities, and the contact roles of those opportunities.
  private static List<CloneStep> accountPlan() {
    return new List<CloneStep>{
      new CloneStep('Firm').copying(Account.SObjectType).suffixed(' (copy)'),
      new CloneStep('People').under('Firm', Contact.AccountId),
      new CloneStep('Deals').under('Firm', Opportunity.AccountId),
      new CloneStep('Roles').under('Deals', OpportunityContactRole.OpportunityId)
    };
  }

  private static Account firmWithEverything(String name) {
    Account firm = new Account(Name = name, Industry = 'Energy', AnnualRevenue = 5000);
    insert firm;
    List<Contact> people = new List<Contact>{
      new Contact(FirstName = name, LastName = 'Ada', AccountId = firm.Id, Email = 'ada@' + name + '.example.com'),
      new Contact(FirstName = name, LastName = 'Ben', AccountId = firm.Id)
    };
    insert people;
    Opportunity deal = new Opportunity(Name = name + ' deal', AccountId = firm.Id, StageName = 'Prospecting', CloseDate = Date.newInstance(2030, 1, 15), Amount = 100);
    insert deal;
    insert new OpportunityContactRole(OpportunityId = deal.Id, ContactId = people[0].Id, Role = 'Decision Maker');
    return firm;
  }

  private static String refusal(String planName, Id recordId) {
    try {
      Cloner.copy(planName, recordId);
    } catch (Cloner.CloneException refused) {
      return refused.getMessage();
    }
    return null;
  }

  @IsTest
  static void aRecordIsCopiedWithWhatIsBeneathIt() {
    ClonePlans.use(accountPlan());
    Account firm = firmWithEverything('Acme');

    Id copyId = Cloner.copy('Firm', firm.Id);

    Account copy = [
      SELECT
        Name,
        Industry,
        AnnualRevenue,
        (SELECT LastName, Email FROM Contacts ORDER BY LastName),
        (SELECT Name, StageName, CloseDate, Amount FROM Opportunities)
      FROM Account
      WHERE Id = :copyId
    ];
    Assert.areNotEqual(firm.Id, copyId);
    Assert.areEqual('Acme (copy)', copy.Name);
    Assert.areEqual('Energy', copy.Industry);
    Assert.areEqual(5000, copy.AnnualRevenue);
    Assert.areEqual(2, copy.Contacts.size());
    Assert.areEqual('ada@acme.example.com', copy.Contacts[0].Email, 'a duplicate rule that only warns does not stop a copy');
    Assert.areEqual(1, copy.Opportunities.size());
    Assert.areEqual('Acme deal', copy.Opportunities[0].Name, 'only the step with a suffix adds one');
    Assert.areEqual(Date.newInstance(2030, 1, 15), copy.Opportunities[0].CloseDate);

    OpportunityContactRole role = [SELECT Role, Contact.AccountId FROM OpportunityContactRole WHERE OpportunityId = :copy.Opportunities[0].Id];
    Assert.areEqual('Decision Maker', role.Role, 'a grandchild follows its own parent\'s copy');
    Assert.areEqual(firm.Id, role.Contact.AccountId, 'a lookup that is not the step\'s own still points where the original did');

    Assert.areEqual(2, [SELECT COUNT() FROM Account], 'the original is untouched');
    Assert.areEqual(4, [SELECT COUNT() FROM Contact]);
    Assert.areEqual(2, [SELECT COUNT() FROM Contact WHERE AccountId = :firm.Id]);
  }

  @IsTest
  static void aStepFiltersLeavesOutAndSetsValues() {
    ClonePlans.use(
      new List<CloneStep>{
        new CloneStep('Firm')
          .copying(Account.SObjectType)
          .leavingOut(new Set<SObjectField>{ Account.AnnualRevenue })
          .setting('Rating = \'Cold\' AND NumberOfEmployees = 0 AND Industry = NULL'),
        new CloneStep('People').under('Firm', Contact.AccountId).matching('Email != NULL'),
        new CloneStep('Deals').under('Firm', Opportunity.AccountId).setting('StageName = \'Qualification\' AND CloseDate = 2031-06-30')
      }
    );
    Account firm = firmWithEverything('Acme');

    Id copyId = Cloner.copy('Firm', firm.Id);

    Account copy = [
      SELECT Name, Industry, AnnualRevenue, Rating, NumberOfEmployees, (SELECT LastName FROM Contacts), (SELECT StageName, CloseDate, Amount FROM Opportunities)
      FROM Account
      WHERE Id = :copyId
    ];
    Assert.areEqual('Acme', copy.Name, 'no suffix was asked for');
    Assert.isNull(copy.AnnualRevenue, 'left out');
    Assert.isNull(copy.Industry, 'set to nothing');
    Assert.areEqual('Cold', copy.Rating);
    Assert.areEqual(0, copy.NumberOfEmployees);
    Assert.areEqual(1, copy.Contacts.size(), 'only the contact with an email');
    Assert.areEqual('Ada', copy.Contacts[0].LastName);
    Assert.areEqual('Qualification', copy.Opportunities[0].StageName);
    Assert.areEqual(Date.newInstance(2031, 6, 30), copy.Opportunities[0].CloseDate);
    Assert.areEqual(100, copy.Opportunities[0].Amount);
  }

  @IsTest
  static void manyRecordsCostOneQueryForEachStep() {
    ClonePlans.use(accountPlan());
    Account first = firmWithEverything('Acme');
    Account second = firmWithEverything('Initech');

    Integer queriesBefore = Limits.getQueries();
    Integer savesBefore = Limits.getDmlStatements();
    Map<Id, Id> copies = Cloner.copy('Firm', new Set<Id>{ first.Id, second.Id });

    Assert.areEqual(4, Limits.getQueries() - queriesBefore, 'four steps, four queries, whatever the number of records');
    Assert.areEqual(4, Limits.getDmlStatements() - savesBefore, 'each object is saved once');
    Assert.areEqual(2, copies.size());
    Assert.areEqual('Initech (copy)', [SELECT Name FROM Account WHERE Id = :copies.get(second.Id)].Name);
    Assert.areEqual(2, [SELECT COUNT() FROM Contact WHERE AccountId = :copies.get(first.Id)]);
    Assert.areEqual(4, [SELECT COUNT() FROM OpportunityContactRole]);
  }

  @IsTest
  static void aLongNameMakesRoomForItsSuffix() {
    ClonePlans.use(accountPlan());
    Account firm = new Account(Name = 'N'.repeat(255));
    insert firm;

    String copied = [SELECT Name FROM Account WHERE Id = :Cloner.copy('Firm', firm.Id)].Name;

    Assert.areEqual(255, copied.length());
    Assert.isTrue(copied.endsWith('N (copy)'), copied.right(12));
  }

  @IsTest
  static void aPlanThatIsUnknownOrWrongIsRefused() {
    CloneStep wrong = new CloneStep('Wrong').copying(Account.SObjectType).setting('Rating != \'Cold\'');
    ClonePlans.use(new List<CloneStep>{ wrong, new CloneStep('People').under('Wrong', Contact.AccountId) });
    Account firm = new Account(Name = 'Acme');
    insert firm;

    Assert.areEqual('There is no clone plan named Nowhere', refusal('Nowhere', firm.Id));
    Assert.areEqual('There is no clone plan named People', refusal('People', firm.Id), 'a step beneath another starts no plan');
    Assert.areEqual(
      'Clone plan Wrong cannot run: Step Wrong: values must be fields of Account set with = and joined by AND',
      refusal('Wrong', firm.Id)
    );
    Assert.areEqual(1, [SELECT COUNT() FROM Account], 'nothing was copied');
  }

  @IsTest
  static void aRecordOfAnotherObjectIsRefused() {
    ClonePlans.use(accountPlan());
    Contact stray = new Contact(LastName = 'Stray');
    insert stray;

    Assert.areEqual('That Account does not exist, or you cannot see it', refusal('Firm', stray.Id));
  }

  // The copy is made as the user.

  /** A user on the Minimum Access profile, with the object and field access given. */
  private static User userWith(List<ObjectPermissions> onObjects, List<String> readableFields) {
    User made = new User(
      ProfileId = [SELECT Id FROM Profile WHERE Name = 'Minimum Access - Salesforce'].Id,
      LastName = 'Copier',
      Alias = 'copier',
      Email = 'copier@clone.example.com',
      Username = 'copier.' + UserInfo.getOrganizationId() + '.' + System.now().getTime() + '@clone.example.com',
      TimeZoneSidKey = 'GMT',
      LocaleSidKey = 'en_US',
      EmailEncodingKey = 'UTF-8',
      LanguageLocaleKey = 'en_US'
    );
    // Users and permission sets are setup objects: saved as another "user" so the test can save records afterwards.
    System.runAs(new User(Id = UserInfo.getUserId())) {
      insert made;
      PermissionSet granted = new PermissionSet(Name = 'Cloner_Test', Label = 'Cloner Test');
      insert granted;
      for (ObjectPermissions onObject : onObjects) {
        onObject.ParentId = granted.Id;
      }
      insert onObjects;
      List<FieldPermissions> onFields = new List<FieldPermissions>();
      for (String field : readableFields) {
        onFields.add(
          new FieldPermissions(ParentId = granted.Id, SobjectType = field.substringBefore('.'), Field = field, PermissionsRead = true, PermissionsEdit = true)
        );
      }
      insert onFields;
      insert new PermissionSetAssignment(AssigneeId = made.Id, PermissionSetId = granted.Id);
    }
    return made;
  }

  @IsTest
  static void theCopyHoldsWhatTheUserCanReadAndBelongsToThem() {
    ClonePlans.use(accountPlan());
    // Accounts with their Industry, but not their AnnualRevenue; no contacts or opportunities at all.
    User copier = userWith(
      new List<ObjectPermissions>{ new ObjectPermissions(SobjectType = 'Account', PermissionsRead = true, PermissionsCreate = true, PermissionsEdit = true) },
      new List<String>{ 'Account.Industry' }
    );
    Account firm = firmWithEverything('Acme');
    update new Account(Id = firm.Id, OwnerId = copier.Id);

    Id copyId;
    System.runAs(copier) {
      copyId = Cloner.copy('Firm', firm.Id);
    }

    Account copy = [SELECT Name, Industry, AnnualRevenue, OwnerId, (SELECT Id FROM Contacts), (SELECT Id FROM Opportunities) FROM Account WHERE Id = :copyId];
    Assert.areEqual('Acme (copy)', copy.Name);
    Assert.areEqual('Energy', copy.Industry);
    Assert.isNull(copy.AnnualRevenue, 'a field the user cannot read is not copied');
    Assert.areEqual(copier.Id, copy.OwnerId);
    Assert.isTrue(copy.Contacts.isEmpty(), 'an object the user cannot read contributes nothing');
    Assert.isTrue(copy.Opportunities.isEmpty());
  }

  @IsTest
  static void theOwnerIsWhoeverCopiesNotWhoeverOwnedTheOriginal() {
    ClonePlans.use(accountPlan());
    User other = userWith(new List<ObjectPermissions>{ new ObjectPermissions(SobjectType = 'Account', PermissionsRead = true) }, new List<String>());
    Account firm = new Account(Name = 'Acme', OwnerId = other.Id);
    insert firm;

    Id copyId = Cloner.copy('Firm', firm.Id);

    Assert.areEqual(UserInfo.getUserId(), [SELECT OwnerId FROM Account WHERE Id = :copyId].OwnerId);
  }

  @IsTest
  static void anObjectTheUserMayNotCreateStopsTheCopy() {
    ClonePlans.use(accountPlan());
    User reader = userWith(
      new List<ObjectPermissions>{
        new ObjectPermissions(SobjectType = 'Account', PermissionsRead = true, PermissionsCreate = true),
        new ObjectPermissions(SobjectType = 'Contact', PermissionsRead = true, PermissionsEdit = true)
      },
      new List<String>{ 'Contact.AccountId' }
    );
    Account firm = firmWithEverything('Acme');
    update new Account(Id = firm.Id, OwnerId = reader.Id);

    System.runAs(reader) {
      Assert.areEqual('You cannot create Contacts', refusal('Firm', firm.Id));
    }
    Assert.areEqual(1, [SELECT COUNT() FROM Account], 'nothing was saved, the account included');
  }

  @IsTest
  static void aRecordTheUserCannotSeeOrAnObjectTheyCannotReadIsRefused() {
    ClonePlans.use(new List<CloneStep>{ new CloneStep('Sample').copying(Reform_Private_Sample__c.SObjectType), new CloneStep('Firm').copying(Account.SObjectType) });
    User copier = userWith(
      new List<ObjectPermissions>{ new ObjectPermissions(SobjectType = String.valueOf(Reform_Private_Sample__c.SObjectType), PermissionsRead = true, PermissionsCreate = true) },
      new List<String>()
    );
    // Shared privately: this one belongs to the user running the test.
    Reform_Private_Sample__c theirs = new Reform_Private_Sample__c(Name = 'Theirs');
    insert theirs;
    Account firm = new Account(Name = 'Acme');
    insert firm;

    System.runAs(copier) {
      Assert.areEqual('That Reform Private Sample does not exist, or you cannot see it', refusal('Sample', theirs.Id));
      Assert.areEqual('You cannot read Accounts', refusal('Firm', firm.Id));
    }
  }

  // The plan stored in the org, on the Rollup sample's objects.

  @IsTest
  static void theStoredSamplePlanRunsAndTheRollupsFollow() {
    User copier = new User(
      ProfileId = [SELECT Id FROM Profile WHERE Name = 'Minimum Access - Salesforce'].Id,
      LastName = 'Sampler',
      Alias = 'sampler',
      Email = 'sampler@clone.example.com',
      Username = 'sampler.' + UserInfo.getOrganizationId() + '.' + System.now().getTime() + '@clone.example.com',
      TimeZoneSidKey = 'GMT',
      LocaleSidKey = 'en_US',
      EmailEncodingKey = 'UTF-8',
      LanguageLocaleKey = 'en_US'
    );
    System.runAs(new User(Id = UserInfo.getUserId())) {
      insert copier;
      insert new PermissionSetAssignment(AssigneeId = copier.Id, PermissionSetId = [SELECT Id FROM PermissionSet WHERE Name = 'Rollup_Sample'].Id);
    }
    Rollup_Sample_Parent__c holder = new Rollup_Sample_Parent__c(Name = 'Holder');
    insert holder;
    // The children are shared privately, so they are the copier's own.
    insert new List<Rollup_Sample_Child__c>{
      new Rollup_Sample_Child__c(Name = 'One', Parent__c = holder.Id, Amount__c = 10, Status__c = 'Open', Kind__c = 'a', OwnerId = copier.Id),
      new Rollup_Sample_Child__c(Name = 'Two', Parent__c = holder.Id, Amount__c = 20, Status__c = 'On hold', Kind__c = 'b', OwnerId = copier.Id),
      new Rollup_Sample_Child__c(Name = 'Three', Parent__c = holder.Id, Amount__c = 40, Status__c = 'Closed', Kind__c = 'c', OwnerId = copier.Id)
    };

    Id copyId;
    Test.startTest();
    System.runAs(copier) {
      copyId = Cloner.copy('Sample_Parent_Copy', holder.Id);
    }
    Test.stopTest();

    Rollup_Sample_Parent__c copy = [
      SELECT Name, Child_Count__c, Open_Amount__c, Largest_Amount__c, Kinds__c, (SELECT Name, Status__c, Amount__c FROM Children__r ORDER BY Amount__c)
      FROM Rollup_Sample_Parent__c
      WHERE Id = :copyId
    ];
    Assert.areEqual('Holder (copy)', copy.Name);
    Assert.areEqual(2, copy.Children__r.size(), 'the closed child stays behind');
    Assert.areEqual('Open', copy.Children__r[1].Status__c, 'every copied child starts again as Open');
    Assert.areEqual(2, copy.Child_Count__c, 'the totals were left out of the copy, and the rollup worked them out from the copied children');
    Assert.areEqual(30, copy.Open_Amount__c);
    Assert.areEqual(20, copy.Largest_Amount__c);
    Assert.areEqual(2, copy.Kinds__c, 'the queued rule too, once its job has run');
  }
}
