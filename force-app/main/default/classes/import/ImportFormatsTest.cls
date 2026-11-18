/**
 * The registry of formats, and the Import_Format__mdt records this org holds. The first test is
 * the guard for a deployment: a stored format that cannot run fails it, with the reason.
 */
@IsTest
private class ImportFormatsTest {
  @IsTest
  static void everyStoredFormatCanRun() {
    Map<String, List<String>> wrong = ImportFormats.problems();
    Assert.isTrue(wrong.isEmpty(), 'Import formats that cannot run: ' + JSON.serialize(wrong));
  }

  @IsTest
  static void theStoredSamplesAreReadWithTheirColumnsInOrder() {
    ImportPlan children = ImportFormats.named('Sample_Children');
    ImportPlan parents = ImportFormats.named('Sample_Parents');

    Assert.areEqual(new List<String>{ 'Child', 'Parent', 'Amount', 'Due', 'Kind', 'Status' }, children.headers());
    Assert.areEqual(Rollup_Sample_Child__c.SObjectType, children.model.token());
    Assert.areEqual(Rollup_Sample_Child__c.Name, children.matchOn);
    Assert.areEqual(ImportFormat.Writes.BOTH, children.format.mode);
    Assert.areEqual('Sample: children under their parents', children.format.label);
    Assert.isFalse(parents.namesItsColumns(), 'the parents format reads a file by its headers');
  }

  @IsTest
  static void columnsComeInTheOrderOfTheirPositionThenOfTheirNames() {
    List<Import_Column__mdt> columns = new List<Import_Column__mdt>{
      new Import_Column__mdt(DeveloperName = 'Unplaced'),
      new Import_Column__mdt(DeveloperName = 'Second_B', Position__c = 2),
      new Import_Column__mdt(DeveloperName = 'Second_A', Position__c = 2),
      new Import_Column__mdt(DeveloperName = 'First', Position__c = 1)
    };

    columns.sort(new ImportFormats.ByPosition());

    List<String> names = new List<String>();
    for (Import_Column__mdt column : columns) {
      names.add(column.DeveloperName);
    }
    Assert.areEqual(new List<String>{ 'First', 'Second_A', 'Second_B', 'Unplaced' }, names, 'a column with no position comes last');
  }

  @IsTest
  static void formatsAreListedByNameAndFoundWhateverTheCase() {
    ImportFormat off = new ImportFormat('Off').into(Lead.SObjectType);
    off.active = false;
    ImportFormats.use(new List<ImportFormat>{ new ImportFormat('Zed').into(Account.SObjectType), off, new ImportFormat('Alpha').into(Contact.SObjectType) });

    Assert.areEqual(new List<String>{ 'Alpha', 'Zed' }, ImportFormats.names());
    Assert.areEqual(Account.SObjectType, ImportFormats.named('zed').model.token());
    Assert.areEqual(2, ImportFormats.runnable().size());
    Assert.isTrue(ImportFormats.problems().isEmpty());
  }

  @IsTest
  static void aNameNoActiveFormatHasIsRefused() {
    ImportFormat off = new ImportFormat('Off').into(Lead.SObjectType);
    off.active = false;
    ImportFormats.use(new List<ImportFormat>{ off });

    for (String name : new List<String>{ 'Off', 'Nowhere', null }) {
      try {
        ImportFormats.named(name);
        Assert.fail('expected a refusal for ' + name);
      } catch (Importer.ImportException refused) {
        Assert.areEqual('There is no import format named ' + name, refused.getMessage());
      }
    }
  }

  @IsTest
  static void aFormatThatCannotRunIsRefusedAndReported() {
    ImportFormat wrong = new ImportFormat('Wrong').into(Contact.SObjectType).changing(Contact.Birthdate);
    ImportFormats.use(new List<ImportFormat>{ wrong, new ImportFormat('Sound').into(Contact.SObjectType) });
    String reason = 'Contact.Birthdate is not text or an Id, so rows cannot be matched on it';

    try {
      ImportFormats.named('Wrong');
      Assert.fail('expected a refusal');
    } catch (Importer.ImportException refused) {
      Assert.areEqual('Import format Wrong cannot run: ' + reason, refused.getMessage());
    }
    Assert.areEqual(new Map<String, List<String>>{ 'Wrong' => new List<String>{ reason } }, ImportFormats.problems());
    Assert.areEqual(1, ImportFormats.runnable().size());
    Assert.areEqual('Sound', ImportFormats.runnable()[0].format.name);
  }
}
