/**
 * Everything the agent needs to write a handover brief for one case.
 *
 * Comments, email and tasks are merged into a single time-ordered feed rather than returned
 * as three parallel lists. A brief is a narrative, and the LLM writes a better one from one
 * chronology than from three collections it has to interleave itself.
 *
 * The feed is returned as preformatted text, not as a list of objects. That sidesteps the
 * complex_data_type_name mapping for Apex inner classes entirely, which is the single most
 * common cause of publish-fix-republish cycles, and the agent only ever reads it as prose.
 */
public with sharing class ConduitCaseDetail {
  private static final Integer CHILD_LIMIT = 10;
  private static final Integer EXCERPT_CHARS = 300;
  private static final Integer DESCRIPTION_CHARS = 1500;

  public class Request {
    @InvocableVariable(
      label='Case Id'
      description='Record id of the case to describe.'
      required=true
    )
    public String caseId;
  }

  public class Result {
    // Deliberately NOT named `description`: that is a reserved @InvocableVariable name and
    // the class will not compile with it.
    @InvocableVariable(label='Description' description='The case description, truncated.')
    public String caseDescription = '';

    @InvocableVariable(label='Contact' description='Name of the case contact.')
    public String contactName = '';

    @InvocableVariable(label='Account' description='Name of the case account.')
    public String accountName = '';

    @InvocableVariable(label='Owner' description='Current case owner.')
    public String ownerName = '';

    @InvocableVariable(label='Days Open' description='How long the case has been open.')
    public String daysOpen = '';

    @InvocableVariable(
      label='Activity Count'
      description='Number of comments, emails and open tasks found.'
    )
    public String activityCount = '';

    @InvocableVariable(label='Last Activity' description='When the case last saw activity.')
    public String lastActivity = '';

    @InvocableVariable(label='Escalated' description='Whether the case is escalated.')
    public Boolean isEscalated = false;

    @InvocableVariable(
      label='Activity Feed'
      description='Time-ordered feed of comments, email and tasks, one entry per line.'
    )
    public String activityFeed = '';
  }

  /** Internal only. Lets the three sources be sorted together before formatting. */
  private class FeedEntry implements Comparable {
    Datetime occurredAt;
    String line;

    FeedEntry(Datetime occurredAt, String line) {
      this.occurredAt = occurredAt;
      this.line = line;
    }

    public Integer compareTo(Object other) {
      Datetime theirs = ((FeedEntry) other).occurredAt;
      if (occurredAt == theirs) {
        return 0;
      }
      // Newest first: that is the order an engineer reads a case in.
      return occurredAt > theirs ? -1 : 1;
    }
  }

  @InvocableMethod(
    label='Get Case Detail'
    description='Returns a case with a merged, time-ordered feed of its comments, email and tasks.'
  )
  public static List<Result> describe(List<Request> requests) {
    List<Result> results = new List<Result>();
    for (Request req : requests) {
      results.add(describeOne(req == null ? null : req.caseId));
    }
    return results;
  }

  private static Result describeOne(String caseIdText) {
    Result out = new Result();

    if (String.isBlank(caseIdText)) {
      out.activityFeed = 'No case id was supplied.';
      return out;
    }

    List<Case> found = [
      SELECT
        Id,
        CaseNumber,
        Description,
        Status,
        Priority,
        IsEscalated,
        CreatedDate,
        Owner.Name,
        Contact.Name,
        Account.Name
      FROM Case
      WHERE Id = :caseIdText
      WITH USER_MODE
      LIMIT 1
    ];

    if (found.isEmpty()) {
      out.activityFeed = 'That case could not be read, or you do not have access to it.';
      return out;
    }

    Case record = found[0];
    out.caseDescription = clip(record.Description, DESCRIPTION_CHARS, '(no description)');
    out.contactName = blankTo(record.Contact?.Name, 'Not recorded');
    out.accountName = blankTo(record.Account?.Name, 'Not recorded');
    out.ownerName = blankTo(record.Owner?.Name, 'Not recorded');
    out.isEscalated = record.IsEscalated == true;

    Integer days = record.CreatedDate.date().daysBetween(Date.today());
    out.daysOpen = days == 0 ? 'opened today' : String.valueOf(days) + ' days';

    List<FeedEntry> feed = new List<FeedEntry>();
    feed.addAll(comments(record.Id));
    feed.addAll(emails(record.Id));
    feed.addAll(tasks(record.Id));
    feed.sort();

    out.activityCount = feed.isEmpty()
      ? 'no recorded activity'
      : String.valueOf(feed.size()) + ' entries';
    out.lastActivity = feed.isEmpty()
      ? 'none since the case was opened'
      : format(feed[0].occurredAt);

    if (feed.isEmpty()) {
      out.activityFeed = 'Nothing has been logged on this case since it was opened.';
      return out;
    }

    List<String> lines = new List<String>();
    for (FeedEntry entry : feed) {
      lines.add(entry.line);
    }
    out.activityFeed = String.join(lines, '\n');
    return out;
  }

  private static List<FeedEntry> comments(Id caseId) {
    List<FeedEntry> entries = new List<FeedEntry>();
    for (CaseComment comment : [
      SELECT CommentBody, CreatedDate, CreatedBy.Name
      FROM CaseComment
      WHERE ParentId = :caseId
      WITH USER_MODE
      ORDER BY CreatedDate DESC
      LIMIT :CHILD_LIMIT
    ]) {
      entries.add(
        new FeedEntry(
          comment.CreatedDate,
          format(comment.CreatedDate) +
            ' | internal note by ' +
            blankTo(comment.CreatedBy?.Name, 'unknown') +
            ' | ' +
            clip(comment.CommentBody, EXCERPT_CHARS, '(empty)')
        )
      );
    }
    return entries;
  }

  private static List<FeedEntry> emails(Id caseId) {
    List<FeedEntry> entries = new List<FeedEntry>();
    for (EmailMessage email : [
      SELECT Subject, TextBody, MessageDate, FromAddress, Incoming, Status
      FROM EmailMessage
      WHERE ParentId = :caseId
      WITH USER_MODE
      ORDER BY MessageDate DESC
      LIMIT :CHILD_LIMIT
    ]) {
      String direction = email.Status == '5'
        ? 'unsent draft'
        : (email.Incoming == true ? 'email from customer' : 'email to customer');
      entries.add(
        new FeedEntry(
          email.MessageDate,
          format(email.MessageDate) +
            ' | ' +
            direction +
            ' | ' +
            blankTo(email.Subject, '(no subject)') +
            ' | ' +
            clip(email.TextBody, EXCERPT_CHARS, '(no body)')
        )
      );
    }
    return entries;
  }

  private static List<FeedEntry> tasks(Id caseId) {
    List<FeedEntry> entries = new List<FeedEntry>();
    for (Task task : [
      SELECT Subject, Status, ActivityDate, CreatedDate, Owner.Name, IsClosed
      FROM Task
      WHERE WhatId = :caseId
      WITH USER_MODE
      ORDER BY CreatedDate DESC
      LIMIT :CHILD_LIMIT
    ]) {
      String due = task.ActivityDate == null
        ? 'no due date'
        : 'due ' + String.valueOf(task.ActivityDate);
      entries.add(
        new FeedEntry(
          task.CreatedDate,
          format(task.CreatedDate) +
            ' | task (' +
            task.Status +
            ', ' +
            due +
            ') owned by ' +
            blankTo(task.Owner?.Name, 'unknown') +
            ' | ' +
            blankTo(task.Subject, '(no subject)')
        )
      );
    }
    return entries;
  }

  /**
   * Always GMT, always labelled. Bare format() renders in the running user's timezone with
   * no marker, and an agent asked to quote it will invent a timezone that is simply wrong.
   */
  private static String format(Datetime value) {
    return value == null ? 'unknown date' : value.formatGmt('yyyy-MM-dd HH:mm') + ' GMT';
  }

  private static String blankTo(String value, String fallback) {
    return String.isBlank(value) ? fallback : value;
  }

  private static String clip(String value, Integer limitChars, String fallback) {
    if (String.isBlank(value)) {
      return fallback;
    }
    String flat = value.trim().replaceAll('\\s+', ' ');
    return flat.length() <= limitChars
      ? flat
      : flat.left(limitChars) + ' [truncated]';
  }
}
