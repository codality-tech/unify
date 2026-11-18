@IsTest
private class ReformPlanTest {
  private static ReformPlan planFor(String written) {
    return ReformPlan.compile(ReformDefinition.fromMap((Map<String, Object>) JSON.deserializeUntyped(written)));
  }

  @IsTest
  static void resolvesFieldsRulesMergeFieldsAndColumns() {
    ReformPlan plan = planFor(
      '{"sobjectName":"Opportunity","label":"Deal","elements":[' +
        '{"field":{"name":"AccountId"}},' +
        '{"width":6,"field":{"name":"amount","label":"Deal size","required":true}},' +
        '{"width":40,"visible":"Amount > 1000","field":{"name":"NextStep","defaultValue":"Call"}},' +
        '{"heading":{"content":"About {!Account.Name}"}},' +
        '{"visible":"Account.Owner.IsActive = true","richtext":{"content":"Owner: {! Account.Owner.Name }"}},' +
        '{}],' +
        '"columns":[{"name":"Name"},{"name":"Account.Owner.Name","label":"Account owner"}],' +
        '"parameters":[{"name":"StageName","fixedValue":"Prospecting"},{"name":"Amount","defaultValue":"5"}],' +
        '"filters":["Amount > 0"]}'
    );

    Assert.isTrue(plan.isUsable());
    Assert.isTrue(plan.allProblems().isEmpty(), String.join(plan.allProblems(), ' | '));
    Assert.areEqual('Deal', plan.label);
    Assert.areEqual(Opportunity.SObjectType.getDescribe().getLabelPlural(), plan.pluralLabel, 'labels default to the object\'s');
    Assert.areEqual(7, plan.parts.size(), 'six elements, and a part for the parameter that had none');

    ReformPlan.Part accountPart = plan.parts[0];
    Assert.areEqual(ReformPlan.Kind.FIELD, accountPart.kind);
    Assert.areEqual(Opportunity.AccountId, accountPart.field);
    Assert.isTrue(accountPart.reactive, 'a merge field and a rule read through it');
    Assert.areEqual(12, accountPart.width);

    ReformPlan.Part amount = plan.parts[1];
    Assert.isTrue(amount === plan.partFor(Opportunity.Amount));
    Assert.areEqual('Deal size', amount.label);
    Assert.isTrue(amount.required);
    Assert.areEqual(6, amount.width);
    Assert.isTrue(amount.reactive, 'a rule reads it');
    Assert.isTrue(amount.hasDefault, 'the parameter adjusted the element');
    Assert.isTrue((Decimal) amount.defaultValue == 5, 'text becomes the field\'s type: ' + amount.defaultValue);

    ReformPlan.Part nextStep = plan.parts[2];
    Assert.areEqual(12, nextStep.width, 'a width off the grid falls back to full');
    Assert.isNotNull(nextStep.showWhen);
    Assert.areEqual('Call', nextStep.defaultValue);
    Assert.isFalse(nextStep.reactive);
    Assert.isFalse(nextStep.required, 'not required by the schema');

    Assert.areEqual(ReformPlan.Kind.HEADING, plan.parts[3].kind);
    Assert.areEqual(new Set<String>{ '{!Account.Name}' }, plan.parts[3].mergePaths.keySet());
    Assert.areEqual(ReformPlan.Kind.RICH_TEXT, plan.parts[4].kind);
    Assert.areEqual('Account.Owner.Name', plan.parts[4].mergePaths.get('{! Account.Owner.Name }').name());
    Assert.areEqual(ReformPlan.Kind.SPACER, plan.parts[5].kind);

    ReformPlan.Part stage = plan.parts[6];
    Assert.areEqual(Opportunity.StageName, stage.field);
    Assert.isTrue(stage.isFixed);
    Assert.areEqual('Prospecting', stage.fixedValue);

    Assert.areEqual(new Set<SObjectField>{ Opportunity.AccountId, Opportunity.Amount }, plan.fieldsRead);
    Assert.areEqual(new Set<SObjectField>{ Opportunity.AccountId }, plan.parentPaths.keySet());
    Set<String> fromTheAccount = new Set<String>();
    for (inj.IPath path : plan.parentPaths.get(Opportunity.AccountId)) {
      Assert.areEqual(Account.SObjectType, path.source().token(), 'seen from the parent');
      fromTheAccount.add(path.name());
    }
    Assert.areEqual(new Set<String>{ 'Name', 'Owner.Name', 'Owner.IsActive' }, fromTheAccount);

    Assert.areEqual('Name', plan.columns[0].name);
    Assert.areEqual('Account.Owner.Name', plan.columns[1].name);
    Assert.areEqual('Account owner', plan.columns[1].label);

    Assert.areEqual(2, plan.rowConditions.size(), 'the filter and the fixed value');
    inj.IQuery listed = plan.model.query();
    for (inj.ICondition condition : plan.rowConditions) {
      listed.addCondition(condition);
    }
    String soql = listed.toSoql();
    Assert.isTrue(soql.contains('Amount > 0'), soql);
    Assert.isTrue(soql.contains('StageName = \'Prospecting\''), soql);
  }

  @IsTest
  static void mistakesBecomeProblemsThatSayWhereTheyAre() {
    ReformPlan plan = planFor(
      '{"sobjectName":"Account","recordTypeDeveloperName":"No_Such_Type","elements":[' +
        '{"field":{"name":"No_Such_Field__c"}},' +
        '{"field":{"name":"Name"}},' +
        '{"field":{"name":"Name"}},' +
        '{"visible":"Name = = =","heading":{"content":"A heading"}},' +
        '{"richtext":{"content":"{!Owner.Nope}"}},' +
        '{"heading":{"content":""}},' +
        '{"field":{"name":"NumberOfEmployees","defaultValue":"many"}},' +
        '{"field":{"name":"Phone"},"heading":{"content":"both"}}],' +
        '"columns":[{"name":"Nope.Name"},{"name":"Name"}],"filters":["((("]}'
    );

    List<String> problems = plan.allProblems();
    String all = String.join(problems, ' | ');
    Assert.isTrue(plan.isUsable(), 'the object resolved, so the rest still renders');
    Assert.areEqual(10, problems.size(), all);
    Assert.isTrue(all.contains('Account has no record type No_Such_Type'), all);
    Assert.isTrue(all.contains('Element 1: Account has no field named No_Such_Field__c'), all);
    Assert.isTrue(all.contains('Element 3: Name already has an element'), all);
    Assert.isTrue(all.contains('Element 4: Cannot read the visible rule'), all);
    Assert.isTrue(all.contains('Element 5: {!Owner.Nope} is not a field path on Account'), all);
    Assert.isTrue(all.contains('Element 6: Content must not be blank'), all);
    Assert.isTrue(all.contains('Element 7: defaultValue "many" is not a valid'), all);
    Assert.isTrue(all.contains('Element 8: An element holds one of'), all);
    Assert.isTrue(all.contains('Column 1: Nope.Name is not a field path on Account'), all);
    Assert.isTrue(all.contains('Cannot read the filter rule'), all);

    Assert.isFalse(plan.parts[0].usable());
    Assert.isTrue(plan.parts[1].usable());
    Assert.areEqual(ReformPlan.Kind.INVALID, plan.parts[7].kind);
    Assert.isTrue(plan.rowConditions.isEmpty());
  }

  @IsTest
  static void aBlueprintNeedsARealObject() {
    ReformPlan unknown = planFor('{"sobjectName":"No_Such_Object__c","elements":[{"field":{"name":"Name"}}]}');
    Assert.isFalse(unknown.isUsable());
    Assert.areEqual(new List<String>{ 'There is no object named No_Such_Object__c' }, unknown.allProblems());
    Assert.isTrue(unknown.parts.isEmpty());

    ReformPlan unnamed = planFor('{}');
    Assert.isFalse(unnamed.isUsable());
    Assert.areEqual(1, unnamed.problems.size());
  }

  @IsTest
  static void withNoColumnsATableShowsTheNameAndTheDates() {
    ReformPlan plan = planFor('{"sobjectName":"Contact"}');

    List<String> names = new List<String>();
    for (ReformPlan.Column column : plan.columns) {
      Assert.isTrue(column.problems.isEmpty());
      names.add(column.name);
    }
    Assert.areEqual(new List<String>{ 'Name', 'CreatedDate', 'LastModifiedDate' }, names);

    ReformPlan renamed = planFor('{"sobjectName":"Contact","namingField":"Email"}');
    Assert.areEqual('Email', renamed.columns[0].name);
  }

  @IsTest
  static void fixedAndDefaultValuesTakeTheFieldsType() {
    ReformPlan plan = planFor(
      '{"sobjectName":"Opportunity","elements":[' +
        '{"field":{"name":"IsPrivate","fixedValue":"true"}},' +
        '{"field":{"name":"CloseDate","defaultValue":"2030-01-15"}},' +
        '{"field":{"name":"Probability","defaultValue":"12.5"}},' +
        '{"field":{"name":"Description","fixedValue":""}}]}'
    );

    Assert.isTrue(plan.allProblems().isEmpty(), String.join(plan.allProblems(), ' | '));
    Assert.areEqual(true, plan.parts[0].fixedValue);
    Assert.areEqual(Date.newInstance(2030, 1, 15), plan.parts[1].defaultValue);
    Assert.areEqual(12.5, plan.parts[2].defaultValue);
    Assert.isTrue(plan.parts[3].isFixed, 'fixed to blank');
    Assert.isNull(plan.parts[3].fixedValue);
  }
}
