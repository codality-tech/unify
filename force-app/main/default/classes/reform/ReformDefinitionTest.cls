@IsTest
private class ReformDefinitionTest {
  private static Map<String, Object> untyped(String written) {
    return (Map<String, Object>) JSON.deserializeUntyped(written);
  }

  @IsTest
  static void readsEveryKindOfElementFromAMap() {
    ReformDefinition definition = ReformDefinition.fromMap(
      untyped(
        '{"name":"deal_form","sobjectName":" Opportunity ","label":"Deal","deleteable":false,' +
          '"elements":[' +
          '{"width":6,"visible":"Amount > 1000","field":{"name":"NextStep","label":"Next","required":true,"defaultValue":"Call","hidden":"false"}},' +
          '{"heading":{"content":"About {!Account.Name}"}},' +
          '{"richtext":"<b>a plain string</b>"},' +
          '{},' +
          '{"field":{"name":"Name"},"heading":{"content":"both"}}],' +
          '"columns":[{"name":"Account.Name","label":"Account"}],' +
          '"parameters":[{"name":"StageName","fixedValue":"Prospecting"}],' +
          '"filters":["StageName != \'Closed Lost\'","  "]}'
      )
    );

    Assert.areEqual('deal_form', definition.name);
    Assert.areEqual('Opportunity', definition.objectName, 'names are trimmed');
    Assert.areEqual('Deal', definition.label);
    Assert.areEqual(false, definition.deleteable);
    Assert.isNull(definition.createable, 'unset stays unset');
    Assert.isTrue(definition.problems.isEmpty());

    Assert.areEqual(5, definition.elements.size());
    ReformDefinition.Element field = definition.elements[0];
    Assert.areEqual(6, field.width);
    Assert.areEqual('Amount > 1000', field.showWhen);
    Assert.areEqual('NextStep', field.field.name);
    Assert.areEqual('Next', field.field.label);
    Assert.areEqual(true, field.field.required);
    Assert.areEqual(false, field.field.hidden, 'a flag may arrive as text');
    Assert.areEqual('Call', field.field.defaultValue);
    Assert.isNull(field.field.fixedValue);
    Assert.areEqual('About {!Account.Name}', definition.elements[1].heading);
    Assert.areEqual('<b>a plain string</b>', definition.elements[2].richText);
    ReformDefinition.Element spacer = definition.elements[3];
    Assert.isTrue(spacer.field == null && spacer.heading == null && spacer.richText == null && !spacer.conflicting);
    Assert.isTrue(definition.elements[4].conflicting);

    Assert.areEqual('Account.Name', definition.columns[0].name);
    Assert.areEqual('Account', definition.columns[0].label);
    Assert.areEqual('Prospecting', definition.parameters[0].fixedValue);
    Assert.areEqual(new List<String>{ 'StageName != \'Closed Lost\'' }, definition.filters, 'blank filters are dropped');
  }

  @IsTest
  static void readsMapsAsLightningSendsThem() {
    Map<Object, Object> looseField = new Map<Object, Object>{ 'name' => 'Phone', 'fixedValue' => '' };
    Map<Object, Object> looseElement = new Map<Object, Object>{ 'field' => looseField, 'width' => 4.0 };
    Map<Object, Object> textWidth = new Map<Object, Object>{ 'width' => '3' };
    Map<Object, Object> badWidth = new Map<Object, Object>{ 'width' => 'wide' };

    ReformDefinition definition = ReformDefinition.fromMap(
      new Map<String, Object>{ 'sobjectName' => 'Account', 'elements' => new List<Object>{ looseElement, textWidth, badWidth } }
    );

    Assert.areEqual('Phone', definition.elements[0].field.name);
    Assert.areEqual('', definition.elements[0].field.fixedValue, 'fixed to blank is not the same as not fixed');
    Assert.areEqual(4, definition.elements[0].width);
    Assert.areEqual(3, definition.elements[1].width);
    Assert.isNull(definition.elements[2].width);
    Assert.isTrue(ReformDefinition.fromMap(null).elements.isEmpty(), 'nothing sent is an empty definition');
  }

  @IsTest
  static void storedJsonThatCannotBeReadBecomesProblems() {
    Reform_Blueprint__c stored = new Reform_Blueprint__c(
      Api_Name__c = 'broken',
      Sobject_Name__c = 'Account',
      Label__c = 'Customer',
      Elements__c = '[{"field":',
      Columns__c = '{"name":"Name"}'
    );

    ReformDefinition definition = ReformDefinition.fromRecord(stored);

    Assert.areEqual('broken', definition.name);
    Assert.areEqual('Customer', definition.label);
    Assert.areEqual(2, definition.problems.size(), String.join(definition.problems, ' | '));
    Assert.isTrue(definition.problems[0].startsWith('Elements is not valid JSON'), definition.problems[0]);
    Assert.areEqual('Columns must be a JSON list', definition.problems[1]);
    Assert.isTrue(definition.elements.isEmpty() && definition.columns.isEmpty());
  }

  @IsTest
  static void aDefinitionLaidOverAnotherKeepsItsOwnValuesAndAddsTheLists() {
    ReformDefinition top = ReformDefinition.fromMap(untyped('{"name":"mine","label":"Mine","elements":[{}],"filters":["Name != null"]}'));
    ReformDefinition base = ReformDefinition.fromMap(
      untyped(
        '{"sobjectName":"Account","label":"Base","pluralLabel":"Bases","deleteable":true,' +
          '"elements":[{"field":{"name":"Name"}},{"field":{"name":"Phone"}}],"columns":[{"name":"Name"}]}'
      )
    );

    ReformDefinition laid = top.over(base);

    Assert.isTrue(laid === top);
    Assert.areEqual('Mine', laid.label);
    Assert.areEqual('Account', laid.objectName);
    Assert.areEqual('Bases', laid.pluralLabel);
    Assert.areEqual(true, laid.deleteable);
    Assert.areEqual(3, laid.elements.size());
    Assert.isNull(laid.elements[0].field, 'its own elements come first');
    Assert.areEqual(1, laid.columns.size());
    Assert.areEqual(1, laid.filters.size());
  }
}
