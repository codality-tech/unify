/** The rollup's scheme: names and describes resolve, and queries run as they are given. */
@IsTest
private class RollupSchemeTest {
  @IsTest
  static void objectsAndFieldsResolve() {
    RollupScheme scheme = new RollupScheme();

    Assert.areEqual(Account.SObjectType, scheme.getSObjectType('Account'));
    Assert.isNull(scheme.getSObjectType('Nope__c'));
    Assert.isNull(scheme.getSObjectType('String'), 'a type that is not an object');
    Assert.areEqual('Account', scheme.getDescribe(Account.SObjectType).getName());
    Assert.isNull(scheme.getDescribe(null));
    Assert.areEqual(Account.Name, scheme.getFieldMap(Account.SObjectType).get('Name'));
    Assert.isNotNull(scheme.getFieldsetMap(Account.SObjectType));
    Assert.areEqual('Name', scheme.getFieldDescribe(Account.Name).getName());
    Assert.areEqual(RollupScheme.class, scheme.getTypeForName('RollupScheme'));
  }

  @IsTest
  static void queriesRunWithTheirBoundValues() {
    insert new Rollup_Sample_Parent__c(Name = 'Holder');
    RollupScheme scheme = new RollupScheme();
    String filtered = ' FROM Rollup_Sample_Parent__c WHERE Name = :wanted';
    Map<String, Object> binds = new Map<String, Object>{ 'wanted' => 'Holder' };

    Assert.areEqual(1, scheme.queryWithBinds('SELECT Id' + filtered, binds, System.AccessLevel.SYSTEM_MODE).size());
    Assert.areEqual(1, scheme.countQueryWithBinds('SELECT COUNT()' + filtered, binds, System.AccessLevel.SYSTEM_MODE));
    Assert.isTrue(scheme.getQueryLocatorWithBinds('SELECT Id' + filtered, binds, System.AccessLevel.SYSTEM_MODE).iterator().hasNext());
  }

  @IsTest
  static void theRollupsApplicationUsesIt() {
    Assert.isTrue(RollupScheme.app.model(Account.SObjectType).scheme() instanceof RollupScheme);
  }
}
