// Puts the demo's records in the org. Safe to run again: it clears what it made last time first.
// Everything it makes is marked: accounts by their Site, sample parents by a name starting 'Demo: '.

Demo.quietExamples();
String site = 'Injectify demo';

// Clear the last run. One unit of work deletes all of it, children before parents.
inj.IQuery oldDeals = App.s.model(Opportunity.SObjectType).query();
oldDeals.fields().add(new Set<SObjectField>{ Opportunity.AccountId });
oldDeals.filters().add(App.s.eq(new List<SObjectField>{ Opportunity.AccountId, Account.Site }, site));
inj.IQuery oldPeople = App.s.model(Contact.SObjectType).query();
oldPeople.fields().add(new Set<SObjectField>{ Contact.AccountId });
oldPeople.filters().add(App.s.eq(new List<SObjectField>{ Contact.AccountId, Account.Site }, site));
inj.IQuery oldFirms = App.s.model(Account.SObjectType).query();
oldFirms.filters().add(App.s.eq(Account.Site, site));
inj.IQuery oldItems = App.s.model(Rollup_Sample_Child__c.SObjectType).query();
oldItems.fields().add(new Set<SObjectField>{ Rollup_Sample_Child__c.Parent__c });
oldItems.filters().add(App.s.lk(new List<SObjectField>{ Rollup_Sample_Child__c.Parent__c, Rollup_Sample_Parent__c.Name }, 'Demo: %'));
inj.IQuery oldRegions = App.s.model(Rollup_Sample_Parent__c.SObjectType).query();
oldRegions.filters().add(App.s.lk(Rollup_Sample_Parent__c.Name, 'Demo: %'));

inj.IWork clearing = App.s.work();
clearing.purge(oldDeals.run()).purge(oldPeople.run()).purge(oldFirms.run());
clearing.purge(oldItems.run());
clearing.apply();
App.s.work().purge(oldRegions.run()).apply(); // after their children are gone: the count rule guards them
Demo.cost('Cleared the last run');

// Accounts, each with two contacts and three opportunities, in one unit of work.
List<List<Object>> firms = new List<List<Object>>{
  new List<Object>{ 'Northwind Energy', 'Energy', 12000000, 'Hot', 'Seattle' },
  new List<Object>{ 'Cascade Power', 'Energy', 3400000, 'Warm', 'Portland' },
  new List<Object>{ 'Harbor Bank', 'Banking', 48000000, 'Hot', 'Boston' },
  new List<Object>{ 'First Meridian', 'Banking', 950000, 'Cold', 'Denver' },
  new List<Object>{ 'Bluebird Retail', 'Retail', 7200000, 'Warm', 'Austin' },
  new List<Object>{ 'Summit Outfitters', 'Retail', 610000, 'Cold', 'Boise' }
};
List<String> surnames = new List<String>{ 'Okafor', 'Lindqvist', 'Tanaka', 'Moreau', 'Reyes', 'Novak', 'Haddad', 'Byrne', 'Castillo', 'Iyer', 'Petrov', 'Nakamura' };
List<String> stages = new List<String>{ 'Prospecting', 'Negotiation/Review', 'Closed Won' };

inj.IWork seeding = App.s.work();
for (Integer at = 0; at < firms.size(); at++) {
  List<Object> firm = firms[at];
  Account company = new Account(
    Name = (String) firm[0],
    Industry = (String) firm[1],
    AnnualRevenue = (Integer) firm[2],
    Rating = (String) firm[3],
    BillingCity = (String) firm[4],
    Site = site
  );
  for (Integer person = 0; person < 2; person++) {
    String surname = surnames[at * 2 + person];
    Contact one = new Contact(FirstName = person == 0 ? 'Alex' : 'Sam', LastName = surname, Email = surname.toLowerCase() + '@' + company.Name.deleteWhitespace().toLowerCase() + '.example.com');
    seeding.track(one, Contact.AccountId, company);
  }
  for (Integer deal = 0; deal < 3; deal++) {
    Opportunity one = new Opportunity(
      Name = company.Name + ' ' + new List<String>{ 'pilot', 'expansion', 'renewal' }[deal],
      StageName = stages[deal],
      Amount = (at + 1) * 15000 * (deal + 1),
      CloseDate = Date.today().addDays(20 * (deal + 1) - 30)
    );
    seeding.track(one, Opportunity.AccountId, company);
  }
}
seeding.apply();
Demo.cost('6 accounts, 12 contacts and 18 opportunities');

// Two sample parents for Rollup, Clone and Import, each with children.
inj.IWork sampling = App.s.work();
for (String region : new List<String>{ 'North', 'South' }) {
  Rollup_Sample_Parent__c parent = new Rollup_Sample_Parent__c(Name = 'Demo: ' + region);
  for (Integer item = 1; item <= 3; item++) {
    Rollup_Sample_Child__c child = new Rollup_Sample_Child__c(
      Name = region + ' item ' + item,
      Amount__c = item * (region == 'North' ? 100 : 250),
      Due__c = Date.today().addDays(item * 7),
      Kind__c = item == 3 ? 'Service' : 'Product',
      Status__c = item == 1 ? 'Closed' : 'Open'
    );
    sampling.track(child, Rollup_Sample_Child__c.Parent__c, parent);
  }
}
sampling.apply();
Demo.cost('2 sample parents with 6 children, their totals worked out by the rollup rules');

inj.IQuery regions = App.s.model(Rollup_Sample_Parent__c.SObjectType).query();
regions.fields().addAll();
regions.filters().add(App.s.lk(Rollup_Sample_Parent__c.Name, 'Demo: %'));
regions.orderings().add(App.s.ordering(Rollup_Sample_Parent__c.Name, true, false));
Demo.table(regions.run(), new List<String>{ 'Name', 'Child_Count__c', 'Open_Amount__c', 'Largest_Amount__c', 'Average_Amount__c', 'Earliest_Due__c' });
Demo.say('Seeded.');
