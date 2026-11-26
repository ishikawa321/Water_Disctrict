# Web verification evidence

## Staff role implementation

Implemented the six role choices confirmed by the owner on 27 November 2026. Staff receive/review concerns, see only assigned repair tickets/history, read bills/payments and confirm payments. Admin manages invitations/active access, financial settings, repair dispatch/assignment and final resolution. The common workflow adds Completed, leaving the concern unresolved until Admin confirms. Full setup is [staff-role.md](staff-role.md).

- All **105 .NET/PostgreSQL tests passed**, zero failures/skips. New role tests install the migration twice and verify Staff payment permission/actor/receipt numbers, denied bill/plan writes, account isolation, assigned-only repairs, denied Staff resolution, Completed history and Admin resolution. Invitation tests cover Admin-only issue, inactive pending profiles, email confirmation, ignored role metadata, no customer link, disabled access, non-reactivation and rejected forged/wrong-email/revoked tokens. The four role tests passed again after adding expired/reused-token cases.
- Real local PostgREST HTTP testing now installs the Staff upgrade, executes Completed then denied Staff resolution/accepted Admin resolution, creates an Admin invitation and verifies its public token-scoped preview. It preserves existing relation, `xmin`, count and isolation checks.
- All **42 Flutter tests passed** and analyzer reported no issues. Added mobile checks cover exact cents, Admin-only completion choices, failed-save note retention, assigned UUID filtering and clearing records on access disable. The existing Admin quick-action test now expects the new repair review workspace.
- All **21 browser workflows passed**, with the legacy API disabled and zero calls to it. New checks cover Admin-created invitation links, recipient signup, Staff financial access, denied Staff invitation/settings changes, disabling a live Staff workspace and Admin-only repair resolution. The Staff payment retry case passed after fixing its isolated fixture's old Admin-only mock rule.
- Web type checks, zero-warning lint, **70 unit/contract tests** and optimized build passed. A small effect/unused-import lint issue was corrected before this final run. Invitation passwords stay server-validated; the token is email-bound and the browser never supplies the assigned role.
- Signed universal Android 1.0.2 build 3 was built and its existing release certificate, package, architectures, version, minimum SDK and APK v2 signature verified. Artifact: 58,080,588 bytes, SHA-256 `f6e63e492c24a1385a206d247447e93ef6e26667abc5613d3aaa5c7d56d733a5`. No physical Android installation or real-user email delivery is claimed.
- Invitation acceptance and Android download browser checks passed again after the effect fix and release metadata update. The production build passed again with version 1.0.2 download metadata; the Admin invitation/access page screenshot was visually reviewed. The owned local PostgreSQL cluster was stopped.
- The owner reported running `database/staff-role.sql` successfully. Follow-up read-only probes confirmed the installed invitation function rejects an invalid token (`400/22023`) and the Staff directory rejects anonymous execution (`401/42501`). The agent used only the public key; no real employee invitation, production payment, role change or database migration was made by automated QA.

Publication: implementation `cda052d` is pushed to `feature/web-platform-parity`. GitHub release `android-v1.0.2` is public and contains only the signed APK and checksum; uploaded digests were verified. A fresh public download matched 58,080,588 bytes and SHA-256 `f6e63e492c24a1385a206d247447e93ef6e26667abc5613d3aaa5c7d56d733a5`, and its checksum sidecar matched. Vercel deployment `dpl_8q3JwZP8QkYq4Cq8Cc3jRrVeGnQW` is Ready in Singapore and aliased to https://maramag-waterdistrict-web.vercel.app. Production Chrome checks passed clean landing/demo login, the Staff acceptance page with absent/invalid tokens denied, five protected office endpoints returning uncached 401, the correct 1.0.2 APK link, 320-pixel invitation/download layouts and zero browser errors. Evidence is under ignored `web/test-results/production-staff/`. No actual live employee signup or physical device installation was performed.

## Registration synchronization from latest main

27 November 2026: integrated upstream main `c44b8bf` (client signup and Admin approval in `8190ca5`) into `feature/web-platform-parity` by fast-forward. This preserves the prior Supabase office/billing implementation, landing-first entry and APK download. See [the source-to-web comparison](web-update-comparison.md).

- Full .NET/PostgreSQL suite: **101 passed**, zero failed or skipped, using the isolated loopback database and official local PostgREST. Registration tests cover pending/inactive profiles, ignored editable roles/account numbers, denied self/Staff approval, private status reads, sequential/expanded account numbers, concurrent/idempotent approval and preservation of existing accounts/links.
- Full browser suite: **20 passed**, exercising signup validation/confirmation guidance at 320 pixels, password clearing on mode changes, pending login denial, Admin approval, returned account number, the approved client's new account link, and existing billing/interest/payments/repairs/landing/download workflows. All legacy desktop API calls remain disabled and their count is asserted zero.
- The approval browser case passed again after adding an injected save failure/retry and waiting for the new account's empty billing result. The saved registration stays available after failure, approval displays its returned number, and the approved client does not receive another account's seeded bill. Its QA screenshot was visually reviewed.
- Final `npm run check` passed 68 unit/contract tests, TypeScript, zero-warning lint and optimized production build after the approval-message/setup refinements. No package/dependency change was needed.
- Live read-only `client_registration_approval_available()` returned HTTP 200 and `true`, consistent with the upstream migration already installed. No live signup, approval, email, account provisioning or role mutation was performed. SMTP and real-user confirmation delivery are not claimed verified. The owned local PostgreSQL cluster was stopped after testing.

Publication: implementation `bba6350` is pushed to `feature/web-platform-parity`. Vercel deployment `dpl_J3f84wztNHybEuQo1LRJX11g6sKd` is Ready in Singapore (`sin1`) and aliased to https://maramag-waterdistrict-web.vercel.app. Production Chrome checks verified clean landing demo login, the new signup fields, cleared password on mode change, pending-approval guidance, a 320-pixel signup form without horizontal overflow, preserved APK download, and uncached anonymous 401 responses on registration, account, billing, repair and consumer endpoints. There were no browser page errors or POST requests. Evidence is under ignored `web/test-results/production-registration/`. Real email delivery and an actual live approval remain outside these read-only checks.

## Monthly billing and payment confirmation

Implemented 27 November 2026 on `feature/web-platform-parity`. Admin payment confirmation now uses an atomic Supabase operation with a generated 10-digit reference and UUID retry protection. Bill numbers are generated by PostgreSQL; the web form keeps only account, amount and due date. Per-account monthly plans issue on the 28th, due three calendar days later. Simple daily 1% interest is stored in the shared bill total, with an original/interest/paid/remaining breakdown for the web. Existing unpaid bills are included from their original due date, as explicitly requested; settled bills remain closed.

- Full .NET suite: 94 passed, zero failed/skipped, against disposable PostgreSQL 18 and official local PostgREST. Four billing integration tests cover generated numbers, retry conflicts, Admin-only confirmation, legacy direct inserts with Manila dates, overpayment, concurrent full-payment attempts, monthly catch-up/uniqueness, period boundaries, partial configuration, simple interest and full-payment freeze. After the schedule-status and same-day-plan refinements, all four billing tests passed again, including leap-year due dates and immediate issuance when enabled on the 28th.
- Existing full 17-workflow browser suite passed against the updated billing fixture, with the old API disabled and zero calls to it. Two targeted workflows then passed for monthly settings, generated confirmation references, failed-save draft retention, consumer settlement/interest display and existing Admin create flows: 18 distinct workflows exercised across those runs.
- Final `npm run check` passed: 59 unit/contract tests, TypeScript, zero-warning lint and optimized production build. Unit additions cover month/leap/year due-date rollover, generated bill numbers, caller-independent confirmation references, and safe missing-migration errors. The Consumer/confirmation browser case passed again after waiting for the bill-page navigation and aligning the saved QA due date with its overdue days.
- Visual checks use isolated QA amounts and saved records, never customer payments. Existing Flutter source/APK is unchanged; its `amount_due` reads receive the stored interest-inclusive total on refresh. No physical mobile acceptance or real-user payment is claimed.
- **Production activation still requires** the owner to apply `database/billing-automation.sql`, then `database/billing-schedule.sql`. Windows local PostgreSQL does not provide Supabase's Cron extension; the core job body is tested, while actual scheduled execution must be verified in Supabase Cron after setup. See [billing setup and exact rules](billing-automation.md).

Publication: implementation `2e2d52a` is pushed. Deployment `dpl_DZ6BMoJ2Wxjt4NgezEcKAciqMN27` is Ready in Singapore and confirmed through https://maramag-waterdistrict-web.vercel.app. A production Chrome check passed clean demo sign-in, the preserved APK download link, 320-pixel login layout, and uncached 401 responses on billing status, plans, bill, payment and consumer-bill endpoints, with zero page errors. Evidence is in ignored `web/test-results/production-billing/`. Both public SQL downloads matched the tested commit. A read-only anonymous function probe returned `401/42501` for `wd_billing_status`, confirming the function is present and anonymous access is denied; this does not establish the job's enabled state or a successful scheduled run. No real-user payment or production migration was executed by this agent. The owned local database was stopped.

## Desktop separation follow-up

The office handler now reads and writes the existing Supabase Data API with the validated caller session. The obsolete API URL is ignored and the old desktop service error no longer exists in application source. Desktop source remains separate and excluded from Vercel. Staff policies and atomic workflow functions are in `database/web-office-workflows.sql`; production installation requires an authorized Supabase operator and is not claimed completed by frontend deployment.

- All 90 .NET/PostgreSQL tests passed, zero failed or skipped. New tests install the SQL twice, enforce role/account isolation, preserve versions and history, reject invalid assignment, serialize concurrent dispatch and roll back after a controlled trigger failure.
- An official local PostgREST 16.6 process exercised actual HTTP calls against a disposable verified-schema database: authenticated intake/review/dispatch/assignment/progress, system `xmin`, nested relations, exact HEAD counts, history author names and consumer/Staff isolation. A targeted follow-up also passed both matching and empty nested account-number search filters.
- All 17 Chrome browser workflows passed with zero calls to the disabled desktop API. The screenshot regression loads saved repairs and real stored history even before workflow installation, finds tickets by account number, and prevents Staff reviewing a concern already dispatched to someone else. Existing landing, APK download, clean demo login, billing, office writes, pinned drafts, sequential repair resolution and 320-pixel layouts remain covered.
- Visual inspection of `independent-office-repairs.png` confirmed the saved repair list and chronological history render without the old service banner, using isolated QA records.
- Final `npm run check` passed after the search refinement: landing JavaScript checks, generated route types, TypeScript, zero-warning ESLint, all 50 unit/contract tests and optimized production build.
- No operational record, production policy, role or migration was changed by these checks. The shared project still needs [one-time SQL setup](web-supabase-office.md) for Staff access and atomic repair saves. No private connection string or service-role key is used in Vercel.

The sections below describe prior releases and their historical API dependency.

Publication: source `deca5f4` is pushed to `feature/web-platform-parity`. Vercel deployment `dpl_FcwkjWanjgnN7tRHVa8pdSEUhxjG` is Ready in Singapore (`sin1`), confirmed through the canonical https://maramag-waterdistrict-web.vercel.app alias. A production Chrome check verified all three landing demo buttons reach clean login, the existing signed APK link remains correct, four protected data endpoints return uncached 401 responses, the 320-pixel login fits, and no page errors occur. Evidence is under ignored `web/test-results/production-supabase-office/`. No real-user login or operational writes were performed.

A read-only production function probe returned `404/PGRST202` for `wd_web_is_staff`, confirming setup was still absent at publication. The public raw SQL download matched the tested committed file. An authorized operator must run it in the existing project before Staff access and atomic repair saves can be accepted live; frontend publication alone does not install it.

Executed 26 November 2026 (Asia/Manila), on `feature/web-platform-parity` based on desktop `68bc1590`. This file records current checks separately from the repository's historical deployment notes.

## Android download follow-up

A private-key-signed universal Android APK 1.0.1 (build 2) was built from the Flutter source. Android Build Tools verified the package, friendly label, API 24 minimum, non-debuggable build, ARM32/ARM64/x86-64 contents and APK v2 release signature. Artifact size is 57,785,128 bytes; SHA-256 and certificate fingerprint are recorded in `web/src/lib/android-release.json`. No physical Android device was connected; device installation is not claimed.

The original adjacent landing and integrated snapshot add two Android download links while preserving all demo/tour actions. A public `/download` page provides install instructions and the verified immutable GitHub Release asset URL. `npm run check` passed (TypeScript, zero-warning lint, 42 tests and production build). All 16 browser workflows passed, including the two landing downloads, artifact URL/checksum, browser download behavior, 320-pixel layout and returning to clean web sign-in. Two backend-origin validation tests reject the supplied Supabase REST URL as an ASP.NET API and reject insecure/credential-bearing/malformed origins.

`render.yaml` and the verified connection script are prepared for the shared API. No Render account or private database connection is currently connected, and the supplied Supabase data URL does not supply that separate service. The live Admin connection is not claimed fixed. See [office API hosting](office-api-hosting.md) and [APK release](android-release.md).

Publication verified: GitHub release `android-v1.0.1` is public, targets source commit `d984d95`, and contains only the signed APK and checksum. A fresh public APK download matched the recorded byte size and SHA-256. Vercel deployment `dpl_3kFPPJvvADynFfiKR1K6GKiwU52f` is Ready in Singapore and aliased to the existing site. A production Chrome check verified both landing download links, `/download`, the correct immutable APK asset URL, 320-pixel layout, return navigation, preserved clean demo sign-in and anonymous office denial, with zero page errors. Evidence is under ignored `web/test-results/production-apk/`.

## Latest app synchronization

Compared and merged main `dbdc382` first, then detected and merged freshly pushed `3336607` at `b375354` before publication. Detailed scope and prerequisites are in [web-update-comparison.md](web-update-comparison.md).

- `npm run check`: landing JavaScript syntax, route generation, TypeScript, zero-warning ESLint, unit/contract tests and the optimized Next.js build passed.
- Web unit/contract suite: 42 tests in six files passed, including optional-location validation, server-stamped consumer identity, mismatched retry rejection, and a capability handshake that blocks pinned office writes to an older API.
- Full browser suite: 15 Chrome workflows passed after the midnight/aqua update. Added pin confirmation/cancellation/removal, draft retention after a failed save, saved read-only map, old API refusal followed by supported office intake/review, actual bill/account payment references, newest published notice selection, explicit GPS success/denial/timeout, editable GPS selection, tile-failure retry preserving the pin, and 390-pixel map/dialog controls. Recent activity correctly switches between a saved verified payment and a successful empty result; bill-specific navigation and the role-scoped mobile dock work. Existing 320-pixel form/navigation checks still pass. A separate computed-text-size doubling check at 390 pixels verified form/navigation wrapping without horizontal document overflow; this does not claim native browser zoom testing.
- Original shared .NET solution: 87 tests passed, zero failures/skips against disposable loopback PostgreSQL 18 databases. New tests cover durable coordinates/landmark through review, idempotency, invalid pairs, authenticated API capability and field transport through resolution. Upstream location SQL was applied twice to a disposable copy of the verified public schema; an owned consumer pin succeeds, other-account reads/writes remain blocked, and an incomplete coordinate pair is rejected.
- Flutter source at final main `3336607`: `flutter analyze` found no issues and all 37 tests passed. The final shared mobile source is unchanged by this web task. Generated platform registrants were restored after verification.
- Visual review: consumer dashboard and mobile concern/location-picker screenshots use isolated QA records. The midnight/aqua palette, rounded disclosure cards, ripple balance/office surfaces, official logo, mobile dock and peso glyph render. Auth and branded loading use the latest theme; the original landing keeps its design.
- No live operational record, grant, migration, account or role was changed. The local test cluster was stopped after verification. Office production acceptance remains blocked by the unhosted API and operational location-grant verification.

Production publication: deployment `dpl_AGBWKZdujDo1yHiBnGULmyJUw2ZX` is Ready and aliased to https://maramag-waterdistrict-web.vercel.app. The source includes upstream `3336607`, web implementation `26ccd5d`, and artifact exclusions `ed46d5c`. Vercel inspection confirmed Singapore (`sin1`) functions. Flutter build/cache/test artifacts are excluded from the upload.

A Chrome check against the public production alias verified all three original landing demo actions reach clean `/login`, Back to the website returns to `/`, midnight auth styling renders, the peso font returns HTTP 200, and a 320-pixel login fits without horizontal overflow. Anonymous session, recent-activity, concern and office-capability endpoints return HTTP 401 with no-store headers. No browser page errors occurred. Screenshots and the JSON result are saved under ignored `web/test-results/production-smoke/`; no real-user sign-in or customer write was performed.

The historical checks below describe earlier web releases.

## Landing-first follow-up

The existing adjacent landing page is now included in the same Vercel deployment at `/`, with primary demo actions opening `/app`. This entry restores an authorized workspace or redirects to sign-in; sign-in links back to the landing page. The static snapshot preserves the original design, assets and fictional concept tour. Browser checks passed for all three demo actions, returning to the landing page, asset loading, signed-in workspace restoration and anonymous protected-route denial (3 targeted cases). Landing JavaScript checks, route type generation, TypeScript, zero-warning lint, all 26 unit/contract tests and the production build passed. No backend or database code changed in this follow-up.

## Executed checks

| Check | Result |
|---|---|
| Node / framework | Node 24.14.0; Next.js 16.4.6; React 19.3.1; versions locked in web/package-lock.json |
| `npm run check` | Passed: route type generation, TypeScript, ESLint with zero warnings, 26 unit/contract tests in four files, and optimized production build |
| Browser suite | All 8 Chrome workflows passed; no production requests or records used |
| Final visual spacing check | Consumer and 320-pixel mobile browser cases passed again after the final spacing adjustment |
| `.NET` solution tests | All 84 passed, zero failed and zero skipped, using an isolated PostgreSQL 18 loopback cluster on port 55439 |
| Release API publish | `dotnet publish ...WaterDistrict.Api.csproj -c Release` succeeded; no private appsettings.Local.json was packaged |
| Source preservation | Original Flutter `lib/` and desktop UI source unchanged; Flutter browser launcher/manifest/icons retained |
| Deployment inputs | Vercel dry run verified the Next.js source libraries are included and ignored settings, .env files, local test database, desktop binaries and browser fixtures are excluded |

The PostgreSQL test helper creates and drops uniquely named disposable databases using the existing schema fixture and reviewed migrations. A separate local cluster was prepared for these checks; the existing Windows PostgreSQL service and Supabase operational database were not reset or migrated. The initial test run explicitly skipped relational tests without configuration; after preparing the local cluster and its fixture-required `postgres` role, the final full run passed with no skips.

## Browser coverage

1. Anonymous protected-page redirects and 401 responses from protected data routes.
2. Consumer linked bills, verified bill-specific payments, private draft exclusion, failed-save draft retention, retry with the same concern UUID, and confirmed saved results.
3. Staff navigation and server-side denial of Admin reads/dispatch, including a direct Admin URL.
4. Stale concern review rejection with retained response, explicit version reload, Admin review/dispatch/assignment, assigned Staff progress/resolution, and four chronological history events.
5. Revoked profile access clears the visible workspace and redirects to sign-in.
6. Admin creates an account, bill, verified payment and published interruption notice; reopening and saving a notice updates its existing record; starting another notice opens an empty draft; directory records load.
7. Unlinked consumers receive guidance and cannot see bill records.
8. Navigation and a usable concern form at 320 × 640, with no horizontal document overflow.

Browser fixtures are a standalone loopback process under `web/tests/browser/`; no production auth bypass or mock-data switch exists in the application. Their simulated workflow responses exercise the web client's contract, while the existing .NET/PostgreSQL suite establishes server transition, assignment ownership, duplicate-ticket, rollback, concurrency, append-only history and RLS behavior.

Unit/contract checks additionally cover ignored editable role metadata, disabled/missing profiles, expired sessions versus dependency outages, consumer account/bill scoping, server-derived actor/account identity, published-only notices, positive two-decimal amounts, invalid date-only fields, exact-cent calculations, Origin/Host validation, blocked arbitrary upstream paths, and exact summary totals beyond the first 500 bills. Related ticket decoding supports both object and array relationship shapes.

Screenshots use clearly isolated `QA` fixtures and are generated into ignored `web/test-results/`. Both desktop and narrow mobile layouts were visually inspected. They are verification artifacts, not screenshots of real customer accounts.

## Live environment limitations

The published frontend at https://maramag-waterdistrict-web.vercel.app returned HTTP 200 for sign-in. Anonymous session, consumer and office API requests returned 401 with no-store headers. A production Chrome check confirmed a direct protected `/portal/bills` URL reaches sign-in (Next.js may stream this redirect in an HTTP 200 page). All three local landing demo actions were browser-checked against the deployed URL; the separate fictional tour still opens.

- The user confirmed the ASP.NET API is not hosted. Office functionality requires that separately hosted HTTPS API and the API host's private existing-database configuration. The Dockerfile and setup instructions are provided; the container image itself was not built because Docker is unavailable here.
- Vercel credentials were available. The new project's `web` root, Next.js framework, Node 24 and public Supabase production/preview variables were configured. Automatic GitHub repository linking was rejected by the Vercel integration; CLI publication remains available.
- Supabase management and API hosting integrations were discovered but were not connected at verification time. The app does not change Auth site/redirect allowlists, SMTP, profiles, roles or account links automatically.
- Actual application-user sign-in, email delivery/recovery, cross-platform live data agreement, and API readiness over a public HTTPS address remain unverified. No live customer writes or production demonstration records were created.

Use the live acceptance sequence in [web-deployment.md](web-deployment.md) after those external connections are configured. A deployed sign-in page is not proof that the unhosted office API works.
