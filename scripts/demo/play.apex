// A place to type. Run it with:  py scripts/demo/run.py play
// Wrap anything that saves in the savepoint below and nothing is kept.

Savepoint before = Database.setSavepoint();
Demo.quietExamples();

inj.IQuery q = App.s.model(Account.SObjectType).query();
q.fields().add(new Set<SObjectField>{ Account.Name, Account.Industry, Account.Rating });
q.filters().add(App.s.eq(Account.Site, 'Injectify demo'));
q.filters().add(App.s.model(Account.SObjectType).parseCondition('Rating = \'Hot\' OR AnnualRevenue > 5000000'));
q.orderings().add(App.s.ordering(Account.Name, true, false));
Demo.run(q, new List<String>{ 'Name', 'Industry', 'Rating' });
Demo.cost('That');

Database.rollback(before);
