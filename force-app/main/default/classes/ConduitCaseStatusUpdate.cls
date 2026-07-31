/**
 * Previews or applies a status and priority change on a case.
 *
 * One class serves both the propose and the apply action in the agent. The `apply` flag is
 * what separates them: false computes the change and writes nothing, true commits it. The
 * agent proposes first, shows the engineer the changeSummary, and only calls again with
 * apply = true once they have said yes.
 *
 * Values are validated against the real picklists before any DML. An LLM will confidently
 * offer "In Progress" to an org whose picklist says "Working", and a validation failure
 * returned as text is far more useful to the conversation than a thrown exception.
 */
public with sharing class ConduitCaseStatusUpdate {
  public class Request {
    @InvocableVariable(
      label='Case Id'
      description='Record id of the case to change.'
      required=true
    )
    public String caseId;

    @InvocableVariable(
      label='New Status'
      description='Proposed status. Leave blank to leave it unchanged.'
    )
    public String newStatus;

    @InvocableVariable(
      label='New Priority'
      description='Proposed priority. Leave blank to leave it unchanged.'
    )
    public String newPriority;

    @InvocableVariable(
      label='Apply'
      description='False to preview the change only. True to commit it.'
    )
    public Boolean apply = false;
  }

  public class Result {
    @InvocableVariable(label='Status' description='Case status after this call.')
    public String status = '';

    @InvocableVariable(label='Priority' description='Case priority after this call.')
    public String priority = '';

    @InvocableVariable(
      label='Change Summary'
      description='Field by field description of what changed, or would change.'
    )
    public String changeSummary = '';

    @InvocableVariable(label='Updated' description='True only when a record was written.')
    public Boolean updated = false;
  }

  @InvocableMethod(
    label='Update Case Status'
    description='Previews or applies a status and priority change on a case.'
  )
  public static List<Result> run(List<Request> requests) {
    List<Result> results = new List<Result>();
    for (Request req : requests) {
      results.add(runOne(req));
    }
    return results;
  }

  private static Result runOne(Request req) {
    Result out = new Result();

    if (req == null || String.isBlank(req.caseId)) {
      out.changeSummary = 'No case id was supplied, so nothing was changed.';
      return out;
    }

    List<Case> found = [
      SELECT Id, CaseNumber, Status, Priority
      FROM Case
      WHERE Id = :req.caseId
      WITH USER_MODE
      LIMIT 1
    ];

    if (found.isEmpty()) {
      out.changeSummary = 'That case could not be read, so nothing was changed.';
      return out;
    }

    Case record = found[0];
    out.status = record.Status;
    out.priority = record.Priority;

    String wantStatus = trimToNull(req.newStatus);
    String wantPriority = trimToNull(req.newPriority);

    if (wantStatus == null && wantPriority == null) {
      out.changeSummary =
        'No new status or priority was given, so nothing would change. Case ' +
        record.CaseNumber +
        ' stays ' +
        record.Status +
        ' at ' +
        record.Priority +
        ' priority.';
      return out;
    }

    List<String> problems = new List<String>();
    if (wantStatus != null) {
      String matched = matchPicklist('Status', wantStatus);
      if (matched == null) {
        problems.add(
          '"' + wantStatus + '" is not a valid Status. Valid values: ' + optionList('Status')
        );
      } else {
        wantStatus = matched;
      }
    }
    if (wantPriority != null) {
      String matched = matchPicklist('Priority', wantPriority);
      if (matched == null) {
        problems.add(
          '"' +
            wantPriority +
            '" is not a valid Priority. Valid values: ' +
            optionList('Priority')
        );
      } else {
        wantPriority = matched;
      }
    }

    if (!problems.isEmpty()) {
      out.changeSummary = String.join(problems, ' ') + ' Nothing was changed.';
      return out;
    }

    List<String> changes = new List<String>();
    if (wantStatus != null && wantStatus != record.Status) {
      changes.add('Status ' + record.Status + ' to ' + wantStatus);
    } else if (wantStatus != null) {
      changes.add('Status already ' + record.Status + ', unchanged');
    }
    if (wantPriority != null && wantPriority != record.Priority) {
      changes.add('Priority ' + record.Priority + ' to ' + wantPriority);
    } else if (wantPriority != null) {
      changes.add('Priority already ' + record.Priority + ', unchanged');
    }

    Boolean anythingDiffers =
      (wantStatus != null && wantStatus != record.Status) ||
      (wantPriority != null && wantPriority != record.Priority);

    if (req.apply != true) {
      out.changeSummary =
        'Proposed for case ' + record.CaseNumber + ': ' + String.join(changes, '; ') + '.';
      return out;
    }

    if (!anythingDiffers) {
      out.changeSummary =
        'Case ' +
        record.CaseNumber +
        ' already matches the requested values, so no update was written.';
      return out;
    }

    Case toUpdate = new Case(Id = record.Id);
    if (wantStatus != null) {
      toUpdate.Status = wantStatus;
    }
    if (wantPriority != null) {
      toUpdate.Priority = wantPriority;
    }

    try {
      update as user toUpdate;
    } catch (DmlException failure) {
      out.changeSummary =
        'The update was rejected: ' + failure.getDmlMessage(0) + '. Nothing was changed.';
      return out;
    }

    // Re-read rather than assuming. A validation rule or workflow may have altered the
    // values we just wrote, and the engineer needs to be told what actually landed.
    Case after = [
      SELECT Status, Priority
      FROM Case
      WHERE Id = :record.Id
      WITH USER_MODE
      LIMIT 1
    ];
    out.status = after.Status;
    out.priority = after.Priority;
    out.updated = true;
    out.changeSummary =
      'Applied to case ' + record.CaseNumber + ': ' + String.join(changes, '; ') + '.';
    return out;
  }

  /** Case-insensitive match against the real picklist, returning the canonical value. */
  private static String matchPicklist(String field, String candidate) {
    for (Schema.PicklistEntry entry : entries(field)) {
      if (
        entry.isActive() &&
        (entry.getValue().equalsIgnoreCase(candidate) ||
        entry.getLabel().equalsIgnoreCase(candidate))
      ) {
        return entry.getValue();
      }
    }
    return null;
  }

  private static String optionList(String field) {
    List<String> values = new List<String>();
    for (Schema.PicklistEntry entry : entries(field)) {
      if (entry.isActive()) {
        values.add(entry.getValue());
      }
    }
    return String.join(values, ', ');
  }

  private static List<Schema.PicklistEntry> entries(String field) {
    return Schema.getGlobalDescribe()
      .get('Case')
      .getDescribe()
      .fields.getMap()
      .get(field)
      .getDescribe()
      .getPicklistValues();
  }

  private static String trimToNull(String value) {
    return String.isBlank(value) ? null : value.trim();
  }
}
