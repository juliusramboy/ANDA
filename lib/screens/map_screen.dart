import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';
import '../database/database_helper.dart';
import '../models/saved_stop.dart';
import '../models/borrower.dart';
import '../models/pinned_location.dart';
import '../services/notification_service.dart';
import '../theme/app_theme.dart';
import '../widgets/vault_toast.dart';

class PlaceSuggestion {
  final String placeId;
  final String mainText;
  final String secondaryText;

  PlaceSuggestion({
    required this.placeId,
    required this.mainText,
    required this.secondaryText,
  });
}

class RouteStep {
  final LatLng startLocation;
  final LatLng endLocation;
  final String instructions;
  final String maneuver;
  final String distanceText;
  final double distanceMeters;

  RouteStep({
    required this.startLocation,
    required this.endLocation,
    required this.instructions,
    required this.maneuver,
    required this.distanceText,
    required this.distanceMeters,
  });
}

String cleanHtml(String html) {
  String text = html.replaceAll(RegExp(r'<[^>]*>'), '');
  text = text.replaceAll('&nbsp;', ' ')
             .replaceAll('&amp;', '&')
             .replaceAll('&quot;', '"')
             .replaceAll('&lt;', '<')
             .replaceAll('&gt;', '>');
  return text.trim();
}

class MapScreen extends StatefulWidget {
  final bool isNavVisible;
  const MapScreen({super.key, this.isNavVisible = true});

  @override
  State<MapScreen> createState() => MapScreenState();
}


class MapScreenState extends State<MapScreen> {
  void refresh() {
    _loadInitialData();
  }

  GoogleMapController? _mapController;
  final TextEditingController _searchCtrl = TextEditingController();

  List<SavedStop> _savedStops = [];
  List<PinnedLocation> _pinnedLocations = [];
  List<Borrower> _allBorrowers = [];

  // Track arrived stops to prevent spamming notifications
  final Set<int> _notifiedArrivalStopIds = {};

  // Live Location States
  LatLng? _currentPosition;
  StreamSubscription<Position>? _positionStreamSub;

  // Search Autocomplete Suggestion States
  List<PlaceSuggestion> _filteredSuggestions = [];
  Timer? _debounceSearch;

  // Center Geocoder
  LatLng _lastCameraPosition = const LatLng(14.5995, 120.9842);
  String _currentStreetAddress = '1100 S Flower St';
  String _currentCityAddress = 'Los Angeles, CA';
  Timer? _debounceGeocode;

  // Selected Stop Card
  SavedStop? _selectedStop;
  int _selectedStopIndex = 1;
  String _selectedStopDistance = '240m';

  // Google Maps Markers & Polylines
  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};

  // Directions routing details
  List<LatLng> _routePoints = [];
  double _totalRouteDistance = 0.0;

  // Real-time Navigation Mode States
  bool _isNavigating = false;
  List<RouteStep> _navigationSteps = [];
  int _currentStepIndex = 0;

  // Blinking / Pulsing User Location Beacon States
  bool _userLocationPulse = false;
  Timer? _userLocationPulseTimer;

  // Map Style Preset
  String _currentMapStyle = 'silver';
  String? _currentMapStyleJson = _silverMapStyleJson;
  MapType _mapType = MapType.normal;

  // API Configuration
  final String _googleApiKey = 'AIzaSyBnSl6ZeMMzocaV8A1OP70Zv8FEhyfWfGc';

  // Real location photo URLs map keyed by lat_lng
  final Map<String, String> _stopPhotoUrls = {};

  @override
  void initState() {
    super.initState();
    _loadSavedMapSettings();
    _loadInitialData();
    _startLocationTracking();
    _startUserLocationPulseAnimation();
  }

  void _startUserLocationPulseAnimation() {
    _userLocationPulseTimer?.cancel();
    _userLocationPulseTimer = Timer.periodic(const Duration(milliseconds: 700), (timer) {
      if (mounted && _currentPosition != null) {
        setState(() {
          _userLocationPulse = !_userLocationPulse;
        });
        _updateMapMarkers();
      }
    });
  }

  Future<void> _loadSavedMapSettings() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/map_settings.json');
      if (await file.exists()) {
        final content = await file.readAsString();
        final data = json.decode(content);
        if (data['mapStyle'] != null) {
          _applyMapStyle(data['mapStyle'] as String, save: false);
        }
      }
    } catch (_) {}
  }

  Future<void> _saveMapSettings(String styleKey) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/map_settings.json');
      await file.writeAsString(json.encode({'mapStyle': styleKey}));
    } catch (_) {}
  }

  String _getStopPhotoUrl(SavedStop? stop) {
    if (stop == null) return '';
    final key = '${stop.latitude}_${stop.longitude}';
    if (_stopPhotoUrls.containsKey(key)) {
      return _stopPhotoUrls[key]!;
    }
    // Authentic Google Street View Real Photo for this coordinate
    return 'https://maps.googleapis.com/maps/api/streetview?size=400x400&location=${stop.latitude},${stop.longitude}&fov=90&heading=235&pitch=10&key=$_googleApiKey';
  }


  @override
  void dispose() {
    _userLocationPulseTimer?.cancel();
    _positionStreamSub?.cancel();
    _debounceGeocode?.cancel();
    _debounceSearch?.cancel();
    _searchCtrl.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    final stops = await DatabaseHelper.instance.getAllSavedStops();
    final borrowers = await DatabaseHelper.instance.getAllBorrowers();
    final pins = await DatabaseHelper.instance.getAllPinnedLocations();
    if (mounted) {
      setState(() {
        _savedStops = stops;
        _allBorrowers = borrowers;
        _pinnedLocations = pins;
        // Do not auto-select stop so card only displays when user clicks a stop/pin
        _selectedStop = null;
      });
      _updateMapMarkers();
      if (stops.isNotEmpty) {
        _fetchRoute();
      }
    }
  }

  void _checkArrivalAtStops(LatLng userPos) {
    for (int i = 0; i < _savedStops.length; i++) {
      final stop = _savedStops[i];
      if (stop.id != null && _notifiedArrivalStopIds.contains(stop.id)) continue;
      final d = Geolocator.distanceBetween(
        userPos.latitude,
        userPos.longitude,
        stop.latitude,
        stop.longitude,
      );
      if (d <= 65.0) {
        if (stop.id != null) _notifiedArrivalStopIds.add(stop.id!);
        NotificationService.showNotification(
          id: stop.id ?? (100 + i),
          title: '📍 Arrived at Stop #${i + 1}: ${stop.name}',
          body: 'You have arrived at your route collection destination (${stop.address ?? stop.name})',
        );
        if (mounted) {
          VaultToast.showSuccess(context, '📍 Arrived at ${stop.name}!');
        }
      }
    }
  }

  Future<void> _startLocationTracking() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.deniedForever || permission == LocationPermission.denied) {
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 8),
      );

      final userLatLng = LatLng(pos.latitude, pos.longitude);

      if (mounted) {
        setState(() {
          _currentPosition = userLatLng;
          _lastCameraPosition = userLatLng;
        });

        _reverseGeocodeOnline(userLatLng).then((addr) {
          if (mounted && addr.isNotEmpty) {
            final parts = addr.split(',');
            setState(() {
              _currentStreetAddress = parts.first.trim();
              _currentCityAddress = parts.skip(1).take(2).join(',').trim();
            });
          }
        });

        _mapController?.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(target: userLatLng, zoom: 16.5, tilt: 45.0),
          ),
        );

        _checkArrivalAtStops(userLatLng);
        _updateMapMarkers();
        if (_savedStops.isNotEmpty) {
          _fetchRoute();
        }
      }

      _positionStreamSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
        ),
      ).listen((p) {
        if (mounted) {
          final newPos = LatLng(p.latitude, p.longitude);
          setState(() {
            _currentPosition = newPos;
          });
          _checkArrivalAtStops(newPos);
          _updateMapMarkers();
          if (_isNavigating) {
            _updateNavigationProgress(newPos);
          }
        }
      });
    } catch (_) {}
  }

  // ── Search & Autocomplete ──
  void _onSearchChanged(String query) {
    _debounceSearch?.cancel();
    if (query.trim().isEmpty) {
      setState(() => _filteredSuggestions = []);
      return;
    }

    _debounceSearch = Timer(const Duration(milliseconds: 300), () async {
      final List<PlaceSuggestion> results = [];

      // 1. Check matching borrowers
      for (final b in _allBorrowers) {
        if (b.fullName.toLowerCase().contains(query.toLowerCase()) ||
            b.loanReference.toLowerCase().contains(query.toLowerCase())) {
          results.add(PlaceSuggestion(
            placeId: 'borrower_${b.id}',
            mainText: b.fullName,
            secondaryText: 'Borrower • Repayment ${b.repaymentDate}',
          ));
        }
      }

      // 2. Query Google Places API
      try {
        final client = HttpClient();
        client.connectionTimeout = const Duration(seconds: 3);
        final url = Uri.parse(
          'https://maps.googleapis.com/maps/api/place/autocomplete/json'
          '?input=${Uri.encodeComponent(query)}'
          '&key=$_googleApiKey'
          '${_currentPosition != null ? '&location=${_currentPosition!.latitude},${_currentPosition!.longitude}&radius=50000' : ''}',
        );
        final req = await client.getUrl(url);
        final res = await req.close();
        if (res.statusCode == 200) {
          final body = await res.transform(utf8.decoder).join();
          final data = json.decode(body);
          if (data['status'] == 'OK' && data['predictions'] != null) {
            for (final p in data['predictions']) {
              final structured = p['structured_formatting'] ?? {};
              results.add(PlaceSuggestion(
                placeId: p['place_id'] ?? '',
                mainText: structured['main_text'] ?? p['description'] ?? '',
                secondaryText: structured['secondary_text'] ?? '',
              ));
            }
          }
        }
      } catch (_) {}

      if (mounted) {
        setState(() {
          _filteredSuggestions = results;
        });
      }
    });
  }

  Future<void> _selectSuggestion(PlaceSuggestion suggestion) async {
    _searchCtrl.text = suggestion.mainText;
    setState(() => _filteredSuggestions = []);
    FocusScope.of(context).unfocus();

    try {
      final client = HttpClient();
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/place/details/json'
        '?place_id=${suggestion.placeId}'
        '&fields=geometry,name,formatted_address,photos'
        '&key=$_googleApiKey',
      );
      final req = await client.getUrl(url);
      final res = await req.close();
      if (res.statusCode == 200) {
        final body = await res.transform(utf8.decoder).join();
        final data = json.decode(body);
        if (data['status'] == 'OK' && data['result'] != null) {
          final loc = data['result']['geometry']?['location'];
          if (loc != null) {
            final lat = (loc['lat'] as num).toDouble();
            final lng = (loc['lng'] as num).toDouble();
            final target = LatLng(lat, lng);

            if (data['result']['photos'] != null && (data['result']['photos'] as List).isNotEmpty) {
              final ref = data['result']['photos'][0]['photo_reference'];
              if (ref != null && ref.toString().isNotEmpty) {
                _stopPhotoUrls['${lat}_$lng'] =
                    'https://maps.googleapis.com/maps/api/place/photo?maxwidth=600&photo_reference=$ref&key=$_googleApiKey';
              }
            }

            final newStop = SavedStop(
              name: suggestion.mainText,
              address: data['result']['formatted_address'] ?? suggestion.secondaryText,
              latitude: lat,
              longitude: lng,
              positionOrder: _savedStops.length,
            );

            await DatabaseHelper.instance.insertSavedStop(newStop);
            await _loadInitialData();

            _mapController?.animateCamera(CameraUpdate.newLatLngZoom(target, 16.5));
          }
        }
      }
    } catch (_) {}

  }

  Future<String> _reverseGeocodeOnline(LatLng latLng) async {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 3);
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/geocode/json'
        '?latlng=${latLng.latitude},${latLng.longitude}'
        '&key=$_googleApiKey',
      );
      final req = await client.getUrl(url);
      final res = await req.close();
      if (res.statusCode == 200) {
        final body = await res.transform(utf8.decoder).join();
        final data = json.decode(body);
        if (data['status'] == 'OK' && data['results'] != null && data['results'].isNotEmpty) {
          return data['results'][0]['formatted_address'] ?? '';
        }
      }
    } catch (_) {}
    return '${latLng.latitude.toStringAsFixed(4)}, ${latLng.longitude.toStringAsFixed(4)}';
  }

  // ── Markers & Custom Glow Styling ──
  Future<BitmapDescriptor> _createGlowMarkerBitmap({
    required Color color,
    required String label,
    bool isStart = false,
  }) async {
    final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(pictureRecorder);
    const double size = 70.0;

    final Paint glowPaint = Paint()
      ..color = color.withValues(alpha: 0.25)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(const Offset(size / 2, size / 2), size / 2, glowPaint);

    final Paint innerGlowPaint = Paint()
      ..color = color.withValues(alpha: 0.45)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(const Offset(size / 2, size / 2), size / 2.8, innerGlowPaint);

    final Paint circlePaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawCircle(const Offset(size / 2, size / 2), size / 4.2, circlePaint);

    if (isStart) {
      final Paint innerHolePaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill;
      canvas.drawCircle(const Offset(size / 2, size / 2), size / 8.5, innerHolePaint);
    } else {
      final textPainter = TextPainter(
        text: TextSpan(
          text: label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w900,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset((size - textPainter.width) / 2, (size - textPainter.height) / 2),
      );
    }

    final ui.Image img = await pictureRecorder.endRecording().toImage(size.toInt(), size.toInt());
    final ByteData? byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(byteData!.buffer.asUint8List());
  }

  Color _getPinnedCategoryColor(String category) {
    switch (category.toLowerCase()) {
      case 'home':
        return const Color(0xFF0284C7); // Cyan Blue
      case 'office':
        return const Color(0xFF7C3AED); // Vivid Purple
      case 'shop':
        return const Color(0xFF059669); // Emerald Green
      case 'warehouse':
        return const Color(0xFFD97706); // Amber
      case 'custom':
      default:
        return const Color(0xFFE11D48); // Rose Crimson
    }
  }

  String _getPinnedCategoryEmoji(String category) {
    switch (category.toLowerCase()) {
      case 'home':
        return '🏠 Home';
      case 'office':
        return '🏢 Office';
      case 'shop':
        return '🏪 Shop';
      case 'warehouse':
        return '📦 Warehouse';
      case 'custom':
      default:
        return '📍 Custom Pin';
    }
  }

  Future<BitmapDescriptor> _createPinMarkerBitmap({
    required String category,
    required Color color,
  }) async {
    final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(pictureRecorder);
    const double size = 76.0;

    // Outer glow
    final Paint glowPaint = Paint()
      ..color = color.withValues(alpha: 0.25)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(const Offset(size / 2, size / 2.3), size / 2.3, glowPaint);

    // Teardrop pin body
    final Paint pinPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final Path path = Path();
    path.moveTo(size / 2, size * 0.88);
    path.cubicTo(
      size * 0.15, size * 0.55,
      size * 0.15, size * 0.2,
      size / 2, size * 0.2,
    );
    path.cubicTo(
      size * 0.85, size * 0.2,
      size * 0.85, size * 0.55,
      size / 2, size * 0.88,
    );
    path.close();
    canvas.drawPath(path, pinPaint);

    // Inner white circle
    final Paint whitePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(const Offset(size / 2, size * 0.42), size * 0.22, whitePaint);

    // Icon glyph/text
    String iconChar = '📍';
    if (category == 'home') {
      iconChar = '🏠';
    } else if (category == 'office') {
      iconChar = '🏢';
    } else if (category == 'shop') {
      iconChar = '🏪';
    } else if (category == 'warehouse') {
      iconChar = '📦';
    }

    final textPainter = TextPainter(
      text: TextSpan(
        text: iconChar,
        style: const TextStyle(fontSize: 14),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset((size - textPainter.width) / 2, (size * 0.84 - textPainter.height) / 2),
    );

    final ui.Image img = await pictureRecorder.endRecording().toImage(size.toInt(), size.toInt());
    final ByteData? byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(byteData!.buffer.asUint8List());
  }

  // ── Blinking / Pulsing User Location Marker Generator ──
  Future<BitmapDescriptor> _createUserLocationMarkerBitmap({required bool isPulsing}) async {
    final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(pictureRecorder);
    const double size = 86.0;
    const center = Offset(size / 2, size / 2);

    const Color beaconColor = Color(0xFF00E5FF); // Electric Cyan Radar
    const Color coreBlue = Color(0xFF0284C7); // Deep Sky Blue

    if (isPulsing) {
      // Expanding outer wave
      final Paint radarPaint1 = Paint()
        ..color = beaconColor.withValues(alpha: 0.28)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(center, size / 2, radarPaint1);

      // Radar ping border
      final Paint radarStroke = Paint()
        ..color = beaconColor.withValues(alpha: 0.65)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
      canvas.drawCircle(center, size / 2 - 2, radarStroke);

      final Paint radarPaint2 = Paint()
        ..color = beaconColor.withValues(alpha: 0.50)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(center, size / 2.8, radarPaint2);
    } else {
      // Focused compact beacon
      final Paint radarPaint = Paint()
        ..color = beaconColor.withValues(alpha: 0.35)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(center, size / 2.6, radarPaint);
    }

    // Outer white halo border
    final Paint whiteRingPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 14.0, whiteRingPaint);

    // Inner bright Blue Core Dot
    final Paint corePaint = Paint()
      ..color = coreBlue
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 10.0, corePaint);

    // Center Pure White Pinpoint Dot
    final Paint centerDot = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 4.0, centerDot);

    final ui.Image img = await pictureRecorder.endRecording().toImage(size.toInt(), size.toInt());
    final ByteData? byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(byteData!.buffer.asUint8List());
  }

  Future<void> _updateMapMarkers() async {
    final Set<Marker> newMarkers = {};
    const markerColor = Color(0xFF5245EC);

    // 1. Current Location Marker (Blinking Radar Beacon)
    if (_currentPosition != null) {
      final startIcon = await _createUserLocationMarkerBitmap(
        isPulsing: _userLocationPulse,
      );
      newMarkers.add(
        Marker(
          markerId: const MarkerId('current_pos'),
          position: _currentPosition!,
          icon: startIcon,
          anchor: const Offset(0.5, 0.5),
          infoWindow: const InfoWindow(title: 'Your Location (Live GPS)'),
        ),
      );
    }

    // 2. Saved Stops Markers (Collection Route)
    for (int i = 0; i < _savedStops.length; i++) {
      final stop = _savedStops[i];
      final stopIcon = await _createGlowMarkerBitmap(
        color: markerColor,
        label: '${i + 1}',
        isStart: false,
      );

      newMarkers.add(
        Marker(
          markerId: MarkerId('stop_${stop.id ?? i}'),
          position: LatLng(stop.latitude, stop.longitude),
          icon: stopIcon,
          anchor: const Offset(0.5, 0.5),
          infoWindow: InfoWindow(title: '${i + 1}. ${stop.name}', snippet: stop.address),
          onTap: () {
            setState(() {
              _selectedStop = stop;
              _selectedStopIndex = i + 1;
              if (_currentPosition != null) {
                final d = Geolocator.distanceBetween(
                  _currentPosition!.latitude,
                  _currentPosition!.longitude,
                  stop.latitude,
                  stop.longitude,
                );
                _selectedStopDistance = d < 1000 ? '${d.toInt()}m' : '${(d / 1000).toStringAsFixed(1)} km';
              }
            });
          },
        ),
      );
    }

    // 3. Custom Pinned Locations Markers (Home, Office, Shop, etc.)
    for (int i = 0; i < _pinnedLocations.length; i++) {
      final pin = _pinnedLocations[i];
      final pinColor = _getPinnedCategoryColor(pin.category);
      final pinIcon = await _createPinMarkerBitmap(
        category: pin.category,
        color: pinColor,
      );

      newMarkers.add(
        Marker(
          markerId: MarkerId('pin_${pin.id ?? i}'),
          position: LatLng(pin.latitude, pin.longitude),
          icon: pinIcon,
          anchor: const Offset(0.5, 0.88),
          infoWindow: InfoWindow(
            title: '${_getPinnedCategoryEmoji(pin.category)}: ${pin.name}',
            snippet: pin.address ?? 'Tap for details',
          ),
          onTap: () {
            _showPinnedLocationDetails(pin);
          },
        ),
      );
    }

    if (mounted) {
      setState(() {
        _markers = newMarkers;
      });
    }
  }

  // ── Zoom Out & Fit Full Route Overview ──
  Future<void> _fitFullRoute() async {
    final List<LatLng> points = [];
    if (_currentPosition != null) {
      points.add(_currentPosition!);
    }
    for (final s in _savedStops) {
      points.add(LatLng(s.latitude, s.longitude));
    }
    for (final p in _pinnedLocations) {
      points.add(LatLng(p.latitude, p.longitude));
    }
    if (_routePoints.isNotEmpty) {
      points.addAll(_routePoints);
    }

    if (points.isEmpty) {
      VaultToast.showSuccess(context, 'No route or pins to display');
      return;
    }

    if (points.length == 1) {
      _mapController?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: points.first, zoom: 16.0),
        ),
      );
      return;
    }

    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLng = points.first.longitude;

    for (final pt in points) {
      if (pt.latitude < minLat) minLat = pt.latitude;
      if (pt.latitude > maxLat) maxLat = pt.latitude;
      if (pt.longitude < minLng) minLng = pt.longitude;
      if (pt.longitude > maxLng) maxLng = pt.longitude;
    }

    final bounds = LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );

    _mapController?.animateCamera(
      CameraUpdate.newLatLngBounds(bounds, 70.0),
    );

    VaultToast.showSuccess(context, 'Zoomed to full route overview');
  }

  // ── Directions Routing ──
  Future<void> _fetchRoute() async {
    if (_currentPosition == null || _savedStops.isEmpty) {
      setState(() {
        _routePoints = [];
        _polylines = {};
      });
      return;
    }

    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 4);

      final String origin = '${_currentPosition!.latitude},${_currentPosition!.longitude}';
      final String destination = '${_savedStops.last.latitude},${_savedStops.last.longitude}';

      String waypoints = '';
      if (_savedStops.length > 1) {
        final List<String> intermediate = _savedStops
            .sublist(0, _savedStops.length - 1)
            .map((stop) => '${stop.latitude},${stop.longitude}')
            .toList();
        waypoints = '&waypoints=${intermediate.join('|')}';
      }

      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/directions/json'
        '?origin=$origin'
        '&destination=$destination'
        '$waypoints'
        '&key=$_googleApiKey',
      );

      final req = await client.getUrl(url);
      final res = await req.close();

      if (res.statusCode == 200) {
        final body = await res.transform(utf8.decoder).join();
        final data = json.decode(body);

        if (data['status'] == 'OK' && data['routes'] != null && data['routes'].isNotEmpty) {
          final route = data['routes'][0];
          final polylineStr = route['overview_polyline']?['points'] ?? '';
          final List<LatLng> decodedPoints = decodePolyline(polylineStr);

          final List<dynamic> legs = route['legs'] ?? [];
          final double totalMeters = legs.fold<double>(0.0, (sum, l) {
            final double m = (l['distance']?['value'] as num?)?.toDouble() ?? 0.0;
            return sum + m;
          });

          final List<RouteStep> stepsList = [];
          for (final leg in legs) {
            final List<dynamic> steps = leg['steps'] ?? [];
            for (final step in steps) {
              final startLat = (step['start_location']?['lat'] as num?)?.toDouble() ?? 0.0;
              final startLng = (step['start_location']?['lng'] as num?)?.toDouble() ?? 0.0;
              final endLat = (step['end_location']?['lat'] as num?)?.toDouble() ?? 0.0;
              final endLng = (step['end_location']?['lng'] as num?)?.toDouble() ?? 0.0;

              final htmlInst = step['html_instructions'] as String? ?? '';
              final maneuver = step['maneuver'] as String? ?? '';
              final distText = step['distance']?['text'] as String? ?? '';
              final distMeters = (step['distance']?['value'] as num?)?.toDouble() ?? 0.0;

              stepsList.add(RouteStep(
                startLocation: LatLng(startLat, startLng),
                endLocation: LatLng(endLat, endLng),
                instructions: cleanHtml(htmlInst),
                maneuver: maneuver,
                distanceText: distText,
                distanceMeters: distMeters,
              ));
            }
          }

          if (mounted) {
            setState(() {
              _routePoints = decodedPoints;
              _totalRouteDistance = totalMeters / 1000.0;
              _navigationSteps = stepsList;
            });
            _updatePolylines();
          }
          return;
        }
      }
    } catch (_) {}

    _calculateStraightLineRoute();
  }

  void _calculateStraightLineRoute() {
    final List<LatLng> points = [];
    final List<RouteStep> stepsList = [];
    double total = 0.0;

    if (_currentPosition != null) {
      points.add(_currentPosition!);
      LatLng lastPoint = _currentPosition!;
      for (final stop in _savedStops) {
        final stopPoint = LatLng(stop.latitude, stop.longitude);
        points.add(stopPoint);
        final dist = Geolocator.distanceBetween(
          lastPoint.latitude,
          lastPoint.longitude,
          stopPoint.latitude,
          stopPoint.longitude,
        ) / 1000.0;
        total += dist;

        stepsList.add(RouteStep(
          startLocation: lastPoint,
          endLocation: stopPoint,
          instructions: 'Proceed towards ${stop.name}',
          maneuver: 'straight',
          distanceText: '${dist.toStringAsFixed(2)} km',
          distanceMeters: dist * 1000.0,
        ));

        lastPoint = stopPoint;
      }
    }

    if (mounted) {
      setState(() {
        _routePoints = points;
        _totalRouteDistance = total;
        _navigationSteps = stepsList;
      });
      _updatePolylines();
    }
  }

  void _updatePolylines() {
    final List<LatLng> polylinePoints = [];
    if (_currentPosition != null) {
      polylinePoints.add(_currentPosition!);
    }
    for (final stop in _savedStops) {
      polylinePoints.add(LatLng(stop.latitude, stop.longitude));
    }

    setState(() {
      _polylines = {
        Polyline(
          polylineId: const PolylineId('route_path'),
          points: _routePoints.isNotEmpty ? _routePoints : polylinePoints,
          color: const Color(0xFF5245EC),
          width: 5,
          jointType: JointType.round,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
        ),
      };
    });
  }

  List<LatLng> decodePolyline(String encoded) {
    final List<LatLng> points = [];
    int index = 0, len = encoded.length;
    int lat = 0, lng = 0;

    while (index < len) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lng += dlng;

      points.add(LatLng(lat / 1E5, lng / 1E5));
    }
    return points;
  }

  void _updateNavigationProgress(LatLng userPos) {
    if (_navigationSteps.isEmpty) return;
    final currentStep = _navigationSteps[_currentStepIndex];
    final distanceToEnd = Geolocator.distanceBetween(
      userPos.latitude,
      userPos.longitude,
      currentStep.endLocation.latitude,
      currentStep.endLocation.longitude,
    );

    if (distanceToEnd < 25.0) {
      if (_currentStepIndex < _navigationSteps.length - 1) {
        setState(() => _currentStepIndex++);
      } else {
        setState(() => _isNavigating = false);
      }
    }
  }

  // ── Map Style Configuration ──
  void _applyMapStyle(String styleKey, {bool save = true}) {
    String? styleJson;
    MapType type = MapType.normal;

    if (styleKey == 'silver') {
      styleJson = _silverMapStyleJson;
    } else if (styleKey == 'retro') {
      styleJson = _retroMapStyleJson;
    } else if (styleKey == 'dark') {
      styleJson = _darkMapStyleJson;
    } else if (styleKey == 'aubergine') {
      styleJson = _aubergineMapStyleJson;
    } else if (styleKey == 'satellite') {
      type = MapType.satellite;
    } else if (styleKey == 'hybrid') {
      type = MapType.hybrid;
    }

    setState(() {
      _currentMapStyle = styleKey;
      _currentMapStyleJson = styleJson;
      _mapType = type;
    });

    if (save) {
      _saveMapSettings(styleKey);
      if (mounted) {
        VaultToast.showSuccess(context, 'Map appearance updated to ${styleKey.toUpperCase()}');
      }
    }
  }

  // ── Bottom Sheets: Settings (Map Style) ──
  void _showSettingsModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Map Appearance',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppTheme.textDark),
            ),
            const SizedBox(height: 6),
            const Text(
              'Choose your preferred navigation theme and look',
              style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStyleOption('Silver', 'silver', Icons.wb_sunny_outlined),
                _buildStyleOption('Standard', 'standard', Icons.map_outlined),
                _buildStyleOption('Retro', 'retro', Icons.filter_vintage_outlined),
                _buildStyleOption('Dark', 'dark', Icons.dark_mode_outlined),
                _buildStyleOption('Satellite', 'satellite', Icons.satellite_alt_outlined),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }


  Widget _buildStyleOption(String label, String key, IconData icon) {
    final isSelected = _currentMapStyle == key;
    return GestureDetector(
      onTap: () {
        Navigator.pop(context);
        _applyMapStyle(key);
      },
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: isSelected ? const Color(0xFF5245EC) : const Color(0xFFF1EFEA),
              borderRadius: BorderRadius.circular(16),
              border: isSelected ? Border.all(color: const Color(0xFF5245EC), width: 2) : null,
            ),
            child: Icon(
              icon,
              color: isSelected ? Colors.white : AppTheme.textDark,
              size: 24,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              color: isSelected ? const Color(0xFF5245EC) : AppTheme.textDark,
            ),
          ),
        ],
      ),
    );
  }

  // ── Bottom Sheets: Compass (Add Stops & Confirm Route) ──
  void _showAddStopsModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Plan Collection Route',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppTheme.textDark),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close, color: AppTheme.textDark),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Add Borrower as Stop Quick Action
              const Text(
                'ADD BORROWER TO ROUTE',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Color(0xFF64748B), letterSpacing: 0.5),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 40,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _allBorrowers.length,
                  itemBuilder: (context, i) {
                    final b = _allBorrowers[i];
                    return GestureDetector(
                      onTap: () async {
                        final newStop = SavedStop(
                          name: b.fullName,
                          address: 'Borrower Repayment Stop • Due ${b.repaymentDate}',
                          latitude: _currentPosition != null ? _currentPosition!.latitude + ((i + 1) * 0.005) : 14.5995,
                          longitude: _currentPosition != null ? _currentPosition!.longitude + ((i + 1) * 0.005) : 120.9842,
                          positionOrder: _savedStops.length,
                        );
                        await DatabaseHelper.instance.insertSavedStop(newStop);
                        await _loadInitialData();
                        setModalState(() {});
                      },
                      child: Container(
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1EFEA),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '+ ${b.fullName}',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textDark),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),

              // Current Stops List
              Text(
                'ACTIVE STOPS (${_savedStops.length})',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Color(0xFF64748B), letterSpacing: 0.5),
              ),
              const SizedBox(height: 8),
              if (_savedStops.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: Text('No stops added yet. Tap a borrower or search above.', style: TextStyle(color: Color(0xFF64748B))),
                  ),
                )
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 180),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _savedStops.length,
                    itemBuilder: (context, i) {
                      final s = _savedStops[i];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFAF8F5),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.black.withValues(alpha: 0.04)),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 12,
                              backgroundColor: const Color(0xFF5245EC),
                              child: Text('${i + 1}', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                s.name,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textDark),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: AppTheme.red, size: 20),
                              onPressed: () async {
                                if (s.id != null) {
                                  await DatabaseHelper.instance.deleteSavedStop(s.id!);
                                  await _loadInitialData();
                                  setModalState(() {});
                                }
                              },
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              const SizedBox(height: 16),

              // Confirm Route Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _fetchRoute();
                    VaultToast.showSuccess(
                      context,
                      'Route confirmed! Polylines and stops updated on map.',
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF5245EC),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Confirm Route', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
                      SizedBox(width: 8),
                      Icon(Icons.arrow_forward, size: 18),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Bottom Sheets: Activity (Route Timeline & Navigation) ──
  void _showActivityModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Route Activity',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppTheme.textDark),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(ctx),
                  icon: const Icon(Icons.close, color: AppTheme.textDark),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Total distance: ${_totalRouteDistance.toStringAsFixed(2)} km • ${_savedStops.length} Stops',
              style: const TextStyle(fontSize: 13, color: Color(0xFF64748B), fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),

            if (_navigationSteps.isNotEmpty)
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _navigationSteps.length,
                  itemBuilder: (context, i) {
                    final step = _navigationSteps[i];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: const BoxDecoration(
                              color: Color(0xFFEEF2FF),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.navigation_rounded, size: 16, color: Color(0xFF5245EC)),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  step.instructions,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textDark),
                                ),
                                Text(
                                  step.distanceText,
                                  style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              )
            else
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: Text('No route steps yet. Add stops and tap Confirm Route in the compass menu.'),
                ),
              ),

            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  setState(() {
                    _isNavigating = true;
                    _currentStepIndex = 0;
                  });
                  _mapController?.animateCamera(
                    CameraUpdate.newCameraPosition(
                      CameraPosition(
                        target: _currentPosition ?? const LatLng(14.5995, 120.9842),
                        zoom: 18.0,
                        tilt: 45.0,
                      ),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF5245EC),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.near_me_rounded, size: 20),
                    SizedBox(width: 8),
                    Text('Start Live Navigation', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // ── 1. Google Map View ──
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: _currentPosition ?? const LatLng(14.5995, 120.9842),
              zoom: 16.5,
            ),
            mapType: _mapType,
            style: _currentMapStyleJson,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            markers: _markers,
            polylines: _polylines,
            onTap: (pos) {
              setState(() {
                _selectedStop = null;
              });
            },
            onMapCreated: (controller) {
              _mapController = controller;
            },
            onCameraMove: (pos) {
              _lastCameraPosition = pos.target;
            },
            onLongPress: (pos) {
              _showAddPinModal(pos);
            },
            onCameraIdle: () {
              _debounceGeocode?.cancel();
              _debounceGeocode = Timer(const Duration(milliseconds: 500), () async {
                final addr = await _reverseGeocodeOnline(_lastCameraPosition);
                if (mounted && addr.isNotEmpty) {
                  final parts = addr.split(',');
                  setState(() {
                    _currentStreetAddress = parts.first.trim();
                    _currentCityAddress = parts.skip(1).take(2).join(',').trim();
                  });
                }
              });
            },
          ),

          // ── 2. Top Header & Search Area ──
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Floating Search Bar Row (Moved up, MAP word removed)
                  Row(
                    children: [
                      if (Navigator.canPop(context)) ...[
                        GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.10),
                                  blurRadius: 12,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: const Icon(Icons.arrow_back, color: AppTheme.textDark, size: 20),
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      Expanded(
                        child: Container(
                          height: 48,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(30),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.08),
                                blurRadius: 16,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              const Icon(Icons.search, color: Color(0xFF64748B), size: 20),
                              const SizedBox(width: 10),
                              Expanded(
                                child: TextField(
                                  controller: _searchCtrl,
                                  onChanged: _onSearchChanged,
                                  textAlignVertical: TextAlignVertical.center,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: AppTheme.textDark,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  decoration: const InputDecoration(
                                    hintText: 'e.g. burgers, fries, pasta',
                                    hintStyle: TextStyle(
                                      color: Color(0xFF94A3B8),
                                      fontSize: 14,
                                      fontWeight: FontWeight.normal,
                                    ),
                                    border: InputBorder.none,
                                    isDense: true,
                                    contentPadding: EdgeInsets.symmetric(vertical: 12),
                                  ),
                                ),
                              ),
                              if (_searchCtrl.text.isNotEmpty)
                                GestureDetector(
                                  onTap: () {
                                    _searchCtrl.clear();
                                    _onSearchChanged('');
                                  },
                                  child: const Padding(
                                    padding: EdgeInsets.all(4.0),
                                    child: Icon(Icons.close_rounded, size: 18, color: Color(0xFF64748B)),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),

                  // Autocomplete List Overlay
                  if (_filteredSuggestions.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      constraints: const BoxConstraints(maxHeight: 200),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        shrinkWrap: true,
                        itemCount: _filteredSuggestions.length,
                        itemBuilder: (ctx, idx) {
                          final suggestion = _filteredSuggestions[idx];
                          return ListTile(
                            leading: const Icon(Icons.location_on_outlined, color: Color(0xFF5245EC)),
                            title: Text(suggestion.mainText, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                            subtitle: Text(suggestion.secondaryText, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                            onTap: () => _selectSuggestion(suggestion),
                          );
                        },
                      ),
                    ),

                  const SizedBox(height: 10),

                  // Current Street / Location Callout Card (Floating Frosted Badge)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.94),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFFE2E8F0), width: 0.8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.06),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _currentStreetAddress,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF0F172A),
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          _currentCityAddress,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── 3. Right Side Floating Quick Actions Column ──
          Positioned(
            right: 18,
            top: MediaQuery.of(context).padding.top + 115,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 1. Zoom Out / Fit Full Route Button
                _buildMapFloatingCircleButton(
                  icon: Icons.zoom_out_map_rounded,
                  tooltip: 'Fit Full Route',
                  color: const Color(0xFF5245EC),
                  iconColor: Colors.white,
                  onTap: _fitFullRoute,
                ),
                const SizedBox(height: 10),

                // 2. Saved Places / Pins List Button
                _buildMapFloatingCircleButton(
                  icon: Icons.push_pin_rounded,
                  tooltip: 'My Places',
                  color: Colors.white,
                  iconColor: const Color(0xFF5245EC),
                  badgeText: _pinnedLocations.isNotEmpty ? '${_pinnedLocations.length}' : null,
                  onTap: _showSavedPinsModal,
                ),
                const SizedBox(height: 10),

                // 3. Drop New Pin at Current View Center
                _buildMapFloatingCircleButton(
                  icon: Icons.add_location_alt_outlined,
                  tooltip: 'Pin This Spot',
                  color: Colors.white,
                  iconColor: const Color(0xFF0F172A),
                  onTap: () => _showAddPinModal(_lastCameraPosition),
                ),
                const SizedBox(height: 10),

                // 4. Center on User Location
                _buildMapFloatingCircleButton(
                  icon: Icons.my_location_rounded,
                  tooltip: 'My Location',
                  color: Colors.white,
                  iconColor: const Color(0xFF0F172A),
                  onTap: () {
                    if (_currentPosition != null) {
                      _mapController?.animateCamera(
                        CameraUpdate.newCameraPosition(
                          CameraPosition(target: _currentPosition!, zoom: 17.0, tilt: 35.0),
                        ),
                      );
                    } else {
                      _startLocationTracking();
                    }
                  },
                ),
              ],
            ),
          ),

          // ── 4. Bottom Overlays (Selected Stop Card & Bottom Floating Bar) ──
          AnimatedPositioned(
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeInOutCubic,
            left: 20,
            right: 20,
            bottom: widget.isNavVisible ? 100.0 : 24.0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Floating Stop Card (Shown only when a stop or pin is selected)
                if (_selectedStop != null) ...[
                  _buildFloatingStopCard(),
                  const SizedBox(height: 14),
                ],

                // Custom Floating Action Bar (Settings, Raised Compass, Activity)
                _buildBottomActionBar(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Floating Stop Card Widget (with Authentic Location Photo & Dismiss Button) ──
  Widget _buildFloatingStopCard() {
    if (_selectedStop == null) return const SizedBox.shrink();

    final stopName = _selectedStop!.name;
    final address = _selectedStop!.address ?? '';
    final photoUrl = _getStopPhotoUrl(_selectedStop);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.all(12),
      child: Stack(
        children: [
          Row(
            children: [
              // Left Thumbnail (Real Location Photo)
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  width: 78,
                  height: 78,
                  color: const Color(0xFFEDE8E1),
                  child: photoUrl.isNotEmpty
                      ? Image.network(
                          photoUrl,
                          fit: BoxFit.cover,
                          loadingBuilder: (ctx, child, progress) {
                            if (progress == null) return child;
                            return const Center(
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Color(0xFF5245EC),
                                ),
                              ),
                            );
                          },
                          errorBuilder: (ctx, err, stack) {
                            return const Center(
                              child: Icon(
                                Icons.location_city_rounded,
                                color: Color(0xFFC68A0E),
                                size: 32,
                              ),
                            );
                          },
                        )
                      : const Center(
                          child: Icon(
                            Icons.restaurant_rounded,
                            color: Color(0xFFC68A0E),
                            size: 32,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 12),

              // Right Stop Info
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        stopName.startsWith('1.') || stopName.startsWith('2.') ? stopName : '$_selectedStopIndex. $stopName',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF0F172A),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          const Icon(Icons.navigation_outlined, size: 12, color: Color(0xFF64748B)),
                          const SizedBox(width: 4),
                          Text(
                            _selectedStopDistance,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      const Row(
                        children: [
                          Text('★★★★★', style: TextStyle(color: Color(0xFF5245EC), fontSize: 11)),
                          SizedBox(width: 6),
                          Text(
                            '12 reviews',
                            style: TextStyle(fontSize: 11, color: Color(0xFF5245EC), fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        address,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8)),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          Positioned(
            top: -4,
            right: -4,
            child: IconButton(
              icon: const Icon(Icons.close, size: 18, color: Color(0xFF94A3B8)),
              onPressed: () {
                setState(() {
                  _selectedStop = null;
                });
              },
            ),
          ),
        ],
      ),
    );
  }


  // ── Custom Bottom Action Bar Widget ──
  Widget _buildBottomActionBar() {
    return Container(
      height: 72,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Left: Settings Button
          GestureDetector(
            onTap: _showSettingsModal,
            behavior: HitTestBehavior.opaque,
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.settings_outlined, color: Color(0xFF5245EC), size: 24),
                SizedBox(height: 2),
                Text(
                  'Settings',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),

          // Center: Raised Compass Floating Button
          Transform.translate(
            offset: const Offset(0, -18),
            child: GestureDetector(
              onTap: _showAddStopsModal,
              child: Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: const Color(0xFF5245EC),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 4),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF5245EC).withValues(alpha: 0.4),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.explore_outlined,
                  color: Colors.white,
                  size: 28,
                ),
              ),
            ),
          ),

          // Right: Activity Button
          GestureDetector(
            onTap: _showActivityModal,
            behavior: HitTestBehavior.opaque,
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.show_chart_rounded, color: Color(0xFF5245EC), size: 24),
                SizedBox(height: 2),
                Text(
                  'Activity',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Floating Circular Action Button with Tooltip & Badge ──
  Widget _buildMapFloatingCircleButton({
    required IconData icon,
    required String tooltip,
    required Color color,
    required Color iconColor,
    String? badgeText,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Tooltip(
        message: tooltip,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            if (badgeText != null)
              Positioned(
                top: -3,
                right: -3,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE11D48),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  child: Text(
                    badgeText,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── Show Add Pin Modal ──
  Future<void> _showAddPinModal([LatLng? initialCoord]) async {
    final LatLng targetCoord = initialCoord ?? _lastCameraPosition;
    String detectedAddress = 'Fetching address...';

    String selectedCategory = 'home';
    final nameCtrl = TextEditingController(text: 'My Home');
    final addressCtrl = TextEditingController();

    _reverseGeocodeOnline(targetCoord).then((addr) {
      if (addr.isNotEmpty) {
        detectedAddress = addr;
        addressCtrl.text = addr;
      }
    });

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return Container(
            padding: EdgeInsets.fromLTRB(
              24, 20, 24, MediaQuery.of(context).viewInsets.bottom + 24,
            ),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Pin a Location',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.textDark,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Category Selector Chips
                const Text(
                  'SELECT PLACE TYPE',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF94A3B8),
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildCategoryChip('home', '🏠 Home', selectedCategory, (cat) {
                        setModalState(() {
                          selectedCategory = cat;
                          if (nameCtrl.text.isEmpty || nameCtrl.text.startsWith('My ')) {
                            nameCtrl.text = 'My Home';
                          }
                        });
                      }),
                      const SizedBox(width: 8),
                      _buildCategoryChip('office', '🏢 Office', selectedCategory, (cat) {
                        setModalState(() {
                          selectedCategory = cat;
                          if (nameCtrl.text.isEmpty || nameCtrl.text.startsWith('My ')) {
                            nameCtrl.text = 'Main Office';
                          }
                        });
                      }),
                      const SizedBox(width: 8),
                      _buildCategoryChip('shop', '🏪 Shop', selectedCategory, (cat) {
                        setModalState(() {
                          selectedCategory = cat;
                          if (nameCtrl.text.isEmpty || nameCtrl.text.startsWith('My ') || nameCtrl.text == 'Main Office') {
                            nameCtrl.text = 'Branch Shop';
                          }
                        });
                      }),
                      const SizedBox(width: 8),
                      _buildCategoryChip('warehouse', '📦 Warehouse', selectedCategory, (cat) {
                        setModalState(() {
                          selectedCategory = cat;
                          if (nameCtrl.text.isEmpty || nameCtrl.text.startsWith('My ') || nameCtrl.text == 'Branch Shop') {
                            nameCtrl.text = 'Storage Hub';
                          }
                        });
                      }),
                      const SizedBox(width: 8),
                      _buildCategoryChip('custom', '📍 Custom', selectedCategory, (cat) {
                        setModalState(() {
                          selectedCategory = cat;
                          if (nameCtrl.text.isEmpty || nameCtrl.text.startsWith('My ')) {
                            nameCtrl.text = 'Favorite Spot';
                          }
                        });
                      }),
                    ],
                  ),
                ),

                const SizedBox(height: 18),

                // Name Input Field
                TextField(
                  controller: nameCtrl,
                  decoration: InputDecoration(
                    labelText: 'Place Name / Label',
                    labelStyle: const TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.bold),
                    hintText: 'e.g. My Home, Head Office, Makati Branch',
                    prefixIcon: const Icon(Icons.label_outline, color: Color(0xFF5245EC)),
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // Address Input Field
                TextField(
                  controller: addressCtrl,
                  decoration: InputDecoration(
                    labelText: 'Address / Location Notes',
                    labelStyle: const TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.bold),
                    hintText: 'e.g. 123 Rizal St., Poblacion',
                    prefixIcon: const Icon(Icons.location_on_outlined, color: Color(0xFF5245EC)),
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                  ),
                ),
                const SizedBox(height: 8),

                Text(
                  'Coordinates: ${targetCoord.latitude.toStringAsFixed(5)}, ${targetCoord.longitude.toStringAsFixed(5)}',
                  style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8), fontWeight: FontWeight.w600),
                ),

                const SizedBox(height: 20),

                // Save Pin Button
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: () async {
                      final name = nameCtrl.text.trim();
                      if (name.isEmpty) {
                        VaultToast.showError(context, 'Please enter a name for this pinned place');
                        return;
                      }

                      final newPin = PinnedLocation(
                        name: name,
                        address: addressCtrl.text.trim().isNotEmpty ? addressCtrl.text.trim() : detectedAddress,
                        latitude: targetCoord.latitude,
                        longitude: targetCoord.longitude,
                        category: selectedCategory,
                      );

                      await DatabaseHelper.instance.insertPinnedLocation(newPin);
                      if (ctx.mounted) {
                        Navigator.pop(ctx);
                      }
                      await _loadInitialData();

                      _mapController?.animateCamera(
                        CameraUpdate.newCameraPosition(
                          CameraPosition(target: targetCoord, zoom: 17.0, tilt: 30.0),
                        ),
                      );

                      if (mounted) {
                        VaultToast.showSuccess(context, 'Pinned ${newPin.name} (${_getPinnedCategoryEmoji(selectedCategory)})');
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF5245EC),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 0,
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.push_pin_rounded, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Save Pin to Map',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildCategoryChip(String key, String label, String selected, ValueChanged<String> onSelect) {
    final isSelected = key == selected;
    return GestureDetector(
      onTap: () => onSelect(key),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF5245EC) : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? const Color(0xFF5245EC) : const Color(0xFFE2E8F0),
            width: 1.2,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: isSelected ? Colors.white : const Color(0xFF334155),
          ),
        ),
      ),
    );
  }

  // ── Show Pinned Location Details Modal ──
  void _showPinnedLocationDetails(PinnedLocation pin) {
    final categoryColor = _getPinnedCategoryColor(pin.category);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: categoryColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _getPinnedCategoryEmoji(pin.category),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      color: categoryColor,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
            const SizedBox(height: 8),

            Text(
              pin.name,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              pin.address ?? 'Pinned location',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Coordinates: ${pin.latitude.toStringAsFixed(5)}, ${pin.longitude.toStringAsFixed(5)}',
              style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
            ),

            const SizedBox(height: 22),

            Row(
              children: [
                // Add to Route Button
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      if (ctx.mounted) {
                        Navigator.pop(ctx);
                      }
                      final newStop = SavedStop(
                        name: pin.name,
                        address: pin.address,
                        latitude: pin.latitude,
                        longitude: pin.longitude,
                        positionOrder: _savedStops.length,
                      );
                      await DatabaseHelper.instance.insertSavedStop(newStop);
                      await _loadInitialData();
                      if (mounted) {
                        VaultToast.showSuccess(context, 'Added ${pin.name} to Collection Route');
                      }
                    },
                    icon: const Icon(Icons.add_road_rounded, size: 18),
                    label: const Text('Add to Route', style: TextStyle(fontWeight: FontWeight.bold)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF5245EC),
                      side: const BorderSide(color: Color(0xFF5245EC), width: 1.5),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                // Delete Pin Button
                IconButton(
                  onPressed: () async {
                    if (pin.id != null) {
                      await DatabaseHelper.instance.deletePinnedLocation(pin.id!);
                      if (ctx.mounted) {
                        Navigator.pop(ctx);
                      }
                      await _loadInitialData();
                      if (mounted) {
                        VaultToast.showSuccess(context, 'Removed pin ${pin.name}');
                      }
                    }
                  },
                  icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444)),
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0xFFFEE2E2),
                    padding: const EdgeInsets.all(12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Show Saved Pins List Modal ──
  void _showSavedPinsModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return Container(
            padding: const EdgeInsets.all(24),
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.75,
            ),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Saved Places & Pins',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.textDark,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${_pinnedLocations.length} Custom Pinned Locations',
                  style: const TextStyle(fontSize: 13, color: Color(0xFF64748B), fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 14),

                if (_pinnedLocations.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 36),
                    child: Center(
                      child: Column(
                        children: [
                          Icon(Icons.push_pin_outlined, size: 48, color: Colors.grey.shade400),
                          const SizedBox(height: 12),
                          const Text(
                            'No pinned locations yet',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF64748B)),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Long-press anywhere on the map or tap Pin This Spot to save your home, office, or branch.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _pinnedLocations.length,
                      itemBuilder: (context, i) {
                        final pin = _pinnedLocations[i];
                        final catColor = _getPinnedCategoryColor(pin.category);

                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: ListTile(
                            leading: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: catColor.withValues(alpha: 0.15),
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: Text(
                                  _getPinnedCategoryEmoji(pin.category).split(' ').first,
                                  style: const TextStyle(fontSize: 18),
                                ),
                              ),
                            ),
                            title: Text(
                              pin.name,
                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppTheme.textDark),
                            ),
                            subtitle: Text(
                              pin.address ?? '${pin.latitude.toStringAsFixed(4)}, ${pin.longitude.toStringAsFixed(4)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline, color: Color(0xFFEF4444), size: 20),
                              onPressed: () async {
                                if (pin.id != null) {
                                  await DatabaseHelper.instance.deletePinnedLocation(pin.id!);
                                  await _loadInitialData();
                                  setModalState(() {});
                                }
                              },
                            ),
                            onTap: () {
                              Navigator.pop(ctx);
                              _mapController?.animateCamera(
                                CameraUpdate.newCameraPosition(
                                  CameraPosition(
                                    target: LatLng(pin.latitude, pin.longitude),
                                    zoom: 17.0,
                                    tilt: 30.0,
                                  ),
                                ),
                              );
                              _showPinnedLocationDetails(pin);
                            },
                          ),
                        );
                      },
                    ),
                  ),

                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _showAddPinModal(_lastCameraPosition);
                    },
                    icon: const Icon(Icons.add_location_alt_outlined, size: 20),
                    label: const Text('Add New Pin at Current View', style: TextStyle(fontWeight: FontWeight.w900)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF5245EC),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ── Map Style JSON Presets ──
  static const String _silverMapStyleJson = '''
  [
    {"elementType": "geometry", "stylers": [{"color": "#f5f5f5"}]},
    {"elementType": "labels.icon", "stylers": [{"visibility": "off"}]},
    {"elementType": "labels.text.fill", "stylers": [{"color": "#616161"}]},
    {"elementType": "labels.text.stroke", "stylers": [{"color": "#f5f5f5"}]},
    {"featureType": "administrative.land_parcel", "elementType": "labels.text.fill", "stylers": [{"color": "#bdbdbd"}]},
    {"featureType": "poi", "elementType": "geometry", "stylers": [{"color": "#eeeeee"}]},
    {"featureType": "poi", "elementType": "labels.text.fill", "stylers": [{"color": "#757575"}]},
    {"featureType": "road", "elementType": "geometry", "stylers": [{"color": "#ffffff"}]},
    {"featureType": "road.arterial", "elementType": "labels.text.fill", "stylers": [{"color": "#757575"}]},
    {"featureType": "road.highway", "elementType": "geometry", "stylers": [{"color": "#dadada"}]},
    {"featureType": "road.highway", "elementType": "labels.text.fill", "stylers": [{"color": "#616161"}]},
    {"featureType": "water", "elementType": "geometry", "stylers": [{"color": "#c9c9c9"}]}
  ]
  ''';

  static const String _retroMapStyleJson = '''
  [
    {"elementType": "geometry", "stylers": [{"color": "#ebe3cd"}]},
    {"elementType": "labels.text.fill", "stylers": [{"color": "#523735"}]},
    {"elementType": "labels.text.stroke", "stylers": [{"color": "#f5f1e6"}]},
    {"featureType": "road", "elementType": "geometry", "stylers": [{"color": "#f5f1e6"}]},
    {"featureType": "road.highway", "elementType": "geometry", "stylers": [{"color": "#f8c967"}]},
    {"featureType": "water", "elementType": "geometry", "stylers": [{"color": "#b9d3c2"}]}
  ]
  ''';

  static const String _darkMapStyleJson = '''
  [
    {"elementType": "geometry", "stylers": [{"color": "#212121"}]},
    {"elementType": "labels.text.fill", "stylers": [{"color": "#757575"}]},
    {"elementType": "road", "elementType": "geometry", "stylers": [{"color": "#2c2c2c"}]},
    {"featureType": "water", "elementType": "geometry", "stylers": [{"color": "#000000"}]}
  ]
  ''';

  static const String _aubergineMapStyleJson = '''
  [
    {"elementType": "geometry", "stylers": [{"color": "#1d2c4d"}]},
    {"elementType": "labels.text.fill", "stylers": [{"color": "#8ec3b9"}]},
    {"featureType": "road", "elementType": "geometry", "stylers": [{"color": "#243761"}]},
    {"featureType": "water", "elementType": "geometry", "stylers": [{"color": "#0e1626"}]}
  ]
  ''';
}
