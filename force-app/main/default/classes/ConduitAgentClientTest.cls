/**
 * The live agent call cannot be mocked, so PlatformClient is not exercised here. What is
 * tested is the guard rails around it and the contract the stub seam has to honour.
 */
@IsTest
private class ConduitAgentClientTest {
  /** Records what it was handed, so tests can assert on the call rather than the answer. */
  public class RecordingClient implements ConduitAgentClient.Client {
    public String agentApiName;
    public String message;
    public String sessionId;
    public Integer calls = 0;

    public ConduitAgentClient.Reply send(
      String agentApiName,
      String message,
      String sessionId
    ) {
      this.agentApiName = agentApiName;
      this.message = message;
      this.sessionId = sessionId;
      this.calls++;
      return new ConduitAgentClient.Reply('a reply', 'session-1');
    }
  }

  public class ThrowingClient implements ConduitAgentClient.Client {
    public ConduitAgentClient.Reply send(
      String agentApiName,
      String message,
      String sessionId
    ) {
      throw new ConduitAgentClient.ConduitException('agent is inactive');
    }
  }

  @IsTest
  static void passesArgumentsStraightThrough() {
    RecordingClient stub = new RecordingClient();
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
    RecordingClient stub = new RecordingClient();
    ConduitAgentClient.setClient(stub);

    ConduitAgentClient.send('My_Agent', 'hello', null);

    Assert.isNull(stub.sessionId, 'A first turn must not invent a session id');
  }

  @IsTest
  static void rejectsBlankAgentName() {
    RecordingClient stub = new RecordingClient();
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
    RecordingClient stub = new RecordingClient();
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
    ConduitAgentClient.setClient(new ThrowingClient());

    try {
      ConduitAgentClient.send('My_Agent', 'hello', null);
      Assert.fail('Expected a ConduitException');
    } catch (ConduitAgentClient.ConduitException expected) {
      Assert.areEqual('agent is inactive', expected.getMessage());
    }
  }
}
