/**
 * Helpers for showing the framework from anonymous Apex: what a query looks like, what came back,
 * and what a piece of work cost.
 *
 *   unif.IQuery q = App.s.model(Account.SObjectType).query();
 *   q.fields().add(new Set<SObjectField>{ Account.Name, Account.Industry });
 *   Demo.run(q, new List<String>{ 'Name', 'Industry' });   // prints the SOQL, then the rows as a table
 *   Demo.cost('That query');                               // prints what was spent since the last mark
 *
 * Every line goes to the debug log behind a marker, so scripts/demo/run.py can print those lines
 * and nothing else.
 */
public class Demo {
  /** What every line starts with in the debug log. */
  public static final String MARK = 'DEMO::';

  private static final Integer WIDEST = 34;
  private static Integer queriesAtMark = Limits.getQueries();
  private static Integer statementsAtMark = Limits.getDmlStatements();
  private static Integer rowsAtMark = Limits.getDmlRows();

  public static void say(Object line) {
    for (String part : String.valueOf(line).split('\n')) {
      System.debug(LoggingLevel.ERROR, MARK + part);
    }
  }

  public static void title(String text) {
    say('');
    say('== ' + text + ' ==');
  }

  /** The query as SOQL, with its values written in. */
  public static void soql(unif.IQuery query) {
    say(query.toSoql());
  }

  /** Prints the query, runs it, prints the rows, and hands them back. */
  public static List<SObject> run(unif.IQuery query, List<String> columns) {
    soql(query);
    List<SObject> records = query.run();
    table(records, columns);
    return records;
  }

  /** The records as a table. A column is a field name, or a path through a lookup: 'Account.Name'. */
  public static void table(List<SObject> records, List<String> columns) {
    for (String line : tableOf(records, columns)) {
      say(line);
    }
  }

  public static List<String> tableOf(List<SObject> records, List<String> columns) {
    List<List<String>> grid = new List<List<String>>{ columns };
    for (SObject record : records) {
      List<String> row = new List<String>();
      for (String column : columns) {
        row.add(textOf(valueAt(record, column)));
      }
      grid.add(row);
    }
    List<Integer> widths = new List<Integer>();
    for (Integer at = 0; at < columns.size(); at++) {
      Integer width = 0;
      for (List<String> row : grid) {
        width = Math.max(width, row[at].length());
      }
      widths.add(width);
    }
    List<String> lines = new List<String>();
    for (Integer line = 0; line < grid.size(); line++) {
      List<String> cells = new List<String>();
      List<String> rule = new List<String>();
      for (Integer at = 0; at < columns.size(); at++) {
        cells.add(grid[line][at].rightPad(widths[at]));
        rule.add('-'.repeat(widths[at]));
      }
      lines.add(String.join(cells, '  ').trim());
      if (line == 0) {
        lines.add(String.join(rule, '  '));
      }
    }
    if (records.isEmpty()) {
      lines.add('(no records)');
    }
    return lines;
  }

  /** Starts counting from here. */
  public static void mark() {
    queriesAtMark = Limits.getQueries();
    statementsAtMark = Limits.getDmlStatements();
    rowsAtMark = Limits.getDmlRows();
  }

  /** What was spent since the last mark, or since the transaction began. Then starts counting again. */
  public static String costSince() {
    Integer queries = Limits.getQueries() - queriesAtMark;
    Integer statements = Limits.getDmlStatements() - statementsAtMark;
    Integer rows = Limits.getDmlRows() - rowsAtMark;
    mark();
    return counted(queries, 'query', 'queries') +
      ', ' +
      counted(statements, 'DML statement', 'DML statements') +
      ', ' +
      counted(rows, 'record', 'records') +
      ' saved or deleted';
  }

  public static void cost(String label) {
    say(label + ': ' + costSince());
  }

  /** What a unit of work could not save, one line for each record. */
  public static void failures(unif.IWork work) {
    if (work.failures().isEmpty()) {
      say('Every record was saved');
    }
    for (unif.IWorkFailure failure : work.failures()) {
      say(failure.getRecord().getSObjectType() + nameOf(failure.getRecord()) + ': ' + failure.getMessage().removeStart('Not saved: '));
    }
  }

  /**
   * Switches off this org's example triggers on Account for the rest of the transaction. They
   * belong to another example (they fill in descriptions in a job of their own) and would be
   * counted in the cost of whatever is being shown.
   */
  public static void quietExamples() {
    App.s.tf().disable(new List<SObjectType>{ Account.SObjectType });
    App.b.tf().disable();
  }

  private static String counted(Integer count, String one, String many) {
    return count + ' ' + (count == 1 ? one : many);
  }

  private static String nameOf(SObject record) {
    Map<String, Object> filled = record.getPopulatedFieldsAsMap();
    for (String field : new List<String>{ 'Name', 'LastName', 'Subject' }) {
      if (filled.get(field) != null) {
        return ' "' + filled.get(field) + '"';
      }
    }
    return '';
  }

  // Follows a dotted path through lookups. A parent that is missing reads as null.
  private static Object valueAt(SObject record, String path) {
    List<String> hops = path.split('\\.');
    SObject holder = record;
    try {
      for (Integer at = 0; at < hops.size() - 1 && holder != null; at++) {
        holder = holder.getSObject(hops[at]);
      }
      return holder?.get(hops[hops.size() - 1]);
    } catch (SObjectException unreadable) {
      return '(not selected)';
    }
  }

  private static String textOf(Object value) {
    if (value == null) {
      return '';
    }
    String text = value instanceof Date ? String.valueOf((Date) value) : String.valueOf(value);
    return text.replace('\n', ' ').abbreviate(WIDEST);
  }
}
