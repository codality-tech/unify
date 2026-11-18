// Takes the demo's records out of the org: the accounts marked 'Injectify demo' with their contacts
// and opportunities, and the sample parents named 'Demo: ...' with their children.

Demo.quietExamples();
String site = 'Injectify demo';

unif.IQuery deals = App.s.model(Opportunity.SObjectType).query();
deals.fields().add(new Set<SObjectField>{ Opportunity.AccountId });
deals.filters().add(App.s.eq(new List<SObjectField>{ Opportunity.AccountId, Account.Site }, site));
unif.IQuery people = App.s.model(Contact.SObjectType).query();
people.fields().add(new Set<SObjectField>{ Contact.AccountId });
people.filters().add(App.s.eq(new List<SObjectField>{ Contact.AccountId, Account.Site }, site));
unif.IQuery firms = App.s.model(Account.SObjectType).query();
firms.filters().add(App.s.eq(Account.Site, site));
unif.IQuery items = App.s.model(Rollup_Sample_Child__c.SObjectType).query();
items.fields().add(new Set<SObjectField>{ Rollup_Sample_Child__c.Parent__c });
items.filters().add(App.s.lk(new List<SObjectField>{ Rollup_Sample_Child__c.Parent__c, Rollup_Sample_Parent__c.Name }, 'Demo: %'));
unif.IQuery regions = App.s.model(Rollup_Sample_Parent__c.SObjectType).query();
regions.filters().add(App.s.lk(Rollup_Sample_Parent__c.Name, 'Demo: %'));

App.s.work().purge(deals.run()).purge(people.run()).purge(firms.run()).purge(items.run()).apply();
App.s.work().purge(regions.run()).apply(); // after their children are gone: the count rule guards them
Demo.cost('Removed the demo records');
