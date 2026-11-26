# Client registration and admin approval

Clients register using full name, service address, email, password and matching
confirmation. Supabase Auth stores the password. On signup, the database saves
the client details in `client_registrations` with status **Pending**, and creates
an inactive client profile. No service account number is consumed yet.

Admins open **Service accounts ? Pending registrations**, review the name,
email and address, then select **Approve registration**. This is available in
Flutter mobile/web, Next.js Admin, and the connected desktop application
`desktop/WaterDistrict.sln`. The separate `desktop/WaterDistrictConnect` prototype
is not the shared workspace.

Approval atomically creates the next sequential MWD account, links it to the
client, activates the profile, and records the approving admin and timestamp.
Client login requires both approval and email confirmation. Pending clients can
read only their own registration status and cannot approve themselves. Staff
cannot review or approve registrations. Existing active accounts are preserved.
Repeated or simultaneous approval creates only one account per registration.

## Database installation

Apply these migrations in order using the Supabase SQL Editor as postgres:

1. `database/enable_client_registration.sql` (original registration infrastructure).
2. `database/require_client_approval.sql` (required approval workflow).

The approval migration was installed and verified on project
`kaeespcylucvsazfdaks` on 2026-11-27. Verification found one pending signup,
an unchanged counter of 1247, enabled row security, and no client update or
anonymous approval permissions. No live registration was approved during testing.

Always apply the approval migration last; rerunning only the original migration
would restore the earlier automatic activation trigger. Both apps check
`client_registration_approval_available()` before offering signup.

Use Supabase's existing email confirmation settings and redirect allowlist.
Approval does not bypass confirmation. Registration does not depend on the
ASP.NET host. The Next.js office uses Supabase directly; the connected desktop
uses WaterDistrict API. Redeploy the website/API and rebuild installed clients to
publish source changes.

The account counter remains private. Only active admins can call
`approve_client_registration`; the database assigns the number and copies the
saved registration details. Editable metadata never grants an admin role or
links a client to someone else's existing service account.

## Validation

Verified with isolated PostgreSQL tests for pending profiles, private registration
reads, denied self/staff approval, atomic approval, duplicate and concurrent
approval, preserved existing accounts, and numbers exceeding six digits. Web
browser tests exercise pending login denial through admin approval to successful
client login. Desktop tests verify that failed approval retains the selection;
Flutter tests verify pending login shows approval guidance and clears the session.
