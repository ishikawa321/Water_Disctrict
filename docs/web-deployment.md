# Web deployment

Published frontend: https://maramag-waterdistrict-web.vercel.app. Web and mobile share the existing Supabase project directly. Desktop ASP.NET hosting is no longer a web dependency; its source stays separately under `desktop/`.

## Supabase setup

For monthly bills and confirmed payments, also apply [billing setup](billing-automation.md): the atomic billing SQL first, then its Cron schedule. This applies the requested retroactive overdue interest to existing unpaid bills. No new database or hosted API is involved.

Follow [one-time office setup](web-supabase-office.md) for Staff access and atomic repair saves. An authorized operator runs `database/web-office-workflows.sql` in the existing project's SQL Editor. No migration runs on Vercel. No Render account, replacement database, private PostgreSQL connection or service-role key is required by the website.

Retain existing mobile/desktop Auth configuration. Add these web redirect destinations alongside existing entries in Authentication > URL Configuration:

```text
https://maramag-waterdistrict-web.vercel.app/auth/callback
https://maramag-waterdistrict-web.vercel.app/auth/callback?next=/reset-password
http://localhost:3000/auth/callback
http://localhost:3000/auth/callback?next=/reset-password
```

For previews allow only this project's preview URLs using documented Supabase patterns. Retain recovery email `{{ .ConfirmationURL }}` links and SMTP settings. Recovery uses PKCE and must be opened in the same browser; local tests do not prove email delivery. Existing active profiles and authorized account links remain the source of access.

## Vercel

Use Next.js, Node 24, **Root Directory `web`**, `npm ci`, `npm run build` and framework default output. Do not select the legacy Flutter `web/index.html` launcher.

```text
NEXT_PUBLIC_SUPABASE_URL=https://kaeespcylucvsazfdaks.supabase.co
NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=<existing public publishable key>
NEXT_PUBLIC_LANDING_URL=https://<separate-landing-site> # optional
```

`WATERDISTRICT_API_URL` is unused and can be removed from old deployments. Do not put database passwords or service-role keys in Vercel. Rebuild after changing public variables.

For CLI deployment, link from the repository root, retain the project's `web` Root Directory setting and run:

```powershell
npx --yes vercel@66.6.0 deploy --prod --local-config web/vercel.json
```

The local config applies the correct commands and Singapore region. Root `.vercelignore` excludes desktop/mobile source, SQL, private settings, local databases, tests and binary artifacts. For Git publishing connect the repository and select `feature/web-platform-parity` as Production Branch; manual CLI publishing works independently.

The landing opens first; Explore Demo restores a workspace or clean login through `/app`. Android links open `/download`. When editing the adjacent original static files, run `npm run sync:landing` from `web/` before redeployment; standalone clones contain the snapshot.

Optional map tile/attribution variables are public build-time settings. Default HTTPS OpenStreetMap tiles retain attribution and browser caching. GPS requires a click and HTTPS. No offline tile download is implemented.

## Live acceptance

Use authorized demonstration identities and records only:

1. Anonymous protected pages redirect and data requests return 401.
2. Linked Consumers see the same account, bills, verified payments, published notices and concerns as mobile.
3. Admin loads accounts, bills, dashboard and saved repairs without a desktop server; submit a demonstration concern/pin and compare its mobile/web values.
4. Admin reviews, dispatches once and assigns active Staff. Duplicate dispatch and stale edits must fail.
5. Assigned Staff records In progress then Resolved with notes; other Staff cannot open/update that ticket. Confirm history and Consumer resolution agree.
6. Access revocation clears the workspace and drafts. Restore authorized demonstration configuration afterward.

SQL setup and real-user acceptance are separate from deployment/local checks. [Historical API hosting](office-api-hosting.md) applies only to maintaining the optional desktop backend.
