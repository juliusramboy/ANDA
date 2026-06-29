import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../database/database_helper.dart';
import '../models/saved_stop.dart';
import '../theme/app_theme.dart';

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
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  GoogleMapController? _mapController;
  final TextEditingController _searchCtrl = TextEditingController();

  // Database list of saved stops (persisted in SQLite)
  List<SavedStop> _savedStops = [];

  // Live Location States
  LatLng? _currentPosition;
  StreamSubscription<Position>? _positionStreamSub;
  bool _fetchingLocation = true;

  // Search Autocomplete Suggestion States
  List<PlaceSuggestion> _filteredSuggestions = [];
  Timer? _debounceSearch;
  bool _isOffline = false;

  // Center Stationary Pin States
  LatLng _lastCameraPosition = const LatLng(14.5995, 120.9842);
  String _centerAddress = 'Drag map to choose location';
  bool _fetchingAddress = false;
  Timer? _debounceGeocode;

  // Temporary Search Marker and Info Card Overlay States
  LatLng? _tempLatLng;
  String? _tempName;
  String? _tempAddress;
  bool _showTempCard = false;

  // Timeline list state
  bool _isRouteSummaryMinimized = true;

  // Camera tracking/responsiveness states
  bool _followUserLocation = true;
  bool _isProgrammaticMovement = false;

  // Google Maps Markers & Polylines
  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};

  // Directions routing details
  List<LatLng> _routePoints = [];
  List<double> _routeLegDistances = [];
  double _totalRouteDistance = 0.0;
  bool _fetchingRoute = false;

  // Real-time Navigation Mode States
  bool _isNavigating = false;
  List<RouteStep> _navigationSteps = [];
  int _currentStepIndex = 0;
  bool _isMapDragging = false;
  final Map<String, BitmapDescriptor> _markerIconCache = {};

  // API Configuration
  final String _googleApiKey = 'AIzaSyBnSl6ZeMMzocaV8A1OP70Zv8FEhyfWfGc';
  bool _showRouteControls = true;

  // Local Preset Fallbacks if completely offline
  final List<PlaceSuggestion> _localPresets = [
    PlaceSuggestion(placeId: 'preset_1', mainText: 'SM Megamall', secondaryText: 'EDSA, Mandaluyong, Manila'),
    PlaceSuggestion(placeId: 'preset_2', mainText: 'Juan Dela Cruz residence', secondaryText: 'Sampaloc, Manila'),
    PlaceSuggestion(placeId: 'preset_3', mainText: 'Bank Vault', secondaryText: 'Intramuros, Manila'),
  ];

  @override
  void initState() {
    super.initState();
    _checkConnectivity();
    _loadSavedStops();
    _startLocationTracking();
  }

  @override
  void dispose() {
    _positionStreamSub?.cancel();
    _debounceGeocode?.cancel();
    _debounceSearch?.cancel();
    _searchCtrl.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  // Check online connectivity
  Future<void> _checkConnectivity() async {
    setState(() => _isOffline = false);
  }

  // Load Saved Stops from SQLite
  Future<void> _loadSavedStops() async {
    final list = await DatabaseHelper.instance.getAllSavedStops();
    setState(() {
      _savedStops = list;
    });
    await _updateMapMarkers();
    await _fetchRoute();
  }

  // Initialize and listen to Live GPS location
  Future<void> _startLocationTracking() async {
    setState(() => _fetchingLocation = true);

    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _useFallbackLocation();
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        _useFallbackLocation();
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      _useFallbackLocation();
      return;
    }

    // Get initial position
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 4),
      );
      final latLng = LatLng(pos.latitude, pos.longitude);
      if (mounted) {
        setState(() {
          _currentPosition = latLng;
          _fetchingLocation = false;
        });
        _isProgrammaticMovement = true;
        _mapController?.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: latLng,
              zoom: 16.5,
              tilt: 45.0,
            ),
          ),
        );
        _fetchAddressForPoint(latLng);
        _fetchRoute();
      }
    } catch (_) {
      _useFallbackLocation();
    }

    // Listen to real-time location stream (updates coordinates locally)
    _positionStreamSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    ).listen((position) {
      if (mounted) {
        final latLng = LatLng(position.latitude, position.longitude);
        setState(() {
          _currentPosition = latLng;
        });

        if (_isNavigating) {
          _updateNavigationProgress(latLng);
        }

        if (_followUserLocation) {
          _isProgrammaticMovement = true;
          _mapController?.animateCamera(
            CameraUpdate.newCameraPosition(
              CameraPosition(
                target: latLng,
                zoom: _isNavigating ? 18.0 : 16.5,
                tilt: 45.0,
                bearing: 0.0,
              ),
            ),
          );
        }
      }
    });
  }

  void _useFallbackLocation() {
    final fallbackLatLng = const LatLng(14.5995, 120.9842);
    setState(() {
      _currentPosition = fallbackLatLng;
      _fetchingLocation = false;
    });
    _fetchAddressForPoint(fallbackLatLng);
    _fetchRoute();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _isProgrammaticMovement = true;
      _mapController?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: fallbackLatLng,
            zoom: 16.5,
            tilt: 45.0,
          ),
        ),
      );
    });
  }

  void _centerOnCurrentPosition() {
    if (_currentPosition != null) {
      _isProgrammaticMovement = true;
      _mapController?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: _currentPosition!,
            zoom: 16.5,
            tilt: 45.0,
          ),
        ),
      );
      _fetchAddressForPoint(_currentPosition!);
    }
  }

  // Reverse Geocode center coordinate via Google Geocoding API
  Future<String> _reverseGeocodeOnline(LatLng point) async {
    if (_isOffline) {
      return 'Coordinates: ${point.latitude.toStringAsFixed(5)}, ${point.longitude.toStringAsFixed(5)}';
    }
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 4);
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/geocode/json'
        '?latlng=${point.latitude},${point.longitude}'
        '&key=$_googleApiKey'
      );
      final request = await client.getUrl(url);
      final response = await request.close();
      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        final Map<String, dynamic> data = json.decode(body);
        final List<dynamic> results = data['results'] ?? [];
        if (results.isNotEmpty) {
          return results.first['formatted_address'] ?? 'Unknown location';
        }
      }
    } catch (_) {
      _isOffline = true;
    }
    return 'Coordinates: ${point.latitude.toStringAsFixed(5)}, ${point.longitude.toStringAsFixed(5)}';
  }

  // Update center geocoded address state
  Future<void> _fetchAddressForPoint(LatLng point) async {
    if (!mounted) return;
    setState(() {
      _fetchingAddress = true;
      _centerAddress = 'Fetching address...';
    });

    final address = await _reverseGeocodeOnline(point);

    if (mounted) {
      setState(() {
        _centerAddress = address;
        _fetchingAddress = false;
      });
    }
  }

  // Google Places Autocomplete API
  Future<List<PlaceSuggestion>> _searchLocationsOnline(String query, LatLng biasPoint) async {
    if (_isOffline) return [];
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 4);
      final encodedQuery = Uri.encodeComponent(query);
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/place/autocomplete/json'
        '?input=$encodedQuery'
        '&key=$_googleApiKey'
        '&location=${biasPoint.latitude},${biasPoint.longitude}'
        '&radius=50000'
        '&components=country:ph'
      );
      final request = await client.getUrl(url);
      final response = await request.close();

      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        final Map<String, dynamic> data = json.decode(body);
        final List<dynamic> predictions = data['predictions'] ?? [];
        return predictions.map((item) {
          final mainText = item['structured_formatting']?['main_text'] ?? '';
          final secondaryText = item['structured_formatting']?['secondary_text'] ?? '';
          final placeId = item['place_id'] ?? '';
          return PlaceSuggestion(
            placeId: placeId,
            mainText: mainText,
            secondaryText: secondaryText,
          );
        }).toList();
      }
    } catch (_) {
      _isOffline = true;
    }
    return [];
  }

  // Handle map center adjustments
  void _onMapPositionChanged(CameraPosition position) {
    _lastCameraPosition = position.target;
    if (!_isRouteSummaryMinimized) {
      setState(() => _isRouteSummaryMinimized = true);
    }

    if (!_isProgrammaticMovement) {
      if (_followUserLocation) {
        setState(() {
          _followUserLocation = false;
        });
      }
    }

    _debounceGeocode?.cancel();
    _debounceGeocode = Timer(const Duration(milliseconds: 600), () {
      _fetchAddressForPoint(_lastCameraPosition);
    });
  }

  // Search input onChanged triggers autocomplete
  void _onSearchChanged(String text) {
    _debounceSearch?.cancel();
    if (text.trim().isEmpty) {
      setState(() => _filteredSuggestions = []);
      return;
    }

    _debounceSearch = Timer(const Duration(milliseconds: 500), () async {
      await _checkConnectivity();
      final clean = text.trim();
      final biasPoint = _currentPosition ?? const LatLng(14.5995, 120.9842);

      List<PlaceSuggestion> results = [];
      if (!_isOffline) {
        results = await _searchLocationsOnline(clean, biasPoint);
      }

      // Offline match fallback
      if (results.isEmpty) {
        final query = clean.toLowerCase();
        results = _localPresets
            .where((s) => s.mainText.toLowerCase().contains(query) || s.secondaryText.toLowerCase().contains(query))
            .toList();
      }

      if (mounted) {
        setState(() {
          _filteredSuggestions = results;
        });
      }
    });
  }

  // Select autocomplete suggestion -> fetch Place details, drop temporary marker, show info card
  Future<void> _selectSuggestion(PlaceSuggestion suggestion) async {
    setState(() {
      _fetchingLocation = true;
      _filteredSuggestions = [];
      _searchCtrl.clear();
    });

    LatLng? point;
    String name = suggestion.mainText;
    String address = suggestion.secondaryText;

    if (_isOffline && suggestion.placeId.startsWith('preset_')) {
      // Offline fallback coordinates
      if (suggestion.placeId == 'preset_1') {
        point = const LatLng(14.5841, 121.0568);
      } else if (suggestion.placeId == 'preset_2') {
        point = const LatLng(14.6045, 120.9892);
      } else {
        point = const LatLng(14.5945, 120.9792);
      }
    } else {
      try {
        final client = HttpClient();
        client.connectionTimeout = const Duration(seconds: 4);
        final url = Uri.parse(
          'https://maps.googleapis.com/maps/api/place/details/json'
          '?place_id=${suggestion.placeId}'
          '&fields=name,formatted_address,geometry'
          '&key=$_googleApiKey'
        );
        final request = await client.getUrl(url);
        final response = await request.close();
        if (response.statusCode == 200) {
          final body = await response.transform(utf8.decoder).join();
          final Map<String, dynamic> data = json.decode(body);
          final result = data['result'];
          if (result != null && result['geometry'] != null) {
            final lat = result['geometry']['location']['lat'] as double;
            final lng = result['geometry']['location']['lng'] as double;
            point = LatLng(lat, lng);
            name = result['name'] ?? suggestion.mainText;
            address = result['formatted_address'] ?? suggestion.secondaryText;
          }
        }
      } catch (_) {
        _isOffline = true;
      }
    }

    if (point != null) {
      _mapController?.animateCamera(CameraUpdate.newLatLngZoom(point, 15.0));
      setState(() {
        _tempLatLng = point;
        _tempName = name;
        _tempAddress = address;
        _showTempCard = true;
        _fetchingLocation = false;
      });
      await _updateMapMarkers();
      _fetchAddressForPoint(point);
    } else {
      setState(() => _fetchingLocation = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not load location details.'),
            backgroundColor: AppTheme.red,
          ),
        );
      }
    }
  }

  void _searchAndFocus(String query) async {
    if (query.trim().isEmpty) return;
    setState(() => _fetchingLocation = true);

    final clean = query.trim();
    final biasPoint = _currentPosition ?? const LatLng(14.5995, 120.9842);

    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 4);
      final encodedQuery = Uri.encodeComponent(clean);
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/place/textsearch/json'
        '?query=$encodedQuery'
        '&location=${biasPoint.latitude},${biasPoint.longitude}'
        '&radius=20000'
        '&key=$_googleApiKey'
      );
      final request = await client.getUrl(url);
      final response = await request.close();

      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        final Map<String, dynamic> data = json.decode(body);
        final List<dynamic> results = data['results'] ?? [];

        if (results.isNotEmpty) {
          if (_currentPosition != null) {
            results.sort((a, b) {
              final latA = a['geometry']?['location']?['lat'] as double? ?? 0.0;
              final lngA = a['geometry']?['location']?['lng'] as double? ?? 0.0;
              final latB = b['geometry']?['location']?['lat'] as double? ?? 0.0;
              final lngB = b['geometry']?['location']?['lng'] as double? ?? 0.0;
              final dA = _calculateDistance(_currentPosition!, LatLng(latA, lngA));
              final dB = _calculateDistance(_currentPosition!, LatLng(latB, lngB));
              return dA.compareTo(dB);
            });
          }

          final nearest = results.first;
          final lat = nearest['geometry']['location']['lat'] as double;
          final lng = nearest['geometry']['location']['lng'] as double;
          final name = nearest['name'] ?? clean;
          final address = nearest['formatted_address'] ?? '';
          final point = LatLng(lat, lng);

          _mapController?.animateCamera(CameraUpdate.newLatLngZoom(point, 16.0));
          setState(() {
            _tempLatLng = point;
            _tempName = name;
            _tempAddress = address;
            _showTempCard = true;
            _fetchingLocation = false;
            _filteredSuggestions = [];
          });
          await _updateMapMarkers();
          _fetchAddressForPoint(point);
          return;
        }
      }
    } catch (_) {}

    List<PlaceSuggestion> autocompleteSuggestions = [];
    try {
      autocompleteSuggestions = await _searchLocationsOnline(clean, biasPoint);
    } catch (_) {}

    if (autocompleteSuggestions.isNotEmpty) {
      setState(() => _fetchingLocation = false);
      await _selectSuggestion(autocompleteSuggestions.first);
    } else {
      final queryLower = clean.toLowerCase();
      final localMatches = _localPresets
          .where((s) => s.mainText.toLowerCase().contains(queryLower) || s.secondaryText.toLowerCase().contains(queryLower))
          .toList();

      setState(() => _fetchingLocation = false);

      if (localMatches.isNotEmpty) {
        await _selectSuggestion(localMatches.first);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No locations found near you.'),
              backgroundColor: AppTheme.red,
            ),
          );
        }
      }
    }
  }

  // Distance computation (straight-line)
  double _calculateDistance(LatLng p1, LatLng p2) {
    return Geolocator.distanceBetween(
      p1.latitude,
      p1.longitude,
      p2.latitude,
      p2.longitude,
    );
  }

  // Get nearest saved stop to user current location
  SavedStop? _getNearestStop() {
    if (_currentPosition == null || _savedStops.isEmpty) return null;
    SavedStop? nearest;
    double minDistance = double.infinity;
    for (final stop in _savedStops) {
      final d = _calculateDistance(_currentPosition!, LatLng(stop.latitude, stop.longitude));
      if (d < minDistance) {
        minDistance = d;
        nearest = stop;
      }
    }
    return nearest;
  }

  // Add stop manually or via picker to SQLite
  Future<void> _addStop(LatLng point, String name, String address) async {
    final newStop = SavedStop(
      name: name,
      address: address,
      latitude: point.latitude,
      longitude: point.longitude,
      positionOrder: _savedStops.length,
    );

    final id = await DatabaseHelper.instance.insertSavedStop(newStop);
    final stopWithId = newStop.copyWith(id: id);

    setState(() {
      _savedStops.add(stopWithId);
      _isRouteSummaryMinimized = false; // Expand summary on add
    });

    await _updateMapMarkers();
    await _fetchRoute();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Saved Stop: $name'),
          backgroundColor: AppTheme.green,
        ),
      );
    }
  }

  // Add Center pin coordinates to route
  void _addCenterStop() {
    final center = _lastCameraPosition;
    String name = _centerAddress.split(',').first.trim();
    if (name.isEmpty) {
      name = 'Stop ${_savedStops.length + 1}';
    }
    _addStop(center, name, _centerAddress);
  }

  // Swipe or click delete stop from SQLite
  Future<void> _removeStop(int index) async {
    final stop = _savedStops[index];
    final id = stop.id;
    if (id != null) {
      await DatabaseHelper.instance.deleteSavedStop(id);
      setState(() {
        _savedStops.removeAt(index);
        // Refresh ordering
        for (int i = 0; i < _savedStops.length; i++) {
          _savedStops[i] = _savedStops[i].copyWith(positionOrder: i);
        }
      });
      await DatabaseHelper.instance.updateSavedStopsOrder(_savedStops);
      await _updateMapMarkers();
      await _fetchRoute();
    }
  }

  // Dialog triggers coordinates fetching, polyline checks, and summary distance display
  Future<void> _showRouteConfirmation() async {
    setState(() => _fetchingLocation = true);
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      setState(() {
        _currentPosition = LatLng(pos.latitude, pos.longitude);
        _fetchingLocation = false;
      });

      // Fetch latest Google Directions or straight-line route
      await _fetchRoute();

      if (!mounted) return;

      if (_savedStops.isEmpty) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFFF5F0E8),
            title: const Text('Confirm Route', style: TextStyle(color: AppTheme.navy, fontWeight: FontWeight.bold)),
            content: const Text('Please add at least one stop to confirm your route.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK', style: TextStyle(color: AppTheme.navy)),
              ),
            ],
          ),
        );
        return;
      }

      final List<String> details = [];
      for (int i = 0; i < _savedStops.length; i++) {
        final stop = _savedStops[i];
        final dist = (i < _routeLegDistances.length) ? _routeLegDistances[i] : 0.0;
        details.add('• Stop ${i + 1}: ${stop.name} (${dist.toStringAsFixed(2)} km from previous)');
      }

      final totalDist = _totalRouteDistance;
      final isDirections = _routePoints.isNotEmpty && !_isOffline;
      final distanceType = isDirections ? 'road route' : 'straight-line';

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFFF5F0E8),
          title: const Text(
            'Route Confirmed',
            style: TextStyle(color: AppTheme.navy, fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Total travel distance: ${totalDist.toStringAsFixed(2)} km ($distanceType)',
                style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.navy, fontSize: 15),
              ),
              const SizedBox(height: 12),
              ...details.map((d) => Padding(
                    padding: const EdgeInsets.only(bottom: 6.0),
                    child: Text(d, style: const TextStyle(fontSize: 13, color: AppTheme.textDark)),
                  )),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Modify', style: TextStyle(color: AppTheme.textGrey)),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx); // close dialog
                setState(() {
                  _showRouteControls = false;
                  _isRouteSummaryMinimized = true;
                  _showTempCard = false;
                  _tempLatLng = null;
                });
                _updateMapMarkers();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.yellow,
                foregroundColor: AppTheme.navy,
              ),
              child: const Text('Done'),
            ),
          ],
        ),
      );
    } catch (e) {
      setState(() => _fetchingLocation = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to fetch GPS location: $e'),
            backgroundColor: AppTheme.red,
          ),
        );
      }
    }
  }

  void _startNavigation() {
    if (_navigationSteps.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No navigation steps available. Please plan a route first.'),
          backgroundColor: AppTheme.red,
        ),
      );
      return;
    }

    setState(() {
      _isNavigating = true;
      _currentStepIndex = 0;
      _followUserLocation = true;
      _showTempCard = false;
      _tempLatLng = null;
      _isRouteSummaryMinimized = true;
    });

    _zoomCameraToNavigationMode();
  }

  void _zoomCameraToNavigationMode() {
    if (_currentPosition != null && _mapController != null) {
      _isProgrammaticMovement = true;
      _mapController!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: _currentPosition!,
            zoom: 18.0,
            tilt: 45.0,
            bearing: 0.0,
          ),
        ),
      );
    }
  }

  void _stopNavigation() {
    setState(() {
      _isNavigating = false;
      _followUserLocation = false;
    });
    if (_currentPosition != null && _mapController != null) {
      _isProgrammaticMovement = true;
      _mapController!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: _currentPosition!,
            zoom: 16.5,
            tilt: 45.0,
            bearing: 0.0,
          ),
        ),
      );
    }
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
        setState(() {
          _currentStepIndex++;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Next instruction: ${_navigationSteps[_currentStepIndex].instructions}'),
            backgroundColor: AppTheme.navy,
            duration: const Duration(seconds: 3),
          ),
        );
      } else {
        setState(() {
          _isNavigating = false;
        });
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFFF5F0E8),
            title: const Text('Arrived!', style: TextStyle(color: AppTheme.navy, fontWeight: FontWeight.bold)),
            content: const Text('You have reached the final destination of your route.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK', style: TextStyle(color: AppTheme.navy)),
              ),
            ],
          ),
        );
      }
    } else {
      setState(() {});
    }
  }

  IconData _getManeuverIcon(String maneuver, String instructions) {
    final m = maneuver.toLowerCase();
    final inst = instructions.toLowerCase();
    
    if (m.contains('left') || inst.contains('turn left')) {
      return Icons.turn_left;
    } else if (m.contains('right') || inst.contains('turn right')) {
      return Icons.turn_right;
    } else if (m.contains('straight') || inst.contains('straight') || inst.contains('continue')) {
      return Icons.straight;
    } else if (inst.contains('uturn') || inst.contains('u-turn')) {
      return Icons.u_turn_left;
    } else if (inst.contains('keep left')) {
      return Icons.turn_slight_left;
    } else if (inst.contains('keep right')) {
      return Icons.turn_slight_right;
    } else if (inst.contains('roundabout')) {
      return Icons.roundabout_left;
    }
    return Icons.navigation;
  }

  Widget _buildNavigationCard() {
    if (_navigationSteps.isEmpty || _currentStepIndex >= _navigationSteps.length) {
      return const SizedBox.shrink();
    }

    final currentStep = _navigationSteps[_currentStepIndex];
    final distanceToEnd = _currentPosition == null
        ? currentStep.distanceMeters
        : Geolocator.distanceBetween(
            _currentPosition!.latitude,
            _currentPosition!.longitude,
            currentStep.endLocation.latitude,
            currentStep.endLocation.longitude,
          );

    final distanceText = distanceToEnd > 1000
        ? '${(distanceToEnd / 1000).toStringAsFixed(1)} km'
        : '${distanceToEnd.toStringAsFixed(0)} m';

    final icon = _getManeuverIcon(currentStep.maneuver, currentStep.instructions);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.navy,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(40),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.white.withAlpha(25),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: AppTheme.yellow, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  currentStep.instructions,
                  style: const TextStyle(
                    color: AppTheme.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'In $distanceText',
                  style: TextStyle(
                    color: AppTheme.yellow.withAlpha(220),
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          IconButton(
            icon: const Icon(Icons.close, color: AppTheme.white, size: 22),
            onPressed: _stopNavigation,
          ),
        ],
      ),
    );
  }


  // Opens bottom sheet with drag-to-reorder list
  void _showStopsBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setSheetState) {
            final nearest = _getNearestStop();

            return Container(
              height: MediaQuery.of(context).size.height * 0.6,
              decoration: const BoxDecoration(
                color: Color(0xFFF5F0E8),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Route Stops List',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.navy,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: AppTheme.textDark),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const Text(
                    'Drag handles to reorder, swipe tile or tap trash to delete.',
                    style: TextStyle(fontSize: 11, color: AppTheme.textGrey),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: _savedStops.isEmpty
                        ? const Center(
                            child: Text(
                              'No saved stops. Add locations using the map.',
                              style: TextStyle(color: AppTheme.textGrey),
                            ),
                          )
                        : ReorderableListView.builder(
                            itemCount: _savedStops.length,
                            onReorder: (oldIndex, newIndex) async {
                              if (newIndex > oldIndex) {
                                newIndex -= 1;
                              }
                              setState(() {
                                final stop = _savedStops.removeAt(oldIndex);
                                _savedStops.insert(newIndex, stop);
                                // Refresh sorting indexes
                                for (int i = 0; i < _savedStops.length; i++) {
                                  _savedStops[i] = _savedStops[i].copyWith(positionOrder: i);
                                }
                              });
                              setSheetState(() {});
                              await DatabaseHelper.instance.updateSavedStopsOrder(_savedStops);
                              await _updateMapMarkers();
                              await _fetchRoute();
                            },
                            itemBuilder: (context, idx) {
                              final stop = _savedStops[idx];
                              final isNearest = nearest?.id == stop.id;

                              double distance = 0.0;
                              if (_currentPosition != null) {
                                distance = _calculateDistance(_currentPosition!, LatLng(stop.latitude, stop.longitude)) / 1000.0;
                              }

                              return Dismissible(
                                key: Key('saved_stop_dismiss_${stop.id}'),
                                background: Container(
                                  alignment: Alignment.centerRight,
                                  padding: const EdgeInsets.only(right: 20),
                                  color: AppTheme.red,
                                  child: const Icon(Icons.delete, color: Colors.white),
                                ),
                                onDismissed: (direction) async {
                                  await _removeStop(idx);
                                  setSheetState(() {});
                                },
                                child: Container(
                                  key: ValueKey('saved_stop_tile_${stop.id}'),
                                  margin: const EdgeInsets.only(bottom: 10),
                                  decoration: BoxDecoration(
                                    color: AppTheme.white,
                                    borderRadius: BorderRadius.circular(16),
                                    border: isNearest ? Border.all(color: AppTheme.yellow, width: 2) : null,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withAlpha(5),
                                        blurRadius: 4,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: ListTile(
                                    leading: CircleAvatar(
                                      backgroundColor: isNearest ? AppTheme.yellow : const Color(0xFFB00020),
                                      child: const Icon(Icons.place, color: Colors.white, size: 18),
                                    ),
                                    title: Text(
                                      stop.name,
                                      style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.navy, fontSize: 14),
                                    ),
                                    subtitle: Text(
                                      _currentPosition != null
                                          ? '${distance.toStringAsFixed(2)} km away${isNearest ? ' (NEAREST)' : ''}'
                                          : 'GPS offline',
                                      style: TextStyle(
                                        color: isNearest ? AppTheme.yellow : AppTheme.textGrey,
                                        fontWeight: isNearest ? FontWeight.bold : FontWeight.normal,
                                        fontSize: 12,
                                      ),
                                    ),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          icon: const Icon(Icons.delete_outline, color: AppTheme.red, size: 18),
                                          onPressed: () async {
                                            await _removeStop(idx);
                                            setSheetState(() {});
                                          },
                                        ),
                                        const Icon(Icons.drag_handle, color: AppTheme.textGrey),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    ).then((_) {
      setState(() {});
    });
  }

  // Add stop manually dialog
  void _showCustomStopDialog() {
    final TextEditingController nameCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFFF5F0E8),
        title: const Text(
          'Add Custom Stop',
          style: TextStyle(color: AppTheme.navy, fontWeight: FontWeight.bold),
        ),
        content: TextField(
          controller: nameCtrl,
          decoration: const InputDecoration(
            hintText: 'Enter stop name (e.g. Office)',
            hintStyle: TextStyle(color: AppTheme.textGrey),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppTheme.navy)),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppTheme.navy)),
          ),
          style: const TextStyle(color: AppTheme.textDark),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: AppTheme.textGrey)),
          ),
          ElevatedButton(
            onPressed: () {
              final name = nameCtrl.text.trim();
              if (name.isNotEmpty) {
                Navigator.pop(ctx);
                final center = _lastCameraPosition;
                _addStop(center, name, _centerAddress);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.navy,
              foregroundColor: AppTheme.white,
            ),
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  // Custom marker builder for saved stops painted dynamically on Canvas
  Future<BitmapDescriptor> _getMarkerIcon(String name, bool isNearest) async {
    final cacheKey = 'stop_${name}_$isNearest';
    if (_markerIconCache.containsKey(cacheKey)) {
      return _markerIconCache[cacheKey]!;
    }
    final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(pictureRecorder);
    const double width = 120.0;
    const double height = 140.0;

    final Paint pinPaint = Paint()
      ..color = isNearest ? const Color(0xFFFFCC00) : const Color(0xFFB00020)
      ..style = PaintingStyle.fill;

    final Paint borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0;

    const double radius = 32.0;
    const Offset center = Offset(width / 2, radius + 10);

    // Circle background
    canvas.drawCircle(center, radius, pinPaint);
    canvas.drawCircle(center, radius, borderPaint);

    // Tip pointing down
    final Path path = Path()
      ..moveTo(width / 2 - 16, center.dy + radius - 4)
      ..lineTo(width / 2 + 16, center.dy + radius - 4)
      ..lineTo(width / 2, center.dy + radius + 20)
      ..close();
    canvas.drawPath(path, pinPaint);
    canvas.drawPath(path, borderPaint);

    // White location icon inside pin
    const IconData iconData = Icons.place;
    final TextPainter textPainter = TextPainter(textDirection: TextDirection.ltr);
    textPainter.text = TextSpan(
      text: String.fromCharCode(iconData.codePoint),
      style: TextStyle(
        fontSize: 34.0,
        fontFamily: iconData.fontFamily,
        package: iconData.fontPackage,
        color: Colors.white,
      ),
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(center.dx - textPainter.width / 2, center.dy - textPainter.height / 2),
    );

    // Label name text below
    if (name.isNotEmpty) {
      final TextPainter labelPainter = TextPainter(
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
        maxLines: 1,
        ellipsis: '...',
      );
      labelPainter.text = TextSpan(
        text: name,
        style: const TextStyle(
          fontSize: 14.0,
          fontWeight: FontWeight.bold,
          color: Color(0xFF1A2355), // Brand Navy
          backgroundColor: Colors.white,
        ),
      );
      labelPainter.layout(maxWidth: width * 1.5);
      labelPainter.paint(
        canvas,
        Offset(width / 2 - labelPainter.width / 2, center.dy + radius + 24),
      );
    }

    final ui.Image img = await pictureRecorder.endRecording().toImage(width.toInt(), height.toInt());
    final ByteData? data = await img.toByteData(format: ui.ImageByteFormat.png);
    final descriptor = BitmapDescriptor.fromBytes(data!.buffer.asUint8List());
    _markerIconCache[cacheKey] = descriptor;
    return descriptor;
  }

  // Temporary pin search icon custom canvas painter
  Future<BitmapDescriptor> _getTempMarkerIcon(String name) async {
    final cacheKey = 'temp_${name}';
    if (_markerIconCache.containsKey(cacheKey)) {
      return _markerIconCache[cacheKey]!;
    }
    final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(pictureRecorder);
    const double width = 120.0;
    const double height = 140.0;

    final Paint pinPaint = Paint()
      ..color = const Color(0xFF1A2355) // Navy
      ..style = PaintingStyle.fill;

    final Paint borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0;

    const double radius = 32.0;
    const Offset center = Offset(width / 2, radius + 10);

    canvas.drawCircle(center, radius, pinPaint);
    canvas.drawCircle(center, radius, borderPaint);

    final Path path = Path()
      ..moveTo(width / 2 - 16, center.dy + radius - 4)
      ..lineTo(width / 2 + 16, center.dy + radius - 4)
      ..lineTo(width / 2, center.dy + radius + 20)
      ..close();
    canvas.drawPath(path, pinPaint);
    canvas.drawPath(path, borderPaint);

    const IconData iconData = Icons.search;
    final TextPainter textPainter = TextPainter(textDirection: TextDirection.ltr);
    textPainter.text = TextSpan(
      text: String.fromCharCode(iconData.codePoint),
      style: TextStyle(
        fontSize: 34.0,
        fontFamily: iconData.fontFamily,
        package: iconData.fontPackage,
        color: const Color(0xFFFFCC00), // Yellow icon
      ),
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(center.dx - textPainter.width / 2, center.dy - textPainter.height / 2),
    );

    if (name.isNotEmpty) {
      final TextPainter labelPainter = TextPainter(
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
        maxLines: 1,
        ellipsis: '...',
      );
      labelPainter.text = TextSpan(
        text: name,
        style: const TextStyle(
          fontSize: 14.0,
          fontWeight: FontWeight.bold,
          color: Color(0xFF1A2355),
          backgroundColor: Colors.white,
        ),
      );
      labelPainter.layout(maxWidth: width * 1.5);
      labelPainter.paint(
        canvas,
        Offset(width / 2 - labelPainter.width / 2, center.dy + radius + 24),
      );
    }

    final ui.Image img = await pictureRecorder.endRecording().toImage(width.toInt(), height.toInt());
    final ByteData? data = await img.toByteData(format: ui.ImageByteFormat.png);
    final descriptor = BitmapDescriptor.fromBytes(data!.buffer.asUint8List());
    _markerIconCache[cacheKey] = descriptor;
    return descriptor;
  }

  // Update map state markers dynamically
  Future<void> _updateMapMarkers() async {
    final Set<Marker> newMarkers = {};
    final nearest = _getNearestStop();

    for (final stop in _savedStops) {
      final isNearest = nearest?.id == stop.id;
      final icon = await _getMarkerIcon(stop.name, isNearest);
      newMarkers.add(
        Marker(
          markerId: MarkerId('saved_stop_${stop.id}'),
          position: LatLng(stop.latitude, stop.longitude),
          icon: icon,
          anchor: const Offset(0.5, 0.85),
        ),
      );
    }

    if (_tempLatLng != null) {
      final tempIcon = await _getTempMarkerIcon(_tempName ?? 'SearchResult');
      newMarkers.add(
        Marker(
          markerId: const MarkerId('temp_search_result'),
          position: _tempLatLng!,
          icon: tempIcon,
          anchor: const Offset(0.5, 0.85),
        ),
      );
    }

    if (mounted) {
      setState(() {
        _markers = newMarkers;
      });
    }
  }

  // Query Directions route path
  Future<void> _fetchRoute() async {
    if (_currentPosition == null || _savedStops.isEmpty) {
      setState(() {
        _routePoints = [];
        _routeLegDistances = [];
        _totalRouteDistance = 0.0;
        _polylines = {};
        _navigationSteps = [];
      });
      return;
    }

    await _checkConnectivity();

    if (_isOffline) {
      _calculateStraightLineRoute();
      return;
    }

    setState(() => _fetchingRoute = true);

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
        '&key=$_googleApiKey'
      );

      final request = await client.getUrl(url);
      final response = await request.close();

      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        final Map<String, dynamic> data = json.decode(body);

        if (data['status'] == 'OK' && data['routes'] != null && data['routes'].isNotEmpty) {
          final route = data['routes'][0];
          final polylineStr = route['overview_polyline']?['points'] ?? '';
          final List<LatLng> decodedPoints = decodePolyline(polylineStr);

          final List<dynamic> legs = route['legs'] ?? [];
          final List<double> legDists = legs.map((l) {
            final double meters = (l['distance']?['value'] as num?)?.toDouble() ?? 0.0;
            return meters / 1000.0; // convert to km
          }).toList();

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
              _routeLegDistances = legDists;
              _totalRouteDistance = totalMeters / 1000.0;
              _navigationSteps = stepsList;
              _fetchingRoute = false;
            });
            _updatePolylines();
          }
          return;
        }
      }
    } catch (_) {
      // failed, fall back
    }

    if (mounted) {
      _calculateStraightLineRoute();
      setState(() => _fetchingRoute = false);
    }
  }

  void _calculateStraightLineRoute() {
    final List<LatLng> points = [];
    final List<double> legDists = [];
    final List<RouteStep> stepsList = [];
    double total = 0.0;

    if (_currentPosition != null) {
      points.add(_currentPosition!);
      LatLng lastPoint = _currentPosition!;
      for (final stop in _savedStops) {
        final stopPoint = LatLng(stop.latitude, stop.longitude);
        points.add(stopPoint);
        final dist = _calculateDistance(lastPoint, stopPoint) / 1000.0; // km
        legDists.add(dist);
        total += dist;

        stepsList.add(RouteStep(
          startLocation: lastPoint,
          endLocation: stopPoint,
          instructions: 'Head towards ${stop.name}',
          maneuver: 'straight',
          distanceText: '${dist.toStringAsFixed(2)} km',
          distanceMeters: dist * 1000.0,
        ));

        lastPoint = stopPoint;
      }
    }

    setState(() {
      _routePoints = points;
      _routeLegDistances = legDists;
      _totalRouteDistance = total;
      _navigationSteps = stepsList;
    });
    _updatePolylines();
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
          color: const Color(0xFF1A2355), // Navy
          width: 5,
        ),
      };
    });
  }

  // Google Maps polyline decoding algorithm
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
              tilt: 45.0,
            ),
            mapType: MapType.normal,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            tiltGesturesEnabled: !_isNavigating,
            rotateGesturesEnabled: !_isNavigating,
            markers: _markers,
            polylines: _polylines,
            onMapCreated: (controller) {
              _mapController = controller;
            },
            onCameraMoveStarted: () {
              setState(() {
                _isMapDragging = true;
              });
            },
            onCameraMove: _onMapPositionChanged,
            onCameraIdle: () {
              setState(() {
                _isProgrammaticMovement = false;
                _isMapDragging = false;
              });
              _fetchAddressForPoint(_lastCameraPosition);
            },
            onTap: (latLng) async {
              if (_isNavigating) return;
              
              setState(() {
                _fetchingLocation = true;
                _showTempCard = false;
              });
              
              final address = await _reverseGeocodeOnline(latLng);
              
              setState(() {
                _tempLatLng = latLng;
                _tempName = 'Tapped Location';
                _tempAddress = address;
                _showTempCard = true;
                _fetchingLocation = false;
              });
              
              _mapController?.animateCamera(CameraUpdate.newLatLng(latLng));
              await _updateMapMarkers();
            },
          ),

          // Loading location indicator overlay
          if (_fetchingLocation)
            Positioned(
              top: 140,
              left: 20,
              right: 20,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: AppTheme.white,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 5)],
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.navy),
                    ),
                    SizedBox(width: 12),
                    Text(
                      'Resolving live GPS location...',
                      style: TextStyle(color: AppTheme.navy, fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),

          // ── 2. Top Navigation & Google Places Search Bar ──
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () {
                          if (_isNavigating) {
                            _stopNavigation();
                          } else {
                            Navigator.pop(context);
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: const BoxDecoration(
                            color: AppTheme.white,
                            shape: BoxShape.circle,
                            boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)],
                          ),
                          child: const Icon(Icons.arrow_back, color: AppTheme.textDark, size: 20),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        _isNavigating ? 'Navigation' : 'Map Route',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textDark,
                          shadows: [Shadow(color: Colors.white, blurRadius: 4)],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  
                  if (!_isNavigating) ...[
                    // Search Box Input
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF5F0E8),
                        borderRadius: BorderRadius.circular(30),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withAlpha(15),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: TextField(
                        controller: _searchCtrl,
                        onSubmitted: _searchAndFocus,
                        onChanged: _onSearchChanged,
                        enabled: true,
                        style: const TextStyle(color: AppTheme.textDark, fontSize: 15),
                        decoration: InputDecoration(
                          icon: const Icon(Icons.search, color: AppTheme.navy),
                          hintText: 'Search for a stop (e.g. Megamall)...',
                          hintStyle: const TextStyle(color: AppTheme.textGrey, fontSize: 15),
                          border: InputBorder.none,
                          suffixIcon: _searchCtrl.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () {
                                    _searchCtrl.clear();
                                    _onSearchChanged('');
                                  },
                                )
                              : null,
                        ),
                      ),
                    ),
                    // Autocomplete List Overlay
                    if (_filteredSuggestions.isNotEmpty && !_isOffline)
                      Container(
                        margin: const EdgeInsets.only(top: 8),
                        constraints: const BoxConstraints(maxHeight: 200),
                        child: Material(
                          elevation: 8,
                          borderRadius: BorderRadius.circular(16),
                          color: AppTheme.white,
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: ListView.builder(
                              padding: EdgeInsets.zero,
                              shrinkWrap: true,
                              itemCount: _filteredSuggestions.length,
                              itemBuilder: (ctx, idx) {
                                final suggestion = _filteredSuggestions[idx];
                                return ListTile(
                                  leading: const Icon(Icons.location_on_outlined, color: AppTheme.navy),
                                  title: Text(suggestion.mainText, style: const TextStyle(fontWeight: FontWeight.bold)),
                                  subtitle: Text(suggestion.secondaryText, maxLines: 1, overflow: TextOverflow.ellipsis),
                                  onTap: () => _selectSuggestion(suggestion),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                  ] else ...[
                    // Floating Turn-by-Turn Card
                    _buildNavigationCard(),
                  ],
                ],
              ),
            ),
          ),

          // ── 3. Foodpanda-Style Center Stationary Pin ──
          if (!_isNavigating)
            IgnorePointer(
              child: Center(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  transform: Matrix4.translationValues(0.0, _isMapDragging ? -32.0 : -22.0, 0.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.location_on,
                        color: AppTheme.navy,
                        size: 44,
                      ),
                      Container(
                        width: 8,
                        height: 4,
                        decoration: const BoxDecoration(
                          color: Colors.black26,
                          borderRadius: BorderRadius.all(Radius.elliptical(8, 4)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // ── My Location Center Button ──
          Positioned(
            bottom: _isNavigating
                ? 100
                : (_showTempCard ? 240 : (!_isRouteSummaryMinimized ? 380 : 180)),
            right: 20,
            child: FloatingActionButton(
              mini: true,
              backgroundColor: AppTheme.white,
              foregroundColor: AppTheme.navy,
              elevation: 4,
              onPressed: () {
                setState(() {
                  _followUserLocation = true;
                });
                if (_isNavigating) {
                  _zoomCameraToNavigationMode();
                } else {
                  _centerOnCurrentPosition();
                }
              },
              child: Icon(
                _followUserLocation ? Icons.gps_fixed : Icons.gps_not_fixed,
                color: _followUserLocation ? AppTheme.yellow : AppTheme.navy,
              ),
            ),
          ),

          // ── 4. Bottom Information Overlays & Actions Card ──
          if (!_isNavigating)
            Positioned(
              bottom: 24,
              left: 20,
              right: 20,
              child: _showRouteControls
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                  // Collapsible Route Summary timeline panel
                  if (!_isRouteSummaryMinimized)
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF5F0E8),
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withAlpha(30),
                            blurRadius: 16,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  const Text(
                                    'Timeline Summary',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.navy,
                                    ),
                                  ),
                                  if (_fetchingRoute) ...[
                                    const SizedBox(width: 8),
                                    const SizedBox(
                                      width: 12,
                                      height: 12,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.navy),
                                    ),
                                  ],
                                ],
                              ),
                              IconButton(
                                icon: const Icon(Icons.close, color: AppTheme.textGrey, size: 20),
                                onPressed: () => setState(() => _isRouteSummaryMinimized = true),
                              ),
                            ],
                          ),
                          Text(
                            'Route Stops: ${_savedStops.length} stops logged',
                            style: const TextStyle(fontSize: 12, color: AppTheme.textGrey, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 12),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 160),
                            child: SingleChildScrollView(
                              child: ListView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: _savedStops.length,
                                itemBuilder: (ctx, idx) {
                                  final stop = _savedStops[idx];
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 8.0),
                                    child: Row(
                                      children: [
                                        CircleAvatar(
                                          radius: 12,
                                          backgroundColor: const Color(0xFFB00020),
                                          child: Text('${idx + 1}', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            stop.name,
                                            style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.navy, fontSize: 13),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.delete_outline, color: AppTheme.red, size: 18),
                                          onPressed: () => _removeStop(idx),
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          // Add custom name manually inside summary panel
                          GestureDetector(
                            onTap: _showCustomStopDialog,
                            child: Row(
                              children: [
                                Container(
                                  width: 28,
                                  height: 28,
                                  decoration: BoxDecoration(
                                    border: Border.all(color: AppTheme.navy, width: 1.5),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.add, color: AppTheme.navy, size: 16),
                                ),
                                const SizedBox(width: 10),
                                const Text(
                                  'Add Custom Location Name',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.textGrey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          // Confirm Route Button
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _showRouteConfirmation,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.yellow,
                                foregroundColor: AppTheme.navy,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(50),
                                ),
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                elevation: 0,
                              ),
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    'Confirm Route',
                                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                                  ),
                                  SizedBox(width: 6),
                                  Icon(Icons.arrow_forward, size: 18),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Main Info Card (Temporary marker match or Stationary center geocoder selection card)
                  _showTempCard
                      ? Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF5F0E8),
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withAlpha(30),
                                blurRadius: 16,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'SEARCH RESULT PIN',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.yellow,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _tempName ?? '',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.navy,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _tempAddress ?? '',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.textGrey,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Expanded(
                                    child: ElevatedButton(
                                      onPressed: () {
                                        if (_tempLatLng != null) {
                                          _addStop(_tempLatLng!, _tempName ?? 'Searched Stop', _tempAddress ?? '');
                                          setState(() {
                                            _showTempCard = false;
                                            _tempLatLng = null;
                                          });
                                          _updateMapMarkers();
                                        }
                                      },
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppTheme.navy,
                                        foregroundColor: AppTheme.white,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(50),
                                        ),
                                        padding: const EdgeInsets.symmetric(vertical: 14),
                                        elevation: 0,
                                      ),
                                      child: const Text(
                                        'ADD STOP',
                                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: () {
                                        setState(() {
                                          _showTempCard = false;
                                          _tempLatLng = null;
                                        });
                                        _updateMapMarkers();
                                      },
                                      style: OutlinedButton.styleFrom(
                                        side: const BorderSide(color: AppTheme.navy, width: 1.5),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(50),
                                        ),
                                        padding: const EdgeInsets.symmetric(vertical: 14),
                                      ),
                                      child: const Text(
                                        'CANCEL',
                                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.navy),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        )
                      : Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF5F0E8),
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withAlpha(30),
                                blurRadius: 16,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'CHOOSE LOCATION',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.textGrey,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  if (_fetchingAddress)
                                    const SizedBox(
                                      width: 12,
                                      height: 12,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.navy),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _centerAddress,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.navy,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Expanded(
                                    flex: 3,
                                    child: ElevatedButton(
                                      onPressed: _addCenterStop,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppTheme.navy,
                                        foregroundColor: AppTheme.white,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(50),
                                        ),
                                        padding: const EdgeInsets.symmetric(vertical: 14),
                                        elevation: 0,
                                      ),
                                      child: const Text(
                                        'ADD STOP HERE',
                                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    flex: 2,
                                    child: OutlinedButton(
                                      onPressed: _showStopsBottomSheet,
                                      style: OutlinedButton.styleFrom(
                                        side: const BorderSide(color: AppTheme.navy, width: 1.5),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(50),
                                        ),
                                        padding: const EdgeInsets.symmetric(vertical: 14),
                                      ),
                                      child: Text(
                                        'STOPS (${_savedStops.length})',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: AppTheme.navy,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              if (_savedStops.isNotEmpty) ...[
                                const SizedBox(height: 10),
                                SizedBox(
                                  width: double.infinity,
                                  child: TextButton(
                                    onPressed: () {
                                      setState(() {
                                        _isRouteSummaryMinimized = !_isRouteSummaryMinimized;
                                      });
                                    },
                                    style: TextButton.styleFrom(
                                      padding: EdgeInsets.zero,
                                      minimumSize: const Size(0, 0),
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    child: Text(
                                      _isRouteSummaryMinimized ? 'Show Timeline Summary' : 'Hide Timeline Summary',
                                      style: const TextStyle(color: AppTheme.yellow, fontWeight: FontWeight.bold, fontSize: 12),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                ],
              )
            : Align(
                alignment: Alignment.bottomCenter,
                child: FloatingActionButton.extended(
                  onPressed: () {
                    setState(() {
                      _showRouteControls = true;
                    });
                  },
                  backgroundColor: AppTheme.navy,
                  foregroundColor: AppTheme.white,
                  icon: const Icon(Icons.edit_road),
                  label: const Text('Edit Route / Stops'),
                ),
              ),
          ),
        ],
      ),
    );
  }
}

