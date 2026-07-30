@IsTest
private class ConduitCaseBriefControllerTest {
  @TestSetup
  static void setup() {
    Account account = new Account(Name = 'Northwind Trading');
    insert account;
    insert new Case(
      Subject = 'Users cannot sign in after the release',
      Description = 'Authentication fails for roughly 150 users.',
      Status = 'New',
      Priority = 'High',
      AccountId = account.Id
    );
  }

  private static Id caseId() {
    return [SELECT Id FROM Case LIMIT 1].Id;
  }

  private static ConduitTestDoubles.RecordingClient useRecordingClient() {
    ConduitTestDoubles.RecordingClient stub = new ConduitTestDoubles.RecordingClient();
    ConduitAgentClient.setClient(stub);
    ConduitAgentSettings.agentApiNameOverride = 'Test_Agent';
    return stub;
  }

  @IsTest
  static void generateBriefSendsCaseContextToTheConfiguredAgent() {
    ConduitTestDoubles.RecordingClient stub = useRecordingClient();

    Test.startTest();
    ConduitAgentClient.Reply reply = ConduitCaseBriefController.generateBrief(
      caseId()
    );
    Test.stopTest();

    Assert.areEqual('a reply', reply.message);
    Assert.areEqual(
      'session-1',
      reply.sessionId,
      'The session id must reach the component'
    );
    Assert.areEqual('Test_Agent', stub.agentApiName);
    Assert.isTrue(
      stub.message.contains('Users cannot sign in after the release'),
      'Prompt should carry the case subject'
    );
    Assert.isTrue(
      stub.message.contains('What to do next'),
      'Prompt should carry the brief headings'
    );
  }

  @IsTest
  static void generateBriefAlwaysStartsAFreshSession() {
    ConduitTestDoubles.RecordingClient stub = useRecordingClient();

    Test.startTest();
    ConduitCaseBriefController.generateBrief(caseId());
    Test.stopTest();

    Assert.isNull(
      stub.sessionId,
      'Regenerating must not continue an earlier conversation'
    );
  }

  @IsTest
  static void followUpReusesTheSession() {
    ConduitTestDoubles.RecordingClient stub = useRecordingClient();

    Test.startTest();
    ConduitCaseBriefController.askFollowUp(
      'What is the SLA exposure?',
      'session-1'
    );
    Test.stopTest();

    Assert.areEqual(
      'session-1',
      stub.sessionId,
      'Without the session id the agent loses the case'
    );
    Assert.areEqual('What is the SLA exposure?', stub.message);
  }

  @IsTest
  static void followUpWithoutSessionIsRejected() {
    ConduitTestDoubles.RecordingClient stub = useRecordingClient();

    Test.startTest();
    try {
      ConduitCaseBriefController.askFollowUp('What is the SLA exposure?', null);
      Assert.fail('Expected an AuraHandledException');
    } catch (AuraHandledException expected) {
      // Expected. The message is not asserted: AuraHandledException reports differently
      // under test than at runtime.
    }
    Test.stopTest();

    Assert.areEqual(
      0,
      stub.calls,
      'Must not reach the agent without a session'
    );
  }

  @IsTest
  static void agentFailureReachesTheComponentAsAuraHandled() {
    ConduitAgentClient.setClient(new ConduitTestDoubles.ThrowingClient());
    ConduitAgentSettings.agentApiNameOverride = 'Test_Agent';

    Test.startTest();
    try {
      ConduitCaseBriefController.generateBrief(caseId());
      Assert.fail('Expected an AuraHandledException');
    } catch (AuraHandledException expected) {
      // Expected.
    }
    Test.stopTest();
  }
}
