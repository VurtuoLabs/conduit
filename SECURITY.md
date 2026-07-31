# Security

Conduit invokes an Agentforce agent from Apex and renders the answer in a Lightning Web Component. It ships the agent it calls.

## Reporting a vulnerability

Report security issues privately to **aimperiale@vurtuolabs.com**. Do not open a public
issue for anything you believe is exploitable.

Include the version or commit you tested, the org edition and configuration if relevant,
what you observed, and the smallest set of steps that reproduces it. A proof of concept is
welcome but not required.

What to expect:

| Stage | Target |
|---|---|
| Acknowledgement that the report was received | 3 working days |
| Initial assessment, including whether it is accepted | 10 working days |
| Fix or documented mitigation for an accepted issue | 30 days, sooner where severity warrants |

We will tell you which way the assessment went either way. If a report is not accepted you
will get the reasoning, not silence. Credit is offered on any accepted report unless you ask
us not to.

## Supported versions

Security fixes land on the default branch. There are no long-lived release branches and no
backports to older commits, so the supported version is the current `main`.

## The security model in one paragraph

This package runs inside your Salesforce org, in the session of the user who invokes it.
It does not introduce an identity of its own, it does not hold credentials, and it does
not create a path to data that the running user could not already reach through the
standard UI or API. Everything below is detail on how that is enforced and where the
deliberate exceptions are.

## Record and field access

Two mechanisms do different jobs, and conflating them is the usual way data leaks:

- **`with sharing` on a class** governs **which records** the running user can see. It
  applies row-level sharing: ownership, role hierarchy, sharing rules, manual shares.
- **`WITH USER_MODE` on a query** enforces **object and field-level security** for that
  query. It applies CRUD and FLS.

`with sharing` alone does not give you field-level security. A class can be `with
sharing` and still hand a user the contents of a field their profile hides from them.
Both are required, and this package uses both.

Measured against the current commit:

| Control | Count |
|---|---|
| Production Apex classes | 13 |
| Classes declared `with sharing` | 13 |
| Classes declared `without sharing` | 0 |
| Production SOQL queries | 17 |
| Queries carrying an explicit enforcement clause | 17 |
| Queries deliberately running in system mode | 0 |
| DML statements using `as user` | 3 |
| Apex test methods | 41 |

Every production query carries an explicit enforcement clause. There are no
exceptions.

## Agent-specific risk

This package ships an Agentforce agent, which changes the threat model in ways that
are worth stating plainly.

**Record data is untrusted input.** Anything a customer or external party can write
into a record can contain text shaped like an instruction to the model. The agent is
instructed to treat retrieved record content as data to report on rather than
directions to follow. That lowers the odds. It does not eliminate them, and it is not
a security boundary.

**The real boundary is that the agent cannot exceed the running user.** Its actions
are invocable Apex running in the user's session under the same sharing and
field-level rules as everything else here. A successful injection cannot read or
write a record the user could not already read or write themselves.

**Writes are gated on explicit human confirmation.** Status changes, case notes and email drafts each require the engineer to confirm through the platform's `require_user_confirmation` gate before anything is written. Customer email is saved as an unsent draft; the package cannot send mail.

**Generated text is not authoritative.** Model output can be wrong or fabricated.
Nothing produced by the agent should be treated as a system of record, and no output
is used to drive an irreversible action without a person in the loop.

## Secrets and credentials

This package makes no authenticated outbound calls and stores no credentials.

No API keys, tokens, passwords, certificates or session identifiers are committed to
this repository. Test fixtures use obviously fake values.

## What this package deliberately does not do

- It does not send email. `ConduitEmailDraft` writes an `EmailMessage` with `Status = '5'`, which is a draft awaiting a human.
- It does not choose an email recipient. The address is resolved in Apex from the case contact, never supplied by the model.
- It does not cache agent responses. The `@AuraEnabled` methods are deliberately not `cacheable`, because each call opens or continues a billed agent session.
- It does not store conversation history outside the Agentforce session.

## Your responsibilities as the deploying admin

This package inherits your org's configuration. It cannot compensate for it.

- Grant access through the permission set
  (1 shipped in this repository), not by widening profiles.
- Field-level security is yours to define. This package enforces what you configure; it
  does not decide what a role should see.
- Review the sharing model on any custom object this package creates before you load
  production data into it.
- Anyone who can see the data can see it through this package too. That is the intent,
  and it is worth confirming it matches your expectations before rollout.

## How these claims are checked

The counts in this document are measured from source, not asserted from memory. They are
reproduced with:

```bash
# production queries (test classes excluded)
grep -rn "\[\s*SELECT" --include="*.cls" force-app | wc -l

# queries carrying an explicit enforcement clause
grep -rn "WITH USER_MODE" --include="*.cls" force-app | wc -l

# classes that opt out of sharing
grep -rn "without sharing" --include="*.cls" force-app
```

If you find a query in this repository that lacks an enforcement clause and is not listed as
a documented exception above, that is a defect. Report it.

## License and warranty

Released under the MIT License. It is provided without warranty of any kind, including
any warranty of security or fitness for a particular purpose. See [LICENSE](LICENSE).

Copyright (c) 2026 VurtuoLabs
