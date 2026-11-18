/**
 * The rollup's jobs, as handlers for the framework's async engine. They hold names and Ids only,
 * so they travel between transactions as they are.
 */
public class RollupJobs {
  /** Recalculates the named rules for the parents given with each, in a transaction of its own. */
  public class Recalculate implements inj.IQueueableHandler {
    private Map<String, Set<Id>> parentsByRule;

    public Recalculate(Map<String, Set<Id>> parentsByRule) {
      this.parentsByRule = parentsByRule;
    }

    public void queueableExecute() {
      Rollups.recalculate(parentsByRule);
    }
  }

  /**
   * Recalculates every rule that writes to one object, over all of its records. To run it with
   * fewer parents at a time (parents with very many children), start it yourself:
   * inj.Async.queryable(new RollupJobs.Sweep('Account')).setBatchSize(50).run();
   */
  public class Sweep implements inj.IBatchQueryableHandler {
    private String parentObject;

    public Sweep(String parentObject) {
      this.parentObject = parentObject;
    }

    public inj.IQuery batchStart() {
      return RollupScheme.app.model(parentObject).query();
    }

    public void batchExecute(List<SObject> scope) {
      Rollups.recalculate(new Map<Id, SObject>(scope).keySet());
    }

    public void batchFinish() {
    }

    public Integer batchDefaultSize() {
      return 200;
    }
  }

  /**
   * Sweeps every night at two. To schedule it: inj.Async.schedulable(new RollupJobs.Nightly()).run();
   */
  public class Nightly implements inj.ISchedulableHandler {
    public void schedulableExecute() {
      Rollups.sweep();
    }

    public String name() {
      return 'Rollup sweep';
    }

    public String cronExpression() {
      return '0 0 2 * * ?';
    }
  }
}
