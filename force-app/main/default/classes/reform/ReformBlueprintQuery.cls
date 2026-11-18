/** Stored blueprints, with every field a definition is read from. */
global class ReformBlueprintQuery extends inj.BaseQuery {
  global ReformBlueprintQuery() {
    super();
  }

  global override Set<SObjectField> getDefaultFields() {
    return new Set<SObjectField>{
      Reform_Blueprint__c.Id,
      Reform_Blueprint__c.Name,
      Reform_Blueprint__c.Api_Name__c,
      Reform_Blueprint__c.Sobject_Name__c,
      Reform_Blueprint__c.Label__c,
      Reform_Blueprint__c.Label_Plural__c,
      Reform_Blueprint__c.Naming_Field__c,
      Reform_Blueprint__c.Icon_Name__c,
      Reform_Blueprint__c.Record_Type_Developer_Name__c,
      Reform_Blueprint__c.Elements__c,
      Reform_Blueprint__c.Columns__c
    };
  }

  /** Only the blueprints with these API names. */
  public ReformBlueprintQuery named(Set<String> apiNames) {
    addCondition(App.s.iin(Reform_Blueprint__c.Api_Name__c, apiNames));
    return this;
  }
}
