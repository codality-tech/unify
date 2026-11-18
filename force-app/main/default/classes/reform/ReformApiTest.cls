@IsTest
private class ReformApiTest {
  private static Map<String, Object> contactBlueprint() {
    return new Map<String, Object>{
      'sobjectName' => 'Contact',
      'elements' => new List<Object>{
        new Map<String, Object>{ 'field' => new Map<String, Object>{ 'name' => 'LastName' } },
        new Map<String, Object>{ 'field' => new Map<String, Object>{ 'name' => 'Title', 'defaultValue' => 'Engineer' } }
      },
      'columns' => new List<Object>{ new Map<String, Object>{ 'name' => 'LastName' } }
    };
  }

  @IsTest
  static void aComponentCanShowSaveListAndDelete() {
    ReformView.Form blank = ReformApi.form(contactBlueprint(), null, false);
    Assert.areEqual('Engineer', blank.parts[1].value);

    ReformView.Form saved = ReformApi.form(contactBlueprint(), new Map<String, Object>{ 'LastName' => 'Lovelace' }, true);
    Assert.isTrue(saved.saved);
    Assert.areEqual('Engineer', [SELECT Title FROM Contact WHERE Id = :saved.recordId].Title);

    ReformView.Table listed = ReformApi.table(contactBlueprint(), 10, 0);
    Assert.areEqual(1, listed.total);
    Assert.areEqual('Lovelace', listed.rows[0].get('LastName'));
    Assert.areEqual(1, ReformApi.tableWired(contactBlueprint(), null, null).total);

    ReformApi.remove(contactBlueprint(), saved.recordId);
    Assert.areEqual(0, [SELECT COUNT() FROM Contact]);
  }

  @IsTest
  static void aStoredBlueprintIsUsedByName() {
    insert new Reform_Blueprint__c(
      Name = 'People',
      Api_Name__c = 'people',
      Sobject_Name__c = 'Contact',
      Elements__c = '[{"field":{"name":"LastName"}}]',
      Columns__c = '[{"name":"LastName"}]'
    );
    insert new Contact(LastName = 'Hopper');

    ReformView.Table listed = ReformApi.table(new Map<String, Object>{ 'name' => 'people' }, null, null);

    Assert.areEqual('Contact', listed.objectName);
    Assert.areEqual('Hopper', listed.rows[0].get('LastName'));
  }

  @IsTest
  static void failuresReachTheComponentWithTheirMessage() {
    Map<String, Object> nowhere = new Map<String, Object>{ 'sobjectName' => 'No_Such_Object__c' };
    Map<String, Object> noName = new Map<String, Object>{ 'Title' => 'Engineer' };
    for (Integer attempt = 0; attempt < 4; attempt++) {
      try {
        if (attempt == 0) {
          ReformApi.form(nowhere, null, false);
        } else if (attempt == 1) {
          ReformApi.table(nowhere, null, null);
        } else if (attempt == 2) {
          ReformApi.remove(nowhere, null);
        } else {
          // LastName is required by the schema, and nothing was sent for it.
          ReformApi.form(contactBlueprint(), noName, true);
        }
        Assert.fail('attempt ' + attempt);
      } catch (AuraHandledException shown) {
        String expected = attempt == 3 ? 'Required: ' : 'There is no object named No_Such_Object__c';
        Assert.isTrue(shown.getMessage().contains(expected), shown.getMessage());
      }
    }
  }
}
