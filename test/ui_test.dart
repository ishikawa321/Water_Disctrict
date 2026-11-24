import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:water_district_connect/main.dart';
import 'package:water_district_connect/ui_components.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Completer<void>? authGate;
  Completer<void>? refreshGate;
  var authStarted = false;
  var failAuth = true;
  var failRefresh = false;
  final boundaryKey = GlobalKey();
  final user = {
    'id': 'test-user',
    'aud': 'authenticated',
    'role': 'authenticated',
    'email': 'user@example.com',
    'created_at': '2026-01-01T00:00:00Z',
    'app_metadata': <String, dynamic>{},
    'user_metadata': <String, dynamic>{},
  };

  setUpAll(() async {
    final iconFont = File(
      'build/flutter_assets/fonts/MaterialIcons-Regular.otf',
    );
    if (await iconFont.exists()) {
      final loader = FontLoader('MaterialIcons')
        ..addFont(
          iconFont.readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
        );
      await loader.load();
    }
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/shared_preferences'),
          (call) async => call.method == 'getAll' ? <String, Object>{} : true,
        );
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-public-key',
      authOptions: const FlutterAuthClientOptions(
        persistSession: false,
        detectSessionInUri: false,
        autoRefreshToken: false,
      ),
      httpClient: MockClient((request) async {
        Object body = [];
        var code = 200;
        if (request.url.path.endsWith('/token')) {
          authStarted = true;
          if (authGate != null) await authGate!.future;
          if (failAuth) {
            code = 400;
            body = {'msg': 'Invalid credentials'};
          } else {
            final payload = base64Url
                .encode(
                  utf8.encode(
                    jsonEncode({
                      'sub': 'test-user',
                      'exp':
                          DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
                    }),
                  ),
                )
                .replaceAll('=', '');
            body = {
              'access_token': 'eyJhbGciOiJIUzI1NiJ9.$payload.signature',
              'refresh_token': 'refresh',
              'expires_in': 3600,
              'token_type': 'bearer',
              'user': user,
            };
          }
        } else if (request.url.path.endsWith('/profiles')) {
          body = [
            {'display_name': 'Test Admin', 'role': 'admin'},
          ];
        } else if (request.url.path.endsWith('/service_concerns')) {
          if (refreshGate != null) await refreshGate!.future;
          if (failRefresh) {
            code = 500;
            body = {'message': 'Unavailable'};
          } else {
            body = [
              {
                'subject': 'Low water pressure',
                'status': 'Submitted',
                'created_at': '2026-01-01',
                'service_accounts': {'account_number': 'WD-001'},
              },
            ];
          }
        } else if (request.url.path.endsWith('/account_access')) {
          body = [
            {
              'service_accounts': {'account_number': 'WD-001'},
            },
          ];
        } else if (request.url.path.endsWith('/bills')) {
          body = [
            {
              'bill_number': 'B-001',
              'billing_period_start': '2026-10-01',
              'billing_period_end': '2026-10-31',
              'amount_due': '450.00',
              'due_date': '2026-11-01',
              'offline_payments': [],
            },
          ];
        } else if (request.url.path.endsWith('/announcements')) {
          body = [
            {
              'title': '${interruptionPrefix}Scheduled maintenance',
              'message':
                  'Water service will pause during scheduled maintenance.',
              'updated_at': '2026-10-23',
            },
          ];
        } else if (request.url.path.endsWith('/logout')) {
          body = {};
        }
        return http.Response(
          jsonEncode(body),
          code,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
  });
  tearDownAll(() => Supabase.instance.dispose());
  setUp(() {
    authGate = null;
    refreshGate = null;
    authStarted = false;
    failAuth = true;
    failRefresh = false;
  });

  Widget app(Widget child) => MaterialApp(
    theme: waterTheme(),
    home: RepaintBoundary(key: boundaryKey, child: child),
  );
  Future<void> screenshot(WidgetTester tester, String name) async {
    await tester.pump();
    final boundary =
        boundaryKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory('build/ui-review').create(recursive: true);
      await File('build/ui-review/$name.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  testWidgets('dashboard groups remain usable at narrow and wide widths', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final role in ['admin', 'client']) {
      for (final width in [320.0, 768.0]) {
        await tester.binding.setSurfaceSize(Size(width, 844));
        await tester.pumpWidget(app(ModernDashboard(
          key: ValueKey('$role/$width'),
          profile: {'display_name': 'Test User', 'role': role},
          onSignOut: () async {}, signingOut: false,
        )));
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
        await tester.pumpAndSettle();
        final heading = find.text(role == 'admin' ? 'Service operations' : 'Service support');
        await tester.ensureVisible(heading);
        await tester.pumpAndSettle();
        expect(heading, findsOneWidget);
        expect(tester.takeException(), isNull);
        await screenshot(tester, '$role-organized-${width.toInt()}');
        await tester.tap(find.text('Services').last);
        await tester.pumpAndSettle();
        expect(find.text(role == 'admin' ? 'Service concerns' : 'My concerns'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      }
    }
  });

  testWidgets(
    'sign-in authenticates during slide and restores label on failure',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(app(const AccountPage()));
      await tester.pump(const Duration(milliseconds: 300));
      await screenshot(tester, 'login');
      await tester.enterText(find.byType(TextField).first, 'user@example.com');
      await tester.enterText(find.byType(TextField).last, 'password123');
      authGate = Completer<void>();
      await tester.tap(find.text('Sign in'));
      await tester.pump();
      expect(
        authStarted,
        isTrue,
        reason: 'Request starts before the animation finishes',
      );
      final button = find.ancestor(
        of: find.text('Sign in'),
        matching: find.byType(FilledButton),
      );
      final rect = tester.getRect(button);
      await tester.pump(const Duration(milliseconds: 850));
      expect(tester.getRect(button), rect);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      authGate!.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 850));
      await tester.pump();
      expect(
        find.text('Sign-in failed. Check your email and password.'),
        findsOneWidget,
      );
      expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('successful sign-in waits for label then opens dashboard', (
    tester,
  ) async {
    failAuth = false;
    await tester.pumpWidget(app(const AccountPage()));
    await tester.enterText(find.byType(TextField).first, 'user@example.com');
    await tester.enterText(find.byType(TextField).last, 'password123');
    await tester.tap(find.text('Sign in'));
    await tester.pump();
    expect(authStarted, isTrue);
    expect(find.byType(ModernDashboard), findsNothing);
    await tester.pump(const Duration(milliseconds: 801));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byType(ModernDashboard), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('dashboard retains records during refresh and failure', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      app(
        ModernDashboard(
          profile: const {'display_name': 'Test Admin', 'role': 'admin'},
          onSignOut: () async {},
          signingOut: false,
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('Low water pressure'), findsOneWidget);
    await screenshot(tester, 'admin-dashboard');
    refreshGate = Completer<void>();
    final refresh = tester
        .widget<RefreshIndicator>(find.byType(RefreshIndicator))
        .onRefresh();
    await tester.pump();
    expect(find.text('Low water pressure'), findsOneWidget);
    expect(find.byType(LoadingCards), findsNothing);
    failRefresh = true;
    refreshGate!.complete();
    await tester.runAsync(() => refresh);
    await tester.pump();
    expect(find.text('Low water pressure'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('client overview shows balance, due date and interruption', (
    tester,
  ) async {
    failAuth = false;
    await tester.runAsync(
      () => Supabase.instance.client.auth.signInWithPassword(
        email: 'user@example.com',
        password: 'password123',
      ),
    );
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      app(
        ModernDashboard(
          profile: const {'display_name': 'Test Client', 'role': 'client'},
          onSignOut: () async {},
          signingOut: false,
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('PHP 450.00'), findsOneWidget);
    expect(find.text('Earliest unpaid due date: 2026-11-01'), findsOneWidget);
    expect(find.text('Service interruption'), findsOneWidget);
    await screenshot(tester, 'client-dashboard');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('bill details expand and small keyboard layout stays usable', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(app(const BillsPage(isAdmin: false)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('PHP 450.00'), findsOneWidget);
    await tester.tap(find.text('Billing details'));
    await tester.pumpAndSettle();
    expect(find.text('Original bill: PHP 450.00'), findsOneWidget);
    await screenshot(tester, 'bill-details');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(
      MaterialApp(
        theme: waterTheme(),
        home: const MediaQuery(
          data: MediaQueryData(
            size: Size(320, 700),
            viewInsets: EdgeInsets.only(bottom: 280),
          ),
          child: AccountPage(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.getSize(find.byType(WaterArtwork)).height, 90);
    await tester.ensureVisible(find.text('Sign in'));
    await tester.tap(find.text('Sign in'));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('Enter a valid email address.'), findsOneWidget);
    expect(find.text('Enter your password.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'reduced motion loading is static and repair marks only recorded state',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: const Scaffold(
              body: Column(
                children: [
                  LoadingCards(count: 1),
                  RepairProgress(status: 'In progress'),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.hasRunningAnimations, isFalse);
      expect(find.byIcon(Icons.radio_button_checked), findsOneWidget);
      expect(find.text('In progress'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
