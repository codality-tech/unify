/**
 * A lookup that makes its record instead of picking one: "create" on a blueprint element. The record
 * made is the lookup's object, or another object whose field fills the lookup ("fill"), which is how
 * a Person Account fills a Contact lookup from its PersonContactId. These tests use Account, Contact,
 * Case and Opportunity, since a scratch org without Person Accounts has nothing closer.
 */
@IsTest
private class ReformCreateTest {
  // A contact whose account is picked, or made on the spot.
  private static final String PERSON =
    '{"sobjectName":"Contact","elements":[' +
    '{"field":{"name":"LastName","required":true}},' +
    '{"field":{"name":"AccountId","create":{"blueprint":"new_company"}}}]}';

  private static void store(String apiName, String objectName, String elements) {
    insert new Reform_Blueprint__c(Name = apiName, Api_Name__c = apiName, Sobject_Name__c = objectName, Elements__c = elements);
  }

  private static void storeCompany() {
    store('new_company', 'Account', '[{"field":{"name":"Name","required":true}},{"field":{"name":"Industry"}}]');
  }

  private static ReformPlan planFor(String written) {
    return ReformPlan.compile(ReformDefinition.fromMap((Map<String, Object>) JSON.deserializeUntyped(written)));
  }

  private static ReformEngine engineFor(String written) {
    return new ReformEngine(planFor(written));
  }

  private static ReformView.Part fieldPart(ReformView.Form form, String name) {
    for (ReformView.Part part : form.parts) {
      if (part.name == name) {
        return part;
      }
    }
    Assert.fail('The form has no part for ' + name);
    return null;
  }

  private static String problemsOf(String written) {
    return String.join(planFor(written).allProblems(), '; ');
  }

  @IsTest
  static void aLookupOffersToMakeItsRecord() {
    storeCompany();

    ReformView.Form blank = engineFor(PERSON).form(null, false);

    ReformView.Part company = fieldPart(blank, 'AccountId');
    Assert.areEqual('new_company', company.createBlueprint, 'the form says which blueprint makes the record');
    Assert.areEqual('New Account', company.createLabel);
    Assert.isNull(fieldPart(blank, 'LastName').createBlueprint, 'only a lookup that can make one offers it');
    Assert.isTrue(planFor(PERSON).allProblems().isEmpty(), String.join(planFor(PERSON).allProblems(), '; '));
  }

  @IsTest
  static void theRecordMadeIsSavedFirstAndFillsTheLookup() {
    storeCompany();
    Map<String, Object> sent = new Map<String, Object>{
      'LastName' => 'Lovelace',
      'AccountId' => new Map<String, Object>{ 'create' => new Map<String, Object>{ 'Name' => 'Analytical Engines', 'Industry' => 'Technology' } }
    };

    ReformView.Form saved = engineFor(PERSON).form(sent, true);

    Assert.isTrue(saved.saved);
    Contact ada = [SELECT LastName, AccountId, Account.Name, Account.Industry FROM Contact WHERE Id = :saved.recordId];
    Assert.areEqual('Analytical Engines', ada.Account.Name, 'the contact points at the account made with it');
    Assert.areEqual('Technology', ada.Account.Industry, 'the account was saved through its own blueprint');
    Assert.areEqual(ada.AccountId, (Id) fieldPart(saved, 'AccountId').value);
  }

  @IsTest
  static void aRefusedSaveLeavesNoRecordBehind() {
    storeCompany();
    Map<String, Object> noLastName = new Map<String, Object>{
      'AccountId' => new Map<String, Object>{ 'create' => new Map<String, Object>{ 'Name' => 'Never Saved' } }
    };
    Map<String, Object> noCompanyName = new Map<String, Object>{
      'LastName' => 'Babbage',
      'AccountId' => new Map<String, Object>{ 'create' => new Map<String, Object>{ 'Industry' => 'Technology' } }
    };

    for (Map<String, Object> sent : new List<Map<String, Object>>{ noLastName, noCompanyName }) {
      try {
        engineFor(PERSON).form(sent, true);
        Assert.fail('A form that cannot be saved is refused');
      } catch (ReformEngine.ReformException refused) {
        Assert.isTrue(refused.getMessage().startsWith('Required: '), refused.getMessage());
      }
    }

    Assert.areEqual(0, [SELECT COUNT() FROM Account], 'the account made for a refused contact is taken back');
    Assert.areEqual(0, [SELECT COUNT() FROM Contact], 'and a contact whose account was refused is not saved');
  }

  @IsTest
  static void aFieldOfTheRecordMadeCanFillTheLookup() {
    Account acme = new Account(Name = 'Acme');
    insert acme;
    // A contact made at Acme fills an opportunity's account: the account, not the contact.
    store(
      'contact_at_acme',
      'Contact',
      '[{"field":{"name":"LastName","required":true}},{"field":{"name":"AccountId","fixedValue":"' + acme.Id + '"}}]'
    );
    String deal =
      '{"sobjectName":"Opportunity","elements":[' +
      '{"field":{"name":"Name"}},{"field":{"name":"CloseDate"}},{"field":{"name":"StageName","fixedValue":"Prospecting"}},' +
      '{"field":{"name":"AccountId","create":{"blueprint":"contact_at_acme","fill":"AccountId"}}}]}';
    Map<String, Object> sent = new Map<String, Object>{
      'Name' => 'Engines',
      'CloseDate' => '2030-01-15',
      'AccountId' => new Map<String, Object>{ 'create' => new Map<String, Object>{ 'LastName' => 'Babbage' } }
    };

    ReformView.Form saved = engineFor(deal).form(sent, true);

    Assert.areEqual(acme.Id, [SELECT AccountId FROM Opportunity WHERE Id = :saved.recordId].AccountId, 'filled from the new contact');
    Assert.areEqual(acme.Id, [SELECT AccountId FROM Contact WHERE LastName = 'Babbage'].AccountId, 'and the contact was made');
  }

  @IsTest
  static void aBlueprintThatCannotMakeTheRecordSaysWhy() {
    storeCompany();
    store('contact_maker', 'Contact', '[{"field":{"name":"LastName"}},{"field":{"name":"AccountId","create":{"blueprint":"new_company"}}}]');
    store('plain_contact', 'Contact', '[{"field":{"name":"LastName"}}]');

    Assert.isTrue(
      problemsOf('{"sobjectName":"Contact","elements":[{"field":{"name":"LastName","create":{"blueprint":"new_company"}}}]}')
        .contains('is not a lookup'),
      'only a lookup can make a record'
    );
    Assert.isTrue(
      problemsOf('{"sobjectName":"Contact","elements":[{"field":{"name":"AccountId","create":{"blueprint":"no_such_blueprint"}}}]}')
        .contains('There is no stored blueprint named no_such_blueprint'),
      'the blueprint must be stored'
    );
    Assert.isTrue(
      problemsOf('{"sobjectName":"Contact","elements":[{"field":{"name":"AccountId","create":{}}}]}').contains('needs the name of a stored blueprint')
    );
    Assert.isTrue(
      problemsOf('{"sobjectName":"Contact","elements":[{"field":{"name":"ReportsToId","create":{"blueprint":"new_company"}}}]}')
        .contains('that fills ReportsToId (fill)'),
      'an account cannot fill a contact lookup unless a field of it says how'
    );
    Assert.isTrue(
      problemsOf(
          '{"sobjectName":"Opportunity","elements":[{"field":{"name":"AccountId","create":{"blueprint":"plain_contact","fill":"LastName"}}}]}'
        )
        .contains('cannot fill AccountId'),
      'the field that fills the lookup must point at its object'
    );
    Assert.isTrue(
      problemsOf('{"sobjectName":"Case","elements":[{"field":{"name":"ContactId","create":{"blueprint":"contact_maker"}}}]}')
        .contains('cannot make another'),
      'a record made from a lookup does not make another'
    );
  }

  @IsTest
  static void aStoredBlueprintThatCannotMakeItsRecordIsNotSaved() {
    try {
      store('broken_person', 'Contact', '[{"field":{"name":"AccountId","create":{"blueprint":"missing"}}}]');
      Assert.fail('A blueprint with a mistake is not saved');
    } catch (DmlException refused) {
      Assert.isTrue(refused.getDmlMessage(0).contains('There is no stored blueprint named missing'), refused.getDmlMessage(0));
    }
  }

  @IsTest
  static void aLookupThatCannotMakeARecordRefusesOne() {
    storeCompany();
    String plain = '{"sobjectName":"Contact","elements":[{"field":{"name":"LastName"}},{"field":{"name":"AccountId"}}]}';
    try {
      engineFor(plain)
        .form(
          new Map<String, Object>{ 'LastName' => 'Hopper', 'AccountId' => new Map<String, Object>{ 'create' => new Map<String, Object>{ 'Name' => 'X' } } },
          true
        );
      Assert.fail('A record is made only where the blueprint says so');
    } catch (ReformEngine.ReformException refused) {
      Assert.areEqual('AccountId cannot make a record here', refused.getMessage());
    }
    Assert.areEqual(0, [SELECT COUNT() FROM Account]);
  }

  @IsTest
  static void aRowWhoseParentIsSetOnceCanBeSavedAndOpenedAgain() {
    // A related list's parent is often set once, when the row is made: a case comment's case, a
    // junction row's two records. The saved row is shown again at once, and opened for an edit later.
    Assert.isFalse(CaseComment.ParentId.getDescribe().isUpdateable(), 'the test needs a parent that is set once');
    Case question = new Case(Subject = 'Where is my statement?');
    insert question;
    String comments =
      '{"sobjectName":"CaseComment","elements":[{"field":{"name":"CommentBody"}},{"richtext":{"content":"On {!Parent.Subject}"}}],' +
      '"parameters":[{"name":"ParentId","fixedValue":"' + question.Id + '"}]}';

    ReformView.Form saved = engineFor(comments).form(new Map<String, Object>{ 'CommentBody' => 'Sent today' }, true);
    ReformView.Form edited = engineFor(comments).form(new Map<String, Object>{ 'Id' => saved.recordId, 'CommentBody' => 'Sent yesterday', 'ParentId' => question.Id }, true);

    Assert.isTrue(saved.saved);
    Assert.isTrue(edited.saved);
    Assert.areEqual('On Where is my statement?', edited.parts[1].content, 'and its parent is read through the lookup as before');
    CaseComment stored = [SELECT ParentId, CommentBody FROM CaseComment WHERE Id = :saved.recordId];
    Assert.areEqual(question.Id, stored.ParentId);
    Assert.areEqual('Sent yesterday', stored.CommentBody);
  }
}
