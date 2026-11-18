trigger RollupSampleParentTrigger on Rollup_Sample_Parent__c(before delete) {
  App.s.tf().execute();
}
