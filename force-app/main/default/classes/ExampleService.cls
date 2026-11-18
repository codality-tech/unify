/**
 * Example Service demonstrating UNIF framework patterns.
 * Separates business logic from domain operations and uses proper async patterns.
 */
public class ExampleService implements ExampleService.IService {
    
    // Service singleton accessor
    public static IService s {
        private set;
        get {
            return (IService) App.s.sf().get(IService.class);
        }
    }

    public interface IService {
        void randomizeField(unif.ICondition filter, String charset, SObjectField field);
    }
    
    public void randomizeField(unif.ICondition filter, String charset, SObjectField field) {
        if (charset == null) {
            charset = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
        }
        RandomizeFieldHandler handler = new RandomizeFieldHandler(filter, charset, field);
        
        // Use UNIF async framework for proper job chaining
        unif.Async.queueable(handler).execute();
    }

    //* Triggered
    public class Triggered implements unif.ITriggered{
        public void handleTrigger(TriggerOperation op, List<SObject> trigNew, List<SObject> trigOld, Map<Id,SObject> trigOldMap, unif.IModel model){
            if (op == TriggerOperation.AFTER_INSERT){
                unif.IDomain dom = App.s.df().make(model.token(), (List<SObject>)trigNew);
                unif.ICondition cnd = App.s.iin(model.path('Id'), dom.toMap().keySet());
                ExampleService.s.randomizeField(cnd, null, Account.Description);
            }
        }
    }
    
    /**
     * Async handler for field randomization using UNIF async patterns
     */
    public class RandomizeFieldHandler implements unif.IBatchQueryableHandler, unif.IQueueableHandler {
        private unif.ICondition filter;
        private String charset;
        private SObjectField field;
        
        public RandomizeFieldHandler(unif.ICondition filter, String charset, SObjectField field) {
            this.filter = filter;
            this.charset = charset;
            this.field = field;
        }
        
        public unif.IQuery batchStart() {
            unif.IQuery query = App.s.qf().make(filter.source().token());
            query.filters().add(filter);
            return query;
        }
        
        public void batchExecute(List<SObject> records) {
            if (records == null || records.isEmpty()) {
                return;
            }

            // Use domain for record manipulation
            unif.IDomain domain = App.s.df().make(records);
            unif.IWork work = App.s.work();
            
            for (SObject rec : domain.records()) {
                String randomValue = unif.RandomUtil.getString(20, charset);
                rec.put(field, randomValue);
                work.track(rec);
            }
            
            work.apply();
        }
        
        public void batchFinish() {
            // Cleanup or final processing if needed
        }
        public integer batchDefaultSize(){
            return 20;
        }
        
        public void queueableExecute() {
            // For small datasets, execute synchronously
            List<SObject> records = batchStart().run();
            batchExecute(records);
        }
    }
}