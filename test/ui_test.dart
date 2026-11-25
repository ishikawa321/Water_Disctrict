import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart' show CupertinoIcons;
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
  var multipleUpdates = false;
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
    final lineIcons = File(
      'build/flutter_assets/packages/cupertino_icons/assets/CupertinoIcons.ttf',
    );
    if (await lineIcons.exists()) {
      final loader = FontLoader('packages/cupertino_icons/CupertinoIcons')
        ..addFont(
          lineIcons.readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
        );
      await loader.load();
    }
    final dmSans = FontLoader('DM Sans');
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      dmSans.addFont(File('assets/fonts/DMSans-$weight.ttf').readAsBytes()
          .then((bytes) => ByteData.sublistView(bytes)));
    }
    await dmSans.load();
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
        if (request.method == 'HEAD') {
          return http.Response('', 200, headers: {'content-range': '0-1/2'}, request: request);
        }
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
                'id': 'test-concern',
                'subject': 'Low water pressure',
                'status': 'Submitted',
                'created_at': '2026-01-01',
                'category': 'Water pressure',
                'description': 'Low pressure near the service address.',
                'admin_response': 'The district is reviewing this concern.',
                'reviewed_at': null,
                'service_accounts': {'account_number': 'WD-001'},
              },
              if (multipleUpdates) {
                'subject': 'Older request', 'status': 'Resolved',
                'created_at': '2025-12-01',
              },
            ];
          }
        } else if (request.url.path.endsWith('/account_access')) {
          body = [
            {
              'account_id': 'test-service-account',
              'service_accounts': {'account_number': 'WD-001'},
            },
          ];
        } else if (request.url.path.endsWith('/service_accounts')) {
          body = [
            {
              'id': 'test-service-account',
              'account_number': 'MWD-001245',
              'holder_name': 'Test Client',
              'service_address': 'Demo service address',
              'active': true,
            },
          ];
        } else if (request.url.path.endsWith('/bills')) {
          body = [
            {
              'id': 'test-bill',
              'bill_number': 'B-001',
              'service_accounts': {'account_number': 'WD-001'},
              'billing_period_start': '2026-10-01',
              'billing_period_end': '2026-10-31',
              'amount_due': '450.00',
              'due_date': '2026-11-01',
              'offline_payments': [],
            },
          ];
        } else if (request.url.path.endsWith('/offline_payments')) {
          body = [{
            'amount_paid': '250.00', 'payment_date': '2026-10-23',
            'verified_at': '2026-10-24', 'receipt_reference': 'DEMO-RECEIPT-001',
            'bills': {'bill_number': 'B-001', 'service_accounts': {'account_number': 'WD-001'}},
          }];
        } else if (request.url.path.endsWith('/repair_tickets')) {
          body = [{
            'id': 'test-repair', 'concern_id': 'test-concern', 'status': 'Assigned',
            'assigned_to': 'District crew', 'latest_update': 'Inspection scheduled.',
            'updated_at': '2026-10-24',
            'service_concerns': {'subject': 'Low water pressure', 'service_accounts': {'account_number': 'WD-001'}},
          }];
        } else if (request.url.path.endsWith('/announcements')) {
          body = [
            {
              'id': 'test-notice', 'published': true,
              'title': '${interruptionPrefix}Scheduled maintenance',
              'message':
                  'Water service will pause during scheduled maintenance.',
              'updated_at': '2026-10-23',
            },
            if (multipleUpdates) {
              'id': 'older-notice', 'title': 'Older notice', 'published': true,
              'message': 'Earlier district update.', 'updated_at': '2026-10-01',
            },
          ];
        } else if (request.url.path.endsWith('/logout')) {
          body = {};
        }
        return http.Response(
          jsonEncode(body),
          code,
          request: request,
          headers: {
            'content-type': 'application/json',
            if (request.method == 'HEAD') 'content-range': '0-0/1',
          },
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
    multipleUpdates = false;
  });

  Widget app(Widget child, {double textScale = 1}) => MaterialApp(
    theme: waterTheme(),
    builder: (context, navigator) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
      child: RepaintBoundary(key: boundaryKey, child: navigator!),
    ),
    home: child,
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

  testWidgets('client and admin dashboards fit narrow wide and large text layouts', (tester) async {
    failAuth = false;
    await tester.runAsync(() => Supabase.instance.client.auth.signInWithPassword(
      email: 'user@example.com', password: 'password123'));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final role in ['admin', 'client']) {
      for (final width in [320.0, 768.0]) {
        for (final scale in [1.0, 2.0]) {
          await tester.binding.setSurfaceSize(Size(width, 844));
          await tester.pumpWidget(app(ModernDashboard(
            key: ValueKey('$role/$width/$scale'),
            profile: {'display_name': 'Test User', 'role': role},
            onSignOut: () async {}, signingOut: false,
          ), textScale: scale));
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
          await tester.pumpAndSettle();
          final heading = find.text(role == 'admin' ? 'Manage district' : 'Recent request');
          await tester.ensureVisible(heading);
          await tester.pumpAndSettle();
          expect(heading, findsOneWidget);
          expect(tester.takeException(), isNull);
          await screenshot(tester, '$role-clean-${width.toInt()}-${scale.toInt()}x');
          await tester.tap(find.byTooltip('Services'));
          await tester.pumpAndSettle();
          expect(find.text(role == 'admin' ? 'Service concerns' : 'My concerns'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        }
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

  testWidgets('client profile icon opens linked account details', (tester) async {
    failAuth = false;
    await tester.runAsync(
      () => Supabase.instance.client.auth.signInWithPassword(
        email: 'user@example.com',
        password: 'password123',
      ),
    );
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(app(ModernDashboard(
      profile: const {'display_name': 'Test Client', 'role': 'client'},
      onSignOut: () async {},
      signingOut: false,
    )));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.tap(find.byTooltip('My profile'));
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
    await tester.pumpAndSettle();
    expect(find.byType(ClientAccountPage), findsOneWidget);
    expect(find.text('MWD-001245'), findsOneWidget);
    expect(find.text('Demo service address'), findsOneWidget);
    expect(find.byType(DesignHelp), findsNothing);
    await screenshot(tester, 'client-profile-clean');
    await tester.ensureVisible(find.text('Get help'));
    await tester.tap(find.text('Get help'));
    await tester.pumpAndSettle();
    expect(find.text('Account help'), findsOneWidget);
    await tester.tap(find.text('Got it'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('administrator icon keeps administrator account menu', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(app(ModernDashboard(
      profile: const {'display_name': 'Test Admin', 'role': 'admin'},
      onSignOut: () async {},
      signingOut: false,
    )));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.tap(find.byTooltip('Account menu'));
    await tester.pumpAndSettle();
    expect(find.byType(ClientAccountPage), findsNothing);
    expect(find.text('More'), findsWidgets);
    expect(find.text('Sign out'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('successful sign-in waits for label then opens dashboard', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    failAuth = false;
    await tester.pumpWidget(app(const AccountPage()));
    await tester.enterText(find.byType(TextField).first, 'user@example.com');
    await tester.enterText(find.byType(TextField).last, 'password123');
    await tester.ensureVisible(find.text('Sign in'));
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
    expect(find.text('₱450.00'), findsOneWidget);
    expect(find.text('Due 1 Nov 2026'), findsOneWidget);
    expect(find.text('Service interruption'), findsOneWidget);
    await screenshot(tester, 'client-dashboard');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('bill totals and small keyboard layout stay usable', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(app(const BillsPage(isAdmin: false)));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('₱450.00'), findsOneWidget);
    await tester.tap(find.text('Billing details'));
    await tester.pumpAndSettle();
    expect(find.text('Original bill'), findsOneWidget);
    expect(find.text('₱450.00'), findsNWidgets(2));
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

  testWidgets('dashboard keeps one latest notice and request with full notice on tap', (tester) async {
    failAuth = false;
    multipleUpdates = true;
    await tester.runAsync(() => Supabase.instance.client.auth.signInWithPassword(
      email: 'user@example.com', password: 'password123'));
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(app(ModernDashboard(
      profile: const {'display_name': 'Test Client', 'role': 'client'},
      onSignOut: () async {}, signingOut: false,
    )));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
    await tester.pumpAndSettle();
    expect(find.text('Older notice'), findsNothing);
    expect(find.text('Older request'), findsNothing);
    expect(find.text('Add bill'), findsNothing);
    expect(find.text('Record payment'), findsNothing);
    await tester.ensureVisible(find.text('Scheduled maintenance'));
    await tester.tap(find.text('Scheduled maintenance'));
    await tester.pumpAndSettle();
    expect(find.text('Water service will pause during scheduled maintenance.'), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);
    await screenshot(tester, 'notice-bottom-sheet');
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('record details expand for clients and admins with large text', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final admin in [false, true]) {
      final pages = <Widget>[
        PaymentsPage(isAdmin: admin), RepairTicketsPage(isAdmin: admin),
        AnnouncementsPage(isAdmin: admin), ConcernsPage(isAdmin: admin),
      ];
      final labels = ['Payment details', 'Repair details', 'Read notice', 'Details & response'];
      final detailTexts = ['Receipt/reference: DEMO-RECEIPT-001', 'Ticket ID: test-repair',
        'Water service will pause during scheduled maintenance.', 'District response'];
      for (var i = 0; i < pages.length; i++) {
        await tester.pumpWidget(app(pages[i], textScale: 2));
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
        await tester.pumpAndSettle();
        if (i != 2) expect(find.text(detailTexts[i]), findsNothing);
        if (i == 2) expect(find.text('Edit notice'), admin ? findsOneWidget : findsNothing);
        if (i == 1) expect(find.text('Update on desktop'), admin ? findsOneWidget : findsNothing);
        await tester.ensureVisible(find.text(labels[i]));
        await tester.tap(find.text(labels[i]));
        await tester.pumpAndSettle();
        expect(find.text(detailTexts[i]), i == 2 ? findsNWidgets(2) : findsOneWidget);
        expect(tester.takeException(), isNull);
        await screenshot(tester, '${admin ? 'admin' : 'client'}-record-$i-2x');
        await tester.pumpWidget(const SizedBox());
      }
    }
  });

  testWidgets('admin quick actions retain all management routes', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final labels = ['Accounts', 'Add bill', 'Record payment', 'Concerns', 'Repairs', 'Announcements'];
    final types = [ServiceAccountsPage, AddBillPage, RecordPaymentPage, ConcernsPage,
      RepairTicketsPage, AnnouncementsPage];
    for (var i = 0; i < labels.length; i++) {
      await tester.pumpWidget(app(ModernDashboard(
        profile: const {'display_name': 'Test Admin', 'role': 'admin'},
        onSignOut: () async {}, signingOut: false,
      )));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
      await tester.pumpAndSettle();
      final action = find.widgetWithText(InkWell, labels[i]).first;
      await tester.ensureVisible(action);
      await tester.tap(action);
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
      await tester.pumpAndSettle();
      expect(find.byType(types[i]), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    }
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
      expect(find.byIcon(CupertinoIcons.largecircle_fill_circle), findsOneWidget);
      expect(find.text('In progress'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
