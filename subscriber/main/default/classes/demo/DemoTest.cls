/** The helpers the demo scripts print with. */
@IsTest
private class DemoTest {
  @IsTest
  static void aTableLinesItsColumnsUpAndFollowsLookups() {
    List<Contact> people = new List<Contact>{
      new Contact(LastName = 'Lovelace', Account = new Account(Name = 'Analytical Engines')),
      new Contact(LastName = 'Ng')
    };

    List<String> lines = Demo.tableOf(people, new List<String>{ 'LastName', 'Account.Name' });

    Assert.areEqual(4, lines.size());
    Assert.areEqual('LastName  Account.Name', lines[0]);
    Assert.areEqual('--------  ------------------', lines[1]);
    Assert.areEqual('Lovelace  Analytical Engines', lines[2]);
    Assert.areEqual('Ng', lines[3], 'a parent that is missing reads as empty');
  }

  @IsTest
  static void aTableSaysSoWhenThereIsNothingToShow() {
    List<String> lines = Demo.tableOf(new List<Account>(), new List<String>{ 'Name' });

    Assert.areEqual('(no records)', lines[2]);
  }

  @IsTest
  static void longTextIsCutAndDatesAreWrittenPlainly() {
    Opportunity deal = new Opportunity(Name = 'x'.repeat(60), CloseDate = Date.newInstance(2026, 1, 31));

    List<String> lines = Demo.tableOf(new List<Opportunity>{ deal }, new List<String>{ 'Name', 'CloseDate' });

    Assert.areEqual('x'.repeat(31) + '...  2026-01-31', lines[2]);
  }

  @IsTest
  static void aFieldThatWasNotSelectedIsNamedAsSuch() {
    insert new Contact(LastName = 'Lovelace');
    Contact stored = [SELECT Id FROM Contact];

    List<String> lines = Demo.tableOf(new List<Contact>{ stored }, new List<String>{ 'LastName' });

    Assert.areEqual('(not selected)', lines[2]);
  }

  @IsTest
  static void theCostIsWhatWasSpentSinceTheLastMark() {
    Demo.quietExamples();
    Demo.mark();
    insert new List<Account>{ new Account(Name = 'One'), new Account(Name = 'Two') };
    Integer found = [SELECT COUNT() FROM Account];

    Assert.areEqual('1 query, 1 DML statement, 2 records saved or deleted', Demo.costSince());
    Assert.areEqual('0 queries, 0 DML statements, 0 records saved or deleted', Demo.costSince(), 'counting starts again');
    Assert.areEqual(2, found);
  }

  @IsTest
  static void aQueryIsPrintedRunAndHandedBack() {
    Demo.quietExamples();
    insert new Account(Name = 'Acme', Industry = 'Energy');
    inj.IQuery query = App.s.model(Account.SObjectType).query();
    query.fields().add(new Set<SObjectField>{ Account.Name });

    Demo.title('Accounts');
    List<SObject> records = Demo.run(query, new List<String>{ 'Name' });
    Demo.cost('That');

    Assert.areEqual('Acme', records[0].get('Name'));
  }

  @IsTest
  static void failuresArePrintedWithoutTrouble() {
    Demo.quietExamples();
    inj.IWork work = App.s.work();
    work.options().optAllOrNone = false;
    work.track(new Account(Name = 'Good')).track(new Contact(LastName = 'Child'), Contact.AccountId, new Account());
    work.apply();

    Demo.failures(work);
    Demo.failures(App.s.work());

    Assert.areEqual(2, work.failures().size());
  }
}
