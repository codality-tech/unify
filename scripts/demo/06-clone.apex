// 06. Clone: a record copied with the records beneath it, from a plan an admin keeps in Setup (Clone_Step__mdt).
// Nothing is kept: the script rolls back at the end.

Savepoint before = Database.setSavepoint();

Demo.title('The plan');
for (Clone_Step__mdt step : Clone_Step__mdt.getAll().values()) {
  Demo.say(step.DeveloperName.rightPad(28) + step.Object__c.rightPad(26) + (step.Filter__c == null ? '' : 'only where ' + step.Filter__c + '  ') + (step.Set_Values__c == null ? '' : 'then set ' + step.Set_Values__c));
}

inj.IQuery parents = App.s.model(Rollup_Sample_Parent__c.SObjectType).query();
parents.fields().addAll();
parents.filters().add(App.s.lk(Rollup_Sample_Parent__c.Name, 'Demo: North%'));
parents.orderings().add(App.s.ordering(Rollup_Sample_Parent__c.Name, true, false));
Id original = parents.fetch().Id;

Demo.title('One call');
Demo.mark();
Id copy = Cloner.copy('Sample_Parent_Copy', original);
Demo.cost('Copied the parent and its children');

Demo.title('The original and its copy. The copy\'s totals were worked out again by the rollup rules');
Demo.table(parents.run(), new List<String>{ 'Name', 'Child_Count__c', 'Open_Amount__c', 'Largest_Amount__c' });

Demo.title('The children: the closed one stayed behind');
inj.IQuery children = App.s.model(Rollup_Sample_Child__c.SObjectType).query();
children.fields().add(new Set<SObjectField>{ Rollup_Sample_Child__c.Name, Rollup_Sample_Child__c.Amount__c, Rollup_Sample_Child__c.Status__c });
children.fields().add('Parent__r', new Set<SObjectField>{ Rollup_Sample_Parent__c.Name });
children.filters().add(App.s.iin(Rollup_Sample_Child__c.Parent__c, new Set<Id>{ original, copy }));
children.orderings().add(App.s.ordering(new List<SObjectField>{ Rollup_Sample_Child__c.Parent__c, Rollup_Sample_Parent__c.Name }, true, false));
children.orderings().add(App.s.ordering(Rollup_Sample_Child__c.Name, true, false));
Demo.table(children.run(), new List<String>{ 'Parent__r.Name', 'Name', 'Amount__c', 'Status__c' });

Database.rollback(before);
Demo.say('');
Demo.say('Rolled back: the org is as it was.');
