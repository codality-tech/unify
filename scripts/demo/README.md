# Demo

Scripts that show the framework and the four solutions running in this project's scratch org. Each is anonymous Apex, short enough to read on a shared screen, and prints what it did and what it cost.

## Before

```bash
py scripts/demo/run.py seed     # 6 accounts with contacts and opportunities, 2 sample parents with children
```

Run it again at any time to put the records back as they were. `py scripts/demo/run.py reset` takes them out.

The scratch org expires on 2026-12-09.

## Running

```bash
py scripts/demo/run.py 01       # the script whose name starts with 01
py scripts/demo/run.py play     # play.apex: type into it, run it, change it, run it again
py scripts/demo/run.py 03 --all # every debug line, not only what the script says
```

`run.py` runs the file with `sf apex run` and prints the lines the script wrote with `Demo.say`, `Demo.table` and the rest. In VS Code, **SFDX: Execute Anonymous Apex with Editor Contents** runs the same files; the output there is the whole debug log.

Scripts 03 to 07 save records and then roll back, so they can be run any number of times and in any order.

## The scripts

| Script | Shows | The line worth saying |
| --- | --- | --- |
| `01-queries` | A query built a piece at a time: fields through lookups, a child subquery, an aggregate | It reads as SOQL at every step, and what runs is bound, never concatenated. |
| `02-conditions` | A rule typed as text, used as a query filter, asked of records in memory, and moved across a relationship | One object does all three, so a rule an admin types can drive a query and a trigger alike. |
| `03-work` | 91 records of four objects saved in four statements; two changes to one record as one update; a delete ordered by itself | You say what should exist, in any order. It works out the order and the lookups. |
| `04-partial-success` | Save what can be saved, and get each failure with its reason | The child of a record that failed is held back, not saved as an orphan. |
| `05-rollup` | Six totals on a parent kept right as 200 children are saved, for three queries | The rules are records in Setup. Adding one is not a deployment of code. |
| `06-clone` | A record copied with its children from a plan in Setup; the copy's totals worked out by the rollup rules | The solutions compose: Clone knows nothing about Rollup. |
| `07-import` | A CSV checked, then loaded: good rows saved, bad rows returned with a reason each | Row and column in every message, and the failures come back as a file to correct. |

## In the browser

```bash
sf org open -o s-unify -p lightning/n/Import                             # choose "Sample: children under their parents", load scripts/demo/data/children.csv
sf org open -o s-unify -p lightning/n/Reform_Showcase                    # forms and tables drawn from blueprints
sf org open -o s-unify -p lightning/o/Rollup_Sample_Parent__c/list       # add a child to a parent and watch its totals
sf org open -o s-unify -p lightning/setup/CustomMetadata/home            # the rules, plans and formats an admin edits
```

The Import tab keeps what it loads. Run `seed` afterwards to put the records back.

## Typing it live

These are the pieces the scripts are made of. All of them run as written in `play.apex`.

```apex
// A query
unif.IQuery q = App.s.model(Account.SObjectType).query();          // selects Id until told otherwise
unif.IQuery q = App.s.qf().make(Account.SObjectType);              // or: every sensible field by default
q.fields().add(new Set<SObjectField>{ Account.Name, Account.Industry });
q.fields().add('Owner', new Set<SObjectField>{ User.Name });       // through a lookup
q.filters().add(App.s.eq(Account.Site, 'Injectify demo'));
q.orderings().add(App.s.ordering(Account.Name, true, false));      // ascending, nulls first
q.setLimit(5);
q.addSubquery('Contacts', App.s.model(Contact.SObjectType).query());
Demo.run(q, new List<String>{ 'Name', 'Industry', 'Owner.Name' }); // prints the SOQL and the rows
Demo.say(q.toSoql(true));                                          // the bound form that runs

// Conditions
App.s.eq(Account.Rating, 'Hot')           // also ne, gt, ge, lt, le
App.s.lk(Account.Name, 'North%')          // LIKE
App.s.iin(Account.Industry, new Set<String>{ 'Energy', 'Banking' })
App.s.eq(new List<SObjectField>{ Contact.AccountId, Account.Rating }, 'Hot')    // a field on the parent
App.s.all(new List<unif.ICondition>{ a, b })                                    // AND; any(...) is OR, neg(x) is NOT
App.s.model(Account.SObjectType).parseCondition('Rating = \'Hot\' OR AnnualRevenue > 5000000')
condition.evaluate(record)                                                      // the same answer, no query
condition.prepend(App.s.reference(Contact.AccountId))                           // the same rule, asked of contacts

// Saving
unif.IWork work = App.s.work();
work.track(record);                                   // no Id: insert. Id: update
work.track(child, Contact.AccountId, parent);         // both saved, the lookup filled in
work.purge(records);                                  // delete, children first
work.options().optAllOrNone = false;                  // save what can be saved...
work.apply();
Demo.failures(work);                                  // ...and print what could not
Demo.cost('That');                                    // queries, statements and records since the last mark

// The solutions
Rollups.recalculate(new Set<Id>{ parentId });
Id copyId = Cloner.copy('Sample_Parent_Copy', parentId);
ImportResult result = Importer.check('Sample_Children', csvText);   // Importer.load saves
```

`Demo.quietExamples()` at the top of a script switches off this org's example triggers on Account, which belong to another example and would be counted in the cost.

## When something goes wrong

- **A script does not compile.** `run.py` prints the line and column. Apex names are case-insensitive: a variable named `account` hides `Account`.
- **Totals look wrong after the Import tab.** Run `seed`.
- **`sf` asks you to log in.** The scratch org has expired or the session has; `sf org open -o s-unify` tells you which.
