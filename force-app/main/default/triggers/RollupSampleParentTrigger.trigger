trigger RollupSampleParentTrigger on Rollup_Sample_Parent__c(before delete) {
  Unify.s.tf().execute();
}
