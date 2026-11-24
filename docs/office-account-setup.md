# Office account setup

The desktop supports existing active `admin` and `staff` profiles. It does not create accounts or let users select their own role. Supabase Auth verifies credentials; the API verifies the token and retrieves the current profile with the caller's Supabase permissions on every protected request.

## Configure the backend database

The Supabase REST URL and publishable key are already configured for this project. They support sign-in and permitted Data API requests, including the Session 1-4 profile checks. PostgreSQL credentials are separately required for EF Core workflow persistence and full schema inspection.

Copy `desktop/src/WaterDistrict.Api/appsettings.Local.example.json` to `desktop/src/WaterDistrict.Api/appsettings.Local.json`. Replace the sample connection locally with the actual connection from Supabase Dashboard > Connect. The local file is ignored by Git. Use the project-provided hostname, username, pooling mode, SSL settings and certificate configuration; do not derive a pooler hostname from the project URL. A session pooler can be appropriate when the office network has IPv4 only.

Restart the API after configuration. `/health/ready` returns 200 when PostgreSQL is reachable and workflow schema markers exist. It returns 503 for unconfigured, unreachable or unmigrated environments. Run the acceptance scenarios to verify business correctness.

Run the catalog inspector from the repository root:

```powershell
# Set ConnectionStrings__WaterDistrict locally from the same secure connection.
dotnet run --project desktop/tools/WaterDistrict.Database
```

The CLI reads the environment variable, not the API's configuration files. Alternatively run `desktop/database/inspect.sql` in the Supabase SQL editor and keep the metadata output locally for review. No secret/service-role key is needed in the desktop application.

## Prepare demonstration identities

1. In an authorized Supabase administration session, create or identify dedicated test Auth users. Complete email verification as required; do not commit credentials.
2. Inspect the real `profiles` definition, role constraint/enum, profile creation trigger and grants before changes. Confirm the Auth user is linked to exactly one profile with the correct display name.
3. Extend the existing role constraint/enum to allow `staff` through a reviewed additive migration if necessary. The current repository cannot establish its exact definition from the publishable key.
4. Use the authorized administration session to set the dedicated profiles to `admin` and `staff`, with `active = true`. Verify clients cannot update their own role/active flag or create privileged profiles.
5. Verify each active office user can read their own profile through RLS. Verify Admin can read the office directory. Staff need not receive unrestricted directory access.
6. Sign in to the desktop with each account. Admin sees Staff directory; Staff does not. A consumer, inactive profile or missing profile must be rejected. Change a test user's active flag and verify Refresh access removes their workspace.
7. Sign in to the existing consumer app and confirm its account data remains accessible. Its current login accepts `admin` and `client`; Staff users use the desktop.

There are no seeded passwords or development authentication bypasses. Do not change the Auth user's JWT `role` to the application role: Supabase's authenticated database role and `profiles.role` have different purposes.

## Session behavior

Desktop access tokens are kept in memory only. Sign out clears local state immediately and attempts remote session revocation. Expiry requires sign-in again; Refresh access reloads permissions, not the Auth refresh token. API authorization reads current active profile state on each request, so deactivation applies without restarting the API.

The API accepts ES256/RS256 signatures from the configured project's HTTPS JWKS and validates issuer, authenticated audience and expiry. Profile role comes from the database response, never from user-editable token metadata. There is no legacy shared-secret JWT fallback; the inspected project advertises an ES256 key.

For access from another computer, configure the API's actual host in AllowedHosts and an HTTPS deployment endpoint. Plain HTTP desktop API configuration is limited to loopback development.

## Remaining database verification

Live PostgreSQL constraints, policies and staff provisioning are pending authorized catalog access. The draft ERD and provisional EF profile mapping must be reconciled with that output before workflow migrations. The inspector deliberately does not modify grants, roles, policies or records.

## Workflow deployment

After catalog review and a backup, rehearse the RepairWorkflow migration on a development copy, then apply it using the database tool's explicit --migrate mode. See release-and-demonstration.md. The migration adds a Staff identity link without changing consumer-facing assignment text, creates append-only ticket history and enforces shared workflow rules in PostgreSQL. It intentionally rejects existing workflow triggers/history that need reconciliation rather than overwriting them. No migration has been applied to the live Supabase project during implementation.
