/**
 * The registry of plans, and the Clone_Step__mdt records this org holds. The first test is the
 * guard for a deployment: a stored plan that cannot run fails it, with the reason.
 */
@IsTest
private class ClonePlansTest {
  @IsTest
  static void everyStoredPlanCanRun() {
    Map<String, List<String>> wrong = ClonePlans.problems();
    Assert.isTrue(wrong.isEmpty(), 'Clone plans that cannot run: ' + JSON.serialize(wrong));
    Assert.isTrue(ClonePlans.names().contains('Sample_Parent_Copy'), 'the sample plan is stored');
  }

  @IsTest
  static void plansAreNamedByTheStepsThatStartThem() {
    CloneStep off = new CloneStep('Off').copying(Lead.SObjectType);
    off.active = false;
    ClonePlans.use(
      new List<CloneStep>{
        new CloneStep('Zed').copying(Account.SObjectType),
        new CloneStep('People').under('Zed', Contact.AccountId),
        off,
        new CloneStep('Alpha').copying(Opportunity.SObjectType)
      }
    );

    Assert.areEqual(new List<String>{ 'Alpha', 'Zed' }, ClonePlans.names());
    Assert.areEqual(2, ClonePlans.named('zed').nodes().size(), 'found whatever the case of the name');
    Assert.isTrue(ClonePlans.problems().isEmpty());
  }

  @IsTest
  static void whatIsWrongIsReportedByPlanAndByStrayStep() {
    CloneStep wrong = new CloneStep('Wrong').copying(Account.SObjectType);
    wrong.leaveOut = 'Nope__c';
    CloneStep off = new CloneStep('Off').copying(Account.SObjectType);
    off.active = false;
    CloneStep unknownObject = new CloneStep('Lost').copying(Account.SObjectType);
    unknownObject.objectName = 'Nope__c';
    CloneStep loopOne = new CloneStep('Loop_One').under('Loop_Two', Account.ParentId);
    CloneStep loopTwo = new CloneStep('Loop_Two').under('Loop_One', Account.ParentId);
    ClonePlans.use(
      new List<CloneStep>{
        wrong,
        new CloneStep('Sound').copying(Account.SObjectType),
        off,
        new CloneStep('Under_Off').under('Off', Contact.AccountId),
        new CloneStep('Under_Nothing').under('Nowhere', Contact.AccountId),
        unknownObject,
        new CloneStep('Under_Lost').under('Lost', Contact.AccountId),
        loopOne,
        loopTwo
      }
    );

    Map<String, List<String>> found = ClonePlans.problems();

    Assert.areEqual(new List<String>{ 'Step Wrong: Account has no field Nope__c' }, found.get('Wrong'));
    Assert.areEqual(new List<String>{ 'Step Lost: unknown object Nope__c' }, found.get('Lost'));
    Assert.areEqual(
      new List<String>{ 'It belongs to no plan: no active step named Off leads back to the start of one' },
      found.get('Under_Off'),
      'an inactive step takes the steps beneath it with it'
    );
    Assert.isTrue(found.containsKey('Under_Nothing'));
    Assert.isTrue(found.containsKey('Loop_One'));
    Assert.isTrue(found.containsKey('Loop_Two'));
    Assert.isFalse(found.containsKey('Sound'));
    Assert.isFalse(found.containsKey('Under_Lost'), 'a step beneath one that could not be resolved is covered by that one\'s problem');
    Assert.areEqual(6, found.size());
  }
}
