/**
 * Shared stand-ins for the live agent call.
 *
 * These live in their own class rather than inside a test class on purpose. Inner classes of
 * a `private` test class are not visible to other test classes, so keeping them here is what
 * lets both ConduitAgentClientTest and ConduitCaseBriefControllerTest use the same doubles.
 */
@IsTest
public class ConduitTestDoubles {
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

  /** Fails the way an inactive or unreachable agent does. */
  public class ThrowingClient implements ConduitAgentClient.Client {
    public ConduitAgentClient.Reply send(
      String agentApiName,
      String message,
      String sessionId
    ) {
      throw new ConduitAgentClient.ConduitException('agent is inactive');
    }
  }

  /** Installs a recording double and returns it. */
  public static RecordingClient useRecording() {
    RecordingClient stub = new RecordingClient();
    ConduitAgentClient.setClient(stub);
    return stub;
  }
}
