/**
 * Object and field names as an administrator writes them in a rule, a plan, a format or a blueprint.
 *
 * Inside the package, Unify's own objects and fields carry its namespace
 * (unif__Rollup_Sample_Child__c). The framework does the looking up, it lives in a namespace of its
 * own, and from there it finds them by their full names only. So a custom name that is not found as
 * written is looked for once more in Unify's namespace. An org's own names, and names that already
 * carry a namespace, are found the first time. Where Unify is deployed as source there is no
 * namespace, and nothing here changes anything.
 */
public class Naming {
  private static final Pattern DOTTED_NAME = Pattern.compile('[A-Za-z_][A-Za-z0-9_]*(?:\\.[A-Za-z_][A-Za-z0-9_]*)*');

  // 'unif__' inside the package; empty where the code is deployed as source.
  @TestVisible
  private static String prefix {
    get {
      if (prefix == null) {
        String full = Naming.class.getName();
        prefix = full.contains('.') ? full.substringBefore('.') + '__' : '';
      }
      return prefix;
    }
    set;
  }

  // Whether a second look is worth it: a custom name that does not carry Unify's namespace already.
  private static Boolean mayBeOurs(String written) {
    return String.isNotBlank(prefix) && written.contains('__') && !written.startsWithIgnoreCase(prefix);
  }

  /** The model of the object with the name; null when no object has it. */
  public static inj.IModel model(inj.IApplication app, String objectName) {
    String written = objectName?.trim();
    if (String.isBlank(written)) {
      return null;
    }
    inj.IModel found = app.model(written);
    return found == null && mayBeOurs(written) ? app.model(prefix + written) : found;
  }

  /** The object's field with the name; null when it has none. */
  public static SObjectField field(inj.IModel owner, String fieldName) {
    String written = fieldName?.trim();
    if (owner == null || String.isBlank(written)) {
      return null;
    }
    Map<String, SObjectField> known = owner.fieldMap();
    SObjectField found = known.get(written);
    return found == null && mayBeOurs(written) ? known.get(prefix + written) : found;
  }

  /** A name without Unify's namespace at its start; any other name as it is. */
  public static String withoutNamespace(String name) {
    return String.isNotBlank(prefix) && name.startsWithIgnoreCase(prefix) ? name.substring(prefix.length()) : name;
  }

  /**
   * A filter or a field path with Unify's own names written in full, so that the framework can read
   * it: inside the package Status__c = 'Open' becomes unif__Status__c = 'Open'. Text between quotes
   * is left alone, and so is every name that is found as written, or not found at all.
   */
  public static String inText(inj.IModel start, String text) {
    if (start == null || String.isBlank(prefix) || String.isBlank(text) || !text.contains('__')) {
      return text;
    }
    String whole = '';
    Integer at = 0;
    while (at < text.length()) {
      Integer opens = text.indexOf('\'', at);
      if (opens < 0) {
        whole += outsideQuotes(start, text.substring(at));
        break;
      }
      Integer closes = endOfQuoted(text, opens);
      whole += outsideQuotes(start, text.substring(at, opens)) + text.substring(opens, closes);
      at = closes;
    }
    return whole;
  }

  // The position after the quote that closes the one at `opens`; the end of the text when none does.
  private static Integer endOfQuoted(String text, Integer opens) {
    Integer at = opens + 1;
    while (at < text.length()) {
      String here = text.substring(at, at + 1);
      if (here == '\'') {
        return at + 1;
      }
      at += here == '\\' ? 2 : 1;
    }
    return text.length();
  }

  private static String outsideQuotes(inj.IModel start, String plain) {
    Matcher words = DOTTED_NAME.matcher(plain);
    String whole = '';
    Integer copied = 0;
    while (words.find()) {
      whole += plain.substring(copied, words.start()) + inFull(start, words.group());
      copied = words.end();
    }
    return whole + plain.substring(copied);
  }

  // A dotted name with each part that is one of Unify's own written in full. The walk stops at the
  // first part that is neither a field nor a lookup's relationship; the rest is kept as written.
  private static String inFull(inj.IModel start, String dotted) {
    if (!dotted.contains('__')) {
      return dotted;
    }
    inj.IScheme scheme = start.scheme();
    Map<String, SObjectField> known = start.fieldMap();
    List<String> parts = dotted.split('\\.');
    for (Integer at = 0; at < parts.size() && known != null; at++) {
      SObjectField step = stepIn(known, parts[at]);
      if (step == null && mayBeOurs(parts[at])) {
        step = stepIn(known, prefix + parts[at]);
        if (step != null) {
          parts[at] = prefix + parts[at];
        }
      }
      List<SObjectType> pointsAt = step == null ? null : scheme.getFieldDescribe(step).getReferenceTo();
      known = pointsAt != null && pointsAt.size() == 1 ? scheme.getFieldMap(pointsAt[0]) : null;
    }
    return String.join(parts, '.');
  }

  // A part of a path is a field, or the relationship of a lookup: Owner__r for Owner__c, Account for AccountId.
  private static SObjectField stepIn(Map<String, SObjectField> known, String part) {
    SObjectField found = known.get(part);
    if (found == null && part.endsWithIgnoreCase('__r')) {
      found = known.get(part.removeEndIgnoreCase('__r') + '__c');
    } else if (found == null && !part.endsWithIgnoreCase('__c')) {
      found = known.get(part + 'Id');
    }
    return found;
  }
}
