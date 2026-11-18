/**
 * Rollups as a user meets them: sample children are saved, deleted and moved through the real
 * trigger, and the sample parent is read back. The rules are given by each test, so nothing here
 * depends on the Rollup_Rule__mdt records in the org.
 */
@IsTest
private class RollupHandlerTest {
  private static RollupRule rule(String name) {
    return new RollupRule(name).children(Rollup_Sample_Child__c.Parent__c);
  }

  private static RollupRule counting() {
    return rule('Count').count().writeTo(Rollup_Sample_Parent__c.Child_Count__c);
  }

  private static RollupRule openAmount() {
    return rule('Open').sum(Rollup_Sample_Child__c.Amount__c).matching('Status__c != \'Closed\'').writeTo(Rollup_Sample_Parent__c.Open_Amount__c);
  }

  private static Rollup_Sample_Parent__c parent(String name) {
    Rollup_Sample_Parent__c made = new Rollup_Sample_Parent__c(Name = name);
    insert made;
    return made;
  }

  private static Rollup_Sample_Child__c child(Id parentId, Decimal amount, String status) {
    return new Rollup_Sample_Child__c(Name = 'Child', Parent__c = parentId, Amount__c = amount, Status__c = status);
  }

  private static Rollup_Sample_Parent__c read(Id parentId) {
    return [
      SELECT Child_Count__c, Open_Amount__c, Average_Amount__c, Largest_Amount__c, Earliest_Due__c, Kinds__c
      FROM Rollup_Sample_Parent__c
      WHERE Id = :parentId
    ];
  }

  @IsTest
  static void childrenAreCountedAsTheyComeAndGo() {
    RollupRules.use(new List<RollupRule>{ counting() });
    Rollup_Sample_Parent__c holder = parent('Holder');
    Assert.isNull(read(holder.Id).Child_Count__c, 'nothing has been rolled up yet');

    List<Rollup_Sample_Child__c> three = new List<Rollup_Sample_Child__c>{ child(holder.Id, 1, 'Open'), child(holder.Id, 2, 'Open'), child(holder.Id, 3, 'Open') };
    insert three;
    Assert.areEqual(3, read(holder.Id).Child_Count__c);

    delete three[0];
    Assert.areEqual(2, read(holder.Id).Child_Count__c);

    undelete three[0];
    Assert.areEqual(3, read(holder.Id).Child_Count__c);

    delete three;
    Assert.areEqual(0, read(holder.Id).Child_Count__c, 'a count of nothing is 0, not blank');
  }

  @IsTest
  static void aChildThatMovesIsCountedForBothParents() {
    RollupRules.use(new List<RollupRule>{ counting() });
    Rollup_Sample_Parent__c first = parent('First');
    Rollup_Sample_Parent__c second = parent('Second');
    Rollup_Sample_Child__c mover = child(first.Id, 1, 'Open');
    insert mover;

    mover.Parent__c = second.Id;
    update mover;
    Assert.areEqual(0, read(first.Id).Child_Count__c);
    Assert.areEqual(1, read(second.Id).Child_Count__c);

    mover.Parent__c = null;
    update mover;
    Assert.areEqual(0, read(second.Id).Child_Count__c);
  }

  @IsTest
  static void aSumFollowsItsFilter() {
    RollupRules.use(new List<RollupRule>{ openAmount() });
    Rollup_Sample_Parent__c holder = parent('Holder');
    Rollup_Sample_Child__c ten = child(holder.Id, 10, 'Open');
    Rollup_Sample_Child__c twenty = child(holder.Id, 20, null);
    Rollup_Sample_Child__c closed = child(holder.Id, 5, 'Closed');
    insert new List<Rollup_Sample_Child__c>{ ten, twenty, closed };
    Assert.areEqual(30, read(holder.Id).Open_Amount__c, 'a blank status is not Closed, as in SOQL');

    twenty.Status__c = 'Closed';
    update twenty;
    Assert.areEqual(10, read(holder.Id).Open_Amount__c, 'a child that leaves the filter leaves the sum');

    ten.Amount__c = 15;
    update ten;
    Assert.areEqual(15, read(holder.Id).Open_Amount__c);

    closed.Status__c = 'Open';
    update closed;
    Assert.areEqual(20, read(holder.Id).Open_Amount__c, 'a child that enters the filter joins the sum');

    delete new List<Rollup_Sample_Child__c>{ ten, closed };
    Assert.areEqual(0, read(holder.Id).Open_Amount__c, 'a sum of nothing is 0');
  }

  @IsTest
  static void everyOperationIsWorkedOut() {
    RollupRules.use(
      new List<RollupRule>{
        rule('Average').avg(Rollup_Sample_Child__c.Amount__c).writeTo(Rollup_Sample_Parent__c.Average_Amount__c),
        rule('Largest').max(Rollup_Sample_Child__c.Amount__c).writeTo(Rollup_Sample_Parent__c.Largest_Amount__c),
        rule('Earliest').min(Rollup_Sample_Child__c.Due__c).writeTo(Rollup_Sample_Parent__c.Earliest_Due__c),
        rule('Kinds').countDistinct(Rollup_Sample_Child__c.Kind__c).writeTo(Rollup_Sample_Parent__c.Kinds__c),
        rule('Dated').count(Rollup_Sample_Child__c.Due__c).writeTo(Rollup_Sample_Parent__c.Child_Count__c)
      }
    );
    Rollup_Sample_Parent__c holder = parent('Holder');
    Date soon = Date.newInstance(2030, 1, 15);
    List<Rollup_Sample_Child__c> made = new List<Rollup_Sample_Child__c>{
      new Rollup_Sample_Child__c(Parent__c = holder.Id, Amount__c = 10, Kind__c = 'a', Due__c = soon.addDays(30)),
      new Rollup_Sample_Child__c(Parent__c = holder.Id, Amount__c = 20, Kind__c = 'a', Due__c = soon),
      new Rollup_Sample_Child__c(Parent__c = holder.Id, Amount__c = 70.01, Kind__c = 'b')
    };
    insert made;

    Rollup_Sample_Parent__c held = read(holder.Id);
    Assert.areEqual(33.34, held.Average_Amount__c, 'rounded to the field\'s two decimal places');
    Assert.areEqual(70.01, held.Largest_Amount__c);
    Assert.areEqual(soon, held.Earliest_Due__c);
    Assert.areEqual(2, held.Kinds__c);
    Assert.areEqual(2, held.Child_Count__c, 'a count of a field counts the children that have a value in it');

    delete made;
    held = read(holder.Id);
    Assert.isNull(held.Average_Amount__c, 'an average of nothing is blank');
    Assert.isNull(held.Largest_Amount__c);
    Assert.isNull(held.Earliest_Due__c);
    Assert.areEqual(0, held.Kinds__c);
    Assert.areEqual(0, held.Child_Count__c);
  }

  @IsTest
  static void twoHundredChildrenCostTwoQueriesAndOneUpdate() {
    RollupRules.use(
      new List<RollupRule>{
        counting(),
        rule('Average').avg(Rollup_Sample_Child__c.Amount__c).writeTo(Rollup_Sample_Parent__c.Average_Amount__c),
        rule('Largest').max(Rollup_Sample_Child__c.Amount__c).writeTo(Rollup_Sample_Parent__c.Largest_Amount__c)
      }
    );
    List<Rollup_Sample_Parent__c> holders = new List<Rollup_Sample_Parent__c>();
    for (Integer at = 0; at < 4; at++) {
      holders.add(new Rollup_Sample_Parent__c(Name = 'Holder ' + at));
    }
    insert holders;
    List<Rollup_Sample_Child__c> many = new List<Rollup_Sample_Child__c>();
    for (Integer at = 0; at < 200; at++) {
      many.add(child(holders[Math.mod(at, 4)].Id, at, 'Open'));
    }

    Integer queriesBefore = Limits.getQueries();
    Integer updatesBefore = Limits.getDmlStatements();
    insert many;

    Assert.areEqual(2, Limits.getQueries() - queriesBefore, 'one aggregate query for the three rules, one for the parents');
    Assert.areEqual(2, Limits.getDmlStatements() - updatesBefore, 'the insert itself, and one update of the parents');
    Rollup_Sample_Parent__c last = read(holders[3].Id);
    Assert.areEqual(50, last.Child_Count__c);
    Assert.areEqual(199, last.Largest_Amount__c);
    Assert.areEqual(101, last.Average_Amount__c);
  }

  @IsTest
  static void aChangeThatCannotAlterAResultCostsNothing() {
    RollupRules.use(new List<RollupRule>{ openAmount() });
    Rollup_Sample_Parent__c holder = parent('Holder');
    Rollup_Sample_Child__c open = child(holder.Id, 10, 'Open');
    Rollup_Sample_Child__c closed = child(holder.Id, 5, 'Closed');
    insert new List<Rollup_Sample_Child__c>{ open, closed };

    Integer queriesBefore = Limits.getQueries();
    open.Kind__c = 'not a field the rule reads';
    update open;
    Assert.areEqual(0, Limits.getQueries() - queriesBefore, 'no watched field changed');

    closed.Amount__c = 500;
    update closed;
    Assert.areEqual(0, Limits.getQueries() - queriesBefore, 'the child is outside the filter before and after');
    Assert.areEqual(10, read(holder.Id).Open_Amount__c);
  }

  @IsTest
  static void aParentWhoseValueIsUnchangedIsNotWritten() {
    RollupRules.use(new List<RollupRule>{ rule('Largest').max(Rollup_Sample_Child__c.Amount__c).writeTo(Rollup_Sample_Parent__c.Largest_Amount__c) });
    Rollup_Sample_Parent__c holder = parent('Holder');
    Rollup_Sample_Child__c five = child(holder.Id, 5, 'Open');
    insert new List<Rollup_Sample_Child__c>{ five, child(holder.Id, 7, 'Open') };

    Integer updatesBefore = Limits.getDmlStatements();
    five.Amount__c = 6;
    update five;

    Assert.areEqual(1, Limits.getDmlStatements() - updatesBefore, 'only the child was saved: the largest is still 7');
    Assert.areEqual(7, read(holder.Id).Largest_Amount__c);
  }

  @IsTest
  static void aParentIsKeptWhileAGuardedCountIsAboveZero() {
    RollupRules.use(new List<RollupRule>{ counting().guardingDelete(), openAmount() });
    Rollup_Sample_Parent__c holder = parent('Holder');
    Rollup_Sample_Child__c only = child(holder.Id, 1, 'Open');
    insert only;
    Rollup_Sample_Parent__c unguarded = parent('Unguarded');
    update new Rollup_Sample_Parent__c(Id = unguarded.Id, Open_Amount__c = 5);
    delete unguarded;
    Assert.areEqual(1, [SELECT COUNT() FROM Rollup_Sample_Parent__c], 'a rule that does not guard keeps nothing');

    String refusal;
    try {
      delete holder;
    } catch (DmlException refused) {
      refusal = refused.getDmlMessage(0);
    }
    Assert.areEqual('This Rollup Sample Parent cannot be deleted while its Child Count is 1', refusal);

    delete only;
    delete holder;
    Assert.areEqual(0, [SELECT COUNT() FROM Rollup_Sample_Parent__c]);
  }

  @IsTest
  static void aRuleThatCannotRunStopsTheSave() {
    RollupRule broken = rule('Broken').count();
    broken.parentField = 'Nope__c';
    RollupRules.use(new List<RollupRule>{ broken });
    Rollup_Sample_Parent__c holder = parent('Holder');

    String refusal;
    try {
      insert child(holder.Id, 1, 'Open');
    } catch (DmlException refused) {
      refusal = refused.getMessage();
    }
    Assert.isTrue(
      refusal != null && refusal.contains('Rollup rule Broken cannot run: ' + String.valueOf(Rollup_Sample_Parent__c.SObjectType) + ' has no field Nope__c'),
      'the save fails and says which rule and why: ' + refusal
    );
  }

  // A total covers every child, including those the person saving cannot see, and is written to a
  // parent that person may not edit.

  private with sharing class AsTheUserSees {
    private Integer children(Id parentId) {
      return [SELECT COUNT() FROM Rollup_Sample_Child__c WHERE Parent__c = :parentId];
    }
  }

  private static User colleague() {
    User made = new User(
      ProfileId = [SELECT Id FROM Profile WHERE Name = 'Minimum Access - Salesforce'].Id,
      LastName = 'Colleague',
      Alias = 'rollg',
      Email = 'colleague@rollup.example.com',
      Username = 'colleague.' + UserInfo.getOrganizationId() + '.' + System.now().getTime() + '@rollup.example.com',
      TimeZoneSidKey = 'GMT',
      LocaleSidKey = 'en_US',
      EmailEncodingKey = 'UTF-8',
      LanguageLocaleKey = 'en_US'
    );
    // Users and permission sets are setup objects: saved as another "user" so the test can save records afterwards.
    System.runAs(new User(Id = UserInfo.getUserId())) {
      insert made;
      PermissionSet granted = new PermissionSet(Name = 'Rollup_Handler_Test', Label = 'Rollup Handler Test');
      insert granted;
      List<ObjectPermissions> onObjects = new List<ObjectPermissions>();
      onObjects.add(new ObjectPermissions(ParentId = granted.Id, SobjectType = String.valueOf(Rollup_Sample_Parent__c.SObjectType), PermissionsRead = true));
      onObjects.add(
        new ObjectPermissions(ParentId = granted.Id, SobjectType = String.valueOf(Rollup_Sample_Child__c.SObjectType), PermissionsRead = true, PermissionsCreate = true, PermissionsEdit = true)
      );
      insert onObjects;
      insert new PermissionSetAssignment(AssigneeId = made.Id, PermissionSetId = granted.Id);
    }
    return made;
  }

  @IsTest
  static void aTotalCoversChildrenTheUserCannotSeeOnAParentTheyCannotEdit() {
    RollupRules.use(new List<RollupRule>{ counting() });
    User colleague = colleague();
    Rollup_Sample_Parent__c holder = parent('Holder');
    insert child(holder.Id, 1, 'Open');

    System.runAs(colleague) {
      insert child(holder.Id, 2, 'Open');
      Assert.areEqual(1, new AsTheUserSees().children(holder.Id), 'the children are shared privately: the colleague sees only their own');
    }
    Assert.isFalse(
      [SELECT RecordId, HasEditAccess FROM UserRecordAccess WHERE UserId = :colleague.Id AND RecordId = :holder.Id].HasEditAccess,
      'the parents are shared read-only: the colleague may not edit this one'
    );

    Assert.areEqual(2, read(holder.Id).Child_Count__c);
  }
}
