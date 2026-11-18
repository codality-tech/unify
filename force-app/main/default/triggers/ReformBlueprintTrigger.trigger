trigger ReformBlueprintTrigger on Reform_Blueprint__c(before insert, before update) {
  App.s.tf().execute();
}
