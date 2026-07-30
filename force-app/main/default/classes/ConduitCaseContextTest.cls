@IsTest
private class ConduitCaseContextTest {
  @TestSetup
  static void setup() {
    Account account = new Account(
      Name = 'Northwind Trading',
      Industry = 'Manufacturing'
    );
    insert account;

    Contact contact = new Contact(
      FirstName = 'Dana',
      LastName = 'Okafor',
      Email = 'dana@example.com',
      AccountId = account.Id
    );
    insert contact;

    Case supportCase = new Case(
      Subject = 'Users cannot sign in after the release',
      Description = 'Authentication fails for roughly 150 users since the Friday deploy.',
      Status = 'New',
      Priority = 'High',
      Origin = 'Email',
      AccountId = account.Id,
      ContactId = contact.Id
    );
    insert supportCase;

    insert new CaseComment(
      ParentId = supportCase.Id,
      CommentBody = 'Reproduced in the sandbox.'
    );
    insert new Task(
      WhatId = supportCase.Id,
      Subject = 'Escalate to platform team',
      Status = 'Open'
    );
  }

  private static Case theCase() {
    return [SELECT Id FROM Case LIMIT 1];
  }

  @IsTest
  static void collectsCaseAccountAndContact() {
    Map<String, Object> context = ConduitCaseContext.build(theCase().Id)
      .toMap();

    Assert.areEqual(
      'Users cannot sign in after the release',
      context.get('subject')
    );
    Assert.areEqual('High', context.get('priority'));
    Assert.areEqual('New', context.get('status'));

    Map<String, Object> account = (Map<String, Object>) context.get('account');
    Assert.areEqual('Northwind Trading', account.get('name'));

    Map<String, Object> contact = (Map<String, Object>) context.get('contact');
    Assert.areEqual('Dana Okafor', contact.get('name'));
  }

  @IsTest
  static void collectsChildRecords() {
    Map<String, Object> context = ConduitCaseContext.build(theCase().Id)
      .toMap();

    List<Object> comments = (List<Object>) context.get('comments');
    Assert.areEqual(1, comments.size());

    List<Object> tasks = (List<Object>) context.get('openTasks');
    Assert.areEqual(1, tasks.size(), 'Open tasks should be collected');
  }

  @IsTest
  static void omitsChildCollectionsThatAreEmpty() {
    Map<String, Object> context = ConduitCaseContext.build(theCase().Id)
      .toMap();

    Assert.isFalse(
      context.containsKey('emails'),
      'An empty collection should be dropped rather than sent to the agent as an empty list'
    );
  }

  @IsTest
  static void serializesToJson() {
    String json = ConduitCaseContext.build(theCase().Id).toJson();

    Assert.isTrue(json.contains('Northwind Trading'));
    Assert.isTrue(
      json.startsWith('{'),
      'Context must serialize as a JSON object'
    );
  }

  @IsTest
  static void rejectsUnreadableCase() {
    // A case id that is syntactically valid but matches no record the user can read.
    Id missing =
      Case.SObjectType.getDescribe().getKeyPrefix() + '000000000000AAA';
    try {
      ConduitCaseContext.build(missing);
      Assert.fail('Expected a ConduitException');
    } catch (ConduitAgentClient.ConduitException expected) {
      Assert.isTrue(expected.getMessage().contains('could not be read'));
    }
  }

  /**
   * The check that matters most in this class. Data the running user is not allowed to see
   * must never reach the agent, because the agent reads it straight back to them.
   *
   * USER_MODE enforces at two levels and the failure shapes differ, so both are asserted.
   * On a stock org the minimum-access profile has no Case read at all, which takes the
   * first branch: the query is refused outright rather than quietly returning rows.
   */
  @IsTest
  static void enforcesObjectAndFieldSecurityForTheRunningUser() {
    User restricted = minimumAccessUser();
    Id caseId = theCase().Id;

    System.runAs(restricted) {
      if (!Schema.SObjectType.Case.isAccessible()) {
        try {
          ConduitCaseContext.build(caseId);
          Assert.fail(
            'A user with no Case access must not receive case context'
          );
        } catch (Exception refused) {
          Assert.isTrue(
            refused instanceof QueryException ||
            refused instanceof ConduitAgentClient.ConduitException,
            'Expected the query to be refused, got ' + refused.getTypeName()
          );
        }
        return;
      }

      if (Schema.SObjectType.Case.fields.Description.isAccessible()) {
        // This user can read the field, so there is nothing for USER_MODE to strip.
        return;
      }

      Map<String, Object> context = ConduitCaseContext.build(caseId).toMap();
      Assert.isFalse(
        context.containsKey('description'),
        'USER_MODE must strip a field this user cannot read'
      );
    }
  }

  private static User minimumAccessUser() {
    Profile profile = [
      SELECT Id
      FROM Profile
      WHERE Name = 'Minimum Access - Salesforce'
      LIMIT 1
    ];
    User user = new User(
      Alias = 'cndt',
      Email = 'conduit.test@example.com',
      EmailEncodingKey = 'UTF-8',
      LastName = 'Tester',
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_US',
      ProfileId = profile.Id,
      TimeZoneSidKey = 'America/New_York',
      Username = 'conduit.test.' + DateTime.now().getTime() + '@example.com'
    );
    insert user;
    return user;
  }
}
