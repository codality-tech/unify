/**
 * The plans this org holds. Steps are read from Clone_Step__mdt once per transaction, which costs
 * no query, and a plan is compiled the first time it is asked for.
 */
public class ClonePlans {
  @TestVisible
  private static List<CloneStep> injected;
  private static List<CloneStep> activeSteps;
  private static Map<String, ClonePlan> plansByName = new Map<String, ClonePlan>();

  /** Tests give the steps themselves, so they do not depend on the records the org happens to hold. */
  @TestVisible
  private static void use(List<CloneStep> steps) {
    injected = steps;
    activeSteps = null;
    plansByName = new Map<String, ClonePlan>();
  }

  private static List<CloneStep> steps() {
    if (activeSteps == null) {
      List<CloneStep> known = injected;
      if (known == null) {
        known = new List<CloneStep>();
        for (Clone_Step__mdt stored : Clone_Step__mdt.getAll().values()) {
          known.add(CloneStep.fromMetadata(stored));
        }
      }
      activeSteps = new List<CloneStep>();
      for (CloneStep step : known) {
        if (step.active == true) {
          activeSteps.add(step);
        }
      }
    }
    return activeSteps;
  }

  private static ClonePlan planNamed(String planName) {
    String key = planName?.toLowerCase();
    if (!plansByName.containsKey(key)) {
      plansByName.put(key, ClonePlan.compile(planName, steps()));
    }
    return plansByName.get(key);
  }

  /** The plan that starts at the named step. Refuses a name that starts no plan, and a plan that cannot run. */
  public static ClonePlan named(String planName) {
    ClonePlan plan = planNamed(planName);
    if (plan.root == null) {
      throw new Cloner.CloneException('There is no clone plan named ' + planName);
    }
    if (!plan.isSound()) {
      throw new Cloner.CloneException('Clone plan ' + plan.name + ' cannot run: ' + String.join(plan.problems, '; '));
    }
    return plan;
  }

  /** The names of the plans: the active steps that have no parent, in name order. */
  public static List<String> names() {
    List<String> starts = new List<String>();
    for (CloneStep step : steps()) {
      if (step.startsAPlan()) {
        starts.add(step.name);
      }
    }
    starts.sort();
    return starts;
  }

  /**
   * What is wrong, by plan name; a plan with nothing wrong has no entry. A step that belongs to no
   * plan (its parent is missing or inactive, or its parents form a loop) is listed under its own name.
   */
  public static Map<String, List<String>> problems() {
    Map<String, List<String>> found = new Map<String, List<String>>();
    Set<String> placed = new Set<String>();
    for (String planName : names()) {
      ClonePlan plan = planNamed(planName);
      if (!plan.isSound()) {
        found.put(planName, plan.problems);
      }
      for (ClonePlan.Node node : plan.nodes()) {
        placed.add(node.step.name.toLowerCase());
      }
    }
    for (CloneStep step : steps()) {
      // A step under one that could not be resolved is not in the tree either, and is already accounted for.
      if (!placed.contains(step.name.toLowerCase()) && !sitsUnderAPlacedStep(step, placed)) {
        found.put(step.name, new List<String>{ 'It belongs to no plan: no active step named ' + step.parentStep + ' leads back to the start of one' });
      }
    }
    return found;
  }

  private static Boolean sitsUnderAPlacedStep(CloneStep step, Set<String> placed) {
    return !step.startsAPlan() && placed.contains(step.parentStep.toLowerCase());
  }
}
