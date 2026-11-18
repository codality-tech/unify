public class Scheme30 implements inj.IScheme {
    public SObjectType getSObjectType(string sobjectName) {
        try{
            return ((SObject)Type.forName(sobjectName)?.newInstance())?.getSObjectType();
        }catch(Exception e){
            return null;
        }
    }
    public DescribeSObjectResult getDescribe(SObjectType sobjectToken) {
        return getSObjectType(''+sobjectToken)?.getDescribe(SObjectDescribeOptions.DEFAULT);
    }
    
    public Map<String,SObjectField> getFieldMap(SObjectType sobjectToken) {
        return getDescribe(sobjectToken)?.fields.getMap();
    }

    public Map<String,Schema.Fieldset> getFieldsetMap(SObjectType sobjectToken) {
        return getDescribe(sobjectToken)?.fieldSets.getMap();
    }

    public DescribeFieldResult getFieldDescribe(SObjectField field) {
        return field.getDescribe();
    }
    
    public List<SObject> queryWithBinds(String queryString, Map<String,Object> bindMap, System.AccessLevel accessLevel) {
        return Database.queryWithBinds(queryString, bindMap, accessLevel);
    }
    
    public Database.QueryLocator getQueryLocatorWithBinds(String queryString, Map<String,Object> bindMap, System.AccessLevel accessLevel) {
        return Database.getQueryLocatorWithBinds(queryString, bindMap, accessLevel);
    }
    
    public Integer countQueryWithBinds(String queryString, Map<String,Object> bindMap, System.AccessLevel accessLevel) {
        return Database.countQueryWithBinds(queryString, bindMap, accessLevel);
    }
    
    public Type getTypeForName(String className) {
        return Type.forName(className);
    }
}
