/**
 * A plan with its names resolved: a tree of steps, each knowing its object, the lookup that ties
 * it to the step above, its parsed filter and the values it sets. A plan that could not be resolved
 * lists what is wrong in `problems`, each saying which step it is about, and must not be run.
 */
public class ClonePlan {
  public String name { get; private set; }
  public Node root { get; private set; }
  public List<String> problems { get; private set; }

  private ClonePlan(String name) {
    this.name = name;
    problems = new List<String>();
  }

  /** The plan that starts at the named step, from the steps given. Inactive steps should already be gone. */
  public static ClonePlan compile(String planName, List<CloneStep> steps) {
    ClonePlan plan = new ClonePlan(planName);
    CloneStep first;
    for (CloneStep step : steps) {
      if (step.name == planName) {
        first = step;
      }
    }
    if (first == null) {
      plan.problems.add('There is no step named ' + planName);
    } else if (!first.startsAPlan()) {
      plan.problems.add(planName + ' does not start a plan: it sits under ' + first.parentStep);
    } else {
      plan.root = plan.grow(first, null, steps);
    }
    return plan;
  }

  public Boolean isSound() {
    return problems.isEmpty();
  }

  /** Every step of the plan, the first one first. */
  public List<Node> nodes() {
    List<Node> every = new List<Node>();
    if (root != null) {
      root.gather(every);
    }
    return every;
  }

  private Node grow(CloneStep step, Node above, List<CloneStep> steps) {
    Node node = new Node(step, above);
    for (String problem : node.resolve()) {
      problems.add('Step ' + step.name + ': ' + problem);
    }
    if (node.model != null) {
      for (CloneStep other : steps) {
        if (other.parentStep == step.name) {
          node.children.add(grow(other, node, steps));
        }
      }
    }
    return node;
  }

  /** One step, resolved. */
  public class Node {
    public CloneStep step { get; private set; }
    public Node above { get; private set; }
    public List<Node> children { get; private set; }
    public inj.IModel model { get; private set; }
    public SObjectField lookup { get; private set; }
    public inj.ICondition filter { get; private set; }
    public Set<SObjectField> leftOut { get; private set; }
    public Map<SObjectField, Object> values { get; private set; }
    private Set<SObjectField> copied;

    private Node(CloneStep step, Node above) {
      this.step = step;
      this.above = above;
      children = new List<Node>();
      leftOut = new Set<SObjectField>();
      values = new Map<SObjectField, Object>();
    }

    private void gather(List<Node> every) {
      every.add(this);
      for (Node child : children) {
        child.gather(every);
      }
    }

    private List<String> resolve() {
      List<String> wrong = new List<String>();
      model = Naming.model(Unify.s, step.objectName);
      if (model == null) {
        wrong.add('unknown object ' + step.objectName);
        return wrong;
      }
      if (above != null) {
        resolveLookup(wrong);
      }
      for (String fieldName : (step.leaveOut ?? '').split(',')) {
        if (String.isNotBlank(fieldName)) {
          SObjectField skipped = fieldNamed(fieldName.trim(), wrong);
          if (skipped != null) {
            leftOut.add(skipped);
          }
        }
      }
      resolveFilter(wrong);
      resolveValues(wrong);
      return wrong;
    }

    private void resolveLookup(List<String> wrong) {
      if (String.isBlank(step.lookupField)) {
        wrong.add('it has no lookup field to tie it to ' + above.step.name);
        return;
      }
      lookup = fieldNamed(step.lookupField, wrong);
      if (lookup != null && above.model != null && !shapeOf(lookup).getReferenceTo().contains(above.model.token())) {
        wrong.add(model.name() + '.' + shapeOf(lookup).getName() + ' does not point at ' + above.model.name());
        lookup = null;
      }
    }

    private void resolveFilter(List<String> wrong) {
      if (String.isBlank(step.filter)) {
        return;
      }
      if (above == null) {
        wrong.add('the step that starts a plan takes no filter: the records to copy are named when the plan is run');
        return;
      }
      try {
        filter = model.parseCondition(Naming.inText(model, step.filter));
        model.compileCondition(filter);
      } catch (Exception unreadable) {
        filter = null;
        wrong.add('filter: ' + unreadable.getMessage());
      }
    }

    // The values are written as a condition the copy must meet, so the framework's parser reads
    // them, checks each against its field, and hands back typed values. Only "field = value"
    // joined by AND can be turned into something to write.
    private void resolveValues(List<String> wrong) {
      if (String.isBlank(step.values)) {
        return;
      }
      try {
        inj.IConditionCompilation compiled = model.compileCondition(model.parseCondition(Naming.inText(model, step.values)));
        // A negated group shows in the markup; a negated comparison shows only in its own SOQL.
        Boolean plain = !compiled.getMarkup().contains(' OR ') && !compiled.getMarkup().contains('NOT ');
        for (inj.IFieldCondition setting : compiled.getFieldConditions()) {
          Boolean assigns = setting.operator() == inj.Enums.Comparator.EQ && !setting.toSoql().startsWith('(NOT ');
          plain = plain && assigns && setting.path().size() == 1;
        }
        if (!plain) {
          wrong.add('values must be fields of ' + model.name() + ' set with = and joined by AND');
          return;
        }
        for (inj.IFieldCondition setting : compiled.getFieldConditions()) {
          SObjectField field = setting.path().terminus();
          // A date literal is a range of days, read when a condition is tested, not one value to write.
          if (setting.value() instanceof inj.IDateLiteral) {
            values.clear();
            wrong.add('values: ' + field + ' takes a date such as 2026-12-31, not the date literal ' + ((inj.IDateLiteral) setting.value()).toSoql());
            return;
          }
          Object fitted = fit(field, setting.value());
          model.token().newSObject().put(field, fitted);
          values.put(field, fitted);
        }
      } catch (Exception unreadable) {
        values.clear();
        wrong.add('values: ' + unreadable.getMessage());
      }
    }

    // A whole-number field takes an Integer, whatever kind of number was written.
    private Object fit(SObjectField field, Object value) {
      if (value instanceof Decimal && shapeOf(field).getSoapType() == Schema.SoapType.INTEGER) {
        return ((Decimal) value).intValue();
      }
      return value;
    }

    private SObjectField fieldNamed(String fieldName, List<String> wrong) {
      SObjectField found = Naming.field(model, fieldName);
      if (found == null) {
        wrong.add(model.name() + ' has no field ' + fieldName);
      }
      return found;
    }

    private DescribeFieldResult shapeOf(SObjectField field) {
      return model.scheme().getFieldDescribe(field);
    }

    /**
     * The fields a copy takes from its original, for the person running the copy: every field they
     * can read and may fill in on a new record, less those the step leaves out, those that must be
     * unique, and the owner, so that the copy belongs to whoever made it.
     */
    public Set<SObjectField> copiedFields() {
      if (copied == null) {
        copied = new Set<SObjectField>();
        for (SObjectField field : model.fieldMap().values()) {
          DescribeFieldResult shape = shapeOf(field);
          Boolean wanted = shape.isAccessible() && shape.isCreateable() && !shape.isUnique() && shape.getName() != 'OwnerId';
          if (wanted && !leftOut.contains(field)) {
            copied.add(field);
          }
        }
      }
      return copied;
    }

    /** A new record like the original, not yet saved and not yet tied to a parent. */
    public SObject copyOf(SObject original) {
      SObject copy = original.clone(false, true, false, false);
      if (lookup != null) {
        copy.put(lookup, null);
      }
      for (SObjectField field : values.keySet()) {
        copy.put(field, values.get(field));
      }
      SObjectField title = model.nameField();
      String named = title != null && copiedFields().contains(title) ? (String) copy.get(title) : null;
      if (named != null && String.isNotBlank(step.nameSuffix)) {
        // A space is put between the two: a metadata record cannot hold one at the start of its text.
        String tail = ' ' + step.nameSuffix.trim();
        Integer room = shapeOf(title).getLength() - tail.length();
        copy.put(title, named.left(Math.max(room, 0)) + tail);
      }
      return copy;
    }
  }
}
