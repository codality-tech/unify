// 02. Conditions: one object that filters a query, tests a record in memory, and moves across a relationship.

Demo.title('A rule an admin could type into a setting');
String rule = 'Industry IN (\'Energy\', \'Banking\') AND (AnnualRevenue > 5000000 OR Rating = \'Hot\')';
Demo.say(rule);
inj.ICondition worthACall = App.s.model(Account.SObjectType).parseCondition(rule);

Demo.title('As a query');
inj.IQuery q = App.s.model(Account.SObjectType).query();
q.fields().add(new Set<SObjectField>{ Account.Name, Account.Industry, Account.AnnualRevenue, Account.Rating });
q.filters().add(App.s.eq(Account.Site, 'Injectify demo'));
q.filters().add(worthACall);
Demo.run(q, new List<String>{ 'Name', 'Industry', 'AnnualRevenue', 'Rating' });

Demo.title('The same rule asked of records in memory, as a trigger would');
Demo.mark();
Account big = new Account(Name = 'Big', Industry = 'Energy', AnnualRevenue = 9000000, Rating = 'Cold');
Account keen = new Account(Name = 'Keen', Industry = 'Banking', AnnualRevenue = 10, Rating = 'Hot');
Account neither = new Account(Name = 'Neither', Industry = 'Retail', AnnualRevenue = 9000000, Rating = 'Hot');
for (Account one : new List<Account>{ big, keen, neither }) {
  Demo.say(one.Name.rightPad(9) + worthACall.evaluate(one));
}
Demo.cost('Asking');

Demo.title('Moved one relationship out: the contacts of those accounts');
inj.ICondition theirPeople = worthACall.prepend(App.s.reference(Contact.AccountId));
inj.IQuery people = App.s.model(Contact.SObjectType).query();
people.fields().add(new Set<SObjectField>{ Contact.LastName });
people.fields().add('Account', new Set<SObjectField>{ Account.Name });
people.filters().add(App.s.eq(new List<SObjectField>{ Contact.AccountId, Account.Site }, 'Injectify demo'));
people.filters().add(theirPeople);
people.orderings().add(App.s.ordering(Contact.LastName, true, false));
Demo.run(people, new List<String>{ 'LastName', 'Account.Name' });

Demo.title('Built in code instead, it reads the same');
inj.ICondition built = App.s.all(new List<inj.ICondition>{
  App.s.iin(Account.Industry, new Set<String>{ 'Energy', 'Banking' }),
  App.s.any(new List<inj.ICondition>{ App.s.gt(Account.AnnualRevenue, 5000000), App.s.eq(Account.Rating, 'Hot') })
});
inj.IQuery again = App.s.model(Account.SObjectType).query();
again.filters().add(built);
Demo.soql(again);
