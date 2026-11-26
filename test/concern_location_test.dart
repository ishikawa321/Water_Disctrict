import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:water_district_connect/concern_location.dart';
import 'package:water_district_connect/main.dart';

// A local test tile: no map server or device location is accessed by these tests.
class _TestTiles extends TileProvider {
  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) =>
      MemoryImage(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGN48ObxfwAJDgOvFpv15AAAAABJRU5ErkJggg==',
        ),
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final loader = FontLoader('DM Sans');
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      loader.addFont(
        File('assets/fonts/DMSans-$weight.ttf')
            .readAsBytes()
            .then((bytes) => ByteData.sublistView(bytes)),
      );
    }
    await loader.load();
  });

  test(
    'location records preserve coordinates and trim the optional landmark',
    () {
      final location = ConcernLocation.fromRecord({
        'latitude': 0,
        'longitude': 0,
        'location_note': '  Near the school  ',
      });
      expect(location, isNotNull);
      expect(location!.toRecord(), {
        'latitude': 0.0,
        'longitude': 0.0,
        'location_note': 'Near the school',
      });
      expect(
        const ConcernLocation(
          latitude: 7,
          longitude: 125,
        ).toRecord()['location_note'],
        isNull,
      );
      for (final record in <Map<String, dynamic>>[
        {},
        {'latitude': 7},
        {'longitude': 125},
        {'latitude': 91, 'longitude': 125},
        {'latitude': 7, 'longitude': 181},
        {'latitude': double.nan, 'longitude': 125},
        {'latitude': 7, 'longitude': double.infinity},
        {'latitude': 'invalid', 'longitude': 125},
      ]) {
        expect(ConcernLocation.fromRecord(record), isNull);
      }
    },
  );

  Future<void> openPicker(
    WidgetTester tester, {
    ConcernLocation? initial,
    bool readOnly = false,
    Future<LatLng> Function()? locate,
    ValueChanged<ConcernLocation?>? onResult,
    double scale = 1,
  }) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: waterTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                final result = await Navigator.of(context)
                    .push<ConcernLocation>(
                      MaterialPageRoute(
                        builder: (_) => ConcernLocationPage(
                          initialLocation: initial,
                          readOnly: readOnly,
                          locate: locate,
                          tileProvider: _TestTiles(),
                        ),
                      ),
                    );
                onResult?.call(result);
              },
              child: const Text('Open picker'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open picker'));
    await tester.pumpAndSettle();
  }

  testWidgets('manual pin requires confirmation and saves the landmark', (
    tester,
  ) async {
    ConcernLocation? result;
    await openPicker(tester, onResult: (value) => result = value);
    final confirm = find.widgetWithText(FilledButton, 'Confirm location');
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
    expect(result, isNull);
    await tester.tapAt(
      tester.getCenter(find.byKey(const ValueKey('concern-map'))),
    );
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('concern-location-pin')), findsOneWidget);
    await tester.ensureVisible(find.byType(TextFormField));
    await tester.enterText(
      find.byType(TextFormField),
      '  Near the barangay hall  ',
    );
    await tester.ensureVisible(confirm);
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(result, isNotNull);
    expect(result!.latitude, closeTo(7.7633, .00001));
    expect(result!.longitude, closeTo(125.0058, .00001));
    expect(result!.note, 'Near the barangay hall');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('cancel does not replace an already saved pin', (tester) async {
    const initial = ConcernLocation(
      latitude: 7.7,
      longitude: 125,
      note: 'Old landmark',
    );
    ConcernLocation? result = initial;
    await openPicker(
      tester,
      initial: initial,
      onResult: (value) => result = value,
    );
    await tester.tapAt(
      tester.getCenter(find.byKey(const ValueKey('concern-map'))) +
          const Offset(50, 20),
    );
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(result, isNull);
    expect(initial.latitude, 7.7);
    expect(initial.note, 'Old landmark');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'optional GPS is only called by its button and keeps selection editable',
    (tester) async {
      var calls = 0;
      ConcernLocation? result;
      await openPicker(
        tester,
        locate: () async {
          calls++;
          return const LatLng(7.8, 125.1);
        },
        onResult: (value) => result = value,
      );
      expect(calls, 0);
      await tester.ensureVisible(find.text('Use my location'));
      await tester.tap(find.text('Use my location'));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(find.text('7.800000, 125.100000'), findsOneWidget);
      await tester.ensureVisible(find.text('Confirm location'));
      await tester.tap(find.text('Confirm location'));
      await tester.pumpAndSettle();
      expect(result!.latitude, 7.8);
      expect(result!.longitude, 125.1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('location timeout leaves manual pin selection available', (
    tester,
  ) async {
    await openPicker(
      tester,
      locate: () async => throw TimeoutException('Location unavailable'),
    );
    await tester.ensureVisible(find.text('Use my location'));
    await tester.tap(find.text('Use my location'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Location lookup timed out'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('concern-map')));
    await tester.tapAt(
      tester.getCenter(find.byKey(const ValueKey('concern-map'))),
    );
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('concern-location-pin')), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Confirm location'),
          )
          .onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('admin map displays the saved location without moving its pin', (
    tester,
  ) async {
    const initial = ConcernLocation(
      latitude: 7.8,
      longitude: 125.1,
      note: 'Near the school',
    );
    await openPicker(tester, initial: initial, readOnly: true, scale: 2);
    expect(find.text('Confirm location'), findsNothing);
    expect(find.text('Use my location'), findsNothing);
    await tester.tapAt(
      tester.getCenter(find.byKey(const ValueKey('concern-map'))) +
          const Offset(40, 10),
    );
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(
      tester.widget<MarkerLayer>(find.byType(MarkerLayer)).markers.single.point,
      initial.point,
    );
    expect(find.text('Near the school'), findsOneWidget);
    expect(find.text('7.800000, 125.100000'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('legacy concern has no broken map button', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ConcernLocationDetails(concern: {'subject': 'Older concern'}),
        ),
      ),
    );
    expect(find.text('No location provided.'), findsOneWidget);
    expect(find.text('View location'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
