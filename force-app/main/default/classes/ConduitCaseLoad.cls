/**
 * Resolves whatever the engineer typed into the one case the agent will work on.
 *
 * Accepts a CaseNumber ("00001234") or a 15/18 character record id, because engineers paste
 * both and making the agent guess which it received is a needless failure mode.
 *
 * Returns found = False rather than throwing when nothing matches. A thrown exception ends
 * the agent turn with a generic error; a False flag lets the agent say "I could not find
 * that case" and ask again, which is the behavior the conversation actually needs.
 */
public with sharing class ConduitCaseLoad {
  public class Request {
    @InvocableVariable(
      label='Case Reference'
      description='A case number such as 00001234, or a 15 or 18 character case record id.'
      required=true
    )
    public String caseRef;
  }

  public class Result {
    @InvocableVariable(
      label='Found'
      description='True when a case matched and the running user can read it.'
    )
    public Boolean found = false;

    @InvocableVariable(label='Case Id' description='Record id of the matched case.')
    public String caseId = '';

    @InvocableVariable(label='Case Number' description='Human readable case number.')
    public String caseNumber = '';

    @InvocableVariable(label='Subject' description='Case subject.')
    public String subject = '';

    @InvocableVariable(label='Status' description='Current case status.')
    public String status = '';

    @InvocableVariable(label='Priority' description='Current case priority.')
    public String priority = '';

    @InvocableVariable(
      label='Summary'
      description='Headline description of the case, or the reason it could not be loaded.'
    )
    public String summary = '';
  }

  @InvocableMethod(
    label='Load Case'
    description='Resolves a case number or record id into a case and returns its headline fields.'
  )
  public static List<Result> load(List<Request> requests) {
    List<Result> results = new List<Result>();
    for (Request req : requests) {
      results.add(loadOne(req == null ? null : req.caseRef));
    }
    return results;
  }

  private static Result loadOne(String caseRef) {
    Result out = new Result();

    if (String.isBlank(caseRef)) {
      out.summary = 'No case reference was supplied.';
      return out;
    }

    String reference = caseRef.trim();
    List<Case> found = looksLikeId(reference) ? byId(reference) : byNumber(reference);

    // An engineer can paste a number that happens to parse as neither. Try the other path
    // before giving up, so a stray leading apostrophe or a 15-char number still resolves.
    if (found.isEmpty()) {
      found = looksLikeId(reference) ? byNumber(reference) : byId(reference);
    }

    if (found.isEmpty()) {
      out.summary =
        'No case matching "' +
        reference +
        '" was found, or you do not have access to it.';
      return out;
    }

    Case record = found[0];
    out.found = true;
    out.caseId = record.Id;
    out.caseNumber = record.CaseNumber;
    out.subject = record.Subject == null ? '(no subject)' : record.Subject;
    out.status = record.Status;
    out.priority = record.Priority;
    out.summary =
      'Case ' +
      record.CaseNumber +
      ', ' +
      out.subject +
      ', is ' +
      record.Status +
      ' at ' +
      record.Priority +
      ' priority' +
      (record.IsEscalated == true ? ' and is escalated.' : '.');
    return out;
  }

  /** A 15 or 18 character alphanumeric token is an id; anything else is treated as a number. */
  private static Boolean looksLikeId(String reference) {
    return (reference.length() == 15 || reference.length() == 18) &&
      Pattern.matches('^[a-zA-Z0-9]+$', reference);
  }

  private static List<Case> byId(String reference) {
    try {
      Id caseId = Id.valueOf(reference);
      return [
        SELECT Id, CaseNumber, Subject, Status, Priority, IsEscalated
        FROM Case
        WHERE Id = :caseId
        WITH USER_MODE
        LIMIT 1
      ];
    } catch (System.StringException badId) {
      // Not a valid id after all. The caller falls back to a case-number lookup.
      return new List<Case>();
    }
  }

  private static List<Case> byNumber(String reference) {
    // Case numbers are stored zero-padded. Engineers rarely type the padding, so match on
    // the padded form as well as what they typed.
    String padded = reference.leftPad(8, '0');
    return [
      SELECT Id, CaseNumber, Subject, Status, Priority, IsEscalated
      FROM Case
      WHERE CaseNumber = :reference OR CaseNumber = :padded
      WITH USER_MODE
      ORDER BY CreatedDate DESC
      LIMIT 1
    ];
  }
}
