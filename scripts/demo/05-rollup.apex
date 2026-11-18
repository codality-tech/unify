// 05. Rollup: totals over any lookup, from rules an admin keeps in Setup (Rollup_Rule__mdt). No code per rule.
// Nothing is kept: the script rolls back at the end.

Savepoint before = Database.setSavepoint();
List<String> columns = new List<String>{ 'Name', 'Child_Count__c', 'Open_Amount__c', 'Largest_Amount__c', 'Average_Amount__c', 'Earliest_Due__c' };

Demo.title('The rules this org holds');
for (Rollup_Rule__mdt rule : Rollup_Rule__mdt.getAll().values()) {
  Demo.say(rule.Operation__c.rightPad(15) + (rule.Source_Field__c ?? '').rightPad(11) + ' -> ' + rule.Parent_Field__c.rightPad(19) + (rule.Filter__c == null ? '' : ' where ' + rule.Filter__c));
}

inj.IQuery north = App.s.model(Rollup_Sample_Parent__c.SObjectType).query();
north.fields().addAll();
north.filters().add(App.s.eq(Rollup_Sample_Parent__c.Name, 'Demo: North'));
Rollup_Sample_Parent__c parent = (Rollup_Sample_Parent__c) north.fetch();

Demo.title('Before');
Demo.table(north.run(), columns);

Demo.title('200 more children are saved under it');
Demo.mark();
inj.IWork work = App.s.work();
for (Integer n = 1; n <= 200; n++) {
  work.track(new Rollup_Sample_Child__c(Name = 'Bulk ' + n, Parent__c = parent.Id, Amount__c = n, Due__c = Date.today().addDays(n), Status__c = 'Open', Kind__c = 'Bulk'));
}
work.apply();
Demo.cost('The insert and every rule');

Demo.title('After');
Demo.table(north.run(), columns);

Demo.title('One child is closed: only the totals that leave out closed children move');
inj.IQuery biggest = App.s.model(Rollup_Sample_Child__c.SObjectType).query();
biggest.filters().add(App.s.eq(Rollup_Sample_Child__c.Name, 'Bulk 200'));
Id itsId = biggest.fetch().Id;
Demo.mark();
App.s.work().track(new Rollup_Sample_Child__c(Id = itsId, Status__c = 'Closed')).apply();
Demo.cost('The update and the rules it touches');
Demo.table(north.run(), columns);

Database.rollback(before);
Demo.say('');
Demo.say('Rolled back: the org is as it was.');
