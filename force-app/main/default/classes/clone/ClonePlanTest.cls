/** What a plan says is wrong with its steps, and what it decides ahead of time for steps that are right. */
@IsTest
private class ClonePlanTest {
  private static CloneStep firm() {
    return new CloneStep('Firm').copying(Account.SObjectType);
  }

  private static CloneStep people() {
    return new CloneStep('People').under('Firm', Contact.AccountId);
  }

  private static String problemsOf(List<CloneStep> steps) {
    return String.join(ClonePlan.compile('Firm', steps).problems, '; ');
  }

  @IsTest
  static void aPlanIsATreeOfItsSteps() {
    ClonePlan plan = ClonePlan.compile(
      'Firm',
      new List<CloneStep>{
        people(),
        new CloneStep('Roles').under('Deals', OpportunityContactRole.OpportunityId),
        firm(),
        new CloneStep('Deals').under('Firm', Opportunity.AccountId),
        new CloneStep('Elsewhere').copying(Lead.SObjectType)
      }
    );

    Assert.isTrue(plan.isSound(), String.join(plan.problems, '; '));
    Assert.areEqual(Account.SObjectType, plan.root.model.token());
    Assert.isNull(plan.root.lookup);
    Assert.areEqual(2, plan.root.children.size());
    List<String> order = new List<String>();
    for (ClonePlan.Node node : plan.nodes()) {
      order.add(node.step.name);
    }
    Assert.areEqual(new List<String>{ 'Firm', 'People', 'Deals', 'Roles' }, order, 'the steps of this plan only, each after the one above it');
    Assert.areEqual(OpportunityContactRole.OpportunityId, plan.nodes()[3].lookup);
    Assert.areEqual('Deals', plan.nodes()[3].above.step.name);
  }

  @IsTest
  static void aPlanMustStartAtAStepWithNoParent() {
    Assert.areEqual('There is no step named Firm', problemsOf(new List<CloneStep>{ people() }));
    Assert.areEqual(
      'People does not start a plan: it sits under Firm',
      String.join(ClonePlan.compile('People', new List<CloneStep>{ firm(), people() }).problems, '; ')
    );
  }

  @IsTest
  static void namesThatDoNotResolveAreReportedWithTheirStep() {
    CloneStep noObject = firm();
    noObject.objectName = 'Nope__c';
    Assert.areEqual('Step Firm: unknown object Nope__c', problemsOf(new List<CloneStep>{ noObject, people() }), 'and the steps beneath are not looked at');

    CloneStep noLookup = people();
    noLookup.lookupField = null;
    Assert.areEqual('Step People: it has no lookup field to tie it to Firm', problemsOf(new List<CloneStep>{ firm(), noLookup }));

    CloneStep wrongLookup = people();
    wrongLookup.lookupField = 'Nope__c';
    Assert.areEqual('Step People: Contact has no field Nope__c', problemsOf(new List<CloneStep>{ firm(), wrongLookup }));

    CloneStep elsewhere = people();
    elsewhere.lookupField = 'ReportsToId';
    Assert.areEqual('Step People: Contact.ReportsToId does not point at Account', problemsOf(new List<CloneStep>{ firm(), elsewhere }));

    CloneStep skipsNothing = firm();
    skipsNothing.leaveOut = 'Rating, Nope__c';
    Assert.areEqual('Step Firm: Account has no field Nope__c', problemsOf(new List<CloneStep>{ skipsNothing }));
  }

  @IsTest
  static void filtersAreReadAndBelongBeneathTheStart() {
    Assert.areEqual(
      'Step Firm: the step that starts a plan takes no filter: the records to copy are named when the plan is run',
      problemsOf(new List<CloneStep>{ firm().matching('Rating = \'Hot\'') })
    );
    String unreadable = problemsOf(new List<CloneStep>{ firm(), people().matching('Email =') });
    Assert.isTrue(unreadable.startsWith('Step People: filter: '), unreadable);
    String unknown = problemsOf(new List<CloneStep>{ firm(), people().matching('Nope__c = 1') });
    Assert.isTrue(unknown.startsWith('Step People: filter: '), unknown);

    ClonePlan sound = ClonePlan.compile('Firm', new List<CloneStep>{ firm(), people().matching('Email != NULL AND Account.Rating = \'Hot\'') });
    Assert.isTrue(sound.isSound(), String.join(sound.problems, '; '));
    Assert.isNotNull(sound.nodes()[1].filter);
  }

  @IsTest
  static void valuesAreFieldsSetWithEqualsAndJoinedByAnd() {
    ClonePlan plan = ClonePlan.compile(
      'Firm',
      new List<CloneStep>{ firm().setting('Rating = \'Cold\' AND NumberOfEmployees = 12 AND AnnualRevenue = 1.5 AND Industry = NULL') }
    );
    Assert.isTrue(plan.isSound(), String.join(plan.problems, '; '));
    Map<SObjectField, Object> values = plan.root.values;
    Assert.areEqual('Cold', values.get(Account.Rating));
    Assert.isTrue(values.get(Account.NumberOfEmployees) instanceof Integer, 'a whole-number field is given a whole number');
    Assert.areEqual(12, values.get(Account.NumberOfEmployees));
    Assert.areEqual(1.5, values.get(Account.AnnualRevenue));
    Assert.isTrue(values.containsKey(Account.Industry), 'set to nothing, which is not the same as not set');
    Assert.isNull(values.get(Account.Industry));

    String notPlain = 'Step Firm: values must be fields of Account set with = and joined by AND';
    Assert.areEqual(notPlain, problemsOf(new List<CloneStep>{ firm().setting('Rating = \'Cold\' OR Rating = \'Hot\'') }));
    Assert.areEqual(notPlain, problemsOf(new List<CloneStep>{ firm().setting('NumberOfEmployees > 5') }));
    Assert.areEqual(notPlain, problemsOf(new List<CloneStep>{ firm().setting('NOT (Rating = \'Cold\')') }));
    Assert.areEqual(notPlain, problemsOf(new List<CloneStep>{ firm().setting('Owner.Name = \'Someone\'') }));
    String unreadable = problemsOf(new List<CloneStep>{ firm().setting('Rating =') });
    Assert.isTrue(unreadable.startsWith('Step Firm: values: '), unreadable);
    Assert.areEqual(
      'Step People: values: Birthdate takes a date such as 2026-12-31, not the date literal TODAY',
      problemsOf(new List<CloneStep>{ firm(), people().setting('Birthdate = TODAY') })
    );
  }

  @IsTest
  static void aCopyTakesWhatCanBeFilledInOnANewRecord() {
    ClonePlan plan = ClonePlan.compile(
      'Blueprint',
      new List<CloneStep>{ new CloneStep('Blueprint').copying(Reform_Blueprint__c.SObjectType).leavingOut(new Set<SObjectField>{ Reform_Blueprint__c.Label__c }) }
    );
    Set<SObjectField> copied = plan.root.copiedFields();

    Assert.isTrue(copied.contains(Reform_Blueprint__c.Name));
    Assert.isTrue(copied.contains(Reform_Blueprint__c.Sobject_Name__c));
    Assert.isFalse(copied.contains(Reform_Blueprint__c.Label__c), 'left out by the step');
    Assert.isFalse(copied.contains(Reform_Blueprint__c.Api_Name__c), 'a field that must be unique cannot be copied');
    Assert.isFalse(copied.contains(Reform_Blueprint__c.OwnerId), 'the copy belongs to whoever makes it');
    Assert.isFalse(copied.contains(Reform_Blueprint__c.Id));
    Assert.isFalse(copied.contains(Reform_Blueprint__c.CreatedDate));
  }

  @IsTest
  static void aCopyIsANewRecordLikeItsOriginal() {
    ClonePlan plan = ClonePlan.compile(
      'Firm',
      new List<CloneStep>{ firm().suffixed(' II').setting('Rating = \'Cold\''), people().suffixed(' II') }
    );
    Account original = new Account(Id = inj.IdUtil.generateId(Account.SObjectType), Name = 'Acme', Rating = 'Hot', Industry = 'Energy');
    Contact person = new Contact(Id = inj.IdUtil.generateId(Contact.SObjectType), LastName = 'Ada', AccountId = original.Id);

    Account copy = (Account) plan.root.copyOf(original);
    Contact personCopy = (Contact) plan.nodes()[1].copyOf(person);

    Assert.isNull(copy.Id);
    Assert.areEqual('Acme II', copy.Name);
    Assert.areEqual('Cold', copy.Rating);
    Assert.areEqual('Energy', copy.Industry);
    Assert.areEqual('Hot', original.Rating, 'the original is not touched');
    Assert.isNull(personCopy.AccountId, 'the tie to the parent is left for the unit of work, which knows the parent\'s copy');
    Assert.areEqual('Ada', personCopy.LastName, 'a contact\'s name is not one field that can be written, so it takes no suffix');
  }
}
