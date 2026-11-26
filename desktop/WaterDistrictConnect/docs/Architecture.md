# Architecture and implementation decisions

## Structure

The existing Avalonia project was reused. `MainWindow` hosts a root ViewModel; XAML data templates select login/workspace/page views. CommunityToolkit generated observable properties and async commands support MVVM. Views have no SQL or business operations. Workspace code-behind resets scroll position on page navigation; the confirmation service constructs presentation-only modal windows. A reusable Feedback control provides loading, error, and success feedback.

Dependency injection composes a session, authentication, database setup, application service, confirmation service, and ViewModels. Each service operation creates/disposes a fresh EF context, rereads the active user and persisted role permissions, and applies account ownership filtering. Detail reads use the same ownership restriction as list reads. Clients cannot supply another account for intake. Queries project allowed event data into DTOs and exclude internal notes in the database query. Session logout clears the user identifier and discards the workspace.

The application uses asynchronous database operations. ViewModel operation guards prevent overlapping submissions and restore busy states in `finally`. Async commands also disable repeated execution. Form values are retained on recoverable errors. A saved concern identifier disables the submission form before its follow-up detail read to avoid duplicate submission after a read failure.

## Versions

| Component | Chosen version |
| --- | --- |
| SDK / target | Installed SDK 10.0.401 / net10.0 |
| Avalonia, Desktop, Fluent | 12.1.6, reused from starter |
| CommunityToolkit.Mvvm | 8.4.0 |
| Npgsql EF PostgreSQL provider / Npgsql | 10.0.0 / 10.0.0 |
| EF Core, relational, design and dotnet-ef | 10.0.0 |
| Microsoft.Extensions.Identity.Core / DI | 10.0.0 |
| Cryptography.Pkcs and Cryptography.Xml | 10.0.15, patched transitive dependency overrides |
| xUnit / VS runner | 2.9.3 / 3.1.4 |
| Microsoft.NET.Test.Sdk / coverlet.collector | 17.14.1 / 6.0.4 |
| PostgreSQL used for verification | Existing PostgreSQL 18 binaries |

Versions are implementation choices, not exact handout mandates. NuGet audit initially identified vulnerable design-time transitive crypto versions; explicit patched versions replace them. Lock files preserve resolved dependencies. Segoe UI is used for Windows; the starter's unused Inter font and developer-tools package were removed.

## Permission matrix

| Operation | Administrator | Handler | Coordinator | Viewer | Client |
| --- | --- | --- | --- | --- | --- |
| Office concerns, tickets, accounts, resources read | Yes | Yes | Yes | Yes | No |
| Office intake, with account/channel/recording user | Yes | Yes | No | No | No |
| Human response, classification, internal concern note | Yes | Yes | No | No | No |
| Ticket creation, assignment, progress, resolve, close, reopen | Yes | No | Yes | No | No |
| Submit linked-account concern | No, use office intake | No, use office intake | No | No | Own account |
| Customer-visible concerns/tickets/account read | Office read | Office read | Office read | Office read | Own account only |
| Internal notes | Office read | Office read | Office read | Office read | Never |
| Ownership/identity edits, customer registration, user administration | No | No | No | No | No |

These are proposed demo duties, not confirmed district staff assignments. Permissions live in RolePermission; UserRole supports multiple roles. Each client has one User–CustomerAccount ownership link in this implementation. All office roles can access all five read-only office destinations; write controls are filtered by their separate permissions and enforced again in services.

## Concern state model (Phase 2)

ConcernPolicy centrally enforces Review, Respond, InternalNote, Reclassify, Resolve, Close and Reopen. Available office actions derive from that policy. Submitted moves to Under Review on an explicit review or human response. A response can also be appended while Under Review or to a legacy Awaiting Repair record. Internal notes change no status. Review, classification reasons and notes are internal; responses and lifecycle reasons are customer-visible. Opening a detail is read-only.

Only the explicit customer-visible response action sets FirstHumanResponseAt, once. Automatic receipt, internal notes, lifecycle reasons and opening/marking review never do. Responses are separate immutable application event rows, not overwritten fields. Existing events from before Phase 2 retain their evidence; missing historic before/after states are not fabricated.

Only nontechnical, unlinked concerns Under Review can Resolve; only resolved nontechnical, unlinked concerns can Close. Reopen requires handler permission and a meaningful reason and returns an unlinked resolved/closed concern to Under Review. Every action needs 10-4000 characters of explanation. Close and Reopen have confirmation dialogs. Reclassification requires an open unlinked concern, a changed category and a recorded internal reason. It corrects factual classification mistakes, not actual repair requirements merely to permit closure.

Technical concerns must remain Submitted/Under Review pending Phase 3. Awaiting Repair is reserved for a future atomic linked-ticket operation, never manually selected. No Phase 2 action can move a concern into that state; technical resolve/close and all ticket creation/update services are blocked. The preserved ticket implementation below is historical design context, not Phase 2 functionality or acceptance evidence.

## Central ticket transition policy

| Action | Allowed source | Result / required evidence |
| --- | --- | --- |
| Create | Existing open Technical concern, no ticket | Unassigned; linked concern event and creation event |
| Assign | Unassigned, Assigned, InProgress | Available existing plumber; explanation required; Assigned unless already InProgress |
| Start | Assigned with resource | InProgress; office update required |
| Progress | Assigned or InProgress | Same state; nonempty update; may be internal |
| Resolve | InProgress | Resolved; nonempty completion summary and time |
| Close | Resolved | Closed; signed Job Order reference, maximum 160 characters, closure time, confirmation |
| Reopen | Resolved or Closed | Assigned if resource retained, otherwise Unassigned; reason and confirmation |

The UI does not verify the authenticity of a real signature. The signed Job Order field records a fictional office-confirmed reference, not a fabricated signature. Reassignment requires a different available resource and a reason. FirstAssignedAt is set once, remains unchanged on reassignment/reopening, and later assignments have separate events. Reopening clears current completion fields/times; prior summaries, Job Order references, actors and times remain in immutable application event history. Resource availability is a seeded demo assertion, not a live field schedule.

## Transactions, concurrency, integrity

Ticket creation and every decision run in an explicit PostgreSQL transaction. First, validated ticket/concern states are saved. Next, the essential event and audit rows are saved, then the transaction commits. If either write fails, disposal rolls back the transaction. Integration verification installs a trigger in a disposable database that throws on the Resolve event INSERT **after the state write**. Fresh reads prove the prior state, summary, version, resolution time, event count, and audit state remain intact. Removing the trigger permits safe retry.

Concern receipt uses an explicit transaction: the sequence-generated concern is saved first, followed by its receipt and audit, then commit. A per-form SubmissionKey, unique index and transaction advisory lock make concurrent retries idempotent. Human responses and other decisions save the state/version first and event/audit second within one transaction. Disposable PostgreSQL tests inject real history INSERT failures to verify rollback after the first save. Guid concurrency tokens on concern and ticket are replaced with each decision. Expected detail versions are compared before processing; EF's concurrency predicate catches races after that comparison. The linked concern token also protects simultaneous ticket/response decisions. The UI shows stale-data guidance and retains input.

Unique constraints cover usernames, account numbers, role names, resource names, references, ownership per user, and one ticket per concern. All related records use foreign keys with Restrict delete behavior. Lengths, required strings, category/state checks, nonblank concern content, resource/state compatibility, and resolved/closed completion evidence have database constraints. Account numbers are strings. No application delete or history-edit operation exists. Foreign keys prevent destructive cascades; this is not a claim that a privileged database administrator cannot modify data.

## Interface system

Theme.axaml centralizes the requested palette as semantic brushes, typography, page/card spacing, radii, borders, focus and button states. Light Fluent styling, Segoe UI, a 208px light sidebar, 1280×800 initial window and 1024×700 minimum are used. The app scrolls long pages. Icons use one consistent outlined path family; the product identity is a simple vector drop, not an official seal. State labels accompany colors. Input controls are at least 38px high, and text fields have automation names. Dialogs identify the reference, current state, intended result and entered reason/reference.

All timestamps are UTC `DateTimeOffset` in PostgreSQL timestamptz, rendered as PHT (UTC+08:00). The system makes no official response-time or physical repair-duration claim.

The reference-board alignment uses a light gradient sidebar, pale cyan navigation selection, water-blue actions, a split sign-in layout with vector waves, compact bordered cards and state-colored badges. Client pages use concern cards and latest-reply panels; office pages use a queue table and a side timeline. Category tiles feed a validated review-before-submit step. A shared button template keeps hover, pressed, disabled and keyboard focus states consistent. Navigation highlights follow dashboard links and record details as well as direct sidebar selections.

`Styles/Motion.axaml` supplies 160ms hover lift/press feedback and 220ms page entrance transitions. These use render transforms, so layout does not shift. The application reads Windows' client-area animation preference at startup and omits motion styles when animations are disabled. `MWD_REDUCED_MOTION=true` also disables them without changing system settings. There are no looping or delayed-action animations. See [Avalonia transitions](https://docs.avaloniaui.net/docs/graphics-animation/control-transitions).

Technical references: [Avalonia MVVM guidance](https://docs.avaloniaui.net/docs/how-to/mvvm-how-to), [Avalonia 12 changes](https://docs.avaloniaui.net/docs/avalonia12-breaking-changes), [EF concurrency](https://learn.microsoft.com/en-us/ef/core/saving/concurrency), [Npgsql concurrency guidance](https://www.npgsql.org/efcore/modeling/concurrency.html). An application-managed Guid token is used instead of provider-specific xmin.

See [reference UI alignment](UIReferenceAlignment.md) for the supplied-board mapping, production rendering harness and screenshots. Overview activity and pending-review panels are projected from persisted authorized records; internal activity is excluded from client queries. Office action choices are held as a stable collection so selector initialization cannot clear the active response mode.
