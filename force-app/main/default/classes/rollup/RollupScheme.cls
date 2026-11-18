/**
 * The scheme the rollup reads through, and the application built on it.
 *
 * A query made through the framework is run by the application's scheme. A scheme with a sharing
 * keyword of its own settles the matter; one without takes the sharing of whoever built the query
 * (GuideAccessTest shows both). A total must cover every child whoever is saving and whichever
 * class happens to call, so the rollup has an application of its own, on a scheme declared WITHOUT
 * SHARING, and leaves App.s, with whatever scheme the rest of the org chose, alone.
 */
public without sharing class RollupScheme implements unif.IScheme {
  /** Everything the rollup reads or writes goes through this. */
  public static final unif.IApplication app = unif.Application.make(new RollupScheme());

  public SObjectType getSObjectType(String sobjectName) {
    try {
      return ((SObject) Type.forName(sobjectName)?.newInstance())?.getSObjectType();
    } catch (Exception notAnObject) {
      return null;
    }
  }

  public DescribeSObjectResult getDescribe(SObjectType sobjectToken) {
    return sobjectToken?.getDescribe(SObjectDescribeOptions.DEFERRED);
  }

  public Map<String, SObjectField> getFieldMap(SObjectType sobjectToken) {
    return getDescribe(sobjectToken)?.fields.getMap();
  }

  public Map<String, Schema.FieldSet> getFieldsetMap(SObjectType sobjectToken) {
    return getDescribe(sobjectToken)?.fieldSets.getMap();
  }

  public DescribeFieldResult getFieldDescribe(SObjectField field) {
    return field.getDescribe();
  }

  public List<SObject> queryWithBinds(String queryString, Map<String, Object> bindMap, System.AccessLevel accessLevel) {
    return Database.queryWithBinds(queryString, bindMap, accessLevel);
  }

  public Database.QueryLocator getQueryLocatorWithBinds(String queryString, Map<String, Object> bindMap, System.AccessLevel accessLevel) {
    return Database.getQueryLocatorWithBinds(queryString, bindMap, accessLevel);
  }

  public Integer countQueryWithBinds(String queryString, Map<String, Object> bindMap, System.AccessLevel accessLevel) {
    return Database.countQueryWithBinds(queryString, bindMap, accessLevel);
  }

  public Type getTypeForName(String className) {
    return Type.forName(className);
  }
}
