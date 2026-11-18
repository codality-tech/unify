/**
 * Runs the statements the framework's utilities guide makes, from a subscriber org: every call
 * here crosses the namespace, so it also proves the utilities can be reached.
 */
@IsTest
private class GuideUtilitiesTest {
  @IsTest
  static void randomValuesHaveTheShapeAskedFor() {
    String code = unif.RandomUtil.getString(8);
    String pin = unif.RandomUtil.getString(4, '0123456789');
    Integer quantity = unif.RandomUtil.getIntegerBetween(1, 10);
    Object pick = unif.RandomUtil.getListItem(new List<Object>{ 'Hot', 'Warm', 'Cold' });

    Assert.areEqual(8, code.length());
    Assert.isTrue(Pattern.matches('[0-9]{4}', pin), pin);
    Assert.isTrue(quantity >= 1 && quantity <= 10, String.valueOf(quantity));
    Assert.isTrue(new Set<Object>{ 'Hot', 'Warm', 'Cold' }.contains(pick));
  }

  @IsTest
  static void aUniqueRangeThrowsOnceItIsUsedUp() {
    Set<Integer> drawn = new Set<Integer>{
      unif.RandomUtil.getIntegerBetweenUnique(1, 2),
      unif.RandomUtil.getIntegerBetweenUnique(1, 2)
    };
    Assert.areEqual(new Set<Integer>{ 1, 2 }, drawn);

    try {
      unif.RandomUtil.getIntegerBetweenUnique(1, 2);
      Assert.fail('The range was used up');
    } catch (unif.RandomUtil.RuntimeException expected) {
      Assert.isNotNull(expected.getMessage());
    }
  }

  @IsTest
  static void fakeIdsAreWellFormedAndNeverRepeat() {
    Id first = unif.IdUtil.generateId(Account.SObjectType);
    Id second = unif.IdUtil.generateId(Account.SObjectType);
    Id third = unif.RandomUtil.getIdUnique(Account.SObjectType);

    Assert.areEqual(Account.SObjectType, first.getSObjectType());
    Assert.areEqual(3, new Set<Id>{ first, second, third }.size());
    Assert.areEqual(Contact.SObjectType, unif.IdUtil.generateId(App.s.model(Contact.SObjectType)).getSObjectType());
  }

  @IsTest
  static void idsBecomeEmptyRecordsOfOneObjectUnlessMixedIsAllowed() {
    Id accountId = unif.IdUtil.generateId(Account.SObjectType);
    Id contactId = unif.IdUtil.generateId(Contact.SObjectType);

    List<SObject> stubs = unif.IdUtil.toRecords(new Set<Id>{ accountId }, false);
    Assert.areEqual(1, stubs.size());
    Assert.areEqual(accountId, stubs[0].Id);
    Assert.areEqual(new Set<String>{ 'Id' }, stubs[0].getPopulatedFieldsAsMap().keySet());

    Assert.areEqual(2, unif.IdUtil.toRecords(new Set<Id>{ accountId, contactId }, true).size());
    try {
      unif.IdUtil.toRecords(new Set<Id>{ accountId, contactId }, false);
      Assert.fail('Two objects were not allowed');
    } catch (Exception expected) {
      Assert.isTrue(expected.getMessage().contains('mixed'), expected.getMessage());
    }
  }

  @IsTest
  static void aTrackerReportsOnlyTheIdsItHasNotSeen() {
    Id known = unif.IdUtil.generateId(Account.SObjectType);
    Id later = unif.IdUtil.generateId(Account.SObjectType);
    unif.IdUtil.ITracker tracker = unif.IdUtil.getTracker();

    Assert.areEqual(new Set<Id>{ known }, tracker.getNovelIds(new Set<Id>{ known }, true));
    Assert.areEqual(new Set<Id>{ later }, tracker.getNovelIds(new Set<Id>{ known, later }, true));
    Assert.areEqual(new Set<Id>{ known, later }, tracker.getIds());
  }

  @IsTest
  static void fieldHelpersCompareCropAndJoinRecords() {
    Id sameId = unif.IdUtil.generateId(Account.SObjectType);
    Id movedId = unif.IdUtil.generateId(Account.SObjectType);
    Id newId = unif.IdUtil.generateId(Account.SObjectType);
    List<Account> current = new List<Account>{
      new Account(Id = sameId, Name = 'Same', Rating = 'Hot'),
      new Account(Id = movedId, Name = 'Moved', Rating = 'Cold'),
      new Account(Id = newId, Name = 'New', Rating = 'Warm')
    };
    Map<Id, SObject> previous = new Map<Id, SObject>{
      sameId => new Account(Id = sameId, Name = 'Renamed', Rating = 'Hot'),
      movedId => new Account(Id = movedId, Name = 'Moved', Rating = 'Hot')
    };

    List<SObject> moved = unif.FieldUtil.changed(current, previous, new List<SObjectField>{ Account.Rating });
    Assert.areEqual(new Set<Id>{ movedId, newId }, new Map<Id, SObject>(moved).keySet());

    SObject slim = unif.FieldUtil.crop(current[0], new Set<SObjectField>{ Account.Name });
    Assert.areEqual(new Set<String>{ 'Name' }, slim.getPopulatedFieldsAsMap().keySet());

    Account merged = (Account) unif.FieldUtil.join(new Account(Name = 'Incoming'), new Account(Name = 'Existing', Industry = 'Energy'));
    Assert.areEqual('Incoming', merged.Name);
    Assert.areEqual('Energy', merged.Industry);
  }

  @IsTest
  static void fieldHelpersReadPicklistsAndAddresses() {
    Assert.isFalse(unif.FieldUtil.getPicklistValues(Account.Rating).isEmpty());
    Assert.isTrue(unif.FieldUtil.getDependentPicklistValues(Account.Rating).isEmpty());

    Account source = new Account(BillingStreet = '1 Main St', BillingCity = 'Springfield');
    Contact target = new Contact();
    unif.FieldUtil.copyAddress(source, 'Billing', target, 'Mailing');

    Assert.areEqual('1 Main St', target.MailingStreet);
    Assert.areEqual('Springfield', target.MailingCity);
    Assert.isTrue(unif.FieldUtil.addressIsBlank(target, 'Other'));
    Assert.isFalse(unif.FieldUtil.addressIsBlank(target, 'Mailing'));
  }

  @IsTest
  static void aTemplateFillsBlanksOrEveryFieldThatDiffers() {
    Account template = new Account(Industry = 'Other', Rating = 'Cold');
    Account partial = new Account(Name = 'Partial', Rating = 'Hot');
    Account complete = new Account(Name = 'Complete', Industry = 'Other', Rating = 'Cold');
    List<Account> accounts = new List<Account>{ partial, complete };

    Assert.isTrue(unif.RecordsUtil.updateWhereBlank(accounts, template, null));
    Assert.areEqual('Other', partial.Industry);
    Assert.areEqual('Hot', partial.Rating);
    Assert.isFalse(unif.RecordsUtil.updateWhereBlank(accounts, template, null));

    Assert.isTrue(unif.RecordsUtil.updateWhereDifferent(accounts, template, null));
    Assert.areEqual('Cold', partial.Rating);
  }

  @IsTest
  static void aTemplateTracksTheRecordsItChangedInAWork() {
    Account stale = new Account(Name = 'Stale');
    Account current = new Account(Name = 'Current', Industry = 'Other');
    insert new List<Account>{ stale, current };

    unif.IWork work = App.s.work();
    unif.RecordsUtil.updateWhereBlank(new List<Account>{ stale, current }, new Account(Industry = 'Other'), work);
    work.apply();

    Assert.areEqual('Other', [SELECT Industry FROM Account WHERE Id = :stale.Id].Industry);
  }

  @IsTest
  static void csvQuotesEveryCellAndFollowsLookups() {
    Contact person = new Contact(LastName = 'O"Neil, Pat', Account = new Account(Name = 'Acme'));

    String csv = unif.CsvUtil.toCsv(new List<String>{ 'LastName', 'Account.Name' }, new List<SObject>{ person });
    String labelled = unif.CsvUtil.toCsv(new Map<String, String>{ 'LastName' => 'Surname' }, new List<SObject>{ person });

    Assert.areEqual('"LastName","Account.Name"\n"O""Neil, Pat","Acme"', csv.trim());
    Assert.isTrue(labelled.startsWith('"Surname"\n'), labelled);
  }

  @IsTest
  static void csvIsReadIntoAHeaderAndRows() {
    String mark = String.fromCharArray(new List<Integer>{ 65279 });
    String text = mark + ' Name ;Note\r\n"Acme; Inc";"said ""hi""\nthen left"\r\n\r\nShort\r\n';

    unif.CsvUtil.Table table = unif.CsvUtil.read(text);

    Assert.areEqual(';', table.separator);
    Assert.areEqual(new List<String>{ 'Name', 'Note' }, table.header, 'trimmed, and without the byte order mark');
    Assert.areEqual(new List<String>{ 'Acme; Inc', 'said "hi"\nthen left' }, table.rows[0]);
    Assert.isTrue(unif.CsvUtil.isBlank(table.rows[1]), 'a blank row beneath the header is kept');
    Assert.areEqual(new List<String>{ 'Short' }, table.rows[2], 'rows need not be the same length');
    Assert.areEqual(2, table.rowNumber(0));
    Assert.areEqual(4, table.rowNumber(2));

    Assert.isTrue(unif.CsvUtil.read('').header.isEmpty());
    Assert.areEqual(2, unif.CsvUtil.rows('a,b\nc,d', ',').size(), 'every row, with no header taken off');
    Assert.areEqual('\t', unif.CsvUtil.separatorOf('a\tb'));
    try {
      unif.CsvUtil.read('a,"b');
      Assert.fail('expected a refusal');
    } catch (unif.CsvUtil.GeneralException refused) {
      Assert.areEqual('A quoted cell is opened and never closed', refused.getMessage());
    }
  }

  @IsTest
  static void textBecomesTheValueAFieldTakes() {
    Assert.areEqual(Date.newInstance(2026, 1, 31), unif.FieldUtil.fromText(Opportunity.CloseDate, '2026-01-31'));
    Assert.areEqual(1234.5, unif.FieldUtil.fromText(Opportunity.Amount, '1,234.50'));
    Assert.areEqual('Closed Won', unif.FieldUtil.fromText(Opportunity.StageName, 'closed won'));
    Assert.areEqual(true, unif.FieldUtil.fromText(Contact.DoNotCall, 'Yes'));
    Assert.areEqual(50, unif.FieldUtil.fromText(Opportunity.Probability, '50%'));
    Assert.areEqual(Time.newInstance(14, 30, 0, 0), unif.FieldUtil.fromText(BusinessHours.MondayStartTime, '14:30'));
    Assert.isNull(unif.FieldUtil.fromText(Opportunity.Amount, '  '), 'blank text is null');

    try {
      unif.FieldUtil.fromText(Opportunity.CloseDate, 'soon');
      Assert.fail('expected a refusal');
    } catch (unif.FieldUtil.GeneralException refused) {
      Assert.areEqual('"soon" is not a date; write it like 2026-01-31', refused.getMessage());
    }
    try {
      unif.FieldUtil.fromText(Opportunity.Amount, '1,5');
      Assert.fail('expected a refusal');
    } catch (unif.FieldUtil.GeneralException refused) {
      Assert.areEqual('"1,5" is not a number', refused.getMessage());
    }

    Assert.isFalse(unif.FieldUtil.takesText(Account.BillingAddress.getDescribe()));
    Assert.isTrue(unif.FieldUtil.takesText(Account.Name.getDescribe()));
  }

  @IsTest
  static void aSecondListMovesInStepWithTheSortedKeys() {
    List<String> names = new List<String>{ 'Ada', 'Grace', 'Edsger' };
    List<Decimal> scores = new List<Decimal>{ 72, 95, 88 };

    unif.TandemSortingUtil.sort(names, scores, false, true);

    Assert.areEqual(new List<String>{ 'Grace', 'Edsger', 'Ada' }, names);
    Assert.areEqual(new List<Decimal>{ 95, 88, 72 }, scores);
  }

  @IsTest
  static void recordsSortByAValueAcrossALookup() {
    List<Contact> people = new List<Contact>{
      new Contact(LastName = 'Second', Account = new Account(Name = 'Zenith')),
      new Contact(LastName = 'First', Account = new Account(Name = 'Acme'))
    };

    unif.IPath accountName = App.s.model(Contact.SObjectType).path('Account.Name');
    unif.TandemSortingUtil.sort(people, accountName, true, true);

    Assert.areEqual('First', people[0].LastName);
  }

  @IsTest
  static void stringsCompareWithNullAsEmpty() {
    Assert.isTrue(unif.StringUtil.areEquivalent(null, '', false));
    Assert.isTrue(unif.StringUtil.areEquivalent('ACME', 'acme', false));
    Assert.isFalse(unif.StringUtil.areEquivalent('ACME', 'acme', true));
    Assert.isTrue(unif.StringUtil.containsAll(new List<String>{ 'a', 'B', 'c' }, new List<String>{ 'A', 'b' }, false));
    Assert.isFalse(unif.StringUtil.containsAny(new List<String>{ 'a' }, new List<String>{ 'A' }, true));
  }

  @IsTest
  static void persistentValuesReadBackAsTheTypeStored() {
    unif.Persistent.INamespace sync = unif.Persistent.getNamespace('guide_sync');
    Datetime moment = Datetime.newInstanceGmt(2030, 1, 15, 10, 0, 0);

    sync.put('lastRun', moment);
    sync.put('attempts', 3);
    Assert.areEqual(moment, (Datetime) sync.get('lastRun'));
    Assert.areEqual(3, (Integer) sync.get('attempts'));
    Assert.areEqual(new Set<String>{ 'lastRun', 'attempts' }, sync.keySet());

    Assert.isFalse(unif.Persistent.getNamespace('other').containsKey('lastRun'));

    sync.put('attempts', null);
    sync.remove('lastRun');
    Assert.isTrue(sync.keySet().isEmpty());
    Assert.isNull(unif.Persistent.getNamespace('not a prefix'));
  }

  @IsTest
  static void aSnapshotDeltaShowsWhatTheWorkConsumed() {
    unif.LimitsUtil.Snapshot before = new unif.LimitsUtil.Snapshot();
    List<Account> none = [SELECT Id FROM Account LIMIT 1];
    String consumed = new unif.LimitsUtil.Snapshot().getDelta(before).stringify();

    Assert.isTrue(Pattern.compile('(?m)^.*Quer.*: .*\\(1/').matcher(consumed).find(), consumed);
  }

  @IsTest
  static void aPrinterCollectsLinesIntoOneBlock() {
    unif.DebugUtil.IPrinter printer = unif.DebugUtil.printer()
      .writeSection('Sync')
      .inc()
      .write('3 accounts changed')
      .writePretty(new Map<String, Object>{ 'ok' => true })
      .dec()
      .writeLimits();
    printer.print();

    String block = printer.toString();
    Assert.isTrue(block.contains('Sync'), block);
    Assert.isTrue(block.contains('  3 accounts changed'), block);
    Assert.areNotEqual(unif.DebugUtil.printer(), unif.DebugUtil.printer());
    Assert.areEqual(unif.DebugUtil.printer, unif.DebugUtil.printer);
  }

  @IsTest
  static void charsetsConvertBetweenBases() {
    Assert.areEqual('ff', unif.CharUtil.numeric.convert('255', 2, unif.CharUtil.lowerhex));
    Assert.areEqual('101', unif.CharUtil.charset('01').fromDecimal(5, 3));
    Assert.areEqual(12, unif.CharUtil.alphadec.generateRandom(12).length());
  }

  @IsTest
  static void anIdSurvivesTheTripToAUuidAndBack() {
    Id accountId = unif.IdUtil.generateId(Account.SObjectType);
    unif.UuidUtil.Converter plain = new unif.UuidUtil.Converter(null);

    String uuid = plain.fromRecordId(accountId);

    Assert.isTrue(Pattern.matches('[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}', uuid), uuid);
    Assert.areEqual(accountId, plain.toRecordId(uuid));
  }
}
