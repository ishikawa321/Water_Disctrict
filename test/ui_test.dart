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
import 'package:water_district_connect/concern_location.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Completer<void>? authGate;
  Completer<void>? refreshGate;
  var authStarted = false;
  var failAuth = true;
  var registrationReady=true, pendingClient=false;
  Map<String,dynamic>? registration;
  var failRefresh = false;
  var multipleUpdates = false;
  Map<String, dynamic>? submittedConcern, reviewedConcern;
  var selectedLocationColumns = false;
  var interruptionPublished = true;
  String? concernFilter, repairFilter;
  var emptyRecords = false, failRecords = false;
  Completer<void>? recordsGate;
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
    await (FontLoader('Currency Symbols')..addFont(
      File('assets/fonts/CurrencySymbols.ttf').readAsBytes()
          .then((bytes) => ByteData.sublistView(bytes)),
    )).load();
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
        if (request.url.path.endsWith('/rpc/client_registration_approval_available')) {
          return http.Response(registrationReady ? 'true' : '{"message":"Not installed"}',
            registrationReady ? 200 : 404, request: request,
            headers: {'content-type': 'application/json'});
        }
        if (request.url.path.endsWith('/signup')) {
          registration = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(jsonEncode({'user': user}), 200, request: request,
            headers: {'content-type': 'application/json'});
        }

        if (request.url.path.startsWith('/rest/v1/') &&
            (request.method == 'GET' || request.method == 'HEAD')) {
          if (recordsGate != null) await recordsGate!.future;
          if (failRecords) {
            return http.Response(
              '{"message":"Connection unavailable"}', 503, request: request,
              headers: {'content-type': 'application/json'});
          }
        }
        if (request.url.path.endsWith('/service_concerns')) {
          if (request.method == 'POST') {
            submittedConcern = jsonDecode(request.body) as Map<String, dynamic>;
            return http.Response('', 201, request: request,
              headers: {'content-type': 'application/json'});
          }
          if (request.method == 'PATCH') {
            reviewedConcern = jsonDecode(request.body) as Map<String, dynamic>;
            return http.Response('{"id":"test-concern"}', 200, request: request,
              headers: {'content-type': 'application/json'});
          }
          selectedLocationColumns = request.url.queryParameters['select']?.contains('latitude,longitude,location_note') == true;
          concernFilter = request.url.queryParameters['id'];
        }
        if (request.method == 'HEAD') {
          return http.Response('', 200, headers: {'content-range': emptyRecords ? '*/0' : '0-1/2'}, request: request);
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
        } else if (request.url.path.endsWith('/client_registrations')) {
          body=pendingClient?[{'status':'Pending'}]:[];
        } else if (request.url.path.endsWith('/profiles')) {
          body = pendingClient?[]:[
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
                'latitude': 7.7633, 'longitude': 125.0058,
                'location_note': 'Beside the school',
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
          repairFilter = request.url.queryParameters['concern_id'];
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
              'title': '${interruptionPublished ? interruptionPrefix : ''}Scheduled maintenance',
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
        if (emptyRecords && request.url.path.startsWith('/rest/v1/') && request.method == 'GET') body = [];
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
    registrationReady=true;pendingClient=false;registration=null;
    failRefresh = false;
    multipleUpdates = false;
    submittedConcern = null;
    reviewedConcern = null;
    selectedLocationColumns = false;
    interruptionPublished = true;
    concernFilter = null;
    repairFilter = null;
    emptyRecords = false;
    failRecords = false;
    recordsGate = null;
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

  testWidgets('client registration validates confirmation and requires database setup before Auth signup', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(app(Builder(builder: (context) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: true), child: const AccountPage()))));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Create account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'New Client');
    await tester.enterText(fields.at(1), 'Maramag service address');
    await tester.enterText(fields.at(2), 'new@example.test');
    await tester.enterText(fields.at(3), 'password123');
    await tester.enterText(fields.at(4), 'different123');
    final create = find.widgetWithText(FilledButton, 'Create account');
    await tester.ensureVisible(create); await tester.pumpAndSettle();
    await tester.tap(create); await tester.pumpAndSettle();
    expect(find.text('Passwords do not match.'), findsOneWidget);
    expect(registration, isNull);
    await tester.enterText(fields.at(4), 'password123');
    registrationReady = false;
    await tester.ensureVisible(create); await tester.pumpAndSettle();
    await tester.tap(create); await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
    await tester.pumpAndSettle();
    expect(registration, isNull);
    expect(find.textContaining('database setup'), findsOneWidget);
    registrationReady = true;
    pendingClient = false;
    await tester.tap(create); await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
    await tester.pumpAndSettle();
    expect(registration?['email'], 'new@example.test');
    final metadata = registration?['data'] as Map<String, dynamic>;
    expect(metadata['display_name'], 'New Client');
    expect(metadata['service_address'], 'Maramag service address');
    expect(metadata['registration_source'], 'client_signup_v1');
    expect(metadata.containsKey('role'), isFalse);
    expect(find.textContaining('Check your email to confirm registration'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('pending client is returned to login with approval guidance', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390,844));
    addTearDown(()=>tester.binding.setSurfaceSize(null));
    failAuth=false;pendingClient=true;
    await tester.pumpWidget(app(const AccountPage()));
    await tester.enterText(find.byType(TextField).first,'user@example.com');
    await tester.enterText(find.byType(TextField).last,'password123');
    await tester.ensureVisible(find.text('Sign in'));await tester.tap(find.text('Sign in'));
    await tester.pump();await tester.pump(const Duration(milliseconds:801));
    await tester.runAsync(()=>Future<void>.delayed(const Duration(milliseconds:150)));
    await tester.pump();await tester.pump(const Duration(milliseconds:350));
    expect(find.byType(ModernDashboard),findsNothing);
    expect(find.text('Your registration is awaiting administrator approval.'),findsOneWidget);
    expect(Supabase.instance.client.auth.currentSession,isNull);
    await tester.pumpWidget(const SizedBox());
  });

  for (final admin in [false,true]) {
    testWidgets('billing history PDF downloads for ${admin ? 'admin' : 'client'}', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390,844));
      addTearDown(()=>tester.binding.setSurfaceSize(null));
      Map<Object?,Object?>? downloaded;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('net.nfet.printing'),(call) async {
          if(call.method=='sharePdf') {downloaded=Map<Object?,Object?>.from(call.arguments as Map);return 1;}
          return null;
        });
      addTearDown(()=>TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('net.nfet.printing'),null));
      await tester.pumpWidget(app(BillsPage(isAdmin:admin)));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Download billing history PDF'));
      await tester.runAsync(() async {
        await tester.tap(find.text('Download billing history PDF'));
        for(var attempt=0;attempt<100 && downloaded==null;attempt++) {
          await Future<void>.delayed(const Duration(milliseconds:20));
        }
      });
      await tester.pumpAndSettle();
      expect(downloaded,isNotNull);
      expect(downloaded!['name'],startsWith('billing-history-'));
      expect(tester.takeException(),isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('client home retains only the top announcement summary and royal blue balance', (tester) async {
    failAuth=false;
    await tester.runAsync(()=>Supabase.instance.client.auth.signInWithPassword(email:'user@example.com',password:'password123'));
    await tester.binding.setSurfaceSize(const Size(540,855));
    addTearDown(()=>tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(app(ModernDashboard(profile:const {'display_name':'Test Client','role':'client'},onSignOut:() async {},signingOut:false)));
    await tester.runAsync(()=>Future<void>.delayed(const Duration(milliseconds:150)));
    await tester.pumpAndSettle();
    expect(find.text('Announcements'),findsOneWidget);
    expect(find.text('Outstanding balance'),findsOneWidget);
    expect(royalBlue,const Color(0xFF2563EB));
    expect(UtilityStyle.blue,const Color(0xFF2563EB));
    await screenshot(tester,'client-home-blue-summary');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('client and admin dashboards fit narrow wide and large text layouts', (tester) async {
    failAuth = false;
    await tester.runAsync(() => Supabase.instance.client.auth.signInWithPassword(
      email: 'user@example.com', password: 'password123'));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final role in ['admin', 'client']) {
      for (final width in [320.0, 390.0, 768.0, 1280.0]) {
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

  Map<String, Widget Function()> auditPages() {
    const concern = <String, dynamic>{
      'id': 'test-concern', 'account_id': 'test-service-account',
      'subject': 'Low water pressure', 'category': 'Water pressure',
      'description': 'Low pressure near the service address.', 'status': 'Submitted',
      'created_at': '2026-01-01', 'admin_response': null, 'reviewed_at': null,
      'service_accounts': {'account_number': 'WD-001'},
    };
    return {
      for (final admin in [false, true]) ...{
        '${admin ? 'admin' : 'client'}-dashboard': () => ModernDashboard(
          profile: {'display_name': 'Alexandria Marie Dela Cruz', 'role': admin ? 'admin' : 'client'},
          onSignOut: () async {}, signingOut: false),
        '${admin ? 'admin' : 'client'}-bills': () => BillsPage(isAdmin: admin),
        '${admin ? 'admin' : 'client'}-payments': () => PaymentsPage(isAdmin: admin),
        '${admin ? 'admin' : 'client'}-concerns': () => ConcernsPage(isAdmin: admin),
        '${admin ? 'admin' : 'client'}-repairs': () => RepairTicketsPage(isAdmin: admin),
        '${admin ? 'admin' : 'client'}-notices': () => AnnouncementsPage(isAdmin: admin),
      },
      'client-profile': () => const ClientAccountPage(),
      'client-new-concern': () => const ConcernFormPage(),
      'admin-accounts': () => const ServiceAccountsPage(),
      'admin-new-bill': () => const AddBillPage(),
      'admin-record-payment': () => const RecordPaymentPage(),
      'admin-review': () => const ConcernFormPage(concern: concern),
      'admin-new-repair': () => const RepairTicketFormPage(),
      'admin-edit-repair': () => const RepairTicketFormPage(ticket: {
        'id': 'test-repair', 'concern_id': 'test-concern', 'status': 'Assigned',
        'assigned_to': 'District crew', 'latest_update': 'Inspection scheduled.'}),
      'admin-new-notice': () => const AnnouncementFormPage(),
      'admin-edit-notice': () => const AnnouncementFormPage(announcement: {
        'id': 'test-notice', 'title': 'Scheduled maintenance', 'message': 'District service notice.',
        'published': true}),
    };
  }

  testWidgets('signed-in visual audit covers every page at all target sizes', (tester) async {
    failAuth = false;
    await tester.runAsync(() => Supabase.instance.client.auth.signInWithPassword(
      email: 'user@example.com', password: 'password123'));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final width in [320.0, 390.0, 768.0, 1280.0]) {
      for (final scale in [1.0, 2.0]) {
        await tester.binding.setSurfaceSize(Size(width, 900));
        for (final entry in auditPages().entries) {
          await tester.pumpWidget(app(entry.value(), textScale: scale));
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull,
            reason: '${entry.key}, width=$width, text=$scale');
          final bar = find.byType(UtilityAppBar);
          if (bar.evaluate().isNotEmpty) {
            final title = find.descendant(of: bar, matching: find.byType(Text)).first;
            final barRect = tester.getRect(bar);
            final titleRect = tester.getRect(title);
            expect(titleRect.top, greaterThanOrEqualTo(barRect.top), reason: '${entry.key} title top');
            expect(titleRect.bottom, lessThanOrEqualTo(barRect.bottom), reason: '${entry.key} title bottom');
          }
          await screenshot(tester, 'audit-${entry.key}-${width.toInt()}-${scale.toInt()}x');
          final scrolls = find.byType(Scrollable);
          if (scrolls.evaluate().isNotEmpty) {
            // Inspect lower form controls and records as well as their first viewport.
            await tester.drag(scrolls.first, const Offset(0, -1600));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull, reason: '${entry.key} after scrolling');
            if (width == 320 && scale == 2) await screenshot(tester, 'audit-${entry.key}-bottom');
          }
          await tester.pumpWidget(const SizedBox());
        }
      }
    }
  }, timeout: const Timeout(Duration(minutes: 6)));

  testWidgets('signed-in data pages handle loading empty and error states', (tester) async {
    failAuth = false;
    await tester.runAsync(() => Supabase.instance.client.auth.signInWithPassword(
      email: 'user@example.com', password: 'password123'));
    await tester.binding.setSurfaceSize(const Size(320, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final state in ['loading', 'empty', 'error']) {
      emptyRecords = state == 'empty';
      failRecords = state == 'error';
      final cases = auditPages()..removeWhere((name, _) =>
        name.contains('edit-') || name == 'admin-new-account' ||
        name == 'admin-new-notice' || name == 'admin-review');
      for (final entry in cases.entries) {
        if (state == 'loading') recordsGate = Completer<void>();
        await tester.pumpWidget(app(entry.value(), textScale: 2));
        await tester.pump();
        if (state == 'loading') {
          await tester.pump(const Duration(milliseconds: 200));
        } else {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
          await tester.pumpAndSettle();
        }
        expect(tester.takeException(), isNull, reason: '${entry.key}: $state');
        await screenshot(tester, 'audit-${entry.key}-$state');
        await tester.pumpWidget(const SizedBox());
        recordsGate?.complete();
        recordsGate = null;
        await tester.pump();
      }
    }
  }, timeout: const Timeout(Duration(minutes: 4)));

  testWidgets('request preview opens its response and filters repair tracking', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    failAuth = false;
    await tester.runAsync(() => Supabase.instance.client.auth.signInWithPassword(
      email: 'user@example.com', password: 'password123'));
    await tester.pumpWidget(app(ModernDashboard(
      profile: const {'display_name': 'Test Client', 'role': 'client'},
      onSignOut: () async {}, signingOut: false)));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
    await tester.pumpAndSettle();
    expect(find.text('Maramag Water District'), findsOneWidget);
    // Wide screens put billing and requests side by side.
    expect(tester.getTopLeft(find.text('Recent request')).dx,
      greaterThan(tester.getTopLeft(find.text('Outstanding balance')).dx + 300));
    await tester.ensureVisible(find.text('Read response'));
    await tester.tap(find.text('Read response'));
    await tester.pumpAndSettle();
    expect(concernFilter, 'eq.test-concern');
    expect(find.text('District response'), findsOneWidget);
    await tester.ensureVisible(find.text('Track repair'));
    await tester.tap(find.text('Track repair'));
    await tester.pumpAndSettle();
    expect(repairFilter, 'eq.test-concern');
    // Shown in the card summary and again in its open details.
    expect(find.text('Inspection scheduled.'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('absence of a published interruption does not imply normal service', (tester) async {
    interruptionPublished = false;
    failAuth = false;
    await tester.runAsync(() => Supabase.instance.client.auth.signInWithPassword(
      email: 'user@example.com', password: 'password123'));
    await tester.pumpWidget(app(ModernDashboard(
      profile: const {'display_name': 'Test Client', 'role': 'client'},
      onSignOut: () async {}, signingOut: false)));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
    await tester.pumpAndSettle();
    expect(find.text('Announcements'), findsOneWidget);
    expect(find.text('Normal service'), findsNothing);
    expect(find.text('Read service advisory'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('payment instructions show bill references and verification next steps', (tester) async {
    await tester.pumpWidget(app(const BillsPage(isAdmin: false)));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('View payment instructions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('View payment instructions'));
    await tester.pumpAndSettle();
    expect(find.text('Account WD-001'), findsOneWidget);
    expect(find.text('Bill B-001'), findsWidgets);
    expect(find.textContaining('after district personnel verify'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
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
    expect(find.text('Announcements'), findsOneWidget);
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
    // Billing details start open; the user can still collapse them.
    expect(find.text('Original bill'), findsOneWidget);
    expect(find.text('₱450.00'), findsNWidgets(2));
    await screenshot(tester, 'bill-details');
    await tester.tap(find.text('Billing details'));
    await tester.pumpAndSettle();
    expect(find.text('Original bill'), findsNothing);
    expect(find.text('₱450.00'), findsOneWidget);
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
    await tester.tap(find.text('Announcements'));
    await tester.pumpAndSettle();
    expect(find.byType(AnnouncementsPage),findsOneWidget);
    expect(find.text('Water service will pause during scheduled maintenance.'),findsWidgets);
    await screenshot(tester,'notices-from-summary');
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
        // Payments and notices start open; Services cards (repairs i=1,
        // concerns i=3) start closed so the list stays short.
        final startsOpen = i == 0 || i == 2;
        expect(find.text(detailTexts[i]),
          i == 2 ? findsNWidgets(2) : startsOpen ? findsOneWidget : findsNothing);
        if (i == 2) expect(find.text('Edit notice'), admin ? findsOneWidget : findsNothing);
        if (i == 1) expect(find.text('Update on desktop'), admin ? findsOneWidget : findsNothing);
        await tester.ensureVisible(find.text(labels[i]));
        await tester.pumpAndSettle();
        await tester.tap(find.text(labels[i]));
        await tester.pumpAndSettle();
        // Tapping the label toggles the details.
        expect(find.text(detailTexts[i]),
          i == 2 ? findsOneWidget : startsOpen ? findsNothing : findsOneWidget);
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
      expect(tester.takeException(), isNull, reason: 'Route: ${labels[i]}');
      await tester.pumpWidget(const SizedBox());
    }
  });

  for (final withLocation in [true, false]) {
    testWidgets('concern submission saves ${withLocation ? 'confirmed coordinates' : 'an optional empty location'}', (tester) async {
      failAuth = false;
      await tester.runAsync(() => Supabase.instance.client.auth.signInWithPassword(
        email: 'user@example.com', password: 'password123'));
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var pickerCalls = 0;
      await tester.pumpWidget(app(Scaffold(body: Builder(builder: (context) => TextButton(
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ConcernFormPage(locationPicker: (_, initial) async {
            pickerCalls++;
            expect(initial, isNull);
            return const ConcernLocation(latitude: 7.7633, longitude: 125.0058, note: '  Beside the school  ');
          }),
        )), child: const Text('Open report'),
      )))));
      await tester.tap(find.text('Open report'));
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, 'Leaking water pipe');
      await tester.enterText(find.byType(TextFormField).last, 'Water has been leaking beside the school since this morning.');
      if (withLocation) {
        await tester.ensureVisible(find.text('Choose location'));
        await tester.tap(find.text('Choose location'));
        await tester.pumpAndSettle();
        expect(pickerCalls, 1);
        expect(find.text('7.763300, 125.005800'), findsOneWidget);
      }
      final submit = find.widgetWithText(FilledButton, 'Submit concern');
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
      await tester.pumpAndSettle();
      expect(submittedConcern, isNotNull);
      expect(submittedConcern!['account_id'], 'test-service-account');
      expect(submittedConcern!['submitted_by'], 'test-user');
      expect(submittedConcern!['latitude'], withLocation ? 7.7633 : null);
      expect(submittedConcern!['longitude'], withLocation ? 125.0058 : null);
      expect(submittedConcern!['location_note'], withLocation ? 'Beside the school' : null);
      expect(find.textContaining('Could not save the concern.'), findsNothing);
      expect(find.textContaining('Save could not be confirmed.'), findsNothing);
      expect(find.byType(ConcernFormPage), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('admin reads the saved pin and hands review off to desktop', (tester) async {
    failAuth = false;
    await tester.runAsync(() => Supabase.instance.client.auth.signInWithPassword(
      email: 'user@example.com', password: 'password123'));
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(app(const ConcernsPage(isAdmin: true)));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
    await tester.pumpAndSettle();
    expect(selectedLocationColumns, isTrue);
    await tester.tap(find.text('Details & response'));
    await tester.pumpAndSettle();
    expect(find.text('7.763300, 125.005800'), findsOneWidget);
    expect(find.text('View location'), findsOneWidget);
    await tester.ensureVisible(find.text('Review on desktop'));
    await tester.tap(find.text('Review on desktop'));
    await tester.pumpAndSettle();
    expect(find.text('Review concerns in the office desktop application.'), findsOneWidget);
    expect(reviewedConcern, isNull);
    expect(find.byType(ConcernFormPage), findsNothing);
    expect(find.byType(ConcernsPage), findsOneWidget);
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
      expect(find.byIcon(CupertinoIcons.largecircle_fill_circle), findsOneWidget);
      expect(find.text('In progress'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
