/** The rollup's jobs: the queued recalculation, the sweep over every parent, and its nightly schedule. */
@IsTest
private class RollupJobsTest {
  private static RollupRule sampleCount() {
    return new RollupRule('Sample_Count').children(Rollup_Sample_Child__c.Parent__c).count().writeTo(Rollup_Sample_Parent__c.Child_Count__c);
  }

  // Contacts have no rollup trigger in this org, so only a sweep fills this in.
  private static RollupRule contactCount() {
    return new RollupRule('Contact_Count').children(Contact.AccountId).count().writeTo(Account.NumberOfEmployees);
  }

  // A sample parent with two children, whose count has been overwritten with 99.
  private static Id driftedParent() {
    Rollup_Sample_Parent__c holder = new Rollup_Sample_Parent__c(Name = 'Holder');
    insert holder;
    insert new List<Rollup_Sample_Child__c>{ new Rollup_Sample_Child__c(Parent__c = holder.Id), new Rollup_Sample_Child__c(Parent__c = holder.Id) };
    update new Rollup_Sample_Parent__c(Id = holder.Id, Child_Count__c = 99);
    return holder.Id;
  }

  private static Decimal countOn(Id parentId) {
    return [SELECT Child_Count__c FROM Rollup_Sample_Parent__c WHERE Id = :parentId].Child_Count__c;
  }

  @IsTest
  static void theQueuedJobRecalculatesWhatItWasGiven() {
    RollupRules.use(new List<RollupRule>{ sampleCount() });
    Id holderId = driftedParent();

    new RollupJobs.Recalculate(new Map<String, Set<Id>>{ 'Sample_Count' => new Set<Id>{ holderId } }).queueableExecute();

    Assert.areEqual(2, countOn(holderId));
  }

  @IsTest
  static void aSweepRunsAsABatch() {
    RollupRules.use(new List<RollupRule>{ sampleCount() });
    Id holderId = driftedParent();

    Test.startTest();
    inj.IJob started = Rollups.sweep();
    Test.stopTest();

    Assert.isNotNull(started.getJobId());
    Assert.areEqual(2, countOn(holderId));
  }

  @IsTest
  static void aSweepTakesEachParentObjectInTurn() {
    inj.Async.synchronousInTests = true;
    RollupRules.use(new List<RollupRule>{ sampleCount(), contactCount() });
    Id holderId = driftedParent();
    Account firm = new Account(Name = 'Firm');
    insert firm;
    insert new List<Contact>{
      new Contact(LastName = 'One', AccountId = firm.Id),
      new Contact(LastName = 'Two', AccountId = firm.Id),
      new Contact(LastName = 'Three', AccountId = firm.Id)
    };
    Assert.isNull([SELECT NumberOfEmployees FROM Account WHERE Id = :firm.Id].NumberOfEmployees, 'nothing rolls contacts up as they are saved');

    Rollups.sweep();

    Assert.areEqual(3, [SELECT NumberOfEmployees FROM Account WHERE Id = :firm.Id].NumberOfEmployees);
    Assert.areEqual(2, countOn(holderId));
  }

  @IsTest
  static void aSweepWithNoRulesStartsNothing() {
    RollupRules.use(new List<RollupRule>());
    Assert.isNull(Rollups.sweep());
  }

  @IsTest
  static void theNightlyJobSweeps() {
    inj.Async.synchronousInTests = true;
    RollupRules.use(new List<RollupRule>{ sampleCount() });
    Id holderId = driftedParent();
    RollupJobs.Nightly nightly = new RollupJobs.Nightly();

    nightly.schedulableExecute();

    Assert.areEqual(2, countOn(holderId));
    Assert.areEqual('Rollup sweep', nightly.name());
    Assert.areEqual('0 0 2 * * ?', nightly.cronExpression());
  }

  @IsTest
  static void theNightlyJobCanBeScheduled() {
    inj.ISchedulable nightly = inj.Async.schedulable(new RollupJobs.Nightly());

    nightly.run();
    Assert.areEqual(1, [SELECT COUNT() FROM CronTrigger WHERE CronJobDetail.Name = 'Rollup sweep']);

    nightly.unschedule();
    Assert.areEqual(0, [SELECT COUNT() FROM CronTrigger WHERE CronJobDetail.Name = 'Rollup sweep']);
  }
}
