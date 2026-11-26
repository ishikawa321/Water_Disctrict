import 'dart:async';

import 'ui_components.dart';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

class ConcernLocation {
  const ConcernLocation({
    required this.latitude,
    required this.longitude,
    this.note = '',
  }) : assert(latitude >= -90 && latitude <= 90),
       assert(longitude >= -180 && longitude <= 180);

  final double latitude;
  final double longitude;
  final String note;
  LatLng get point => LatLng(latitude, longitude);
  String get coordinates =>
      '${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}';

  static ConcernLocation? fromRecord(Map<String, dynamic> record) {
    final lat = double.tryParse('${record['latitude']}');
    final lon = double.tryParse('${record['longitude']}');
    if (lat == null ||
        lon == null ||
        !lat.isFinite ||
        !lon.isFinite ||
        lat < -90 ||
        lat > 90 ||
        lon < -180 ||
        lon > 180) {
      return null;
    }
    return ConcernLocation(
      latitude: lat,
      longitude: lon,
      note: record['location_note']?.toString().trim() ?? '',
    );
  }

  Map<String, dynamic> toRecord() => {
    'latitude': latitude,
    'longitude': longitude,
    'location_note': note.trim().isEmpty ? null : note.trim(),
  };
}

typedef ConcernLocationPicker = Future<ConcernLocation?> Function(
  BuildContext context,
  ConcernLocation? initialLocation,
);

Future<ConcernLocation?> pickConcernLocation(
  BuildContext context,
  ConcernLocation? initialLocation,
) => Navigator.of(context).push<ConcernLocation>(
  MaterialPageRoute(
    builder: (_) => ConcernLocationPage(initialLocation: initialLocation),
  ),
);

class _LocationUnavailable implements Exception {
  const _LocationUnavailable(this.message);
  final String message;
}

Future<LatLng> locateConcernPosition() async {
  if (!await Geolocator.isLocationServiceEnabled()) {
    throw const _LocationUnavailable(
      'Turn on location services, or choose a pin on the map.',
    );
  }
  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }
  if (permission != LocationPermission.whileInUse &&
      permission != LocationPermission.always) {
    throw const _LocationUnavailable(
      'Location permission is unavailable. Allow it in device or browser '
      'settings, or choose a pin manually.',
    );
  }
  final position = await Geolocator.getCurrentPosition(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.high,
      timeLimit: Duration(seconds: 15),
    ),
  );
  final location = ConcernLocation.fromRecord({
    'latitude': position.latitude,
    'longitude': position.longitude,
  });
  if (location == null) {
    throw const _LocationUnavailable(
      'Could not find a valid location. Choose a pin manually.',
    );
  }
  return location.point;
}

class ConcernLocationPage extends StatefulWidget {
  const ConcernLocationPage({
    super.key,
    this.initialLocation,
    this.readOnly = false,
    this.locate,
    this.tileProvider,
  }) : assert(!readOnly || initialLocation != null);

  final ConcernLocation? initialLocation;
  final bool readOnly;
  final Future<LatLng> Function()? locate;
  final TileProvider? tileProvider;

  @override
  State<ConcernLocationPage> createState() => _ConcernLocationPageState();
}

class _ConcernLocationPageState extends State<ConcernLocationPage> {
  static const _maramag = LatLng(7.7633, 125.0058);
  static const _tileUrl = String.fromEnvironment(
    'MAP_TILE_URL',
    defaultValue: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
  );
  final _controller = MapController();
  final _form = GlobalKey<FormState>();
  late final TextEditingController _note = TextEditingController(
    text: widget.initialLocation?.note ?? '',
  );
  late LatLng? _point = widget.initialLocation?.point;
  bool _locating = false, _mapReady = false, _tileError = false;
  int _tileAttempt = 0;
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _select(LatLng point) {
    final normalized = ConcernLocation.fromRecord({
      'latitude': point.latitude,
      'longitude': point.longitude >= -180 && point.longitude <= 180
          ? point.longitude
          : (point.longitude + 180) % 360 - 180,
    });
    if (normalized == null) return;
    setState(() {
      _point = normalized.point;
      _error = null;
    });
  }

  Future<void> _useLocation() async {
    setState(() {
      _locating = true;
      _error = null;
    });
    try {
      final point = await (widget.locate ?? locateConcernPosition)();
      if (!mounted) return;
      _select(point);
      if (_mapReady) _controller.move(point, 17);
    } on _LocationUnavailable catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on TimeoutException {
      if (mounted) {
        setState(
          () => _error =
              'Location lookup timed out. You can still choose a pin manually.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not use your location. Choose a pin manually or check location permission.',
        );
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _reportTileError() {
    if (_tileError || !mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_tileError) setState(() => _tileError = true);
    });
  }

  void _confirm() {
    if (_point == null || !_form.currentState!.validate()) return;
    Navigator.of(context).pop(
      ConcernLocation(
        latitude: _point!.latitude,
        longitude: _point!.longitude,
        note: _note.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return UtilityScaffold(
      appBar: UtilityAppBar(
        title: Text(widget.readOnly ? 'Concern location' : 'Choose location'),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    widget.readOnly ? 'Reported issue location' : 'Tap the map to place the pin at the issue. Zoom in to adjust it.',
                  ),
                ),
                if (_tileError)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Map tiles could not load. Check your connection. Your selected pin is kept.',
                        ),
                        TextButton(
                          onPressed: () => setState(() {
                            _tileAttempt++;
                            _tileError = false;
                          }),
                          child: const Text('Retry map'),
                        ),
                      ],
                    ),
                  ),
                SizedBox(
                  height: (constraints.maxHeight * .55).clamp(260.0, 560.0),
                  child: Stack(
                    children: [
                      FlutterMap(
                        key: const ValueKey('concern-map'),
                        mapController: _controller,
                        options: MapOptions(
                          initialCenter:
                              widget.initialLocation?.point ?? _maramag,
                          initialZoom: widget.initialLocation == null ? 13 : 17,
                          minZoom: 3,
                          maxZoom: 19,
                          onMapReady: () => _mapReady = true,
                          onTap: widget.readOnly || _locating
                              ? null
                              : (_, point) => _select(point),
                        ),
                        children: [
                          TileLayer(
                            key: ValueKey(_tileAttempt),
                            urlTemplate: _tileUrl,
                            userAgentPackageName:
                                'ph.maramag.waterdistrictconnect',
                            tileProvider: widget.tileProvider,
                            maxNativeZoom: 19,
                            panBuffer: 0,
                            errorTileCallback: (_, _, _) => _reportTileError(),
                          ),
                          if (_point != null)
                            MarkerLayer(
                              markers: [
                                Marker(
                                  point: _point!,
                                  width: 48,
                                  height: 48,
                                  alignment: Alignment.topCenter,
                                  child: Semantics(
                                    label: 'Selected issue location',
                                    child: Icon(
                                      Icons.location_pin,
                                      key: const ValueKey(
                                        'concern-location-pin',
                                      ),
                                      size: 48,
                                      color: primary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          Align(
                            alignment: Alignment.bottomRight,
                            child: Material(
                              color: Colors.white,
                              child: InkWell(
                                onTap: () => launchUrl(
                                  Uri.parse(
                                    'https://www.openstreetmap.org/copyright',
                                  ),
                                ),
                                child: const Padding(
                                  padding: EdgeInsets.all(6),
                                  child: Text(
                                    '© OpenStreetMap contributors',
                                    textAlign: TextAlign.right,
                                    style: TextStyle(fontSize: 12),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      Positioned(
                        top: 12,
                        right: 12,
                        child: Column(
                          children: [
                            IconButton.filledTonal(
                              tooltip: 'Zoom in',
                              icon: const Icon(Icons.add),
                              onPressed: () {
                                if (_mapReady) {
                                  _controller.move(
                                    _controller.camera.center,
                                    (_controller.camera.zoom + 1).clamp(
                                      3.0,
                                      19.0,
                                    ),
                                  );
                                }
                              },
                            ),
                            const SizedBox(height: 8),
                            IconButton.filledTonal(
                              tooltip: 'Zoom out',
                              icon: const Icon(Icons.remove),
                              onPressed: () {
                                if (_mapReady) {
                                  _controller.move(
                                    _controller.camera.center,
                                    (_controller.camera.zoom - 1).clamp(
                                      3.0,
                                      19.0,
                                    ),
                                  );
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_point != null)
                        Text(
                          '${_point!.latitude.toStringAsFixed(6)}, ${_point!.longitude.toStringAsFixed(6)}',
                          key: const ValueKey('selected-coordinates'),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        )
                      else
                        const Text('No pin selected yet.'),
                      const SizedBox(height: 16),
                      if (widget.readOnly) ...[
                        if (_note.text.isNotEmpty) Text(_note.text),
                        const SizedBox(height: 16),
                        OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Done'),
                        ),
                      ] else ...[
                        OutlinedButton.icon(
                          onPressed: _locating ? null : _useLocation,
                          icon: _locating
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.my_location),
                          label: Text(
                            _locating
                                ? 'Finding location...'
                                : 'Use my location',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _note,
                          enabled: !_locating,
                          maxLength: 300,
                          minLines: 1,
                          maxLines: 3,
                          decoration: const InputDecoration(
                            labelText: 'Landmark (optional)',
                            hintText: 'For example, beside the barangay hall',
                          ),
                          validator: (value) =>
                              (value?.trim().length ?? 0) > 300
                              ? 'Use 300 characters or fewer.'
                              : null,
                        ),
                        if (_error != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Semantics(
                              liveRegion: true,
                              child: Text(
                                _error!,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                            ),
                          ),
                        FilledButton.icon(
                          onPressed: _point == null || _locating
                              ? null
                              : _confirm,
                          icon: const Icon(Icons.check),
                          label: const Text('Confirm location'),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ConcernLocationDetails extends StatelessWidget {
  const ConcernLocationDetails({
    super.key,
    required this.concern,
    this.tileProvider,
  });
  final Map<String, dynamic> concern;
  final TileProvider? tileProvider;

  @override
  Widget build(BuildContext context) {
    final location = ConcernLocation.fromRecord(concern);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Issue location',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          if (location == null)
            const Text('No location provided.')
          else ...[
            if (location.note.isNotEmpty) Text(location.note),
            Text(
              location.coordinates,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ConcernLocationPage(
                    initialLocation: location,
                    readOnly: true,
                    tileProvider: tileProvider,
                  ),
                ),
              ),
              icon: const Icon(Icons.location_on_outlined),
              label: const Text('View location'),
            ),
          ],
        ],
      ),
    );
  }
}
