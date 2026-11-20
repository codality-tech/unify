/**
 * What the query guide says about semi-joins, date literals, the statement's options and paths
 * through a polymorphic lookup, run as subscriber code. Each test is named for what the guide says;
 * when one fails, either the framework changed or the guide is wrong.
 */
@IsTest
private class GuideQueryTest {
  // The example triggers on Account do work of their own; these tests are not about them.
  private static void quietAccountTriggers() {
    App.s.tf().disable(new List<SObjectType>{ Account.SObjectType });
    App.b.tf().disable();
  }

  @IsTest
  static void aQueryAsTheValueOfInMatchesAFieldAgainstItsRows() {
    quietAccountTriggers();
    List<Account> firms = new List<Account>{
      new Account(Name = 'Guide Seattle Energy', Industry = 'Energy'),
      new Account(Name = 'Guide Portland Energy', Industry = 'Energy')
    };
    insert firms;
    insert new List<Contact>{
      new Contact(LastName = 'Guide Seattle', AccountId = firms[0].Id, MailingCity = 'Seattle'),
      new Contact(LastName = 'Guide Portland', AccountId = firms[1].Id, MailingCity = 'Portland')
    };

    inj.IQuery inSeattle = App.s.model(Contact.SObjectType).query();
    inSeattle.fields().add(new Set<SObjectField>{ Contact.AccountId });
    inSeattle.filters().add(App.s.eq(Contact.MailingCity, 'Seattle'));

    inj.IQuery accounts = App.s.model(Account.SObjectType).query();
    accounts.fields().add(new Set<SObjectField>{ Account.Name });
    accounts.filters().add(App.s.eq(Account.Industry, 'Energy'));
    accounts.filters().add(App.s.iin(Account.Id, inSeattle));
    Assert.areEqual(
      'SELECT Id, Name FROM Account WHERE (Industry = \'Energy\' AND Id IN (SELECT AccountId FROM Contact WHERE (MailingCity = \'Seattle\')))',
      accounts.toSoql()
    );
    List<Account> found = (List<Account>) accounts.run();
    Assert.areEqual(1, found.size(), 'the values of both queries are bound when it runs');
    Assert.areEqual(firms[0].Id, found[0].Id);

    inj.IQuery elsewhere = App.s.model(Account.SObjectType).query();
    elsewhere.filters().add(App.s.nin(Account.Id, inSeattle));
    elsewhere.filters().add(App.s.iin(Account.Id, new Map<Id, Account>(firms).keySet()));
    Assert.areEqual(firms[1].Id, ((List<Account>) elsewhere.run())[0].Id, 'nin is the anti-join');
  }

  @IsTest
  static void aFactoryQueryIsAnInnerQueryOnceItsDefaultFieldsAreCleared() {
    inj.IQuery contacts = App.s.qf().make(Contact.SObjectType);
    contacts.fields().clearFields().add(new Set<SObjectField>{ Contact.AccountId });
    inj.IQuery accounts = App.s.model(Account.SObjectType).query();
    accounts.filters().add(App.s.iin(Account.Id, contacts));
    Assert.areEqual('SELECT Id FROM Account WHERE (Id IN (SELECT AccountId FROM Contact))', accounts.toSoql());

    inj.IQuery withDefaults = App.s.model(Account.SObjectType).query();
    withDefaults.filters().add(App.s.iin(Account.Id, App.s.qf().make(Contact.SObjectType)));
    try {
      withDefaults.toSoql();
      Assert.fail('a query with its default fields is not an inner query');
    } catch (Exception refused) {
      Assert.isTrue(refused.getMessage().startsWith('Cannot use the query on Contact in a semi-join: it selects'), refused.getMessage());
    }
  }

  @IsTest
  static void aDateLiteralIsWrittenAsItIsAndGivesItsRangeInApex() {
    inj.IQuery q = App.s.model(Opportunity.SObjectType).query();
    q.filters().add(App.s.eq(Opportunity.StageName, 'Prospecting'));
    q.filters().add(App.s.le(Opportunity.CloseDate, inj.DateLiteral.nextNDays(30)));
    q.filters().add(App.s.iin(Opportunity.CreatedDate, new List<inj.IDateLiteral>{ inj.DateLiteral.today(), inj.DateLiteral.yesterday() }));
    Assert.areEqual(
      'SELECT Id FROM Opportunity WHERE (StageName = \'Prospecting\' AND CloseDate <= NEXT_N_DAYS:30 AND CreatedDate IN (TODAY, YESTERDAY))',
      q.toSoql()
    );
    Assert.areEqual(0, q.run().size(), 'the platform takes it as written, the literals unbound');

    Date firstOfMonth = Date.today().toStartOfMonth();
    Assert.areEqual(firstOfMonth, inj.DateLiteral.thisMonth().startDate());
    Assert.areEqual(firstOfMonth.addMonths(1).addDays(-1), inj.DateLiteral.thisMonth().endDate(), 'the last day, inclusive');
    Assert.areEqual('LAST_N_DAYS:30', inj.DateLiteral.of('last_n_days : 30').toSoql(), 'case and the spaces around the colon do not matter');
  }

  @IsTest
  static void theOptionsAreWrittenWhereThePlatformTakesThem() {
    inj.IQuery mine = App.s.model(Account.SObjectType).query()
      .usingScope(inj.Enums.FilterScope.MINE)
      .allRows(true)
      .forView(true)
      .setLimit(10);
    mine.addCondition(App.s.eq(Account.Industry, 'Energy'));
    Assert.areEqual(
      'SELECT Id FROM Account USING SCOPE mine WHERE (Industry = \'Energy\') LIMIT 10 FOR VIEW ALL ROWS',
      mine.toSoql()
    );
    Assert.areEqual(0, mine.run().size(), 'the platform takes the options in that order');
  }

  @IsTest
  static void aPathGoesThroughAPolymorphicLookupToTheFieldsEveryTargetHas() {
    quietAccountTriggers();
    Account firm = new Account(Name = 'Guide Polymorphic');
    insert firm;
    insert new Task(Subject = 'Guide call', WhatId = firm.Id);

    inj.IQuery t = App.s.model(Task.SObjectType).query();
    t.fields().add(new Set<String>{ 'Subject', 'What.Type', 'What.Name', 'Owner.Name' });
    t.filters().add(App.s.eq('What.Type', 'Account'));
    t.orderings().add(App.s.ordering('What.Name', true, false));
    Assert.areEqual(
      'SELECT Id, Subject, What.Type, What.Name, Owner.Name FROM Task WHERE (What.Type = \'Account\') ORDER BY What.Name ASC NULLS FIRST',
      t.toSoql()
    );
    List<Task> found = (List<Task>) t.run();
    Assert.areEqual(1, found.size());
    Assert.areEqual('Guide Polymorphic', found[0].What.Name);
    Assert.isTrue(App.s.eq('What.Type', 'Account').evaluate(found[0]), 'a row the query returned answers in memory');

    try {
      App.s.model(Task.SObjectType).query().addCondition(App.s.eq('What.Industry', 'Energy')).toSoql();
      Assert.fail('a field of one target does not follow the lookup');
    } catch (Exception refused) {
      Assert.isTrue(refused.getMessage().contains('What can point at several objects, and Industry is not a field of them all'), refused.getMessage());
    }
  }
}
