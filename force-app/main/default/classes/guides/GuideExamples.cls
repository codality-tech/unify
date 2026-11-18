/**
 * The example classes from the framework's extension and testing guides, as real code, so the
 * guides' statements can be run (GuideExtensionTest). They are registered in GuideApp, which stands
 * in for the guides' App.
 */
global class GuideExamples {
  /** How many times CopyableQuery's initialization hook has run in this transaction. */
  public static Integer copyableHookRuns = 0;

  // Custom query classes

  global class AccountQuery extends inj.BaseQuery {
    global override Set<SObjectField> getDefaultFields() {
      return new Set<SObjectField>{ Account.Id, Account.Name, Account.Industry, Account.AnnualRevenue };
    }

    public AccountQuery inIndustry(String industry) {
      addCondition(GuideApp.s.eq(Account.Industry, industry));
      return this;
    }

    public AccountQuery overRevenue(Decimal floor) {
      addCondition(GuideApp.s.gt(Account.AnnualRevenue, floor));
      return this;
    }
  }

  global class OpenCaseQuery extends inj.BaseQuery {
    global override Set<SObjectField> getDefaultFields() {
      return new Set<SObjectField>{ Case.Id, Case.Subject, Case.Priority };
    }

    global override void onInitialized(inj.IModel source) {
      addCondition(GuideApp.s.eq(Case.IsClosed, false));
      orderings().add(GuideApp.s.ordering(Case.CreatedDate, false, true));
    }
  }

  /** Registered, but says nothing about its fields. */
  public class PlainContactQuery extends inj.BaseQuery {
  }

  /** Calls what it inherits directly, with no  */
  global class DirectLeadQuery extends inj.BaseQuery {
    global override void onInitialized(inj.IModel source) {
      addCondition(GuideApp.s.eq(Lead.IsConverted, false));
      orderings().add(GuideApp.s.ordering(Lead.CreatedDate, false, true));
      setLimit(5);
    }

    public DirectLeadQuery fromSource(String leadSource) {
      addCondition(GuideApp.s.eq(Lead.LeadSource, leadSource));
      return this;
    }
  }

  /** A domain that calls what it inherits directly, with no  */
  global class DirectLeads extends inj.BaseDomain {
    global DirectLeads() {
      super();
    }

    public DirectLeads(List<Lead> rows) {
      super(GuideApp.s.model(Lead.SObjectType), rows);
    }

    public List<Lead> items() {
      return (List<Lead>) records();
    }

    public Integer howMany() {
      return size();
    }

    public List<Lead> renamed(Map<Id, SObject> oldMap) {
      return (List<Lead>) getChangedRecords(oldMap, new Set<SObjectField>{ Lead.LastName });
    }
  }

  /** Can be created directly and copied, as well as by the factory. */
  global class CopyableQuery extends inj.BaseQuery {
    global CopyableQuery() {
      super(GuideApp.s.model(Account.SObjectType));
    }

    global CopyableQuery(CopyableQuery other) {
      super(other);
    }

    global override void onInitialized(inj.IModel source) {
      GuideExamples.copyableHookRuns++;
      addCondition(GuideApp.s.eq(Account.Type, 'Customer'));
    }
  }

  // A domain class

  global class Opportunities extends inj.BaseDomain {
    global Opportunities() {
      super();
    }

    // For use outside triggers: new Opportunities(records)
    public Opportunities(List<Opportunity> records) {
      super(GuideApp.s.model(Opportunity.SObjectType), records);
    }

    public List<Opportunity> items() {
      return (List<Opportunity>) records();
    }

    public override void onBeforeUpsert(Map<Id, SObject> oldMap) {
      for (Opportunity row : items()) {
        if (String.isBlank(row.NextStep)) {
          row.NextStep = 'Qualify';
        }
      }
    }

    public override void onAfterUpsert(Map<Id, SObject> oldMap) {
      Set<SObjectField> stage = new Set<SObjectField>{ Opportunity.StageName };
      inj.IWork work = GuideApp.s.work();
      for (Opportunity row : (List<Opportunity>) getChangedRecords(oldMap, stage)) {
        if (row.StageName == 'Closed Won') {
          work.track(new Task(WhatId = row.Id, Subject = 'Send the welcome pack'));
        }
      }
      work.apply();
    }
  }

  // A trigger handler that is not a domain

  public class AuditTrail implements inj.ITriggered {
    public void handleTrigger(
      TriggerOperation operation,
      List<SObject> newRecords,
      List<SObject> oldRecords,
      Map<Id, SObject> oldMap,
      inj.IModel model
    ) {
      // called for every operation the trigger is declared for
    }
  }

  // A service

  public interface IInvoicing {
    void invoice(Set<Id> opportunityIds);
  }

  public class Invoicing implements IInvoicing {
    public Set<Id> invoiced = new Set<Id>();

    public void invoice(Set<Id> opportunityIds) {
      invoiced.addAll(opportunityIds);
    }
  }

  // Code that queries through the application it is given, so a test can hand it a mock

  public class AccountReview {
    private inj.IApplication app;

    public AccountReview(inj.IApplication app) {
      this.app = app;
    }

    public List<Account> largeAccounts() {
      inj.IQuery large = app.qf().make(Account.SObjectType);
      large.addCondition(app.gt(Account.AnnualRevenue, 1000000));
      return (List<Account>) large.run();
    }
  }

  // A batch whose execute step starts another batch, which the platform does not allow directly.
  // The second batch leaves a record behind so a run can be checked afterwards.

  public class StartsABatch implements inj.IBatchIterableHandler {
    private String mark;

    public StartsABatch(String mark) {
      this.mark = mark;
    }

    public Iterable<Object> batchStart() {
      return new List<Object>{ mark };
    }

    public void batchExecute(Iterable<Object> scope) {
      inj.Async.iterable(new LeavesAMark(mark)).run();
    }

    public void batchFinish() {
    }

    public Integer batchDefaultSize() {
      return 1;
    }
  }

  public class LeavesAMark implements inj.IBatchIterableHandler {
    private String mark;

    public LeavesAMark(String mark) {
      this.mark = mark;
    }

    public Iterable<Object> batchStart() {
      return new List<Object>{ mark };
    }

    public void batchExecute(Iterable<Object> scope) {
      List<Reform_Private_Sample__c> marks = new List<Reform_Private_Sample__c>();
      for (Object each : scope) {
        marks.add(new Reform_Private_Sample__c(Name = (String) each));
      }
      insert marks;
    }

    public void batchFinish() {
    }

    public Integer batchDefaultSize() {
      return 1;
    }
  }
}
