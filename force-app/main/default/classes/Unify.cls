/**
 * The application the Unify solutions run on: the package's own entry point to the Injectify
 * framework. What belongs to the package is registered here (the query and domain classes for stored
 * blueprints, and the ready-made rollup handler for the sample objects), so nothing in the package
 * depends on a class of the org it is installed in.
 *
 * An org wires its own objects in its own entry point; RollupHandler says how.
 */
public class Unify {
  public static inj.IApplication s {
    get {
      if (s == null) {
        s = inj.Application.make(
          null, // the framework's default scheme
          new Map<Type, Type>(), // no services
          new Map<Type, Type>{ Reform_Blueprint__c.class => ReformBlueprintQuery.class }, // queries
          new Map<Type, Type>{ Reform_Blueprint__c.class => ReformBlueprints.class }, // domains
          new Map<Type, Type>{
            // triggers
            Reform_Blueprint__c.class => ReformBlueprints.class,
            Rollup_Sample_Child__c.class => RollupHandler.class,
            Rollup_Sample_Parent__c.class => RollupHandler.class
          }
        );
      }
      return s;
    }
    private set;
  }
}
