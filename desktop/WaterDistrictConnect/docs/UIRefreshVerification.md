# UI refresh verification

Historical refresh record. The current light reference-board design supersedes the dark sidebar described below; see [UI reference alignment](UIReferenceAlignment.md).

Verified on 23 November 2026 using the installed .NET 10 SDK and the existing fictional-data PostgreSQL demo environment.

## Implemented

- Shared deep-blue navigation, stronger Segoe UI headings and section hierarchy.
- Split login screen, a featured overview metric, status badges, readable record rows and restrained shadows.
- One shared button template with hover, pressed, disabled and keyboard focus states.
- 140ms button lift/press and navigation motion; 200ms page slide/fade entrance.
- Startup handling of the Windows client-area animation preference; `MWD_REDUCED_MOTION=true` suppresses motion styles.
- Sidebar selection follows dashboard actions and detail navigation.
- Window maximizes on launch when its initial dimensions would exceed the detected working area.

## Executed checks

| Check | Actual result |
| --- | --- |
| `dotnet build` after visual/style changes | Passed, 0 warnings and 0 errors |
| Self-contained win-x64 publish after final refinements | Passed; output in `artifacts/win-x64-ui` |
| Existing unit test suite | 9 passed, 0 failed, 0 skipped; `TestResults/unit-ui-refresh.trx` |
| Login layout in the running application | Inspected; brand panel, form, demo help and primary action displayed |
| Office login against PostgreSQL | Successful in the published UI release |
| Client login and shared dashboard styling | Successful; client navigation and saved record counts displayed |
| Final selected-navigation contrast | Verified in published office overview and concern queue after correcting Fluent presenter interference |
| Concern queue in published application | Inspected; filters, rows, status badges, actions and pagination displayed |
| Prior operational records | Displayed existing fictional concerns and linked ticket; no record reset performed |

The earlier release remains separate so it need not be overwritten while open. `Start-LocalDemo.ps1` prefers the refreshed release. No business workflow or database schema change was introduced by this UI task. PostgreSQL integration tests were not rerun for this presentation-only refresh; the prior seven-test execution is separate evidence.

Minimum-size resizing, alternate Windows scaling factors, animation frame timing, live changes to the Windows animation preference, and a complete keyboard/screen-reader audit were not fully verified in this pass. Motion preference is evaluated at application startup. Source implementation and successful rendering do not constitute an exhaustive accessibility or performance certification.
