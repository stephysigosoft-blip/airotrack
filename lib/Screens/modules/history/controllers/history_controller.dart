import 'dart:async';
import 'dart:math' as math;

import 'package:airotrack/Configs/ApiConfigs.dart';
import 'package:airotrack/Configs/DioClient.dart';
import 'package:airotrack/Models/HistoryModel.dart';
import 'package:airotrack/Services/ReverseGeocodeService.dart';
import 'package:airotrack/Utils/Utils.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

Future<Map<String, dynamic>> _getHistoryInIsolate(
  Map<String, dynamic> params,
) async {
  try {
    final dio = Dio(
      BaseOptions(
        baseUrl: params['baseUrl'] as String,
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 20),
        headers: <String, dynamic>{
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          if (params['token'] != null)
            'Authorization': params['token'] as String,
        },
      ),
    );
    final response = await dio.get<Map<String, dynamic>>(
      params['path'] as String,
      queryParameters: params['query'] as Map<String, dynamic>,
    );
    return <String, dynamic>{
      'data': response.data,
      'statusCode': response.statusCode,
    };
  } catch (e, st) {
    return <String, dynamic>{
      'error': e.toString(),
      'stackTrace': st.toString(),
    };
  }
}

/// Top-level for isolate: build polyline points with deviceTime (sendable types only).
/// [args] must be {'responseBody': Map?}.
List<Map<String, dynamic>> _buildPolylinePointsInIsolate(
  Map<String, dynamic> args,
) {
  final responseBody = args['responseBody'] as Map<String, dynamic>?;
  if (responseBody == null) {
    debugPrint('[History] Isolate: no responseBody, returning []');
    return [];
  }
  final model = HistoryModel.fromJson(responseBody);
  final list = model.data?.locationHistory ?? [];
  debugPrint(
    '[History] Isolate: location_history count from backend = ${list.length}',
  );
  final points = <Map<String, dynamic>>[];
  for (final item in list) {
    final lat = item.latitude != null
        ? double.tryParse(item.latitude!.trim())
        : null;
    final lng = item.longitude != null
        ? double.tryParse(item.longitude!.trim())
        : null;
    if (lat != null &&
        lng != null &&
        lat.abs() <= 90 &&
        lng.abs() <= 180 &&
        (lat != 0 || lng != 0)) {
      points.add({
        'lat': lat,
        'lng': lng,
        'deviceTime': item.deviceTime ?? '',
        'speed': item.speed ?? '0',
      });
    }
  }
  debugPrint(
    '[History] Isolate: valid points (lat/lng parsed) = ${points.length}',
  );
  if (points.isNotEmpty) {
    debugPrint(
      '[History] Isolate: first point lat=${points.first['lat']} lng=${points.first['lng']} deviceTime=${points.first['deviceTime']}',
    );
    debugPrint(
      '[History] Isolate: last point lat=${points.last['lat']} lng=${points.last['lng']} deviceTime=${points.last['deviceTime']}',
    );
  }
  return points;
}

/// Bearing in degrees (0-360) from [start] to [end] for marker rotation.
double _getBearing(LatLng start, LatLng end) {
  final lat1 = start.latitude * math.pi / 180;
  final lon1 = start.longitude * math.pi / 180;
  final lat2 = end.latitude * math.pi / 180;
  final lon2 = end.longitude * math.pi / 180;
  final dLon = lon2 - lon1;
  final y = math.sin(dLon) * math.cos(lat2);
  final x =
      math.cos(lat1) * math.sin(lat2) -
      math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
  final bearing = math.atan2(y, x);
  return (bearing * 180 / math.pi + 360) % 360;
}

/// Mapbox Map Matching API (snaps GPS track to road). Max 100 points per request.
const String _mapboxMatchBase =
    'https://api.mapbox.com/matching/v5/mapbox/driving';

/// Top-level: parse Mapbox match response to list of [lat, lng]. Geometry is GeoJSON [lng, lat].
List<List<double>> _processMapboxChunk(Map<String, dynamic> data) {
  debugPrint('[History] Mapbox parse: _processMapboxChunk START');
  final result = <List<double>>[];
  try {
    final code = data['code']?.toString();
    debugPrint('[History] Mapbox parse: code=$code');
    if (code != 'Ok') {
      debugPrint('[History] Mapbox parse: code != Ok, returning empty');
      return result;
    }
    final matchings = data['matchings'];
    debugPrint(
      '[History] Mapbox parse: matchings type=${matchings.runtimeType} length=${matchings is List ? matchings.length : "n/a"}',
    );
    if (matchings == null || matchings is! List || matchings.isEmpty) {
      debugPrint('[History] Mapbox parse: no matchings, returning empty');
      return result;
    }
    for (final m in matchings) {
      if (m is! Map<String, dynamic>) continue;
      final geometry = m['geometry'];
      if (geometry == null || geometry is! Map) continue;
      final coords = geometry['coordinates'];
      if (coords == null || coords is! List) continue;
      for (final c in coords) {
        if (c is List && c.length >= 2) {
          final lng = (c[0] is num) ? (c[0] as num).toDouble() : null;
          final lat = (c[1] is num) ? (c[1] as num).toDouble() : null;
          if (lat != null && lng != null) result.add([lat, lng]);
        }
      }
    }
    debugPrint(
      '[History] Mapbox parse: _processMapboxChunk DONE result.length=${result.length}',
    );
  } catch (e, st) {
    debugPrint('[History] Mapbox parse: _processMapboxChunk THREW $e');
    debugPrint('[History] Mapbox parse: $st');
  }
  return result;
}

class HistoryController extends GetxController {
  var showBottomSheet = true.obs;
  final List<String> dateRangeOptions = [
    "1 hour",
    "Today",
    "Yesterday",
    "Week",
    "Month",
    "Custom",
  ];
  var selectedDateRange = "Today".obs;
  var isLoading = false.obs;

  void updateDateRange(String value) {
    selectedDateRange.value = value;
    DateTime now = DateTime.now();
    DateTime from;
    DateTime to = now;

    switch (value) {
      case "1 hour":
        from = now.subtract(const Duration(hours: 1));
        break;
      case "Today":
        from = DateTime(now.year, now.month, now.day);
        to = DateTime(now.year, now.month, now.day, 23, 59, 59);
        break;
      case "Yesterday":
        from = DateTime(now.year, now.month, now.day - 1);
        to = DateTime(now.year, now.month, now.day - 1, 23, 59, 59);
        break;
      case "Week":
        from = now.subtract(const Duration(days: 7));
        break;
      case "Month":
        from = now.subtract(const Duration(days: 30));
        break;
      case "Custom":
      default:
        fromDate.value = "-:-";
        toDate.value = "-:-";
        return;
    }

    fromDate.value = _dateFormat.format(from);
    toDate.value = _dateFormat.format(to);

    final imei = _resolveImeiForHistoryCall();
    getHistory(imei);
  }

  var fromDate = "-:-".obs;
  var toDate = "-:-".obs;
  var vehicleId = "KL 07 D 0518".obs;
  String _activeImei = '';

  @override
  void onInit() {
    super.onInit();
    _historyFetchScheduled = false;
    syncRouteParams(
      imei: Get.parameters['imei'],
      vehicleNameOrId: Get.parameters['vehicleId'],
    );
    // Default: show Today and load history as soon as the screen opens.
    updateDateRange('Today');
  }

  String get activeImei => _activeImei;

  void syncRouteParams({String? imei, String? vehicleNameOrId}) {
    final resolvedImei = (imei ?? '').trim();
    if (resolvedImei.isNotEmpty) {
      _activeImei = resolvedImei;
      if ((vehicleNameOrId ?? '').trim().isNotEmpty) {
        vehicleId.value = vehicleNameOrId!.trim();
      } else {
        vehicleId.value = resolvedImei;
      }
      return;
    }
    if (_activeImei.isNotEmpty && vehicleId.value.trim().isEmpty) {
      vehicleId.value = _activeImei;
    }
  }

  String _resolveImeiForHistoryCall() {
    final routeImei = (Get.parameters['imei'] ?? '').trim();
    if (routeImei.isNotEmpty) {
      _activeImei = routeImei;
      return routeImei;
    }
    return _activeImei;
  }

  var currentSpeed = "0 Kmph".obs;
  /// Elapsed time from `vehicle_timing.vehicle_start_time` → `vehicle_end_time`.
  var duration = "00:00:00".obs;
  /// From `kilometer_statistics.total_kilometers_traveled`.
  var totalDistance = "0.00 Km".obs;
  /// From `stop_analysis.total_stops`.
  var totalStops = "0".obs;
  /// From `stop_analysis.total_stop_duration`.
  var totalStopDuration = "0 h 0 m".obs;
  final vehicleStartTime = RxnString();
  final vehicleEndTime = RxnString();

  /// Stops from `stop_analysis.stop_locations` — numbered markers on the route.
  final stopLocations = <HistoryStopLocation>[].obs;
  /// Segments from `vehicle__history` (ignition_off + trip) for the bottom sheet.
  final vehicleHistoryItems = <HistoryVehicleHistoryItem>[].obs;
  final selectedStopIndex = RxnInt();
  final selectedVehicleHistoryIndex = RxnInt();
  final showStopMarkers = true.obs;

  final MapController mapController = MapController();

  void zoomIn() {
    try {
      final camera = mapController.camera;
      mapController.move(camera.center, camera.zoom + 1);
      disableFollowCamera();
    } catch (e) {
      debugPrint('[History] zoomIn failed: $e');
    }
  }

  void zoomOut() {
    try {
      final camera = mapController.camera;
      mapController.move(camera.center, camera.zoom - 1);
      disableFollowCamera();
    } catch (e) {
      debugPrint('[History] zoomOut failed: $e');
    }
  }

  /// Playback speed multiplier: 1.0, 1.5, or 2.0. Used for smooth movement animation.
  final playbackSpeedMultiplier = 1.0.obs;
  var playbackSpeed = "1X".obs;

  /// Camera follows moving marker during playback when enabled.
  final isFollowCameraEnabled = true.obs;
  var isPlaying = false.obs;
  var progress = 0.0.obs;

  void enableFollowCamera() {
    if (!isFollowCameraEnabled.value) {
      isFollowCameraEnabled.value = true;
      debugPrint('[History] Camera: follow enabled');
    }
  }

  void disableFollowCamera() {
    if (isFollowCameraEnabled.value) {
      isFollowCameraEnabled.value = false;
      debugPrint('[History] Camera: follow disabled');
    }
  }

  /// Cycles playback speed: 1 → 1.5 → 2 → 1. Updates display and animation speed.
  void cyclePlaybackSpeed() {
    final current = playbackSpeedMultiplier.value;
    if (current < 1.25) {
      playbackSpeedMultiplier.value = 1.5;
      playbackSpeed.value = '1.5X';
    } else if (current < 1.75) {
      playbackSpeedMultiplier.value = 2.0;
      playbackSpeed.value = '2X';
    } else {
      playbackSpeedMultiplier.value = 1.0;
      playbackSpeed.value = '1X';
    }
  }

  void toggleStopMarkers() {
    showStopMarkers.value = !showStopMarkers.value;
    if (!showStopMarkers.value) selectedStopIndex.value = null;
  }

  void selectStop(int index) {
    if (index < 0) {
      selectedStopIndex.value = null;
      selectedVehicleHistoryIndex.value = null;
      return;
    }
    if (index >= stopLocations.length) return;
    final next = selectedStopIndex.value == index ? null : index;
    selectedStopIndex.value = next;
    if (next == null) {
      selectedVehicleHistoryIndex.value = null;
      return;
    }
    // Sync list selection to matching ignition_off card.
    final match = vehicleHistoryItems.indexWhere(
      (e) => e.isIgnitionOff && e.mapMarkerIndex == next,
    );
    selectedVehicleHistoryIndex.value = match >= 0 ? match : null;
  }

  void selectVehicleHistoryItem(int index) {
    if (index < 0 || index >= vehicleHistoryItems.length) {
      selectedVehicleHistoryIndex.value = null;
      selectedStopIndex.value = null;
      return;
    }
    final next =
        selectedVehicleHistoryIndex.value == index ? null : index;
    selectedVehicleHistoryIndex.value = next;
    if (next == null) {
      selectedStopIndex.value = null;
      return;
    }
    final item = vehicleHistoryItems[next];
    selectedStopIndex.value =
        item.isIgnitionOff ? item.mapMarkerIndex : null;
  }

  void clearSelectedStop() {
    selectedStopIndex.value = null;
    selectedVehicleHistoryIndex.value = null;
  }

  static final _dateFormat = DateFormat('dd MMM yyyy');
  static final _apiDateFormat = DateFormat('yyyy-MM-dd');

  DateTime _parseDisplayDate(String value) {
    try {
      return _dateFormat.parse(value);
    } catch (_) {
      return DateTime.now();
    }
  }

  Future<void> pickFromDate(BuildContext context) async {
    final initial = _parseDisplayDate(fromDate.value);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      fromDate.value = _dateFormat.format(picked);
      if (toDate.value != '-:-') {
        final imei = _resolveImeiForHistoryCall();
        getHistory(imei);
      }
    }
  }

  Future<void> pickToDate(BuildContext context) async {
    final initial = _parseDisplayDate(toDate.value);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      toDate.value = _dateFormat.format(picked);
      if (fromDate.value != '-:-') {
        final imei = _resolveImeiForHistoryCall();
        getHistory(imei);
      }
    }
  }

  HistoryModel historyModel = HistoryModel();

  /// Small list for bottom-sheet timeline UI (kept lightweight to avoid huge widget/data allocation).
  final RxList<LocationHistoryItem> historyPreviewItems =
      <LocationHistoryItem>[].obs;
  List<double> _playbackSpeedSeries = <double>[];

  static const int _maxHistoryPreviewItems = 300;

  List<LocationHistoryItem> _buildHistoryPreview(
    Map<String, dynamic>? responseBody, {
    int maxItems = _maxHistoryPreviewItems,
  }) {
    final data = responseBody?['data'];
    if (data is! Map<String, dynamic>) return <LocationHistoryItem>[];
    final raw = data['location_history'];
    if (raw is! List || raw.isEmpty) return <LocationHistoryItem>[];
    final int n = raw.length;
    if (n <= maxItems || maxItems <= 1) {
      return raw
          .whereType<Map<String, dynamic>>()
          .map(LocationHistoryItem.fromJson)
          .toList();
    }
    final step = (n - 1) / (maxItems - 1);
    final preview = <LocationHistoryItem>[];
    for (int i = 0; i < maxItems; i++) {
      final idx = (i * step).round().clamp(0, n - 1);
      final item = raw[idx];
      if (item is Map<String, dynamic>) {
        preview.add(LocationHistoryItem.fromJson(item));
      }
    }
    return preview;
  }

  /// Cached after parsing in isolate; avoids recomputing on every build.
  List<LatLng> _cachedPolylinePoints = [];

  /// Incremented when starting a new progressive load; stale runs skip updates.
  int _progressiveRunId = 0;

  /// Set when controller is closed; prevents timer/async from touching state and avoids crashes.
  bool _disposed = false;
  int _geocodeRunId = 0;

  static const LatLng _defaultMapCenter = LatLng(11.8745, 75.3704);
  static const double _defaultMapZoom = 13;

  /// Polyline points from location_history (cached; set when history is loaded).
  List<LatLng> get polylinePoints => _cachedPolylinePoints;
  bool _isPolylineFullyDrawn = false;
  bool _pendingPlayRequest = false;

  /// Initial map center: center of polyline bounds when 2+ points, else first point or default.
  LatLng get initialMapCenter {
    final points = polylinePoints;
    if (points.length < 2) {
      return points.isNotEmpty ? points.first : _defaultMapCenter;
    }
    double south = points.first.latitude, north = south;
    double west = points.first.longitude, east = west;
    for (final p in points) {
      if (p.latitude < south) south = p.latitude;
      if (p.latitude > north) north = p.latitude;
      if (p.longitude < west) west = p.longitude;
      if (p.longitude > east) east = p.longitude;
    }
    return LatLng((south + north) / 2, (west + east) / 2);
  }

  /// Initial map zoom level (only used before camera fits to polyline).
  double get initialMapZoom => _defaultMapZoom;

  /// Whether to draw the route polyline (need at least 2 points).
  bool get showMapPolyline => polylinePoints.length > 1;

  /// Points to show as markers (start and end when different).
  List<LatLng> get mapMarkerPoints {
    final points = polylinePoints;
    if (points.isEmpty) return [];
    if (points.length == 1) return [points.first];
    if (!_isPolylineFullyDrawn) return [points.first];
    if (points.first == points.last) return [points.first];
    return [points.first, points.last];
  }

  // --- Moving marker along polyline (reactive to avoid full GetBuilder rebuilds) ---
  final Rxn<LatLng> movingMarkerPosition = Rxn<LatLng>();

  /// Bearing in degrees (0-360) for rotating the vehicle marker along the route.
  final Rxn<double> movingMarkerBearing = Rxn<double>();
  Timer? _movingMarkerTimer;
  int _movingSegmentIndex = 0;
  double _movingSegmentFraction = 0.0;
  List<LatLng> _playbackRoutePoints = [];

  static const Duration _playbackFramePeriod = Duration(milliseconds: 16);
  static const double _playbackTickSeconds = 0.016;
  static const double _bearingSmoothing = 0.35;

  /// Whether the marker is currently animating along the route.
  bool get isMovingMarkerActive => _movingMarkerTimer?.isActive ?? false;

  void _tryFulfillPendingPlay() {
    if (!_pendingPlayRequest) return;
    if (isPlaying.value) return;
    if (polylinePoints.length < 2) return;
    _pendingPlayRequest = false;
    debugPrint('[History] Playback: fulfilling queued play request');
    startMovingMarker();
  }

  /// Starts moving the marker along the polyline. Resumes from current position if paused; otherwise starts from beginning.
  void startMovingMarker() {
    final points = polylinePoints;
    if (points.length < 2) {
      _pendingPlayRequest = true;
      debugPrint('[History] Playback: queued play request (route not ready)');
      return;
    }
    _pendingPlayRequest = false;
    enableFollowCamera();
    stopMovingMarker();
    final bool resumeFromCurrent =
        movingMarkerPosition.value != null &&
        progress.value < 1.0 &&
        _movingSegmentIndex >= 0 &&
        _playbackRoutePoints.isNotEmpty &&
        _movingSegmentIndex < _playbackRoutePoints.length - 1;
    if (!resumeFromCurrent) {
      _playbackRoutePoints = List<LatLng>.from(points);
      _movingSegmentIndex = 0;
      _movingSegmentFraction = 0.0;
      movingMarkerPosition.value = _playbackRoutePoints.first;
      movingMarkerBearing.value = _playbackRoutePoints.length > 1
          ? _getBearing(_playbackRoutePoints[0], _playbackRoutePoints[1])
          : 0.0;
    } else if (_playbackRoutePoints.length < points.length) {
      // Extend frozen route when more polyline chunks arrive during pause.
      _playbackRoutePoints = List<LatLng>.from(points);
    }
    debugPrint(
      '[History] Playback: start movement mode=${resumeFromCurrent ? "resume" : "start"}',
    );
    debugPrint('[History] Playback: backend speed driven movement enabled');
    if (!_disposed) update();
    isPlaying.value = true;

    void advanceFrame() {
      if (_disposed) return;
      final route = _playbackRoutePoints;
      if (route.length < 2) {
        stopMovingMarker();
        return;
      }

      final currentProgress = _getProgressFromMarkerPosition(route);
      final backendKmph = _getBackendSpeedKmphAtProgress(currentProgress);
      double effectiveMps;
      if (_playbackSpeedSeries.isEmpty) {
        effectiveMps = _basePlaybackSpeedMps * playbackSpeedMultiplier.value;
      } else {
        final effectiveKmph = math.max(_minPlaybackSpeedKmph, backendKmph) *
            playbackSpeedMultiplier.value;
        effectiveMps = effectiveKmph / 3.6;
      }
      double distanceBudgetMeters = effectiveMps * _playbackTickSeconds;

      while (distanceBudgetMeters > 0) {
        if (_movingSegmentIndex >= route.length - 1) {
          movingMarkerPosition.value = route.last;
          final prevBearing = movingMarkerBearing.value ?? 0.0;
          final endBearing = route.length >= 2
              ? _getBearing(route[route.length - 2], route.last)
              : prevBearing;
          movingMarkerBearing.value =
              _lerpBearing(prevBearing, endBearing, _bearingSmoothing);
          progress.value = 1.0;
          _syncCurrentSpeedWithProgress(1.0);
          debugPrint('[History] Playback: reached end');
          stopMovingMarker();
          return;
        }

        final a = route[_movingSegmentIndex];
        final b = route[_movingSegmentIndex + 1];
        final segmentMeters = _distanceMeters(a, b);
        if (segmentMeters <= 1e-6) {
          _movingSegmentIndex++;
          _movingSegmentFraction = 0.0;
          continue;
        }

        final currentT = _movingSegmentFraction.clamp(0.0, 1.0);
        final remainingMeters = segmentMeters * (1.0 - currentT);
        if (distanceBudgetMeters >= remainingMeters) {
          distanceBudgetMeters -= remainingMeters;
          _movingSegmentIndex++;
          _movingSegmentFraction = 0.0;
        } else {
          final additionalT = distanceBudgetMeters / segmentMeters;
          _movingSegmentFraction = (currentT + additionalT).clamp(0.0, 1.0);
          distanceBudgetMeters = 0.0;
        }
      }

      if (_movingSegmentIndex >= route.length - 1) {
        movingMarkerPosition.value = route.last;
        final prevBearing = movingMarkerBearing.value ?? 0.0;
        final endBearing = route.length >= 2
            ? _getBearing(route[route.length - 2], route.last)
            : prevBearing;
        movingMarkerBearing.value =
            _lerpBearing(prevBearing, endBearing, _bearingSmoothing);
        progress.value = 1.0;
        _syncCurrentSpeedWithProgress(1.0);
        debugPrint('[History] Playback: reached end');
        stopMovingMarker();
        return;
      }

      final a = route[_movingSegmentIndex];
      final b = route[_movingSegmentIndex + 1];
      final t = _movingSegmentFraction.clamp(0.0, 1.0);
      final interpolated = LatLng(
        a.latitude + (b.latitude - a.latitude) * t,
        a.longitude + (b.longitude - a.longitude) * t,
      );
      movingMarkerPosition.value = interpolated;
      final targetBearing = _getBearing(a, b);
      final prevBearing = movingMarkerBearing.value ?? targetBearing;
      movingMarkerBearing.value =
          _lerpBearing(prevBearing, targetBearing, _bearingSmoothing);
      progress.value = _getProgressFromMarkerPosition(route);
      _syncCurrentSpeedWithProgress();
    }

    advanceFrame();
    debugPrint('[History] Playback: first movement frame applied');
    if (!isPlaying.value) return;
    _movingMarkerTimer =
        Timer.periodic(_playbackFramePeriod, (_) => advanceFrame());
  }

  /// Stops the marker animation.
  void stopMovingMarker() {
    _movingMarkerTimer?.cancel();
    _movingMarkerTimer = null;
    isPlaying.value = false;
  }

  /// Resets moving marker (hides it). Used when route is cleared or reloading.
  void resetMovingMarker() {
    if (_pendingPlayRequest) {
      debugPrint('[History] Playback: cleared pending play request on reset');
    }
    _pendingPlayRequest = false;
    stopMovingMarker();
    movingMarkerPosition.value = null;
    movingMarkerBearing.value = null;
    _movingSegmentIndex = 0;
    _movingSegmentFraction = 0.0;
    _playbackRoutePoints = [];
    if (!_disposed) update();
  }

  /// Places the car marker at the start of the route (resting position). Does not start animation.
  void placeMovingMarkerAtStart() {
    stopMovingMarker();
    final points = polylinePoints;
    _playbackRoutePoints = List<LatLng>.from(points);
    _movingSegmentIndex = 0;
    _movingSegmentFraction = 0.0;
    progress.value = 0.0;
    if (points.isEmpty) {
      movingMarkerPosition.value = null;
      movingMarkerBearing.value = null;
    } else {
      movingMarkerPosition.value = points.first;
      movingMarkerBearing.value = points.length >= 2
          ? _getBearing(points[0], points[1])
          : 0.0;
    }
    _syncCurrentSpeedWithProgress(0.0);
    if (!_disposed) update();
  }

  /// Total distance along the polyline in km.
  double _getTotalDistanceKm(List<LatLng> points) {
    if (points.length < 2) return 0.0;
    double total = 0.0;
    for (int i = 0; i < points.length - 1; i++) {
      total += _distanceKm(points[i], points[i + 1]);
    }
    return total;
  }

  /// Distance covered from start up to (segmentIndex, segmentFraction). In km.
  double _getDistanceCoveredKm(
    List<LatLng> points,
    int segmentIndex,
    double segmentFraction,
  ) {
    if (points.length < 2) return 0.0;
    double covered = 0.0;
    for (int i = 0; i < segmentIndex && i < points.length - 1; i++) {
      covered += _distanceKm(points[i], points[i + 1]);
    }
    if (segmentIndex < points.length - 1) {
      covered +=
          segmentFraction *
          _distanceKm(points[segmentIndex], points[segmentIndex + 1]);
    }
    return covered;
  }

  /// Progress 0.0..1.0 from current marker position (distance covered / total distance).
  double _getProgressFromMarkerPosition([List<LatLng>? routePoints]) {
    final points = routePoints ?? _playbackRoutePoints;
    if (points.isEmpty) {
      final fallback = polylinePoints;
      if (fallback.length < 2) return 0.0;
      return _progressForRoute(fallback);
    }
    if (points.length < 2) return 0.0;
    return _progressForRoute(points);
  }

  double _progressForRoute(List<LatLng> points) {
    final total = _getTotalDistanceKm(points);
    if (total <= 0) return 0.0;
    final covered = _getDistanceCoveredKm(
      points,
      _movingSegmentIndex,
      _movingSegmentFraction,
    );
    return (covered / total).clamp(0.0, 1.0);
  }

  double _lerpBearing(double from, double to, double t) {
    final diff = ((to - from + 540) % 360) - 180;
    return (from + diff * t) % 360;
  }

  /// Moves the marker to the position corresponding to [p] (0.0..1.0) along the route. Stops animation.
  void seekToProgress(double p) {
    final points = _playbackRoutePoints.isNotEmpty
        ? _playbackRoutePoints
        : polylinePoints;
    if (points.length < 2) return;
    stopMovingMarker();
    final clamped = p.clamp(0.0, 1.0);
    if (clamped <= 0.0) {
      _movingSegmentIndex = 0;
      _movingSegmentFraction = 0.0;
      movingMarkerPosition.value = points.first;
      movingMarkerBearing.value = _getBearing(points[0], points[1]);
      progress.value = 0.0;
      _syncCurrentSpeedWithProgress(0.0);
      if (!_disposed) update();
      return;
    }
    if (clamped >= 1.0) {
      _movingSegmentIndex = points.length - 1;
      _movingSegmentFraction = 1.0;
      movingMarkerPosition.value = points.last;
      movingMarkerBearing.value = points.length >= 2
          ? _getBearing(points[points.length - 2], points[points.length - 1])
          : 0.0;
      progress.value = 1.0;
      _syncCurrentSpeedWithProgress(1.0);
      if (!_disposed) update();
      return;
    }
    final totalKm = _getTotalDistanceKm(points);
    final targetKm = clamped * totalKm;
    double cum = 0.0;
    for (int i = 0; i < points.length - 1; i++) {
      final segKm = _distanceKm(points[i], points[i + 1]);
      if (cum + segKm >= targetKm) {
        final t = segKm > 0 ? (targetKm - cum) / segKm : 0.0;
        _movingSegmentIndex = i;
        _movingSegmentFraction = t.clamp(0.0, 1.0);
        final a = points[i];
        final b = points[i + 1];
        movingMarkerPosition.value = LatLng(
          a.latitude + (b.latitude - a.latitude) * _movingSegmentFraction,
          a.longitude + (b.longitude - a.longitude) * _movingSegmentFraction,
        );
        movingMarkerBearing.value = _getBearing(a, b);
        progress.value = clamped;
        _syncCurrentSpeedWithProgress(clamped);
        if (!_disposed) update();
        return;
      }
      cum += segKm;
    }
    _movingSegmentIndex = points.length - 1;  
    _movingSegmentFraction = 1.0;
    movingMarkerPosition.value = points.last;
    progress.value = 1.0;
    _syncCurrentSpeedWithProgress(1.0);
    if (!_disposed) update();
  }

  /// Progressive load: process and draw polyline in chunks of this size.
  static const int _progressiveChunkSize = 80;

  /// Base playback velocity in meters/second when backend speed is unavailable.
  static const double _basePlaybackSpeedMps = 120.0;

  /// Minimum playback speed at 1x (km/h). Raised so 1x feels responsive.
  static const double _minPlaybackSpeedKmph = 480.0;

  /// Mapbox allows up to 100 coords/request — use larger chunks = fewer HTTP round-trips.
  static const int _mapboxChunkSize = 80;

  /// Cap points sent to Mapbox so long trips don't take forever.
  static const int _maxMapboxInputPoints = 500;

  static const double _coordEpsilon = 1e-6;

  /// Parses deviceTime string (ISO or "yyyy-MM-dd HH:mm:ss") for sorting.
  DateTime _parseDeviceTime(String? s) {
    if (s == null || s.trim().isEmpty) return DateTime(1970);
    final t = DateTime.tryParse(s.trim());
    if (t != null) return t;
    try {
      return DateFormat('yyyy-MM-dd HH:mm:ss').parse(s.trim());
    } catch (_) {
      try {
        return DateFormat('dd MMM yyyy').parse(s.trim());
      } catch (_) {
        return DateTime(1970);
      }
    }
  }

  double _parseSpeedValue(dynamic raw) {
    if (raw == null) return 0.0;
    final v = double.tryParse(raw.toString().trim());
    return v ?? 0.0;
  }

  void _buildPlaybackSpeedSeries(List<Map<String, dynamic>> raw) {
    if (raw.isEmpty) {
      _playbackSpeedSeries = <double>[];
      return;
    }
    final sorted = List<Map<String, dynamic>>.from(raw)
      ..sort((a, b) {
        final t1 = _parseDeviceTime(a['deviceTime'] as String?);
        final t2 = _parseDeviceTime(b['deviceTime'] as String?);
        return t1.compareTo(t2);
      });
    _playbackSpeedSeries = sorted
        .map((m) => _parseSpeedValue(m['speed']))
        .toList(growable: false);
  }

  int _speedSeriesIndexForProgress(double progressValue) {
    if (_playbackSpeedSeries.isEmpty) return -1;
    return (progressValue.clamp(0.0, 1.0) * (_playbackSpeedSeries.length - 1))
        .round()
        .clamp(0, _playbackSpeedSeries.length - 1);
  }

  double _getBackendSpeedKmphAtProgress([double? p]) {
    if (_playbackSpeedSeries.isEmpty) return 0.0;
    final idx = _speedSeriesIndexForProgress(p ?? progress.value);
    if (idx < 0) return 0.0;
    return _playbackSpeedSeries[idx];
  }

  void _syncCurrentSpeedWithProgress([double? p]) {
    if (_playbackSpeedSeries.isEmpty) return;
    final progressValue = (p ?? progress.value).clamp(0.0, 1.0);
    final idx = _speedSeriesIndexForProgress(progressValue);
    if (idx < 0) return;
    final speed = _playbackSpeedSeries[idx];
    final speedText = speed % 1 == 0
        ? '${speed.toInt()} Kmph'
        : '${speed.toStringAsFixed(1)} Kmph';
    if (currentSpeed.value != speedText) {
      currentSpeed.value = speedText;
    }
  }

  /// Pipeline: Sort by devicetime only. No filtering — send full track to Mapbox for accurate road snapping.
  List<LatLng> _applyPolylinePipeline(List<Map<String, dynamic>> raw) {
    if (raw.isEmpty) {
      debugPrint('[History] Pipeline: raw input empty, returning []');
      return [];
    }
    debugPrint('[History] Pipeline: input raw points = ${raw.length}');
    final sorted = List<Map<String, dynamic>>.from(raw)
      ..sort((a, b) {
        final t1 = _parseDeviceTime(a['deviceTime'] as String?);
        final t2 = _parseDeviceTime(b['deviceTime'] as String?);
        return t1.compareTo(t2);
      });
    debugPrint(
      '[History] Pipeline: after sort by devicetime = ${sorted.length}',
    );
    final result = sorted
        .map((m) => LatLng(m['lat'] as double, m['lng'] as double))
        .toList();
    if (result.isNotEmpty) {
      debugPrint(
        '[History] Pipeline: final cleanList first lat=${result.first.latitude} lng=${result.first.longitude}',
      );
      debugPrint(
        '[History] Pipeline: final cleanList last lat=${result.last.latitude} lng=${result.last.longitude}',
      );
    }
    return result;
  }

  bool _samePoint(LatLng a, LatLng b) {
    return (a.latitude - b.latitude).abs() < _coordEpsilon &&
        (a.longitude - b.longitude).abs() < _coordEpsilon;
  }

  /// Snaps path to roads using Mapbox Map Matching API. Returns raw points on failure.
  Future<List<LatLng>> _smoothPathWithMapbox(List<LatLng> rawPoints) async {
    final token = ApiConfig.mapboxAccessToken;
    debugPrint('[History] Mapbox: input rawPoints = ${rawPoints.length}');
    if (token.isEmpty) {
      debugPrint('[History] Mapbox: token empty, returning raw points');
      return rawPoints;
    }
    if (rawPoints.length < 2) {
      debugPrint('[History] Mapbox: rawPoints < 2, returning as-is');
      return rawPoints;
    }
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 25),
        receiveTimeout: const Duration(seconds: 25),
        validateStatus: (status) => status != null && status < 500,
      ),
    );
    final snappedPath = <LatLng>[];
    int successChunks = 0;
    int totalChunks = 0;
    try {
      for (int i = 0; i < rawPoints.length; i += _mapboxChunkSize) {
        final end = (i + _mapboxChunkSize > rawPoints.length)
            ? rawPoints.length
            : i + _mapboxChunkSize;
        final chunk = rawPoints.sublist(i, end);
        if (chunk.length < 2) continue;
        totalChunks++;
        final chunkIndex = i ~/ _mapboxChunkSize;
        debugPrint(
          '[History] Mapbox: chunk $chunkIndex request points ${chunk.length} (indices $i–${end - 1})',
        );
        Map<String, dynamic>? responseData;
        int? statusCode;
        try {
          final coords = chunk
              .map((p) => '${p.longitude},${p.latitude}')
              .join(';');
          final radiuses = List.filled(chunk.length, 25).join(';');
          final url =
              '$_mapboxMatchBase/$coords.json?geometries=geojson&overview=full&radiuses=$radiuses&tidy=true&access_token=$token';
          debugPrint(
            '[History] Mapbox: chunk $chunkIndex about to HTTP GET (url length=${url.length})',
          );
          final response = await dio.get<Map<String, dynamic>>(url);
          statusCode = response.statusCode;
          responseData = response.data;
          debugPrint(
            '[History] Mapbox: chunk $chunkIndex HTTP done statusCode=$statusCode dataNull=${responseData == null}',
          );
        } catch (e, st) {
          debugPrint('[History] Mapbox: chunk $chunkIndex HTTP THREW $e');
          debugPrint('[History] Mapbox: chunk $chunkIndex stack: $st');
          continue;
        }
        if (statusCode != 200 || responseData == null) {
          debugPrint(
            '[History] Mapbox: chunk $chunkIndex HTTP ${statusCode ?? "null"}, skipping',
          );
          continue;
        }
        final matchingsRaw = responseData['matchings'];
        final inputMatchingsCount = matchingsRaw is List
            ? matchingsRaw.length
            : 0;
        debugPrint(
          '[History] Mapbox: chunk $chunkIndex parse isolate start inputMatchings=$inputMatchingsCount',
        );
        final parsePayload = <String, dynamic>{
          // Send only fields required by parser to reduce isolate transfer payload.
          'code': responseData['code'],
          'matchings': matchingsRaw is List ? matchingsRaw : const [],
        };
        final parseSw = Stopwatch()..start();
        List<List<double>> chunkSmoothed;
        try {
          chunkSmoothed = await compute(_processMapboxChunk, parsePayload);
        } catch (e, st) {
          debugPrint(
            '[History] Mapbox: chunk $chunkIndex parse isolate FAILED error=$e',
          );
          debugPrint('[History] Mapbox: chunk $chunkIndex parse stack: $st');
          continue;
        } finally {
          parseSw.stop();
        }
        debugPrint(
          '[History] Mapbox: chunk $chunkIndex parse isolate done outputPoints=${chunkSmoothed.length} elapsedMs=${parseSw.elapsedMilliseconds}',
        );
        if (chunkSmoothed.isEmpty) {
          debugPrint(
            '[History] Mapbox: chunk $chunkIndex parsed 0 points, skipping',
          );
          continue;
        }
        successChunks++;
        debugPrint(
          '[History] Mapbox: chunk $chunkIndex matched ${chunkSmoothed.length} points',
        );
        try {
          final chunkLatLng = chunkSmoothed
              .map((p) => LatLng(p[0], p[1]))
              .toList();
          if (snappedPath.isNotEmpty &&
              chunkLatLng.isNotEmpty &&
              _samePoint(snappedPath.last, chunkLatLng.first)) {
            chunkLatLng.removeAt(0);
          }
          snappedPath.addAll(chunkLatLng);
        } catch (e, st) {
          debugPrint(
            '[History] Mapbox: chunk $chunkIndex to LatLng/addAll THREW $e',
          );
          debugPrint('[History] Mapbox: chunk $chunkIndex stack: $st');
          continue;
        }
        debugPrint(
          '[History] Mapbox: chunk $chunkIndex fully done, snappedPath.length=${snappedPath.length}',
        );
      }
      if (snappedPath.isEmpty) {
        debugPrint(
          '[History] Mapbox: all chunks failed, returning raw points (${rawPoints.length})',
        );
        return rawPoints;
      }
      if (successChunks < totalChunks) {
        debugPrint(
          '[History] Mapbox: partial ($successChunks/$totalChunks chunks), snapped ${snappedPath.length} points',
        );
        debugPrint(
          'Mapbox: partial ($successChunks/$totalChunks chunks), ${snappedPath.length} points',
        );
      } else {
        debugPrint(
          '[History] Mapbox: all $totalChunks chunks ok, snapped ${snappedPath.length} points',
        );
      }
      debugPrint(
        '[History] Mapbox: _smoothPathWithMapbox returning snappedPath.length=${snappedPath.length}',
      );
      return snappedPath;
    } catch (e, st) {
      debugPrint('[History] Mapbox: _smoothPathWithMapbox OUTER CATCH $e');
      debugPrint('[History] Mapbox: _smoothPathWithMapbox FULL STACK:\n$st');
      return rawPoints;
    }
  }

  double _distanceKm(LatLng a, LatLng b) {
    const R = 6371.0;
    final dLat = (b.latitude - a.latitude) * math.pi / 180;
    final dLon = (b.longitude - a.longitude) * math.pi / 180;
    final la1 = a.latitude * math.pi / 180;
    final la2 = b.latitude * math.pi / 180;
    final x =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(la1) * math.cos(la2) * math.sin(dLon / 2) * math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(x), math.sqrt(1 - x));
    return R * c;
  }

  double _distanceMeters(LatLng a, LatLng b) => _distanceKm(a, b) * 1000;

  /// Finds the closest point on the polyline to [currentLocation] (snap-to-route).
  /// Returns map with 'point', 'distance' (m), 'segmentIndex', 't' (0..1 on segment).
  Map<String, dynamic> getClosestPointOnPolyline(
    LatLng currentLocation,
    List<LatLng> polyline,
  ) {
    if (polyline.isEmpty) {
      return {
        'point': currentLocation,
        'distance': double.infinity,
        'segmentIndex': -1,
        't': 0.0,
      };
    }
    if (polyline.length == 1) {
      final dist = _distanceMeters(currentLocation, polyline[0]);
      return {
        'point': polyline[0],
        'distance': dist,
        'segmentIndex': 0,
        't': 0.0,
      };
    }
    double minDistance = double.infinity;
    LatLng closestPoint = polyline[0];
    int closestSegmentIndex = 0;
    double closestT = 0.0;
    for (int i = 0; i < polyline.length - 1; i++) {
      final p1 = polyline[i];
      final p2 = polyline[i + 1];
      final dx = p2.longitude - p1.longitude;
      final dy = p2.latitude - p1.latitude;
      final segmentLengthSq = dx * dx + dy * dy;
      if (segmentLengthSq < 1e-10) {
        final dist = _distanceMeters(currentLocation, p1);
        if (dist < minDistance) {
          minDistance = dist;
          closestPoint = p1;
          closestSegmentIndex = i;
          closestT = 0.0;
        }
        continue;
      }
      final t =
          ((currentLocation.longitude - p1.longitude) * dx +
              (currentLocation.latitude - p1.latitude) * dy) /
          segmentLengthSq;
      final clampedT = t.clamp(0.0, 1.0);
      final q = LatLng(
        p1.latitude + clampedT * dy,
        p1.longitude + clampedT * dx,
      );
      final dist = _distanceMeters(currentLocation, q);
      if (dist < minDistance) {
        minDistance = dist;
        closestPoint = q;
        closestSegmentIndex = i;
        closestT = clampedT;
      }
    }
    return {
      'point': closestPoint,
      'distance': minDistance,
      'segmentIndex': closestSegmentIndex,
      't': closestT,
    };
  }


  /// Loads polyline step-by-step: sends points to Mapbox for snapping.
  /// Caller should already show the raw GPS line for instant feedback.
  void _runProgressiveSnapInBackground(List<LatLng> cleanPoints) {
    if (cleanPoints.length < 2) {
      debugPrint('[History] Progressive: cleanPoints < 2, skipping');
      return;
    }
    final runId = ++_progressiveRunId;
    final mapboxInput = _downsampleForMapbox(cleanPoints);
    debugPrint(
      '[History] Progressive: runId=$runId cleanPoints=${cleanPoints.length} '
      'mapboxInput=${mapboxInput.length}',
    );
    Future<void>.delayed(Duration.zero, () async {
      _isPolylineFullyDrawn = false;
      final snappedAccum = <LatLng>[];
      int chunkIndex = 0;
      for (
        int start = 0;
        start < mapboxInput.length;
        start += _progressiveChunkSize
      ) {
        if (_disposed || runId != _progressiveRunId) return;
        final end = (start + _progressiveChunkSize > mapboxInput.length)
            ? mapboxInput.length
            : start + _progressiveChunkSize;
        final chunk = mapboxInput.sublist(start, end);
        if (chunk.length < 2) continue;
        debugPrint(
          '[History] Progressive: chunk $chunkIndex start=$start end=$end size=${chunk.length}',
        );
        List<LatLng> snapped;
        try {
          snapped = await _smoothPathWithMapbox(chunk);
        } catch (e, st) {
          debugPrint(
            '[History] Progressive: chunk $chunkIndex _smoothPathWithMapbox THREW $e\n$st',
          );
          chunkIndex++;
          continue;
        }
        if (_disposed || runId != _progressiveRunId) return;
        final mapboxOk = !identical(snapped, chunk) && snapped.length >= 2;
        if (!mapboxOk) {
          // Keep raw segment if Mapbox fails for this chunk.
          if (snappedAccum.isNotEmpty &&
              chunk.isNotEmpty &&
              _samePoint(snappedAccum.last, chunk.first)) {
            snappedAccum.addAll(chunk.skip(1));
          } else {
            snappedAccum.addAll(chunk);
          }
          chunkIndex++;
          continue;
        }
        if (snappedAccum.isNotEmpty &&
            snapped.isNotEmpty &&
            _samePoint(snappedAccum.last, snapped.first)) {
          snapped = snapped.sublist(1);
        }
        snappedAccum.addAll(snapped);
        // Update the blue line as soon as we have snapped geometry.
        if (snappedAccum.length >= 2) {
          _cachedPolylinePoints = List<LatLng>.from(snappedAccum);
          _snapStopsToTraveledLine();
          if (!_disposed) update();
        }
        chunkIndex++;
      }
      if (_disposed || runId != _progressiveRunId) return;
      if (snappedAccum.length >= 2) {
        _cachedPolylinePoints = List<LatLng>.from(snappedAccum);
      }
      _isPolylineFullyDrawn = true;
      debugPrint(
        '[History] Progressive: done. Total polyline points on map = ${_cachedPolylinePoints.length}',
      );
      _snapStopsToTraveledLine();
      placeMovingMarkerAtStart();
      if (_disposed) return;
      update();
      _tryFulfillPendingPlay();
    });
  }

  /// Reduce dense GPS tracks before Mapbox to cut HTTP round-trips.
  List<LatLng> _downsampleForMapbox(List<LatLng> points) {
    if (points.length <= _maxMapboxInputPoints) return points;
    final result = <LatLng>[points.first];
    final step = (points.length - 1) / (_maxMapboxInputPoints - 1);
    for (var i = 1; i < _maxMapboxInputPoints - 1; i++) {
      result.add(points[(i * step).round().clamp(0, points.length - 1)]);
    }
    result.add(points.last);
    debugPrint(
      '[History] Mapbox downsample: ${points.length} → ${result.length}',
    );
    return result;
  }

  @override
  void onClose() {
    _disposed = true;
    _geocodeRunId++;
    stopMovingMarker();
    super.onClose();
  }

  bool _historyFetchScheduled = false;

  /// Fetches history once per screen load (didChangeDependencies can run multiple times).
  void getHistoryOnce(String imei) {
    if (_historyFetchScheduled || imei.trim().isEmpty) return;
    _historyFetchScheduled = true;
    getHistory(imei);
  }

  Future<void> getHistory(String imei) async {
    final effectiveImei = imei.trim().isNotEmpty
        ? imei.trim()
        : _resolveImeiForHistoryCall();
    debugPrint(
      '[History] getHistory: imei=$effectiveImei fromDate=${fromDate.value} toDate=${toDate.value}',
    );
    if (effectiveImei.isEmpty) return;
    _activeImei = effectiveImei;
    _historyFetchScheduled = true;
    if (_pendingPlayRequest) {
      debugPrint(
        '[History] Playback: cleared pending play request on new fetch',
      );
    }
    _pendingPlayRequest = false;
    isLoading.value = true;
    _resetHistorySummaryStats();
    debugPrint(
      '[History] getHistory: imei=$imei fromDate=${fromDate.value} toDate=${toDate.value}',
    );
    try {
      final token = DioClient().dio.options.headers['Authorization']
          ?.toString();
      final params = <String, dynamic>{
        'baseUrl': ApiConfig.baseUrl,
        'path': ApiEndPoints.vehicleHistory,
        'query': <String, String>{
          'imei': effectiveImei,
          'from_date': fromDate.value == '-:-'
              ? _apiDateFormat.format(DateTime.now())
              : _apiDateFormat.format(_parseDisplayDate(fromDate.value)),
          'to_date': toDate.value == '-:-'
              ? _apiDateFormat.format(DateTime.now())
              : _apiDateFormat.format(_parseDisplayDate(toDate.value)),
        },
        'token': token,
      };
      debugPrint(
        '[History] getHistory: fetching backend ${params['path']} query=${params['query']}',
      );
      final result = await compute(_getHistoryInIsolate, params);
      if (result.containsKey('error')) {
        debugPrint('[History] getHistory: backend error ${result['error']}');
        isLoading.value = false;
        showErrorMessage(Exception(result['error']));
        return;
      }
      final statusCode = result['statusCode'] as int?;
      debugPrint('[History] getHistory: backend statusCode=$statusCode');
      final responseBody = result['data'] as Map<String, dynamic>?;
      if (responseBody != null) {
        final dataMap = responseBody['data'];
        final dataJson = dataMap is Map
            ? Map<String, dynamic>.from(dataMap)
            : <String, dynamic>{};
        Map<String, dynamic>? asMap(dynamic value) =>
            value is Map ? Map<String, dynamic>.from(value) : null;

        // Keep model lightweight: avoid parsing full location_history into HistoryModel.
        historyModel = HistoryModel(
          status: responseBody['status'] is bool
              ? responseBody['status'] as bool
              : null,
          data: HistoryData(
            vehicleInfo: asMap(dataJson['vehicle_info']) != null
                ? VehicleInfo.fromJson(asMap(dataJson['vehicle_info']))
                : null,
            locationHistory: const [],
            kilometerStatistics: asMap(dataJson['kilometer_statistics']) != null
                ? HistoryKilometerStatistics.fromJson(
                    asMap(dataJson['kilometer_statistics']),
                  )
                : null,
            vehicleTiming: asMap(dataJson['vehicle_timing']) != null
                ? HistoryVehicleTiming.fromJson(
                    asMap(dataJson['vehicle_timing']),
                  )
                : null,
            speedStatistics: asMap(dataJson['speed_statistics']) != null
                ? HistorySpeedStatistics.fromJson(
                    asMap(dataJson['speed_statistics']),
                  )
                : null,
            stopAnalysis: asMap(dataJson['stop_analysis']) != null
                ? HistoryStopAnalysis.fromJson(
                    asMap(dataJson['stop_analysis']),
                  )
                : null,
          ),
        );
        _applyHistorySummaryStats(historyModel.data, dataJson: dataJson);
        _applyStopLocationsFromResponse(dataJson);
        historyPreviewItems.assignAll(_buildHistoryPreview(responseBody));
        debugPrint(
          '[History] getHistory: history preview items = ${historyPreviewItems.length}',
        );
        debugPrint(
          '[History] getHistory: parsing lat/lng from response (capped in isolate to avoid crash)',
        );
        final rawPoints = await compute(
          _buildPolylinePointsInIsolate,
          <String, dynamic>{'responseBody': responseBody},
        );
        debugPrint(
          '[History] getHistory: rawPoints from isolate = ${rawPoints.length}',
        );
        _buildPlaybackSpeedSeries(rawPoints);
        _applyDurationFallbackFromRawPoints(rawPoints);
        final cleanList = _applyPolylinePipeline(rawPoints);
        debugPrint(
          '[History] getHistory: pipeline cleanList = ${cleanList.length} points',
        );
        resetMovingMarker();
        if (cleanList.length >= 2) {
          // Instant UI: draw raw GPS track immediately, then refine with Mapbox.
          _cachedPolylinePoints = List<LatLng>.from(cleanList);
          _isPolylineFullyDrawn = false;
          debugPrint(
            '[History] getHistory: drew raw line (${cleanList.length} pts), '
            'starting Mapbox refine in background',
          );
          _syncCurrentSpeedWithProgress(0.0);
          placeMovingMarkerAtStart();
          update();
          isLoading.value = false;
          _runProgressiveSnapInBackground(cleanList);
        } else {
          debugPrint('[History] getHistory: cleanList < 2, no polyline');
          _cachedPolylinePoints = [];
          _isPolylineFullyDrawn = false;
          _syncCurrentSpeedWithProgress(0.0);
          update();
          isLoading.value = false;
        }
      } else {
        debugPrint('[History] getHistory: responseBody null');
        historyPreviewItems.clear();
        _playbackSpeedSeries = <double>[];
        _resetHistorySummaryStats();
        isLoading.value = false;
      }
    } catch (e, st) {
      debugPrint('[History] getHistory: exception $e\n$st');
      isLoading.value = false;
      showErrorMessage(e);
    }
  }

  void _resetHistorySummaryStats() {
    totalDistance.value = '0.00 Km';
    duration.value = '00:00:00';
    totalStops.value = '0';
    totalStopDuration.value = '0 h 0 m';
    vehicleStartTime.value = null;
    vehicleEndTime.value = null;
    stopLocations.clear();
    vehicleHistoryItems.clear();
    selectedStopIndex.value = null;
    selectedVehicleHistoryIndex.value = null;
  }

  void _applyStopLocationsFromResponse(Map<String, dynamic> dataJson) {
    selectedStopIndex.value = null;
    selectedVehicleHistoryIndex.value = null;

    // Prefer new `vehicle__history` segments for the bottom sheet list.
    final rawVehicleHistory =
        dataJson['vehicle__history'] ?? dataJson['vehicle_history'];
    final segments = <HistoryVehicleHistoryItem>[];
    if (rawVehicleHistory is List) {
      for (final item in rawVehicleHistory) {
        if (item is! Map) continue;
        segments.add(
          HistoryVehicleHistoryItem.fromJson(Map<String, dynamic>.from(item)),
        );
      }
    }
    debugPrint(
      '[History] vehicle__history segments = ${segments.length}',
    );

    // Map markers: ignition_off points from vehicle__history, else stop_analysis.
    var stops = <HistoryStopLocation>[];
    final numberedSegments = <HistoryVehicleHistoryItem>[];
    var markerIndex = 0;
    if (segments.isNotEmpty) {
      for (final segment in segments) {
        if (segment.isIgnitionOff && segment.hasValidCoordinates) {
          numberedSegments.add(
            segment.copyWith(mapMarkerIndex: markerIndex),
          );
          stops.add(
            HistoryStopLocation(
              latitude: segment.startLatitude,
              longitude: segment.startLongitude,
              arrivalTime: segment.startTime,
              departureTime: segment.endTime,
              duration: segment.duration,
              address: segment.startAddress,
              index: markerIndex + 1,
            ),
          );
          markerIndex++;
        } else {
          numberedSegments.add(segment);
        }
      }
      vehicleHistoryItems.assignAll(numberedSegments);
    } else {
      vehicleHistoryItems.clear();
    }

    if (stops.isEmpty) {
      final analysisMap = dataJson['stop_analysis'];
      HistoryStopAnalysis? analysis;
      if (analysisMap is Map) {
        analysis = HistoryStopAnalysis.fromJson(
          Map<String, dynamic>.from(analysisMap),
        );
      }

      stops = List<HistoryStopLocation>.from(
        analysis?.stopLocations ?? const <HistoryStopLocation>[],
      );

      final rawStops =
          analysisMap is Map ? analysisMap['stop_locations'] : null;
      if (rawStops is List) {
        debugPrint(
          '[History] stop_analysis.total_stops=${analysis?.totalStops} '
          'raw stop_locations=${rawStops.length} parsed=${stops.length}',
        );
      }

      if (stops.isEmpty) {
        stops = _deriveStopsFromLocationHistory(dataJson['location_history']);
        debugPrint(
          '[History] derived stop markers from location_history = ${stops.length}',
        );
      }

      // Legacy UI: if no vehicle__history, show stop_analysis as ignition_off cards.
      if (vehicleHistoryItems.isEmpty && stops.isNotEmpty) {
        vehicleHistoryItems.assignAll(
          stops.map(
            (s) => HistoryVehicleHistoryItem(
              startLatitude: s.latitude,
              startLongitude: s.longitude,
              endLatitude: s.latitude,
              endLongitude: s.longitude,
              startTime: s.arrivalTime,
              endTime: s.departureTime,
              duration: s.duration,
              type: 'ignition_off',
              startAddress: s.address,
              mapMarkerIndex: (s.index ?? 1) - 1,
            ),
          ),
        );
      }

      final stopCount = analysis?.totalStops ?? stops.length;
      totalStops.value = '$stopCount';
      final stopDur = analysis?.totalStopDuration;
      if (stopDur != null) {
        totalStopDuration.value =
            HistoryStopLocation.formatDurationSeconds(stopDur);
      } else if (stops.isNotEmpty) {
        totalStopDuration.value = '${stops.length} stops';
      } else {
        totalStopDuration.value = '0 h 0 m';
      }
    } else {
      final ignitionCount =
          vehicleHistoryItems.where((e) => e.isIgnitionOff).length;
      totalStops.value = '$ignitionCount';
      totalStopDuration.value = '$ignitionCount stops';
    }

    // Keep vehicle__history order for map markers so list ↔ marker indices stay aligned.
    if (segments.isEmpty) {
      stops = _sortStopsChronologically(stops);
    }
    stopLocations.assignAll(_numberStops(stops));
    _snapStopsToTraveledLine();
    _resolveVehicleHistoryAddresses();

    debugPrint(
      '[History] bottom sheet segments = ${vehicleHistoryItems.length}, '
      'map stop markers = ${stopLocations.length}',
    );
  }

  /// Reverse-geocode vehicle__history segments (and sync ignition_off map markers).
  /// Prefers Mapbox place for exact start/end coordinates over API address text
  /// so labels stay accurate and consistent.
  Future<void> _resolveVehicleHistoryAddresses() async {
    final runId = ++_geocodeRunId;
    final count = vehicleHistoryItems.length;
    if (count == 0) {
      await _resolveMissingStopAddresses(runId: runId);
      return;
    }

    debugPrint('[History] reverse-geocoding $count vehicle__history segments');
    for (var i = 0; i < count; i++) {
      if (_disposed || runId != _geocodeRunId) return;
      if (i >= vehicleHistoryItems.length) return;

      var item = vehicleHistoryItems[i];
      String? startAddress = item.startAddress?.trim();
      String? endAddress = item.endAddress?.trim();

      if (item.hasValidStartCoordinates) {
        final place = await ReverseGeocodeService.instance.reverse(
          item.startLatitude,
          item.startLongitude,
        );
        if (_disposed || runId != _geocodeRunId) return;
        if (place != null && place.isNotEmpty) {
          startAddress = place;
        } else if (startAddress != null &&
            startAddress.isNotEmpty &&
            startAddress.toLowerCase() != 'null' &&
            !_looksLikeRawCoordinates(startAddress)) {
          startAddress = ReverseGeocodeService.withoutPincode(startAddress);
        } else {
          startAddress = null;
        }
      } else if (startAddress != null &&
          startAddress.isNotEmpty &&
          startAddress.toLowerCase() != 'null') {
        startAddress = ReverseGeocodeService.withoutPincode(startAddress);
      }

      if (item.isTrip && item.hasValidEndCoordinates) {
        final place = await ReverseGeocodeService.instance.reverse(
          item.endLatitude,
          item.endLongitude,
        );
        if (_disposed || runId != _geocodeRunId) return;
        if (place != null && place.isNotEmpty) {
          endAddress = place;
        } else if (endAddress != null &&
            endAddress.isNotEmpty &&
            endAddress.toLowerCase() != 'null' &&
            !_looksLikeRawCoordinates(endAddress)) {
          endAddress = ReverseGeocodeService.withoutPincode(endAddress);
        } else {
          endAddress = null;
        }
      } else if (endAddress != null &&
          endAddress.isNotEmpty &&
          endAddress.toLowerCase() != 'null') {
        endAddress = ReverseGeocodeService.withoutPincode(endAddress);
      }

      if (i >= vehicleHistoryItems.length) return;
      item = vehicleHistoryItems[i].copyWith(
        startAddress: startAddress,
        endAddress: endAddress,
      );
      vehicleHistoryItems[i] = item;
      if (startAddress != null && startAddress.isNotEmpty) {
        _syncAddressToStopMarker(item, startAddress);
      }
      await Future<void>.delayed(const Duration(milliseconds: 80));
    }

    await _resolveMissingStopAddresses(runId: runId);
  }

  void _syncAddressToStopMarker(HistoryVehicleHistoryItem item, String address) {
    final markerIndex = item.mapMarkerIndex;
    if (markerIndex == null) return;
    if (markerIndex < 0 || markerIndex >= stopLocations.length) return;
    // Always apply coordinate-based address so markers stay accurate.
    stopLocations[markerIndex] =
        stopLocations[markerIndex].copyWith(address: address);
  }

  /// Reverse-geocode stops from exact GPS coordinates (always preferred).
  Future<void> _resolveMissingStopAddresses({int? runId}) async {
    final activeRunId = runId ?? ++_geocodeRunId;
    final count = stopLocations.length;
    if (count == 0) return;

    debugPrint('[History] reverse-geocoding $count stop locations');
    for (var i = 0; i < count; i++) {
      if (_disposed || activeRunId != _geocodeRunId) return;
      if (i >= stopLocations.length) return;

      final stop = stopLocations[i];
      final place = await ReverseGeocodeService.instance.reverse(
        stop.latitude,
        stop.longitude,
      );
      if (_disposed || activeRunId != _geocodeRunId) return;
      if (i >= stopLocations.length) return;

      if (place != null && place.isNotEmpty) {
        stopLocations[i] = stopLocations[i].copyWith(address: place);
      } else {
        final existing = stop.address?.trim();
        if (existing != null &&
            existing.isNotEmpty &&
            existing.toLowerCase() != 'null' &&
            !_looksLikeRawCoordinates(existing)) {
          stopLocations[i] = stopLocations[i].copyWith(
            address: ReverseGeocodeService.withoutPincode(existing),
          );
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  bool _looksLikeRawCoordinates(String value) {
    final parts = value.split(',');
    if (parts.length != 2) return false;
    final lat = double.tryParse(parts[0].trim());
    final lng = double.tryParse(parts[1].trim());
    return lat != null && lng != null;
  }

  /// Sort stops by arrival time (then departure). Ensures marker 1 is the first stop.
  List<HistoryStopLocation> _sortStopsChronologically(
    List<HistoryStopLocation> stops,
  ) {
    if (stops.length <= 1) return List<HistoryStopLocation>.from(stops);

    final sorted = List<HistoryStopLocation>.from(stops);
    sorted.sort((a, b) {
      final aHas = a.arrivalTime != null && a.arrivalTime!.trim().isNotEmpty;
      final bHas = b.arrivalTime != null && b.arrivalTime!.trim().isNotEmpty;
      if (aHas && bHas) {
        final cmp = _parseDeviceTime(a.arrivalTime)
            .compareTo(_parseDeviceTime(b.arrivalTime));
        if (cmp != 0) return cmp;
      } else if (aHas != bHas) {
        return aHas ? -1 : 1;
      }

      final aDep = a.departureTime != null && a.departureTime!.trim().isNotEmpty;
      final bDep = b.departureTime != null && b.departureTime!.trim().isNotEmpty;
      if (aDep && bDep) {
        return _parseDeviceTime(a.departureTime)
            .compareTo(_parseDeviceTime(b.departureTime));
      }
      return 0;
    });
    return sorted;
  }

  List<HistoryStopLocation> _numberStops(List<HistoryStopLocation> stops) {
    return [
      for (var i = 0; i < stops.length; i++)
        stops[i].copyWith(index: i + 1),
    ];
  }

  /// Place stop markers on the blue Mapbox-snapped route (raw GPS can sit off-road).
  /// Popup Latlong still shows the original GPS from the API.
  /// Snaps in chronological order along the route so 1 → 2 → 3 follow travel direction.
  void _snapStopsToTraveledLine() {
    if (stopLocations.isEmpty) return;
    final route = _cachedPolylinePoints;
    if (route.length < 2) return;

    final snapped = <HistoryStopLocation>[];
    var minRouteIndex = 0;

    for (final stop in stopLocations) {
      final nearest = _nearestPointOnPolylineAfter(
        LatLng(stop.latitude, stop.longitude),
        route,
        minRouteIndex: minRouteIndex,
      );
      snapped.add(
        stop.copyWith(
          mapLatitude: nearest.point.latitude,
          mapLongitude: nearest.point.longitude,
        ),
      );
      // Next stop should generally be further along the traveled line.
      minRouteIndex = nearest.segmentIndex;
    }
    stopLocations.assignAll(snapped);
    debugPrint(
      '[History] snapped ${snapped.length} stop markers onto traveled line (ordered)',
    );
  }

  ({LatLng point, int segmentIndex}) _nearestPointOnPolylineAfter(
    LatLng target,
    List<LatLng> route, {
    int minRouteIndex = 0,
  }) {
    final start = minRouteIndex.clamp(0, route.length - 2);
    var best = route[start];
    var bestDist = _calculateDistanceMeters(target, best);
    var bestSeg = start;

    for (var i = start + 1; i < route.length; i++) {
      final a = route[i - 1];
      final b = route[i];
      final projected = _projectPointOntoSegment(target, a, b);
      final dist = _calculateDistanceMeters(target, projected);
      if (dist < bestDist) {
        bestDist = dist;
        best = projected;
        bestSeg = i - 1;
      }
    }

    // If remaining route is a poor match (e.g. GPS noise), fall back to full route.
    if (bestDist > 250 && start > 0) {
      return _nearestPointOnPolylineAfter(target, route, minRouteIndex: 0);
    }
    return (point: best, segmentIndex: bestSeg);
  }

  LatLng _projectPointOntoSegment(LatLng p, LatLng a, LatLng b) {
    final ax = a.longitude;
    final ay = a.latitude;
    final bx = b.longitude;
    final by = b.latitude;
    final px = p.longitude;
    final py = p.latitude;

    final dx = bx - ax;
    final dy = by - ay;
    if (dx == 0 && dy == 0) return a;

    final t = ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy);
    final clamped = t.clamp(0.0, 1.0);
    return LatLng(ay + dy * clamped, ax + dx * clamped);
  }

  double _calculateDistanceMeters(LatLng p1, LatLng p2) {
    const radius = 6371000.0;
    final dLat = (p2.latitude - p1.latitude) * math.pi / 180;
    final dLon = (p2.longitude - p1.longitude) * math.pi / 180;
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(p1.latitude * math.pi / 180) *
            math.cos(p2.latitude * math.pi / 180) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return radius * (2 * math.atan2(math.sqrt(a), math.sqrt(1 - a)));
  }

  /// Build stop markers from consecutive stopped points when API stop_locations is empty.
  List<HistoryStopLocation> _deriveStopsFromLocationHistory(dynamic raw) {
    if (raw is! List || raw.isEmpty) return const [];

    final points = <Map<String, dynamic>>[];
    for (final item in raw) {
      if (item is Map) points.add(Map<String, dynamic>.from(item));
    }
    if (points.isEmpty) return const [];

    points.sort((a, b) {
      final t1 = _parseDeviceTime(
        (a['devicetime'] ?? a['device_time'])?.toString(),
      );
      final t2 = _parseDeviceTime(
        (b['devicetime'] ?? b['device_time'])?.toString(),
      );
      return t1.compareTo(t2);
    });

    bool isStoppedPoint(Map<String, dynamic> p) {
      if (p['is_stopped'] == true) return true;
      final mode = p['mode']?.toString().toUpperCase() ?? '';
      if (mode == 'S' || mode == 'STOPPED') return true;
      return false;
    }

    double? coord(Map<String, dynamic> p, List<String> keys) {
      for (final key in keys) {
        final v = p[key];
        if (v is num) return v.toDouble();
        final parsed = double.tryParse(v?.toString() ?? '');
        if (parsed != null) return parsed;
      }
      return null;
    }

    final stops = <HistoryStopLocation>[];
    int? clusterStart;

    void closeCluster(int endIdx) {
      final startIdx = clusterStart;
      if (startIdx == null || endIdx < startIdx) return;
      final first = points[startIdx];
      final last = points[endIdx];
      final lat = coord(first, ['latitude', 'lat']);
      final lng = coord(first, ['longitude', 'lng', 'lon']);
      if (lat == null || lng == null || (lat == 0 && lng == 0)) return;

      final arrival =
          (first['devicetime'] ?? first['device_time'])?.toString();
      final departure =
          (last['devicetime'] ?? last['device_time'])?.toString();
      String? durationText;
      if (arrival != null && departure != null) {
        final a = _parseDeviceTime(arrival);
        final b = _parseDeviceTime(departure);
        if (!b.isBefore(a)) {
          durationText = HistoryStopLocation.formatDurationSeconds(
            b.difference(a).inSeconds,
          );
        }
      }

      stops.add(
        HistoryStopLocation(
          latitude: lat,
          longitude: lng,
          arrivalTime: arrival,
          departureTime: departure,
          duration: durationText,
          address: first['address']?.toString(),
        ),
      );
    }

    for (var i = 0; i < points.length; i++) {
      if (isStoppedPoint(points[i])) {
        clusterStart ??= i;
      } else if (clusterStart != null) {
        closeCluster(i - 1);
        clusterStart = null;
      }
    }
    if (clusterStart != null) closeCluster(points.length - 1);

    // Ignore tiny single-point blips with no meaningful duration.
    return stops
        .where((s) {
          if (s.arrivalTime == null || s.departureTime == null) return true;
          final a = _parseDeviceTime(s.arrivalTime);
          final b = _parseDeviceTime(s.departureTime);
          return b.difference(a).inSeconds >= 60;
        })
        .toList();
  }

  /// Maps API summary blocks into bottom-sheet stats.
  /// - Distance ← `kilometer_statistics.total_kilometers_traveled`
  /// - Duration ← `vehicle_timing` start/end, then location_history fallback
  void _applyHistorySummaryStats(
    HistoryData? data, {
    Map<String, dynamic>? dataJson,
  }) {
    final km = data?.kilometerStatistics?.totalKilometersTraveled;
    if (km == null) {
      totalDistance.value = '0.00 Km';
    } else {
      totalDistance.value = '${km.toStringAsFixed(2)} Km';
    }

    final timing = data?.vehicleTiming;
    final startRaw = timing?.vehicleStartTime;
    final endRaw = timing?.vehicleEndTime;
    vehicleStartTime.value =
        (startRaw != null && startRaw.trim().isNotEmpty && startRaw != 'null')
            ? startRaw.trim()
            : null;
    vehicleEndTime.value =
        (endRaw != null && endRaw.trim().isNotEmpty && endRaw != 'null')
            ? endRaw.trim()
            : null;

    // 1) Explicit duration field from API (seconds or HH:MM:SS).
    final fromApiDuration = _formatFlexibleDuration(timing?.totalDuration);
    if (fromApiDuration != null) {
      duration.value = fromApiDuration;
      debugPrint('[History] duration from vehicle_timing.total_duration=$fromApiDuration');
      return;
    }

    // 2) Elapsed between vehicle_start_time → vehicle_end_time.
    final fromTiming = _formatVehicleTimingDuration(
      vehicleStartTime.value,
      vehicleEndTime.value,
    );
    if (fromTiming != '00:00:00') {
      duration.value = fromTiming;
      debugPrint(
        '[History] duration from vehicle_timing '
        '${vehicleStartTime.value} → ${vehicleEndTime.value} = $fromTiming',
      );
      return;
    }

    // 3) Fallback: first → last deviceTime in location_history.
    final fromHistory = _durationFromLocationHistory(
      dataJson?['location_history'],
    );
    if (fromHistory != null) {
      duration.value = fromHistory;
      debugPrint(
        '[History] duration fallback from location_history = $fromHistory '
        '(vehicle_timing start/end were null)',
      );
      return;
    }

    duration.value = '00:00:00';
    debugPrint(
      '[History] duration unavailable: vehicle_timing='
      '${dataJson?['vehicle_timing']} location_history empty/missing times',
    );
  }

  /// When timing is still zero after load, use sorted GPS point times.
  void _applyDurationFallbackFromRawPoints(List<Map<String, dynamic>> raw) {
    if (duration.value != '00:00:00') return;
    if (raw.length < 2) return;

    DateTime? minT;
    DateTime? maxT;
    String? firstRaw;
    String? lastRaw;
    for (final point in raw) {
      final t = point['deviceTime']?.toString();
      if (t == null || t.trim().isEmpty || t == 'null') continue;
      final parsed = _parseDeviceTime(t);
      if (parsed.year <= 1970) continue;
      if (minT == null || parsed.isBefore(minT)) {
        minT = parsed;
        firstRaw = t;
      }
      if (maxT == null || parsed.isAfter(maxT)) {
        maxT = parsed;
        lastRaw = t;
      }
    }
    if (firstRaw == null || lastRaw == null) return;

    final formatted = _formatVehicleTimingDuration(firstRaw, lastRaw);
    if (formatted == '00:00:00') return;

    duration.value = formatted;
    vehicleStartTime.value ??= firstRaw.trim();
    vehicleEndTime.value ??= lastRaw.trim();
    debugPrint(
      '[History] duration from raw GPS points $firstRaw → $lastRaw = $formatted',
    );
  }

  String? _durationFromLocationHistory(dynamic raw) {
    if (raw is! List || raw.isEmpty) return null;

    DateTime? minT;
    DateTime? maxT;
    String? firstRaw;
    String? lastRaw;
    for (final item in raw) {
      if (item is! Map) continue;
      final map = Map<String, dynamic>.from(item);
      final t = (map['devicetime'] ??
              map['device_time'] ??
              map['deviceTime'] ??
              map['created_at'])
          ?.toString();
      if (t == null || t.trim().isEmpty || t.toLowerCase() == 'null') continue;
      final parsed = _parseDeviceTime(t);
      if (parsed.year <= 1970) continue;
      if (minT == null || parsed.isBefore(minT)) {
        minT = parsed;
        firstRaw = t;
      }
      if (maxT == null || parsed.isAfter(maxT)) {
        maxT = parsed;
        lastRaw = t;
      }
    }
    if (firstRaw == null || lastRaw == null) return null;

    final formatted = _formatVehicleTimingDuration(firstRaw, lastRaw);
    if (formatted == '00:00:00') return null;

    vehicleStartTime.value ??= firstRaw.trim();
    vehicleEndTime.value ??= lastRaw.trim();
    return formatted;
  }

  /// Accepts seconds (num/string) or already-formatted `HH:MM:SS` / `H h M m`.
  String? _formatFlexibleDuration(String? raw) {
    if (raw == null) return null;
    final text = raw.trim();
    if (text.isEmpty || text.toLowerCase() == 'null') return null;
    if (text.contains(':')) return text;
    final asNum = num.tryParse(text);
    if (asNum == null) return text;
    final totalSeconds = asNum.round().clamp(0, 24 * 3600 * 30);
    final h = (totalSeconds ~/ 3600).toString().padLeft(2, '0');
    final m = ((totalSeconds % 3600) ~/ 60).toString().padLeft(2, '0');
    final s = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  String _formatVehicleTimingDuration(String? startRaw, String? endRaw) {
    if (startRaw == null || endRaw == null) return '00:00:00';
    final start = _parseDeviceTime(startRaw);
    final end = _parseDeviceTime(endRaw);
    if (start.year <= 1970 || end.year <= 1970) return '00:00:00';
    if (end.isBefore(start)) return '00:00:00';
    final totalSeconds = end.difference(start).inSeconds;
    final h = (totalSeconds ~/ 3600).toString().padLeft(2, '0');
    final m = ((totalSeconds % 3600) ~/ 60).toString().padLeft(2, '0');
    final s = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}
