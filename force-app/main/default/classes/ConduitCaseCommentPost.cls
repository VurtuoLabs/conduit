/**
 * Adds an internal note to a case.
 *
 * Comments are created with IsPublished = false. These are engineer-to-engineer notes, and a
 * note the agent wrote should never default to customer-visible. Customer communication goes
 * through ConduitEmailDraft, where a human reviews it before anything is sent.
 */
public with sharing class ConduitCaseCommentPost {
  private static final Integer EXCERPT_CHARS = 200;

  public class Request {
    @InvocableVariable(
      label='Case Id'
      description='Record id of the case to annotate.'
      required=true
    )
    public String caseId;

    @InvocableVariable(
      label='Note'
      description='The internal note to post to the case.'
      required=true
    )
    public String commentBody;
  }

  public class Result {
    @InvocableVariable(label='Posted At' description='When the note was recorded.')
    public String postedAt = '';

    @InvocableVariable(label='Excerpt' description='The opening of the note, echoed back.')
    public String excerpt = '';

    @InvocableVariable(label='Posted' description='True only when a note was written.')
    public Boolean posted = false;
  }

  @InvocableMethod(
    label='Add Case Note'
    description='Adds an internal, non-public note to a case.'
  )
  public static List<Result> post(List<Request> requests) {
    List<Result> results = new List<Result>();
    for (Request req : requests) {
      results.add(postOne(req));
    }
    return results;
  }

  private static Result postOne(Request req) {
    Result out = new Result();

    if (req == null || String.isBlank(req.caseId)) {
      out.excerpt = 'No case id was supplied, so no note was posted.';
      return out;
    }
    if (req == null || String.isBlank(req.commentBody)) {
      out.excerpt = 'The note was empty, so nothing was posted.';
      return out;
    }

    List<Case> found = [
      SELECT Id, CaseNumber
      FROM Case
      WHERE Id = :req.caseId
      WITH USER_MODE
      LIMIT 1
    ];

    if (found.isEmpty()) {
      out.excerpt = 'That case could not be read, so no note was posted.';
      return out;
    }

    CaseComment comment = new CaseComment(
      ParentId = found[0].Id,
      CommentBody = req.commentBody,
      IsPublished = false
    );

    try {
      insert as user comment;
    } catch (DmlException failure) {
      out.excerpt = 'The note was rejected: ' + failure.getDmlMessage(0);
      return out;
    }

    CaseComment saved = [
      SELECT CreatedDate
      FROM CaseComment
      WHERE Id = :comment.Id
      WITH USER_MODE
      LIMIT 1
    ];

    out.posted = true;
    // formatGmt with an explicit marker. Bare format() renders in the running user's
    // timezone with nothing to say so, and the agent then labels it with a zone it guessed.
    out.postedAt = saved.CreatedDate.formatGmt('yyyy-MM-dd HH:mm') + ' GMT';
    String flat = req.commentBody.trim().replaceAll('\\s+', ' ');
    out.excerpt = flat.length() <= EXCERPT_CHARS
      ? flat
      : flat.left(EXCERPT_CHARS) + ' [truncated]';
    return out;
  }
}
