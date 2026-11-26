# App-to-web update comparison

Source audit: 26 November 2026, Asia/Manila. Compared the published web baseline `49abbfd` with upstream main `dbdc382` (including `e560a93` concern locations/service UI and `7d089af` standalone desktop). Main was merged into `feature/web-platform-parity` at `7cba6e1` before the compatible web update.

## Changes carried into the web client

| Upstream change | Updated web behavior |
|---|---|
| Optional concern pin and landmark | Consumer and office intake offer a Maramag-centered map, manual coordinates, explicit GPS, confirm/cancel/remove, and a 300-character landmark. Location stays in memory with an unsaved report. Saved consumer/office maps are read-only. |
| Location database columns | Consumer reads and inserts use `latitude`, `longitude`, `location_note` under the current user's RLS. Office contracts/domain/EF mapping carry the same fields through intake, reload, review and resolution. Validation checks coordinate pairs, finite values, ranges and landmark length. UUID retries compare locations too. |
| Old API compatibility | A pinned office report first checks authenticated `GET /api/workflow/capabilities`. An older/unreachable API receives no report write and the draft remains available. Reports without a pin retain the old optional-field contract. |
| Signed-in service UI | Scoped utility palette: blue #1A4FD6, background #F6F9FC, ink #172536, border #E1E6EB, metadata #526077. Compact white cards, neutral icons, 48px controls, logo/dashboard header, responsive columns, persistent navigation labels and a peso font fallback. Authentication and the original landing page keep their designs. |
| Consumer dashboard | Balance/next due date, Bills/Report issue/Repairs shortcuts, exact recent-concern link, and the latest published notice by update date. No older interruption is promoted above a newer published notice; no advisory makes no service-availability claim. |
| Progressive detail | Bill/payment/notice/concern/repair supporting details use disclosure controls. Account profile and linked service details share one card with compact help. Office history and mutation rules remain available. |
| Payment instructions | Unpaid bills show district guidance, the actual account/bill references, amount and due date, and receipt/verification guidance. No invented payment channels or online checkout. |
| Existing landing/session behavior | `/` remains the original landing; demo opens `/app`, restoring an active workspace or clean `/login` without the misleading session-ended message. |

## Role and architecture differences found

The shared Flutter login in `lib/main.dart` still explicitly accepts only `admin` and `client` profiles. It does not currently admit `staff`. The existing web client already accepts active Admin, Staff and Consumer identities from the shared Supabase project. Staff can receive/review concerns and update only assigned repairs; Admin-only billing, account, payment, publication, directory and dispatch boundaries remain enforced by the web handlers and original ASP.NET API.

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
