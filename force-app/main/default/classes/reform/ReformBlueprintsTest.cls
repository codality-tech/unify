@IsTest
private class ReformBlueprintsTest {
  private static Reform_Blueprint__c dealForm() {
    return new Reform_Blueprint__c(
      Name = 'Deal form',
      Api_Name__c = 'Deal_Form',
      Sobject_Name__c = 'Opportunity',
      Label__c = 'Deal',
      Elements__c = '[{"field":{"name":"Name"}},{"visible":"Amount > 1000","field":{"name":"NextStep"}}]',
      Columns__c = '[{"name":"Name"},{"name":"Account.Name"}]'
    );
  }

  @IsTest
  static void aBlueprintWithMistakesCannotBeSaved() {
    Reform_Blueprint__c mistaken = dealForm();
    mistaken.Elements__c = '[{"field":{"name":"No_Such_Field__c"}},{"visible":"Amount >","field":{"name":"NextStep"}}]';

    try {
      insert mistaken;
      Assert.fail('two elements cannot be resolved');
    } catch (DmlException refused) {
      Assert.isTrue(refused.getMessage().contains('Element 1: Opportunity has no field named No_Such_Field__c'), refused.getMessage());
      Assert.isTrue(refused.getMessage().contains('Element 2: Cannot read the visible rule'), refused.getMessage());
    }
    Assert.areEqual(0, [SELECT COUNT() FROM Reform_Blueprint__c]);
  }

  @IsTest
  static void onlyAChangedDefinitionIsCheckedAgain() {
    Reform_Blueprint__c blueprint = dealForm();
    insert blueprint;

    blueprint.Label__c = 'Renamed';
    update blueprint;

    blueprint.Columns__c = '[{"name":"Nope"}]';
    try {
      update blueprint;
      Assert.fail('the column cannot be resolved');
    } catch (DmlException refused) {
      Assert.isTrue(refused.getMessage().contains('Column 1: Nope is not a field path on Opportunity'), refused.getMessage());
    }
    Assert.areEqual('Renamed', [SELECT Label__c FROM Reform_Blueprint__c WHERE Id = :blueprint.Id].Label__c);
  }

  @IsTest
  static void aStoredBlueprintIsFoundByNameInAnyCase() {
    insert dealForm();

    Map<String, Reform_Blueprint__c> found = ReformBlueprints.stored(new Set<String>{ 'DEAL_FORM', 'nobody' });

    Assert.areEqual(new Set<String>{ 'deal_form' }, found.keySet());
    Assert.areEqual('Opportunity', found.get('deal_form').Sobject_Name__c);
    Assert.isNotNull(found.get('deal_form').Elements__c, 'the query class selects what a definition is read from');
  }

  @IsTest
  static void whatIsSentIsLaidOverTheStoredBlueprintItNames() {
    insert dealForm();

    ReformDefinition resolved = ReformDefinition.resolve(
      new Map<String, Object>{ 'name' => 'deal_form', 'label' => 'My deal', 'filters' => new List<Object>{ 'Amount > 0' } }
    );

    Assert.areEqual('Opportunity', resolved.objectName, 'from the stored blueprint');
    Assert.areEqual('My deal', resolved.label, 'what is sent wins');
    Assert.areEqual(2, resolved.elements.size());
    Assert.areEqual(2, resolved.columns.size());
    Assert.areEqual(1, resolved.filters.size());

    ReformDefinition unstored = ReformDefinition.resolve(new Map<String, Object>{ 'name' => 'nobody', 'sobjectName' => 'Account' });
    Assert.areEqual('Account', unstored.objectName, 'a name with nothing stored behind it is just a name');
    Assert.isTrue(unstored.elements.isEmpty());
  }

  @IsTest
  static void problemsAreReportedByPosition() {
    Reform_Blueprint__c mistaken = dealForm();
    mistaken.Sobject_Name__c = 'No_Such_Object__c';

    Map<Integer, List<String>> found = new ReformBlueprints(new List<Reform_Blueprint__c>{ dealForm(), mistaken }).problems();

    Assert.areEqual(new Set<Integer>{ 1 }, found.keySet());
    Assert.areEqual(new List<String>{ 'There is no object named No_Such_Object__c' }, found.get(1));
  }
}
