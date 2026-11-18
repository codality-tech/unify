/**
 * Turns a compiled blueprint into a form or a table.
 *
 * A form is computed from the values a component holds: the stored record (when editing) with those
 * values laid over it, fixed values and defaults applied, the parents its rules and merge fields
 * read loaded, and then each element's value, visibility and text worked out in memory. Nothing is
 * written until save is asked for, so a component can ask again after every change.
 *
 * Reads run as the user (sharing and field security), and so do writes: the unit of work is put in
 * user mode, so the platform refuses whatever the user may not do. Before that this class checks
 * the user's object and field permissions and their access to the record itself, so a refusal
 * comes with a message a person can act on, and it writes only fields the blueprint names and the
 * user may write.
 */
public with sharing class ReformEngine {
  public class ReformException extends Exception {
  }

  private static final Integer DEFAULT_PAGE = 50;
  private static final Integer LARGEST_PAGE = 200;
  // SOQL's OFFSET goes no further.
  private static final Integer FARTHEST_SKIP = 2000;

  private ReformPlan plan;
  private inj.IModel model;

  public ReformEngine(ReformPlan plan) {
    if (plan == null || !plan.isUsable()) {
      throw new ReformException(plan == null ? 'A plan is required' : String.join(plan.problems, '; '));
    }
    this.plan = plan;
    model = plan.model;
    // Sharing alone would still count and list the records of an object the user may not read.
    if (!model.describe().isAccessible()) {
      throw new ReformException('You cannot see ' + plan.pluralLabel);
    }
  }

  // Forms

  /**
   * The form for the values a component holds. An Id among them means an existing record. With
   * save, the record is written first and the form is the saved record's.
   */
  public ReformView.Form form(Map<String, Object> sent, Boolean save) {
    Map<String, Object> given = accepted(sent);
    SObject offered = model.spawnRecord(given);
    Boolean editing = offered.Id != null;
    SObject working = offered;
    if (editing) {
      working = stored(offered.Id);
      for (String fieldName : given.keySet()) {
        if (fieldName != 'Id') {
          working.put(fieldName, offered.get(fieldName));
        }
      }
    }
    settle(working, editing, given.keySet());
    attachParents(working);
    if (save == true) {
      Id savedId = write(working, editing, given.keySet());
      ReformView.Form afterSave = form(new Map<String, Object>{ 'Id' => savedId }, false);
      afterSave.saved = true;
      return afterSave;
    }
    return view(working, editing);
  }

  // The sent values the blueprint lets through: the Id, and fields that have a usable element and
  // that the user could write. Keys become the fields' API names; blank text becomes null.
  private Map<String, Object> accepted(Map<String, Object> sent) {
    Map<String, Object> kept = new Map<String, Object>();
    for (String key : sent == null ? new Set<String>() : sent.keySet()) {
      Object value = sent.get(key);
      Boolean blank = value == null || (value instanceof String && String.isBlank((String) value));
      if (key.equalsIgnoreCase('Id')) {
        if (!blank) {
          kept.put('Id', value);
        }
        continue;
      }
      SObjectField field = Naming.field(model, key);
      ReformPlan.Part part = field == null ? null : plan.partFor(field);
      if (part != null && part.usable() && (part.describe.isCreateable() || part.describe.isUpdateable())) {
        kept.put(part.describe.getName(), blank ? null : value);
      }
    }
    return kept;
  }

  // The record as stored, with every field the form shows or reads that the user may see.
  private SObject stored(Id recordId) {
    Set<SObjectField> wanted = new Set<SObjectField>();
    for (ReformPlan.Part part : plan.parts) {
      if (part.kind == ReformPlan.Kind.FIELD && part.usable()) {
        wanted.add(part.field);
      }
    }
    wanted.addAll(plan.fieldsRead);
    Set<SObjectField> visibleFields = new Set<SObjectField>();
    for (SObjectField field : wanted) {
      if (field.getDescribe().isAccessible()) {
        visibleFields.add(field);
      }
    }
    inj.IQuery one = model.query();
    one.fields().add(visibleFields);
    one.addCondition(Unify.s.condId(new Set<Id>{ recordId }));
    SObject found = one.withSharing(true).fetch();
    if (found == null) {
      throw new ReformException('That ' + plan.label + ' does not exist, or you cannot see it');
    }
    return found;
  }

  // Fixed values always apply. Defaults apply to a new record, for fields the component did not send.
  private void settle(SObject working, Boolean editing, Set<String> given) {
    for (ReformPlan.Part part : plan.parts) {
      if (part.kind != ReformPlan.Kind.FIELD || !part.usable() || part.describe.isCalculated() || part.describe.isAutoNumber()) {
        continue;
      }
      if (part.isFixed) {
        working.put(part.field, part.fixedValue);
      } else if (part.hasDefault && !editing && !given.contains(part.describe.getName())) {
        working.put(part.field, part.defaultValue);
      }
    }
  }

  // Loads the parents that rules and merge fields read through, by the lookup values the working
  // record holds now. A lookup the user has just changed therefore shows its new parent.
  private void attachParents(SObject working) {
    Map<SObjectType, Set<Id>> idsByType = new Map<SObjectType, Set<Id>>();
    Map<SObjectType, Set<inj.IPath>> readsByType = new Map<SObjectType, Set<inj.IPath>>();
    Map<SObjectField, SObjectType> typeByLookup = new Map<SObjectField, SObjectType>();
    for (SObjectField lookup : plan.parentPaths.keySet()) {
      Id parentId = lookup.getDescribe().isAccessible() || working.Id == null ? (Id) working.get(lookup) : null;
      Set<inj.IPath> reads = readable(plan.parentPaths.get(lookup));
      if (parentId == null || reads.isEmpty()) {
        continue;
      }
      SObjectType parentType = reads.iterator().next().source().token();
      typeByLookup.put(lookup, parentType);
      if (!idsByType.containsKey(parentType)) {
        idsByType.put(parentType, new Set<Id>());
        readsByType.put(parentType, new Set<inj.IPath>());
      }
      idsByType.get(parentType).add(parentId);
      readsByType.get(parentType).addAll(reads);
    }
    for (SObjectType parentType : idsByType.keySet()) {
      inj.IQuery parents = Unify.s.model(parentType).query();
      parents.fields().add(readsByType.get(parentType));
      parents.addCondition(Unify.s.condId(idsByType.get(parentType)));
      Map<Id, SObject> byId = new Map<Id, SObject>(parents.withSharing(true).run());
      for (SObjectField lookup : typeByLookup.keySet()) {
        SObject parent = typeByLookup.get(lookup) == parentType ? byId.get((Id) working.get(lookup)) : null;
        if (parent != null) {
          working.putSObject(lookup, parent);
        }
      }
    }
  }

  private static Set<inj.IPath> readable(Set<inj.IPath> paths) {
    Set<inj.IPath> allowed = new Set<inj.IPath>();
    for (inj.IPath path : paths) {
      if (path.describe().isAccessible()) {
        allowed.add(path);
      }
    }
    return allowed;
  }

  // Checks the user's permissions and the blueprint's required fields, then writes only the fields
  // the blueprint names and the user may write. Returns the record's Id.
  private Id write(SObject working, Boolean editing, Set<String> given) {
    DescribeSObjectResult described = model.describe();
    Boolean allowed = editing
      ? described.isUpdateable() && plan.definition.updateable != false
      : described.isCreateable() && plan.definition.createable != false;
    if (!allowed) {
      throw new ReformException('You cannot ' + (editing ? 'edit' : 'create') + ' ' + plan.pluralLabel + ' here');
    }
    if (editing && !access(working.Id).HasEditAccess) {
      throw new ReformException('You cannot edit this ' + plan.label);
    }
    List<String> missing = new List<String>();
    SObject outgoing = editing ? model.token().newSObject(working.Id) : model.token().newSObject();
    for (ReformPlan.Part part : plan.parts) {
      if (part.kind != ReformPlan.Kind.FIELD || !part.usable()) {
        continue;
      }
      Object value = part.describe.isAccessible() || !editing ? working.get(part.field) : null;
      Boolean empty = value == null || (value instanceof String && String.isBlank((String) value));
      if (part.required && empty && shows(part, working, editing)) {
        missing.add(part.label);
      }
      Boolean writable = editing ? part.describe.isUpdateable() : part.describe.isCreateable();
      Boolean touched = part.isFixed || given.contains(part.describe.getName()) || (!editing && !empty);
      if (writable && touched) {
        outgoing.put(part.field, value);
      }
    }
    if (!missing.isEmpty()) {
      throw new ReformException('Required: ' + String.join(missing, ', '));
    }
    if (!editing && plan.recordTypeId != null) {
      outgoing.put('RecordTypeId', plan.recordTypeId);
    }
    Unify.s.work().withSharing(true).track(outgoing).apply();
    return outgoing.Id;
  }

  // What sharing lets the user do with one record. Object permissions are checked separately.
  private UserRecordAccess access(Id recordId) {
    List<UserRecordAccess> found = [
      SELECT RecordId, HasReadAccess, HasEditAccess, HasDeleteAccess
      FROM UserRecordAccess
      WHERE UserId = :UserInfo.getUserId() AND RecordId = :recordId
    ];
    if (found.isEmpty() || !found[0].HasReadAccess) {
      throw new ReformException('That ' + plan.label + ' does not exist, or you cannot see it');
    }
    return found[0];
  }

  private ReformView.Form view(SObject working, Boolean editing) {
    ReformView.Form shown = new ReformView.Form();
    shown.objectName = model.name();
    shown.label = plan.label;
    shown.recordId = working.Id;
    shown.recordTypeId = plan.recordTypeId;
    shown.saved = false;
    shown.problems = plan.problems.clone();
    shown.parts = new List<ReformView.Part>();
    for (ReformPlan.Part part : plan.parts) {
      ReformView.Part drawn = new ReformView.Part();
      drawn.kind = part.kind.name();
      drawn.width = part.width;
      drawn.problems = part.problems.clone();
      drawn.visible = part.usable() && shows(part, working, editing);
      if (part.usable() && part.kind == ReformPlan.Kind.FIELD) {
        DescribeFieldResult described = part.describe;
        Boolean seen = described.isAccessible() || !editing;
        drawn.name = described.getName();
        drawn.label = part.label;
        drawn.dataType = described.getType().name();
        drawn.helpText = described.getInlineHelpText();
        drawn.required = part.required;
        drawn.reactive = part.reactive;
        drawn.readOnly = !(editing ? described.isUpdateable() : described.isCreateable());
        drawn.value = seen ? working.get(part.field) : null;
        Schema.DisplayType shape = described.getType();
        if (shape == Schema.DisplayType.PICKLIST || shape == Schema.DisplayType.MULTIPICKLIST) {
          drawn.options = choices(described);
        } else if (shape == Schema.DisplayType.REFERENCE && !described.getReferenceTo().isEmpty()) {
          drawn.lookupTo = String.valueOf(described.getReferenceTo()[0]);
        }
      } else if (part.usable() && part.content != null) {
        drawn.content = merged(part, working);
      }
      shown.parts.add(drawn);
    }
    return shown;
  }

  // A picklist's active values. They are the object's, not a record type's: Apex cannot see the latter.
  private static List<ReformView.Choice> choices(DescribeFieldResult described) {
    List<ReformView.Choice> offered = new List<ReformView.Choice>();
    for (Schema.PicklistEntry entry : described.getPicklistValues()) {
      if (entry.isActive()) {
        ReformView.Choice choice = new ReformView.Choice();
        choice.value = entry.getValue();
        choice.label = entry.getLabel();
        offered.add(choice);
      }
    }
    return offered;
  }

  // Whether a part is on show: its rule holds, and for a field, the blueprint offers it for this
  // kind of edit and the user may see it. A rule that cannot be evaluated hides the part.
  private Boolean shows(ReformPlan.Part part, SObject working, Boolean editing) {
    if (part.kind == ReformPlan.Kind.FIELD) {
      Boolean offered = !part.hidden && !part.isFixed && (editing ? part.onUpdate : part.onCreate);
      if (!offered || !part.describe.isAccessible()) {
        return false;
      }
    }
    if (part.showWhen == null) {
      return true;
    }
    try {
      return part.showWhen.evaluate(working) == true;
    } catch (Exception unreadable) {
      return false;
    }
  }

  // The part's text with each {!path} replaced by the value there. Values going into rich text
  // are escaped, so a record's data cannot add markup.
  private String merged(ReformPlan.Part part, SObject working) {
    String filled = part.content;
    for (String placeholder : part.mergePaths.keySet()) {
      inj.IPath path = part.mergePaths.get(placeholder);
      String written = '';
      try {
        written = display(path.getFieldValue(working), path.describe().getSoapType());
      } catch (Exception unread) {
        written = '';
      }
      filled = filled.replace(placeholder, part.kind == ReformPlan.Kind.RICH_TEXT ? written.escapeHtml4() : written);
    }
    return filled;
  }

  private static String display(Object value, Schema.SoapType valueType) {
    if (value == null) {
      return '';
    }
    if (valueType == Schema.SoapType.DATE) {
      return ((Date) value).format();
    }
    if (valueType == Schema.SoapType.DATETIME) {
      return ((Datetime) value).format();
    }
    if (value instanceof Integer) {
      return ((Integer) value).format();
    }
    if (value instanceof Long) {
      return ((Long) value).format();
    }
    if (value instanceof Decimal) {
      return ((Decimal) value).format();
    }
    if (value instanceof Double) {
      return Decimal.valueOf((Double) value).format();
    }
    return String.valueOf(value);
  }

  // Tables

  /** A page of the records the blueprint lists, with the count of all that match. */
  public ReformView.Table table(Integer pageSize, Integer skip) {
    ReformView.Table shown = new ReformView.Table();
    shown.objectName = model.name();
    shown.label = plan.label;
    shown.pluralLabel = plan.pluralLabel;
    shown.problems = plan.problems.clone();
    DescribeSObjectResult allowed = model.describe();
    shown.canCreate = allowed.isCreateable() && plan.definition.createable != false;
    shown.canEdit = allowed.isUpdateable() && plan.definition.updateable != false;
    shown.canDelete = allowed.isDeletable() && plan.definition.deleteable != false;
    shown.pageSize = Math.min(Math.max(pageSize ?? DEFAULT_PAGE, 1), LARGEST_PAGE);
    shown.skip = Math.min(Math.max(skip ?? 0, 0), FARTHEST_SKIP);
    shown.columns = new List<ReformView.Column>();

    Map<String, inj.IPath> pathByColumn = new Map<String, inj.IPath>();
    inj.IPath sortBy;
    for (ReformPlan.Column column : plan.columns) {
      ReformView.Column drawn = new ReformView.Column();
      drawn.name = column.name;
      drawn.label = column.label;
      drawn.problems = column.problems.clone();
      if (column.path != null && !column.path.describe().isAccessible()) {
        drawn.problems.add('You cannot see ' + column.name);
      }
      if (drawn.problems.isEmpty()) {
        drawn.dataType = column.path.describe().getType().name();
        pathByColumn.put(column.name, column.path);
        if (sortBy == null && column.path.describe().isSortable()) {
          sortBy = column.path;
        }
      }
      shown.columns.add(drawn);
    }

    inj.IQuery listed = model.query();
    listed.fields().add(new Set<inj.IPath>(pathByColumn.values()));
    for (inj.ICondition condition : plan.rowConditions) {
      listed.addCondition(condition);
    }
    if (sortBy != null) {
      listed.orderings().add(Unify.s.ordering(sortBy, true, true));
    }
    // Id last, so pages do not shuffle records that sort alike.
    listed.orderings().add(Unify.s.ordering('Id', true, false));
    listed.withSharing(true).setLimit(shown.pageSize).setOffset(shown.skip);

    shown.total = listed.count();
    shown.rows = new List<Map<String, Object>>();
    for (SObject record : listed.run()) {
      Map<String, Object> row = new Map<String, Object>{ 'Id' => record.Id };
      for (String column : pathByColumn.keySet()) {
        row.put(column, pathByColumn.get(column).getFieldValue(record));
      }
      shown.rows.add(row);
    }
    return shown;
  }

  // Deleting

  /** Deletes a record of the blueprint's object, if the blueprint and the user's permissions allow. */
  public void remove(Id recordId) {
    if (recordId == null || recordId.getSObjectType() != model.token()) {
      throw new ReformException('That is not a ' + plan.label);
    }
    if (plan.definition.deleteable == false || !model.describe().isDeletable()) {
      throw new ReformException('You cannot delete ' + plan.pluralLabel + ' here');
    }
    if (!access(recordId).HasDeleteAccess) {
      throw new ReformException('You cannot delete this ' + plan.label);
    }
    Unify.s.work().withSharing(true).purge(model.token().newSObject(recordId)).apply();
  }
}
