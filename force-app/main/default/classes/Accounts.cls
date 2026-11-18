global class Accounts extends unif.BaseDomain implements IAccounts {
    
    global Accounts() {
        super();
    }
    
    global Accounts(unif.IModel source, List<SObject> records) {
        super(source, records);
    }

    global List<Account> items(){
        return (List<Account>)base().records();
    }
    
    global override void onBeforeUpsert(Map<Id, SObject> oldMap) {
        printDescriptions();
    }

    private void printDescriptions(){
        for (Account item : items()){
            system.debug(item.Description);
        }
    }

}

