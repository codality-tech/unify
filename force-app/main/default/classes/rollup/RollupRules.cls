/**
 * The active rules. They are read from Rollup_Rule__mdt once per transaction, which costs no query,
 * and each is compiled the first time something needs it.
 *
 * A rule that cannot run is not skipped: the save that would have used it fails with a message that
 * names the rule and what is wrong with it. A total that is silently out of date is worse than an
 * error someone has to fix.
 */
public class RollupRules {
  @TestVisible
  private static List<RollupRule> injected;
  private static Map<String, RollupRule> rulesByName;
  private static Map<String, RollupPlan> plansByName = new Map<String, RollupPlan>();

  /** Tests give the rules themselves, so they do not depend on the records the org happens to hold. */
  @TestVisible
  private static void use(List<RollupRule> rules) {
    injected = rules;
    rulesByName = null;
    plansByName = new Map<String, RollupPlan>();
  }

  // Active rules by name, in name order.
  private static Map<String, RollupRule> rules() {
    if (rulesByName == null) {
      List<RollupRule> known = injected;
      if (known == null) {
        known = new List<RollupRule>();
        for (Rollup_Rule__mdt stored : Rollup_Rule__mdt.getAll().values()) {
          known.add(RollupRule.fromMetadata(stored));
        }
      }
      Map<String, RollupRule> switchedOn = new Map<String, RollupRule>();
      for (RollupRule rule : known) {
        if (rule.active == true) {
          switchedOn.put(rule.name, rule);
        }
      }
      List<String> names = new List<String>(switchedOn.keySet());
      names.sort();
      rulesByName = new Map<String, RollupRule>();
      for (String name : names) {
        rulesByName.put(name, switchedOn.get(name));
      }
    }
    return rulesByName;
  }

  private static RollupPlan planOf(RollupRule rule) {
    RollupPlan plan = plansByName.get(rule.name);
    if (plan == null) {
      plan = RollupPlan.compile(rule);
      plansByName.put(rule.name, plan);
    }
    return plan;
  }

  private static RollupPlan sound(RollupPlan plan) {
    if (!plan.isSound()) {
      throw new Rollups.RollupException('Rollup rule ' + plan.rule.name + ' cannot run: ' + String.join(plan.problems, '; '));
    }
    return plan;
  }

  /** The plan of an active rule; null when there is no such rule. */
  public static RollupPlan named(String name) {
    RollupRule rule = rules().get(name);
    return rule == null ? null : sound(planOf(rule));
  }

  /** The rules that roll this object's records up. Only these are compiled. */
  public static List<RollupPlan> forChild(SObjectType childType) {
    String childName = String.valueOf(childType);
    List<RollupPlan> plans = new List<RollupPlan>();
    for (RollupRule rule : rules().values()) {
      if (rule.childObject == childName) {
        plans.add(sound(planOf(rule)));
      }
    }
    return plans;
  }

  /** The rules that write to this object's records. */
  public static List<RollupPlan> forParent(SObjectType parentType) {
    List<RollupPlan> plans = new List<RollupPlan>();
    for (RollupRule rule : rules().values()) {
      RollupPlan plan = planOf(rule);
      if (plan.parent?.token() == parentType) {
        plans.add(sound(plan));
      }
    }
    return plans;
  }

  /** The API names of the objects that active rules write to, in name order. */
  public static List<String> parentObjects() {
    Set<String> found = new Set<String>();
    for (RollupRule rule : rules().values()) {
      RollupPlan plan = planOf(rule);
      if (plan.parent != null) {
        found.add(plan.parent.name());
      }
    }
    List<String> names = new List<String>(found);
    names.sort();
    return names;
  }

  /** What is wrong with each active rule, by rule name; a rule with nothing wrong has no entry. */
  public static Map<String, List<String>> problems() {
    Map<String, List<String>> found = new Map<String, List<String>>();
    for (RollupRule rule : rules().values()) {
      RollupPlan plan = planOf(rule);
      if (!plan.isSound()) {
        found.put(rule.name, plan.problems);
      }
    }
    return found;
  }
}
