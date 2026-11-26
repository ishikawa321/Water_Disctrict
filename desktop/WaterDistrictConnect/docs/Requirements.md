# Requirements evidence and proposed decisions

The provided files were extracted locally and reviewed. They are source requirements, not evidence of instructor approval or a production district deployment.

| Source | Requirement / context used |
| --- | --- |
| ITSD81 Final Project Handout, v1.2 Instructor Review Candidate | Two complete principal workflows sharing meaningful data; Avalonia/XAML, MVVM, DI, EF, migrations, async access, relational persistence, advanced capability; at least four xUnit tests; six to eight scenarios; self-contained Windows x64 release and manual release check |
| ITSD81 Final Project Testing Guide, v1.2 | Preconditions, controlled data, expected and actual results; fresh persisted-state reads; genuine integration evidence; separate published release check; skipped cases cannot be counted as passes |
| ITSD81 Final Project Scope Reconciliation, v1.2, four-page blank sheet | Sections A–J and documented instructor approval before assessment; actual Midterm evidence must be verified |
| IT3C-08_Tanamal (1).docx | Wider web prototype; fictional records; account ownership; concern → technical ticket link; no repair ticket for payment inquiries; office-managed plumber assignments and updates; signed Job Order reference; weekday staffing context; timestamps separating receipt from human response; district duties and real integration details remain unresolved |
| Second scope reconciliation document requested by user | **Requires verification: not found among supplied attachments or project files.** No contents or approval inferred |

The manuscript describes a proposed responsive HTML/CSS/JavaScript + Laravel + MySQL system. **The C#/Avalonia/.NET/PostgreSQL desktop mini-system is a proposed course adaptation**, not the manuscript's original platform or verified Midterm baseline. The handout permits SQLite or PostgreSQL; the user's explicit requirement selects PostgreSQL. The handout requires six to eight scenarios; the user selects eight. The handout permits several advanced options; the user selects Option A transactional processing.

The implementation deliberately narrows the research: concern receipt and linked repair processing are mandatory. Authentication, fixed fictional reference accounts, resources, search, timelines, dashboard counts and audit records support those workflows. Billing import/publication, payment verification, and announcements are deferred. Bill computation, meter readings, online collection, plumber portal and live district integration are excluded.

Proposed implementation decisions include five demo office/client role definitions, one account per client, Guid concurrency tokens, explicit transactions across state/history/audit, concern states, reopening rules, signed reference length, PHT display, a loopback demo database, and the palette/layout requested by the user. They do not establish official district policies.

The actual Midterm submission, verified members/student IDs, original Midterm ERD and architecture, second scope document, instructor decision/date/reference, district task assignments, exact office hours, verified emergency contacts, real account ownership procedures and production data access require verification. Development uses reasonable fictional assumptions; no missing evidence has been represented as approval.
