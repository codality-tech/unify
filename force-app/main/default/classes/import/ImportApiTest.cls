/** The entry points the import component calls. */
@IsTest
private class ImportApiTest {
  private static void useFormats() {
    ImportFormat broken = new ImportFormat('Broken').into(Contact.SObjectType).changing(Contact.Birthdate);
    ImportFormat firms = new ImportFormat('Firms').into(Account.SObjectType).allOrNothing();
    firms.label = 'Firms, by header';
    ImportFormats.use(
      new List<ImportFormat>{
        new ImportFormat('People')
          .into(Contact.SObjectType)
          .creatingOrChanging(Contact.Email)
          .column('Email', Contact.Email)
          .column('Surname', Contact.LastName)
          .required(),
        broken,
        firms
      }
    );
  }

  @IsTest
  static void theFormatsOfferedAreTheOnesThatCanRun() {
    useFormats();

    List<ImportApi.Format> offered = ImportApi.formats();

    Assert.areEqual(2, offered.size(), 'the broken one is left out');
    Assert.areEqual('Firms', offered[0].name);
    Assert.areEqual('Firms, by header', offered[0].label);
    Assert.areEqual('Creates Accounts. Saves every row or none', offered[0].summary);
    Assert.isTrue(offered[0].headers.isEmpty());
    Assert.isTrue(offered[0].allOrNothing);
    Assert.areEqual('People', offered[1].name);
    Assert.areEqual('Creates or updates Contacts, matched on Email', offered[1].summary);
    Assert.areEqual(new List<String>{ 'Email', 'Surname' }, offered[1].headers);
    Assert.isFalse(offered[1].allOrNothing);
  }

  @IsTest
  static void aRunSavesOrOnlyChecks() {
    useFormats();
    String text = 'Email,Surname\nada@api.example.com,Lovelace\n,Hopper\n';

    ImportResult checked = ImportApi.run('People', text, 0, false);
    Assert.areEqual(0, [SELECT COUNT() FROM Contact]);
    ImportResult done = ImportApi.run('People', text, 100, true);

    Assert.isFalse(checked.saved);
    Assert.areEqual(1, checked.created);
    Assert.isTrue(done.saved);
    Assert.areEqual(1, done.created);
    Assert.areEqual(1, done.failed);
    Assert.areEqual(103, done.failures[0].row, 'a later part of a file numbers its rows from where the earlier parts stopped');
    Assert.areEqual('Lovelace', [SELECT LastName FROM Contact].LastName);
  }

  @IsTest
  static void aRefusalReachesTheComponentAsItsMessage() {
    useFormats();

    try {
      ImportApi.run('People', 'Email\nada@api.example.com', 0, true);
      Assert.fail('expected a refusal');
    } catch (AuraHandledException refused) {
      Assert.areEqual('The file does not fit the format People: it has no column headed Surname', refused.getMessage());
    }
  }
}
