# Water District Connect

## Browser application

The Next.js application in [`web/`](web/README.md) adds Consumer, Admin and Staff browser workspaces using the same Supabase identities/database and ASP.NET Core API as the existing applications. See the [feature matrix](docs/web-parity.md), [deployment guide](docs/web-deployment.md) and [verification evidence](docs/web-verification.md).

Run `npm ci` and `npm run dev` from `web/` after configuring its `.env.local`. Deploy that folder as the Vercel project root; the office API requires a separately hosted HTTPS address. The Flutter browser launcher files are preserved for the original Flutter workflow described below.

## Latest WaterDistrictConnect desktop source

The current standalone Avalonia/.NET desktop workspace is available in
[`desktop/WaterDistrictConnect/`](desktop/WaterDistrictConnect/README.md).
Open `desktop/WaterDistrictConnect/WaterDistrictConnect.slnx` in Visual Studio,
or run `dotnet build desktop/WaterDistrictConnect/WaterDistrictConnect.slnx -c Release`.
Its README covers PostgreSQL configuration, migrations, demo setup and verification.
Local database credentials and generated build output are excluded.
The existing `desktop/WaterDistrict.sln` implementation is also retained.


## Configure authentication

The app uses the existing Supabase project `kaeespcylucvsazfdaks`.
The project URL and public publishable key are configured in `lib/main.dart`.
You can override the key at build or launch time with
`--dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLIC_KEY`.
Do not use a secret or service-role key in the app.

Run the web app on the port registered in Supabase:

```powershell
flutter run -d chrome --web-port=3000
```

For Android, use `flutter run -d DEVICE_ID`.
Alternatively, use the VS Code launch configuration **Web (password reset - port 3000)**.
The reset redirect is `http://localhost:3000/`, matching your Supabase redirect URL.
Request and open the reset email in the same browser on this computer, with the
web app running. This localhost setup supports web recovery; mobile recovery
needs a separately configured app redirect.
Keep the Reset Password email template linked to `{{ .ConfirmationURL }}` so
Supabase verifies the recovery token before redirecting to the app.
For delivery to real users, configure Supabase custom SMTP; the default mail
service is restricted. See [Supabase email configuration](https://supabase.com/docs/guides/auth/auth-smtp)
and [mobile deep linking](https://supabase.com/docs/guides/auth/native-mobile-deep-linking).

## Verify password recovery

1. Enter the email of an existing account and select **Forgot password?**.
2. Open the newest reset email on the device that requested it (same browser
   for web). Keep the app installed/web server running.
3. Enter matching passwords with at least eight characters and save.
4. Return to sign in, then sign in with the new password. The old password
   should fail. Login also requires the existing active `profiles` record.
5. An expired/used link should show an error; request a fresh link.

```powershell
flutter test
flutter analyze
```

Tests use a fake HTTP service and do not send emails or change real accounts.
Live delivery and the email-to-app round trip require the public key, redirect
allowlist, and email delivery settings above.

## Concern locations

- Run `database/add_concern_locations.sql` in Supabase SQL Editor. It adds the
  nullable location columns, a coordinate-pair/range constraint, and authenticated
  INSERT permission on the three location columns. Existing concerns remain valid
  and row access policies stay unchanged. If the columns were added manually and
  submission returns access denied, run
  `database/fix_concern_location_permissions.sql` to apply and verify that grant.
- Client: **Report issue → Choose location**. Tap the map, optionally use
  **Use my location**, add a landmark, then **Confirm location**. The pin is saved
  with the concern only when the concern is submitted. Cancelling the picker
  preserves the previous selection. Locations are optional for billing inquiries
  and other concerns that do not need a repair location.
- Flutter admin: **Service concerns → Details & response → View location**, or
  open the concern review form. The saved location is read-only. Reviewing a
  concern updates its status/response without replacing the client's coordinates.
  Old concerns show **No location provided**.
- GPS permission is requested only after **Use my location**. Manual selection
  remains available if GPS is disabled, denied, or times out. Browser geolocation
  requires localhost or HTTPS; it can return an approximate position, so clients
  should confirm or adjust the pin. Android and Apple permission metadata is
  included; no background location tracking is used.
- Maps use OpenStreetMap tiles with visible linked attribution, a distinct app
  identifier, and flutter_map's default caching. Follow the
  [tile usage policy](https://operations.osmfoundation.org/policies/tiles/).
  `MAP_TILE_URL` can override the tile template at build time; changing providers
  also requires reviewing the displayed attribution and provider terms.
- The separate `desktop/` office workspace currently has no concern-review UI.
  Its future concern screen can read the same `latitude`, `longitude`, and
  `location_note` fields from Supabase.

## Interface and motion

- Client and admin pages share the water-inspired design: light headers,
  midnight balance and operations cards with fine aqua rings, cobalt actions,
  white quick-action tiles with aqua icon wells, rounded records and fields,
  and a floating navy navigation dock with an aqua active tab.
  Bills, payments, concerns, repairs, notices, account records, dialogs, maps,
  and forms use the same visual system. Sign-in and recovery share its palette
  and controls while retaining the startup animation and login artwork.
- User navigation links Home, Bills, Services, and Account. Admin navigation
  links Home, Accounts, Services, and More; record pages return to the matching
  dashboard destination. At large text sizes the dock uses two rows, content
  stacks, and headers grow to keep their titles visible.
- Dashboard branding uses the Maramag Water District logo. Desktop dashboards
  use two columns, while mobile and large-text layouts remain stacked. Service
  advisories link to published notices, whose detail sheet shows publication dates;
  the absence of a notice does not assert normal service. Request previews open
  the selected concern and its repair records. Unpaid client bills include
  payment guidance with account/bill references and verification requirements.
- Browser loading, the startup screen, and startup errors use the same midnight,
  cobalt, and aqua palette. Recent activity displays the latest payment record;
  its empty message appears only after an empty successful response.
- Splash waits at least three seconds while initialization runs, then slides left
  as sign-in enters. The sign-in label exits over 800 ms while authentication runs;
  a spinner covers longer requests and failed sign-ins restore the label.
- Client home prioritizes the balance, due date, and three quick actions. Admin
  home prioritizes pending concerns, repairs, and management actions. The profile
  uses one account card with a compact help action. Refresh keeps records visible.
- Bills, payments, concerns, repairs, and notices reveal supporting details on
  demand. Important amounts, dates, and statuses stay visible. Large-text layouts
  stack content, and currency amounts stay on one line.
- Status badges use text, icons, and color. Repair progress highlights only the
  recorded current status; it does not imply unrecorded stages were completed.
- Authors can mark an announcement as **Service interruption**. To work with the
  existing database schema, this choice is stored as a `[Service interruption] `
  prefix in the title. The app hides the prefix and shows a badge instead. The
  dashboard shows the latest published notice, opening its full message on tap.
  Interruption badges remain visible, and all notices remain in Announcements.
- Reduced-motion settings suppress decorative transitions and pulsing placeholders.
  Login artwork shrinks when the keyboard opens; field errors appear by the input.

Widget coverage includes splash timing, concurrent sign-in and animation,
authentication failure recovery, password recovery, retained dashboard records,
bill disclosure, a 320-pixel keyboard layout, and reduced motion. Tests use mock
records. UI preview images are written to `build/ui-review/` by `test/ui_test.dart`.

## Web release

The signed-in visual audit covers 23 page variants at 320, 390, 768, and 1280
logical pixels with 100% and 200% text scaling, plus loading, empty, and error
states for data-backed pages. Screenshots use mock data; they do not certify
live database authorization or email delivery.

```powershell
flutter test
flutter analyze
flutter build web --release
```

Deploy the contents of `build/web/` to HTTPS static hosting. Set Supabase's
Site URL and allowed recovery redirect to the final deployed origin; localhost
configuration alone does not enable production password recovery. Complete the
live client/admin and recovery checks against that origin before release.
Map selection is preserved, and browser GPS requires HTTPS outside localhost.

Android APK distribution now uses `ph.maramag.waterdistrictconnect` and a private
release signing configuration. The landing page links to the signed universal
APK and installation instructions at https://maramag-waterdistrict-web.vercel.app/download.
See [Android release and signing instructions](docs/android-release.md). Private
keystores/credentials stay outside source control. Google Play store submission
is separate from this directly downloadable APK release.


## Admin and Staff desktop

The Avalonia/.NET solution is in [`desktop/WaterDistrict.sln`](desktop/WaterDistrict.sln). See the [desktop setup guide](desktop/README.md), [implementation sessions](docs/implementation-plan.md), and [shared database contract](docs/database-contract.md).

Office concern review and repair assignments/updates are performed in the desktop app. The mobile app keeps consumer submissions and recorded status viewing, and directs its legacy office-edit buttons to desktop. See [release preparation](docs/release-and-demonstration.md) and [workflow acceptance evidence](docs/acceptance-verification.md). The mobile project supports the installed Dart 3.13.1 patch level; run the verification commands above after dependency restoration.
