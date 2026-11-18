/** What a result holds before anything is counted. */
@IsTest
private class ImportResultTest {
  @IsTest
  static void aResultStartsEmpty() {
    ImportResult result = new ImportResult();

    Assert.isFalse(result.saved);
    Assert.areEqual(0, result.rows + result.created + result.updated + result.failed + result.held);
    Assert.isTrue(result.columns.isEmpty() && result.ignored.isEmpty() && result.notes.isEmpty() && result.failures.isEmpty());
    Assert.isNull(result.failuresCsv);
    Assert.isTrue(result.idsByRow.isEmpty());
  }

  @IsTest
  static void aFailureNamesItsRow() {
    ImportResult.Failure failure = new ImportResult.Failure(7, 'Surname is empty');

    Assert.areEqual(7, failure.row);
    Assert.areEqual('Surname is empty', failure.message);
  }
}
