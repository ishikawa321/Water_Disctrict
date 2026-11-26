# Phase 2 concern workflow and verification

Presentation update: the client/admin reference-board alignment and 16 production-view renders are recorded in [UI reference alignment](UIReferenceAlignment.md). That later presentation record supersedes the older styling descriptions while preserving this phase's workflow and security checks.

Implemented on 24 November 2026 in the existing Avalonia solution. Phase 1 architecture, PostgreSQL setup, authenticated Session, persisted permission loading, account ownership queries and shared theme are reused. No Flutter files were changed. Earlier concern code and the existing forward Phase2Concerns migration were inspected, completed and verified rather than creating another solution. No essential Phase 1 dependency required replacement.

## Delivered behavior

- Linked-account client submission with five categories, required subject/description/location, prefilled location and optional contact. Both UI and application service validate. Client-supplied account IDs are checked against current persisted ownership.
- Concurrent-safe sequence references and per-form idempotent submission keys. A saved form is locked against repeat submission, including when its follow-up detail read fails. Form values survive recoverable failures.
- Atomic concern, receipt and audit writes. Automatic receipt explicitly means awaiting office review, not staff response.
- My Concerns and office queue with search, category/status filters, clear filters, 20-record pages, previous/next boundaries, refresh and loading/empty/error feedback.
- Concern details with current status, submitted date, classification, description/location, intake attribution, first response time and chronological visible history.
- Office intake with existing-account search, actual intake channel and actual office actor.
- Authorized review, reasoned classification correction, append-only human responses and internal notes, nontechnical resolution/closure, and reasoned reopening. Closure/reopening use confirmation. Available UI actions derive from the central transition policy; services enforce it again.
- Read-only office access. Services reload current active identity/permissions on every call and enforce ownership independently of UI controls.
- Expected-version checks and EF concurrency predicates reject stale/racing updates. Refresh reloads the detail; unsaved response input is retained.
- Overview counts read persisted, access-scoped concerns. Ticket navigation and ticket mutation services remain disabled.

## State and history rule

Submitted can become Under Review through Review or a customer-visible response. Only a nontechnical, unlinked Under Review concern can Resolve, followed by Close. An authorized handler can Reopen an unlinked Resolved/Closed concern to Under Review with a reason. Every office action requires 10–4000 characters. No arbitrary status setter is exposed.

Technical concerns cannot Resolve/Close here. Actual repair needs remain under review until Phase 3 introduces the linked repair workflow and reserved Awaiting Repair transition. Correcting an erroneous intake category requires a recorded reason and must not be used to disguise a real technical repair requirement merely to close it. Reclassification is unavailable after resolution or once a ticket is linked.

ConcernEvent stores actor, UTC timestamp, type, text, visibility and relevant before/after state/category. Human responses use event rows rather than a separate response table. Review, classification reasons and explicitly marked notes are internal and are excluded from client queries before DTO construction. Response and lifecycle reasons are customer-visible. FirstHumanResponseAt is set once by the explicit human response action; lifecycle reasons, receipt, review, internal notes and opening a detail do not count as responses. PHT is the existing display convention.

## Migration and setup

Use `./scripts/Start-Phase2.ps1 -UseExistingLocalDemo -Migrate` against the configured fictional demo server, then omit `-Migrate` for normal launches. See README for starting the existing cluster or configuring another authorized PostgreSQL database. The normal app checks readiness and never resets data.

`20261123160835_Phase2Concerns` adds the supported categories/states/channels, event before/after fields, unique SubmissionKey and PostgreSQL reference sequence. Existing numeric category/state values remain stable. Legacy intake strings are copied to LegacyIntakeChannel before normalization. Existing reference values are retained and the sequence is advanced past existing numeric MWD references. Old event fields remain nullable; no historic evidence is invented. The retained one-concern/one-ticket relationship is reserved for Phase 3. Destructive downgrade is intentionally refused.

The configured demo database received the forward migration successfully during verification. No normal records were deleted, reset or used as automated fixtures. Generated test databases contain all integration fixtures. Historical published artifacts are not Phase 2 builds; launch current source.

## Executed verification

| Check | Actual result |
| --- | --- |
| Release solution build | Passed, 0 warnings and 0 errors |
| Locked restore | All four projects restored successfully |
| EF model versus migration snapshot | No pending model changes |
| Unit tests | 28 passed, 0 failed, 0 skipped |
| Phase 2 PostgreSQL integration tests | 15 passed, 0 failed, 0 skipped |
| Valid client receipt, persistence and fresh session | Passed |
| Invalid required values, lengths, category and missing linked account | Rejected without concern/event/audit persistence |
| Foreign account submission, list filter and direct detail read | Rejected through direct service calls |
| Office intake account/channel/actor attribution | Passed for Telephone, Walk-in and Other; Desktop Client rejected for office intake |
| Read-only, revoked permission and logged-out updates | Rejected |
| Receipt/open/review/classification/internal note timing | First human-response time remains null |
| First and later customer-visible responses | First timestamp set once and preserved |
| Internal event privacy | Excluded from client detail and overview DTOs |
| Resolve/close/reopen policy and meaningful reasons | Passed; invalid actions rejected |
| Technical repair bypass | Resolve, close and ticket creation rejected |
| Stale and concurrent office decisions | Only one racing update succeeds; no lost history |
| Concurrent references and identical form retries | Unique references; concurrent retries save one concern/receipt |
| Actual PostgreSQL unique reference constraint | Duplicate reference rejected |
| PostgreSQL category/state/channel/content/foreign-key constraints | Invalid direct inserts rejected without persistence |
| Real history INSERT failure after concern/state save | Transaction rolls back concern/state/version/timing/audit; safe retry succeeds |
| Search, filters, pagination, overview scoping | Passed against persisted records |
| Upgrade from InitialScope with existing concern | Original ID, description, reference and intake text retained; next reference advanced safely |
| Full production ViewModel demonstration | Client submission, handler queue/response, client retrieval, second-client denial, fresh-session persistence passed |
| Current native application launch | Succeeded following forward migration |
| Native screen inspection | Blocked: computer-use tool returned “Computer Use was not approved to use waterdistrictconnect” |
| Phase 2 and common demo launch/test scripts | PowerShell parser checks passed; common demo launcher now selects current source |

Commands: `dotnet build -c Release`, `dotnet restore --locked-mode`, `dotnet ef migrations has-pending-model-changes --project WaterDistrictConnect.Core`, and `./scripts/Test-Phase2.ps1 -UseExistingLocalDemo`.

Raw evidence: `TestResults/phase2-unit.trx` and `TestResults/phase2-postgresql.trx`. PostgreSQL tests create only generated `mwd_phase2_<GUID>` databases, migrate/seed them and remove only those generated names. They never clean/reset the normal application database. Initial integration execution found the existing server stopped (`127.0.0.1:55481` actively refused connections); starting that existing cluster resolved the blocker. Sandboxed dotnet verification also required execution outside the sandbox. Final passing results supersede those setup failures.

The ViewModel test exercises actual authentication, services, commands and PostgreSQL persistence; it is not evidence of native rendering or a literal app-process restart. Persistence is verified using fresh sessions/service instances and new database reads. Native end-to-end clicks, screen-reader behavior, scaling and a full keyboard audit were not verified because native inspection was denied. Those remain manual checks, not claimed passes.

## Manual demonstration

All fictional demo logins use `WaterDemo!2026`.

1. Sign in as Client A, `amara` (000101), select Submit Concern, choose General Inquiry, complete the fields and submit. Note the reference, automatic receipt explanation and View saved concern action.
2. Sign out; sign in as `handler` or `admin`.
3. Find that reference in Concern Queue, open it, choose Customer-visible response, enter a meaningful response and save. Optionally add a separately marked internal note.
4. Return as `amara`; use My Concerns to verify Under Review, the visible response and first response time. The internal note must be absent.
5. Sign in as Client B, `benito` (000102); searching that reference returns no concern. Automated direct-service tests also reject its identifier and account filter.
6. Close/restart the current source app, sign in as `amara`, and retrieve the same reference and response again.

For lifecycle demonstration use a nontechnical concern, mark it under review, resolve with a reason, close with confirmation, and reopen with a reason and confirmation. A technical concern must offer no resolve/close action and no repair button.

## Limitations and Phase 3 readiness

The Phase 2 domain/services and persistence are ready to support Phase 3 work. Its repair processing must be implemented/reviewed separately, connect only eligible technical concerns, and atomically preserve linked versions and events. Historical repair code/tables are retained but are not Phase 3 completion evidence and must not be enabled unchanged.

This remains a trusted-machine academic prototype using fictional data, not a production service boundary. Customer registration, user administration, password recovery, payments, backups UI and live district integration are outside scope. Account eligibility means an existing linked account in the Phase 1 model; there is no invented billing/service eligibility flag. Native UI verification limits are stated above. No instructor approval, district validation or research participant results are claimed. Work stops at Phase 2.
