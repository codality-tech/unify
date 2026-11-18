/**
 * Names are found as written first, then in Unify's namespace.
 *
 * These tests run with the real namespace and with none, so they pretend to one of their own: the
 * prefix is set to the start of a real name, whatever that name is in this org, and the rest of the
 * name is then "a name written without its namespace".
 */
@IsTest
private class NamingTest {
  private static final String CHILD = String.valueOf(Rollup_Sample_Child__c.SObjectType);
  private static final String COUNT = Rollup_Sample_Parent__c.Child_Count__c.getDescribe().getName();

  private static inj.IModel child() {
    return Unify.s.model(Rollup_Sample_Child__c.SObjectType);
  }

  private static inj.IModel parent() {
    return Unify.s.model(Rollup_Sample_Parent__c.SObjectType);
  }

  // Child_Count__c is then written Count__c.
  private static void pretendTheCountIsOurs() {
    Naming.prefix = COUNT.substringBefore('Count__c');
  }

  @IsTest
  static void aNameFoundAsWrittenIsNotLookedForAgain() {
    pretendTheCountIsOurs();
    String amount = Rollup_Sample_Child__c.Amount__c.getDescribe().getName();

    Assert.areEqual(Account.SObjectType, Naming.model(Unify.s, ' Account ').token(), 'a standard object, spaces aside');
    Assert.areEqual(Rollup_Sample_Child__c.SObjectType, Naming.model(Unify.s, CHILD).token());
    Assert.areEqual(Rollup_Sample_Child__c.Amount__c, Naming.field(child(), amount));
    Assert.areEqual(Account.Name, Naming.field(Unify.s.model(Account.SObjectType), 'name'));
  }

  @IsTest
  static void anObjectNotFoundAsWrittenIsLookedForInTheNamespace() {
    Naming.prefix = CHILD.substringBefore('Sample_Child__c');

    Assert.areEqual(Rollup_Sample_Child__c.SObjectType, Naming.model(Unify.s, 'Sample_Child__c').token());
    Assert.isNull(Naming.model(Unify.s, 'No_Such_Thing__c'), 'still unknown with the namespace');
    Assert.isNull(Naming.model(Unify.s, 'Sample_Child'), 'not a custom name, so not tried again');
    Assert.isNull(Naming.model(Unify.s, ' '));
    Assert.isNull(Naming.model(Unify.s, null));
  }

  @IsTest
  static void aFieldNotFoundAsWrittenIsLookedForInTheNamespace() {
    pretendTheCountIsOurs();

    Assert.areEqual(Rollup_Sample_Parent__c.Child_Count__c, Naming.field(parent(), 'Count__c'));
    Assert.areEqual(Rollup_Sample_Parent__c.Child_Count__c, Naming.field(parent(), ' count__c '), 'any case, spaces aside');
    Assert.isNull(Naming.field(parent(), 'Nope__c'));
    Assert.isNull(Naming.field(parent(), ''));
    Assert.isNull(Naming.field(null, 'Count__c'));
  }

  @IsTest
  static void aFilterHasItsOwnNamesWrittenInFull() {
    pretendTheCountIsOurs();
    String code = Rollup_Sample_Parent__c.Code__c.getDescribe().getName();
    String rest = ' > 0 AND (Name = \'Count__c\' OR ' + code + ' != \'it\\\'s Count__c\') AND Nope__c = 1';

    Assert.areEqual(
      COUNT + rest,
      Naming.inText(parent(), 'Count__c' + rest),
      'the name is completed; quoted text, names found as written and unknown names are kept'
    );
    Assert.areEqual('Name = \'never closed Count__c', Naming.inText(parent(), 'Name = \'never closed Count__c'));
    Assert.areEqual('CreatedDate = LAST_N_DAYS:7', Naming.inText(parent(), 'CreatedDate = LAST_N_DAYS:7'), 'nothing custom, nothing to do');
    Assert.isNull(Naming.inText(parent(), null));
    Assert.areEqual('Count__c > 0', Naming.inText(null, 'Count__c > 0'), 'no object to look in');
  }

  @IsTest
  static void aPathIsFollowedThroughItsLookups() {
    String toParent = Rollup_Sample_Child__c.Parent__c.getDescribe().getRelationshipName();
    String toFormer = Rollup_Sample_Child__c.Former_Parent__c.getDescribe().getRelationshipName();

    pretendTheCountIsOurs();
    Assert.areEqual(toParent + '.' + COUNT, Naming.inText(child(), toParent + '.Count__c'), 'a field of the object the lookup points at');
    Assert.areEqual('CreatedBy.Count__c', Naming.inText(child(), 'CreatedBy.Count__c'), 'a user has no such field');
    Assert.areEqual('Nope__r.Count__c', Naming.inText(child(), 'Nope__r.Count__c'), 'the walk stops at a part that leads nowhere');

    // Former_Parent__r is then written mer_Parent__r.
    Naming.prefix = toFormer.substringBefore('mer_Parent__r');
    Assert.areEqual(toFormer + '.Name', Naming.inText(child(), 'mer_Parent__r.Name'), 'a relationship is completed like a field');
  }

  @IsTest
  static void aNamespaceCanBeTakenOffAName() {
    pretendTheCountIsOurs();

    Assert.areEqual('Count__c', Naming.withoutNamespace(COUNT));
    Assert.areEqual('Other__c', Naming.withoutNamespace('Other__c'));
  }

  @IsTest
  static void withNoNamespaceNothingChanges() {
    Naming.prefix = '';

    Assert.areEqual('Count__c > 0', Naming.inText(parent(), 'Count__c > 0'));
    Assert.isNull(Naming.field(parent(), 'Count__c'));
    Assert.isNull(Naming.model(Unify.s, 'Sample_Child__c'));
    Assert.areEqual(COUNT, Naming.withoutNamespace(COUNT));
  }

  @IsTest
  static void theNamespaceIsThatOfThePackage() {
    String className = Naming.class.getName();

    Assert.areEqual(className.contains('.') ? className.substringBefore('.') + '__' : '', Naming.prefix);
  }
}
