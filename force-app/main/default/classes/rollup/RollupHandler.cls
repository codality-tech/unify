/**
 * A ready-made trigger handler for an object that takes part in rollups and has no domain class of
 * its own. Register it against the object in App's trigger registry, and give the object a trigger
 * whose body is App.s.tf().execute(). It serves both sides: a child's changes are rolled up, and a
 * parent's deletion is guarded.
 *
 * An object that already has a domain class makes the same four calls from its own hooks.
 */
global class RollupHandler extends inj.BaseDomain {
  global RollupHandler() {
    super();
  }

  public override void onAfterUpsert(Map<Id, SObject> oldMap) {
    Rollups.changed(this, oldMap);
  }

  public override void onAfterDelete() {
    Rollups.changed(this, null);
  }

  public override void onAfterUndelete() {
    Rollups.changed(this, null);
  }

  public override void onBeforeDelete() {
    Rollups.guardDelete(this);
  }
}
