/**
 * Copies records together with the records beneath them, as a Clone_Step__mdt plan describes.
 *
 * The copy is made as the person asking for it. It holds the records they can see and the fields
 * they can read and may fill in, and it belongs to them. An object they cannot read contributes
 * nothing; one they can read but may not create stops the copy, with a message, before anything
 * is saved.
 *
 * A copy is a duplicate by design, so duplicate rules that only warn are passed over. One that
 * blocks still blocks.
 *
 * What a copy costs, however many records are copied: one query for each step of the plan, and one
 * unit of work, which saves each object once, parents before the records that point at them.
 */
public with sharing class Cloner {
  public class CloneException extends Exception {
  }

  /** Copies one record; returns the Id of its copy. */
  public static Id copy(String planName, Id recordId) {
    return copy(planName, new Set<Id>{ recordId }).get(recordId);
  }

  /** Copies several records of the plan's object; returns the Id of each one's copy, by the original's Id. */
  public static Map<Id, Id> copy(String planName, Set<Id> recordIds) {
    ClonePlan plan = ClonePlans.named(planName);
    inj.IWork work = App.s.work().withSharing(true);
    work.options().DuplicateRuleHeader.allowSave = true;

    Map<Id, SObject> copies = copyLevel(plan.root, recordIds, null, work);
    if (copies.size() < recordIds.size()) {
      String label = plan.root.model.describe().getLabel();
      throw new CloneException(
        recordIds.size() == 1 ? 'That ' + label + ' does not exist, or you cannot see it' : 'Some of those records are not ' + label + ' records you can see'
      );
    }
    work.apply();

    Map<Id, Id> copyIds = new Map<Id, Id>();
    for (Id originalId : copies.keySet()) {
      copyIds.put(originalId, copies.get(originalId).Id);
    }
    return copyIds;
  }

  // Reads one step's records (the originals named, or the children of the originals above), tracks
  // a copy of each under the copy of its parent, and goes on to the steps beneath. Returns the
  // copies by their original's Id.
  private static Map<Id, SObject> copyLevel(ClonePlan.Node node, Set<Id> ids, Map<Id, SObject> copiesAbove, inj.IWork work) {
    Map<Id, SObject> copies = new Map<Id, SObject>();
    DescribeSObjectResult shape = node.model.describe();
    Boolean readable = shape.isAccessible() && (node.lookup == null || node.model.scheme().getFieldDescribe(node.lookup).isAccessible());
    if (!readable) {
      if (node.above == null) {
        throw new CloneException('You cannot read ' + shape.getLabelPlural());
      }
      return copies;
    }

    inj.IQuery reading = node.model.query().withSharing(true);
    reading.fields().add(node.copiedFields());
    if (node.lookup == null) {
      reading.addCondition(App.s.condId(ids));
    } else {
      reading.fields().add(new Set<SObjectField>{ node.lookup });
      reading.addCondition(App.s.iin(node.lookup, ids));
    }
    if (node.filter != null) {
      reading.addCondition(node.filter.clone(true));
    }
    List<SObject> originals = reading.run();
    if (originals.isEmpty()) {
      return copies;
    }
    if (!shape.isCreateable()) {
      throw new CloneException('You cannot create ' + shape.getLabelPlural());
    }

    for (SObject original : originals) {
      SObject copy = node.copyOf(original);
      copies.put(original.Id, copy);
      if (node.lookup == null) {
        work.track(copy);
      } else {
        work.track(copy, node.lookup, copiesAbove.get((Id) original.get(node.lookup)));
      }
    }
    for (ClonePlan.Node beneath : node.children) {
      copyLevel(beneath, copies.keySet(), copies, work);
    }
    return copies;
  }
}
