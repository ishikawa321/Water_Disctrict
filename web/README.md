# Water District Connect web application

Next.js App Router and TypeScript web client for the existing Maramag Water District system. Uses the same Supabase Auth users, active profiles, account links and PostgreSQL records. Office operations call the existing ASP.NET Core API; workflow rules remain in that API and its database triggers.

The main URL shows the existing landing page first. Its primary demo actions open `/app`, which restores the user's authorized workspace or redirects to `/login`. Sign-in includes a link back to the landing page. The fictional concept tour remains a separate action in the landing preview.

The deployed landing snapshot lives in `public/landing/`. In this workspace, update the adjacent original `index.html`, `app.js`, `styles.css` and assets, then run `npm run sync:landing` from this directory before building/deploying. Standalone checkouts already contain the committed snapshot and do not need the original folder. Public landing assets and `/` load independently of authentication; protected app routes retain their access checks.

## Run locally

Use Node 24. From this directory:

```powershell
npm ci
Copy-Item .env.example .env.local
# Set the public publishable key and the separately hosted HTTPS API URL.
npm run dev
```

Open http://localhost:3000. Use an existing application identity with an active `admin`, `staff` or `client` profile. Clients can register using their full name, service address, email and matching passwords. Supabase saves pending signup details; Admin approval creates the numbered account and enables login after email confirmation; see [client registration](../docs/client-registration.md). Staff/Admin provisioning and linking an existing service account remain restricted to authorized district processes. The original Flutter web launcher files in this folder remain intact; Flutter's mobile/desktop targets are unchanged.

## Configuration

| Variable | Purpose |
|---|---|
| `NEXT_PUBLIC_SUPABASE_URL` | Existing `https://kaeespcylucvsazfdaks.supabase.co` project |
| `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` | Public publishable client key from that project |
| `WATERDISTRICT_API_URL` | Server-only origin of separately deployed ASP.NET Core API, without `/api` |
| `NEXT_PUBLIC_LANDING_URL` | Optional independently deployed landing-page link |

Never put service-role keys, database credentials or connection strings in this web project. The example contains placeholders. Missing API configuration produces an explicit connection error in the office workspace. Consumer services use Supabase directly from the Next.js server with the signed-in user's RLS permissions.

## Authentication and data boundaries

- `@supabase/ssr` stores/refreshes the session in cookies. The Next.js Proxy refreshes auth; each protected page and handler independently calls `auth.getUser()` and reads the active profile. Roles never come from browser input or editable metadata.
- Protected responses use `private, no-store`. Office forwarding accepts only the supported routes and methods, restricts Staff, and forwards the validated user's bearer token. The API independently validates the user/profile, assignee ownership, versions and transactions.
- Consumer handlers resolve the user's current active link, scope all account queries, and retain RLS. Payment history verifies the bill belongs to that account. Notice queries explicitly require `published=true`.
- Mutation requests require a matching browser Origin/Host and JSON content. Tokens are never returned by application endpoints or logged.
- Access is rechecked on focus, visibility change and every minute. Invalid sessions/profiles clear the visible workspace and memory drafts; account-link changes clear the account workspace. Data requests also enforce access independently of these UI checks.
- Drafts live only in the current signed-in browser memory, survive forms closing and client navigation, and clear on sign-out/access loss. A browser reload clears unsaved drafts. Concern retries reuse their UUID; ticket creation and version conflicts use existing API safeguards.
- Office lists retain the established 1,000 / 500 / 200 limits and label them. Consumer lists paginate 30 records at a time. Dashboard admin counts use the exact summary endpoint rather than a list's length.
- Consumer billing shows individual saved bill balances. The dashboard pages through all linked bills/payments to calculate the exact outstanding balance, bill count and next unpaid due date. It does not total a truncated district list. Consumer repair progress is the current saved personnel update; office staff can see chronological append-only history.

## Android download

The existing landing now offers Download for Android alongside Explore Demo. `/download` shows the signed universal APK's actual version/size, minimum Android version, SHA-256 and installation steps. The binary is hosted on GitHub Releases; `src/lib/android-release.json` identifies the verified artifact. APK/private signing/Flutter build outputs are excluded from Vercel uploads. See [Android release instructions](../docs/android-release.md).

The live Admin error is a missing separate office API, not a missing Supabase public key. [Prepared API hosting and connection steps](../docs/office-api-hosting.md) preserve the existing shared database and ASP.NET workflows.

## Latest app update

Concern intake now supports optional map pins and landmarks, with explicit GPS/manual selection, draft retention and read-only saved maps. The shared office API carries those fields and exposes an authenticated capability check so older APIs cannot silently discard a pin. Unpaid bills offer payment guidance using their actual account and bill references. Screens follow the latest mobile midnight/aqua palette, rounded cards, ripple balance/office surfaces and mobile navigation dock. Recent activity reflects the latest saved verified payment; an empty feed is shown only after a successful empty read. Workspace loading/errors and auth artwork use the same branding.

Review [the source comparison and deployment prerequisites](../docs/web-update-comparison.md). Verify upstream `database/add_concern_locations.sql` has been applied by an authorized operator before using pins against the shared database; this website does not run migrations. Office modules require the separately hosted updated API. Optional map tile provider variables are documented in `.env.example`. The default OpenStreetMap tiles retain visible attribution; GPS is requested only by the button and requires HTTPS.

## Checks

```powershell
npm run typecheck
npm run lint
npm test
npm run build
npm run test:browser
```

Browser tests start an isolated loopback Auth/Data API fixture and a separate Next.js dev server. They use the installed Chrome channel, make no production writes, and test the actual application authentication and handlers. Set up Chrome or change Playwright's channel to an installed browser if necessary. These tests complement the .NET PostgreSQL workflow/RLS tests; fixture tests alone do not prove live backend or SMTP configuration.

From the repository root, run the existing `.NET` suite with `WATERDISTRICT_TEST_POSTGRES` set to a disposable loopback PostgreSQL administration connection. Database tests explicitly skip without it. Do not supply the live Supabase connection to tests.

See [deployment instructions](../docs/web-deployment.md), [feature parity matrix](../docs/web-parity.md) and [verification evidence](../docs/web-verification.md).

## Official implementation references

- [Next.js authentication](https://nextjs.org/docs/app/guides/authentication)
- [Next.js Proxy](https://nextjs.org/docs/app/api-reference/file-conventions/proxy)
- [Supabase server-side clients](https://supabase.com/docs/guides/auth/server-side/creating-a-client)
- [Supabase redirect URLs](https://supabase.com/docs/guides/auth/redirect-urls)
- [Vercel monorepo root configuration](https://vercel.com/docs/monorepos)

Brand assets and the DM Sans OFL license are copied from the existing mobile application into `public/`.
