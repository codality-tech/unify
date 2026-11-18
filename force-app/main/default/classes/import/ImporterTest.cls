/**
 * Imports made through real saves. The formats are given by each test, apart from the last, which
 * runs the sample formats stored in the org.
 */
@IsTest
private class ImporterTest {
  private static ImportFormat people() {
    return new ImportFormat('People')
      .into(Contact.SObjectType)
      .creatingOrChanging(Contact.Email)
      .column('Email', Contact.Email)
      .column('Surname', Contact.LastName)
      .required()
      .column('First', Contact.FirstName)
      .column('Company', Contact.AccountId, Account.Name)
      .column('Born', Contact.Birthdate)
      .column('Title', Contact.Title)
      .otherwise('Member')
      .constant(Contact.LeadSource, 'Other');
  }

  // The example triggers on Account do work of their own; these tests are not about them.
  private static void quietAccountTriggers() {
    App.s.tf().disable(new List<SObjectType>{ Account.SObjectType });
    App.b.tf().disable();
  }

  // Saved past the org's duplicate rules, for the tests that need two records alike.
  private static void insertAlike(List<SObject> records) {
    Database.DMLOptions options = new Database.DMLOptions();
    options.DuplicateRuleHeader.allowSave = true;
    Database.insert(records, options);
  }

  private static String refusal(String formatName, String text) {
    try {
      Importer.load(formatName, text);
    } catch (Importer.ImportException refused) {
      return refused.getMessage();
    }
    return null;
  }

  private static Map<Integer, String> failuresByRow(ImportResult result) {
    Map<Integer, String> found = new Map<Integer, String>();
    for (ImportResult.Failure failure : result.failures) {
      found.put(failure.row, failure.message);
    }
    return found;
  }

  @IsTest
  static void rowsBecomeNewRecordsOrChangeTheOnesTheyMatch() {
    quietAccountTriggers();
    ImportFormats.use(new List<ImportFormat>{ people() });
    Account acme = new Account(Name = 'Acme');
    insert new List<Account>{ acme, new Account(Name = 'Globex') };
    Contact ada = new Contact(LastName = 'Old', Email = 'ada@imp.example.com', Title = 'Countess', Department = 'Engines');
    insert ada;

    ImportResult result = Importer.load(
      'People',
      'Email,Surname,First,Company,Born,Title,Notes\n' +
        'ADA@imp.example.com,Lovelace,Ada,acme,1815-12-10,,first programmer\n' +
        'grace@imp.example.com,Hopper,Grace,Globex,,Admiral,\n' +
        'alan@imp.example.com,"Turing, A",Alan,,1912-06-23,,\n'
    );

    Assert.isTrue(result.saved);
    Assert.areEqual('People', result.format);
    Assert.areEqual(3, result.rows);
    Assert.areEqual(2, result.created);
    Assert.areEqual(1, result.updated);
    Assert.areEqual(0, result.failed);
    Assert.isTrue(result.failures.isEmpty());
    Assert.isNull(result.failuresCsv);
    Assert.areEqual(new List<String>{ 'Notes' }, result.ignored);
    Assert.areEqual(7, result.columns.size());
    Assert.areEqual(ada.Id, result.idsByRow.get(2));

    Map<String, Contact> saved = new Map<String, Contact>();
    for (Contact each : [SELECT Email, LastName, FirstName, Account.Name, Birthdate, Title, LeadSource, Department FROM Contact]) {
      saved.put(each.Email.toLowerCase(), each);
    }
    Assert.areEqual(3, saved.size());
    Contact changed = saved.get('ada@imp.example.com');
    Assert.areEqual(ada.Id, changed.Id, 'matched whatever the case of the email');
    Assert.areEqual('Lovelace', changed.LastName);
    Assert.areEqual('Acme', changed.Account.Name, 'the company is found by its name, whatever the case');
    Assert.areEqual(Date.newInstance(1815, 12, 10), changed.Birthdate);
    Assert.areEqual('Member', changed.Title, 'an empty cell takes the column\'s default');
    Assert.areEqual('Engines', changed.Department, 'a field the file does not mention is left alone');
    Assert.areEqual('Admiral', saved.get('grace@imp.example.com').Title);
    Assert.areEqual('Globex', saved.get('grace@imp.example.com').Account.Name);
    Assert.areEqual(result.idsByRow.get(3), saved.get('grace@imp.example.com').Id);
    Assert.areEqual('Turing, A', saved.get('alan@imp.example.com').LastName);
    Assert.isNull(saved.get('alan@imp.example.com').Account, 'an empty lookup cell is left empty');
    Assert.areEqual('Other', saved.get('alan@imp.example.com').LeadSource, 'a constant fills every row');
  }

  @IsTest
  static void aRowThatCannotBeSavedFailsAloneAndSaysWhy() {
    quietAccountTriggers();
    ImportFormats.use(new List<ImportFormat>{ people() });
    insertAlike(new List<Account>{ new Account(Name = 'Twin'), new Account(Name = 'Twin') });
    String accountName = Account.Name.getDescribe().getLabel();

    ImportResult result = Importer.load(
      'People',
      'Email,Surname,First,Company,Born\n' +
        'good@imp.example.com,Fine,,,\n' +
        'baddate@imp.example.com,Date,,,soon\n' +
        'nosurname@imp.example.com,,,,\n' +
        'lost@imp.example.com,Lost,,Nowhere Ltd,\n' +
        'twins@imp.example.com,Twins,,Twin,\n' +
        'GOOD@imp.example.com,Again,,,\n' +
        ',NoEmail,,,\n' +
        'long@imp.example.com,' + 'x'.repeat(81) + ',,,\n' +
        ' , ,,,\n' +
        'multi@imp.example.com,,,,soon\n'
    );

    Assert.isTrue(result.saved);
    Assert.areEqual(9, result.rows, 'the blank row is not counted');
    Assert.areEqual(1, result.created);
    Assert.areEqual(8, result.failed);
    Map<Integer, String> why = failuresByRow(result);
    Assert.areEqual('Born: "soon" is not a date; write it like 2026-01-31', why.get(3));
    Assert.areEqual('Surname is empty', why.get(4));
    Assert.areEqual('Company: no Account you can see has ' + accountName + ' "Nowhere Ltd"', why.get(5));
    Assert.areEqual('Company: 2 Accounts have ' + accountName + ' "Twin"', why.get(6));
    Assert.areEqual('Email: row 2 has "GOOD@imp.example.com" too', why.get(7));
    Assert.areEqual('Email is empty, and rows are matched on it', why.get(8));
    Assert.isTrue(why.get(9).contains('max length'), 'what the org says about a row it refuses: ' + why.get(9));
    Assert.areEqual('Surname is empty; Born: "soon" is not a date; write it like 2026-01-31', why.get(11), 'the blank row keeps its number');
    Assert.areEqual('Fine', [SELECT LastName FROM Contact].LastName);
  }

  @IsTest
  static void theRowsThatFailedComeBackAsAFileToCorrect() {
    ImportFormats.use(new List<ImportFormat>{ people() });

    ImportResult first = Importer.load('People', 'Email,Surname,Note\ngood@imp.example.com,Fine,ok\nbad@imp.example.com,,"said ""no"""\n');
    unif.CsvUtil.Table file = unif.CsvUtil.read(first.failuresCsv);

    Assert.areEqual(new List<String>{ 'Email', 'Surname', 'Note', 'Error' }, file.header);
    Assert.areEqual(1, file.rows.size());
    Assert.areEqual(new List<String>{ 'bad@imp.example.com', '', 'said "no"', 'Surname is empty' }, file.rows[0]);

    // Sent again uncorrected, the file is read as before and its Error column is brought up to date.
    ImportResult second = Importer.load('People', first.failuresCsv);
    unif.CsvUtil.Table again = unif.CsvUtil.read(second.failuresCsv);

    Assert.areEqual(new List<String>{ 'Note', 'Error' }, second.ignored);
    Assert.areEqual(file.header, again.header);
    Assert.areEqual(file.rows[0], again.rows[0]);

    ImportResult corrected = Importer.load('People', first.failuresCsv.replace('"bad@imp.example.com",""', '"bad@imp.example.com","Better"'));
    Assert.areEqual(1, corrected.created);
    Assert.isNull(corrected.failuresCsv);
  }

  @IsTest
  static void aCheckDoesEverythingButSave() {
    ImportFormats.use(new List<ImportFormat>{ people() });
    insert new Contact(LastName = 'Old', Email = 'ada@imp.example.com');

    ImportResult result = Importer.check('People', 'Email,Surname,Born\nada@imp.example.com,Lovelace,\nnew@imp.example.com,New,\nbad@imp.example.com,Bad,soon\n');

    Assert.isFalse(result.saved);
    Assert.areEqual(1, result.created, 'what a save would make');
    Assert.areEqual(1, result.updated);
    Assert.areEqual(1, result.failed);
    Assert.areEqual(0, result.held);
    Assert.isTrue(result.idsByRow.isEmpty());
    Assert.isTrue(result.notes.isEmpty());
    Assert.areEqual('Old', [SELECT LastName FROM Contact].LastName, 'nothing was saved');
  }

  @IsTest
  static void anAllOrNothingFormatSavesNoRowUnlessEveryRowCanBeSaved() {
    ImportFormats.use(new List<ImportFormat>{ people().allOrNothing() });
    String header = 'Email,Surname,Born\n';
    String good = 'good@imp.example.com,Fine,\n';

    ImportResult unreadable = Importer.load('People', header + good + 'bad@imp.example.com,Bad,soon\n');
    ImportResult refusedByTheOrg = Importer.load('People', header + good + 'long@imp.example.com,' + 'x'.repeat(81) + ',\n');

    for (ImportResult result : new List<ImportResult>{ unreadable, refusedByTheOrg }) {
      Assert.isFalse(result.saved);
      Assert.areEqual(0, result.created);
      Assert.areEqual(1, result.failed);
      Assert.areEqual(1, result.held);
      Assert.areEqual(new List<String>{ 'Nothing was saved: this format saves every row or none, and 1 row failed' }, result.notes);
      Assert.isTrue(result.idsByRow.isEmpty());
    }
    Assert.areEqual(0, [SELECT COUNT() FROM Contact], 'the row that was saved before the other failed is undone');

    ImportResult clean = Importer.load('People', header + good);

    Assert.isTrue(clean.saved);
    Assert.areEqual(1, clean.created);
    Assert.areEqual(1, [SELECT COUNT() FROM Contact]);
  }

  @IsTest
  static void aFormatThatOnlyChangesRecordsFailsARowItCannotMatch() {
    ImportFormats.use(
      new List<ImportFormat>{
        new ImportFormat('Titles').into(Contact.SObjectType).changing(Contact.Email).column('Email', Contact.Email).column('Title', Contact.Title)
      }
    );
    insertAlike(
      new List<Contact>{
        new Contact(LastName = 'Lovelace', Email = 'ada@imp.example.com'),
        new Contact(LastName = 'One', Email = 'both@imp.example.com'),
        new Contact(LastName = 'Other', Email = 'both@imp.example.com')
      }
    );

    ImportResult result = Importer.load('Titles', 'Email,Title\nada@imp.example.com,Countess\nghost@imp.example.com,Nobody\nboth@imp.example.com,Either\n');

    Assert.areEqual(1, result.updated);
    Assert.areEqual(0, result.created);
    Map<Integer, String> why = failuresByRow(result);
    Assert.areEqual('Email: no Contact you can see has Email "ghost@imp.example.com"', why.get(3));
    Assert.areEqual('Email: 2 Contacts have Email "both@imp.example.com"', why.get(4));
    Assert.areEqual('Countess', [SELECT Title FROM Contact WHERE LastName = 'Lovelace'].Title);
    Assert.areEqual(3, [SELECT COUNT() FROM Contact]);
  }

  @IsTest
  static void rowsMatchedOnIdChangeThatRecordAndARowWithNoIdIsNew() {
    ImportFormats.use(
      new List<ImportFormat>{
        new ImportFormat('ById').into(Contact.SObjectType).creatingOrChanging(Contact.Id).column('Id', Contact.Id).column('Surname', Contact.LastName)
      }
    );
    Contact ada = new Contact(LastName = 'Old', Email = 'ada@imp.example.com');
    insert ada;
    Id gone = unif.IdUtil.generateId(Contact.SObjectType);
    String idLabel = Contact.Id.getDescribe().getLabel();

    ImportResult result = Importer.load('ById', 'Id,Surname\n' + String.valueOf(ada.Id).left(15) + ',Lovelace\n,Hopper\n' + gone + ',Ghost\nnonsense,Odd\n');

    Assert.areEqual(1, result.updated);
    Assert.areEqual(1, result.created);
    Map<Integer, String> why = failuresByRow(result);
    Assert.areEqual('Id: no Contact you can see has ' + idLabel + ' "' + gone + '"', why.get(4), 'an Id that is not found is never made a new record');
    Assert.areEqual('Id: "nonsense" is not an Id', why.get(5));
    Assert.areEqual('Lovelace', [SELECT LastName FROM Contact WHERE Id = :ada.Id].LastName);
    Assert.areEqual(2, [SELECT COUNT() FROM Contact]);
  }

  @IsTest
  static void anEmptyCellLeavesAFieldAloneAndTheClearMarkEmptiesIt() {
    ImportFormats.use(new List<ImportFormat>{ people() });
    insert new Contact(LastName = 'Lovelace', Email = 'ada@imp.example.com', Title = 'Countess', Birthdate = Date.newInstance(1815, 12, 10));

    ImportResult result = Importer.load(
      'People',
      'Email,Surname,Born,Title\nada@imp.example.com,Lovelace,,#N/A\nnew@imp.example.com,#N/A,,\n#N/A,Nobody,,\n'
    );

    Contact ada = [SELECT Title, Birthdate FROM Contact WHERE Email = 'ada@imp.example.com'];
    Assert.isNull(ada.Title, 'emptied, not given the default');
    Assert.areEqual(Date.newInstance(1815, 12, 10), ada.Birthdate, 'left as it was');
    Map<Integer, String> why = failuresByRow(result);
    Assert.areEqual('Surname cannot be emptied', why.get(3));
    Assert.areEqual('Email cannot be emptied', why.get(4));
  }

  @IsTest
  static void aFileThatCannotBeReadAtAllIsRefusedBeforeAnythingIsSaved() {
    ImportFormats.use(new List<ImportFormat>{ people() });

    Assert.areEqual('The file is empty', refusal('People', ''));
    Assert.areEqual('The file is empty', refusal('People', '\n\n'));
    Assert.areEqual('The file does not fit the format People: it has no column headed Surname', refusal('People', 'Email\nada@imp.example.com'));
    Assert.areEqual('The file cannot be read: A quoted cell is opened and never closed', refusal('People', 'Email,Surname\n"ada,Lovelace'));
    Assert.areEqual('There is no import format named Nope', refusal('Nope', 'Email,Surname'));
    Assert.areEqual(0, Importer.load('People', 'Email,Surname\n').rows, 'a header with nothing under it is an import of no rows');
  }

  @IsTest
  static void aFormatWithNoColumnsReadsTheFileByItsHeaders() {
    quietAccountTriggers();
    ImportFormats.use(new List<ImportFormat>{ new ImportFormat('Firms').into(Account.SObjectType) });
    insert new Account(Name = 'Acme');
    String revenue = Account.AnnualRevenue.getDescribe().getLabel();
    String industry = Account.Industry.getDescribe().getPicklistValues()[0].getValue();

    ImportResult result = Importer.load('Firms', 'Name;Industry;' + revenue + ';Parent.Name;Notes\nChild Co;' + industry.toUpperCase() + ';1,500.50;acme;"a;b"\n');

    Assert.areEqual(1, result.created, String.valueOf(result.failures));
    Assert.areEqual(new List<String>{ 'Notes' }, result.ignored);
    Account made = [SELECT Industry, AnnualRevenue, Parent.Name FROM Account WHERE Name = 'Child Co'];
    Assert.areEqual(industry, made.Industry, 'a picklist value is found whatever its case');
    Assert.areEqual(1500.50, made.AnnualRevenue);
    Assert.areEqual('Acme', made.Parent.Name, 'the semicolons were taken as the separator, and the parent found by name');
  }

  @IsTest
  static void aLaterPartOfAFileNumbersItsRowsFromWhereTheEarlierPartsStopped() {
    ImportFormats.use(new List<ImportFormat>{ people() });

    ImportResult result = Importer.run('People', 'Email,Surname\nbad@imp.example.com,\n', 200, true);

    Assert.areEqual(202, result.failures[0].row, 'the 201st row under the header is row 202 of the file');
  }

  @IsTest
  static void textTooLargeForOneTransactionIsRefusedBeforeAnythingIsSaved() {
    ImportFormats.use(new List<ImportFormat>{ people() });
    Importer.rowsPerTransaction = 2;
    String text = 'Email,Surname\na@imp.example.com,A\nb@imp.example.com,B\nc@imp.example.com,C\n';

    Assert.areEqual('The text has 3 rows, and 2 is the most one transaction can save. Send it in parts.', refusal('People', text));
    Assert.areEqual(0, [SELECT COUNT() FROM Contact]);
    Assert.areEqual(3, Importer.check('People', text).created, 'a check saves nothing, so it may be any size');
  }

  @IsTest
  static void twoHundredRowsCostTwoQueriesAndTwoSaves() {
    quietAccountTriggers();
    ImportFormats.use(new List<ImportFormat>{ people() });
    insert new Account(Name = 'Acme');
    List<Contact> existing = new List<Contact>();
    String text = 'Email,Surname,First,Company\n';
    for (Integer at = 0; at < 200; at++) {
      if (at < 100) {
        existing.add(new Contact(LastName = 'Before' + at, FirstName = 'Number' + at, Email = 'p' + at + '@imp.example.com'));
      }
      text += 'p' + at + '@imp.example.com,After' + at + ',Number' + at + ',Acme\n';
    }
    insert existing;

    Integer queries = Limits.getQueries();
    Integer saves = Limits.getDmlStatements();
    ImportResult result = Importer.load('People', text);

    Assert.areEqual(100, result.created, String.valueOf(result.failures));
    Assert.areEqual(100, result.updated);
    Assert.areEqual(2, Limits.getQueries() - queries, 'one to find the companies, one to match the rows');
    Assert.areEqual(2, Limits.getDmlStatements() - saves, 'one insert and one update');
    Assert.areEqual(200, [SELECT COUNT() FROM Contact WHERE LastName LIKE 'After%' AND Account.Name = 'Acme']);
  }

  @IsTest
  static void aFieldThatCanBeWrittenOnlyOnNewOrOnlyOnExistingRecordsIsLeftOutOfTheOthers() {
    ImportFormats.use(
      new List<ImportFormat>{
        new ImportFormat('Leads')
          .into(Lead.SObjectType)
          .creatingOrChanging(Lead.Email)
          .column('Email', Lead.Email)
          .column('Surname', Lead.LastName)
          .column('Company', Lead.Company)
          .column('Bounced', Lead.EmailBouncedReason)
          .column('Converted', Lead.IsConverted)
      }
    );
    Assert.isTrue(Lead.IsConverted.getDescribe().isCreateable() && !Lead.IsConverted.getDescribe().isUpdateable(), 'this test relies on a field of each kind');
    Assert.isTrue(!Lead.EmailBouncedReason.getDescribe().isCreateable() && Lead.EmailBouncedReason.getDescribe().isUpdateable());
    insert new Lead(LastName = 'Old', Company = 'Engines', Email = 'ada@imp.example.com');
    String text = 'Email,Surname,Company,Bounced,Converted\nada@imp.example.com,Lovelace,Engines,mailbox full,no\nnew@imp.example.com,Hopper,Navy,mailbox full,no\n';

    ImportResult result = Importer.load('Leads', text);

    Assert.areEqual(1, result.created, String.valueOf(result.failures));
    Assert.areEqual(1, result.updated);
    Assert.areEqual(
      new List<String>{
        Lead.EmailBouncedReason.getDescribe().getLabel() + ' is not filled in on new records: it can only be changed on existing ones',
        Lead.IsConverted.getDescribe().getLabel() + ' is left as it is on existing records: it can only be filled in on new ones'
      },
      result.notes
    );
    Assert.areEqual('mailbox full', [SELECT EmailBouncedReason FROM Lead WHERE LastName = 'Lovelace'].EmailBouncedReason);
    Assert.isNull([SELECT EmailBouncedReason FROM Lead WHERE LastName = 'Hopper'].EmailBouncedReason);

    // A file with only new rows has no record that could take the bounce reason, so it is refused.
    Assert.areEqual(
      'You cannot fill in ' + Lead.EmailBouncedReason.getDescribe().getLabel() + ' on Leads',
      refusal('Leads', 'Email,Surname,Company,Bounced\nthird@imp.example.com,Turing,Bletchley,mailbox full\n')
    );
  }

  // The import is made as the user.

  private static Integer usersMade = 0;

  /** A user on the Minimum Access profile, with the object and field access given. */
  private static User userWith(List<ObjectPermissions> onObjects, List<String> editableFields) {
    usersMade++;
    User made = new User(
      ProfileId = [SELECT Id FROM Profile WHERE Name = 'Minimum Access - Salesforce'].Id,
      LastName = 'Importer' + usersMade,
      Alias = 'import' + usersMade,
      Email = 'loader' + usersMade + '@imp.example.com',
      Username = 'loader' + usersMade + '.' + UserInfo.getOrganizationId() + '.' + System.now().getTime() + '@imp.example.com',
      TimeZoneSidKey = 'GMT',
      LocaleSidKey = 'en_US',
      EmailEncodingKey = 'UTF-8',
      LanguageLocaleKey = 'en_US'
    );
    // Users and permission sets are setup objects: saved as another "user" so the test can save records afterwards.
    System.runAs(new User(Id = UserInfo.getUserId())) {
      insert made;
      PermissionSet granted = new PermissionSet(Name = 'Importer_Test_' + usersMade, Label = 'Importer Test ' + usersMade);
      insert granted;
      for (ObjectPermissions onObject : onObjects) {
        onObject.ParentId = granted.Id;
      }
      insert onObjects;
      List<FieldPermissions> onFields = new List<FieldPermissions>();
      for (String field : editableFields) {
        onFields.add(
          new FieldPermissions(ParentId = granted.Id, SobjectType = field.substringBefore('.'), Field = field, PermissionsRead = true, PermissionsEdit = true)
        );
      }
      insert onFields;
      insert new PermissionSetAssignment(AssigneeId = made.Id, PermissionSetId = granted.Id);
    }
    return made;
  }

  private static ObjectPermissions contactAccess(Boolean maySeeAll, Boolean mayCreate, Boolean mayEdit) {
    return new ObjectPermissions(
      SobjectType = 'Contact',
      PermissionsRead = true,
      PermissionsCreate = mayCreate,
      PermissionsEdit = mayEdit,
      PermissionsViewAllRecords = maySeeAll
    );
  }

  @IsTest
  static void theImportIsSavedAsThePersonAndBelongsToThem() {
    ImportFormats.use(new List<ImportFormat>{ people() });
    User loader = userWith(
      new List<ObjectPermissions>{ contactAccess(false, true, true) },
      new List<String>{ 'Contact.Email', 'Contact.Birthdate', 'Contact.Title', 'Contact.LeadSource', 'Contact.AccountId' }
    );
    // The loader cannot see this contact, so its email matches nothing for them.
    insert new Contact(LastName = 'Hidden', Email = 'ada@imp.example.com');

    ImportResult result;
    System.runAs(loader) {
      result = Importer.load('People', 'Email,Surname,Born\nada@imp.example.com,Lovelace,1815-12-10\n');
    }

    Assert.areEqual(1, result.created, String.valueOf(result.failures));
    Contact made = [SELECT OwnerId, Birthdate FROM Contact WHERE LastName = 'Lovelace'];
    Assert.areEqual(loader.Id, made.OwnerId);
    Assert.areEqual(Date.newInstance(1815, 12, 10), made.Birthdate);
  }

  @IsTest
  static void aRecordThePersonCanSeeButMayNotEditFailsAsItsOwnRow() {
    ImportFormats.use(new List<ImportFormat>{ people() });
    User loader = userWith(new List<ObjectPermissions>{ contactAccess(true, true, true) }, new List<String>{ 'Contact.Email', 'Contact.Title', 'Contact.LeadSource' });
    // A contact with no account belongs to its owner alone. The loader may view every contact, and edit only their own.
    insert new Contact(LastName = 'Old', Email = 'ada@imp.example.com');

    ImportResult result;
    System.runAs(loader) {
      result = Importer.load('People', 'Email,Surname\nada@imp.example.com,Lovelace\nnew@imp.example.com,New\n');
    }

    Assert.areEqual(1, result.created, String.valueOf(result.failures));
    Assert.areEqual(1, result.failed);
    Assert.areEqual(2, result.failures[0].row);
    Assert.isTrue(String.isNotBlank(result.failures[0].message), 'the org says why');
    Assert.areEqual('Old', [SELECT LastName FROM Contact WHERE Email = 'ada@imp.example.com'].LastName);
  }

  @IsTest
  static void anObjectThePersonMayNotWriteStopsTheFile() {
    ImportFormats.use(new List<ImportFormat>{ people() });
    List<String> fields = new List<String>{ 'Contact.Email', 'Contact.Title', 'Contact.LeadSource' };
    User reader = userWith(new List<ObjectPermissions>{ contactAccess(true, false, false) }, fields);
    insert new Contact(LastName = 'Old', Email = 'ada@imp.example.com');

    System.runAs(reader) {
      Assert.areEqual('You cannot create Contacts', refusal('People', 'Email,Surname\nnew@imp.example.com,New\n'));
      Assert.areEqual('You cannot change Contacts', refusal('People', 'Email,Surname\nada@imp.example.com,Lovelace\n'));
      Assert.areEqual(1, Importer.load('People', 'Email,Surname\nbad@imp.example.com,\n').failed, 'with no row to save there is nothing to refuse');
    }
    Assert.areEqual('Old', [SELECT LastName FROM Contact].LastName);
  }

  @IsTest
  static void aFieldThePersonMayNotFillInStopsTheFile() {
    ImportFormats.use(new List<ImportFormat>{ people() });
    User loader = userWith(
      new List<ObjectPermissions>{ contactAccess(false, true, true) },
      new List<String>{ 'Contact.Email', 'Contact.Title', 'Contact.LeadSource' }
    );
    String birthdate = Contact.Birthdate.getDescribe().getLabel();

    System.runAs(loader) {
      Assert.areEqual('You cannot fill in ' + birthdate + ' on Contacts', refusal('People', 'Email,Surname,Born\nnew@imp.example.com,New,1815-12-10\n'));
      Assert.areEqual(1, Importer.load('People', 'Email,Surname\nnew@imp.example.com,New\n').created, 'a file without that column is fine');
    }
  }

  @IsTest
  static void whatThePersonCannotReadCannotBeMatchedOrLookedUp() {
    ImportFormats.use(new List<ImportFormat>{ people() });
    User blind = userWith(new List<ObjectPermissions>{ contactAccess(false, true, true) }, new List<String>{ 'Contact.Title', 'Contact.LeadSource', 'Contact.AccountId' });
    User sighted = userWith(
      new List<ObjectPermissions>{ contactAccess(false, true, true) },
      new List<String>{ 'Contact.Email', 'Contact.Title', 'Contact.LeadSource', 'Contact.AccountId' }
    );
    String email = Contact.Email.getDescribe().getLabel();

    System.runAs(blind) {
      Assert.areEqual('You cannot read ' + email + ' on Contacts, which rows are matched on', refusal('People', 'Email,Surname\nnew@imp.example.com,New\n'));
    }
    System.runAs(sighted) {
      Assert.areEqual(
        'You cannot read Accounts, which the column Company looks up',
        refusal('People', 'Email,Surname,Company\nnew@imp.example.com,New,Acme\n')
      );
    }
  }

  @IsTest
  static void aRecordThePersonCannotSeeIsNotFound() {
    ImportFormats.use(
      new List<ImportFormat>{
        new ImportFormat('Samples').into(Reform_Private_Sample__c.SObjectType).changing(Reform_Private_Sample__c.Name).column('Name', Reform_Private_Sample__c.Name)
      }
    );
    User loader = userWith(
      new List<ObjectPermissions>{ new ObjectPermissions(SobjectType = 'Reform_Private_Sample__c', PermissionsRead = true, PermissionsEdit = true) },
      new List<String>()
    );
    // Shared privately: this one belongs to the user running the test.
    insert new Reform_Private_Sample__c(Name = 'Theirs');
    String nameLabel = Reform_Private_Sample__c.Name.getDescribe().getLabel();

    ImportResult result;
    System.runAs(loader) {
      result = Importer.load('Samples', 'Name\nTheirs\n');
    }

    Assert.areEqual('Name: no Reform Private Sample you can see has ' + nameLabel + ' "Theirs"', result.failures[0].message);
  }

  // The formats stored in the org, on the Rollup sample's objects.

  @IsTest
  static void theStoredSampleFormatsRunAndTheRollupsFollow() {
    User loader = new User(
      ProfileId = [SELECT Id FROM Profile WHERE Name = 'Minimum Access - Salesforce'].Id,
      LastName = 'Sampler',
      Alias = 'sampler',
      Email = 'sampler@imp.example.com',
      Username = 'sampler.' + UserInfo.getOrganizationId() + '.' + System.now().getTime() + '@imp.example.com',
      TimeZoneSidKey = 'GMT',
      LocaleSidKey = 'en_US',
      EmailEncodingKey = 'UTF-8',
      LanguageLocaleKey = 'en_US'
    );
    System.runAs(new User(Id = UserInfo.getUserId())) {
      insert loader;
      insert new PermissionSetAssignment(AssigneeId = loader.Id, PermissionSetId = [SELECT Id FROM PermissionSet WHERE Name = 'Rollup_Sample'].Id);
    }
    String parentName = Rollup_Sample_Parent__c.Name.getDescribe().getLabel();

    ImportResult parents;
    ImportResult children;
    ImportResult again;
    Test.startTest();
    System.runAs(loader) {
      parents = Importer.load('Sample_Parents', 'Name\nNorth\nSouth\n');
      children = Importer.load(
        'Sample_Children',
        'Child,Parent,Amount,Due,Kind,Status\n' +
          'One,North,10,2030-01-15,a,\n' +
          'Two,north,20.5,,b,Closed\n' +
          'Three,South,5,,a,\n' +
          'Four,East,1,,a,\n'
      );
      again = Importer.load('Sample_Children', 'Child,Amount\nOne,100\n');
    }
    Test.stopTest();

    Assert.areEqual(2, parents.created, String.valueOf(parents.failures));
    Assert.areEqual(3, children.created, String.valueOf(children.failures));
    Assert.areEqual('Parent: no Rollup Sample Parent you can see has ' + parentName + ' "East"', children.failures[0].message);
    Assert.areEqual(1, again.updated, String.valueOf(again.failures));
    Map<String, Rollup_Sample_Parent__c> held = new Map<String, Rollup_Sample_Parent__c>();
    for (Rollup_Sample_Parent__c parent : [SELECT Name, Child_Count__c, Open_Amount__c, Earliest_Due__c FROM Rollup_Sample_Parent__c]) {
      held.put(parent.Name, parent);
    }
    Assert.areEqual(2, held.get('North').Child_Count__c.intValue(), 'the rollups ran as the rows were saved');
    Assert.areEqual(100, held.get('North').Open_Amount__c.intValue(), 'One was given the default status, Open, and then a new amount; Two is closed');
    Assert.areEqual(Date.newInstance(2030, 1, 15), held.get('North').Earliest_Due__c);
    Assert.areEqual(1, held.get('South').Child_Count__c.intValue());
  }
}
