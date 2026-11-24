# Water District Connect

## Configure authentication

The app uses the existing Supabase project `kaeespcylucvsazfdaks`.
Its public publishable key is configured in `lib/main.dart`. You can override it
with `--dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLIC_KEY`.
Do not use a secret or service-role key in the app.

Run the web app on the port registered in Supabase:

```powershell
flutter run -d chrome --web-port=3000
```

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

## Interface and motion

- Splash waits at least three seconds while initialization runs, then slides left
  as sign-in enters. The sign-in label exits over 800 ms while authentication runs;
  a spinner covers longer requests and failed sign-ins restore the label.
- Dashboard content enters once and tabs crossfade. Cards respond to presses;
  bill and concern details expand. Refresh keeps existing records visible.
- Status badges use text, icons, and color. Repair progress highlights only the
  recorded current status; it does not imply unrecorded stages were completed.
- Authors can mark an announcement as **Service interruption**. To work with the
  existing database schema, this choice is stored as a `[Service interruption] `
  prefix in the title. The app hides the prefix and shows a badge instead. The
  dashboard prioritizes marked interruptions among the ten most recent published
  notices, displaying up to two notices. Older notices remain in Announcements.
- Reduced-motion settings suppress decorative transitions and pulsing placeholders.
  Login artwork shrinks when the keyboard opens; field errors appear by the input.

Widget coverage includes splash timing, concurrent sign-in and animation,
authentication failure recovery, password recovery, retained dashboard records,
bill disclosure, a 320-pixel keyboard layout, and reduced motion. Tests use mock
records. UI preview images are written to `build/ui-review/` by `test/ui_test.dart`.

