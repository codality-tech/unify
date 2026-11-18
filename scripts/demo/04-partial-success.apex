// 04. Partial success: save what can be saved, and be told exactly what could not.
// Nothing is kept: the script rolls back at the end.

Savepoint before = Database.setSavepoint();
Demo.quietExamples();

Demo.title('Three accounts, one of them with no name, each with a contact');
unif.IWork work = App.s.work();
work.options().optAllOrNone = false;
Account good = new Account(Name = 'Good Co');
Account nameless = new Account(Industry = 'Energy');
Account alsoGood = new Account(Name = 'Also Good Co');
Contact orphan = new Contact(LastName = 'Would-be orphan');
work.track(new Contact(LastName = 'Fine'), Contact.AccountId, good);
work.track(orphan, Contact.AccountId, nameless);
work.track(new Contact(LastName = 'Also fine'), Contact.AccountId, alsoGood);
work.apply();

Demo.say('Saved: ' + [SELECT COUNT() FROM Account WHERE Name LIKE '%Good Co'] + ' accounts, ' + [SELECT COUNT() FROM Contact WHERE LastName LIKE '%ine'] + ' contacts');
Demo.say('Not saved:');
Demo.failures(work);

Demo.title('Asked about one record');
Demo.say('The contact of the nameless account: ' + work.failureOf(orphan).getMessage());
Demo.say('It was never inserted without its parent: Id is ' + orphan.Id);
Demo.say('The good account: ' + (work.failureOf(good) == null ? 'no failure' : 'failed'));

Demo.title('The platform\'s own error is there too');
Database.Error first = work.failureOf(nameless).getErrors()[0];
Demo.say(first.getStatusCode() + ' on ' + first.getFields());

Database.rollback(before);
Demo.say('');
Demo.say('Rolled back: the org is as it was.');
