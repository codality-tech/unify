// 03. Unit of work: say what should exist, in any order; it saves in dependency order, one statement per object.
// Nothing is kept: the script rolls back at the end.

Savepoint before = Database.setSavepoint();
Demo.quietExamples();

Demo.title('An account, 50 contacts, 20 opportunities, and a task on every opportunity');
Demo.mark();
unif.IWork work = App.s.work();
Account firm = new Account(Name = 'Globex', Industry = 'Technology');
for (Integer n = 1; n <= 20; n++) {
  Opportunity deal = new Opportunity(Name = 'Globex order ' + n, StageName = 'Prospecting', CloseDate = Date.today().addDays(30), Amount = 1000 * n);
  work.track(new Task(Subject = 'Call about order ' + n), Task.WhatId, deal); // the task comes first, and that is fine
  work.track(deal, Opportunity.AccountId, firm);
}
for (Integer n = 1; n <= 50; n++) {
  work.track(new Contact(LastName = 'Person ' + n), Contact.AccountId, firm);
}
work.apply();
Demo.cost('Saved');

Demo.title('The lookups were filled in as each parent got its Id');
unif.IQuery tasks = App.s.model(Task.SObjectType).query();
tasks.fields().add(new Set<SObjectField>{ Task.Subject });
tasks.fields().add(Task.WhatId, new Set<SObjectField>{ Opportunity.Name });
tasks.filters().add(App.s.lk(Task.Subject, 'Call about order%'));
tasks.orderings().add(App.s.ordering(Task.Subject, true, false));
tasks.setLimit(3);
Demo.soql(tasks);
for (Task one : (List<Task>) tasks.run()) {
  Demo.say(one.Subject + '  ->  ' + ((Opportunity) one.What).Name);
}

Demo.title('The same record tracked twice is one update');
Demo.mark();
unif.IWork changes = App.s.work();
changes.track(new Account(Id = firm.Id, Rating = 'Hot'));
changes.track(new Account(Id = firm.Id, Industry = 'Energy'));
changes.apply();
Demo.cost('Two changes to one account');

Demo.title('Deleting: children first, worked out from the records themselves');
Demo.mark();
unif.IQuery deals = App.s.model(Opportunity.SObjectType).query();
deals.fields().add(new Set<SObjectField>{ Opportunity.AccountId });
deals.filters().add(App.s.eq(Opportunity.AccountId, firm.Id));
unif.IQuery people = App.s.model(Contact.SObjectType).query();
people.fields().add(new Set<SObjectField>{ Contact.AccountId });
people.filters().add(App.s.eq(Contact.AccountId, firm.Id));
App.s.work().purge(firm).purge(deals.run()).purge(people.run()).apply(); // the account is named first; it is deleted last
Demo.cost('Deleted');

Database.rollback(before);
Demo.say('');
Demo.say('Rolled back: the org is as it was.');
