/** The entry point the guides call App, with the guides' example classes registered. */
public class GuideApp {
  public static unif.IApplication s {
    get {
      if (s == null) {
        s = unif.Application.make(
          null, // scheme: null uses the default
          new Map<Type, Type>{ GuideExamples.IInvoicing.class => GuideExamples.Invoicing.class }, // services
          new Map<Type, Type>{ Account.class => GuideExamples.AccountQuery.class, Case.class => GuideExamples.OpenCaseQuery.class }, // queries
          new Map<Type, Type>{ Opportunity.class => GuideExamples.Opportunities.class } // domains, also used for triggers
        );
      }
      return s;
    }
    private set;
  }
}
