/**
 * The live agent call cannot be mocked, so PlatformClient is not exercised here. What is
 * tested is the guard rails around it and the contract the stub seam has to honour.
 */
@IsTest
private class ConduitAgentClientTest {
  // The doubles live in ConduitTestDoubles so ConduitCaseBriefControllerTest can use them
  // too. Inner classes of a private test class are not visible outside it.

  @IsTest
  static void passesArgumentsStraightThrough() {
    ConduitTestDoubles.RecordingClient stub = new ConduitTestDoubles.RecordingClient();
    ConduitAgentClient.setClient(stub);

    ConduitAgentClient.Reply reply = ConduitAgentClient.send(
      'My_Agent',
      'hello',
      'session-0'
    );

    Assert.areEqual('My_Agent', stub.agentApiName);
    Assert.areEqual('hello', stub.message);
    Assert.areEqual('session-0', stub.sessionId);
    Assert.areEqual('a reply', reply.message);
    Assert.areEqual('session-1', reply.sessionId);
  }

  @IsTest
  static void allowsNullSessionForFirstTurn() {
    ConduitTestDoubles.RecordingClient stub = new ConduitTestDoubles.RecordingClient();
    ConduitAgentClient.setClient(stub);

    ConduitAgentClient.send('My_Agent', 'hello', null);

    Assert.isNull(stub.sessionId, 'A first turn must not invent a session id');
  }

  @IsTest
  static void rejectsBlankAgentName() {
    ConduitTestDoubles.RecordingClient stub = new ConduitTestDoubles.RecordingClient();
    ConduitAgentClient.setClient(stub);

    try {
      ConduitAgentClient.send('   ', 'hello', null);
      Assert.fail('Expected a ConduitException');
    } catch (ConduitAgentClient.ConduitException expected) {
      Assert.isTrue(
        expected.getMessage().contains('Conduit_Agent__mdt'),
        'Error should point at the config record'
      );
    }
    Assert.areEqual(
      0,
      stub.calls,
      'Must not reach the agent with no agent name'
    );
  }

  @IsTest
  static void rejectsBlankMessage() {
    ConduitTestDoubles.RecordingClient stub = new ConduitTestDoubles.RecordingClient();
    ConduitAgentClient.setClient(stub);

    try {
      ConduitAgentClient.send('My_Agent', '', null);
      Assert.fail('Expected a ConduitException');
    } catch (ConduitAgentClient.ConduitException expected) {
      Assert.isTrue(expected.getMessage().contains('empty message'));
    }
    Assert.areEqual(
      0,
      stub.calls,
      'Must not spend an agent call on an empty message'
    );
  }

  @IsTest
  static void surfacesClientFailures() {
    ConduitAgentClient.setClient(new ConduitTestDoubles.ThrowingClient());

    try {
      ConduitAgentClient.send('My_Agent', 'hello', null);
      Assert.fail('Expected a ConduitException');
    } catch (ConduitAgentClient.ConduitException expected) {
      Assert.areEqual('agent is inactive', expected.getMessage());
    }
  }
}
