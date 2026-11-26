# Workflow acceptance and verification

## Eight acceptance scenarios

| ID | Preconditions and action | Expected business and persisted outcome | Verification |
|---|---|---|---|
| A1 | Active office user, active account; submit valid concern and repeat same request identifier | Exactly one durable concern with correct account, submitter and server time | Intake_is_durable_and_retrying_the_same_request_is_idempotent |
| A2 | Missing description, unknown/inactive account or unapproved role; attempt intake | Rejection without an operational record; desktop retains entered draft | Invalid_information_or_account_is_rejected_without_records; Failed_intake_keeps_draft_and_retry_identifier_until_confirmed_success |
| A3 | Reviewed concern requires repair; Admin creates ticket | One linked Open ticket, initial history and dispatch marker agree | Ticket_assignment_and_resolution_preserve_history_and_consumer_summary; API workflow test |
| A4 | Competing creators or stale record version; save ticket/review | One creation succeeds; rejected save does not overwrite current data | Concurrent_creators_leave_one_ticket_and_one_initial_event; Stale_review_cannot_overwrite_the_saved_decision |
| A5 | Admin assigns active Staff; Staff progresses and resolves; try invalid transition/inactive assignee/unassigned actor | Valid events append; invalid operations change no business data; resolution updates consumer summary | Ticket_assignment_and_resolution_preserve_history_and_consumer_summary; Invalid_transition_inactive_assignee_and_unassigned_staff_change_nothing |
| A6 | Force essential concern dispatch write to fail after ticket/history writes | Entire transaction rolls back; no ticket, history or dispatch marker survives | Failure_after_history_insert_rolls_back_ticket_history_and_dispatch_marker, using fresh PostgreSQL reads |
| A7 | Saved operational records; reopen with a fresh context/process; disconnect API/database | Correct records remain; failures do not claim success; drafts remain available | Fresh-context integration assertions; client/UI failure tests; published-process smoke check and manual release checklist |
| A8 | Linked consumer submits and office reviews/resolves; another consumer attempts access | Shared data follows the workflow; account ownership and role permissions hold | Consumer_submission_enters_desktop_processing_with_server_recorded_identity; Consumer_rls_hides_other_accounts_and_prevents_profile_escalation; real mobile/shared-environment round trip pending |

## Controlled data and execution

PostgreSQL tests use a loopback server and create a unique `waterdistrict_test_...` database for each test, apply the source-contract baseline and actual EF migration, then drop that test database. They never point at Supabase or damage operational data. The baseline reconstructs required tables from the consumer source; it is not a verified production schema export.

Set `WATERDISTRICT_TEST_POSTGRES` to a loopback PostgreSQL administration connection, then run `desktop/scripts/verify.ps1 -RequirePostgres`. Without that variable, relational tests explicitly skip and cannot establish database correctness. TRX output is written under `desktop/artifacts/test-results/`; UI previews are under the test output's `artifacts/ui/` directory.

Authentication tests use signed test JWTs and controlled profile services. API integration tests replace identity only within the test host and exercise actual PostgreSQL workflow processing. There is no production authentication bypass.

## Current limitations

The live Supabase connection, catalog, role constraints, grants, existing triggers and office-user provisioning remain unavailable. No live migration or operational changes have been applied. Instructor approval, member IDs and a real consumer/mobile-to-desktop demonstration remain pending. The release checklist records which checks must be repeated in that prepared environment.

## Executed results on 2026-11-25

| Check | Actual result |
|---|---|
| .NET solution build | Passed, zero warnings and zero errors |
| xUnit with PostgreSQL 17.12 on loopback | 55 passed, zero failed, zero skipped; includes API/database workflows, atomic rollback, concurrency, RLS, migration readiness and UI draft behavior |
| Flutter analysis on Dart 3.13.1 | No issues found |
| Flutter widget tests | 14 passed; count-response mocks, viewport setup and existing peso/visible-total expectations reconciled with the actual UI |
| Self-contained win-x64 publish | Desktop, API and Database tool published successfully |
| Packaged local initialization | Empty waterdistrict_dev_release database initialized and migrated; second --migrate succeeded without reset or duplicate data |
| Generated idempotent SQL | Applied to separate local source-contract baseline and applied again successfully |
| Packaged process check outside Visual Studio | Desktop window opened; API /health=200; configured /health/ready=200; anonymous session/concern/ticket requests=401 |
| Dependency failure checks | Unconfigured readiness=503 and client/API failure tests retain drafts without fabricated success |
| Live Supabase end-to-end release check | Pending authorized PostgreSQL catalog/configuration and office/consumer demonstration identities |

Verification evidence is local under desktop/artifacts/test-results/verification.trx and the release's smoke-results.json/api-smoke.log. UI previews use controlled fictional records. The current release folder is desktop/artifacts/release/20261125-011647; release output is ignored by Git and can be reproduced with publish.ps1.

Flutter dependencies resolved without changing package versions after lowering the minimum Dart patch requirement from 3.13.5 to the installed 3.13.1. The Windows Flutter plugin-link step still requests Developer Mode; no system setting was changed. Analysis and all widget tests completed with the resolved packages using --no-pub. A native Flutter platform build remains a separate consumer deployment check.

## Updated mobile Admin adaptation

The main/f4848dc comparison and new office-module verification are documented in admin-staff-mobile-comparison.md. Existing local PostgreSQL workflow tests remain unchanged; new module tests use controlled Data API responses and do not claim live RLS/data verification. Read-only live schema inspection was attempted, but VerifyFull certificate validation failed before PostgreSQL password verification. No live database changes were made.

Final Admin adaptation verification: solution build succeeded with zero warnings/errors; 77 .NET tests passed with local PostgreSQL configured, zero failures and zero skipped tests. Rendered account, bill, payment and announcement screens were generated; payment and announcement layouts were visually inspected. Consumer Flutter source was unchanged in this adaptation, so the earlier Flutter verification remains applicable to this branch's unchanged consumer source rather than to newly fetched main UI changes.

The updated Windows x64 release at desktop/artifacts/release/20261125-015301 was smoke-checked: native desktop opened, local configured API readiness returned 200, and all five new office endpoints rejected anonymous access with 401. Supabase database connectivity remains blocked at TLS certificate verification.

## Verified live schema follow-up

Database authentication and VerifyFull certificate validation now succeed. The live public schema was inspected/exported read-only and used as a local DDL/grants fixture with generated test identities. No operational production data was copied into tests. See live-database-integration.md for Staff/profile gaps, title/subject corrections, the 83-test verification and the migration impact on direct mobile Admin edits. Live migration remains pending the shared-workflow decision.

## Approved live deployment

The user selected desktop workflow rules (option 1). A private public-schema/data backup was created and its contents verified before applying RepairWorkflow and StaffDirectoryAccess to Supabase. Both migrations succeeded. Read-only post-deployment checks confirmed that all original table counts and all original consumer policies are preserved, while Staff support, the Admin directory policy and ticket history are present. No production test identities or operational records were created. Actual office-user sign-in remains a separate check with real credentials.

Post-deployment runtime verification: the new self-contained release's API returned HTTP 200 from /health/ready against live Supabase; all protected route groups returned 401 anonymously, and the native desktop window opened. The local launcher reads private settings from the ignored source configuration rather than embedding passwords in the package. Real application-user sign-in and a live operational demonstration remain unverified.
