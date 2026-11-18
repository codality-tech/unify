trigger AccountTrigger on Account (before insert, after insert, before update, after update, before delete, after delete, after undelete) {
    // The example handlers stay out of other tests' way. A test that is about them sets App.examplesInTests.
    if (Test.isRunningTest() && !App.examplesInTests) {
        return;
    }
    system.debug(Trigger.operationType);
    App.s.tf().execute();
    App.b.tf().execute();
}