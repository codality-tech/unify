/**
 * The copy as an action a flow can call, so an admin can put "Copy with related records" on a
 * button without code. Requests that name the same plan are copied together.
 */
public with sharing class CloneAction {
  public class Request {
    @InvocableVariable(label='Plan' description='The name of the Clone Step that starts the plan' required=true)
    public String plan;

    @InvocableVariable(label='Record Id' description='The record to copy' required=true)
    public Id recordId;
  }

  public class Result {
    @InvocableVariable(label='Copy Id' description='The Id of the copy')
    public Id copyId;
  }

  @InvocableMethod(
    label='Copy a record with its related records'
    description='Copies a record and the records beneath it, as a Clone Step plan describes. Returns the Id of the copy.'
    category='Clone'
  )
  public static List<Result> copy(List<Request> requests) {
    Map<String, Set<Id>> idsByPlan = new Map<String, Set<Id>>();
    for (Request asked : requests) {
      if (!idsByPlan.containsKey(asked.plan)) {
        idsByPlan.put(asked.plan, new Set<Id>());
      }
      idsByPlan.get(asked.plan).add(asked.recordId);
    }
    Map<String, Map<Id, Id>> copiesByPlan = new Map<String, Map<Id, Id>>();
    for (String planName : idsByPlan.keySet()) {
      copiesByPlan.put(planName, Cloner.copy(planName, idsByPlan.get(planName)));
    }
    List<Result> results = new List<Result>();
    for (Request asked : requests) {
      Result made = new Result();
      made.copyId = copiesByPlan.get(asked.plan).get(asked.recordId);
      results.add(made);
    }
    return results;
  }
}
