/** A format built in code, and a format read from metadata records. */
@IsTest
private class ImportFormatTest {
  @IsTest
  static void aFormatStartsOutCreatingRecordsOneRowAtATime() {
    ImportFormat format = new ImportFormat('People').into(Contact.SObjectType);

    Assert.areEqual('People', format.name);
    Assert.areEqual('People', format.label);
    Assert.areEqual('Contact', format.objectName);
    Assert.areEqual(ImportFormat.Writes.CREATE, format.mode);
    Assert.isNull(format.matchField);
    Assert.isFalse(format.allOrNothing);
    Assert.isTrue(format.active);
    Assert.isTrue(format.columns.isEmpty());
  }

  @IsTest
  static void aFormatSaysWhatItsRowsDoAndWhatTheyAreMatchedOn() {
    ImportFormat format = new ImportFormat('People').into(Contact.SObjectType);

    Assert.areEqual(ImportFormat.Writes.CHANGE, format.changing(Contact.Email).mode);
    Assert.areEqual('Email', format.matchField);
    Assert.areEqual(ImportFormat.Writes.BOTH, format.creatingOrChanging(Contact.Id).mode);
    Assert.areEqual('Id', format.matchField);
    Assert.areEqual(ImportFormat.Writes.CREATE, format.creating().mode);
    Assert.isNull(format.matchField);
    Assert.isTrue(format.allOrNothing().allOrNothing);
  }

  @IsTest
  static void columnsAreAddedInOrderAndTheLastOneCanBeQualified() {
    ImportFormat format = new ImportFormat('People')
      .into(Contact.SObjectType)
      .column('Surname', Contact.LastName)
      .required()
      .column('Company', Contact.AccountId, Account.Name)
      .column('Title', Contact.Title)
      .otherwise('Member')
      .constant(Contact.LeadSource, 'Other');

    Assert.areEqual(4, format.columns.size());
    Assert.areEqual('Surname', format.columns[0].header);
    Assert.areEqual('LastName', format.columns[0].fieldName);
    Assert.isTrue(format.columns[0].required);
    Assert.areEqual('AccountId', format.columns[1].fieldName);
    Assert.areEqual('Name', format.columns[1].relatedField);
    Assert.isFalse(format.columns[1].required);
    Assert.areEqual('Member', format.columns[2].fallback);
    Assert.isNull(format.columns[3].header, 'a constant has no column in the file');
    Assert.areEqual('LeadSource', format.columns[3].fieldName);
    Assert.areEqual('Other', format.columns[3].fallback);
  }

  @IsTest
  static void metadataRecordsBecomeAFormat() {
    ImportFormat format = ImportFormat.fromMetadata(
      new Import_Format__mdt(
        DeveloperName = 'People',
        MasterLabel = 'People from the events team',
        Object__c = 'Contact',
        Operation__c = 'BOTH',
        Match_Field__c = 'Email',
        All_Or_Nothing__c = true,
        Active__c = true
      ),
      new List<Import_Column__mdt>{
        new Import_Column__mdt(Header__c = 'Company', Field__c = 'AccountId', Match_Related_By__c = 'Name', Required__c = true),
        new Import_Column__mdt(Field__c = 'LeadSource', Default__c = 'Other')
      }
    );

    Assert.areEqual('People', format.name);
    Assert.areEqual('People from the events team', format.label);
    Assert.areEqual('Contact', format.objectName);
    Assert.areEqual(ImportFormat.Writes.BOTH, format.mode);
    Assert.areEqual('Email', format.matchField);
    Assert.isTrue(format.allOrNothing);
    Assert.isTrue(format.active);
    Assert.areEqual('Company', format.columns[0].header);
    Assert.areEqual('AccountId', format.columns[0].fieldName);
    Assert.areEqual('Name', format.columns[0].relatedField);
    Assert.isTrue(format.columns[0].required);
    Assert.isNull(format.columns[1].header);
    Assert.areEqual('Other', format.columns[1].fallback);
    Assert.isFalse(format.columns[1].required);
  }

  @IsTest
  static void aRecordThatNamesNoOperationOrIsSwitchedOffSaysSo() {
    ImportFormat format = ImportFormat.fromMetadata(new Import_Format__mdt(DeveloperName = 'Odd', Object__c = 'Contact'), new List<Import_Column__mdt>());

    Assert.isNull(format.mode, 'left for the plan to report');
    Assert.isFalse(format.active);
    Assert.isFalse(format.allOrNothing);
  }
}
