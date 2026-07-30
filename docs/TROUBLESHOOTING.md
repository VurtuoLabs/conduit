# Troubleshooting

Agent invocation failures are reported generically, and the message rarely names the real
cause. This maps what you see to what is actually wrong.

Start with [`scripts/apex/ping-agent.apex`](../scripts/apex/ping-agent.apex). It isolates
the platform call from everything Conduit does. If the ping fails, nothing in this package
is involved and nothing in this package will fix it.

## Deployment and compile

| Symptom                                                                                           | Cause                                                                                                                               | Fix                                                                                                                                                                                                      |
| ------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `Invalid action type: generateAiAgentResponse`                                                    | The calling class is below API 64.0                                                                                                 | Set `<apiVersion>64.0</apiVersion>` in that class's `.cls-meta.xml`. The floor is per class. Raising the org's API version does not help.                                                                |
| `Method does not exist or incorrect signature: createCustomAction`                                | Same cause, different compiler path                                                                                                 | As above.                                                                                                                                                                                                |
| `Invalid type: Conduit_Agent__mdt`                                                                | The custom metadata type was not deployed, or was deployed after the classes                                                        | Deploy `force-app` as a unit rather than a subset, so the type lands before the Apex that references it.                                                                                                 |
| Deploy reports success but nothing changed                                                        | `sf` has reported "Unchanged" and even a stale success for a deploy that did not run                                                | Retrieve the metadata back and diff it. Do not trust the deploy summary on its own.                                                                                                                      |
| `Access to TOKEN 'force:base.fontSize3' with access 'INTERNAL' is not allowed from namespace 'c'` | LWC CSS referenced a `--lwc-*` custom property                                                                                      | Those are internal tokens and the `c` namespace cannot use them. Use SLDS utility classes or plain values. The error names only the first one it hits, so remove all of them, not just the one reported. |
| `UNKNOWN_EXCEPTION` with zero component failures and no detail                                    | Usually malformed XML in a `customMetadata` record, most often an `xsi:type="xsd:string"` where the `xsd` prefix was never declared | Declare `xmlns:xsi` and `xmlns:xsd` on the root `<CustomMetadata>` element. The platform reports this as an unknown exception with no component named, so bisect by deploying one directory at a time.   |

## Invocation

| Symptom                                                | Cause                                                               | Fix                                                                                                                                   |
| ------------------------------------------------------ | ------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------- |
| Agent not found, or a generic failure naming the agent | The Agent API Name is wrong                                         | Copy it from Agent Builder. It is usually not the display label and often ends in a numeric suffix.                                   |
| Failure mentioning access or permissions               | The agent is inactive, or the running user has no Agentforce access | Activate the agent. Check the user's permission set assignments. The Conduit User permission set does not grant Agentforce itself.    |
| `Conduit Agent setting "Case_Brief" is switched off.`  | `Active__c` is unchecked on the metadata record                     | Setup, Custom Metadata Types, Conduit Agent, Manage Records.                                                                          |
| `No Conduit Agent setting named "Case_Brief"`          | The metadata record was not deployed                                | Confirm `customMetadata/Conduit_Agent.Case_Brief.md-meta.xml` was included in the deploy.                                             |
| Accepted the request but returned no content           | No agent topic covers this kind of request                          | Open the agent in Agent Builder and check its topics. A summarization prompt needs a topic whose scope actually admits it.            |
| Follow-up answers ignore the case entirely             | The session id was not passed back                                  | The reply's `sessionId` must be sent on the next call. An Apex static will not carry it: statics do not survive between transactions. |
| Second question starts over again                      | The component dropped the session id                                | Reassign `this.sessionId` from every reply, including follow-up replies.                                                              |
| `You have uncommitted work pending`                    | DML ran earlier in the same transaction                             | Move the invocation into a `Queueable`, or do the DML after the agent call.                                                           |
| CPU or transaction timeout                             | Invoked inside a loop or a bulk trigger                             | One invocation per transaction. Anything driven by data change belongs in async.                                                      |

## The component

| Symptom                                    | Cause                                                          | Fix                                                                                                    |
| ------------------------------------------ | -------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------ |
| Error reads `[object Object]`              | The raw exception was rendered instead of `error.body.message` | Use `readError` in `conduitCaseBrief.js`.                                                              |
| Not in the Lightning App Builder palette   | `isExposed` is false, or no matching target                    | `<isExposed>true</isExposed>` plus a `lightning__RecordPage` target.                                   |
| In the palette, but absent from the record | The page was saved but not activated                           | Activate the Lightning page.                                                                           |
| `recordId` is undefined                    | The component is on a page that is not a record page           | Targets are restricted to Case for exactly this reason. Check where it was dropped.                    |
| Brief renders as one unbroken block        | Line breaks collapsed by the renderer                          | Keep it in `<pre>` with `white-space: pre-wrap`. A rich-text renderer discards them.                   |
| The same brief comes back every time       | `cacheable=true` was added to the controller                   | Remove it. These calls are not idempotent and each one opens or continues a session.                   |
| Copy silently does nothing                 | The clipboard API needs a secure context                       | Expected outside HTTPS. The component already falls back to a toast telling the user to copy manually. |

## Field-level security

If a user reports that the brief omits something they can see, or includes something they
should not, the cause is `WITH USER_MODE` doing its job or missing from a query.

`ConduitCaseContextTest.respectsFieldLevelSecurity` covers this for `Case.Description` under
a minimum-access user. Extend it rather than removing `WITH USER_MODE` from a query to make
a field appear. A field the running user cannot read must not reach the agent, because the
agent will read it back to them.

## Reporting a problem

Include the real output of `getErrors()` from the ping script, the API version from the
class's `.cls-meta.xml`, and whether the agent is active. A description of the symptom
without those three is not enough to diagnose anything.
