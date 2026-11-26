# Connect the live Admin and Staff services

The current production error `The office service is not connected yet` means Vercel has no `WATERDISTRICT_API_URL`. Supabase Auth signs the user in successfully, but Admin/Staff operations use the original ASP.NET service. `https://kaeespcylucvsazfdaks.supabase.co/rest/v1/` is the database's data API, not that service; setting it as the office API would break the established routes and bypass the intended architecture.

The backend remains `desktop/src/WaterDistrict.Api`, with Supabase JWT/profile validation, shared workflow rules and existing PostgreSQL transactions/triggers. No replacement database, demo seed, automatic migration or alternate JavaScript workflow is introduced.

## Prepared Render deployment

[Deploy the prepared API to Render](https://render.com/deploy?repo=https://github.com/ishikawa321/Water_Disctrict/tree/feature/web-platform-parity)

The repository's `render.yaml` selects the original Dockerfile, Singapore, the free web-service plan and `/health/ready`. Automatic deployments are off. It creates no Render database. The existing Supabase project URL and public publishable key are included; these are not backend database credentials.

1. Sign in to Render and open the link. Review the free service configuration.
2. Supply `ConnectionStrings__WaterDistrict` privately in Render's setup form. Use the existing Supabase PostgreSQL/pooler connection and its password, with the schema-owner privileges required by the existing API. A public publishable key is not a PostgreSQL password. Retain verified TLS settings and mount the appropriate trusted CA file as a Render secret file if the connection requires one. Never enter the database password in chat, source control or Vercel.
3. Verify the reviewed Staff/workflow migrations and `database/add_concern_locations.sql` are already applied to that same project. This deployment does not apply them. Deploy and wait for `/health/ready` to return HTTP 200 and `status: ready`.
4. Copy the actual public HTTPS origin from Render, without `/api`. For a custom hostname, replace the blueprint's `AllowedHosts` setting with that hostname.
5. From this checkout run the following. The script checks the original API's identity, shared-database readiness and anonymous access denial before changing Vercel, then redeploys the linked project:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/connect-office-api.ps1 -ApiUrl https://YOUR-ACTUAL-API.onrender.com
```

If a Render connection becomes available in this session, the agent can perform the hosting/configuration steps through that connection. Without an authenticated hosting account and the existing private database configuration, the live service cannot be connected merely by changing an error message. Read-only API checks do not prove real-user cross-platform acceptance.

The free Render plan can sleep after inactivity and delay the first request. Open the API health page to let it wake, then refresh the office workspace. This configuration does not authorize or create a paid service.

## Acceptance

Sign in with authorized accounts. Admin overview/accounts/bills/payments/notices/directory must load; Staff must remain denied Admin modules and dispatch. Use authorized test records to verify review, one-time dispatch, active assignment, sequential repair updates/history, conflict handling and consumer summaries. Keep real customer records out of tests. Existing isolated .NET and web tests cover those contracts; a deployed health page alone is not live workflow acceptance.

References: [Render web services](https://render.com/docs/web-services), [Blueprint reference](https://render.com/docs/blueprint-spec), [Deploy button](https://render.com/docs/deploy-to-render), [free service limitations](https://render.com/docs/free).
