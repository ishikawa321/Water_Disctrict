import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:water_district_connect/main.dart';

Widget artwork({bool reducedMotion = false}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: reducedMotion),
    child: const Center(
      child: SizedBox(width: 400, height: 205, child: WaterArtwork()),
    ),
  ),
);

void main() {
  const logoKey = ValueKey('water-district-logo');

  testWidgets('logo descends after water animation and stays at landing point', (
    tester,
  ) async {
    await tester.pumpWidget(artwork());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 3999));
    expect(find.byKey(logoKey), findsNothing);
    await tester.pump(const Duration(milliseconds: 2));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final earlyTop = tester.getTopLeft(find.byKey(logoKey)).dy;
    await tester.pump(const Duration(milliseconds: 350));
    expect(tester.getTopLeft(find.byKey(logoKey)).dy, greaterThan(earlyTop));
    await tester.pump(const Duration(milliseconds: 450));
    final landing = tester.getCenter(find.byKey(logoKey));
    final waterRect = tester.getRect(find.byType(WaterArtwork));
    expect(landing.dx, closeTo(waterRect.center.dx, .01));
    expect(landing.dy, closeTo(waterRect.top + waterRect.height * .77, .01));
    await tester.pump(const Duration(seconds: 8));
    expect(tester.getCenter(find.byKey(logoKey)), landing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('reduced motion shows settled logo without animation', (tester) async {
    await tester.pumpWidget(artwork(reducedMotion: true));
    expect(find.byKey(logoKey), findsOneWidget);
    final landing = tester.getCenter(find.byKey(logoKey));
    final waterRect = tester.getRect(find.byType(WaterArtwork));
    expect(landing.dy, closeTo(waterRect.top + waterRect.height * .77, .01));
    expect(tester.hasRunningAnimations, isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
