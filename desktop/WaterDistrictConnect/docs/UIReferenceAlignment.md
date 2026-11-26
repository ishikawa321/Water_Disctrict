# Reference UI alignment

The desktop UI was aligned on 24 November 2026 to the user-supplied **Maramag Water client experience screens-2.png** and **Maramag Water service desk admin board-1.png**. The implementation reuses the existing Avalonia application, MVVM commands, authenticated session, application services and PostgreSQL persistence. It does not introduce another application or modify Flutter.

## Reference mapping

| Reference element | Implemented presentation |
| --- | --- |
| Light navigation and water identity | Shared light sidebar, vector drop/waves, outlined icons, cyan selected item, signed-in identity and demo badge |
| Sign-in | Split light layout, native vector wave artwork, username/password icons, password visibility toggle, primary sign-in action and actual demo credentials |
| Client overview | Welcome, full-width submission action, real account-scoped counts, latest saved activity and service information |
| Admin overview | Primary intake action, persisted concern counts, awaiting-review list and recent activity |
| Submission | Five selectable category tiles, inline validation, contextual guidance, prefilled address, review/edit/submit steps and saved-receipt action |
| My Concerns | Search, category filter, status tabs, concern cards, icons, colored status badges, details actions and working pagination |
| Concern Queue | Search/filters, aligned table columns, real customer/reference/category/status/date, pagination and queue actions |
| Client detail | Reference/category summary, submitted report, latest customer-visible response, readable timeline and intake attribution |
| Office detail | Customer and concern cards, customer-response/internal-note tabs, permitted action selector, classification controls and side timeline |
| My Account | Account summary, actual linked identity/address, help action, sign out and fictional-data notice |
| Customer accounts/resources | Searchable account directory, selected account detail and persisted fictional resource availability |
| Shared behavior | Segoe UI, compact card borders/radii, blue gradients, consistent primary actions, focus states, 160ms hover and 220ms page motion with reduced-motion support |

Screens use the actual authenticated names, records and state labels. Sample names, passwords, counts, phone numbers, unverified office hours and repair progress depicted on the presentation boards are not copied into operational data. The five required concern categories remain distinct. Contact details are optional at intake; the Phase 1 account model does not contain a phone field, so My Account shows the real sign-in username rather than a fabricated phone number.

Repair screens, ticket actions and the linked-ticket button shown in the boards remain deferred to Phase 3. Account editing/provisioning is outside Phase 2. Those controls are not presented as working actions. Existing repair relationships and service restrictions are retained. No database migration is required for this presentation update.

## Render verification

`tools/UiReview` is a development-only harness outside the application solution. It uses the production XAML views, real application services, authentication and persisted permissions. It creates a generated `mwd_ui_<GUID>` database, applies migrations, seeds fictional reference data and registers/responds to fixtures through the real services. It renders the actual Avalonia visual tree with RenderTargetBitmap, then drops only its generated database. Normal application data is never cleaned, reset or used as render fixtures. No sign-in bypass is added to the production application.

Run against the existing local PostgreSQL server:

```powershell
./scripts/Review-UI.ps1 -UseExistingLocalDemo
```

For another dedicated server, supply `MWD_TEST_ADMIN` with permission to create/drop disposable databases, then omit `-UseExistingLocalDemo`. Screens are saved under `TestResults/ui-reference/`.

The render pass covers sign-in; client overview, submit, review, list, detail and account; office overview, queue, detail, accounts and resources; office intake/queue at the minimum 1024×700 window size; read-only office detail; and an empty second-client list. Standard frames use a 1280×800 window. The main application scrolls longer forms and histories. A runtime assertion verifies that the actual office action ComboBox retains its selected permitted action after binding.

Visual inspection caught and corrected a split-panel width error, account/help column sizing, narrow queue customer columns, inherited Fluent selection colors, excess empty feedback spacing and a response selector initialization issue. Reference colors, spacing and component treatment are centralized in Theme.axaml rather than repeated as separate screen themes.

## Executed checks and limits

Release build, unit tests, Phase 2 PostgreSQL integration tests, EF model consistency and production rendering were run for this update. Regression tests exercise the review/edit/submit commands and verify that new overview activity projections exclude internal client-invisible notes. See the raw TRX files and render output for results.

| Verification | Result |
| --- | --- |
| Release build | Passed; 0 warnings, 0 errors |
| xUnit unit suite | 28 passed, 0 failed, 0 skipped |
| Phase 2 PostgreSQL integration suite | 15 passed, 0 failed, 0 skipped |
| EF model/migration consistency | No pending model changes |
| Production render harness | 16 states rendered successfully; action-selector assertion passed |
| Review script syntax | PowerShell parser check passed |

Representative rendered previews: [sign-in](../TestResults/ui-reference/01-sign-in.png), [client overview](../TestResults/ui-reference/02-client-overview.png), [submit form](../TestResults/ui-reference/03-client-submit.png), [client concerns](../TestResults/ui-reference/05-client-concerns.png), [office overview](../TestResults/ui-reference/08-office-overview.png), [office queue](../TestResults/ui-reference/09-office-queue.png), [office detail](../TestResults/ui-reference/10-office-detail.png), and [client account](../TestResults/ui-reference/07-client-account.png). Generated previews are local verification artifacts under the ignored TestResults folder and can be regenerated with the script above.

Rendered views verify production data binding and layout, not OS window chrome, native pointer input, every keyboard path, screen readers or every DPI setting. The presentation boards are raster composites; the UI uses native vector geometry and Segoe UI instead of stretching/cropping their screenshots. Pixel identity across Windows/font/DPI settings is not claimed. Database authorization, receipt wording, UTC/PHT convention and Phase 2 scope take precedence over illustrative sample content.
