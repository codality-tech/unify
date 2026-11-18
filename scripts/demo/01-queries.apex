// 01. Queries: built a piece at a time, readable as SOQL at any point, bound when they run.

Demo.title('Energy and banking accounts, biggest first, with their owner');
unif.IQuery q = App.s.model(Account.SObjectType).query();
q.fields().add(new Set<SObjectField>{ Account.Name, Account.Industry, Account.AnnualRevenue });
q.fields().add('Owner', new Set<SObjectField>{ User.Name });
q.filters().add(App.s.eq(Account.Site, 'Injectify demo'));
q.filters().add(App.s.iin(Account.Industry, new Set<String>{ 'Energy', 'Banking' }));
q.orderings().add(App.s.ordering(Account.AnnualRevenue, false, true));
Demo.run(q, new List<String>{ 'Name', 'Industry', 'AnnualRevenue', 'Owner.Name' });

Demo.title('The same query, with each account\'s open opportunities added');
unif.IQuery open = App.s.model(Opportunity.SObjectType).query();
open.fields().add(new Set<SObjectField>{ Opportunity.Name, Opportunity.StageName, Opportunity.Amount });
open.filters().add(App.s.eq(Opportunity.IsClosed, false));
q.addSubquery('Opportunities', open);
Demo.soql(q);
for (Account firm : (List<Account>) q.run()) {
  Demo.say(firm.Name + ': ' + firm.Opportunities.size() + ' open');
}

Demo.title('What actually runs: values are bound, never written into the text');
Demo.say(q.toSoql(true));

Demo.title('Contacts, with a field two lookups away and a condition on the parent');
unif.IQuery people = App.s.model(Contact.SObjectType).query();
people.fields().add(new Set<SObjectField>{ Contact.LastName });
people.fields().add('Account', new Set<SObjectField>{ Account.Name });
people.fields().add(new List<SObjectField>{ Contact.AccountId, Account.OwnerId }, new Set<SObjectField>{ User.Username });
people.filters().add(App.s.eq(new List<SObjectField>{ Contact.AccountId, Account.Site }, 'Injectify demo'));
people.filters().add(App.s.eq(new List<SObjectField>{ Contact.AccountId, Account.Rating }, 'Hot'));
people.orderings().add(App.s.ordering(Contact.LastName, true, false));
Demo.run(people, new List<String>{ 'LastName', 'Account.Name', 'Account.Owner.Username' });

Demo.title('Totals by stage');
unif.IAggregateQuery totals = App.s.model(Opportunity.SObjectType).aggregateQuery();
totals.aggregates().add(App.s.count(Opportunity.Id));
totals.aggregates().add(App.s.sum(Opportunity.Amount));
totals.groupBys().add(App.s.path(Opportunity.StageName));
totals.filters().add(App.s.eq(new List<SObjectField>{ Opportunity.AccountId, Account.Site }, 'Injectify demo'));
Demo.say(totals.toSoql());
for (AggregateResult row : totals.run()) {
  Demo.say(String.valueOf(row.get('StageName')).rightPad(20) + row.get('Id_cnt') + ' worth ' + row.get('Amount_sum'));
}

Demo.cost('All of the above');
