# Web verification evidence

Executed 26 November 2026 (Asia/Manila), on `feature/web-platform-parity` based on desktop `68bc1590`. This file records current checks separately from the repository's historical deployment notes.

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
