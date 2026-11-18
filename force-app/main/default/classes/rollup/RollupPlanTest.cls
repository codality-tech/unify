/** What a plan says is wrong with a rule, and what it decides ahead of time for a rule that is right. */
@IsTest
private class RollupPlanTest {
  private static RollupRule rule() {
    return new RollupRule('Rule').children(Rollup_Sample_Child__c.Parent__c);
  }

  private static RollupRule counting() {
    return rule().count().writeTo(Rollup_Sample_Parent__c.Child_Count__c);
  }

  private static String problemsOf(RollupRule checked) {
    return String.join(RollupPlan.compile(checked).problems, '; ');
  }

  @IsTest
  static void aRuleThatIsRightHasNoProblems() {
    RollupPlan plan = RollupPlan.compile(
      rule().sum(Rollup_Sample_Child__c.Amount__c).matching('Status__c != \'Closed\'').writeTo(Rollup_Sample_Parent__c.Open_Amount__c)
    );

    Assert.isTrue(plan.isSound(), String.join(plan.problems, '; '));
    Assert.areEqual(Rollup_Sample_Child__c.SObjectType, plan.child.token());
    Assert.areEqual(Rollup_Sample_Parent__c.SObjectType, plan.parent.token(), 'the parent is what the lookup points at');
    Assert.areEqual(
      new Set<SObjectField>{ Rollup_Sample_Child__c.Parent__c, Rollup_Sample_Child__c.Amount__c, Rollup_Sample_Child__c.Status__c },
      plan.watched,
      'the lookup, the source, and what the filter reads'
    );
  }

  @IsTest
  static void namesThatDoNotResolveAreReported() {
    RollupRule noChild = counting();
    noChild.childObject = 'Nope__c';
    Assert.areEqual('Unknown child object: Nope__c', problemsOf(noChild));

    RollupRule noLookup = counting();
    noLookup.lookupField = null;
    Assert.areEqual('The rule has no lookup field', problemsOf(noLookup));

    RollupRule wrongLookup = counting();
    wrongLookup.lookupField = 'Nope__c';
    Assert.areEqual('Rollup_Sample_Child__c has no field Nope__c', problemsOf(wrongLookup));

    RollupRule wrongTarget = counting();
    wrongTarget.parentField = 'Nope__c';
    Assert.areEqual('Rollup_Sample_Parent__c has no field Nope__c', problemsOf(wrongTarget));

    RollupRule wrongSource = counting();
    wrongSource.sourceField = 'Nope__c';
    Assert.areEqual('Rollup_Sample_Child__c has no field Nope__c', problemsOf(wrongSource));
  }

  @IsTest
  static void aLookupMustPointAtOneObject() {
    RollupRule notALookup = counting();
    notALookup.lookupField = 'Amount__c';
    Assert.areEqual('Rollup_Sample_Child__c.Amount__c is not a lookup', problemsOf(notALookup));

    RollupRule manyTargets = new RollupRule('Rule').children(Task.WhatId).count().writeTo(Account.NumberOfEmployees);
    Assert.areEqual('Task.WhatId can point at more than one object, which a rollup cannot follow', problemsOf(manyTargets));
  }

  @IsTest
  static void theOperationMustSuitItsFields() {
    RollupRule noOperation = rule().writeTo(Rollup_Sample_Parent__c.Child_Count__c);
    Assert.areEqual('The rule has no operation', problemsOf(noOperation));

    RollupRule noSource = counting();
    noSource.operation = unif.Enums.Aggregate.SUM;
    Assert.areEqual('SUM needs a source field', problemsOf(noSource));

    Assert.areEqual(
      'Rollup_Sample_Child__c.Kind__c is not a number, so it cannot be summed or averaged',
      problemsOf(rule().sum(Rollup_Sample_Child__c.Kind__c).writeTo(Rollup_Sample_Parent__c.Open_Amount__c))
    );
    Assert.areEqual(
      'Rollup_Sample_Parent__c.Earliest_Due__c must be a number field to hold a count',
      problemsOf(rule().count().writeTo(Rollup_Sample_Parent__c.Earliest_Due__c))
    );
    Assert.areEqual(
      'Rollup_Sample_Parent__c.Earliest_Due__c must be a number field to hold a sum or an average',
      problemsOf(rule().avg(Rollup_Sample_Child__c.Amount__c).writeTo(Rollup_Sample_Parent__c.Earliest_Due__c))
    );
    Assert.areEqual(
      'Rollup_Sample_Parent__c.Child_Count__c must hold the same kind of value as Rollup_Sample_Child__c.Due__c',
      problemsOf(rule().max(Rollup_Sample_Child__c.Due__c).writeTo(Rollup_Sample_Parent__c.Child_Count__c))
    );
    Assert.areEqual(
      'Rollup_Sample_Parent__c.Earliest_Due__c must hold the same kind of value as Rollup_Sample_Child__c.CreatedDate',
      problemsOf(rule().max(Rollup_Sample_Child__c.CreatedDate).writeTo(Rollup_Sample_Parent__c.Earliest_Due__c)),
      'a date field does not hold a date and time'
    );
  }

  @IsTest
  static void fieldsThatCannotBeAggregatedOrWrittenAreReported() {
    Assert.areEqual(
      'Contact.Description cannot be aggregated',
      problemsOf(new RollupRule('Rule').children(Contact.AccountId).max(Contact.Description).writeTo(Account.Description))
    );
    Assert.areEqual(
      'Rollup_Sample_Child__c.Former_Parent__c has no smallest or largest value',
      problemsOf(rule().max(Rollup_Sample_Child__c.Former_Parent__c).writeTo(Rollup_Sample_Parent__c.Name))
    );
    String autoNumbered = problemsOf(new RollupRule('Rule').children(CaseComment.ParentId).count().writeTo(Case.CaseNumber));
    Assert.isTrue(autoNumbered.contains('Case.CaseNumber is worked out by Salesforce and cannot be written'), autoNumbered);
  }

  @IsTest
  static void aFilterThatCannotBeReadIsReported() {
    Assert.isTrue(problemsOf(counting().matching('Status__c =')).startsWith('Filter: '), problemsOf(counting().matching('Status__c =')));
    Assert.isTrue(problemsOf(counting().matching('Nope__c = 1')).startsWith('Filter: '), problemsOf(counting().matching('Nope__c = 1')));
  }

  @IsTest
  static void aFilterOnTheChildsOwnFieldsIsTestedOnTheRecord() {
    RollupPlan plan = RollupPlan.compile(counting().matching('Status__c != \'Closed\' AND Amount__c > 0'));

    Assert.isTrue(plan.mayCount(new Rollup_Sample_Child__c(Status__c = 'Open', Amount__c = 1)));
    Assert.isFalse(plan.mayCount(new Rollup_Sample_Child__c(Status__c = 'Closed', Amount__c = 1)));
    Assert.isFalse(plan.mayCount(new Rollup_Sample_Child__c(Status__c = 'Open', Amount__c = 0)));
    Assert.isTrue(RollupPlan.compile(counting()).mayCount(new Rollup_Sample_Child__c()), 'no filter: every child counts');
  }

  @IsTest
  static void aFilterThroughALookupIsLeftToTheQuery() {
    RollupPlan plan = RollupPlan.compile(counting().matching('Former_Parent__r.Name = \'Archive\''));

    Assert.isTrue(plan.isSound(), String.join(plan.problems, '; '));
    Assert.isTrue(plan.mayCount(new Rollup_Sample_Child__c()), 'the related record is not loaded in a trigger, so the record cannot be ruled out');
    Assert.isTrue(plan.watched.contains(Rollup_Sample_Child__c.Former_Parent__c), 'the lookup the filter reads through is watched');
  }

  @IsTest
  static void rulesThatReadTheSameChildrenShareAQuery() {
    RollupPlan one = RollupPlan.compile(counting().matching('Status__c = \'Open\''));
    RollupPlan two = RollupPlan.compile(rule().sum(Rollup_Sample_Child__c.Amount__c).matching('  Status__c = \'Open\' ').writeTo(Rollup_Sample_Parent__c.Open_Amount__c));
    RollupPlan other = RollupPlan.compile(counting().matching('Status__c = \'Closed\''));

    Assert.areEqual(one.queryKey(), two.queryKey());
    Assert.areNotEqual(one.queryKey(), other.queryKey());
    Assert.areNotEqual(one.functionKey(), two.functionKey());
    Assert.areEqual('COUNT(Id)', one.function().toSoql());
    Assert.areEqual('SUM(Amount__c)', two.function().toSoql());
  }

  @IsTest
  static void aResultIsFittedToTheParentField() {
    RollupPlan average = RollupPlan.compile(rule().avg(Rollup_Sample_Child__c.Amount__c).writeTo(Rollup_Sample_Parent__c.Average_Amount__c));
    Assert.areEqual(3.33, average.fit(Decimal.valueOf(10) / 3), 'rounded to the field\'s two decimal places');
    Assert.isNull(average.fit(null), 'an average of nothing is blank');
    Assert.isTrue(average.same(5, 5.00));
    Assert.isTrue(average.same(5L, 5.00), 'whatever kind of number the platform hands back');
    Double half = 2.5;
    Assert.areEqual(2.50, average.fit(half));
    Assert.isFalse(average.same(null, 0));
    Assert.isTrue(average.same(null, null));

    RollupPlan whole = RollupPlan.compile(new RollupRule('Rule').children(Contact.AccountId).count().writeTo(Account.NumberOfEmployees));
    Assert.isTrue(whole.fit(2.6) instanceof Integer, 'a whole-number field is given a whole number');
    Assert.areEqual(3, whole.fit(2.6));
    Assert.areEqual(0, whole.fit(null), 'a count of nothing is 0');

    RollupPlan earliest = RollupPlan.compile(rule().min(Rollup_Sample_Child__c.Due__c).writeTo(Rollup_Sample_Parent__c.Earliest_Due__c));
    Date someDay = Date.newInstance(2030, 1, 15);
    Assert.areEqual(someDay, earliest.fit(someDay));
    Assert.isTrue(earliest.same(someDay, Date.newInstance(2030, 1, 15)));
    Assert.isFalse(earliest.same(someDay, someDay.addDays(1)));
  }

  @IsTest
  static void aParentHoldsSomethingWhenItsResultIsAboveZeroOrNotBlank() {
    RollupPlan count = RollupPlan.compile(counting());
    Assert.isTrue(count.holdsSomething(new Rollup_Sample_Parent__c(Child_Count__c = 2)));
    Assert.isFalse(count.holdsSomething(new Rollup_Sample_Parent__c(Child_Count__c = 0)));
    Assert.isFalse(count.holdsSomething(new Rollup_Sample_Parent__c()));

    RollupPlan earliest = RollupPlan.compile(rule().min(Rollup_Sample_Child__c.Due__c).writeTo(Rollup_Sample_Parent__c.Earliest_Due__c));
    Assert.isTrue(earliest.holdsSomething(new Rollup_Sample_Parent__c(Earliest_Due__c = Date.today())));
  }
}
