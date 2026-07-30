/**
 * Gathers a Case and its surrounding records into an agent-ready context.
 *
 * Security note, because this is the class where getting it wrong actually leaks data:
 * every query runs WITH USER_MODE. `with sharing` on the class controls which records the
 * user can see, but it does nothing for field-level security. Without USER_MODE, a user who
 * is blocked from reading Case.Description would still receive it back, summarized, in the
 * agent output. The field would be hidden in the UI and exposed through the AI.
 *
 * Treat any query added here without WITH USER_MODE as a defect.
 */
public with sharing class ConduitCaseContext {
  /** Child records are capped so a long-running case cannot produce an unbounded prompt. */
  private static final Integer CHILD_LIMIT = 10;

  public static ConduitContext build(Id caseId) {
    List<Case> found = [
      SELECT
        Id,
        CaseNumber,
        Subject,
        Description,
        Status,
        Priority,
        Origin,
        Type,
        Reason,
        IsEscalated,
        CreatedDate,
        Owner.Name,
        Contact.Name,
        Contact.Email,
        Contact.Phone,
        Account.Name,
        Account.Industry
      FROM Case
      WHERE Id = :caseId
      WITH USER_MODE
      LIMIT 1
    ];

    if (found.isEmpty()) {
      throw new ConduitAgentClient.ConduitException(
        'That case could not be read. It may not exist, or you may not have access to it.'
      );
    }

    Case record = found[0];

    ConduitContext context = new ConduitContext();
    context.put('caseNumber', record.CaseNumber)
      .put('subject', record.Subject)
      .put('description', record.Description)
      .put('status', record.Status)
      .put('priority', record.Priority)
      .put('origin', record.Origin)
      .put('type', record.Type)
      .put('reason', record.Reason)
      .put('escalated', record.IsEscalated)
      .put('owner', record.Owner?.Name)
      .putDate('openedAt', record.CreatedDate);

    ConduitContext contact = new ConduitContext();
    contact.put('name', record.Contact?.Name)
      .put('email', record.Contact?.Email)
      .put('phone', record.Contact?.Phone);
    context.put('contact', contact.toMap());

    ConduitContext account = new ConduitContext();
    account.put('name', record.Account?.Name)
      .put('industry', record.Account?.Industry);
    context.put('account', account.toMap());

    context.put('comments', comments(caseId));
    context.put('emails', emails(caseId));
    context.put('openTasks', openTasks(caseId));

    return context;
  }

  private static List<Object> comments(Id caseId) {
    List<Object> items = new List<Object>();
    for (CaseComment comment : [
      SELECT CommentBody, CreatedDate, CreatedBy.Name
      FROM CaseComment
      WHERE ParentId = :caseId
      WITH USER_MODE
      ORDER BY CreatedDate DESC
      LIMIT :CHILD_LIMIT
    ]) {
      ConduitContext entry = new ConduitContext();
      entry.put('author', comment.CreatedBy?.Name)
        .put('body', comment.CommentBody)
        .putDate('postedAt', comment.CreatedDate);
      items.add(entry.toMap());
    }
    return items;
  }

  private static List<Object> emails(Id caseId) {
    List<Object> items = new List<Object>();
    for (EmailMessage email : [
      SELECT Subject, TextBody, MessageDate, FromAddress, Incoming
      FROM EmailMessage
      WHERE ParentId = :caseId
      WITH USER_MODE
      ORDER BY MessageDate DESC
      LIMIT :CHILD_LIMIT
    ]) {
      ConduitContext entry = new ConduitContext();
      entry.put('direction', email.Incoming ? 'from customer' : 'to customer')
        .put('from', email.FromAddress)
        .put('subject', email.Subject)
        .put('body', email.TextBody)
        .putDate('sentAt', email.MessageDate);
      items.add(entry.toMap());
    }
    return items;
  }

  private static List<Object> openTasks(Id caseId) {
    List<Object> items = new List<Object>();
    for (Task task : [
      SELECT Subject, Status, ActivityDate, Owner.Name
      FROM Task
      WHERE WhatId = :caseId AND IsClosed = FALSE
      WITH USER_MODE
      ORDER BY ActivityDate ASC NULLS LAST
      LIMIT :CHILD_LIMIT
    ]) {
      ConduitContext entry = new ConduitContext();
      entry.put('subject', task.Subject)
        .put('status', task.Status)
        .put('owner', task.Owner?.Name)
        .putDate('dueOn', task.ActivityDate);
      items.add(entry.toMap());
    }
    return items;
  }
}
