/**
 * What the conduitCaseBrief component calls.
 *
 * Note there is no `cacheable=true` anywhere in this class, and that is not an oversight.
 * These calls are not idempotent: each one opens or continues an agent session and consumes
 * usage. Marked cacheable, Lightning would hand back a stale brief and the follow-up
 * conversation would silently stop working.
 */
public with sharing class ConduitCaseBriefController {
  private static final String USE_CASE = 'Case_Brief';

  /**
   * Produce a fresh brief for a case. Starts a new agent session every time, so the
   * follow-up thread always matches the brief on screen.
   */
  @AuraEnabled
  public static ConduitAgentClient.Reply generateBrief(Id caseId) {
    try {
      String agent = ConduitAgentSettings.agentApiNameFor(USE_CASE);
      ConduitContext context = ConduitCaseContext.build(caseId);
      String prompt = ConduitPrompt.caseBrief(context).build();
      return ConduitAgentClient.send(agent, prompt, null);
    } catch (ConduitAgentClient.ConduitException known) {
      // Deliberately ahead of the generic handler. These messages are written to be
      // read by an admin and say what to go and fix.
      throw new AuraHandledException(known.getMessage());
    } catch (Exception unexpected) {
      throw new AuraHandledException(
        'The brief could not be generated: ' + unexpected.getMessage()
      );
    }
  }

  /**
   * Ask a follow-up against the session the brief opened. Passing the session id back is
   * the entire mechanism by which the agent remembers the case it just summarized, so a
   * blank one here means the agent answers with no context at all.
   */
  @AuraEnabled
  public static ConduitAgentClient.Reply askFollowUp(
    String question,
    String sessionId
  ) {
    try {
      if (String.isBlank(sessionId)) {
        throw new ConduitAgentClient.ConduitException(
          'Generate a brief before asking a follow-up question.'
        );
      }
      String agent = ConduitAgentSettings.agentApiNameFor(USE_CASE);
      return ConduitAgentClient.send(agent, question, sessionId);
    } catch (ConduitAgentClient.ConduitException known) {
      throw new AuraHandledException(known.getMessage());
    } catch (Exception unexpected) {
      throw new AuraHandledException(
        'The question could not be answered: ' + unexpected.getMessage()
      );
    }
  }
}
