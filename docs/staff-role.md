# Staff role on web and Android

The role follows the six choices confirmed by the owner: office/customer service and field repairs; read bills and confirm payments; all concerns and only assigned repair tickets; Admin invitations; web and mobile sign-in; Admin confirmation of completed repairs.

| Action | Staff | Admin |
|---|---|---|
| Read/receive/review concerns | Yes | Yes |
| Read repair tickets/history | Own assignments only | All |
| Assign or dispatch repairs | No | Yes |
| Move assigned repairs to In progress / Completed | Yes | Yes |
| Confirm Completed as Resolved or return to In progress | No | Yes |
| Read bills and verified payments; confirm payments | Yes | Yes |
| Issue bills/change monthly plans | No | Yes |
| Approve Consumer registration/manage Staff | No | Yes |

## Supabase installation

Run **the entire `database/staff-role.sql`** in the existing project's SQL Editor as the project owner, after `web-office-workflows.sql` and `billing-automation.sql`. The migration checks those prerequisites, preserves existing records and users, expands the existing role/status constraints and applies the Staff financial policies and invitation functions. It is safe to rerun. It does not provision real employees or change any existing user's role.

The web/mobile public key cannot apply database migrations. A published frontend/APK alone does not install these rules. Until an authorized operator runs the SQL, invitations and Staff payment confirmation report missing setup/permission rather than bypassing it. Do not rerun older workflow/billing scripts afterward: they restore their older function definitions and can undo the new behavior. Apply this Staff upgrade last.

The role is `staff` in the existing `public.profiles` table, with an `active` flag. RLS protects data even when a caller skips the UI. Staff financial reads include customer bills/payments for office verification; billing plan writes and issuance stay Admin-only. Payment confirmation retains atomic bill locking, current interest calculation, generated 10-digit receipts, actor stamping, duplicate-request checks and overpayment protection.

## Invite and disable Staff

1. Admin opens **Staff directory / Staff management** on the website, enters the person's name and a new Staff email, then selects **Create Staff invitation**.
2. Copy the private invitation link and send it to that employee. The application does **not** send the invitation link automatically. It is shown only in that browser and uses a URL fragment to avoid putting the token in server request logs.
3. The recipient opens the link, sets matching passwords, and confirms their email through the existing Supabase confirmation message. After confirmation, the same credentials work on web and the new Android app.
4. Admin can revoke a pending invitation or disable/re-enable an accepted Staff member. Disabling keeps operational history. New requests fail immediately under RLS; visible workspaces recheck access on resume/focus and periodically and clear records after access loss.

Invitations expire after seven days, bind to one email and one Auth identity, and require the inviting Admin to remain active at acceptance. Only an opaque token hash is stored. Public metadata cannot request an Admin role or promote an existing Consumer/Admin identity. Existing emails cannot be converted through this flow. If an unconfirmed Staff signup expires, contact the project owner to review that pending Auth identity rather than deleting operational data or promoting it from the browser.

Email confirmation still depends on existing Supabase email/redirect configuration. Staff acceptance uses the existing website `/auth/callback` destination. The Admin never chooses the employee's password. Pending Staff profiles are inactive; confirmation cannot reactivate an already accepted, disabled employee.

## Repair completion

The shared sequence is **Open → Assigned → In progress → Completed → Resolved**. Completed means the assigned Staff member reports work finished. The concern remains Under review, and the customer sees awaiting Admin confirmation. Only Admin can confirm resolution, with a required note; Admin may instead return the work to In progress. Every successful change appends a real history event and compares the saved `xmin` under a database lock. A direct Staff attempt to resolve is rejected by PostgreSQL.

Existing Resolved repairs remain resolved. Mobile Admin repair links open the new review workspace, where Admin can confirm completed tickets. The desktop source is retained separately; its older client still lacks a Completed choice and should use the office website for this new workflow.

## Mobile and verification

Android 1.0.2 build 3 adds the Staff workspace with concerns, assigned repairs/history, bills and payment confirmation. Saved concern locations use the existing read-only map details. Admin repair navigation opens the review workspace. It uses the same Supabase project and no desktop host. A newly approved Consumer is never linked to a Staff account.

Tests use disposable PostgreSQL, a local PostgREST server, loopback browser fixtures and Flutter HTTP fixtures. They cover denied self-invitation, wrong-email/forged/revoked tokens, confirmation/disable behavior, Staff payment permissions, billing restrictions, owned repairs, completion/confirmation/history, failed-save draft retention and mobile access revocation. No live employee invitation or operational payment is made during testing.
