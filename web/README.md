# Water District Connect web application

Next.js and TypeScript web client sharing the existing Flutter app's Supabase Auth, active profiles, account links and PostgreSQL records. **The web no longer calls the desktop ASP.NET API.** Desktop source stays separately under `desktop/` and is excluded from Vercel.

The landing is first at `/`. Explore Demo opens `/app`, restoring an authorized workspace or clean `/login`. `/download` provides the verified signed Android APK; its fictional concept tour remains separate.

## Run and configure

Use Node 24. From `web/`: run `npm ci`, copy `.env.example` to `.env.local`, set the existing public Supabase URL/key, then `npm run dev`. Open http://localhost:3000 with an existing active Admin, Staff or Consumer identity. Clients can register with full name, service address, email and matching passwords. Admin approval assigns the service account number; email confirmation is also required to sign in. See [client registration](../docs/client-registration.md). Office roles and existing-account linking remain restricted.

| Variable | Purpose |
|---|---|
| `NEXT_PUBLIC_SUPABASE_URL` | Existing `https://kaeespcylucvsazfdaks.supabase.co` project |
| `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` | That project's public client key |
| `NEXT_PUBLIC_LANDING_URL` | Optional separate landing link |
| `NEXT_PUBLIC_MAP_TILE_URL`, `NEXT_PUBLIC_MAP_TILE_ATTRIBUTION` | Optional raster tiles and attribution |

No Render host, `WATERDISTRICT_API_URL`, database password or service-role key is needed by the web.

For automatic bill/payment numbers, per-account monthly billing, the 28th issuance schedule and daily simple interest, follow [billing setup](../docs/billing-automation.md). It requires the two billing SQL files in the existing project; frontend deployment does not install them. Billing reports the schedule's actual configured state.

An authorized operator must run [database/web-office-workflows.sql](../database/web-office-workflows.sql) once in the existing project's SQL Editor. See [Supabase office setup](../docs/web-supabase-office.md). Admin lists and existing repair details use existing RLS immediately. Staff access and atomic repair saves require the added policies/functions. Until installed, saves report the required setup and retain drafts. No migration runs during deployment.

## Data boundaries

- Supabase SSR cookies refresh through Next.js Proxy. Protected pages/handlers independently validate `auth.getUser()` and the active profile. Roles never come from editable metadata. Protected responses are private and uncached.
- Every data operation uses the signed-in caller's Supabase client and RLS. Admin-only billing, payments, directory and dispatch stay restricted. Staff see their own repair assignments. Consumers remain scoped to their current active linked account; only published notices are visible.
- Mutations require matching Origin/Host and JSON. Actor identities are stamped on the server and guarded in PostgreSQL. Atomic workflow functions lock records and compare `xmin`; existing triggers enforce transitions, assignment, append-only history and concern resolution.
- Access is rechecked on focus, visibility and every minute. Access loss clears sensitive data and memory drafts. Drafts survive form closing/navigation; reload/sign-out clears them. Concern retries reuse a UUID.
- Office lists retain the established 1,000 / 500 / 200 limits and labels; dashboard counts are exact. Consumer lists paginate and balances include all scoped verified payments with decimal-safe calculations.
- Optional pins/landmarks support explicit GPS, manual coordinates and confirmation. Saved maps are read-only; OpenStreetMap attribution stays visible, with no offline tile download.

## Landing and Android

The deployed landing snapshot is `public/landing/`. In the original workspace edit the adjacent static source, then run `npm run sync:landing` here. Standalone checkouts already include the snapshot. The existing native Flutter APK is hosted on GitHub Releases, identified by `src/lib/android-release.json`; private signing files and binary build outputs are excluded from Vercel. See [Android release](../docs/android-release.md).

## Verification

Run `npm run check` and `npm run test:browser`. Browser checks use isolated loopback Auth/Data fixtures and Chrome, disable the legacy API and assert zero desktop calls. The .NET suite also tests the SQL against disposable PostgreSQL and real local PostgREST when configured. Never supply a production test connection.

See [deployment](../docs/web-deployment.md), [feature parity](../docs/web-parity.md) and [verification evidence](../docs/web-verification.md). Brand assets and the DM Sans OFL license originate in the mobile app.
