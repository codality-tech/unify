/**
 * One rollup: an aggregate of child records, written to a field on the record their lookup points
 * at. A rule is plain data, held as API names. It comes from a Rollup_Rule__mdt record or is built
 * in code; RollupPlan resolves the names and says what is wrong with them.
 *
 *   new RollupRule('Open_Amount')
 *     .children(Opportunity.AccountId)
 *     .sum(Opportunity.Amount)
 *     .matching('IsClosed = FALSE')
 *     .writeTo(Account.AnnualRevenue);
 */
public class RollupRule {
  /** IMMEDIATE recalculates as part of the save; QUEUED does it moments later, in a job of its own. */
  public enum Timing {
    IMMEDIATE,
    QUEUED
  }

  public String name;
  public String childObject;
  public String lookupField;
  public String parentField;
  public inj.Enums.Aggregate operation;
  public String sourceField;
  public String filter;
  public Timing runs = Timing.IMMEDIATE;
  public Boolean active = true;
  public Boolean guardsDelete = false;

  public RollupRule(String name) {
    this.name = name;
  }

  /** The rule a metadata record describes. An operation the record does not name stays null. */
  public static RollupRule fromMetadata(Rollup_Rule__mdt stored) {
    RollupRule rule = new RollupRule(stored.DeveloperName);
    rule.childObject = stored.Child_Object__c;
    rule.lookupField = stored.Lookup_Field__c;
    rule.parentField = stored.Parent_Field__c;
    rule.sourceField = stored.Source_Field__c;
    rule.filter = stored.Filter__c;
    rule.active = stored.Active__c == true;
    rule.guardsDelete = stored.Guard_Parent_Delete__c == true;
    rule.runs = stored.Timing__c == Timing.QUEUED.name() ? Timing.QUEUED : Timing.IMMEDIATE;
    for (inj.Enums.Aggregate known : inj.Enums.Aggregate.values()) {
      if (known.name() == stored.Operation__c) {
        rule.operation = known;
      }
    }
    return rule;
  }

  // Building a rule in code

  /** The children are the records whose lookup this is; the parent is what it points at. */
  public RollupRule children(SObjectField lookup) {
    DescribeFieldResult shape = lookup.getDescribe();
    childObject = String.valueOf(shape.getSObjectType());
    lookupField = shape.getName();
    return this;
  }

  /** How many children there are. */
  public RollupRule count() {
    return take(inj.Enums.Aggregate.COUNT, null);
  }

  /** How many children have a value in the field. */
  public RollupRule count(SObjectField counted) {
    return take(inj.Enums.Aggregate.COUNT, counted);
  }

  public RollupRule countDistinct(SObjectField counted) {
    return take(inj.Enums.Aggregate.COUNT_DISTINCT, counted);
  }

  public RollupRule sum(SObjectField added) {
    return take(inj.Enums.Aggregate.SUM, added);
  }

  public RollupRule avg(SObjectField averaged) {
    return take(inj.Enums.Aggregate.AVG, averaged);
  }

  public RollupRule min(SObjectField compared) {
    return take(inj.Enums.Aggregate.MIN, compared);
  }

  public RollupRule max(SObjectField compared) {
    return take(inj.Enums.Aggregate.MAX, compared);
  }

  /** The field on the parent that receives the result. */
  public RollupRule writeTo(SObjectField onParent) {
    parentField = onParent.getDescribe().getName();
    return this;
  }

  /** Which children count, written like a SOQL WHERE clause. */
  public RollupRule matching(String whereText) {
    filter = whereText;
    return this;
  }

  public RollupRule queued() {
    runs = Timing.QUEUED;
    return this;
  }

  /** Stops a parent from being deleted while the result is above zero (or, for dates and text, not blank). */
  public RollupRule guardingDelete() {
    guardsDelete = true;
    return this;
  }

  private RollupRule take(inj.Enums.Aggregate wanted, SObjectField fromField) {
    operation = wanted;
    sourceField = fromField?.getDescribe().getName();
    return this;
  }
}
