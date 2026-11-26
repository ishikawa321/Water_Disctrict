# Web and API deployment

## Vercel project

Published frontend: https://maramag-waterdistrict-web.vercel.app. It uses the existing Supabase project. The office API remains an external hosting dependency; publishing the frontend alone does not connect office operations.

The Next.js application lives at `web/`. Select the Next.js framework preset and Node 24, with **Root Directory `web`**. Use `npm ci`, `npm run build`, and the framework's default output directory. Do not deploy the Flutter `web/index.html` as the Next.js app.

Set these production environment variables in Vercel:

```text
NEXT_PUBLIC_SUPABASE_URL=https://kaeespcylucvsazfdaks.supabase.co
NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=<existing public publishable key>
WATERDISTRICT_API_URL=https://<your-separately-hosted-api>
NEXT_PUBLIC_LANDING_URL=https://<your-landing-site>   # optional
```

No database connection or service-role key belongs in Vercel. Rebuild after changing public variables; redeploy after changing server runtime variables. A missing API URL produces a truthful service configuration error in office modules, rather than fake data.

For CLI deployment, link the Vercel project from the **repository root**, retain its `web` Root Directory setting, then run `npx vercel deploy --prod --local-config web/vercel.json`. The explicit local config applies the web install/build commands and Singapore function region to root-level CLI deployments. The root `.vercelignore` excludes mobile, desktop, local settings and isolated tests. For Git deployment, connect the repository in Vercel and select `feature/web-platform-parity` as the Production Branch after connecting. Do not change your existing mobile/desktop integration branch just to deploy the website.

## Supabase authentication

Keep all existing mobile and desktop Auth configuration. In Authentication → URL Configuration, add these exact web redirect destinations alongside existing entries:

```text
https://maramag-waterdistrict-web.vercel.app/auth/callback
https://maramag-waterdistrict-web.vercel.app/auth/callback?next=/reset-password
http://localhost:3000/auth/callback
http://localhost:3000/auth/callback?next=/reset-password
```

If using preview deployments, allow only your project's preview URLs using Supabase's documented matching syntax. Keep the recovery email template's `{{ .ConfirmationURL }}` link. Supabase must verify the link before redirecting. Configure SMTP for real recipients as required by your project; do not claim email delivery based on local tests. Recovery requests and emails must be opened in the same browser because the web flow uses PKCE.

Email/password sign-in uses the existing verified identities. Account links and active role profiles continue to be provisioned through authorized district processes, never through browser metadata or public office signup. Do not remove the applied repair/Staff migrations or weaken any RLS/column grants.

## Separately hosted ASP.NET API

Use a host that supports an ASP.NET Core 10 Linux service or Docker container behind HTTPS. The checked-in container definition builds the original API and its dependencies, with no Windows executables:

```powershell
# From repository root (requires Docker)
docker build -f desktop/Dockerfile.api -t waterdistrict-api .
```

Configure the API host's secret/environment settings, not a committed file:

| Name | Value |
|---|---|
| `ASPNETCORE_ENVIRONMENT` | `Production` |
| `ASPNETCORE_HTTP_PORTS` | `8080` (or the host's internal service port) |
| `TZ` | `Asia/Manila`, preserving the API's existing local payment-date validation |
| `AllowedHosts` | Your API hostname, with other required internal hostnames separated by semicolons |
| `Supabase__Url` | `https://kaeespcylucvsazfdaks.supabase.co` |
| `Supabase__PublishableKey` | Existing public publishable key |
| `ConnectionStrings__WaterDistrict` | Existing shared database/pooler connection, stored only as an API-host secret |

Retain `SSL Mode=VerifyFull` and the appropriate trusted project CA certificate, as required by the existing connection. Mount the CA certificate at the path referenced by `Root Certificate` if it is not in the OS trust store. Do not disable certificate validation, log the connection string, copy private appsettings, or create a replacement operational database.

The Docker build is rooted at the repository root and starts `WaterDistrict.Api.dll` as the non-root .NET `app` user. Configure HTTPS at the hosting ingress. No migration runs on application startup. Use `/health` for process health and `/health/ready` to verify the configured existing schema/migrations and database reachability.

The website calls this API through its authenticated Next.js server handlers, so browser-to-API CORS changes are unnecessary. If you later deliberately switch to direct browser calls, add a reviewed explicit origin allowlist on the API. Do not enable wildcard credentialed CORS.

Deploy the updated API from this branch: `/api/office/payments?billId=<UUID>` now filters bill history **before** the established 1,000-row limit. Existing desktop calls without that optional parameter retain their contract. All dispatch, assignment, status transitions, append-only history, actor stamping and concurrency rules remain in the original server.

## Final live acceptance

The original local landing page's header demo link, hero button and final Explore button now navigate to the published web URL in `config.js`. Its illustrative tour remains separate. Redeploy that independent static folder if a previously hosted copy also needs the new links.

Use authorized demonstration accounts and isolated demonstration records. Do not experiment with customer records.

1. Load `/login`, then refresh a direct `/portal/bills` or `/office/concerns` URL. Anonymous API/data requests must return 401.
2. Sign in as a linked consumer. Verify account information, bill original/paid/balance, bill-specific payment history, notices and password recovery.
3. Submit a demonstration concern. Refresh Desktop and the office website to verify the same saved row appears.
4. Admin reviews, dispatches once, and assigns an active Staff identity. Confirm duplicate dispatch and stale updates fail.
5. Assigned Staff records In progress and Resolved with required notes. Other Staff must be unable to view/update that ticket.
6. Refresh consumer web/mobile. The saved concern result and repair summary must agree. Verify verified payments and published notices agree across platforms; drafts remain private.
7. Revoke a demonstration profile/account link through an authorized process and refresh access. The website must clear sensitive records. Restore the authorized demonstration configuration afterward.

Local automated checks do not establish real-user live acceptance or email delivery. See `web-verification.md` for exact executed results and external dependencies.
