/**
 * Rollups over lookups: counts, sums, averages, smallest, largest and distinct counts of child
 * records, kept on the record their lookup points at. The rules are Rollup_Rule__mdt records.
 *
 * To roll an object's records up, call changed() from its after-save, after-delete and
 * after-undelete hooks, or register RollupHandler as its trigger handler.
 *
 * What a save costs, however many records and rules are involved:
 * - one aggregate query for each set of rules that share a child object, lookup and filter;
 * - one query for the parents' present values, per parent object, which also locks them;
 * - one update, of only the parents whose values differ.
 * A change that cannot alter any result costs nothing.
 *
 * A total covers every child, whoever saves one, and reaches a parent that person may not edit.
 * Reads go through RollupScheme, which runs them without sharing whoever calls; writes go through
 * a unit of work in system mode, which takes its sharing from this class.
 */
public without sharing class Rollups {
  public class RollupException extends Exception {
  }

  // The queries a transaction keeps back for everything else. When a recalculation would leave
  // fewer than this, it is queued instead of run.
  @TestVisible
  private static Integer spareQueries = 20;

  // More parents than this are read in several queries: an aggregate query returns at most 2,000 rows at once.
  @TestVisible
  private static Integer parentsPerQuery = 2000;

  // Parents already waiting for a queued recalculation in this transaction, by rule name.
  private static Map<String, Set<Id>> waiting = new Map<String, Set<Id>>();

  /**
   * Call after child records are inserted, updated, deleted or undeleted. `previous` is their
   * earlier state on update, and null otherwise.
   */
  public static void changed(unif.IDomain children, Map<Id, SObject> previous) {
    Map<String, Set<Id>> now = new Map<String, Set<Id>>();
    Map<String, Set<Id>> later = new Map<String, Set<Id>>();
    for (RollupPlan plan : RollupRules.forChild(children.source().token())) {
      Set<Id> parents = touched(plan, children, previous);
      if (!parents.isEmpty()) {
        (plan.rule.runs == RollupRule.Timing.QUEUED ? later : now).put(plan.rule.name, parents);
      }
    }
    if (!now.isEmpty() && !new Calculation(now).fitsThisTransaction()) {
      later.putAll(now);
      now.clear();
    }
    if (!later.isEmpty() && !enqueue(later)) {
      now.putAll(later);
    }
    recalculate(now);
  }

  /** Recalculates every active rule that writes to these records, now. */
  public static void recalculate(Set<Id> parentIds) {
    Map<SObjectType, Set<Id>> idsByType = new Map<SObjectType, Set<Id>>();
    for (Id parentId : parentIds) {
      SObjectType parentType = parentId.getSObjectType();
      if (!idsByType.containsKey(parentType)) {
        idsByType.put(parentType, new Set<Id>());
      }
      idsByType.get(parentType).add(parentId);
    }
    Map<String, Set<Id>> parentsByRule = new Map<String, Set<Id>>();
    for (SObjectType parentType : idsByType.keySet()) {
      for (RollupPlan plan : RollupRules.forParent(parentType)) {
        parentsByRule.put(plan.rule.name, idsByType.get(parentType));
      }
    }
    recalculate(parentsByRule);
  }

  /** Recalculates the named rules for the parents given with each, now. An unknown rule is ignored. */
  public static void recalculate(Map<String, Set<Id>> parentsByRule) {
    new Calculation(parentsByRule).run();
  }

  /**
   * Recalculates every rule over every parent record: one batch per parent object, one after
   * another. Use it after adding a rule, or on a schedule to correct what no trigger saw (merged
   * records, data loaded with triggers off). Returns the first job, or null when there are no rules.
   */
  public static unif.IJob sweep() {
    unif.IJob first;
    for (String parentObject : RollupRules.parentObjects()) {
      unif.IJob next = unif.Async.queryable(new RollupJobs.Sweep(parentObject));
      first = first == null ? next : first.then(next);
    }
    return first?.run();
  }

  /**
   * Call before parent records are deleted. A rule that guards deletion refuses the delete while
   * the parent holds a result above zero (or, for dates and text, any result).
   */
  public static void guardDelete(unif.IDomain parents) {
    for (RollupPlan plan : RollupRules.forParent(parents.source().token())) {
      if (plan.rule.guardsDelete != true) {
        continue;
      }
      DescribeFieldResult counted = plan.parent.scheme().getFieldDescribe(plan.target);
      for (SObject parentRecord : parents.records()) {
        if (plan.holdsSomething(parentRecord)) {
          parentRecord.addError(
            'This ' + plan.parent.describe().getLabel() + ' cannot be deleted while its ' + counted.getLabel() + ' is ' + parentRecord.get(plan.target)
          );
        }
      }
    }
  }

  // The parents whose result a change to these children can alter. A child counts towards the
  // parent it points at now and the one it pointed at before, in each case only if it may be among
  // the records the rule counts.
  private static Set<Id> touched(RollupPlan plan, unif.IDomain children, Map<Id, SObject> previous) {
    Set<Id> parents = new Set<Id>();
    List<SObject> relevant = previous == null ? children.records() : children.getChangedRecords(previous, plan.watched);
    for (SObject child : relevant) {
      note(parents, plan, child);
      note(parents, plan, previous?.get(child.Id));
    }
    return parents;
  }

  private static void note(Set<Id> parents, RollupPlan plan, SObject child) {
    Id parentId = (Id) child?.get(plan.lookup);
    if (parentId != null && plan.mayCount(child)) {
      parents.add(parentId);
    }
  }

  // Starts one job for the parents not already waiting for one. False when the transaction may not
  // start another job, in which case the caller recalculates now.
  private static Boolean enqueue(Map<String, Set<Id>> parentsByRule) {
    // Inline jobs (a test's switch) have finished by the time later changes arrive, so nothing is waiting.
    Boolean inline = Test.isRunningTest() && unif.Async.synchronousInTests == true;
    Map<String, Set<Id>> fresh = new Map<String, Set<Id>>();
    for (String ruleName : parentsByRule.keySet()) {
      Set<Id> parents = parentsByRule.get(ruleName).clone();
      if (!inline && waiting.containsKey(ruleName)) {
        parents.removeAll(waiting.get(ruleName));
      }
      if (!parents.isEmpty()) {
        fresh.put(ruleName, parents);
      }
    }
    if (fresh.isEmpty()) {
      return true;
    }
    if (Limits.getQueueableJobs() >= Limits.getLimitQueueableJobs()) {
      return false;
    }
    for (String ruleName : fresh.keySet()) {
      if (!waiting.containsKey(ruleName)) {
        waiting.put(ruleName, new Set<Id>());
      }
      waiting.get(ruleName).addAll(fresh.get(ruleName));
    }
    unif.Async.queueable(new RollupJobs.Recalculate(fresh)).run();
    return true;
  }

  /** Rules that read the same children, and the parents to work them out for. */
  private without sharing class SharedQuery {
    public List<RollupPlan> plans = new List<RollupPlan>();
    public Set<Id> parents = new Set<Id>();
    private Map<String, String> aliasByFunction = new Map<String, String>();

    public void add(RollupPlan plan, Set<Id> parentIds) {
      plans.add(plan);
      parents.addAll(parentIds);
      if (!aliasByFunction.containsKey(plan.functionKey())) {
        aliasByFunction.put(plan.functionKey(), 'r' + aliasByFunction.size());
      }
    }

    public String aliasOf(RollupPlan plan) {
      return aliasByFunction.get(plan.functionKey());
    }

    // SELECT Lookup, <one column per function> FROM Child WHERE Lookup IN :parents AND <filter> GROUP BY Lookup
    public Map<Id, AggregateResult> totals() {
      RollupPlan lead = plans[0];
      String lookupName = lead.child.scheme().getFieldDescribe(lead.lookup).getName();
      Map<Id, AggregateResult> byParent = new Map<Id, AggregateResult>();
      for (Set<Id> portion : portions(parents)) {
        unif.IAggregateQuery tally = lead.child.aggregateQuery();
        tally.groupBys().add(RollupScheme.app.path(lead.lookup));
        Set<String> placed = new Set<String>();
        for (RollupPlan plan : plans) {
          if (placed.add(plan.functionKey())) {
            tally.aggregates().add(plan.function().setAlias(aliasOf(plan)));
          }
        }
        tally.filters().add(RollupScheme.app.iin(lead.lookup, portion));
        if (lead.filter != null) {
          tally.filters().add(lead.filter.clone(true));
        }
        for (AggregateResult row : tally.run()) {
          byParent.put((Id) row.get(lookupName), row);
        }
      }
      return byParent;
    }
  }

  private static List<Set<Id>> portions(Set<Id> everything) {
    List<Set<Id>> cut = new List<Set<Id>>{ new Set<Id>() };
    for (Id each : everything) {
      if (cut[cut.size() - 1].size() == parentsPerQuery) {
        cut.add(new Set<Id>());
      }
      cut[cut.size() - 1].add(each);
    }
    return cut;
  }

  /** One recalculation: rules grouped by the query they share. */
  private without sharing class Calculation {
    private Map<String, SharedQuery> queries = new Map<String, SharedQuery>();

    public Calculation(Map<String, Set<Id>> parentsByRule) {
      for (String ruleName : parentsByRule.keySet()) {
        RollupPlan plan = RollupRules.named(ruleName);
        Set<Id> parents = parentsByRule.get(ruleName);
        if (plan == null || parents == null || parents.isEmpty()) {
          continue;
        }
        if (!queries.containsKey(plan.queryKey())) {
          queries.put(plan.queryKey(), new SharedQuery());
        }
        queries.get(plan.queryKey()).add(plan, parents);
      }
    }

    public Boolean fitsThisTransaction() {
      Set<SObjectType> parentTypes = new Set<SObjectType>();
      for (SharedQuery shared : queries.values()) {
        parentTypes.add(shared.plans[0].parent.token());
      }
      Integer needed = queries.size() + parentTypes.size();
      return needed + spareQueries <= Limits.getLimitQueries() - Limits.getQueries();
    }

    public void run() {
      if (queries.isEmpty()) {
        return;
      }
      Map<Id, SObject> held = presentValues();
      Map<Id, SObject> changes = new Map<Id, SObject>();
      for (SharedQuery shared : queries.values()) {
        Map<Id, AggregateResult> totals = shared.totals();
        for (RollupPlan plan : shared.plans) {
          for (Id parentId : shared.parents) {
            // A parent deleted in this transaction was not found, and has nothing to update.
            SObject parentRecord = held.get(parentId);
            if (parentRecord == null) {
              continue;
            }
            Object fresh = plan.fit(totals.get(parentId)?.get(shared.aliasOf(plan)));
            if (!plan.same(parentRecord.get(plan.target), fresh)) {
              SObject change = changes.get(parentId) ?? plan.parent.token().newSObject(parentId);
              change.put(plan.target, fresh);
              changes.put(parentId, change);
            }
          }
        }
      }
      if (changes.isEmpty()) {
        return;
      }
      unif.IWork work = RollupScheme.app.work();
      for (SObject change : changes.values()) {
        work.track(change);
      }
      work.apply();
    }

    // The parents as they stand, with the fields the rules write: one query per parent object.
    // They are locked, and read before the children are totalled, so that two saves under one
    // parent take turns: the second waits here, then totals what the first has saved.
    private Map<Id, SObject> presentValues() {
      Map<SObjectType, unif.IModel> models = new Map<SObjectType, unif.IModel>();
      Map<SObjectType, Set<SObjectField>> fields = new Map<SObjectType, Set<SObjectField>>();
      Map<SObjectType, Set<Id>> ids = new Map<SObjectType, Set<Id>>();
      for (SharedQuery shared : queries.values()) {
        for (RollupPlan plan : shared.plans) {
          SObjectType parentType = plan.parent.token();
          if (!models.containsKey(parentType)) {
            models.put(parentType, plan.parent);
            fields.put(parentType, new Set<SObjectField>());
            ids.put(parentType, new Set<Id>());
          }
          fields.get(parentType).add(plan.target);
          ids.get(parentType).addAll(shared.parents);
        }
      }
      Map<Id, SObject> held = new Map<Id, SObject>();
      for (SObjectType parentType : models.keySet()) {
        unif.IQuery reading = models.get(parentType).query().forUpdate(true);
        reading.fields().add(fields.get(parentType));
        reading.addCondition(RollupScheme.app.condId(ids.get(parentType)));
        held.putAll(reading.run());
      }
      return held;
    }
  }
}
