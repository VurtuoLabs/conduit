/**
 * Finds previously closed cases that resemble the one in hand, and what resolved them.
 *
 * Matching is keyword-based on the subject via SOSL, narrowed to closed cases. It is not
 * semantic search and does not pretend to be: the agent is told to report what came back and
 * say plainly when nothing did, rather than reason about similarity it cannot measure.
 *
 * Results are returned as preformatted lines rather than a list of objects. Same reason as
 * ConduitCaseDetail: it avoids complex_data_type_name mapping, and the agent reads it as text.
 */
public with sharing class ConduitSimilarCases {
  private static final Integer MAX_MATCHES = 5;
  private static final Integer RESOLUTION_CHARS = 300;
  /** Words too common in support subjects to discriminate between cases. */
  private static final Set<String> NOISE = new Set<String>{
    'the', 'and', 'for', 'with', 'from', 'this', 'that', 'have', 'has', 'not',
    'can', 'cant', 'unable', 'issue', 'problem', 'error', 'help', 'please',
    'case', 'support', 'when', 'after', 'about', 'need', 'does', 'doesnt'
  };

  public class Request {
    @InvocableVariable(
      label='Case Id'
      description='Record id of the case to find precedent for.'
      required=true
    )
    public String caseId;
  }

  public class Result {
    @InvocableVariable(
      label='Match Summary'
      description='How many closed cases matched, or that none did.'
    )
    public String matchSummary = '';

    @InvocableVariable(
      label='Matches'
      description='One closed case per line with its number, subject, close date and resolution.'
    )
    public String matches = '';

    @InvocableVariable(label='Has Matches' description='True when at least one case matched.')
    public Boolean hasMatches = false;
  }

  @InvocableMethod(
    label='Find Similar Cases'
    description='Finds previously closed cases with similar subjects and how each was resolved.'
  )
  public static List<Result> find(List<Request> requests) {
    List<Result> results = new List<Result>();
    for (Request req : requests) {
      results.add(findOne(req == null ? null : req.caseId));
    }
    return results;
  }

  private static Result findOne(String caseIdText) {
    Result out = new Result();

    if (String.isBlank(caseIdText)) {
      out.matchSummary = 'No case id was supplied.';
      return out;
    }

    List<Case> found = [
      SELECT Id, Subject, Type
      FROM Case
      WHERE Id = :caseIdText
      WITH USER_MODE
      LIMIT 1
    ];

    if (found.isEmpty()) {
      out.matchSummary = 'That case could not be read, so no comparison was possible.';
      return out;
    }

    Case current = found[0];
    List<String> terms = keywords(current.Subject);

    if (terms.isEmpty()) {
      out.matchSummary =
        'The case subject has no distinctive words to search on, so no comparison was possible.';
      return out;
    }

    List<Case> candidates = search(terms, current.Id);

    if (candidates.isEmpty()) {
      out.matchSummary = 'No closed cases were found with a similar subject.';
      return out;
    }

    List<String> lines = new List<String>();
    for (Case match : candidates) {
      lines.add(
        match.CaseNumber +
          ' | ' +
          blankTo(match.Subject, '(no subject)') +
          ' | closed ' +
          (match.ClosedDate == null
            ? 'date not recorded'
            : match.ClosedDate.format('yyyy-MM-dd')) +
          ' | resolution: ' +
          resolutionOf(match)
      );
    }

    out.hasMatches = true;
    out.matches = String.join(lines, '\n');
    out.matchSummary =
      String.valueOf(candidates.size()) +
      ' closed case' +
      (candidates.size() == 1 ? '' : 's') +
      ' with a similar subject.';
    return out;
  }

  /**
   * SOSL rather than SOQL LIKE: it tokenizes the subject and matches any term, which is what
   * finds "cannot authenticate" from a case titled "login failure after deploy".
   */
  private static List<Case> search(List<String> terms, Id excludeId) {
    String query = String.join(terms, ' OR ');
    List<List<SObject>> hits = Search.query(
      'FIND {' +
        String.escapeSingleQuotes(query) +
        '} IN NAME FIELDS RETURNING Case(Id, CaseNumber, Subject, Reason, Description, ClosedDate ' +
        'WHERE IsClosed = true AND Id != \'' +
        excludeId +
        '\' ORDER BY ClosedDate DESC LIMIT ' +
        MAX_MATCHES +
        ')',
      AccessLevel.USER_MODE
    );
    return hits.isEmpty() ? new List<Case>() : (List<Case>) hits[0];
  }

  /**
   * There is no standard resolution field on Case. Reason is the closest structured signal;
   * fall back to the description so the engineer gets something rather than a blank column.
   */
  private static String resolutionOf(Case match) {
    if (String.isNotBlank(match.Reason)) {
      return match.Reason;
    }
    if (String.isNotBlank(match.Description)) {
      String flat = match.Description.trim().replaceAll('\\s+', ' ');
      return flat.length() <= RESOLUTION_CHARS
        ? flat
        : flat.left(RESOLUTION_CHARS) + ' [truncated]';
    }
    return 'not recorded';
  }

  /** Distinctive words from the subject, longest first, capped to keep the SOSL sane. */
  private static List<String> keywords(String subject) {
    List<String> picked = new List<String>();
    if (String.isBlank(subject)) {
      return picked;
    }
    Set<String> seen = new Set<String>();
    for (String raw : subject.toLowerCase().split('[^a-z0-9]+')) {
      String word = raw.trim();
      if (word.length() < 4 || NOISE.contains(word) || seen.contains(word)) {
        continue;
      }
      seen.add(word);
      picked.add(word);
      if (picked.size() == 6) {
        break;
      }
    }
    return picked;
  }

  private static String blankTo(String value, String fallback) {
    return String.isBlank(value) ? fallback : value;
  }
}
