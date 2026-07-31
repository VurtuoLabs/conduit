/**
 * Resolves the case the engineer is currently looking at.
 *
 * Agent Script has no linked-variable source for the current Lightning record. The only
 * documented sources are `@MessagingSession`, `@MessagingEndUser` and `@VoiceCall`, all of
 * which are service-agent constructs that an employee agent does not have. So an agent
 * opened from the Agentforce panel on a case record cannot be told which record that is.
 *
 * `LastViewedDate` closes the gap. It is maintained per user, so the most recently viewed
 * case for the running user is, in practice, the one whose page they are sitting on while
 * they type.
 *
 * This is a heuristic, and it is treated as one. It can be wrong if the engineer opened
 * another case moments earlier, so the agent is required to state which case it resolved and
 * invite a correction. Everything it enables is read-only until the engineer confirms a
 * write, and every write names the case number first.
 */
public with sharing class ConduitCurrentCase {
  public class Request {
    // An invocable action needs at least one input to bind against. This one exists so the
    // agent has something to send; the answer depends only on who is running.
    @InvocableVariable(
      label='Unused'
      description='Not used. The result depends only on the running user.'
    )
    public String ignored;
  }

  public class Result {
    @InvocableVariable(
      label='Found'
      description='True when a recently viewed case was resolved.'
    )
    public Boolean found = false;

    @InvocableVariable(
      label='Case Id'
      description='Record id of the resolved case.'
    )
    public String caseId = '';

    @InvocableVariable(
      label='Case Number'
      description='Human readable case number.'
    )
    public String caseNumber = '';

    @InvocableVariable(label='Subject' description='Case subject.')
    public String subject = '';

    @InvocableVariable(label='Status' description='Current case status.')
    public String status = '';

    @InvocableVariable(label='Priority' description='Current case priority.')
    public String priority = '';

    @InvocableVariable(
      label='Summary'
      description='Which case was resolved and how, or why none could be.'
    )
    public String summary = '';
  }

  @InvocableMethod(
    label='Get Current Case'
    description='Resolves the case the running user most recently viewed, for when they say "this case" without naming one.'
  )
  public static List<Result> current(List<Request> requests) {
    // The answer is the same for every element, so resolve once and fan it out rather than
    // running the same query per request.
    Result resolved = resolve();
    List<Result> results = new List<Result>();
    Integer count = requests == null || requests.isEmpty()
      ? 1
      : requests.size();
    for (Integer i = 0; i < count; i++) {
      results.add(resolved);
    }
    return results;
  }

  private static Result resolve() {
    Result out = new Result();

    // LastViewedDate is per running user, so this needs no explicit user filter.
    List<Case> recent = [
      SELECT Id, CaseNumber, Subject, Status, Priority, LastViewedDate
      FROM Case
      WHERE LastViewedDate != NULL
      WITH USER_MODE
      ORDER BY LastViewedDate DESC
      LIMIT 1
    ];

    if (recent.isEmpty()) {
      out.summary =
        'You have not opened a case recently, so there is nothing to work from. ' +
        'Tell me a case number instead.';
      return out;
    }

    Case record = recent[0];
    out.found = true;
    out.caseId = record.Id;
    out.caseNumber = record.CaseNumber;
    out.subject = record.Subject == null ? '(no subject)' : record.Subject;
    out.status = record.Status;
    out.priority = record.Priority;
    out.summary =
      'The case you most recently opened is ' +
      record.CaseNumber +
      ', ' +
      out.subject +
      ', currently ' +
      record.Status +
      ' at ' +
      record.Priority +
      ' priority.';
    return out;
  }
}
