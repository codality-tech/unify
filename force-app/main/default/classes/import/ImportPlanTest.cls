/** A format checked against the schema, and then fitted to the header of a file. */
@IsTest
private class ImportPlanTest {
  private static ImportFormat people() {
    return new ImportFormat('People')
      .into(Contact.SObjectType)
      .creatingOrChanging(Contact.Email)
      .column('Email', Contact.Email)
      .column('Surname', Contact.LastName)
      .required()
      .column('First', Contact.FirstName)
      .column('Company', Contact.AccountId, Account.Name)
      .column('Title', Contact.Title)
      .otherwise('Member')
      .constant(Contact.LeadSource, 'Other');
  }

  private static List<String> problemsOf(ImportFormat format) {
    return ImportPlan.compile(format).problems;
  }

  private static ImportFormat withColumn(SObjectType target, String header, String fieldName, String relatedField) {
    ImportFormat format = new ImportFormat('Odd').into(target);
    ImportFormat.Column column = new ImportFormat.Column();
    column.header = header;
    column.fieldName = fieldName;
    column.relatedField = relatedField;
    format.columns.add(column);
    return format;
  }

  // Compiling

  @IsTest
  static void aSoundFormatResolvesItsObjectItsMatchFieldAndItsColumns() {
    ImportPlan plan = ImportPlan.compile(people());

    Assert.isTrue(plan.isSound(), String.join(plan.problems, '; '));
    Assert.areEqual(Contact.SObjectType, plan.model.token());
    Assert.areEqual(Contact.Email, plan.matchOn);
    Assert.isTrue(plan.namesItsColumns());
    Assert.areEqual(new List<String>{ 'Email', 'Surname', 'First', 'Company', 'Title' }, plan.headers(), 'a constant has no header');
    Assert.areEqual('Creates or updates Contacts, matched on Email', plan.summary());
  }

  @IsTest
  static void theSummarySaysWhatTheFormatDoes() {
    ImportFormat creating = new ImportFormat('New').into(Account.SObjectType);
    ImportFormat strict = new ImportFormat('Strict').into(Contact.SObjectType).changing(Contact.Email).allOrNothing();

    Assert.areEqual('Creates Accounts', ImportPlan.compile(creating).summary());
    Assert.areEqual('Updates Contacts, matched on Email. Saves every row or none', ImportPlan.compile(strict).summary());
    Assert.isFalse(ImportPlan.compile(creating).namesItsColumns());
    Assert.isTrue(ImportPlan.compile(creating).headers().isEmpty());
  }

  @IsTest
  static void anObjectOrOperationThatCannotBeResolvedIsAProblem() {
    ImportFormat lost = new ImportFormat('Lost');
    lost.objectName = 'Nope__c';
    ImportFormat silent = new ImportFormat('Silent').into(Contact.SObjectType);
    silent.mode = null;

    Assert.areEqual(new List<String>{ 'unknown object Nope__c' }, problemsOf(lost));
    Assert.areEqual(new List<String>{ 'unknown object null' }, problemsOf(new ImportFormat('Blank')));
    Assert.areEqual(new List<String>{ 'it does not say whether rows create records, change them or both' }, problemsOf(silent));
  }

  @IsTest
  static void theMatchFieldMustSuitWhatTheRowsDo() {
    ImportFormat creating = new ImportFormat('A').into(Contact.SObjectType);
    creating.matchField = 'Email';
    ImportFormat changing = new ImportFormat('B').into(Contact.SObjectType);
    changing.mode = ImportFormat.Writes.CHANGE;
    ImportFormat unknown = new ImportFormat('C').into(Contact.SObjectType).changing(Contact.Email);
    unknown.matchField = 'Nope__c';
    ImportFormat notText = new ImportFormat('D').into(Contact.SObjectType).changing(Contact.Birthdate);
    ImportFormat unfilled = new ImportFormat('E').into(Contact.SObjectType).creatingOrChanging(Contact.Email).column('Surname', Contact.LastName);

    Assert.areEqual(new List<String>{ 'a format that only creates records has nothing to match on Email' }, problemsOf(creating));
    Assert.areEqual(new List<String>{ 'it changes records, so it needs a field to match rows on' }, problemsOf(changing));
    Assert.areEqual(new List<String>{ 'unknown match field Contact.Nope__c' }, problemsOf(unknown));
    Assert.areEqual(new List<String>{ 'Contact.Birthdate is not text or an Id, so rows cannot be matched on it' }, problemsOf(notText));
    Assert.areEqual(new List<String>{ 'no column fills Email, which rows are matched on' }, problemsOf(unfilled));
  }

  @IsTest
  static void aColumnThatCannotBeFilledIsAProblemThatNamesIt() {
    Assert.areEqual(new List<String>{ 'column Wrong: unknown field Contact.Nope__c' }, problemsOf(withColumn(Contact.SObjectType, 'Wrong', 'Nope__c', null)));
    Assert.areEqual(
      new List<String>{ 'column LeadSource: it has neither a header nor a default, so nothing would fill it' },
      problemsOf(withColumn(Contact.SObjectType, null, 'LeadSource', null))
    );
    Assert.areEqual(
      new List<String>{ 'column Number: CaseNumber is worked out by the org and cannot be filled in' },
      problemsOf(withColumn(Case.SObjectType, 'Number', 'CaseNumber', null))
    );
    Assert.areEqual(
      new List<String>{ 'column Address: BillingAddress cannot be filled in from text' },
      problemsOf(withColumn(Account.SObjectType, 'Address', 'BillingAddress', null))
    );
  }

  @IsTest
  static void twoColumnsMayNotShareAHeaderOrAField() {
    ImportFormat format = new ImportFormat('Twice')
      .into(Contact.SObjectType)
      .column('Email', Contact.Email)
      .column('email ', Contact.Title)
      .column('Mail', Contact.Email);

    Assert.areEqual(new List<String>{ 'column email : another column has the same header', 'column Mail: another column fills Email too' }, problemsOf(format));
  }

  @IsTest
  static void aColumnThatFindsARelatedRecordNeedsALookupAndATextFieldToFindItBy() {
    Assert.areEqual(
      new List<String>{ 'column Surname: LastName is not a lookup, so it has no related record to match by Name' },
      problemsOf(withColumn(Contact.SObjectType, 'Surname', 'LastName', 'Name'))
    );
    Assert.areEqual(
      new List<String>{ 'column What: WhatId can point at more than one object, so its cells must hold Ids' },
      problemsOf(withColumn(Task.SObjectType, 'What', 'WhatId', 'Name'))
    );
    Assert.areEqual(
      new List<String>{ 'column Company: unknown field Account.Nope__c' },
      problemsOf(withColumn(Contact.SObjectType, 'Company', 'AccountId', 'Nope__c'))
    );
    Assert.areEqual(
      new List<String>{ 'column Company: Account.AnnualRevenue is not text, so records cannot be matched by it' },
      problemsOf(withColumn(Contact.SObjectType, 'Company', 'AccountId', 'AnnualRevenue'))
    );
  }

  @IsTest
  static void theColumnRowsAreMatchedOnHoldsItsOwnValues() {
    ImportFormat format = withColumn(Contact.SObjectType, 'Company', 'AccountId', 'Name').changing(Contact.AccountId);

    Assert.areEqual(new List<String>{ 'column Company: rows are matched on AccountId, so its cells hold its own values, not Name' }, problemsOf(format));
  }

  @IsTest
  static void aDefaultIsCheckedWhenTheFormatIsCompiled() {
    ImportFormat format = new ImportFormat('Born').into(Contact.SObjectType).column('Born', Contact.Birthdate).otherwise('soon');

    Assert.areEqual(new List<String>{ 'column Born: default "soon" is not a date; write it like 2026-01-31' }, problemsOf(format));
  }

  @IsTest
  static void aFieldThatIsWorkedOutMayStillBeWhatRowsAreMatchedOn() {
    ImportFormat format = new ImportFormat('Cases').into(Case.SObjectType).changing(Case.CaseNumber).column('Number', Case.CaseNumber).column('Subject', Case.Subject);

    Assert.isTrue(problemsOf(format).isEmpty(), String.join(problemsOf(format), '; '));
  }

  // Fitting a file whose format names its columns

  @IsTest
  static void namedColumnsAreFoundByHeaderWhateverTheCaseOrOrder() {
    ImportPlan.Layout layout = ImportPlan.compile(people()).layout(new List<String>{ 'surname', 'EMAIL', 'Notes', 'Company', '' });

    Assert.isTrue(layout.fits(), String.join(layout.problems, '; '));
    Assert.areEqual(5, layout.slots.size(), 'First is not in the file and is left out; Title and the constant are filled from their defaults');
    Assert.areEqual(Contact.Email, layout.slots[0].field);
    Assert.areEqual(1, layout.slots[0].position);
    Assert.isTrue(layout.slots[0].matches);
    Assert.areEqual(layout.slots[0], layout.matching);
    Assert.areEqual(0, layout.slots[1].position);
    Assert.isTrue(layout.slots[1].required);
    Assert.areEqual(Contact.AccountId, layout.slots[2].field);
    Assert.areEqual(3, layout.slots[2].position);
    Assert.areEqual(Account.SObjectType, layout.slots[2].related.token());
    Assert.areEqual(Account.Name, layout.slots[2].relatedBy);
    Assert.isNull(layout.slots[3].position, 'no Title column: every row takes the default');
    Assert.areEqual('Member', layout.slots[3].fallback);
    Assert.isNull(layout.slots[4].position);
    Assert.areEqual(new List<String>{ 'Notes' }, layout.ignored, 'a column with no header is not worth a mention');
  }

  @IsTest
  static void aSlotSaysHowItIsRead() {
    ImportPlan.Layout layout = ImportPlan.compile(people()).layout(new List<String>{ 'Email', 'Surname', 'Company' });
    String accountId = Contact.AccountId.getDescribe().getLabel();
    String accountName = Account.Name.getDescribe().getLabel();
    String leadSource = Contact.LeadSource.getDescribe().getLabel();

    Assert.areEqual('Surname', layout.slots[1].title());
    Assert.areEqual('Surname fills ' + Contact.LastName.getDescribe().getLabel(), layout.slots[1].reading());
    Assert.areEqual('Company fills ' + accountId + ', matched by ' + accountName, layout.slots[2].reading());
    Assert.areEqual(leadSource, layout.slots[4].title(), 'a constant goes by its field');
    Assert.areEqual(leadSource + ' fills ' + leadSource, layout.slots[4].reading());
  }

  @IsTest
  static void aFileThatLacksAColumnTheFormatNeedsDoesNotFit() {
    ImportPlan plan = ImportPlan.compile(people());

    Assert.areEqual(new List<String>{ 'it has no column headed Surname' }, plan.layout(new List<String>{ 'Email', 'First' }).problems);
    Assert.areEqual(new List<String>{ 'it has no column headed Email' }, plan.layout(new List<String>{ 'Surname' }).problems);
    Assert.areEqual(new List<String>{ 'it has two columns headed Email' }, plan.layout(new List<String>{ 'Email', 'Surname', 'email' }).problems);
    Assert.isTrue(plan.layout(new List<String>{ 'Email', 'Surname', 'Notes', 'Notes' }).fits(), 'a column that is not read may repeat');
  }

  // Fitting a file whose format names no columns

  @IsTest
  static void withoutNamedColumnsAHeaderIsAFieldNameALabelOrAPathThroughALookup() {
    ImportPlan plan = ImportPlan.compile(new ImportFormat('Firms').into(Account.SObjectType));
    String revenue = Account.AnnualRevenue.getDescribe().getLabel();

    ImportPlan.Layout layout = plan.layout(new List<String>{ 'Name', 'industry', revenue, 'Parent.Name', 'Notes', '' });

    Assert.isTrue(layout.fits(), String.join(layout.problems, '; '));
    Assert.areEqual(4, layout.slots.size());
    Assert.areEqual(Account.Name, layout.slots[0].field);
    Assert.areEqual(Account.Industry, layout.slots[1].field);
    Assert.areEqual(Account.AnnualRevenue, layout.slots[2].field);
    Assert.areEqual(2, layout.slots[2].position);
    Assert.areEqual(Account.ParentId, layout.slots[3].field);
    Assert.areEqual(Account.Name, layout.slots[3].relatedBy);
    Assert.areEqual('Parent.Name', layout.slots[3].header);
    Assert.areEqual(new List<String>{ 'Notes' }, layout.ignored);
    Assert.isNull(layout.matching);
  }

  @IsTest
  static void aHeaderForAFieldTheOrgWorksOutIsPassedOverUnlessRowsAreMatchedOnIt() {
    ImportPlan creating = ImportPlan.compile(new ImportFormat('Cases').into(Case.SObjectType));
    ImportPlan changing = ImportPlan.compile(new ImportFormat('Cases').into(Case.SObjectType).changing(Case.CaseNumber));

    ImportPlan.Layout made = creating.layout(new List<String>{ 'CaseNumber', 'Subject' });
    ImportPlan.Layout matched = changing.layout(new List<String>{ 'CaseNumber', 'Subject' });

    Assert.areEqual(new List<String>{ 'CaseNumber' }, made.ignored, 'an exported file often carries such columns');
    Assert.areEqual(1, made.slots.size());
    Assert.isTrue(matched.ignored.isEmpty());
    Assert.areEqual(Case.CaseNumber, matched.matching.field);
  }

  @IsTest
  static void aLabelTwoFieldsShareNamesNeitherOfThem() {
    ImportPlan plan = ImportPlan.compile(new ImportFormat('Deals').into(Opportunity.SObjectType));
    String shared = Opportunity.ForecastCategoryName.getDescribe().getLabel();
    Assert.areEqual(shared, Opportunity.ForecastCategory.getDescribe().getLabel(), 'the two fields this test relies on have one label');

    ImportPlan.Layout layout = plan.layout(new List<String>{ 'Name', shared, 'ForecastCategoryName' });

    Assert.areEqual(new List<String>{ shared }, layout.ignored, 'the label could mean either field, so it is not read');
    Assert.areEqual(2, layout.slots.size(), 'the API name says which one is meant');
    Assert.areEqual(Opportunity.ForecastCategoryName, layout.slots[1].field);
  }

  @IsTest
  static void aFileThatCannotBeReadByItsHeadersDoesNotFit() {
    ImportPlan creating = ImportPlan.compile(new ImportFormat('Firms').into(Account.SObjectType));
    ImportPlan changing = ImportPlan.compile(new ImportFormat('Firms').into(Account.SObjectType).changing(Account.Id));
    String name = Account.Name.getDescribe().getLabel();

    Assert.areEqual(new List<String>{ 'none of its columns is one this format reads' }, creating.layout(new List<String>{ 'Notes', 'More' }).problems);
    Assert.areEqual(new List<String>{ 'column ' + name + ': another column fills Name too' }, creating.layout(new List<String>{ 'Name', name }).problems);
    Assert.areEqual(new List<String>{ 'column Owner.Nope: unknown field User.Nope' }, creating.layout(new List<String>{ 'Name', 'Owner.Nope' }).problems);
    Assert.areEqual(
      new List<String>{ 'it has no column for ' + Account.Id.getDescribe().getLabel() + ', which rows are matched on' },
      changing.layout(new List<String>{ 'Name' }).problems
    );
    Assert.isTrue(changing.layout(new List<String>{ 'ID', 'Name' }).fits());
  }
}
