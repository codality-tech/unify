/**
 * The extension and testing guides' statements, run as subscriber code against the example classes
 * in GuideExamples. When one of these fails, either the framework changed or a guide is wrong.
 */
@IsTest
private class GuideExtensionTest {
  private static GuideExamples.AccountQuery bigEnergy() {
    return ((GuideExamples.AccountQuery) GuideApp.s.qf().make(Account.SObjectType)).inIndustry('Energy').overRevenue(1000000);
  }

  // The fields a query selects: what is written between SELECT and FROM.
  private static Set<String> selectedBy(inj.IQuery query) {
    return new Set<String>(query.toSoql().substringBetween('SELECT ', ' FROM ').split(', '));
  }

  private static void quietAccountTriggers() {
    App.s.tf().disable(new List<SObjectType>{ Account.SObjectType });
    App.b.tf().disable();
  }

  // Your entry point

  @IsTest
  static void aPairThatBreaksTheRegistryRulesIsRefusedWhenTheApplicationIsMade() {
    try {
      inj.Application.make(null, null, new Map<Type, Type>{ Account.class => GuideExamples.Invoicing.class }, null);
      Assert.fail('Invoicing is not a query');
    } catch (inj.Application.FactoryException refused) {
      Assert.isFalse(String.isBlank(refused.getMessage()));
    }

    // The five-argument form takes a trigger registry of its own, for handlers that are not domains.
    inj.IApplication separate = inj.Application.make(null, null, null, null, new Map<Type, Type>{ Contact.class => GuideExamples.AuditTrail.class });
    Assert.isNotNull(separate.tf());
  }

  @IsTest
  static void inheritedMethodsCanBeCalledWithoutBase() {
    inj.IApplication app = inj.Application.make(null, null, new Map<Type, Type>{ Lead.class => GuideExamples.DirectLeadQuery.class }, null);

    inj.IQuery made = app.qf().make(Lead.SObjectType);
    Assert.isTrue(made instanceof GuideExamples.DirectLeadQuery);
    String soql = ((GuideExamples.DirectLeadQuery) made).fromSource('Web').toSoql();
    Assert.isTrue(soql.contains('IsConverted = false'), soql);
    Assert.isTrue(soql.contains('LeadSource = \'Web\''), soql);
    Assert.isTrue(soql.contains('ORDER BY CreatedDate DESC'), soql);
    Assert.isTrue(soql.contains('LIMIT 5'), soql);

    Lead ada = new Lead(Id = inj.IdUtil.generateId(Lead.SObjectType), LastName = 'Lovelace', Company = 'Analytical');
    GuideExamples.DirectLeads leads = new GuideExamples.DirectLeads(new List<Lead>{ ada });
    Assert.areEqual(1, leads.howMany());
    Assert.areEqual('Lovelace', leads.items()[0].LastName);
    Lead before = new Lead(Id = ada.Id, LastName = 'Byron');
    Assert.areEqual(1, leads.renamed(new Map<Id, SObject>{ ada.Id => before }).size());
  }

  @IsTest
  static void anObjectWithNothingRegisteredStillWorks() {
    Assert.isNotNull(GuideApp.s.qf().make(Contact.SObjectType));
    Assert.isNotNull(GuideApp.s.df().make(new List<Contact>{ new Contact(LastName = 'Ada') }));
    Assert.isNull(GuideApp.s.df().make(new List<Contact>()), 'no records, no domain');
  }

  @IsTest
  static void aFactoryTakesMorePairsLater() {
    GuideApp.s.qf().register(new Map<Type, Type>{ Lead.class => GuideExamples.PlainContactQuery.class });
    Assert.isTrue(GuideApp.s.qf().make(Lead.SObjectType) instanceof GuideExamples.PlainContactQuery);
  }

  // Custom query classes

  @IsTest
  static void aRegisteredQueryClassComesFromTheFactoryWithItsDefaults() {
    GuideExamples.AccountQuery big = bigEnergy();

    Assert.areEqual(
      'SELECT Id, Name, Industry, AnnualRevenue FROM Account WHERE (Industry = :a0 AND AnnualRevenue > :a1)',
      big.toSoql(true),
      'as run: values bound'
    );
    Assert.areEqual(
      'SELECT Id, Name, Industry, AnnualRevenue FROM Account WHERE (Industry = \'Energy\' AND AnnualRevenue > 1000000)',
      big.toSoql(),
      'for display: values inline'
    );
  }

  @IsTest
  static void aQueryClassReturnsTheRightRows() {
    quietAccountTriggers();
    insert new List<Account>{
      new Account(Name = 'Big Energy', Industry = 'Energy', AnnualRevenue = 5000000),
      new Account(Name = 'Small Energy', Industry = 'Energy', AnnualRevenue = 1000),
      new Account(Name = 'Big Retail', Industry = 'Retail', AnnualRevenue = 5000000)
    };

    List<Account> rows = (List<Account>) bigEnergy().run();

    Assert.areEqual(1, rows.size());
    Assert.areEqual('Big Energy', rows[0].Name);
  }

  @IsTest
  static void theInitializationHookShapesEveryQueryOfTheClass() {
    Assert.areEqual(
      'SELECT Id, Subject, Priority FROM Case WHERE (IsClosed = false) ORDER BY CreatedDate DESC NULLS LAST',
      GuideApp.s.qf().make(Case.SObjectType).toSoql()
    );
  }

  @IsTest
  static void aRegisteredClassThatNamesNoDefaultFieldsSelectsEveryField() {
    inj.IApplication registered = inj.Application.make(null, null, new Map<Type, Type>{ Contact.class => GuideExamples.PlainContactQuery.class }, null);
    inj.IApplication unregistered = inj.Application.make();

    inj.IQuery wide = registered.qf().make(Contact.SObjectType);
    Set<String> everyField = selectedBy(wide);
    Set<String> trimmed = selectedBy(unregistered.qf().make(Contact.SObjectType));

    Assert.isTrue(wide instanceof GuideExamples.PlainContactQuery, 'the factory made the registered class');
    Assert.isTrue(everyField.contains('Description'), 'a long text area is among every field');
    Assert.isFalse(trimmed.contains('Description'), 'and is left out of the trimmed default set');
    Assert.isTrue(everyField.size() > trimmed.size());
    wide.setLimit(1).run();
  }

  @IsTest
  static void aQueryMadeDirectlyHasNotBeenThroughTheFactory() {
    GuideExamples.CopyableQuery direct = new GuideExamples.CopyableQuery();

    Assert.areEqual(1, GuideExamples.copyableHookRuns);
    Assert.areEqual('SELECT Id FROM Account WHERE (Type = \'Customer\')', direct.toSoql(), 'Id, plus what the hook adds');
  }

  @IsTest
  static void aCopyCarriesTheOriginalsStateOnce() {
    GuideExamples.CopyableQuery original = new GuideExamples.CopyableQuery();
    original.fields().add(new Set<SObjectField>{ Account.Name });
    original.setLimit(5);

    GuideExamples.CopyableQuery copy = new GuideExamples.CopyableQuery(original);

    Assert.areEqual(2, GuideExamples.copyableHookRuns, 'the hook runs for the copy too; what it adds is then replaced by the state copied over');
    Assert.areEqual(original.toSoql(), copy.toSoql());
    Assert.areEqual(1, copy.toSoql().countMatches('Type ='), 'the hook\'s condition is there once, not twice');
    copy.setLimit(9);
    Assert.isTrue(original.toSoql().endsWith('LIMIT 5'), 'the copy is its own query');
  }

  @IsTest
  static void theFactoryCanStillCreateAClassThatBindsItself() {
    inj.IApplication other = inj.Application.make(null, null, new Map<Type, Type>{ Account.class => GuideExamples.CopyableQuery.class }, null);

    String soql = other.qf().make(Account.SObjectType).toSoql();

    Assert.areEqual(1, soql.countMatches('Type ='), 'binding it to the same object twice does nothing: ' + soql.right(120));
  }

  // Domain classes

  @IsTest
  static void aBeforeHookCanBeCalledWithNoDml() {
    List<Opportunity> deals = new List<Opportunity>{ new Opportunity(Name = 'One'), new Opportunity(Name = 'Two', NextStep = 'Negotiate') };

    new GuideExamples.Opportunities(deals).onBeforeUpsert(null);

    Assert.areEqual('Qualify', deals[0].NextStep);
    Assert.areEqual('Negotiate', deals[1].NextStep);
  }

  @IsTest
  static void onInsertEveryRecordCountsAsChanged() {
    List<Opportunity> deals = new List<Opportunity>{
      new Opportunity(Name = 'Won', StageName = 'Closed Won', CloseDate = Date.today()),
      new Opportunity(Name = 'Open', StageName = 'Prospecting', CloseDate = Date.today())
    };
    insert deals;

    new GuideExamples.Opportunities(deals).onAfterUpsert(null);

    Assert.areEqual(1, [SELECT COUNT() FROM Task WHERE WhatId = :deals[0].Id AND Subject = 'Send the welcome pack']);
    Assert.areEqual(0, [SELECT COUNT() FROM Task WHERE WhatId = :deals[1].Id]);
  }

  @IsTest
  static void onlyAChangeToTheNamedFieldsCounts() {
    Id fakeId = Opportunity.SObjectType.getDescribe().getKeyPrefix() + '000000000001';
    Opportunity before = new Opportunity(Id = fakeId, StageName = 'Prospecting', Amount = 100);
    Opportunity after = new Opportunity(Id = fakeId, StageName = 'Prospecting', Amount = 500);
    inj.IDomain deals = new GuideExamples.Opportunities(new List<Opportunity>{ after }).base();
    Map<Id, SObject> oldMap = new Map<Id, SObject>{ fakeId => before };

    Assert.areEqual(0, deals.getChangedRecords(oldMap, new Set<SObjectField>{ Opportunity.StageName }).size());
    Assert.areEqual(1, deals.getChangedRecords(oldMap, new Set<String>{ 'Amount' }).size(), 'fields can be given by name');
  }

  @IsTest
  static void theRecordsCanBeFilteredGroupedAndSummed() {
    Id acme = Account.SObjectType.getDescribe().getKeyPrefix() + '000000000001';
    List<Opportunity> rows = new List<Opportunity>{
      new Opportunity(Name = 'A', Amount = 250000, AccountId = acme, StageName = 'Prospecting'),
      new Opportunity(Name = 'B', Amount = 50000, AccountId = acme),
      new Opportunity(Name = 'C')
    };
    GuideExamples.Opportunities domain = new GuideExamples.Opportunities(rows);
    inj.IDomain deals = domain.base();

    Assert.areEqual(3, deals.size());
    Assert.isTrue(deals.toMap().isEmpty(), 'no Ids yet');
    Assert.areEqual(1, deals.filter(GuideApp.s.gt(Opportunity.Amount, 100000)).size());
    Assert.areEqual('A', ((Opportunity) deals.sort(GuideApp.s.ordering(Opportunity.Amount, false, true))[0]).Name);

    Map<Id, List<SObject>> byAccount = deals.catalogId(Opportunity.AccountId);
    Assert.areEqual(new Set<Id>{ acme }, byAccount.keySet(), 'records with no Id there are left out');
    Assert.areEqual(2, byAccount.get(acme).size());

    Map<String, List<SObject>> byStage = deals.segment(Opportunity.StageName);
    Assert.areEqual(2, byStage.get('null').size(), 'null values group under the text null');

    Decimal total = (Decimal) deals.aggregate(GuideApp.s.sum(Opportunity.Amount));
    Assert.isTrue(total == 300000, 'nulls are skipped: ' + total);

    List<Opportunity> copy = domain.items();
    copy.remove(0);
    Assert.areEqual(3, deals.size(), 'records() is a copy of the list');
    domain.items()[0].Name = 'Renamed';
    Assert.areEqual('Renamed', rows[0].Name, 'holding the domain\'s own records');
  }

  @IsTest
  static void aDomainCanBeMadeOutsideATrigger() {
    List<Opportunity> rows = new List<Opportunity>{ new Opportunity(Name = 'A') };

    Assert.isTrue(GuideApp.s.df().make(rows) instanceof GuideExamples.Opportunities, 'the registered class');
    Assert.isFalse(GuideApp.s.model(Opportunity.SObjectType).domain(rows) instanceof GuideExamples.Opportunities, 'always a plain domain');
  }

  // Triggers

  @IsTest
  static void switchingTriggersOffCounts() {
    // A blueprint for an object that does not exist is refused by its trigger (ReformBlueprints).
    Reform_Blueprint__c mistaken = new Reform_Blueprint__c(Name = 'Mistaken', Api_Name__c = 'mistaken', Sobject_Name__c = 'No_Such_Object__c');

    App.s.tf().disable();
    App.s.tf().disable();
    App.s.tf().enable();
    insert mistaken;
    Assert.isNotNull(mistaken.Id, 'still off: disabled twice, enabled once');

    App.s.tf().enable();
    mistaken.Naming_Field__c = 'Name';
    try {
      update mistaken;
      Assert.fail('triggers are back on');
    } catch (DmlException refused) {
      Assert.isTrue(refused.getMessage().contains('No_Such_Object__c'), refused.getMessage());
    }

    List<SObjectType> oneObject = new List<SObjectType>{ Reform_Blueprint__c.SObjectType };
    App.s.tf().disable(oneObject);
    update mistaken;
    App.s.tf().enable(oneObject);

    Map<SObjectType, Set<TriggerOperation>> oneOperation = new Map<SObjectType, Set<TriggerOperation>>{
      Reform_Blueprint__c.SObjectType => new Set<TriggerOperation>{ TriggerOperation.BEFORE_UPDATE }
    };
    App.s.tf().disable(oneOperation);
    mistaken.Naming_Field__c = 'Id';
    update mistaken;
    try {
      insert new Reform_Blueprint__c(Name = 'Another', Api_Name__c = 'another', Sobject_Name__c = 'No_Such_Object__c');
      Assert.fail('only updates are off');
    } catch (DmlException refused) {
      Assert.isTrue(refused.getMessage().contains('No_Such_Object__c'), refused.getMessage());
    }
    App.s.tf().enable(oneOperation);
  }

  // Services

  @IsTest
  static void aServiceIsSharedByGetAndNewFromMake() {
    GuideExamples.IInvoicing invoicing = (GuideExamples.IInvoicing) GuideApp.s.sf().get(GuideExamples.IInvoicing.class);
    Id deal = Opportunity.SObjectType.getDescribe().getKeyPrefix() + '000000000001';
    invoicing.invoice(new Set<Id>{ deal });

    Object again = GuideApp.s.sf().get(GuideExamples.IInvoicing.class);
    Object another = GuideApp.s.sf().make(GuideExamples.IInvoicing.class);

    Assert.isTrue(again === invoicing, 'get: one shared instance');
    Assert.isTrue(((GuideExamples.Invoicing) again).invoiced.contains(deal));
    Assert.isFalse(another === invoicing, 'make: a new instance each time');
    for (Integer attempt = 0; attempt < 2; attempt++) {
      try {
        if (attempt == 0) {
          GuideApp.s.sf().get(GuideExamples.AuditTrail.class);
        } else {
          GuideApp.s.sf().make(GuideExamples.AuditTrail.class);
        }
        Assert.fail('never registered');
      } catch (Exception unregistered) {
        Assert.isTrue(unregistered.getTypeName().endsWith('ServiceFactoryException'), unregistered.getTypeName());
      }
    }
  }

  // The testing guide

  @IsTest
  static void aConditionGivesTheSameAnswerInMemory() {
    inj.ICondition rule = GuideApp.s.model(Account.SObjectType).parseCondition('Industry = \'Energy\' AND AnnualRevenue > 1000000');

    Assert.isTrue(rule.evaluate(new Account(Industry = 'Energy', AnnualRevenue = 5000000)));
    Assert.isFalse(rule.evaluate(new Account(Industry = 'Retail', AnnualRevenue = 5000000)));
  }

  @IsTest
  static void aMockSchemeReturnsCannedRowsAndRecordsTheQuery() {
    List<Account> canned = new List<Account>{ new Account(Name = 'Acme', AnnualRevenue = 5000000) };
    inj.MockScheme scheme = new inj.MockScheme().returning(Account.SObjectType, canned);
    inj.IApplication app = inj.Application.make(scheme);

    List<Account> flagged = new GuideExamples.AccountReview(app).largeAccounts();

    Assert.areEqual(1, flagged.size());
    Assert.areEqual('Acme', flagged[0].Name);
    Assert.areEqual(1, scheme.queries().size());
    Assert.areEqual(1000000, scheme.bindMaps()[0].get('a0'));
    Assert.areEqual(0, [SELECT COUNT() FROM Account], 'nothing was inserted');
  }

  @IsTest
  static void aWorkCanBeAskedWhetherItHasAnythingToDo() {
    inj.IWork work = GuideApp.s.work();
    Assert.isFalse(work.hasWork());
    work.track(new Task(Subject = 'Renew'));
    Assert.isTrue(work.hasWork());
  }
}
