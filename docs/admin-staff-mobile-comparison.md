# Admin and Staff functionality comparison

Reference: ishikawa321/Water_Disctrict main at f4848dc (partial UI design update), fetched on 2026-11-25. The desktop remains on feature/desktop-admin-staff. Mobile source was inspected without overwriting its consumer screens or merging unrelated UI changes.

## Role finding

The mobile login accepts only admin and client. Its dashboard checks only whether role equals admin; it does not define Staff access or a Staff workflow. Consequently there is no mobile Staff permission matrix to copy. Existing desktop Staff access remains limited to concern review and their own assigned repair updates. New accounts/billing/payment/announcement management and overview counts are Admin-only. The user approved the desktop rules (option 1); existing Staff limits were retained and no broader Staff access was inferred.

## Feature comparison and adaptation

| Mobile Admin behavior | Previous desktop gap | Adaptation |
|---|---|---|
| List service accounts; create active account with number, holder and address | Workflow account lookup only | Dedicated account list and creation form using the same fields and updated_by actor |
| List bills; enter district-computed charge and billing/due dates | Missing | Billing screen with active account selection, original amount, verified-payment total and remaining balance; no tariff computation |
| List/filter verified offline payments; record receipt/date/amount after confirmation | Missing | Payment list and verified-entry form, bill selection, positive two-decimal amount, date and verification checks; verified_by is the authenticated actor |
| List published notices and drafts; create/edit/publish; mark service interruptions | Missing | Announcement list/editor with draft/publish and interruption controls, preserving the exact title prefix used by mobile |
| Pending concern and active repair overview counts | Static workspace | Counts retrieved with exact database count headers, never inferred from a truncated list |
| Review submitted concerns and record a response | Already present | Existing desktop intake/review/closure retained |
| Create/update repair tickets and display current assignment/status | Already present with stronger identity/history rules | Existing Admin dispatch/assignment and Staff progress/resolution retained |
| Consumer account/bill/concern/status screens | Outside requested desktop role boundary | No consumer-screen changes in this adaptation |

The office additions call the same Supabase Data API tables with the validated user's bearer token and the public key. Existing RLS remains authoritative. Repair workflows continue through EF Core and their atomic history/concern updates. No secret/service-role key was introduced and no live schema migration was applied.

## Desktop visual adaptation

The desktop now follows the visual language in the same mobile reference (main at f4848dc): embedded DM Sans fonts, royal blue (#2563EB), ink (#111827), muted text (#6B7280), pale backgrounds (#F8F9FB), thin gray borders (#E5E7EB), and rounded white cards. The font license ships beside the bundled fonts. Sign-in, the dashboard, service accounts, billing, verified payments, announcements, concerns, repair tickets, and the staff directory share this styling.

Mobile's compact navigation is adapted into a labeled desktop sidebar with vector line icons, a selected-page capsule, a breadcrumb, and an account footer. The sidebar navigation and page content scroll independently at the 1000 x 700 minimum window size. Desktop keeps the wider record/form and list/detail layouts needed for office work. Status badges use the mobile green, blue, amber, and red state colors while retaining readable status text.

This adaptation changes presentation only. The shared database contracts, authentication, role restrictions, and repair workflow rules remain in place. Headless UI checks render both roles, sign-in, the four office modules, concern review, and ticket detail; they also check selected navigation and that Sign out remains reachable at minimum size. Rendered PNG previews are generated under desktop/tests/WaterDistrict.Tests/bin/Debug/net10.0/artifacts/ui by the UI tests.

## Accepted shared workflow differences

The mobile draft permits selecting any listed concern/ticket status in its forms and stores assignment as text. Desktop requires review before ticket creation, an active Staff identity for assignment, allowed sequential repair transitions, one ticket per concern, and append-only history. It closes answered non-repair concerns with Closed rather than directly setting Resolved. These integrity rules were retained rather than silently weakened. Exact status/assignment parity remains a policy decision and requires review against the real database constraints.

The desktop payment screen lists bill/account references and supports filtering history to the selected bill, matching the mobile bill-specific history view. Office lists show up to 1000 records, matching the bounded Data API access; these are not analytical exports.

## Verification and live connection status

The adaptation builds without warnings. Tests cover actual actor stamping, caller-token forwarding, payment/date/amount validation, decimal totals, announcement prefixes and publish state, exact counts, duplicate/denied/empty saves, malformed responses, Staff denial, four rendered Admin screens and retained drafts. The final solution build passed with zero warnings and errors. All 83 tests passed with zero failures and zero skipped tests, including local PostgreSQL integration, office Data API contract tests, Admin/Staff permission checks, retained drafts, selected-bill filtering, selected-page navigation, minimum-size account controls, and rendered Admin/Staff screens.

The saved live PostgreSQL connection now succeeds with VerifyFull and the project CA certificate. Credentials and the public schema have been verified read-only. See live-database-integration.md for the confirmed constraints, column grants, Staff-role gap and tested migration package. The user chose the shared desktop ticket rules; both migrations are applied. Existing consumer policies and original table counts were preserved. New Admin Data API modules can be tested with an existing verified Admin login independently of that direct PostgreSQL certificate setup, subject to the current RLS policies.

Instructor scope documentation still identifies billing/payment/notice functionality as supporting additions; formal scope approval and the live role/schema review remain pending.

Published adaptation release: desktop/artifacts/release/20261125-015301. Native process checks passed outside Visual Studio: desktop window opened; /health and configured local /health/ready returned 200; anonymous requests to all five new office routes returned 401. This was a local PostgreSQL check and does not establish live Supabase certificate/authentication or data verification.

Deployment follow-up: option 1 was explicitly approved and the shared desktop rules are now installed in Supabase. See live-database-integration.md for the backup, applied migration IDs and preservation checks. The mobile Admin draft must follow the same review/assignment/transition rules; consumer submissions and reading retain their policies.
