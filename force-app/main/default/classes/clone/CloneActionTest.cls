/** The copy as a flow would call it. */
@IsTest
private class CloneActionTest {
  private static CloneAction.Request request(String plan, Id recordId) {
    CloneAction.Request asked = new CloneAction.Request();
    asked.plan = plan;
    asked.recordId = recordId;
    return asked;
  }

  @IsTest
  static void eachRequestGetsItsCopyInTheOrderAsked() {
    App.s.tf().disable(new List<SObjectType>{ Account.SObjectType });
    App.b.tf().disable();
    ClonePlans.use(
      new List<CloneStep>{
        new CloneStep('Firm').copying(Account.SObjectType).suffixed(' (copy)'),
        new CloneStep('Person').copying(Contact.SObjectType).setting('Title = \'Copy\'')
      }
    );
    Account acme = new Account(Name = 'Acme');
    Account initech = new Account(Name = 'Initech');
    insert new List<Account>{ acme, initech };
    Contact ada = new Contact(LastName = 'Ada');
    insert ada;

    Integer queriesBefore = Limits.getQueries();
    List<CloneAction.Result> results = CloneAction.copy(
      new List<CloneAction.Request>{ request('Firm', initech.Id), request('Person', ada.Id), request('Firm', acme.Id) }
    );

    Assert.areEqual(2, Limits.getQueries() - queriesBefore, 'requests for one plan are copied together');
    Assert.areEqual(3, results.size());
    Assert.areEqual('Initech (copy)', [SELECT Name FROM Account WHERE Id = :results[0].copyId].Name);
    Assert.areEqual('Copy', [SELECT Title FROM Contact WHERE Id = :results[1].copyId].Title);
    Assert.areEqual('Acme (copy)', [SELECT Name FROM Account WHERE Id = :results[2].copyId].Name);
  }
}
