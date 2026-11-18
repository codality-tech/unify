# CLAUDE.md

Guidance for Claude Code when working in this repository.

## What this is

**Unify**: solutions built with the Injectify framework, and the framework's subscriber test. Everything here compiles and runs against the installed package through its public API only. `README.md` describes the solutions: Reform (forms and tables from blueprints), Rollup (totals over lookups, from metadata rules), Clone (a record copied with the records beneath it, from metadata plans) and Import (CSV files loaded into records, from metadata formats).

The framework's source is the sibling repository `../injectify`. Its package is installed here under the namespace `inj`.

| Need | Where |
| --- | --- |
| Every global type and method signature | `../injectify/docs/documentation/package_api.apex` |
| Guides (extension, query, work, async, testing) | `../injectify/docs/documentation/` |
| Framework source, when a signature is not enough | `../injectify/force-app/classes/` |

Read the API file before writing framework code. Do not guess at method names, and do not copy the documentation into this repository.

## Layout

```
force-app/main/default/
  classes/            App (the entry point), Accounts, ExampleService, Scheme30/50/64, BypassTriggers (the trigger switch an administrator assigns)
  classes/reform/     Reform's server side and its tests
  classes/rollup/     Rollup's engine and its tests
  classes/clone/      Clone's engine and its tests
  classes/import/     Import's engine and its tests
  classes/guides/     Tests that run the statements the framework's guides make
  classes/demo/       Demo, the print helper the demo scripts use
  lwc/                reformEntry, reformList, reformPanel, reformShowcase, importPanel (each with __tests__)
  objects/            Reform_Blueprint__c; Reform_Private_Sample__c (privately shared, for tests);
                      Rollup_Rule__mdt; Rollup_Sample_Parent__c and Rollup_Sample_Child__c; Clone_Step__mdt;
                      Import_Format__mdt and Import_Column__mdt
  customMetadata/     The six sample rollup rules, the two steps of the sample clone plan, and the two
                      sample import formats with their columns
  triggers/           AccountTrigger, ReformBlueprintTrigger, RollupSampleChildTrigger, RollupSampleParentTrigger
  customPermissions/  Bypass_Triggers, with a permission set of the same name
```

## Rules for subscriber code

These are all proven by code in this repository.

- Prefix every package type: `inj.IQuery`, `inj.BaseDomain`.
- Registry keys are `Account.class`, not `Account.SObjectType`.
- Query and domain classes are `global class`, with a `global` no-argument constructor. Hook overrides (`onBeforeUpsert`, `getDefaultFields`) can be `public override`.
- Reach inherited behaviour through `base()`: `base().records()`, `base().getChangedRecords(...)`.
- A trigger body is one line: `App.s.tf().execute();`
- To switch triggers off for some users, give the application a rule: `App.s.tf().disableWhen(new BypassTriggers())`. The rule reads the custom permission `Bypass_Triggers`, so an administrator assigns a permission set and nothing is deployed (`BypassTriggersTest`). Keep the rule a class of this org, so that the permission it reads is this org's own.
- Of the framework's exceptions only `inj.Application.FactoryException` and the utility classes' exceptions are global. Catch the others as `Exception`.
- The framework's utility classes are in the package: `inj.RandomUtil`, `inj.FieldUtil`, `inj.IdUtil` and the rest. Do not copy them here.
- A query made through the framework is run by the application's scheme. A scheme with a sharing keyword of its own decides whose records are seen; one without takes the sharing of the class that built the query (`GuideAccessTest`). `RollupScheme` is the example of a scheme declared `without sharing`.
- Text kept in a custom metadata field loses the spaces at its ends, and `getAll()` cuts a long text area off at 255 characters.
- Apex names are case-insensitive. A local `account` hides `Account`, a field `kind` hides an enum `Kind`, a parameter `json` hides `JSON`, a local `importer` hides the class `Importer`. `by` is a reserved word.
- To save what can be saved and learn what could not, set `work.options().optAllOrNone = false` and read `work.failures()` or `work.failureOf(record)` after `apply()`. `Importer` is the example. Do not call `Database.insert` to get at the results.
- CSV text is read with `inj.CsvUtil.read`, and text becomes a field's value with `inj.FieldUtil.fromText`. Do not write either here.
- A custom metadata relationship field (`Import_Column__mdt.Format__c`) holds the Id of the record it points at when read with `getAll()`.

`App.cls` shows the registries:

```apex
s = inj.Application.make(
    new Scheme64(),
    new Map<Type, Type>{ ExampleService.IService.class => ExampleService.class },   // services
    new Map<Type, Type>{ Reform_Blueprint__c.class => ReformBlueprintQuery.class }, // queries
    new Map<Type, Type>{ Reform_Blueprint__c.class => ReformBlueprints.class },     // domains
    new Map<Type, Type>{ Reform_Blueprint__c.class => ReformBlueprints.class,       // triggers
                         Rollup_Sample_Child__c.class => RollupHandler.class }
);
```

## Demo

`scripts/demo/` is the live demo: `seed.apex`, `reset.apex`, `01` to `07`, `play.apex`, sample CSVs in `data/`, and `run.py`, which runs a script with `sf apex run` and prints the lines written through `Demo`. Its `README.md` is the running order. When a solution's API or messages change, run the scripts again: they are not covered by the Apex tests. `run.py` contacts the org, so running it needs the same approval as any `sf` command.

## Orgs

- This repository deploys to the scratch org **`s-unify`** only. It is the default in `.sf/config.json`.
- Never deploy to `s-injectify` (the framework's org) or to any `ns-*` org.
- Do not run `sf org list`. Read `.sf/config.json` instead.
- Any `sf` command that contacts an org needs the user's explicit approval.

## Commands

The package must be installed in the org first. The version to install is the newest alias in `../injectify/sfdx-project.json`.

```bash
sf package install --package <04t id> --target-org s-unify --wait 20
sf project deploy start -d force-app --ignore-conflicts
sf apex test run -l RunLocalTests -c -w 30
```

- `sf` can exit 1 on success. Pass `--json` and read the result.
- Deploy when a feature is finished, not after each edit, and never while a test run is in progress.
- After deploying Apex, run all local tests.

Component tests need no org:

```bash
npm install --ignore-scripts --legacy-peer-deps --no-package-lock
npx sfdx-lwc-jest
```

## Tests

- Every Apex class has a test class, and every component a `__tests__` folder. Change them together.
- When a framework guide changes, the tests under `classes/guides/` are where its statements get checked.
- Keep `README.md` and the manifests (`reform.xml`, `rollup.xml`, `clone.xml`, `import.xml`) in step with the code.
