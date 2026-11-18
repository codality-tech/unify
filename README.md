# Unify

Solutions built with the Injectify framework. Each one is a working piece of an org, and together they are the framework's subscriber test: everything here compiles and runs against the installed package, through its public API only.

The repository has two halves:

- **`force-app/` is the Unify package** (unlocked, namespace `unif`, depending on Injectify): the four solutions, their sample objects and sample metadata, and `Unify`, the application they run on. No version is built yet.
- **`subscriber/` is an org's own side**, deployed as source and never packaged: the org's entry point (`App`), example classes, the tests that check the framework's guides, and the demo.

Code in the examples below is written as it reads in this repository, without a prefix. In an org that installs the package, the solutions' names carry it: `unif.Cloner.copy(...)`, `unif.RollupHandler`, `unif__Rollup_Rule__mdt`.

| Solution | What an org calls or uses |
| --- | --- |
| Reform | The components `reformPanel` and `reformShowcase`, and `Reform_Blueprint__c` records |
| Rollup | `RollupHandler`, `Rollups.changed`, `Rollups.guardDelete`, `Rollups.recalculate`, `Rollups.sweep`, `RollupJobs.Nightly`, and `Rollup_Rule__mdt` records |
| Clone | `Cloner.copy`, the flow action `CloneAction`, and `Clone_Step__mdt` records |
| Import | `Importer.load`, `Importer.check`, `ImportResult`, the component `importPanel`, and `Import_Format__mdt` records with their columns |

Those Apex names are `global`. Everything else in the package is its own business and can change.

> **Status:** early. Reform is rebuilt on the current framework: server side and Lightning components, both tested. Rollup and Clone are new: server side only, tested. Import is new: server side and a Lightning component, both tested.

## Reform

Forms and tables that an admin describes in a **blueprint** instead of a developer building them in a component.

A blueprint names an object and lists:

- **elements** of a form: fields, headings, rich text and spacers, each optionally shown only when a rule holds;
- **columns** of a table, which can cross lookups (`Account.Owner.Name`);
- **filters** that decide which records the table lists;
- **parameters**: field values fixed from outside, such as the account a related list belongs to. A fixed value filters the table and is stamped on every record the form saves.

```json
{
  "sobjectName": "Opportunity",
  "elements": [
    { "field": { "name": "AccountId" } },
    { "width": 6, "field": { "name": "Name", "required": true } },
    { "width": 6, "field": { "name": "Amount" } },
    { "visible": "Amount > 100000", "field": { "name": "NextStep", "defaultValue": "Brief the account team" } },
    { "visible": "AccountId != null", "richtext": { "content": "Account owner: <b>{!Account.Owner.Name}</b>" } }
  ],
  "columns": [{ "name": "Name" }, { "name": "Account.Name", "label": "Account" }, { "name": "Amount" }],
  "filters": ["StageName != 'Closed Lost'"],
  "parameters": [{ "name": "StageName", "fixedValue": "Prospecting" }]
}
```

A blueprint is stored in a `Reform_Blueprint__c` record, sent by a component, or both: a component that sends `{ "name": "deal_form" }` plus a few keys of its own gets the stored blueprint with those keys laid over it.

### What the framework does here

| Reform needs | The framework provides |
| --- | --- |
| A rule written by an admin, `Amount > 100000` | `model.parseCondition(text)` turns it into a condition |
| The same kind of rule filtering a table and showing or hiding an element | One condition: compiled into the table's SOQL, evaluated in memory for the form |
| To know which fields a rule reads, so the form can react when they change | `model.compileCondition(rule).getPaths()` |
| `{!Account.Owner.Name}` in text, and columns across lookups | `model.path('Account.Owner.Name')`, then `path.getFieldValue(record)` |
| Queries with exactly the fields in use, run as the user | `model.query()`, `fields().add(paths)`, `withSharing(true)` |
| Saving and deleting as the user | `App.s.work().withSharing(true).track(record).apply()` and `purge` |
| Stored blueprints, checked when saved | A registered query class and a domain class with a trigger hook |

### How it is put together

| Class | Does |
| --- | --- |
| `ReformDefinition` | Reads a blueprint from a record or a map. Knows nothing about the schema. |
| `ReformPlan` | Checks a definition against the schema: fields, rules, merge fields, columns. Mistakes become problems that say where they are; nothing throws. |
| `ReformEngine` | Computes a form or a page of a table from a plan, and saves and deletes. |
| `ReformView` | What a component receives. |
| `ReformApi` | The `@AuraEnabled` entry points: `form`, `table`, `tableWired`, `remove`. |
| `ReformBlueprints`, `ReformBlueprintQuery` | The domain and query classes for stored blueprints. A blueprint with a mistake cannot be saved. |

### Components

| Component | Does |
| --- | --- |
| `c-reform-entry` | The form. Draws what the server computes, with an input to suit each field's type, and asks again when a `reactive` field changes. Fires `saved` and `cancel`. |
| `c-reform-list` | The table: the blueprint's columns, a page at a time, with New, Edit and Delete where the blueprint and the user's permissions allow. Fires `new` and `edit`. |
| `c-reform-panel` | The two together. Add it to a page in the Lightning App Builder and give it a stored blueprint's API name. On a record page, also give it the lookup that points at the page's record (`AccountId`) and it becomes a related list: only that record's children, and new ones filed under it. |
| `c-reform-showcase` | Three sample blueprints to try, on the **Reform Showcase** tab. Assign the `Reform Showcase` permission set to see the tab. |

A component is given a blueprint as an object: a whole definition, `{ name: 'deal_form' }` for a stored one, or a stored one's name plus keys to lay over it.

A form is computed from the values a component holds and is never written until `save` is asked for, so a component can ask again after every change to a field marked `reactive`. Rules and merge fields that read through a lookup see the parent the user has just picked, not the one stored.

### Access

Reads and writes both run as the user. Reads apply sharing and field-level security, and a field or column the user cannot see is left out. Writes go through the framework's unit of work in user mode, so the platform refuses whatever the user may not do. Before that the engine checks the user's object and field permissions and their access to the record, so a refusal says what was refused, and it writes only the fields the blueprint names. A blueprint can also set `createable`, `updateable` or `deleteable` to `false`.

- **Permissions.** A user who cannot read the object is refused outright. A field the user cannot see is left out of tables and forms, and a rule or merge field that reads it comes out as if the field were empty. A field the user can see but not change is drawn read-only, and a value sent for it is ignored. `ReformAccessTest` runs each of these as a user with a minimal profile.
- **Sharing.** A record the user cannot see is not listed and cannot be opened. A record shared with them for reading opens but cannot be saved or deleted; one shared for editing can be saved but not deleted. `ReformSharingTest` runs these on `Reform_Private_Sample__c`, an object that exists for the purpose: it is shared privately, which the standard objects in a scratch org are not.

Not handled: a form does not yet draw itself read-only for a record the user can open but not edit. The save is refused with a message instead.

### Rules

Rules use SOQL's `WHERE` syntax: `=`, `!=`, `<`, `>`, `<=`, `>=`, `LIKE`, `IN`, `NOT IN`, `INCLUDES`, `EXCLUDES`, combined with `AND`, `OR`, `NOT` and parentheses. Fields can be reached through lookups: `Account.Owner.IsActive = true`.

## Rollup

Totals of child records, kept on the record their lookup points at. It is what a roll-up summary field does for a master-detail relationship, for any lookup.

A rule is a `Rollup_Rule__mdt` record, so an admin adds one in Setup and it deploys like any other metadata:

| Field | Holds |
| --- | --- |
| Child Object, Lookup Field | Whose records are rolled up, and the lookup that points at the parent: `Opportunity`, `AccountId` |
| Operation, Source Field | Count, Count Distinct, Sum, Average, Minimum or Maximum, and the child field it reads. A count needs no field; given one, it counts the children that have a value in it. |
| Parent Field | The field on the parent that receives the result |
| Filter | Optional. Which children count, in SOQL's `WHERE` syntax: `StageName = 'Closed Won' AND Amount > 0` |
| Timing | Immediate recalculates as part of the save. Queued recalculates moments later, in a job of its own. |
| Guard Parent Delete | Stops a parent from being deleted while the result is above zero |
| Active | An inactive rule is ignored |

The same rule can be written in code, which is how the tests give theirs:

```apex
new RollupRule('Open_Amount')
  .children(Opportunity.AccountId)
  .sum(Opportunity.Amount)
  .matching('IsClosed = FALSE')
  .writeTo(Account.AnnualRevenue);
```

### Wiring an object

A child object needs a trigger, and its body is the usual one line. With no domain class of its own, register `RollupHandler` for it in the org's own entry point, `App`:

```apex
trigger OpportunityTrigger on Opportunity(after insert, after update, after delete, after undelete) {
  App.s.tf().execute();
}

new Map<Type, Type>{ Opportunity.class => RollupHandler.class } // in App's trigger registry
```

The sample objects are wired the same way inside the package, on its own application (`Unify.s`), so they work as installed.

An object that already has a domain class calls `Rollups.changed(this, oldMap)` from its after-save hook and `Rollups.changed(this, null)` from its after-delete and after-undelete hooks. A parent whose deletion is guarded needs a `before delete` trigger the same way.

### What a save costs

However many children are saved and however many rules there are:

- one aggregate query for each set of rules that share a child object, lookup and filter;
- one query for the parents' present values, for each parent object;
- one update, of only the parents whose values differ.

`RollupHandlerTest` saves 200 children under three rules and counts two queries and one update. A change that cannot alter a result (no watched field changed, or the child is outside the filter before and after) costs no query at all.

When a transaction is running short of queries, an immediate rule is queued instead of run. When no job can be started, a queued rule is run at once.

### After the fact

- `Rollups.recalculate(parentIds)` recalculates every rule for those parents, now.
- `Rollups.sweep()` recalculates every rule over every parent: one batch per parent object, chained. Run it after adding a rule.
- `inj.Async.schedulable(new RollupJobs.Nightly()).run()` schedules a sweep every night at two, to correct what no trigger saw.

### What the framework does here

| Rollup needs | The framework provides |
| --- | --- |
| A filter an admin writes | `model.parseCondition(text)` |
| The same filter deciding, in a trigger, whether a changed child matters | `condition.evaluate(record)`, on the record as it is now and as it was |
| To know which fields a filter reads, so other changes are ignored | `model.compileCondition(filter).getPaths()` |
| One grouped query that serves several rules | `model.aggregateQuery()` with a function per rule, grouped by the lookup |
| The function a rule names, chosen at run time | `aggregate(inj.Enums.Aggregate, field)` |
| Two saves under one parent taking turns | `query.forUpdate(true)` on the parents, before the children are totalled |
| The children whose watched fields changed | `domain.getChangedRecords(oldMap, fields)` |
| Parents written in system mode, only where a value differs | `work().track(record).apply()` |
| A recalculation in a job of its own, batches one after another, a schedule | `inj.Async.queueable`, `queryable(...).then(...)`, `schedulable` |
| Totals that cover records the user cannot see | An application of its own, built on a scheme declared `without sharing` |
| A trigger handler any object can use | A `inj.BaseDomain` registered in the trigger registry |

### How it is put together

| Class | Does |
| --- | --- |
| `RollupRule` | A rule as plain data: API names, an operation, a filter. Read from a metadata record or built in code. |
| `RollupPlan` | A rule with its names resolved. Mistakes become problems an admin can act on: `Opportunity.StageName is not a number, so it cannot be summed or averaged`. |
| `RollupRules` | The active rules, read once per transaction at no query cost, each compiled when first needed. |
| `Rollups` | The engine: `changed`, `recalculate`, `sweep`, `guardDelete`. |
| `RollupJobs` | The queued recalculation, the sweep and its nightly schedule, as handlers for the framework's async engine. |
| `RollupScheme` | The scheme the rollup reads through, and the application built on it. |
| `RollupHandler` | The ready-made trigger handler. |

### Access

A total covers every child, whoever saves one, and is written to a parent that person may not edit. `RollupHandlerTest` shows both, with a user who can see one of a parent's two children and can only read the parent.

A query made through the framework is run by the application's scheme. A scheme with a sharing keyword of its own settles whose records are seen; one without takes the sharing of the class that built the query. The rollup has an application of its own, on a scheme declared `without sharing`, so its totals depend neither on which class happens to call it nor on the scheme the rest of the org chose. `GuideAccessTest` shows both cases.

### A rule that is wrong

A rule that cannot run is not skipped. The save that would have used it fails, and the message names the rule and what is wrong with it: a total that is silently out of date is worse than an error someone has to fix. Rules of other objects carry on.

`RollupRulesTest.everyStoredRuleCanRun` checks the rules stored in the org, so a deployment that runs the tests cannot bring in a rule that will not run.

### The sample

`Rollup_Sample_Parent__c` and `Rollup_Sample_Child__c`, with six rules between them, one for each operation. Assign the `Rollup Sample` permission set to see the **Rollup Sample Parents** tab; add children to a parent and watch its fields. Five are filled as part of the save and Kinds a moment later, since its rule is queued.

### Not handled

- A lookup that can point at more than one object (`WhatId`, `WhoId`) is refused.
- First, last and concatenated values: only what a SOQL aggregate can work out.
- A filter that reads through a lookup (`Account.Type = 'Customer'`) is honoured by the query, but a change to that related record does not recalculate anything. Only changes to the children do, until the next sweep.
- Changes no trigger sees: merged records, and data loaded with triggers switched off. A sweep corrects them.
- A filter longer than 255 characters.

The parents are read with a lock before their children are totalled, so two saves under one parent take turns, and the second totals what the first saved. A save that cannot get the lock in time fails with the platform's error.

Not tested: a parent with tens of thousands of children, the lock under real concurrent saves, and currency fields in an org with several currencies.

## Clone

Copies a record together with the records beneath it: an opportunity with its products and contact roles, a project with its tasks. A **plan** says what comes along, and an admin writes it in Setup.

A plan is a tree of `Clone_Step__mdt` records. The step with no parent starts the plan and gives it its name; each step beneath says which related records are copied too, to any depth.

| Field | Holds |
| --- | --- |
| Object | The object this step copies |
| Parent Step, Lookup Field | The step this one sits under, and the lookup that points at that step's object: `Deal`, `OpportunityId`. Both blank on the step that starts a plan. |
| Filter | Optional. Which of the related records are copied, in SOQL's `WHERE` syntax: `IsPrimary = TRUE` |
| Leave Out | Optional. Fields not to copy, separated by commas |
| Set Values | Optional. Values every copy is given, written as a condition the copy must meet: `StageName = 'Prospecting' AND Probability = 10` |
| Name Suffix | Optional. Added after the name of each copy: `(copy)` |
| Active | An inactive step is ignored, along with every step beneath it |

The same plan in code, which is how the tests give theirs:

```apex
new CloneStep('Deal').copying(Opportunity.SObjectType).suffixed('(copy)').setting('StageName = \'Prospecting\'');
new CloneStep('Deal_Roles').under('Deal', OpportunityContactRole.OpportunityId);
```

### Running one

```apex
Id copyId = Cloner.copy('Deal', opportunityId);
Map<Id, Id> copyIds = Cloner.copy('Deal', opportunityIds); // each copy's Id, by its original's
```

A flow runs one through the action **Copy a record with its related records** (`CloneAction`), so an admin can put it on a button without code.

### What gets copied

Every field the person can read and may fill in on a new record, except:

- fields the step leaves out;
- fields that must be unique;
- the owner: a copy belongs to whoever made it.

A lookup that is not the step's own still points where the original's did. A copied contact role points at the copy of its opportunity, and at the same contact as before.

### What a copy costs

One query for each step of the plan, however many records are copied, and one unit of work, which saves each object once, parents before the records that point at them. `ClonerTest` copies two accounts with their contacts, opportunities and contact roles in four queries and four saves.

### Access

The copy is made as the person asking for it, unlike a rollup:

- it holds the records they can see, and the fields they can read and may fill in;
- an object they cannot read contributes nothing;
- an object they can read but may not create stops the copy, with a message, before anything is saved;
- a record they cannot see is refused: `That Account does not exist, or you cannot see it`.

A copy is a duplicate by design, so duplicate rules that only warn are passed over. One that blocks still blocks.

### What the framework does here

| Clone needs | The framework provides |
| --- | --- |
| Children saved after their parents, each pointing at its parent's copy | `work.track(copy, lookupField, parentCopy)`: the unit of work orders the saves and fills in the lookups |
| The copy made as the user | `query.withSharing(true)` and `work().withSharing(true)` |
| A filter an admin writes | `model.parseCondition(text)` |
| Values an admin writes, checked against their fields and typed | The same parser: `StageName = 'Prospecting' AND Probability = 10` is read as a condition, and each comparison's field and value are taken from it |
| Duplicate rules that warn passed over | `work.options()`, the platform's own DML options |
| The name of any object | `model.nameField()` |

### How it is put together

| Class | Does |
| --- | --- |
| `CloneStep` | A step as plain data. Read from a metadata record or built in code. |
| `ClonePlan` | A plan with its names resolved, as a tree. Mistakes become problems that say which step they are about. |
| `ClonePlans` | The plans the org holds, read at no query cost. |
| `Cloner` | The engine: `copy`. |
| `CloneAction` | The action a flow calls. |

A plan that is wrong is refused when it is run, with what is wrong. `ClonePlansTest.everyStoredPlanCanRun` checks the stored plans, so a deployment that runs the tests cannot bring in one that will not run.

### The sample

The plan `Sample_Parent_Copy` copies a `Rollup_Sample_Parent__c` with its children that are not closed, and sets each copied child back to Open. It leaves the parent's totals out, and the Rollup solution works them out again from the copied children: `ClonerTest.theStoredSamplePlanRunsAndTheRollupsFollow` runs the two together.

### Not handled

- A lookup between two copied records that is not a step's own lookup (a task that depends on another task) still points at the original, not at its copy.
- Records that point at their own object (an account's child accounts) as a step beneath it: not tried.
- Files, notes and other records that hang off a record through a link object need a step of their own for the link.
- A name is given its suffix only where the name is one field that can be written. A contact's is not.
- There is no button yet: only the Apex calls and the flow action.

Not tested: a copy too large for one transaction.

## Import

Loads a CSV file into records. A **format** says what the file holds, and an admin writes it in Setup: no mapping screen to click through on every upload, and no script per file.

A format is an `Import_Format__mdt` record with `Import_Column__mdt` records beneath it.

| Format field | Holds |
| --- | --- |
| Object | The object the rows become |
| Operation | Create records, update records, or create or update |
| Match Field | The field that says which record a row is: `Id`, `Email`, an external Id. Any text field will do, not only an external Id. Blank for a format that only creates. |
| All Or Nothing | Checked: one row that fails stops the whole file. Unchecked: the other rows are saved. |
| Active | An inactive format cannot be run and is not offered |

| Column field | Holds |
| --- | --- |
| Format | The format the column belongs to |
| Header | The column's heading in the file; case does not matter. Blank gives every row the default. |
| Field | The field the column fills |
| Match Related By | For a lookup. A text field of the related object that the cell is matched against: `Name`. Blank when the cell holds an Id. |
| Default | Optional. The value a row takes where its cell is empty, or where the file has no such column. |
| Required | A row with nothing in this column fails |
| Position | Optional. Where the column comes when the format lists its headers. |

**A format with no columns reads the file by its headers.** A header that is a field's API name or its label fills that field, and a header like `Account.Name` fills the lookup by matching the related record on that field. Columns it cannot place are passed over and listed.

The same format in code, which is how the tests give theirs:

```apex
new ImportFormat('Contacts')
  .into(Contact.SObjectType)
  .creatingOrChanging(Contact.Email)
  .column('Email', Contact.Email)
  .column('Surname', Contact.LastName).required()
  .column('Company', Contact.AccountId, Account.Name)
  .column('Title', Contact.Title).otherwise('Member')
  .constant(Contact.LeadSource, 'Other');
```

### Running one

```apex
ImportResult done = Importer.load('Contacts', csvText);
ImportResult wouldBe = Importer.check('Contacts', csvText); // everything but the save
```

A result counts the rows created, updated and failed, lists each failure with its row number, and carries the failed rows as CSV text.

On a page, the **Import** tab (the `importPanel` component, behind the `Import` permission set) does the same: choose a format, choose a file, check it or import it. Placed on a page of its own, the component can be given one format to offer.

### Rows that fail

A row that cannot be read or saved fails by itself, and says why by row and column:

| Row | What is wrong |
| --- | --- |
| 3 | Born: "soon" is not a date; write it like 2026-01-31 |
| 5 | Company: no Account you can see has Account Name "Nowhere Ltd" |
| 6 | Company: 2 Accounts have Account Name "Twin" |
| 7 | Email: row 2 has "good@example.com" too |
| 9 | Last Name: data value too large: xxxxxxxx... (max length=80) |

The last of those is the org speaking: validation rules, triggers, required fields and duplicate rules are reported the same way.

The failed rows come back as a file: the columns they came with and one more, **Error**. Correct them and import that file; its Error column is not read. An all-or-nothing format saves no row unless every row can be saved, and still reports every row that is wrong, not only the first.

### What a cell may hold

| Field | Text it reads |
| --- | --- |
| Checkbox | true, yes, y, 1, false, no, n, 0, in any case |
| Number, currency, percent | `1234.5`, `-1234.5`, `1,234.5`; a percent may end in `%` |
| Date | `2026-01-31`, or the way the person's own locale writes a date |
| Date and time | `2026-01-31T14:30:00Z`, `2026-01-31 14:30` in the person's time zone, a date alone, or their locale's way |
| Time | `14:30` or `14:30:15` |
| Lookup | An Id, or the related record's value in the column's Match Related By field |
| Picklist | A value or its label, in any case |

- An empty cell leaves the field alone. A cell holding `#N/A` empties it.
- A comma is taken as a thousands separator only where it sits like one: `1,5` is refused, not read as 15.
- The file's separator is worked out from its first line: comma, semicolon, tab or bar. Quoted cells may hold separators, line breaks and doubled quotes.

### What an import costs

One query for each column that finds a related record, one to match the rows against existing records, one insert and one update, however many rows. `ImporterTest` loads 200 rows, half new and half existing, each with a company to find, in two queries and two saves.

One transaction takes as many rows as the org's limits allow. The component sends a longer file in parts of 200 rows, each a transaction of its own, and adds up the results. An all-or-nothing format is sent whole.

### Access

The import is made as the person asking for it, like a copy and unlike a rollup:

- rows are matched against the records they can see, and saved with their permissions;
- an object they may not create or change, or a field they may not fill in, stops the file with a message before anything is saved: `You cannot fill in Birthdate on Contacts`;
- a record they can see but may not edit fails as its own row;
- a field that can be written only on new records is left alone on the rows that update, one that can be written only on existing records is left out of the rows that create, and the result says so.

A row matched on anything but an Id is matched among the records the person can see. If the record exists and they cannot see it, a create-or-update format makes a new one.

### What the framework does here

| Import needs | The framework provides |
| --- | --- |
| The object and fields an admin names, checked | `App.s.model(name)`, `model.fieldMap()`, `model.scheme().getFieldDescribe(field)` |
| Related records found by any field, as the user | `model.query().withSharing(true)` with `iin(field, values)`: one query per column |
| Rows matched against existing records, as the user | The same query on the format's match field |
| A typed list to save | `model.spawnRecordList()` |
| The file as a header and rows, whatever its separator and quoting | `inj.CsvUtil.read(text)` |
| The text of a cell as the value its field takes, or a message a person can act on | `inj.FieldUtil.fromText(describe, text)` |
| The rows saved as the user, each passing or failing by itself | `App.s.work().withSharing(true)` with `options().optAllOrNone = false`, then `work.failureOf(record)` |
| The failed rows as a file | `inj.CsvUtil.toCsv(header, rows)` |

Reading CSV, turning text into values and reporting which records failed were not in the framework when Import was first built. Import did all three itself; building it showed the gaps, and package 0.2.7-5 closed them.

### How it is put together

| Class | Does |
| --- | --- |
| `ImportFormat` | A format as plain data. Read from metadata records or built in code. |
| `ImportPlan` | A format with its names resolved, and `layout(header)`, which fits it to one file. Mistakes become problems that say which column they are about. |
| `ImportFormats` | The formats the org holds, read at no query cost. |
| `Importer` | The engine: `load`, `check`. |
| `ImportResult` | What an import did. |
| `ImportApi` | The `@AuraEnabled` entry points: `formats`, `run`. |
| `importPanel` | The component. |

A format that is wrong is refused when it is run, with what is wrong. `ImportFormatsTest.everyStoredFormatCanRun` checks the stored formats, so a deployment that runs the tests cannot bring in one that will not run.

### The samples

- `Sample_Parents` creates `Rollup_Sample_Parent__c` records and names no columns: a file with a `Name` column is enough.
- `Sample_Children` creates or updates `Rollup_Sample_Child__c` records, matched on their name. Its Parent column finds the parent by name, and Status defaults to Open.

The Rollup solution's triggers fire as the rows are saved, so the parents' totals follow: `ImporterTest.theStoredSampleFormatsRunAndTheRollupsFollow` runs the two together. Both need the `Rollup_Sample` permission set as well, for access to the sample objects.

### Not handled

- Rows are matched on one field, which must be text or an Id. A number field, or two fields together, cannot be the match.
- Two rows of one file with the same match value: the second fails. Sent in parts, a row that repeats one from an earlier part updates the record that part made.
- Lookups that can point at more than one object (`WhatId`, `WhoId`) take Ids only.
- Address and location fields, and files.
- A number written the continental way (`1.234,5`) is refused.
- Deleting records.
- There is no flow action, and no background job: a file is loaded while the person waits.

Not tested: a file of tens of thousands of rows, the two download links (what they hold is tested; clicking them in a browser is not), and the component in any browser but Chrome.

## Demo

`scripts/demo/` holds a demo that runs in the scratch org: a seed script, seven short anonymous Apex scripts (queries, conditions, the unit of work, partial success, Rollup, Clone, Import), a file to type into, and a runner that prints only what each script says. `Demo` (`subscriber/.../classes/demo/`) is the helper they print with: a query as SOQL and its rows as a table, and what a piece of work cost in queries and statements. See [`scripts/demo/README.md`](scripts/demo/README.md).

```bash
py scripts/demo/run.py seed
py scripts/demo/run.py 01
```

## Working on it

The Injectify package must be installed in the org first. Then both halves are deployed as source, to an org without a namespace:

```bash
sf project deploy start -d force-app -d subscriber --ignore-conflicts
sf apex test run -l RunLocalTests -c
```

The package is built from `force-app/` alone, so nothing in it may name a class in `subscriber/`. The solutions reach the framework through `Unify.s`; the org's own code reaches it through `App.s`. The tests in `force-app/` cover the package by themselves.

The components have unit tests of their own, which need no org:

```bash
npm install --ignore-scripts --legacy-peer-deps
npx sfdx-lwc-jest
```
