/**
 * Reform as users who are not administrators: one with no access to the object, one who may only
 * read it, and one who may edit it but cannot see or change every field.
 *
 * Every object in a scratch org is shared read/write by default, so these tests cover object and
 * field permissions. Records hidden by sharing are not covered here.
 */
@IsTest
private class ReformAccessTest {
  private static final String ACCOUNTS =
    '{"sobjectName":"Account","elements":[' +
    '{"field":{"name":"Name"}},' +
    '{"field":{"name":"Industry"}},' +
    '{"field":{"name":"Rating"}},' +
    '{"field":{"name":"AnnualRevenue"}},' +
    '{"visible":"AnnualRevenue > 1000000","heading":{"content":"A large account"}},' +
    '{"richtext":{"content":"Revenue: {!AnnualRevenue}"}}],' +
    '"columns":[{"name":"Name"},{"name":"Industry"},{"name":"AnnualRevenue"}]}';

  private static ReformEngine engine() {
    return new ReformEngine(ReformPlan.compile(ReformDefinition.fromMap((Map<String, Object>) JSON.deserializeUntyped(ACCOUNTS))));
  }

  /** A user whose profile grants nothing, given exactly the access asked for through a permission set. */
  private static User userWith(ObjectPermissions onAccount, Map<String, Boolean> editByField) {
    User made = new User(
      ProfileId = [SELECT Id FROM Profile WHERE Name = 'Minimum Access - Salesforce'].Id,
      LastName = 'Restricted',
      Alias = 'rstrctd',
      Email = 'restricted@reform.example.com',
      Username = 'restricted.' + UserInfo.getOrganizationId() + '.' + System.now().getTime() + '@reform.example.com',
      TimeZoneSidKey = 'GMT',
      LocaleSidKey = 'en_US',
      EmailEncodingKey = 'UTF-8',
      LanguageLocaleKey = 'en_US'
    );
    // Users and permission sets are setup objects: saved as another "user" so the test can save records afterwards.
    System.runAs(new User(Id = UserInfo.getUserId())) {
      insert made;
      if (onAccount != null) {
        PermissionSet granted = new PermissionSet(Name = 'Reform_Access_Test', Label = 'Reform Access Test');
        insert granted;
        onAccount.ParentId = granted.Id;
        onAccount.SobjectType = 'Account';
        insert onAccount;
        List<FieldPermissions> fields = new List<FieldPermissions>();
        for (String fieldName : editByField.keySet()) {
          fields.add(
            new FieldPermissions(
              ParentId = granted.Id,
              SobjectType = 'Account',
              Field = 'Account.' + fieldName,
              PermissionsRead = true,
              PermissionsEdit = editByField.get(fieldName)
            )
          );
        }
        insert fields;
        insert new PermissionSetAssignment(AssigneeId = made.Id, PermissionSetId = granted.Id);
      }
    }
    return made;
  }

  private static Account acme() {
    App.s.tf().disable(new List<SObjectType>{ Account.SObjectType });
    App.b.tf().disable();
    Account made = new Account(Name = 'Acme', Industry = 'Energy', Rating = 'Hot', AnnualRevenue = 5000000);
    insert made;
    return made;
  }

  private static Account reread(Id accountId) {
    return [SELECT Name, Industry, Rating, AnnualRevenue FROM Account WHERE Id = :accountId];
  }

  private static ReformView.Part named(ReformView.Form form, String name) {
    for (ReformView.Part part : form.parts) {
      if (part.name == name) {
        return part;
      }
    }
    Assert.fail('The form has no part for ' + name);
    return null;
  }

  private static ReformView.Part ofKind(ReformView.Form form, String kind) {
    for (ReformView.Part part : form.parts) {
      if (part.kind == kind) {
        return part;
      }
    }
    Assert.fail('The form has no ' + kind);
    return null;
  }

  private static String refusal(ReformEngine engine, String action, Map<String, Object> values, Id recordId) {
    try {
      if (action == 'save') {
        engine.form(values, true);
      } else if (action == 'show') {
        engine.form(values, false);
      } else if (action == 'list') {
        engine.table(10, 0);
      } else {
        engine.remove(recordId);
      }
    } catch (ReformEngine.ReformException refused) {
      return refused.getMessage();
    }
    return null;
  }

  @IsTest
  static void aUserWithNoAccessToTheObjectIsRefusedEverything() {
    User outsider = userWith(null, null);
    Account stored = acme();

    System.runAs(outsider) {
      try {
        engine();
        Assert.fail('An object the user cannot read was opened');
      } catch (ReformEngine.ReformException refused) {
        Assert.areEqual('You cannot see Accounts', refused.getMessage());
      }
    }
    Assert.areEqual('Acme', reread(stored.Id).Name);
  }

  @IsTest
  static void aUserWhoMayOnlyReadSeesRecordsAndIsOfferedNoChanges() {
    User reader = userWith(
      new ObjectPermissions(PermissionsRead = true),
      new Map<String, Boolean>{ 'Industry' => false, 'Rating' => false, 'AnnualRevenue' => false }
    );
    Account stored = acme();

    System.runAs(reader) {
      ReformEngine engine = engine();

      ReformView.Table listed = engine.table(10, 0);
      Assert.areEqual(1, listed.total);
      Assert.areEqual('Energy', listed.rows[0].get('Industry'));
      Assert.isFalse(listed.canCreate, 'New is not offered');
      Assert.isFalse(listed.canEdit, 'Edit is not offered');
      Assert.isFalse(listed.canDelete, 'Delete is not offered');

      ReformView.Form shown = engine.form(new Map<String, Object>{ 'Id' => stored.Id }, false);
      Assert.areEqual('Energy', named(shown, 'Industry').value);
      Assert.isTrue(named(shown, 'Industry').readOnly);
      Assert.isTrue(named(shown, 'Name').readOnly);

      // Asking anyway is refused on the server, whatever the component offers.
      Assert.areEqual('You cannot create Accounts here', refusal(engine, 'save', new Map<String, Object>{ 'Name' => 'Mine' }, null));
      Assert.areEqual(
        'You cannot edit Accounts here',
        refusal(engine, 'save', new Map<String, Object>{ 'Id' => stored.Id, 'Name' => 'Renamed' }, null)
      );
      Assert.areEqual('You cannot delete Accounts here', refusal(engine, 'remove', null, stored.Id));
    }

    Assert.areEqual('Acme', reread(stored.Id).Name);
    Assert.areEqual(1, [SELECT COUNT() FROM Account]);
  }

  @IsTest
  static void aFieldTheUserCannotSeeIsLeftOutOfTablesFormsRulesAndText() {
    User editor = userWith(
      new ObjectPermissions(PermissionsRead = true, PermissionsCreate = true, PermissionsEdit = true),
      new Map<String, Boolean>{ 'Industry' => true, 'Rating' => false }
    );
    Account stored = acme();

    System.runAs(editor) {
      ReformEngine engine = engine();

      ReformView.Table listed = engine.table(10, 0);
      Assert.areEqual('Energy', listed.rows[0].get('Industry'));
      Assert.isFalse(listed.rows[0].containsKey('AnnualRevenue'), 'the hidden column carries no values');
      Assert.areEqual(new List<String>{ 'You cannot see AnnualRevenue' }, listed.columns[2].problems);
      Assert.isNull(listed.columns[2].dataType);
      Assert.isTrue(listed.canCreate && listed.canEdit);
      Assert.isFalse(listed.canDelete);

      ReformView.Form shown = engine.form(new Map<String, Object>{ 'Id' => stored.Id }, false);
      Assert.isFalse(named(shown, 'AnnualRevenue').visible, 'the hidden field is not drawn');
      Assert.isNull(named(shown, 'AnnualRevenue').value, 'and its value is not sent');
      Assert.isFalse(ofKind(shown, 'HEADING').visible, 'a rule that reads it cannot give it away');
      Assert.areEqual('Revenue: ', ofKind(shown, 'RICH_TEXT').content, 'nor can text that merges it');
      Assert.areEqual('Hot', named(shown, 'Rating').value);
      Assert.isTrue(named(shown, 'Rating').readOnly, 'a field the user may read but not change');
      Assert.isFalse(named(shown, 'Industry').readOnly);
    }
  }

  @IsTest
  static void aSaveWritesOnlyTheFieldsTheUserMayChange() {
    User editor = userWith(
      new ObjectPermissions(PermissionsRead = true, PermissionsCreate = true, PermissionsEdit = true),
      new Map<String, Boolean>{ 'Industry' => true, 'Rating' => false }
    );
    Account stored = acme();
    Id createdId;

    System.runAs(editor) {
      ReformEngine engine = engine();

      ReformView.Form saved = engine.form(
        new Map<String, Object>{ 'Id' => stored.Id, 'Industry' => 'Banking', 'Rating' => 'Cold', 'AnnualRevenue' => 1 },
        true
      );
      Assert.isTrue(saved.saved);
      Assert.areEqual('Banking', named(saved, 'Industry').value);

      createdId = engine.form(new Map<String, Object>{ 'Name' => 'Globex', 'Industry' => 'Energy', 'Rating' => 'Cold', 'AnnualRevenue' => 9 }, true)
        .recordId;
    }

    Account edited = reread(stored.Id);
    Assert.areEqual('Banking', edited.Industry, 'the field the user may change');
    Assert.areEqual('Hot', edited.Rating, 'a read-only field keeps its value');
    Assert.areEqual(5000000, edited.AnnualRevenue, 'so does a field the user cannot see');

    Account created = reread(createdId);
    Assert.areEqual('Globex', created.Name);
    Assert.areEqual('Energy', created.Industry);
    Assert.isNull(created.Rating);
    Assert.isNull(created.AnnualRevenue);
  }
}
