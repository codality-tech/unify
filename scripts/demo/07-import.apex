// 07. Import: CSV text into records, from a format an admin keeps in Setup (Import_Format__mdt and its columns).
// Nothing is kept: the script rolls back at the end. The Import tab does the same from a file.

Savepoint before = Database.setSavepoint();

String file =
  'Child,Parent,Amount,Due,Kind,Status\n' +
  'North item 2,Demo: North,"1,250.50",2027-03-01,Product,\n' + // exists: updated
  'Brand new item,Demo: South,75,2027-04-15,Service,Open\n' + // new: created
  'Late item,Demo: South,forty,2027-05-01,Product,Open\n' + // "forty" is not a number
  'Lost item,Demo: Nowhere,10,2027-05-01,Product,Open\n' + // no such parent
  'No date item,Demo: North,10,soon,Product,Open\n'; // "soon" is not a date

Demo.title('The file');
Demo.say(file);

Demo.title('Checked first: nothing is saved');
ImportResult check = Importer.check('Sample_Children', file);
Demo.say('Would create ' + check.created + ', update ' + check.updated + '; ' + check.failed + ' of ' + check.rows + ' rows have something wrong');
for (ImportResult.Failure wrong : check.failures) {
  Demo.say('  row ' + wrong.row + ': ' + wrong.message);
}

Demo.title('Then loaded: the good rows are saved, the rest come back');
Demo.mark();
ImportResult done = Importer.load('Sample_Children', file);
Demo.cost('Created ' + done.created + ', updated ' + done.updated + ', failed ' + done.failed);
Demo.say('(That cost includes the rollup rules, which ran for the two parents the rows belong to.)');

Demo.title('The failed rows, as a file to correct and send again');
Demo.say(done.failuresCsv);

Demo.title('What is in the org now');
unif.IQuery children = App.s.model(Rollup_Sample_Child__c.SObjectType).query();
children.fields().add(new Set<SObjectField>{ Rollup_Sample_Child__c.Name, Rollup_Sample_Child__c.Amount__c, Rollup_Sample_Child__c.Due__c, Rollup_Sample_Child__c.Status__c });
children.fields().add('Parent__r', new Set<SObjectField>{ Rollup_Sample_Parent__c.Name });
children.filters().add(App.s.iin(Rollup_Sample_Child__c.Name, new Set<String>{ 'North item 2', 'Brand new item' }));
Demo.table(children.run(), new List<String>{ 'Name', 'Parent__r.Name', 'Amount__c', 'Due__c', 'Status__c' });

Database.rollback(before);
Demo.say('');
Demo.say('Rolled back: the org is as it was.');
