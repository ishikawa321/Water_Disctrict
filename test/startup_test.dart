import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:water_district_connect/main.dart';

void main() {
  testWidgets('failed startup can retry and reach sign-in without restarting', (
    tester,
  ) async {
    var attempts = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: WaterStartup(
            initialize: () async {
              if (++attempts == 1) {
                throw PlatformException(code: 'storage_unavailable');
              }
            },
            destination: const Scaffold(body: Text('Sign-in ready')),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.textContaining('Could not prepare sign-in'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('Sign-in ready'), findsOneWidget);
    expect(attempts, 2);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
