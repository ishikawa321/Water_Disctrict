import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:water_district_connect/staff_workspace.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  var active = true;
  var denied = false;
  final queries = <String>[];
  final user = {
    'id': '10000000-0000-4000-8000-000000000002',
    'email': 'staff@example.test',
    'aud': 'authenticated',
    'role': 'authenticated',
    'created_at': '2026-01-01T00:00:00Z',
    'user_metadata': {},
    'app_metadata': {},
  };
  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/shared_preferences'),
          (call) async => call.method == 'getAll' ? <String, Object>{} : true,
        );
    await Supabase.initialize(
      url: 'https://staff-test.supabase.co',
      publishableKey: 'isolated-public-key',
      authOptions: const FlutterAuthClientOptions(
        persistSession: false,
        detectSessionInUri: false,
        autoRefreshToken: false,
      ),
      httpClient: MockClient((r) async {
        Object body = [];
        if (r.url.path.endsWith('/token')) {
          final payload = base64Url
              .encode(
                utf8.encode(
                  jsonEncode({
                    'sub': user['id'],
                    'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
                  }),
                ),
              )
              .replaceAll('=', '');
          body = {
            'access_token': 'eyJhbGciOiJIUzI1NiJ9.$payload.signature',
            'refresh_token': 'qa-refresh',
            'expires_in': 3600,
            'token_type': 'bearer',
            'user': user,
          };
        } else if (r.url.path.endsWith('/user')) {
          body = user;
        } else if (r.url.path.endsWith('/profiles')) {
          body = active
              ? [
                  {'role': 'staff', 'active': true},
                ]
              : [];
        } else if (r.url.path.endsWith('/repair_tickets')) {
          queries.add(r.url.query);
          body = [
            {
              'id': 'ticket',
              'xmin': '41',
              'status': 'Completed',
              'assigned_to_user_id': user['id'],
              'assigned_to': 'Staff',
              'latest_update': 'Work finished',
              'service_concerns': {'subject': 'Assigned leak'},
            },
          ];
        } else if (r.url.path.endsWith('/service_concerns')) {
          body = [
            {
              'id': 'concern',
              'subject': 'Customer concern',
              'status': 'Submitted',
              'description': 'Low pressure',
              'service_accounts': {'account_number': 'MWD-001'},
            },
          ];
        }
        return http.Response(
          jsonEncode(body),
          200,
          request: r,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    await Supabase.instance.client.auth.signInWithPassword(
      email: 'staff@example.test',
      password: 'password123',
    );
  });
  tearDownAll(() => Supabase.instance.dispose());
  testWidgets(
    'Staff workspace scopes repairs and clears records when access is disabled',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: StaffWorkspace(onSignOut: () => denied = true)),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Customer concern'), findsOneWidget);
      await tester.tap(find.text('Repairs'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Assigned leak'), findsOneWidget);
      expect(find.text('Awaiting final resolution'), findsOneWidget);
      expect(
        queries.single,
        contains('assigned_to_user_id=eq.10000000-0000-4000-8000-000000000002'),
      );
      active = false;
      await tester.tap(find.byTooltip('Refresh records'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      expect(denied, isTrue);
      expect(find.text('Assigned leak'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
