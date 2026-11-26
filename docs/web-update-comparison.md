# App-to-web update comparison

## Latest synchronization: client registration and approval

Compared published web `2e2d52a` / branch `98caf96` with new upstream main `c44b8bf` (registration feature `8190ca5`). Main includes the billing/desktop-separation work already merged through PRs #3 and #4. It was integrated by fast-forward, preserving the shared source and its existing web implementation.

| New app behavior | Current web behavior |
|---|---|
| Client signup | Create account from sign-in; full name, service address, email and matching passwords. Details go to Supabase Auth and the shared pending-registration trigger. No user-supplied role or account number is trusted. |
| Pending approval | Pending clients receive approval guidance and no workspace access. Email confirmation remains necessary. Signup success clears the form and gives confirmation/approval instructions. |
| Admin approval | Service accounts shows pending registrations with saved name, email, address and confirmation status. Approval invokes the existing atomic Supabase function; its returned MWD number is displayed immediately and the account/pending lists refresh. |
| Automatic account assignment | Approval creates and links one new sequential service account, activates the client profile and records the approving Admin. Retry/concurrent approvals do not duplicate the account. Manual account creation is removed. |
| Refreshed account list | Pending requests and service accounts poll every 30 seconds while visible and refresh on focus; manual Refresh is retained. |
| Role boundaries | Staff and Consumers cannot list/approve registrations. Existing identities, role checks, links, billing, payments, maps and repair workflow remain in place. |

Additional web refinements: switching login/signup/recovery clears password fields and hides passwords, matching mobile; missing registration setup reports the registration requirement; the approval message displays its returned account number even if that account falls outside the loaded list limit.

The live anonymous `client_registration_approval_available()` probe returned HTTP 200 / `true`; the upstream registration setup is available. No live signup, email, approval, account or role mutation was performed. Existing Supabase Auth redirect/email settings remain required. The new client registration source is preserved; the already published APK is not rebuilt by this web-only synchronization. See [registration behavior](client-registration.md) and [verification evidence](web-verification.md).

The sections below describe the previous mobile/UI synchronization.

**Architecture follow-up:** the current website no longer needs the hosted API described in this historical comparison. Office records use caller-scoped Supabase; atomic repair functions and Staff policies are in [web Supabase office setup](web-supabase-office.md). Desktop source remains separate.

Source audit: 26 November 2026, Asia/Manila. Compared the published web baseline `49abbfd` with upstream main `3336607` (including `e560a93` concern locations/service UI and `7d089af` standalone desktop). Main was merged first at `7cba6e1`; a second fetch found the newly pushed midnight/aqua update `3336607`, merged at `b375354` before final publication.

## Changes carried into the web client

| Upstream change | Updated web behavior |
|---|---|
| Optional concern pin and landmark | Consumer and office intake offer a Maramag-centered map, manual coordinates, explicit GPS, confirm/cancel/remove, and a 300-character landmark. Location stays in memory with an unsaved report. Saved consumer/office maps are read-only. |
| Location database columns | Consumer reads and inserts use `latitude`, `longitude`, `location_note` under the current user's RLS. Office contracts/domain/EF mapping carry the same fields through intake, reload, review and resolution. Validation checks coordinate pairs, finite values, ranges and landmark length. UUID retries compare locations too. |
| Old API compatibility | A pinned office report first checks authenticated `GET /api/workflow/capabilities`. An older/unreachable API receives no report write and the draft remains available. Reports without a pin retain the old optional-field contract. |
| Signed-in service UI | Latest midnight/aqua palette: navy #081B3D, blue #0648D7, aqua #CDF7FA, background #F8FAFD, ink #0C142B, metadata #626C82 and border #E0E6EF. Rounded white cards, 48px controls, a navy balance/office overview with ripple artwork, aqua icon surfaces, responsive columns, a peso fallback font and a mobile navigation dock. Auth artwork and workspace loading/error states share this branding; the original public landing page remains intact. |
| Consumer dashboard | Balance/next due date, Bills/Report issue/Repairs shortcuts, exact recent-concern link, and the latest published notice by update date. The separate service-advisory card can open the latest interruption while Latest notice still shows the newest published notice. Absence of an interruption is explicitly not a live service-status claim. |
| Progressive detail | Bill/payment/notice/concern/repair supporting details use disclosure controls. Account profile and linked service details share one card with compact help. Office history and mutation rules remain available. |
| Payment instructions | Unpaid bills show district guidance, the actual account/bill references, amount and due date, and receipt/verification guidance. No invented payment channels or online checkout. |
| Recent verified-payment activity | Server-scoped linked-account lookup returns the latest saved payment and opens that bill's history. Empty records show No recent transactions; loading/failure never claims an empty ledger. No invented transaction feed. |
| Existing landing/session behavior | `/` remains the original landing; demo opens `/app`, restoring an active workspace or clean `/login` without the misleading session-ended message. |

## Role and architecture differences found

The shared Flutter login in `lib/main.dart` at `3336607` still explicitly accepts only `admin` and `client` profiles. It does not currently admit `staff`. The existing web client already accepts active Admin, Staff and Consumer identities from the shared Supabase project. Staff can receive/review concerns and update only assigned repairs; Admin-only billing, account, payment, publication, directory and dispatch boundaries remain enforced by the web handlers and original ASP.NET API.

The newly added `desktop/WaterDistrictConnect` workspace is explicitly a separate standalone prototype with its own ASP.NET Identity/local database and fictional demo seed. Its extra roles/concern statuses and disabled phase-two repair flow are not the shared operational contract. Its source is preserved through the merge; its demo users/schema and permissive transitions are not installed into the shared web application. The shared API remains `desktop/src/WaterDistrict.Api` and the tested solution remains `desktop/WaterDistrict.sln`.

## Deployment prerequisites and limits

1. Publish this Next.js frontend to the existing Vercel project with Root Directory `web`. The root landing and clean demo sign-in are part of the same deployment.
2. An authorized database operator must verify/apply upstream `database/add_concern_locations.sql` to the existing Supabase database if it has not already been applied. It adds only nullable location columns, the coordinate-pair/range constraint and column-specific INSERT grants; existing account/RLS policies remain authoritative. If columns already exist but location inserts are denied, review `database/fix_concern_location_permissions.sql`. No operational SQL was run by this update. These scripts were applied twice only in a disposable local schema test to confirm idempotence and consumer isolation.
3. Deploy the updated original ASP.NET API and configure its public HTTPS URL as `WATERDISTRICT_API_URL`. It remains unhosted according to the user. Location support is advertised by the new authenticated capability endpoint; no-location desktop calls remain backward compatible. The original desktop UI is not restyled by this web task.
4. Map tiles default to the same OpenStreetMap source as mobile, using HTTPS, visible attribution and normal browser caching/referrer behavior. No offline download/prefetch is implemented. For public capacity needs, configure a suitable compatible tile provider through `NEXT_PUBLIC_MAP_TILE_URL` and `NEXT_PUBLIC_MAP_TILE_ATTRIBUTION` and rebuild. GPS is available only on secure contexts and only on request; denial/timeout leaves manual selection usable.
5. Live-user sign-in, email recovery, database grants and cross-platform operational acceptance require authorized accounts and the hosted API. Local fixture success does not establish these external conditions.

## Verification

See [web-verification.md](web-verification.md) for executed web, browser, Flutter and isolated PostgreSQL results. Fixtures contain test-only QA identities/data and are excluded from Vercel deployments. No live customer record or production demo account was created.

## Implementation references

- [Leaflet 1.9.4 reference](https://leafletjs.com/reference-1.9.4.html)
- [OpenStreetMap tile policy](https://operations.osmfoundation.org/policies/tiles/)
- [Browser Geolocation API](https://developer.mozilla.org/en-US/docs/Web/API/Geolocation_API)
