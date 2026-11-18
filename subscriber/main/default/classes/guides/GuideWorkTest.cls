/**
 * The work guide's statements, run as subscriber code. Each test is named for what the guide says;
 * when one of these fails, either the framework changed or the guide is wrong.
 */
@IsTest
private class GuideWorkTest {
  // The example triggers on Account do DML of their own, which would blur the statement counts.
  private static void quietAccountTriggers() {
    App.s.tf().disable(new List<SObjectType>{ Account.SObjectType });
    App.b.tf().disable();
  }

  // The sample objects have rollup triggers; these tests count their own statements.
  private static void quietSampleTriggers() {
    Unify.s.tf().disable(new List<SObjectType>{ Rollup_Sample_Parent__c.SObjectType, Rollup_Sample_Child__c.SObjectType });
  }

  private static Reform_Blueprint__c blueprint(String key, String label) {
    return new Reform_Blueprint__c(Name = key, Api_Name__c = key, Sobject_Name__c = 'Account', Label__c = label);
  }

  @IsTest
  static void trackInsertsRecordsWithoutAnIdAndUpdatesThoseWithOne() {
    quietAccountTriggers();
    Account known = new Account(Name = 'Globex');
    insert known;
    Account fresh = new Account(Name = 'Acme');
    known.Rating = 'Hot';

    App.s.work().track(fresh).track(known).apply();

    Assert.isNotNull(fresh.Id);
    Assert.areEqual('Hot', [SELECT Rating FROM Account WHERE Id = :known.Id].Rating);
  }

  @IsTest
  static void nullsAreIgnoredAndAnEmptyWorkDoesNothing() {
    inj.IWork idle = App.s.work();
    idle.track((Account) null).track((List<Account>) null).track(new List<Account>()).purge((Account) null).purge((List<Account>) null);

    Assert.isFalse(idle.hasWork());
    Integer before = Limits.getDmlStatements();
    idle.apply();
    Assert.areEqual(0, Limits.getDmlStatements() - before);
  }

  @IsTest
  static void aWorkIsAppliedOnce() {
    quietAccountTriggers();
    inj.IWork work = App.s.work().track(new Account(Name = 'Once'));
    work.apply();

    try {
      work.apply();
      Assert.fail('the second apply inserts the same record again');
    } catch (DmlException again) {
      Assert.isTrue(again.getMessage().containsIgnoreCase('id'), again.getMessage());
    }
  }

  @IsTest
  static void newChildrenOfNewParentsGoInWithTheirLookupsSet() {
    quietAccountTriggers();
    Account company = new Account(Name = 'Acme');
    Contact person = new Contact(LastName = 'Lovelace');
    Case question = new Case(Subject = 'Where is my order?');

    Integer before = Limits.getDmlStatements();
    App.s.work()
      .track(person, Contact.AccountId, company)
      .track(question, Case.ContactId, person)
      .track(question, Case.AccountId, company)
      .apply();

    Assert.areEqual(3, Limits.getDmlStatements() - before, 'three inserts, no updates');
    Case saved = [SELECT ContactId, AccountId FROM Case WHERE Id = :question.Id];
    Assert.areEqual(person.Id, saved.ContactId);
    Assert.areEqual(company.Id, saved.AccountId);
    Assert.areEqual(company.Id, [SELECT AccountId FROM Contact WHERE Id = :person.Id].AccountId);
  }

  @IsTest
  static void aParentThatAlreadyExistsIsFilledInBeforeTheInsert() {
    quietAccountTriggers();
    Account company = new Account(Name = 'Acme');
    insert company;
    Contact person = new Contact(LastName = 'Hopper');

    Integer before = Limits.getDmlStatements();
    App.s.work().track(person, Contact.AccountId, company).apply();
    Integer used = Limits.getDmlStatements() - before;

    Assert.areEqual(company.Id, [SELECT AccountId FROM Contact WHERE Id = :person.Id].AccountId);
    // The parent is tracked too, so it is updated as well as the child being inserted.
    Assert.areEqual(2, used, 'one insert for the child, one update for the parent it was related to');
  }

  @IsTest
  static void anExistingRecordRelatedToANewParentIsUpdatedAfterTheInsert() {
    quietAccountTriggers();
    Contact person = new Contact(LastName = 'Turing');
    insert person;
    Account company = new Account(Name = 'Bletchley');

    App.s.work().track(person, Contact.AccountId, company).apply();

    Assert.isNotNull(company.Id);
    Assert.areEqual(company.Id, [SELECT AccountId FROM Contact WHERE Id = :person.Id].AccountId);
  }

  @IsTest
  static void newRecordsThatDependOnEachOtherInACircleAreRefused() {
    quietAccountTriggers();
    Account first = new Account(Name = 'First');
    Account second = new Account(Name = 'Second');

    try {
      App.s.work().track(first, Account.ParentId, second).track(second, Account.ParentId, first).apply();
      Assert.fail('neither can go first');
    } catch (Exception circular) {
      Assert.isTrue(circular.getTypeName().endsWith('WorkException'), circular.getTypeName());
    }
    Assert.isNull(first.Id, 'nothing was inserted');
    Assert.areEqual(0, [SELECT COUNT() FROM Account]);
  }

  @IsTest
  static void deletesGoChildrenFirstWhenTheLookupsAreLoaded() {
    quietAccountTriggers();
    Account company = new Account(Name = 'Acme');
    insert company;
    Contact person = new Contact(LastName = 'Lovelace', AccountId = company.Id);
    insert person;
    Case question = new Case(Subject = 'Q', ContactId = person.Id, AccountId = company.Id);
    insert question;

    Integer before = Limits.getDmlStatements();
    App.s.work().purge(company).purge(person).purge(question).apply();

    Assert.areEqual(3, Limits.getDmlStatements() - before, 'one delete per object type');
    Assert.areEqual(0, [SELECT COUNT() FROM Account WHERE Id = :company.Id]);
    Assert.areEqual(0, [SELECT COUNT() FROM Contact WHERE Id = :person.Id]);
    Assert.areEqual(0, [SELECT COUNT() FROM Case WHERE Id = :question.Id]);
  }

  @IsTest
  static void aLookupThatIsNotLoadedDoesNotCountForTheOrder() {
    quietAccountTriggers();
    Account company = new Account(Name = 'Acme');
    insert company;
    Contact person = new Contact(LastName = 'Lovelace', AccountId = company.Id);
    insert person;
    Contact withoutItsLookup = new Contact(Id = person.Id);

    Boolean failed = false;
    try {
      // With no link to go on, the account goes first here and takes its contact with it.
      App.s.work().purge(withoutItsLookup).purge(company).apply();
    } catch (DmlException alreadyGone) {
      failed = true;
    }
    Assert.isTrue(failed, 'the contact was cascade-deleted with its account before its own delete ran');
  }

  @IsTest
  static void setOrderMustNameExactlyTheTypesBeingPurged() {
    quietAccountTriggers();
    List<Account> companies = new List<Account>{ new Account(Name = 'A'), new Account(Name = 'B'), new Account(Name = 'C') };
    insert companies;
    List<Contact> people = new List<Contact>();
    for (Account each : companies) {
      people.add(new Contact(LastName = each.Name, AccountId = each.Id));
    }
    insert people;

    App.s.work()
      .setOrder(new List<SObjectType>{ Contact.SObjectType, Account.SObjectType })
      .purge(companies[0])
      .purge(people[0])
      .apply();
    Assert.areEqual(2, [SELECT COUNT() FROM Account]);

    List<List<SObjectType>> wrongOrders = new List<List<SObjectType>>{
      new List<SObjectType>{ Account.SObjectType },
      new List<SObjectType>{ Case.SObjectType, Contact.SObjectType, Account.SObjectType }
    };
    for (List<SObjectType> wrong : wrongOrders) {
      try {
        App.s.work().setOrder(wrong).purge(companies[1]).purge(people[1]).apply();
        Assert.fail('an order of ' + wrong.size() + ' types for two purged types');
      } catch (Exception refused) {
        Assert.isTrue(refused.getTypeName().endsWith('WorkException'), refused.getTypeName());
      }
    }
    Assert.areEqual(2, [SELECT COUNT() FROM Account], 'nothing was deleted by the refused works');
  }

  @IsTest
  static void aRecordWithoutAnIdCannotBePurged() {
    try {
      App.s.work().purge(new Account(Name = 'Never saved'));
      Assert.fail('there is nothing to delete');
    } catch (Exception refused) {
      Assert.isTrue(refused.getTypeName().endsWith('WorkException'), refused.getTypeName());
    }
  }

  @IsTest
  static void upsertMatchesOnAnExternalIdField() {
    insert blueprint('acme', 'Old label');
    List<Reform_Blueprint__c> incoming = new List<Reform_Blueprint__c>{ blueprint('acme', 'New label'), blueprint('globex', 'Globex') };

    App.s.work().track(incoming, Reform_Blueprint__c.Api_Name__c).apply();

    Assert.areEqual(2, [SELECT COUNT() FROM Reform_Blueprint__c]);
    Assert.areEqual('New label', [SELECT Label__c FROM Reform_Blueprint__c WHERE Api_Name__c = 'acme'].Label__c);
  }

  @IsTest
  static void upsertWithPartialSuccessListsTheRecordsThatFailed() {
    quietSampleTriggers();
    insert new Rollup_Sample_Parent__c(Name = 'Old name', Code__c = 'N-1');
    Rollup_Sample_Parent__c renamed = new Rollup_Sample_Parent__c(Name = 'New name', Code__c = 'N-1');
    Rollup_Sample_Parent__c tooLong = new Rollup_Sample_Parent__c(Name = 'x'.repeat(81), Code__c = 'L-1');
    Rollup_Sample_Parent__c added = new Rollup_Sample_Parent__c(Name = 'South', Code__c = 'S-1');
    inj.IWork work = App.s.work();
    work.options().optAllOrNone = false;

    work.track(new List<Rollup_Sample_Parent__c>{ renamed, tooLong, added }, Rollup_Sample_Parent__c.Code__c).apply();

    Assert.areEqual(1, work.failures().size());
    Assert.areEqual(StatusCode.STRING_TOO_LONG, work.failureOf(tooLong).getErrors()[0].getStatusCode());
    Assert.isNull(work.failureOf(renamed));
    Assert.isNotNull(added.Id, 'a record that was inserted has its Id');
    Assert.areEqual(2, [SELECT COUNT() FROM Rollup_Sample_Parent__c]);
    Assert.areEqual('New name', [SELECT Name FROM Rollup_Sample_Parent__c WHERE Code__c = 'N-1'].Name);
  }

  // Work guide: A parent known by its external Id

  @IsTest
  static void aParentKnownByItsExternalIdIsSetByAnUpdateAfterTheInsert() {
    quietSampleTriggers();
    Rollup_Sample_Parent__c north = new Rollup_Sample_Parent__c(Name = 'North', Code__c = 'N-1');
    insert north;
    Rollup_Sample_Child__c child = new Rollup_Sample_Child__c(Name = 'First');
    Integer before = Limits.getDmlStatements();

    App.s.work().track(child, Rollup_Sample_Child__c.Parent__c, Rollup_Sample_Parent__c.Code__c, 'N-1').apply();

    Assert.areEqual(2, Limits.getDmlStatements() - before, 'the insert, then the update that sets the lookup');
    Assert.areEqual(north.Id, [SELECT Parent__c FROM Rollup_Sample_Child__c WHERE Id = :child.Id].Parent__c);
  }

  @IsTest
  static void anExternalIdThatMatchesNothingFailsTheUpdateAndLeavesTheChild() {
    quietSampleTriggers();
    Rollup_Sample_Child__c child = new Rollup_Sample_Child__c(Name = 'Orphan');

    try {
      App.s.work().track(child, Rollup_Sample_Child__c.Parent__c, Rollup_Sample_Parent__c.Code__c, 'NOBODY').apply();
      Assert.fail('expected a DmlException');
    } catch (DmlException thrown) {
      Assert.isTrue(thrown.getMessage().contains('not found for field Code__c'), thrown.getMessage());
    }

    // The insert had already been made; a caught exception does not undo it.
    Assert.areEqual(1, [SELECT COUNT() FROM Rollup_Sample_Child__c WHERE Name = 'Orphan' AND Parent__c = NULL]);
  }

  @IsTest
  static void withPartialSuccessAnExternalIdThatMatchesNothingIsListed() {
    quietSampleTriggers();
    Rollup_Sample_Child__c child = new Rollup_Sample_Child__c(Name = 'Orphan');
    inj.IWork work = App.s.work();
    work.options().optAllOrNone = false;

    work.track(child, Rollup_Sample_Child__c.Parent__c, Rollup_Sample_Parent__c.Code__c, 'NOBODY').apply();

    Assert.isNotNull(child.Id, 'the child was inserted before its lookup was set');
    inj.IWorkFailure failure = work.failureOf(child);
    Assert.isNotNull(failure, 'and the update that could not set the lookup is listed');
    Assert.isTrue(failure.getMessage().contains('not found for field Code__c'), failure.getMessage());
  }

  @IsTest
  static void upsertNeedsAFieldMarkedAsAnExternalId() {
    try {
      App.s.work().track(new List<Account>{ new Account(Name = 'Acme') }, Account.Name);
      Assert.fail('Name is not an external Id');
    } catch (Exception refused) {
      Assert.isTrue(refused.getTypeName().endsWith('WorkException'), refused.getTypeName());
    }
  }

  @IsTest
  static void trackingARecordAgainIsSortedOut() {
    quietAccountTriggers();
    Account target = new Account(Name = 'Target');
    insert target;

    inj.IWork merging = App.s.work();
    merging.track(new Account(Id = target.Id, Rating = 'Hot'));
    merging.track(new Account(Id = target.Id, Industry = 'Energy'));
    Integer before = Limits.getDmlStatements();
    merging.apply();
    Assert.areEqual(1, Limits.getDmlStatements() - before, 'one update for the one record');
    Account saved = [SELECT Rating, Industry FROM Account WHERE Id = :target.Id];
    Assert.areEqual('Hot', saved.Rating);
    Assert.areEqual('Energy', saved.Industry);

    inj.IWork replacing = App.s.work();
    replacing.track(new Account(Id = target.Id, Rating = 'Cold'));
    replacing.track(new Account(Id = target.Id, Rating = 'Warm'));
    replacing.apply();
    Assert.areEqual('Warm', [SELECT Rating FROM Account WHERE Id = :target.Id].Rating, 'the later instance replaces the earlier');

    Account twin = new Account(Name = 'Twin');
    Account otherTwin = new Account(Name = 'Twin');
    App.s.work().track(twin).track(twin).track(otherTwin).apply();
    Assert.areEqual(2, [SELECT COUNT() FROM Account WHERE Name = 'Twin'], 'the same instance once, an equal-looking record as well');
  }

  @IsTest
  static void dmlOptionsApplyToInserts() {
    inj.IWork work = App.s.work();
    work.options().duplicateRuleHeader.allowSave = true;
    work.options().assignmentRuleHeader.useDefaultRule = true;
    Lead prospect = new Lead(LastName = 'Lovelace', Company = 'Analytical Engines');

    work.track(prospect).apply();

    Assert.isNotNull(prospect.Id);
    Assert.areEqual(true, App.s.work().options().optAllOrNone, 'all or none unless you say otherwise');
  }

  @IsTest
  static void partialSuccessSavesWhatItCanAndListsTheRest() {
    quietAccountTriggers();
    inj.IWork work = App.s.work();
    work.options().optAllOrNone = false;
    Account good = new Account(Name = 'Good');
    Account nameless = new Account();
    Contact child = new Contact(LastName = 'Child');
    Assert.isTrue(work.failures().isEmpty(), 'empty before apply()');

    work.track(good).track(child, Contact.AccountId, nameless).apply();

    Assert.isNotNull(good.Id);
    Assert.isNull(nameless.Id);
    Assert.isNull(child.Id, 'a record is not saved without the new record it depends on');
    Assert.areEqual(2, work.failures().size());
    Assert.isNull(work.failureOf(good), 'null when the record was saved');

    inj.IWorkFailure refused = work.failureOf(nameless);
    Assert.isTrue(refused.getRecord() === nameless, 'the instance that was tracked');
    Assert.areEqual(StatusCode.REQUIRED_FIELD_MISSING, refused.getErrors()[0].getStatusCode());
    Assert.isTrue(refused.getMessage().contains('Name'), refused.getMessage());

    inj.IWorkFailure held = work.failureOf(child);
    Assert.areEqual('Not saved: the Account it is related to was not saved', held.getMessage());
    Assert.isTrue(held.getErrors().isEmpty());
  }

  @IsTest
  static void anExistingRecordIsNotUpdatedWhenTheNewParentItWasToJoinFails() {
    quietAccountTriggers();
    Contact existing = new Contact(LastName = 'Before');
    insert existing;
    existing.LastName = 'After';
    inj.IWork work = App.s.work();
    work.options().optAllOrNone = false;

    work.track(existing, Contact.AccountId, new Account()).apply();

    Assert.areEqual('Before', [SELECT LastName FROM Contact WHERE Id = :existing.Id].LastName, 'its other changes are not saved either');
    Assert.isNotNull(work.failureOf(existing));
  }

  @IsTest
  static void everyRecordOrNoneWithEveryFailureListed() {
    quietAccountTriggers();
    Savepoint before = Database.setSavepoint();
    inj.IWork work = App.s.work();
    work.options().optAllOrNone = false;

    work.track(new Account(Name = 'Good')).track(new Account()).track(new Account()).apply();
    if (!work.failures().isEmpty()) {
      Database.rollback(before);
    }

    Assert.areEqual(2, work.failures().size(), 'both bad records are named, not only the first');
    Assert.areEqual(0, [SELECT COUNT() FROM Account]);
  }

  @IsTest
  static void withAllOrNoneAFailureThrowsAndNothingIsListed() {
    quietAccountTriggers();
    inj.IWork work = App.s.work().track(new Account());

    try {
      work.apply();
      Assert.fail('expected a DmlException');
    } catch (DmlException thrown) {
      Assert.isTrue(work.failures().isEmpty());
    }
  }

  @IsTest
  static void emailsAreAcceptedButNotSentInATest() {
    quietAccountTriggers();
    Messaging.SingleEmailMessage note = new Messaging.SingleEmailMessage();
    note.setToAddresses(new List<String>{ 'owner@example.com' });
    note.setSubject('Order shipped');
    note.setPlainTextBody('Your order is on its way.');
    Account company = new Account(Name = 'Acme');

    inj.IWork work = App.s.work().track(company).track(note);
    Assert.isTrue(work.hasWork());
    work.apply();

    Assert.isNotNull(company.Id);
    Assert.areEqual(0, Limits.getEmailInvocations());
  }
}
