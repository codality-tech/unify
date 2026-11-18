/**
 * A rule with its names resolved: the objects, the fields, the parsed filter, and everything that
 * can be decided once instead of on every save. A plan that could not be resolved lists what is
 * wrong in `problems`, in words an admin can act on, and must not be run.
 */
public class RollupPlan {
  private enum Shape {
    NUMERIC,
    DAY,
    MOMENT,
    WORDS,
    OTHER
  }

  public RollupRule rule { get; private set; }
  public List<String> problems { get; private set; }

  public inj.IModel child { get; private set; }
  public inj.IModel parent { get; private set; }
  public SObjectField lookup { get; private set; }
  public SObjectField target { get; private set; }
  public SObjectField source { get; private set; }
  public inj.ICondition filter { get; private set; }

  /** The child fields whose change can alter the result: the lookup, the source, and those the filter reads. */
  public Set<SObjectField> watched { get; private set; }

  // True when the filter reads only the child's own fields, so a record in a trigger can be tested
  // against it. A filter that reads through a lookup cannot be: the related record is not loaded.
  private Boolean filterIsLocal = true;
  private DescribeFieldResult targetShape;
  private Shape targetKind;

  private RollupPlan(RollupRule rule) {
    this.rule = rule;
    problems = new List<String>();
    watched = new Set<SObjectField>();
  }

  public static RollupPlan compile(RollupRule rule) {
    RollupPlan plan = new RollupPlan(rule);
    plan.resolve();
    return plan;
  }

  public Boolean isSound() {
    return problems.isEmpty();
  }

  // Resolving

  private void resolve() {
    child = Naming.model(RollupScheme.app, rule.childObject);
    if (child == null) {
      problems.add('Unknown child object: ' + rule.childObject);
      return;
    }
    lookup = fieldNamed(child, rule.lookupField, 'lookup field');
    if (lookup == null) {
      return;
    }
    DescribeFieldResult lookupShape = shapeOf(child, lookup);
    List<SObjectType> pointsAt = lookupShape.getReferenceTo();
    if (pointsAt.isEmpty()) {
      problems.add(child.name() + '.' + lookupShape.getName() + ' is not a lookup');
      return;
    }
    if (pointsAt.size() > 1) {
      problems.add(child.name() + '.' + lookupShape.getName() + ' can point at more than one object, which a rollup cannot follow');
      return;
    }
    watched.add(lookup);
    parent = RollupScheme.app.model(pointsAt[0]);
    target = fieldNamed(parent, rule.parentField, 'parent field');
    if (target != null) {
      targetShape = shapeOf(parent, target);
      targetKind = kindOf(targetShape);
      if (targetShape.isCalculated() || targetShape.isAutoNumber()) {
        problems.add(written() + ' is worked out by Salesforce and cannot be written');
      }
    }
    resolveSource();
    resolveFilter();
  }

  private void resolveSource() {
    if (rule.operation == null) {
      problems.add('The rule has no operation');
      return;
    }
    Boolean counts = rule.operation == inj.Enums.Aggregate.COUNT || rule.operation == inj.Enums.Aggregate.COUNT_DISTINCT;
    if (String.isBlank(rule.sourceField)) {
      if (rule.operation != inj.Enums.Aggregate.COUNT) {
        problems.add(rule.operation + ' needs a source field');
      }
    } else {
      source = fieldNamed(child, rule.sourceField, 'source field');
    }
    if (target != null && counts && targetKind != Shape.NUMERIC) {
      problems.add(written() + ' must be a number field to hold a count');
    }
    if (source == null) {
      return;
    }
    watched.add(source);
    DescribeFieldResult sourceShape = shapeOf(child, source);
    String read = child.name() + '.' + sourceShape.getName();
    Shape sourceKind = kindOf(sourceShape);
    if (!sourceShape.isAggregatable()) {
      problems.add(read + ' cannot be aggregated');
    } else if (rule.operation == inj.Enums.Aggregate.SUM || rule.operation == inj.Enums.Aggregate.AVG) {
      if (sourceKind != Shape.NUMERIC) {
        problems.add(read + ' is not a number, so it cannot be summed or averaged');
      } else if (target != null && targetKind != Shape.NUMERIC) {
        problems.add(written() + ' must be a number field to hold a sum or an average');
      }
    } else if (!counts) {
      if (sourceKind == Shape.OTHER) {
        problems.add(read + ' has no smallest or largest value');
      } else if (target != null && targetKind != sourceKind) {
        problems.add(written() + ' must hold the same kind of value as ' + read);
      }
    }
  }

  private void resolveFilter() {
    if (String.isBlank(rule.filter)) {
      return;
    }
    try {
      filter = child.parseCondition(Naming.inText(child, rule.filter));
      for (inj.IPath read : child.compileCondition(filter).getPaths()) {
        watched.add(read.fieldSequence()[0]);
        filterIsLocal = filterIsLocal && read.size() == 1;
      }
    } catch (Exception unreadable) {
      filter = null;
      problems.add('Filter: ' + unreadable.getMessage());
    }
  }

  private SObjectField fieldNamed(inj.IModel owner, String fieldName, String role) {
    if (String.isBlank(fieldName)) {
      problems.add('The rule has no ' + role);
      return null;
    }
    SObjectField found = Naming.field(owner, fieldName);
    if (found == null) {
      problems.add(owner.name() + ' has no field ' + fieldName);
    }
    return found;
  }

  private static DescribeFieldResult shapeOf(inj.IModel owner, SObjectField field) {
    return owner.scheme().getFieldDescribe(field);
  }

  private static Shape kindOf(DescribeFieldResult described) {
    Schema.SoapType held = described.getSoapType();
    if (held == Schema.SoapType.INTEGER || held == Schema.SoapType.DOUBLE) {
      return Shape.NUMERIC;
    }
    if (held == Schema.SoapType.DATE) {
      return Shape.DAY;
    }
    if (held == Schema.SoapType.DATETIME) {
      return Shape.MOMENT;
    }
    return held == Schema.SoapType.STRING ? Shape.WORDS : Shape.OTHER;
  }

  private String written() {
    return parent.name() + '.' + targetShape.getName();
  }

  // Running

  /**
   * Rules with the same key read the same children, so one query serves them all. Filters are
   * compared as written, apart from the space around them.
   */
  public String queryKey() {
    return (child.name() + '.' + rule.lookupField).toLowerCase() + ' ' + (rule.filter ?? '').trim();
  }

  /** Rules with the same key in one query share a column. */
  public String functionKey() {
    return rule.operation + ' ' + (rule.sourceField ?? '').toLowerCase();
  }

  /** A new function each time: its alias is set by whoever puts it in a query. */
  public inj.IAggregateFunction function() {
    return RollupScheme.app.aggregate(rule.operation, source);
  }

  /**
   * Whether a child record may be among those the rule counts. When the filter can be tested on the
   * record it is; when it cannot, the answer is yes, and the query decides.
   */
  public Boolean mayCount(SObject candidate) {
    return filter == null || !filterIsLocal || filter.evaluate(candidate) == true;
  }

  /**
   * An aggregate's result as the parent field holds it: rounded to the field's decimal places, and
   * a whole number where the field is one. With no children a count or a sum is 0; an average, a
   * minimum or a maximum is blank.
   */
  public Object fit(Object result) {
    if (result == null) {
      Boolean startsAtZero = rule.operation != inj.Enums.Aggregate.AVG &&
        rule.operation != inj.Enums.Aggregate.MIN &&
        rule.operation != inj.Enums.Aggregate.MAX;
      return startsAtZero ? fit(0) : null;
    }
    if (targetKind != Shape.NUMERIC) {
      return result;
    }
    Decimal amount = asDecimal(result);
    if (targetShape.getSoapType() == Schema.SoapType.INTEGER) {
      return amount.round(System.RoundingMode.HALF_UP).intValue();
    }
    return amount.setScale(targetShape.getScale(), System.RoundingMode.HALF_UP);
  }

  /** Whether the parent already holds the value, so writing it would change nothing. */
  public Boolean same(Object held, Object fresh) {
    if (held == null || fresh == null) {
      return held == null && fresh == null;
    }
    return targetKind == Shape.NUMERIC ? asDecimal(held) == asDecimal(fresh) : held == fresh;
  }

  /** Whether the parent holds a result that should keep it from being deleted. */
  public Boolean holdsSomething(SObject parentRecord) {
    Object held = parentRecord.get(target);
    return held != null && (targetKind != Shape.NUMERIC || asDecimal(held) != 0);
  }

  private static Decimal asDecimal(Object value) {
    if (value instanceof Integer) {
      return (Integer) value;
    }
    if (value instanceof Long) {
      return (Long) value;
    }
    // A double arrives here too, and the cast takes it (RollupPlanTest).
    return (Decimal) value;
  }
}
