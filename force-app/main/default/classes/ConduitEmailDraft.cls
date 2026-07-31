/**
 * Saves a customer reply as an unsent draft email on the case.
 *
 * This class deliberately cannot send. It creates an EmailMessage with Status = '5' (draft),
 * which lands in the case feed for a human to review, edit and send. An agent that can email
 * customers unattended is a materially different risk than one that leaves a draft, and
 * nothing about summarizing a case justifies the former.
 *
 * The recipient is resolved here from the case contact. The agent supplies subject and body
 * only, and never chooses who receives the mail.
 */
public with sharing class ConduitEmailDraft {
  public class Request {
    @InvocableVariable(
      label='Case Id'
      description='Record id of the case to attach the draft to.'
      required=true
    )
    public String caseId;

    @InvocableVariable(label='Subject' description='Subject line of the reply.')
    public String emailSubject;

    @InvocableVariable(label='Body' description='Body of the reply.')
    public String emailBody;

    @InvocableVariable(
      label='Apply'
      description='False to check the recipient without writing. True to save the draft.'
    )
    public Boolean apply = false;
  }

  public class Result {
    @InvocableVariable(
      label='To'
      description='Recipient resolved from the case contact, never supplied by the agent.'
    )
    public String toAddress = '';

    @InvocableVariable(
      label='Saved As'
      description='What happened, and where the engineer can find the draft.'
    )
    public String savedAs = '';

    @InvocableVariable(label='Saved' description='True only when a draft was created.')
    public Boolean saved = false;
  }

  @InvocableMethod(
    label='Save Draft Reply'
    description='Saves a reply as an unsent draft email on the case. Never sends.'
  )
  public static List<Result> save(List<Request> requests) {
    List<Result> results = new List<Result>();
    for (Request req : requests) {
      results.add(saveOne(req));
    }
    return results;
  }

  private static Result saveOne(Request req) {
    Result out = new Result();

    if (req == null || String.isBlank(req.caseId)) {
      out.savedAs = 'No case id was supplied, so no draft was saved.';
      return out;
    }
    // Only the real save needs text. The precheck runs before the reply is composed, and its
    // whole job is to establish whether composing one is worth the engineer's time.
    if (req.apply == true && (String.isBlank(req.emailSubject) || String.isBlank(req.emailBody))) {
      out.savedAs = 'The reply needs both a subject and a body. Nothing was saved.';
      return out;
    }

    List<Case> found = [
      SELECT Id, CaseNumber, ContactId, Contact.Email, Contact.Name, SuppliedEmail
      FROM Case
      WHERE Id = :req.caseId
      WITH USER_MODE
      LIMIT 1
    ];

    if (found.isEmpty()) {
      out.savedAs = 'That case could not be read, so no draft was saved.';
      return out;
    }

    Case record = found[0];

    // Contact email first, then the address the case was submitted from. If neither exists
    // there is nobody to reply to, and an orphan draft would just be litter in the feed.
    String recipient = record.Contact?.Email;
    if (String.isBlank(recipient)) {
      recipient = record.SuppliedEmail;
    }
    if (String.isBlank(recipient)) {
      out.savedAs =
        'Case ' +
        record.CaseNumber +
        ' has no contact email and no supplied email, so there is no one to reply to. ' +
        'Add a contact with an email address before drafting a reply. Nothing was saved.';
      return out;
    }

    // Precheck: the recipient resolves, so a reply is worth composing. Write nothing yet.
    if (req.apply != true) {
      out.toAddress = recipient;
      out.savedAs =
        'Ready to draft. A reply on case ' +
        record.CaseNumber +
        ' would be addressed to ' +
        recipient +
        '. Nothing has been saved yet.';
      return out;
    }

    EmailMessage draft = new EmailMessage(
      ParentId = record.Id,
      Subject = req.emailSubject,
      TextBody = req.emailBody,
      ToAddress = recipient,
      Incoming = false,
      Status = '5' // Draft. Anything else would make this look like it was actually sent.
    );

    try {
      insert as user draft;
    } catch (DmlException failure) {
      out.savedAs = 'The draft was rejected: ' + failure.getDmlMessage(0);
      return out;
    }

    out.saved = true;
    out.toAddress = recipient;
    out.savedAs =
      'Draft saved to case ' +
      record.CaseNumber +
      ' addressed to ' +
      recipient +
      '. It has NOT been sent. Open the case feed to review and send it.';
    return out;
  }
}
