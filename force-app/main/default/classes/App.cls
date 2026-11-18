public class App {
    public static inj.IApplication s{private set; get{
        if (s == null){
            s = inj.Application.make(
                new Scheme64(), // Your scheme - injected throughout entire framework
                new Map<Type, Type>{
                    ExampleService.IService.class => ExampleService.class
                },
                new Map<Type, Type>{ // queries
                    Reform_Blueprint__c.class => ReformBlueprintQuery.class
                },
                new Map<Type, Type>{ // domains
                    Reform_Blueprint__c.class => ReformBlueprints.class
                },
                new Map<Type, Type>{ // trigger handlers
                    Account.class => ExampleService.Triggered.class,
                    Rollup_Sample_Child__c.class => RollupHandler.class,
                    Rollup_Sample_Parent__c.class => RollupHandler.class,
                    Reform_Blueprint__c.class => ReformBlueprints.class
                }
            );
        }
        return s;
    }}    
    public static inj.IApplication b{private set; get{
        if (b == null){
            b = inj.Application.make(
                new Scheme64(), // Your scheme - injected throughout entire framework
                null,
                null, // Optional: your queries
                new Map<Type, Type>{ Account.class => Accounts.class }
            );
        }
        return b;
    }}   
} 