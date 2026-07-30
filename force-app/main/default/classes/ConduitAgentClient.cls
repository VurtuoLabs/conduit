/**
 * Sends a message to an Agentforce agent and returns what came back.
 *
 * This is the only class in Conduit that touches the agent. Everything else builds the
 * message or renders the reply, which is what keeps the rest of the package unit testable:
 * tests swap in a stub through `setClient` and never reach the live service.
 *
 * The underlying platform surface is the `generateAiAgentResponse` invocable action,
 * reached through `Invocable.Action.createCustomAction`. It requires API version 64.0 or
 * later on this class. Lowering the version in ConduitAgentClient.cls-meta.xml makes the
 * action unresolvable, and the resulting error does not mention the API version.
 */
public with sharing class ConduitAgentClient {
  private static final String AGENT_ACTION = 'generateAiAgentResponse';

  public class ConduitException extends Exception {
  }

  /**
   * One exchange with an agent. `sessionId` is what makes the next turn stateful, so
   * callers that support follow-up questions must hold on to it.
   */
  public class Reply {
    @AuraEnabled
    public String message { get; set; }

    @AuraEnabled
    public String sessionId { get; set; }

    public Reply(String message, String sessionId) {
      this.message = message;
      this.sessionId = sessionId;
    }
  }

  /** Seam that lets tests replace the live call. */
  public interface Client {
    Reply send(String agentApiName, String message, String sessionId);
  }

  @TestVisible
  private static Client client = new PlatformClient();

  /** Test-only. Redirects every send through a stub. */
  @TestVisible
  private static void setClient(Client replacement) {
    client = replacement;
  }

  /**
   * Send a message to an agent.
   *
   * @param agentApiName Agent API Name exactly as it appears in Agent Builder. This is
   *                     usually not the display label and often carries a numeric suffix.
   * @param message      The full prompt, context included.
   * @param sessionId    Null on the first turn. On later turns, the value returned by the
   *                     previous Reply, which is what gives the agent conversation memory.
   */
  public static Reply send(
    String agentApiName,
    String message,
    String sessionId
  ) {
    if (String.isBlank(agentApiName)) {
      throw new ConduitException(
        'No agent API name was supplied. Check the Conduit_Agent__mdt record for this use case.'
      );
    }
    if (String.isBlank(message)) {
      throw new ConduitException('Cannot send an empty message to an agent.');
    }
    return client.send(agentApiName, message, sessionId);
  }

  /** The real call. Everything here is untestable by definition, so it stays thin. */
  public class PlatformClient implements Client {
    public Reply send(String agentApiName, String message, String sessionId) {
      Invocable.Action action = Invocable.Action.createCustomAction(
        AGENT_ACTION,
        agentApiName
      );
      action.setInvocationParameter('userMessage', message);
      if (String.isNotBlank(sessionId)) {
        action.setInvocationParameter('sessionId', sessionId);
      }

      List<Invocable.Action.Result> results = action.invoke();
      if (results == null || results.isEmpty()) {
        throw new ConduitException(
          'Agent "' + agentApiName + '" returned no result.'
        );
      }

      Invocable.Action.Result result = results[0];
      if (!result.isSuccess()) {
        throw new ConduitException(describeFailure(result, agentApiName));
      }

      Map<String, Object> output = result.getOutputParameters();
      String reply = (String) output.get('agentResponse');
      String returnedSession = (String) output.get('sessionId');

      // A successful call with no text is the normal symptom of an agent whose topics
      // do not cover the request. Without this guard the caller renders an empty box
      // and there is nothing to diagnose from.
      if (String.isBlank(reply)) {
        throw new ConduitException(
          'Agent "' +
            agentApiName +
            '" accepted the request but returned no content. ' +
            'Confirm the agent has a topic that covers this kind of request.'
        );
      }

      return new Reply(reply, returnedSession);
    }

    private String describeFailure(
      Invocable.Action.Result result,
      String agentApiName
    ) {
      List<String> parts = new List<String>();
      for (Invocable.Action.Error err : result.getErrors()) {
        parts.add(err.getCode() + ': ' + err.getMessage());
      }
      return parts.isEmpty()
        ? 'Agent "' + agentApiName + '" failed without reporting a reason.'
        : 'Agent "' + agentApiName + '" failed. ' + String.join(parts, ' | ');
    }
  }
}
