# ITSD81 Final Project Scope Reconciliation

Version 0.1 ? Proposed implementation; instructor approval pending.

## A. Original Midterm Baseline

| Item | Group entry |
|---|---|
| Project title / section | Water District Information System ? Desktop Administration Component; BSIT-3C |
| Verified members | Presentation lists Hervy Bjorn Tanamal and Steven Malnegro. Student IDs and final membership require confirmation. |
| Midterm source | Local `Malnegro&Tanamal_Midterm_Presentation (2).pptx`, slides 1?11 |
| Problem and users | Organize client records, billing information and concern follow-up for registered clients and authorized district personnel. Stakeholder procedures remain subject to validation. |
| Original desktop boundary | Client lookup, request review, ticket creation, assignment and updates; verified payment status and notices. |
| Original workflow | Receive concern, validate client/category/description, persist request, create ticket if required, assign staff, append authorized updates and confirm saved result. |
| Decision and unresolved risk | MVVM plus application services/repositories. Office computer and network reliability needs checking. |

## B. Final Workflow 1

| Item | Group entry |
|---|---|
| Name / actor | Receive and review a service concern / active Admin or authorized Staff |
| Purpose | Produce an accountable reviewed concern, ready for repair action or closure with a response. |
| Trigger / preconditions | Consumer submission or office report; signed-in authorized personnel; valid service account. |
| Main success scenario | Find account/submission, validate details, save intake, review concern, record decision/response, retrieve saved result. |
| Inputs | Account, category, subject, description, review decision and response when closing. |
| Rules | Existing permitted account; nonempty required fields; authorized reviewer; server-recorded actor/time; agreed review states. |
| Persisted information | `service_concerns` linked to `service_accounts`, submitter and reviewer identities. |
| Alternatives / failures | Missing details, inaccessible account, unauthorized review, stale data or unavailable dependency: reject without false success and retain draft. No-repair concerns can close with a response. |
| Observable outcome | Concern and review result reopen correctly after application restart. |

## C. Final Workflow 2

| Item | Group entry |
|---|---|
| Name / actor | Dispatch and resolve a repair ticket / Admin and assigned active Staff |
| Purpose | Convert an eligible reviewed concern into accountable repair follow-up and a recorded resolution. |
| Trigger / preconditions | Concern requires repair; no existing ticket; actor has permission. |
| Main success scenario | Admin selects concern, creates ticket and initial event, assigns active staff; assigned staff records permitted progress and resolution; retrieve timeline. |
| Inputs | Concern, assignee, status, update/resolution note and expected record version. |
| Rules | One ticket per concern; valid active staff relationship; permitted transitions; required assignment for Assigned/In progress/Resolved; authorized updates; prevent conflicting saves. Exact transitions require approval. |
| Persisted information | `repair_tickets`, proposed ticket history, concern processing state, accountable actors/timestamps. |
| Alternatives / failures | Duplicate ticket, inactive assignee, unauthorized update, conflict or essential write failure: no partial successful outcome. |
| Observable outcome | Current summary and complete recorded history agree and can be retrieved by desktop and appropriate consumer account. |

## D. Relationship Between Workflows

Workflow 1 establishes or receives the concern. Workflow 2 uses that same concern through a foreign key and a unique concern-to-ticket relationship. Invalid or unavailable account/concern information blocks repair processing. A concern may legitimately have no ticket when no repair is needed.

## E. Data Sources and Persistence

| Information | Source | Retrieval / entry | Local storage | Relationships / integrity |
|---|---|---|---|---|
| Identity | Supabase Auth | Password sign-in and server-validated bearer token | Desktop tokens in memory only | Auth user ID links to active `profiles` row |
| Accounts and access | District-managed existing records | Shared PostgreSQL / consumer Data API | No second desktop operational database | `service_accounts`, `account_access`; live constraints pending inspection |
| Concerns | Consumer submission / office report | Mobile Data API / desktop API | Shared PostgreSQL | Account, submitter and reviewer references |
| Tickets and history | Authorized office processing | Desktop API / EF Core | Shared PostgreSQL | Unique concern, staff identity and atomic related writes |
| Categories / permitted states | Approved reference rules | Application/reference data | Versioned configuration/schema as appropriate | Reference values do not replace operational records |

Supabase is the shared identity/database platform. District personnel remain authoritative for office records and recorded repair updates; the application does not monitor physical work automatically.

## F. Architecture and Data Model

| Item | Proposed implementation |
|---|---|
| Views / ViewModels | Sign-in, role-aware workspace, concerns, review, ticket detail and assigned-work list |
| Application services | Session/profile access, concern review, ticket processing and permission rules |
| Persistence | ASP.NET Core API with EF Core PostgreSQL; consumer app retains Supabase Data API/RLS |
| Entities | Profiles, service accounts, account access, concerns, repair tickets and ticket history |
| ERD revisions | Reconcile original CLIENT with existing service account/access model; retain Supabase Auth; add verified staff link/history without breaking mobile summary fields. |
| Instructor review item | Confirm companion API placement of EF Core satisfies the desktop architecture requirement. |

## G. Advanced Capability

| Item | Group entry |
|---|---|
| Selected option | A ? Transactional business processing |
| Business need | A created repair ticket must agree with its first event and the concern's processing state. |
| Trigger | Authorized user creates ticket from eligible concern. |
| Information | Existing concern/account/profile plus entered repair information. |
| Processing | Validate permission and eligibility; coordinate ticket, first history event and concern state in one PostgreSQL transaction. |
| Outcome | One retrievable, consistent repair-processing result. |
| Integrity | Commit all required related changes together; uniqueness/relationships enforce valid associations. |
| Failure | Forced essential write failure rolls back all affected records; no success message. |
| Verification | Real PostgreSQL integration tests and fresh persisted-state reads for success, duplicate creation and rollback. |

## H. Proposed Scope

| Classification | Features |
|---|---|
| Mandatory | Two workflows above, relational persistence, transaction capability, role authorization, tests, published Windows x64 build |
| Supporting | Login/logout, account lookup, search/filter, loading/error/conflict feedback, history display |
| Deferred | Desktop billing entry, offline payment verification, announcements, exports and advanced dashboards; existing mobile tables remain compatible |
| Excluded Capstone features | Online payments, tariff computation, meter reading, leak detection, automatic physical repair monitoring; implementing the entire consumer application is not required for desktop assessment |

## I. Acceptance Scenarios

| ID | Requirement / preconditions | Action | Expected result | Verification |
|---|---|---|---|---|
| A1 | Active authorized actor; valid account | Save valid office concern | Durable concern linked to correct account | xUnit service/database test |
| A2 | Invalid details or inaccessible account | Attempt intake | Useful rejection; no new concern | xUnit rule/authorization tests |
| A3 | Eligible reviewed concern | Create ticket | Ticket, initial history and concern state agree | xUnit PostgreSQL integration test |
| A4 | Existing ticket or competing creation | Create another ticket | Only one ticket; duplicate/conflict feedback | xUnit PostgreSQL integration test |
| A5 | Assigned active staff | Advance/resolve ticket; attempt unauthorized/invalid transition | Permitted event persists; forbidden update changes nothing | xUnit permission/transition tests |
| A6 | Essential write forced to fail | Create ticket transaction | No partial ticket/history/concern change | xUnit PostgreSQL rollback test |
| A7 | Persisted concern/ticket/history | Restart published application and reopen | Same records and relationships remain | Manual release check plus fresh-context integration reads |
| A8 | Linked consumer and desktop accounts | Submit on mobile, process on desktop, refresh mobile; interrupt dependency | Correct account sees saved result; failed operation reports failure and preserves draft | Manual integration/release check and controlled failure tests |

At least four meaningful automated xUnit tests are required in the final release. The Session 1?4 authentication tests supplement, rather than replace, the principal-workflow tests scheduled for Sessions 5?10.

## J. Instructor Approval

Decision: **Pending ? not yet approved**.

Required revisions: To be recorded by instructor.

Approved scope version: Pending. Approval date: Pending.

Instructor acknowledgment or documented approval reference: Pending.
