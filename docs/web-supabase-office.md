# Web and mobile through the same Supabase project

The web no longer depends on a running desktop or ASP.NET service. It uses the same project as Flutter: `https://kaeespcylucvsazfdaks.supabase.co`. Existing accounts, active profiles, account links and operational records are retained. Desktop code remains under `desktop/`, excluded from Vercel.

## One-time setup

1. Open the existing project's [SQL Editor](https://supabase.com/dashboard/project/kaeespcylucvsazfdaks/sql/new) as an authorized project operator.
2. Open [database/web-office-workflows.sql](../database/web-office-workflows.sql), copy the entire file into a new query, review and run it once.
3. It should finish successfully. If the preflight reports missing reviewed repair/Staff migrations, stop and verify those existing migrations with the project owner; do not disable guards. This setup runs in one transaction, so a failure rolls it back.
4. Refresh the website and use existing authorized demonstration records for the acceptance steps in [web deployment](web-deployment.md).

The setup is repeatable. It adds scoped Staff policies, caller-executable atomic workflow functions, optional location columns/the existing coordinate-pair constraint and necessary column grants. It deletes no records or existing policies and creates no users. It requires the original reviewed workflow triggers and Staff migration already used by the shared district system.

Admin reads use existing RLS immediately. Staff access and workflow writes require this setup. Until installed, a repair save reports the required setup and retains the draft; it never attempts partial dispatch or fabricated success. Existing repair history can still load under existing caller permissions. Without the scoped author-name function, other authors display their actual user UUID rather than an invented name.

## Enforcement

Next.js validates the real Supabase user and active profile, checks route/method permissions and requires same-origin mutation requests. Data calls use that caller's session, without a service-role key or private connection string.

`wd_web_workflow` runs with caller permissions. It locks the record and compares `xmin` before editing. Admin-only dispatch, active Staff assignment, sequential statuses, actor stamping, immutable origin and append-only history are enforced by the original PostgreSQL guards. Dispatch/history/concern markers and resolution share the same transaction. Intake keeps its UUID for safe retry.

Two scoped helpers use a fixed search path and explicit active-role checks: Staff account visibility avoids circular RLS, and authorized ticket history resolves real author names. Public/anonymous execution is revoked. Billing, payments, publication and directory remain Admin-only; Consumer account isolation stays intact.

## Verification and deployment limits

Disposable PostgreSQL tests install the SQL twice and verify intake/retry, review, stale edits, Admin-only dispatch, assignment, Staff resolution, account isolation, history, concurrent dispatch and rollback after a trigger failure. Real local PostgREST checks cover `xmin`, relationships, exact counts and authenticated RPCs. Browser tests disable the old API and assert zero desktop calls.

Tests never use operational data. Deployment cannot install SQL using a public Supabase key. Production setup is not claimed applied until an authorized project operator completes it.

## Admin announcement creation

Announcement INSERT grants allow content, publication state and author columns. `updated_at` is granted only for UPDATE; creation timestamps use database defaults. The web now omits the timestamp on INSERT while retaining it on edits and derives both authors from the authenticated Admin. This fixes the permission denial for valid active Admin accounts without broadening RLS, column grants or Staff publication rights. No migration is needed for this announcement fix. Regression tests exercise actual exported PostgreSQL grants, strict browser fixtures and role checks.
