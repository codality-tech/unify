/**
 * The engine beneath the trigger handler: recalculating on request, queued rules, what happens when
 * a transaction runs short of queries or of jobs, and many parents at once.
 */
@IsTest
private class RollupsTest {
  private static RollupRule rule(String name) {
    return new RollupRule(name).children(Rollup_Sample_Child__c.Parent__c);
  }

  private static RollupRule counting() {
    return rule('Count').count().writeTo(Rollup_Sample_Parent__c.Child_Count__c);
  }

  private static RollupRule kinds() {
    return rule('Kinds').countDistinct(Rollup_Sample_Child__c.Kind__c).writeTo(Rollup_Sample_Parent__c.Kinds__c);
  }

  private static Rollup_Sample_Parent__c parent(String name) {
    Rollup_Sample_Parent__c made = new Rollup_Sample_Parent__c(Name = name);
    insert made;
    return made;
  }

  private static Rollup_Sample_Child__c child(Id parentId, String kind) {
    return new Rollup_Sample_Child__c(Name = 'Child', Parent__c = parentId, Kind__c = kind, Amount__c = 1);
  }

  private static Rollup_Sample_Parent__c read(Id parentId) {
    return [SELECT Child_Count__c, Kinds__c, Open_Amount__c FROM Rollup_Sample_Parent__c WHERE Id = :parentId];
  }

  private class Idle implements Queueable {
    public void execute(QueueableContext context) {
    }
  }

  @IsTest
  static void recalculateRepairsValuesThatDrifted() {
    RollupRules.use(new List<RollupRule>{ counting(), kinds() });
    Rollup_Sample_Parent__c holder = parent('Holder');
    Rollup_Sample_Parent__c childless = parent('Childless');
    insert new List<Rollup_Sample_Child__c>{ child(holder.Id, 'a'), child(holder.Id, 'b') };
    update new Rollup_Sample_Parent__c(Id = holder.Id, Child_Count__c = 99, Kinds__c = null);

    Rollups.recalculate(new Set<Id>{ holder.Id, childless.Id });

    Assert.areEqual(2, read(holder.Id).Child_Count__c);
    Assert.areEqual(2, read(holder.Id).Kinds__c);
    Assert.areEqual(0, read(childless.Id).Child_Count__c, 'a parent with no children is given its zeroes');
  }

  @IsTest
  static void aParentThatIsGoneIsPassedOver() {
    RollupRules.use(new List<RollupRule>{ counting() });
    Rollup_Sample_Parent__c holder = parent('Holder');
    Rollup_Sample_Parent__c gone = parent('Gone');
    insert child(holder.Id, 'a');
    delete gone;
    update new Rollup_Sample_Parent__c(Id = holder.Id, Child_Count__c = 99);

    Rollups.recalculate(new Set<Id>{ holder.Id, gone.Id });

    Assert.areEqual(1, read(holder.Id).Child_Count__c);
  }

  @IsTest
  static void recalculatingByRuleIgnoresARuleThatNoLongerExists() {
    RollupRules.use(new List<RollupRule>{ counting() });
    Rollup_Sample_Parent__c holder = parent('Holder');
    update new Rollup_Sample_Parent__c(Id = holder.Id, Child_Count__c = 99);

    Rollups.recalculate(new Map<String, Set<Id>>{ 'Count' => new Set<Id>{ holder.Id }, 'Retired' => new Set<Id>{ holder.Id } });

    Assert.areEqual(0, read(holder.Id).Child_Count__c);
  }

  @IsTest
  static void aQueuedRuleRunsInAJobOfItsOwn() {
    RollupRules.use(new List<RollupRule>{ counting(), kinds().queued() });
    Rollup_Sample_Parent__c holder = parent('Holder');

    Test.startTest();
    insert child(holder.Id, 'a');
    insert child(holder.Id, 'b');
    Assert.areEqual(2, read(holder.Id).Child_Count__c, 'the immediate rule has run');
    Assert.isNull(read(holder.Id).Kinds__c, 'the queued rule has not');
    Assert.areEqual(1, Limits.getQueueableJobs(), 'the second save found the parent already waiting, and started no second job');
    Test.stopTest();

    Assert.areEqual(2, read(holder.Id).Kinds__c, 'the job sees everything the transaction saved');
  }

  @IsTest
  static void anImmediateRuleIsQueuedWhenQueriesRunShort() {
    RollupRules.use(new List<RollupRule>{ counting() });
    Rollup_Sample_Parent__c holder = parent('Holder');
    Rollups.spareQueries = Limits.getLimitQueries();

    Test.startTest();
    insert child(holder.Id, 'a');
    Assert.isNull(read(holder.Id).Child_Count__c, 'not worked out in this transaction');
    Assert.areEqual(1, Limits.getQueueableJobs());
    Test.stopTest();

    Assert.areEqual(1, read(holder.Id).Child_Count__c);
  }

  @IsTest
  static void withNoJobLeftToStartTheWorkIsDoneNow() {
    RollupRules.use(new List<RollupRule>{ kinds().queued() });
    Rollup_Sample_Parent__c holder = parent('Holder');

    Test.startTest();
    while (Limits.getQueueableJobs() < Limits.getLimitQueueableJobs()) {
      System.enqueueJob(new Idle());
    }
    insert child(holder.Id, 'a');
    Assert.areEqual(1, read(holder.Id).Kinds__c, 'worked out in the save, since no job could be started');
    Test.stopTest();
  }

  @IsTest
  static void jobsRunInlineLeaveNothingWaiting() {
    unif.Async.synchronousInTests = true;
    RollupRules.use(new List<RollupRule>{ kinds().queued() });
    Rollup_Sample_Parent__c holder = parent('Holder');

    insert child(holder.Id, 'a');
    Assert.areEqual(1, read(holder.Id).Kinds__c);
    insert child(holder.Id, 'b');
    Assert.areEqual(2, read(holder.Id).Kinds__c, 'the second save is worked out too');
  }

  @IsTest
  static void manyParentsAreReadInPortions() {
    RollupRules.use(new List<RollupRule>{ counting() });
    List<Rollup_Sample_Parent__c> holders = new List<Rollup_Sample_Parent__c>();
    for (Integer at = 0; at < 5; at++) {
      holders.add(new Rollup_Sample_Parent__c(Name = 'Holder ' + at));
    }
    insert holders;
    List<Rollup_Sample_Child__c> made = new List<Rollup_Sample_Child__c>();
    for (Rollup_Sample_Parent__c holder : holders) {
      made.add(child(holder.Id, 'a'));
    }
    insert made;
    List<Rollup_Sample_Parent__c> wrong = new List<Rollup_Sample_Parent__c>();
    for (Rollup_Sample_Parent__c holder : holders) {
      wrong.add(new Rollup_Sample_Parent__c(Id = holder.Id, Child_Count__c = 99));
    }
    update wrong;
    Rollups.parentsPerQuery = 2;

    Integer queriesBefore = Limits.getQueries();
    Rollups.recalculate(new Map<Id, SObject>(holders).keySet());

    Assert.areEqual(4, Limits.getQueries() - queriesBefore, 'five parents, two at a time: three aggregate queries, and one for the parents');
    Assert.areEqual(5, [SELECT COUNT() FROM Rollup_Sample_Parent__c WHERE Child_Count__c = 1]);
  }

  @IsTest
  static void rulesWithDifferentFiltersOrLookupsAreQueriedApart() {
    RollupRules.use(
      new List<RollupRule>{
        counting(),
        rule('Open').sum(Rollup_Sample_Child__c.Amount__c).matching('Status__c != \'Closed\'').writeTo(Rollup_Sample_Parent__c.Open_Amount__c),
        new RollupRule('Former')
          .children(Rollup_Sample_Child__c.Former_Parent__c)
          .count()
          .writeTo(Rollup_Sample_Parent__c.Kinds__c)
      }
    );
    Rollup_Sample_Parent__c holder = parent('Holder');
    Rollup_Sample_Parent__c earlier = parent('Earlier');
    Rollup_Sample_Child__c moved = child(holder.Id, 'a');
    moved.Former_Parent__c = earlier.Id;

    Integer queriesBefore = Limits.getQueries();
    insert moved;

    Assert.areEqual(4, Limits.getQueries() - queriesBefore, 'three aggregate queries, and one for the two parents');
    Assert.areEqual(1, read(holder.Id).Child_Count__c);
    Assert.areEqual(1, read(holder.Id).Open_Amount__c);
    Assert.areEqual(1, read(earlier.Id).Kinds__c, 'a second lookup to the same object has rollups of its own');
    Assert.isNull(read(earlier.Id).Child_Count__c, 'a parent is written only by the rules it was read for');
  }
}
