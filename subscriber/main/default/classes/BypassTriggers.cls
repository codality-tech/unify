/**
 * Switches every trigger off for a user who holds the custom permission Bypass_Triggers: an
 * integration user loading data, say. An administrator assigns the permission set of the same
 * name, and nothing is deployed.
 *
 * App registers it with App.s.tf().disableWhen(new BypassTriggers()). The framework asks the rule
 * each time a trigger is about to run. The rule is a class of this org, not of the package, so
 * the permission it reads is this org's own.
 */
public class BypassTriggers implements inj.ITriggeredBypass {
  public Boolean bypasses(SObjectType token, TriggerOperation operation) {
    return FeatureManagement.checkPermission('Bypass_Triggers');
  }
}
