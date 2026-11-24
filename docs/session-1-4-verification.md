# Sessions 1 to 4 verification record

## Implemented additions

| Session | Result |
|---|---|
| 1 | Branch created from mobile baseline d8a48e4; source documents retained locally; reconciliation draft, scope and session plan committed. Instructor approval and member IDs remain pending. |
| 2 | Source-level database contract, proposed ERD, migration strategy, read-only SQL and catalog inspector implemented. Public boundary checked. Full live schema inspection is pending PostgreSQL access. |
| 3 | Seven-project solution: Avalonia desktop, Domain, Application, EF Core Infrastructure, ASP.NET Core API, Database inspector and xUnit tests. DI, configuration, dependency status and EF design-time tooling implemented. |
| 4 | Supabase password sign-in, signed-token validation, per-request active profile authorization, Admin/Staff workspace, Admin directory, refresh-access and logout implemented and tested with controlled identities. Real office-account sign-in and Staff provisioning remain pending. |

## Executed verification

- Full solution build: success, zero warnings and zero errors.
- xUnit: 39 passing tests, zero failures or skipped tests. API tests use real signed ES256 test tokens with controlled signing configuration/profile services; HTTP and UI tests use controlled dependencies, not real user credentials.
- Token tests cover incorrect issuer/audience/signature, expired and malformed tokens; those requests do not reach profile lookup.
- Permission tests cover active Admin/Staff, Client/unknown/inactive/missing/mismatched profiles, forged Admin claim, Admin-only directory access, deactivation on next request and dependency failure.
- Client tests cover correct credential/bearer boundaries, failed login, denied profile cleanup, offline logout, expiry and failed API communication after authentication.
- UI tests render sign-in at 850 ? 650 and Admin/Staff workspaces; verify role-specific controls, input rejection and workspace clearing after revocation. Rendered previews were visually inspected; layout and navigation text contrast were corrected.
- Native API process smoke check: `/health` returned 200; `/health/ready` returned 503 with unconfigured database; anonymous `/api/session` and `/api/admin/staff` returned 401. The API was shut down afterward.
- Local EF CLI reports 10.0.15. Database inspector without connection exits with an actionable message and does not contact a database.
- Live public Supabase checks: signing keys endpoint returned ES256 metadata; unauthenticated zero-row table probes returned 401/42501; OpenAPI root required privileged access. No operational rows or database changes were requested.

## Reproduce

From the repository root:

```powershell
dotnet build desktop/WaterDistrict.sln
dotnet test desktop/WaterDistrict.sln
```

UI previews are generated under `desktop/tests/WaterDistrict.Tests/bin/Debug/net10.0/artifacts/ui/`. These local build artifacts are ignored by Git.

## Outstanding checks

Full schema inventory, EF mapping confirmation/migrations, Staff constraint and RLS changes, authorized test-account provisioning and real sign-in with those identities need PostgreSQL/catalog administration access. No database migration or role change has been applied. Final workflow/persistence/transaction tests belong to Sessions 5?10 and are not replaced by these foundation/authentication tests. Self-contained publishing and native release verification remain in Session 11. Flutter source was unchanged.
