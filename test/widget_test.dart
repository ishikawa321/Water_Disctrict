import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:water_district_connect/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final requests = <http.Request>[];
  var failRequest = false;
  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/shared_preferences'),
          (call) async => call.method == 'getAll' ? <String, Object>{} : true,
        );
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-public-key',
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.implicit,
        persistSession: false,
        detectSessionInUri: false,
        autoRefreshToken: false,
      ),
      httpClient: MockClient((request) async {
        requests.add(request);
        if (request.url.path == '/auth/v1/user') {
          return http.Response(
            jsonEncode({
              'id': 'test-user',
              'aud': 'authenticated',
              'role': 'authenticated',
              'email': 'user@example.com',
              'created_at': '2026-01-01T00:00:00Z',
              'app_metadata': <String, dynamic>{},
              'user_metadata': <String, dynamic>{},
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (failRequest) {
          return http.Response(
            '{"msg":"Email rate limit exceeded"}',
            429,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(
          '{}',
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
  });
  setUp(() {
    requests.clear();
    failRequest = false;
  });
  tearDownAll(() => Supabase.instance.dispose());

  testWidgets('verified recovery link allows saving a matching password', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: waterTheme(),
        home: const MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: AccountPage(),
        ),
      ),
    );
    final payload = base64Url
        .encode(
          utf8.encode(
            jsonEncode({
              'sub': 'test-user',
              'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
            }),
          ),
        )
        .replaceAll('=', '');
    await tester.runAsync(
      () => Supabase.instance.client.auth.getSessionFromUrl(
        Uri.parse(
          'http://localhost:3000/'
          '#access_token=eyJhbGciOiJIUzI1NiJ9.$payload.signature'
          '&refresh_token=test-refresh&expires_in=3600&token_type=bearer&type=recovery',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Reset password'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'new-password-123');
    await tester.enterText(find.byType(TextField).last, 'does-not-match');
    await tester.ensureVisible(find.text('Save new password'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save new password'));
    await tester.pumpAndSettle();
    expect(find.text('Passwords do not match.'), findsOneWidget);
    expect(requests.where((r) => r.method == 'PUT'), isEmpty);
    await tester.enterText(find.byType(TextField).last, 'new-password-123');
    await tester.ensureVisible(find.text('Save new password'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save new password'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Password updated successfully.'),
      findsOneWidget,
    );
    expect(
      jsonDecode(
        requests.singleWhere((r) => r.method == 'PUT').body,
      )['password'],
      'new-password-123',
    );
    await tester.ensureVisible(find.text('Return to sign in'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Return to sign in'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Forgot password?'), findsOneWidget);
    expect(Supabase.instance.client.auth.currentSession, isNull);
  });

  testWidgets('reset rejects invalid email without sending a request', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: waterTheme(),
        home: const MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: AccountPage(),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField).first, 'person@');
    await tester.ensureVisible(find.text('Forgot password?'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Forgot password?'));
    await tester.pumpAndSettle();
    expect(
      find.text('Enter your registered email address first.'),
      findsOneWidget,
    );
    expect(requests, isEmpty);
  });

  testWidgets('reset email uses the configured mobile redirect', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: waterTheme(),
        home: const MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: AccountPage(),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField).first, ' user@example.com ');
    await tester.ensureVisible(find.text('Forgot password?'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Forgot password?'));
    await tester.pumpAndSettle();
    expect(requests.single.url.path, '/auth/v1/recover');
    expect(jsonDecode(requests.single.body)['email'], 'user@example.com');
    expect(
      requests.single.url.queryParameters['redirect_to'],
      mobileRecoveryUrl,
    );
    expect(
      find.textContaining('Check your inbox and spam folder.'),
      findsOneWidget,
    );
  });

  testWidgets('reset shows service error and allows retry', (tester) async {
    failRequest = true;
    await tester.pumpWidget(
      MaterialApp(
        theme: waterTheme(),
        home: const MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: AccountPage(),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField).first, 'user@example.com');
    await tester.ensureVisible(find.text('Forgot password?'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Forgot password?'));
    await tester.pumpAndSettle();
    expect(find.text('Email rate limit exceeded'), findsOneWidget);
    expect(
      tester
          .widget<TextButton>(
            find.widgetWithText(TextButton, 'Forgot password?'),
          )
          .onPressed,
      isNotNull,
    );
  });
}
