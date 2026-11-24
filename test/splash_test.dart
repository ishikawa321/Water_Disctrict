import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:water_district_connect/main.dart';

void main() {
  testWidgets('splash spins for three seconds then both screens slide left', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: WaterStartup(
          initialize: () async {},
          destination: const Scaffold(body: Text('Login destination')),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(tester.hasRunningAnimations, isTrue);
    await tester.pump(const Duration(milliseconds: 2999));
    expect(find.text('Login destination'), findsNothing);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final splash = tester.getRect(find.byKey(const ValueKey('loading')));
    final login = tester.getRect(find.byKey(const ValueKey('ready')));
    expect(splash.left, lessThan(0));
    expect(login.left, greaterThan(0));
    expect(splash.right, closeTo(login.left, 1));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('loading')), findsNothing);
    expect(find.text('Login destination'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
