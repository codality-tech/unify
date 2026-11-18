@IsTest
private class ReformEngineTest {
  private static final String DEAL =
    '{"sobjectName":"Opportunity","label":"Deal","elements":[' +
    '{"field":{"name":"AccountId"}},' +
    '{"field":{"name":"Name","required":true}},' +
    '{"field":{"name":"CloseDate"}},' +
    '{"field":{"name":"Amount"}},' +
    '{"visible":"Amount > 1000","field":{"name":"NextStep","defaultValue":"Call the buyer"}},' +
    '{"visible":"AccountId != null","richtext":{"content":"Account: <b>{!Account.Name}</b>"}},' +
    '{"heading":{"content":"Deal worth {!Amount}"}}],' +
    '"parameters":[{"name":"StageName","fixedValue":"Prospecting"}]}';

  private static ReformEngine engineFor(String written) {
    return new ReformEngine(ReformPlan.compile(ReformDefinition.fromMap((Map<String, Object>) JSON.deserializeUntyped(written))));
  }

  // The example triggers on Account do work of their own; these tests are not about them.
  private static void quietAccountTriggers() {
    App.s.tf().disable(new List<SObjectType>{ Account.SObjectType });
    App.b.tf().disable();
  }

  private static Account company(String name) {
    quietAccountTriggers();
    Account made = new Account(Name = name);
    insert made;
    return made;
  }

  private static ReformView.Part fieldPart(ReformView.Form form, String name) {
    for (ReformView.Part part : form.parts) {
      if (part.name == name) {
        return part;
      }
    }
    Assert.fail('The form has no part for ' + name);
    return null;
  }

  @IsTest
  static void aNewFormAppliesDefaultsFixedValuesAndRules() {
    ReformView.Form blank = engineFor(DEAL).form(null, false);

    Assert.areEqual('Opportunity', blank.objectName);
    Assert.areEqual('Deal', blank.label);
    Assert.isNull(blank.recordId);
    Assert.isFalse(blank.saved);
    Assert.areEqual(8, blank.parts.size());

    ReformView.Part nextStep = fieldPart(blank, 'NextStep');
    Assert.areEqual('Call the buyer', nextStep.value, 'the default');
    Assert.isFalse(nextStep.visible, 'no amount yet, so the rule does not hold');
    Assert.areEqual('STRING', nextStep.dataType);

    ReformView.Part stage = fieldPart(blank, 'StageName');
    Assert.areEqual('PICKLIST', stage.dataType);
    Set<String> stages = new Set<String>();
    for (ReformView.Choice choice : stage.options) {
      Assert.isFalse(String.isBlank(choice.label));
      stages.add(choice.value);
    }
    Assert.isTrue(stages.contains('Prospecting'), 'a picklist comes with its values: ' + stages);
    Assert.areEqual('Account', fieldPart(blank, 'AccountId').lookupTo, 'a lookup says what it points at');
    Assert.isFalse(fieldPart(blank, 'AccountId').label.endsWithIgnoreCase(' ID'), 'and is labelled for the record, not its Id');
    Assert.isNull(fieldPart(blank, 'Name').options);
    Assert.areEqual('Prospecting', stage.value);
    Assert.isFalse(stage.visible, 'a fixed field is set, not shown');

    Assert.isTrue(fieldPart(blank, 'Amount').reactive);
    Assert.isTrue(fieldPart(blank, 'AccountId').reactive);
    Assert.isFalse(fieldPart(blank, 'Name').reactive);
    Assert.isTrue(fieldPart(blank, 'Name').required);
    Assert.isTrue(fieldPart(blank, 'Name').visible);
    Assert.isFalse(fieldPart(blank, 'Name').readOnly);

    Assert.areEqual('RICH_TEXT', blank.parts[5].kind);
    Assert.isFalse(blank.parts[5].visible);
    Assert.areEqual('Account: <b></b>', blank.parts[5].content);
    Assert.areEqual('HEADING', blank.parts[6].kind);
    Assert.areEqual('Deal worth ', blank.parts[6].content);
  }

  @IsTest
  static void aFormRecomputesFromTheValuesItIsSent() {
    Account acme = company('Acme & <Sons>');

    ReformView.Form filled = engineFor(DEAL)
      .form(
        new Map<String, Object>{
          'accountid' => acme.Id,
          'Amount' => 2500,
          'NextStep' => '',
          'Description' => 'not in the blueprint',
          'No_Such_Field__c' => 'ignored'
        },
        false
      );

    ReformView.Part nextStep = fieldPart(filled, 'NextStep');
    Assert.isTrue(nextStep.visible, 'the amount now passes the rule');
    Assert.isNull(nextStep.value, 'sent blank, so the default does not apply');
    Assert.areEqual(acme.Id, fieldPart(filled, 'AccountId').value, 'field names match in any case');
    Assert.isTrue(filled.parts[5].visible);
    Assert.areEqual('Account: <b>Acme &amp; &lt;Sons&gt;</b>', filled.parts[5].content, 'the parent is loaded, and its value escaped');
    Assert.isTrue(filled.parts[6].content.startsWith('Deal worth 2'), filled.parts[6].content);
    Assert.areEqual(0, [SELECT COUNT() FROM Opportunity], 'nothing is written until asked');
  }

  @IsTest
  static void savingWritesOnlyWhatTheBlueprintNames() {
    Account acme = company('Acme');

    ReformView.Form saved = engineFor(DEAL)
      .form(
        new Map<String, Object>{
          'AccountId' => acme.Id,
          'Name' => 'Big deal',
          'CloseDate' => '2030-01-15',
          'Amount' => 5000,
          'Description' => 'not in the blueprint',
          'Probability' => 99
        },
        true
      );

    Assert.isTrue(saved.saved);
    Assert.isNotNull(saved.recordId);
    Opportunity stored = [
      SELECT Name, StageName, Amount, NextStep, CloseDate, Description, AccountId
      FROM Opportunity
      WHERE Id = :saved.recordId
    ];
    Assert.areEqual('Big deal', stored.Name);
    Assert.areEqual('Prospecting', stored.StageName, 'the fixed value');
    Assert.areEqual('Call the buyer', stored.NextStep, 'the default');
    Assert.areEqual(Date.newInstance(2030, 1, 15), stored.CloseDate);
    Assert.areEqual(acme.Id, stored.AccountId);
    Assert.isNull(stored.Description, 'a field with no element is not written');

    Assert.isTrue(fieldPart(saved, 'NextStep').visible, 'the view after a save is the stored record\'s');
    Assert.areEqual('Call the buyer', fieldPart(saved, 'NextStep').value);
    Assert.areEqual('Account: <b>Acme</b>', saved.parts[5].content);
  }

  @IsTest
  static void aRequiredFieldLeftEmptyStopsTheSave() {
    try {
      engineFor(DEAL).form(new Map<String, Object>{ 'CloseDate' => '2030-01-15' }, true);
      Assert.fail('the name is required');
    } catch (ReformEngine.ReformException refused) {
      Assert.isTrue(refused.getMessage().startsWith('Required: '), refused.getMessage());
      Assert.isTrue(refused.getMessage().contains(Opportunity.Name.getDescribe().getLabel()), refused.getMessage());
    }
    Assert.areEqual(0, [SELECT COUNT() FROM Opportunity]);
  }

  @IsTest
  static void anExistingRecordIsShownEditedAndSaved() {
    Account acme = company('Acme');
    Opportunity existing = new Opportunity(
      Name = 'Old name',
      StageName = 'Qualification',
      CloseDate = Date.newInstance(2030, 1, 1),
      Amount = 10,
      AccountId = acme.Id,
      NextStep = 'Wait'
    );
    insert existing;
    ReformEngine engine = engineFor(DEAL);

    ReformView.Form opened = engine.form(new Map<String, Object>{ 'Id' => existing.Id }, false);
    Assert.areEqual(existing.Id, opened.recordId);
    Assert.areEqual('Old name', fieldPart(opened, 'Name').value);
    Assert.areEqual('Wait', fieldPart(opened, 'NextStep').value, 'defaults are for new records');
    Assert.isFalse(fieldPart(opened, 'NextStep').visible);
    Assert.areEqual('Account: <b>Acme</b>', opened.parts[5].content);

    ReformView.Form edited = engine.form(new Map<String, Object>{ 'Id' => existing.Id, 'Amount' => 9000 }, false);
    Assert.isTrue(fieldPart(edited, 'NextStep').visible, 'the unsaved amount passes the rule');
    Assert.isTrue([SELECT Amount FROM Opportunity WHERE Id = :existing.Id].Amount == 10, 'and is still unsaved');

    ReformView.Form saved = engine.form(new Map<String, Object>{ 'Id' => existing.Id, 'Amount' => 9000, 'Name' => 'New name' }, true);
    Assert.isTrue(saved.saved);
    Opportunity stored = [SELECT Name, Amount, StageName, NextStep FROM Opportunity WHERE Id = :existing.Id];
    Assert.areEqual('New name', stored.Name);
    Assert.isTrue(stored.Amount == 9000, 'the amount was ' + stored.Amount);
    Assert.areEqual('Prospecting', stored.StageName, 'the fixed value is written on every save');
    Assert.areEqual('Wait', stored.NextStep, 'what was not sent is left alone');
  }

  @IsTest
  static void aRecordThatIsNotThereIsReported() {
    Id nobody = Opportunity.SObjectType.getDescribe().getKeyPrefix() + '000000000001';
    try {
      engineFor(DEAL).form(new Map<String, Object>{ 'Id' => nobody }, false);
      Assert.fail('no such record');
    } catch (ReformEngine.ReformException missing) {
      Assert.isTrue(missing.getMessage().contains('does not exist'), missing.getMessage());
    }
  }

  @IsTest
  static void aTableListsFiltersSortsAndPages() {
    Account acme = company('Acme');
    Account globex = company('Globex');
    insert new List<Contact>{
      new Contact(LastName = 'Linus', Title = 'CTO', AccountId = globex.Id),
      new Contact(LastName = 'Ada', Title = 'CTO', AccountId = acme.Id),
      new Contact(LastName = 'Grace', Title = 'CEO', AccountId = acme.Id),
      new Contact(LastName = 'Zed', Title = 'CTO')
    };
    ReformEngine engine = engineFor(
      '{"sobjectName":"Contact","pluralLabel":"People",' +
        '"columns":[{"name":"LastName"},{"name":"Account.Name","label":"Company"},{"name":"Nope"}],' +
        '"filters":["Title = \'CTO\'"]}'
    );

    ReformView.Table first = engine.table(2, 0);

    Assert.areEqual('People', first.pluralLabel);
    Assert.isTrue(first.canCreate && first.canEdit && first.canDelete, 'nothing forbids it');
    Assert.areEqual(3, first.total, 'every match, not just this page');
    Assert.areEqual(2, first.rows.size());
    Assert.areEqual('Ada', first.rows[0].get('LastName'), 'sorted by the first column');
    Assert.areEqual('Acme', first.rows[0].get('Account.Name'), 'a column can cross a lookup');
    Assert.isNotNull(first.rows[0].get('Id'));
    Assert.areEqual('Linus', first.rows[1].get('LastName'));
    Assert.areEqual('Globex', first.rows[1].get('Account.Name'));
    Assert.areEqual(3, first.columns.size());
    Assert.areEqual('Company', first.columns[1].label);
    Assert.areEqual('STRING', first.columns[0].dataType);
    Assert.isFalse(first.columns[2].problems.isEmpty(), 'a bad column is reported and left out');
    Assert.isFalse(first.rows[0].containsKey('Nope'));

    ReformView.Table second = engine.table(2, 2);
    Assert.areEqual(1, second.rows.size());
    Assert.areEqual('Zed', second.rows[0].get('LastName'));
    Assert.isNull(second.rows[0].get('Account.Name'));

    ReformView.Table defaults = engine.table(null, -5);
    Assert.areEqual(50, defaults.pageSize);
    Assert.areEqual(0, defaults.skip);
    ReformView.Table capped = engine.table(5000, 99999);
    Assert.areEqual(200, capped.pageSize);
    Assert.areEqual(2000, capped.skip);
  }

  @IsTest
  static void aFixedValueFiltersTheTableAndPresetsTheForm() {
    Account acme = company('Acme');
    Account globex = company('Globex');
    insert new List<Contact>{ new Contact(LastName = 'Ada', AccountId = acme.Id), new Contact(LastName = 'Linus', AccountId = globex.Id) };
    ReformEngine engine = engineFor(
      '{"sobjectName":"Contact","elements":[{"field":{"name":"LastName"}}],"columns":[{"name":"LastName"}],' +
        '"parameters":[{"name":"AccountId","fixedValue":"' + acme.Id + '"}]}'
    );

    ReformView.Table listed = engine.table(null, null);
    Assert.areEqual(1, listed.total);
    Assert.areEqual('Ada', listed.rows[0].get('LastName'));

    ReformView.Form saved = engine.form(new Map<String, Object>{ 'LastName' => 'Grace', 'AccountId' => globex.Id }, true);
    Assert.areEqual(acme.Id, [SELECT AccountId FROM Contact WHERE Id = :saved.recordId].AccountId, 'fixed wins over what is sent');
    Assert.areEqual(2, engine.table(null, null).total);
  }

  @IsTest
  static void deletingRespectsTheBlueprint() {
    Account acme = company('Acme');
    List<Contact> people = new List<Contact>{ new Contact(LastName = 'Gone'), new Contact(LastName = 'Kept') };
    insert people;

    Assert.isFalse(engineFor('{"sobjectName":"Contact","deleteable":false}').table(1, 0).canDelete);
    engineFor('{"sobjectName":"Contact"}').remove(people[0].Id);
    Assert.areEqual(0, [SELECT COUNT() FROM Contact WHERE Id = :people[0].Id]);

    for (Integer attempt = 0; attempt < 3; attempt++) {
      try {
        if (attempt == 0) {
          engineFor('{"sobjectName":"Contact","deleteable":false}').remove(people[1].Id);
        } else if (attempt == 1) {
          engineFor('{"sobjectName":"Contact"}').remove(acme.Id);
        } else {
          engineFor('{"sobjectName":"Contact"}').remove(null);
        }
        Assert.fail('attempt ' + attempt);
      } catch (ReformEngine.ReformException refused) {
        Assert.isFalse(String.isBlank(refused.getMessage()));
      }
    }
    Assert.areEqual(1, [SELECT COUNT() FROM Contact WHERE Id = :people[1].Id]);
  }

  @IsTest
  static void theBlueprintCanForbidCreatingAndEditing() {
    ReformEngine readOnly = engineFor(
      '{"sobjectName":"Contact","createable":false,"updateable":false,"elements":[{"field":{"name":"LastName"}}]}'
    );
    Contact existing = new Contact(LastName = 'Ada');
    insert existing;

    for (Map<String, Object> sent : new List<Map<String, Object>>{
      new Map<String, Object>{ 'LastName' => 'New' },
      new Map<String, Object>{ 'Id' => existing.Id, 'LastName' => 'Changed' }
    }) {
      try {
        readOnly.form(sent, true);
        Assert.fail('the blueprint forbids it');
      } catch (ReformEngine.ReformException refused) {
        Assert.isTrue(refused.getMessage().startsWith('You cannot'), refused.getMessage());
      }
    }
    Assert.areEqual('Ada', [SELECT LastName FROM Contact WHERE Id = :existing.Id].LastName);
  }

  @IsTest
  static void anEngineNeedsAUsablePlan() {
    try {
      engineFor('{"sobjectName":"No_Such_Object__c"}');
      Assert.fail('no object');
    } catch (ReformEngine.ReformException refused) {
      Assert.isTrue(refused.getMessage().contains('No_Such_Object__c'), refused.getMessage());
    }
    try {
      new ReformEngine(null);
      Assert.fail('no plan');
    } catch (ReformEngine.ReformException refused) {
      Assert.areEqual('A plan is required', refused.getMessage());
    }
  }
}
