import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';
import '../../../../Configs/ApiConfigs.dart';
import '../../../../Models/LiveTrackModel.dart';
import '../../../../Configs/DioClient.dart';
import '../../../../Utils/Utils.dart';
import '../../../../Services/LiveTrackWebSocketService.dart';
import '../../../../Services/DirectionsService.dart';
import '../../../../widgets/map_widget.dart';
/// Live tracking flow (snapshot once + WebSocket only):
/// 1. User selects vehicle on live track screen (IMEI from route).
/// 2. GET /website/live_track_snapshot?imei= once (Bearer via DioClient).
/// 3. Parse position.lat/lng, websocket.channel/event,
///    websocket_config.websocket_url + app_key.
/// 4. Show map immediately from snapshot position.
/// 5. Connect WebSocket using websocket_config (no Bearer).
/// 6. Subscribe pusher channel (e.g. device.<imei>).
/// 7. Listen for device.update on that channel.
/// 8. On each device.update → update marker (no position API polling).
/// 9. On socket drop → reconnect, resubscribe, optional snapshot catch-up.
/// 10. onClose → disconnect WebSocket.
class TrackController extends GetxController {
  final vehicleImei = ''.obs;
  final vehiclePlate = ''.obs;

  final liveTrackData = Rxn<LiveTrackData>();
  final isLiveLoading = false.obs;

  /// Published to UI (throttled). Glide math uses [_animLat]/[_animLng].
  final animatedLat = 0.0.obs;
  final animatedLng = 0.0.obs;
  final animatedRotation = 0.0.obs;
  final reactiveMarkers = <Marker>[].obs;

  /// High-frequency glide position (does not notify GetX every frame).
  double _animLat = 0.0;
  double _animLng = 0.0;
  /// Smoothed on-screen position (EMA) — kills vibration from snaps/rebuilds.
  double _uiLat = 0.0;
  double _uiLng = 0.0;
  /// Display heading eases toward [_lockedBearing] every frame.
  double _uiHeading = 0.0;
  DateTime? _lastUiSync;
  LatLng? _lastUiSyncPoint;
  final ValueNotifier<double> _headingNotifier = ValueNotifier<double>(0);

  final MapController mapController = MapController();
  final showBottomSheet = true.obs;
  final isLocked = true.obs;

  static const double _followZoom = 18.0;
  bool _userAdjustedZoom = false;
  bool _hasInitialCameraFocus = false;
  double _smoothCameraLat = 0.0;
  double _smoothCameraLng = 0.0;

  /// Streets map by default; user can switch to satellite via the map button.
  final mapStyle = AiroMapStyle.mapboxStreets.obs;

  void toggleMapStyle() {
    mapStyle.value = mapStyle.value == AiroMapStyle.mapboxStreets
        ? AiroMapStyle.mapboxSatellite
        : AiroMapStyle.mapboxStreets;
  }

  bool _isFetchingSnapshot = false;
  bool _disposed = false;

  final LiveTrackWebSocketService _webSocketService = LiveTrackWebSocketService();
  LiveWebsocketConfig? _wsConfig;
  LiveWebsocketInfo? _wsInfo;

  Timer? _animationTimer;
  LatLng? _liveTarget;
  LatLng? _lastAcceptedGps;

  static const double _maxBackwardBearingDeg = 95.0;
  static const double _snapBackMinLagMeters = 4.0;
  static const double _reverseGpsStepMeters = 4.0;
  static const double _maxGlideSpeedMs = 45.0;
  static const double _catchUpMinLagMeters = 10.0;
  static const double _catchUpWindowSec = 4.5;
  static const double _reconnectSnapMeters = 150.0;

  double _expectedPingSec = 6.0;
  double _roadSpeedFactor = 1.0;
  double _targetRoadSpeedFactor = 1.0;
  double _smoothedGlideSpeedMs = 0.0;
  int _routeRequestId = 0;
  DateTime? _lastRoadFetchAt;
  /// True while a Mapbox match/route request is in flight.
  bool _roadFetchInFlight = false;
  /// Latest GPS we still need a road path for (set while a fetch is running).
  LatLng? _pendingRoadTarget;

  /// Road-snapped waypoints the marker animates along (Mapbox only).
  final List<LatLng> _roadQueue = [];
  /// Last Mapbox road geometry (for snap when the live queue drains).
  final List<LatLng> _lastRoadCorridor = [];
  /// Device GPS samples — used ONLY to build Mapbox match/route requests.
  /// Never applied directly to the marker position.
  final List<LatLng> _gpsTrace = [];

  final DirectionsService _directionsService = DirectionsService();

  double _currentSpeedMs = 0.0;
  double _smoothedSpeedMs = 0.0;
  DateTime? _lastMovingTime;
  String _movementMode = '';
  double _lockedBearing = 0.0;
  bool _hasHeading = false;
  DateTime? _lastGlideTime;
  DateTime? _lastGpsTime;
  DateTime? _lastCameraMove;
  /// Ignore map "gestures" caused by our own camera follow moves.
  DateTime? _ignoreMapGestureUntil;
  /// Stable marker child — recreating Image/Obx every frame causes vibration.
  Widget? _vehicleMarkerChild;
  static const int _cameraMoveIntervalMs = 40;
  /// Publish marker every animation tick while moving (~30 fps).
  static const int _uiSyncMinMs = 33;
  static const double _uiSyncMinMeters = 0.08;
  /// Soft continuous chase — higher when camera lags far behind.
  static const double _cameraFollowK = 1.8;
  static const double _cameraCatchUpK = 3.0;
  /// Base max camera travel per follow tick; scales up with speed.
  static const double _maxCameraStepM = 3.5;
  /// Pure EMA toward glide (lower = smoother on-screen motion).
  static const double _uiPosSmoothMoving = 0.11;
  /// Slightly softer when stopped so soft-follow doesn't twitch.
  static const double _uiPosSmoothStopped = 0.09;
  /// Zoom above this starts stronger anti-vibration (close-up view).
  static const double _zoomSmoothStart = 15.0;
  /// Full close-up smoothing by this zoom.
  static const double _zoomSmoothFull = 18.0;
  /// Ignore GPS noise while stopped — prevents marker vibration.
  static const double _stoppedGpsDeadbandM = 8.0;
  /// Slow forward roll while device reports speed 0 (~1.3 km/h).
  static const double _stoppedCreepMs = 0.35;
  /// Max distance past last GPS while stopped (avoids endless park drift).
  static const double _stoppedCreepMaxLeadM = 20.0;
  static const double _minRotationChangeDeg = 24.0;
  static const double _minGpsBearingMoveM = 10.0;
  /// GPS must be within this of travel heading to chase it (else go straight).
  static const double _onCourseMaxDeg = 28.0;
  static const double _frameSeconds = 0.033;
  /// Minimum roll speed between WS pings (~1.8 km/h).
  static const double _wsWaitCreepMinMs = 0.5;
  /// Skip Mapbox for tiny hops; stay on last matched road instead of raw GPS.
  static const double _minRoadRouteMeters = 8.0;
  /// Max locked-bearing step while following road (~deg per frame @30fps).
  static const double _maxRotationStepDeg = 0.9;
  /// Max on-screen heading rate (deg/sec) — stops visual shake.
  static const double _maxUiHeadingDegPerSec = 36.0;
  static const int _gpsTraceMaxPoints = 8;
  /// Soft-correct back onto road when drifting farther than this.
  static const double _maxOffRoadMeters = 4.0;
  /// Hard-snap onto Mapbox geometry if farther than this.
  static const double _hardSnapOnRoadMeters = 12.0;
  /// Speed-up rate (m/s²). Keep lower than old catch-up spikes.
  static const double _maxSpeedAccelMs = 0.55;
  /// Coast-down rate — softer than accel so speed doesn't slam then surge.
  static const double _maxSpeedDecelMs = 0.22;
  /// Floor for per-frame travel; real cap scales with current glide speed.
  static const double _maxStepPerFrameM = 0.85;
  /// Min spacing between road waypoints (reduces left/right zigzag vibration).
  static const double _roadWaypointMinM = 5.0;

  /// Device-reported speed (km/h) from latest WS ping. Stop only when 0.
  double _lastReportedSpeedKmh = 0.0;
  /// GPS-inferred speed (km/h) — keeps roll rate realistic between pings.
  double _lastInferredSpeedKmh = 0.0;
  /// GPS movement on latest ping (m).
  double _lastGpsDeltaM = 0.0;
  /// Latched on each ping — keeps rolling between WS updates until next ping.
  bool _isMovingVehicle = false;

  final fenceNameController = TextEditingController();
  final fenceNameError = RxnString();
  final selectedShareOption = '24h'.obs;
  final isUpdatingOdometer = false.obs;
  /// Light odometer source for UI (avoids rewriting all liveTrackData on update).
  final odometerKm = Rxn<num>();
  /// Pause marker UI sync while an input sheet is open (prevents ANR with IME).
  bool _pauseMarkerUi = false;

  void updateShareOption(String value) => selectedShareOption.value = value;

  void submitFence() {
    if (fenceNameController.text.isEmpty) {
      fenceNameError.value = "Geofence name is required";
      return;
    }
    debugPrint("Submitting geofence: ${fenceNameController.text}");
  }

  @override
  void onInit() {
    super.onInit();
    _disposed = false;
    final imei = Get.parameters['imei'] ?? '';
    final plate = Get.parameters['vehicleId'] ?? '';
    vehicleImei.value = imei;
    vehiclePlate.value = plate;

    if (imei.isNotEmpty) {
      _initAndStartTracking(imei);
    }
    _startAnimationLoop();
  }

  Future<void> _initAndStartTracking(String imei) async {
    final token = await getSavedObject('token');
    if (token != null) DioClient().updateToken(token.toString());
    if (_disposed) return;
    await _fetchLiveTrackSnapshot(imei);
  }

  /// Snapshot once on entry; reconnectOnly skips WebSocket re-setup.
  Future<void> _fetchLiveTrackSnapshot(
    String imei, {
    bool reconnectOnly = false,
  }) async {
    if (_disposed) return;
    if (_isFetchingSnapshot && !reconnectOnly) return;

    try {
      _isFetchingSnapshot = true;
      if (!reconnectOnly) isLiveLoading.value = true;

      final response = await DioClient().get(
        ApiEndPoints.liveTrackSnapshot,
        query: {'imei': imei.trim()},
      );

      final rawBody = response.data;
      if (rawBody is! Map) {
        debugPrint('❌ LiveTrack: invalid snapshot response');
      return;
    }
      final body = Map<String, dynamic>.from(rawBody);

      final snapshot = LiveTrackSnapshotModel.fromJson(body);
      final data = snapshot.data;
      if (data == null) {
        debugPrint('❌ LiveTrack: snapshot missing data');
        return;
      }

      _wsConfig = data.websocketConfig;
      _wsInfo = data.websocket;

      liveTrackData.value = data.toLiveTrackData();
      _syncOdometerKm(liveTrackData.value?.currentPosition?.odometer);
      if (reconnectOnly) {
        final pos = liveTrackData.value?.currentPosition;
        final lat = double.tryParse(pos?.latitude ?? '');
        final lng = double.tryParse(pos?.longitude ?? '');
        if (lat != null && lng != null && _animLat != 0.0) {
          final snap = LatLng(lat, lng);
          final current = LatLng(_animLat, _animLng);
          final lag = _calculateDistance(current, snap);
          if (lag > _reconnectSnapMeters && _isForwardOf(snap, current)) {
            _snapMarkerTo(
              snap,
              pos?.speed?.toDouble() ?? 0.0,
              status: pos?.derivedStatus,
              mode: pos?.mode,
            );
          } else if (lag > 1.0) {
            _onDevicePosition(
              snap,
              pos?.speed?.toDouble() ?? 0.0,
              status: pos?.derivedStatus,
              mode: pos?.mode,
            );
          }
        }
      } else {
        _applyPositionFromData(isInitial: true);
      }

      if (!reconnectOnly) {
        await _webSocketService.disconnect();
        await _connectWebSocket(imei);
      }
    } catch (e) {
      debugPrint('❌ Live track snapshot error: $e');
    } finally {
      _isFetchingSnapshot = false;
      if (!reconnectOnly) isLiveLoading.value = false;
    }
  }

  void _applyPositionFromData({required bool isInitial}) {
    final pos = liveTrackData.value?.currentPosition;
    final lat = double.tryParse(pos?.latitude ?? '');
    final lng = double.tryParse(pos?.longitude ?? '');
    if (lat == null || lng == null || (lat == 0.0 && lng == 0.0)) return;

    final location = LatLng(lat, lng);
    final speed = pos?.speed?.toDouble() ?? 0.0;

    if (isInitial || _animLat == 0.0 || _animLng == 0.0) {
      _setAnimPosition(lat, lng, publish: true);
      _liveTarget = location;
      _lastAcceptedGps = location;
      _lastGpsTime = DateTime.now();
      _lastReportedSpeedKmh = speed;
      _lastInferredSpeedKmh = speed;
      _lastGpsDeltaM = 0;
      _isMovingVehicle = speed > 0;
      _gpsTrace
        ..clear()
        ..add(location);
      _smoothedGlideSpeedMs = speed > 0
          ? (speed / 3.6).clamp(_wsWaitCreepMinMs, _maxGlideSpeedMs)
          : 0.0;
      _updateMovementSpeed(speed, pos?.derivedStatus ?? 'Stopped', mode: pos?.mode);
      // Seed Mapbox route so animation starts on-road, not on raw GPS.
      _requestRoadPath(location, force: true);
      if (!_hasInitialCameraFocus && isLocked.value) {
        _hasInitialCameraFocus = true;
        moveMapToVehicle(snap: true, resetZoom: true);
      }
      return;
    }

    _onDevicePosition(location, speed, status: pos?.derivedStatus, mode: pos?.mode);
  }

  /// Step 4–5: connect using API websocket_config only (Option A).
  Future<void> _connectWebSocket(String imei) async {
    if (_wsConfig == null) {
      debugPrint('❌ LiveTrack: websocket_config missing from API');
      return;
    }

    final snapshot = LiveTrackSnapshotData(
      websocket: _wsInfo,
      websocketConfig: _wsConfig,
    );

    if (!snapshot.hasWebSocketConnectionConfig) {
      debugPrint('❌ LiveTrack: websocket_config.websocket_url or app_key missing');
      return;
    }
    if (snapshot.channelFor(imei) == null) {
      debugPrint(
        '❌ LiveTrack: channel missing (websocket.channel or channel_prefix)',
      );
      return;
    }
    if (snapshot.eventNameFor() == null) {
      debugPrint(
        '❌ LiveTrack: event missing (websocket.event or event_name)',
      );
      return;
    }

    final connected = await _webSocketService.connect(
      imei: imei,
      websocketConfig: _wsConfig,
      websocket: _wsInfo,
      onDeviceUpdate: _handleDeviceUpdate,
      onReconnected: () {
        if (_disposed || vehicleImei.value.isEmpty) return;
        debugPrint('[LiveTrack] WS reconnected — refreshing snapshot');
        _fetchLiveTrackSnapshot(vehicleImei.value, reconnectOnly: true);
      },
    );

    if (!connected) {
      debugPrint('❌ LiveTrack: WebSocket connection setup failed');
    }
  }

  void _handleDeviceUpdate(Map<String, dynamic> data) {
    if (_disposed) return;

    try {
      final coords = _readLatLngFromMap(data);
      if (coords == null) {
        debugPrint('⚠️ LiveTrack: device.update missing lat/lng: $data');
        return;
      }

      final lat = coords.$1;
      final lng = coords.$2;
      final speed = _readSpeedFromMap(data)?.toDouble() ?? 0.0;
      final course = _readCourseFromMap(data);

      final existing = liveTrackData.value;
      final pos = LiveCurrentPosition(
        imei: data['imei']?.toString() ?? vehicleImei.value,
        latitude: lat.toString(),
        longitude: lng.toString(),
        speed: speed,
        deviceTime:
            data['devicetime']?.toString() ?? data['device_time']?.toString(),
        ignition: data['ignition'] is int
            ? data['ignition'] as int
            : int.tryParse(data['ignition']?.toString() ?? ''),
        power: data['power'] is int
            ? data['power'] as int
            : int.tryParse(data['power']?.toString() ?? ''),
        mode: data['mode']?.toString(),
        kilometer: data['kilometer']?.toString() ??
            existing?.currentPosition?.kilometer,
        odometer: data['odometer'] is num
            ? data['odometer'] as num
            : num.tryParse(data['odometer']?.toString() ?? '') ??
                existing?.currentPosition?.odometer,
        altitude: data['altitude']?.toString() ??
            existing?.currentPosition?.altitude,
        gsmSignalStrength: data['gsm_signal_strength']?.toString() ??
            existing?.currentPosition?.gsmSignalStrength ??
            existing?.currentPositionApi?.data?.gsmSignalStrength,
        network: data['network']?.toString() ??
            existing?.currentPosition?.network ??
            existing?.currentPositionApi?.data?.network,
        lastUpdate: data['last_update']?.toString() ??
            existing?.currentPosition?.lastUpdate ??
            existing?.currentPositionApi?.data?.lastUpdate,
      );

      liveTrackData.value = LiveTrackData(
        vehicleInfo: existing?.vehicleInfo,
        currentPosition: pos,
        currentStatus: pos.derivedStatus,
        todayStatistics: existing?.todayStatistics,
        currentPositionApi: existing?.currentPositionApi,
      );
      _syncOdometerKm(pos.odometer);

      _onDevicePosition(
        LatLng(lat, lng),
        speed,
        status: pos.derivedStatus,
        courseDeg: course,
        mode: pos.mode,
      );
    } catch (e, st) {
      debugPrint('⚠️ LiveTrack device update error: $e\n$st');
    }
  }

  void _onDevicePosition(
    LatLng location,
    double speedKmH, {
    String? status,
    double? courseDeg,
    String? mode,
  }) {
    final now = DateTime.now();
    final previousGps = _lastAcceptedGps;
    final previousGpsTime = _lastGpsTime;

    final reportedKmH = speedKmH;
    speedKmH = _inferSpeedKmh(location, speedKmH, now);
    _lastReportedSpeedKmh = reportedKmH;
    _lastInferredSpeedKmh = speedKmH;
    if (mode != null) _movementMode = mode;

    var gpsDeltaM = 0.0;
    if (previousGps != null) {
      gpsDeltaM = _calculateDistance(previousGps, location);
    }
    _lastGpsDeltaM = gpsDeltaM;

    // Device-reported speed gates "live tracking" vs "stopped crawl".
    // GPS jitter alone must not flip into full chase (that caused vibration).
    if (reportedKmH <= 0) {
      _isMovingVehicle = false;
    } else {
      _isMovingVehicle = true;
    }

    _updateMovementSpeed(
      _isMovingVehicle ? math.max(speedKmH, reportedKmH) : 0,
      status ?? 'Stopped',
      mode: mode,
    );

    // Device GPS never moves the marker directly — it only updates the
    // Mapbox route target. Animation walks the returned road geometry.
    if (!_isMovingVehicle) {
      _smoothedGlideSpeedMs = 0.0;
      if (previousGps != null && gpsDeltaM < _stoppedGpsDeadbandM) {
        _lastGpsTime = now;
        return;
      }
      if (previousGpsTime != null) {
        final interval =
            now.difference(previousGpsTime).inMilliseconds / 1000.0;
        if (interval >= 0.8 && interval < 60.0) {
          _expectedPingSec = _expectedPingSec * 0.65 + interval * 0.35;
        }
      }
      if (!_hasHeading &&
          courseDeg != null &&
          courseDeg >= 0 &&
          courseDeg <= 360) {
        _setLockedBearing(courseDeg % 360);
      }
      _lastAcceptedGps = location;
      _lastGpsTime = now;
      _liveTarget = location;
      // Snap park pose onto the road network (still via Mapbox, not raw GPS).
      _requestRoadPath(location, force: true);
      return;
    }

    if (previousGps != null) {
      if (previousGpsTime != null) {
        final interval =
            now.difference(previousGpsTime).inMilliseconds / 1000.0;
        if (interval >= 0.8 && interval < 60.0) {
          _expectedPingSec = _expectedPingSec * 0.65 + interval * 0.35;
        }
      }
      if (_isLikelySnapBack(location, previousGps)) {
        _lastGpsTime = now;
        return;
      }
    }

    _updateHeadingFromMovement(
      location,
      previousGps: previousGps,
      courseDeg: courseDeg,
    );

    _lastAcceptedGps = location;
    _lastGpsTime = now;
    _liveTarget = location;
    _smoothedGlideSpeedMs = math.max(
      _smoothedGlideSpeedMs,
      _wsWaitCreepMinMs,
    );

    // Build / refresh Mapbox road route — marker animates along that only.
    // Don't force-cancel in-flight Mapbox calls on every ping (that froze the car).
    _requestRoadPath(location, force: _roadQueue.length < 2);
  }

  void _snapMarkerTo(
    LatLng location,
    double speedKmH, {
    String? status,
    String? mode,
  }) {
    _setAnimPosition(location.latitude, location.longitude, publish: true);
    _liveTarget = location;
    _lastAcceptedGps = location;
    _lastGpsTime = DateTime.now();
    _lastReportedSpeedKmh = speedKmH;
    _lastInferredSpeedKmh = speedKmH;
    _isMovingVehicle = speedKmH > 0;
    _roadQueue.clear();
    _gpsTrace.clear();
    _updateMovementSpeed(speedKmH, status ?? 'Stopped', mode: mode);
    // Resolve onto the road network before animating.
    _requestRoadPath(location, force: true);
    if (isLocked.value) _maybeMoveCameraToVehicle();
  }

  void _setAnimPosition(double lat, double lng, {bool publish = false}) {
    _animLat = lat;
    _animLng = lng;
    if (_uiLat == 0.0 && _uiLng == 0.0) {
      _uiLat = lat;
      _uiLng = lng;
    }
    if (publish) {
      _smoothUiPosition(snap: true);
      _publishAnim(force: true);
    }
  }

  /// Push glide position to GetX / map marker at a capped rate.
  void _publishAnim({bool force = false}) {
    if (_animLat == 0.0 && _animLng == 0.0) return;
    if (_pauseMarkerUi && !force) return;

    final point = LatLng(_uiLat != 0.0 ? _uiLat : _animLat,
        _uiLng != 0.0 ? _uiLng : _animLng);
    final now = DateTime.now();
    if (!force && _lastUiSyncPoint != null && _lastUiSync != null) {
      final dtMs = now.difference(_lastUiSync!).inMilliseconds;
      final moved = _calculateDistance(_lastUiSyncPoint!, point);
      // At high zoom, skip sub-pixel marker moves (they read as vibration).
      final minMoveM = _minMarkerMoveMeters();
      if (_isMovingVehicle) {
        if (dtMs < _uiSyncMinMs && moved < minMoveM) return;
        if (moved < minMoveM * 0.55 && dtMs < 90) return;
      } else {
        if (dtMs < _uiSyncMinMs) return;
        if (moved < minMoveM && dtMs < 300) return;
      }
    }

    _lastUiSync = now;
    _lastUiSyncPoint = point;
    animatedLat.value = point.latitude;
    animatedLng.value = point.longitude;
    _syncMarkerPosition();
  }

  /// ~0.6–1 px in meters at the current zoom — larger gate when zoomed in.
  double _minMarkerMoveMeters() {
    final mpp = _metersPerPixel();
    final zoomFactor = _zoomSmoothFactor();
    return math.max(_uiSyncMinMeters, mpp * (0.7 + zoomFactor * 0.6));
  }

  double _readMapZoom() {
    try {
      return mapController.camera.zoom;
    } catch (_) {
      return _followZoom;
    }
  }

  /// 0 at normal zoom, 1 when heavily zoomed in on the car.
  double _zoomSmoothFactor() {
    final z = _readMapZoom();
    if (z <= _zoomSmoothStart) return 0.0;
    if (z >= _zoomSmoothFull) return 1.0;
    return (z - _zoomSmoothStart) / (_zoomSmoothFull - _zoomSmoothStart);
  }

  double _metersPerPixel() {
    final lat = _uiLat != 0.0
        ? _uiLat
        : (_animLat != 0.0 ? _animLat : 0.0);
    final zoom = _readMapZoom();
    return 156543.03392 *
        math.cos(lat * math.pi / 180.0) /
        math.pow(2.0, zoom);
  }

  void _smoothUiPosition({bool snap = false}) {
    if (_animLat == 0.0 && _animLng == 0.0) return;
    if (snap || (_uiLat == 0.0 && _uiLng == 0.0)) {
      _uiLat = _animLat;
      _uiLng = _animLng;
      return;
    }

    final speedKmh =
        math.max(_lastReportedSpeedKmh, _lastInferredSpeedKmh).clamp(0.0, 140.0);
    final speedLift = (speedKmh / 100.0).clamp(0.0, 1.0) * 0.10;
    final zoomF = _zoomSmoothFactor();

    // Zoomed in → much softer EMA so meter noise isn't visible as shake.
    var alpha = _isMovingVehicle
        ? (_uiPosSmoothMoving + speedLift).clamp(0.08, 0.22)
        : _uiPosSmoothStopped;
    alpha *= (1.0 - zoomF * 0.70);
    alpha = alpha.clamp(0.035, 0.22);

    var nextLat = _uiLat + (_animLat - _uiLat) * alpha;
    var nextLng = _uiLng + (_animLng - _uiLng) * alpha;

    // Close-up: keep motion along the road heading; kill sideways / reverse
    // micro-wobble that looks like vibration when zoomed.
    if (zoomF > 0.15 && _hasHeading) {
      final from = LatLng(_uiLat, _uiLng);
      final candidate = LatLng(nextLat, nextLng);
      final dist = _calculateDistance(from, candidate);
      if (dist > 0.005) {
        final moveBearing = _getBearing(from, candidate);
        final errDeg = _shortestBearingDelta(_lockedBearing, moveBearing);
        final errRad = errDeg * math.pi / 180.0;
        var along = dist * math.cos(errRad);
        var lateral = dist * math.sin(errRad);

        if (along < 0) {
          along *= (1.0 - zoomF * 0.85);
        }
        lateral *= (1.0 - zoomF * 0.92);

        var pos = _offsetMeters(from, _lockedBearing, along);
        if (lateral.abs() > 0.001) {
          pos = _offsetMeters(pos, _lockedBearing + 90.0, lateral);
        }
        nextLat = pos.latitude;
        nextLng = pos.longitude;
      }
    }

    _uiLat = nextLat;
    _uiLng = nextLng;
  }

  /// Ease visible heading toward travel bearing every frame (no rotation snaps).
  void _smoothUiHeading(double dt) {
    if (!_hasHeading) return;
    if (_uiHeading == 0.0 && _headingNotifier.value != 0.0) {
      _uiHeading = _headingNotifier.value;
    }

    final zoomF = _zoomSmoothFactor();
    final delta = _shortestBearingDelta(_uiHeading, _lockedBearing);
    // Slower heading at high zoom so the icon doesn't flicker while close-up.
    final maxStep = _maxUiHeadingDegPerSec * (1.0 - zoomF * 0.45) * dt;
    final step = delta.clamp(-maxStep, maxStep);
    if (step.abs() < 0.08 + zoomF * 0.15) return;

    _uiHeading = _normalizeBearing(_uiHeading + step);
    if ((_headingNotifier.value - _uiHeading).abs() >= 0.25 ||
        _shortestBearingDelta(_headingNotifier.value, _uiHeading).abs() >=
            0.25) {
      _headingNotifier.value = _uiHeading;
    }
  }

  void setInputSheetOpen(bool open) {
    _pauseMarkerUi = open;
    if (open) {
      // Fully stop glide while IME/sheet is open — timer+rebuild was ANRing.
      _animationTimer?.cancel();
      _animationTimer = null;
      return;
    }
    if (!_disposed) {
      _startAnimationLoop();
      Future<void>.delayed(const Duration(milliseconds: 150), () {
        if (!_disposed && !_pauseMarkerUi) {
          _publishAnim(force: true);
        }
      });
    }
  }

  void applyOdometerLocal(num value) {
    odometerKm.value = value;
  }

  void clearOdometerUpdating() {
    if (isUpdatingOdometer.value) {
      isUpdatingOdometer.value = false;
    }
  }

  void _syncOdometerKm(num? value) {
    if (value == null) return;
    if (odometerKm.value == value) return;
    odometerKm.value = value;
  }

  /// Feed latest device GPS into Mapbox Matching / Directions.
  /// Resulting road polyline is what the marker animates along — never the
  /// raw GPS coordinate itself.
  void _requestRoadPath(LatLng to, {bool force = false}) {
    _pushGpsTrace(to);
    _pendingRoadTarget = to;

    if (_animLat == 0.0 && _animLng == 0.0) return;

    // One Mapbox call at a time — remember the newest target and refetch after.
    if (_roadFetchInFlight) {
      return;
    }

    final now = DateTime.now();
    final queueEmpty = _roadQueue.length < 2;
    final minGapMs = queueEmpty ? 300 : 800;
    if (!force &&
        !queueEmpty &&
        _lastRoadFetchAt != null &&
        now.difference(_lastRoadFetchAt!).inMilliseconds < minGapMs) {
      return;
    }

    final from = LatLng(_animLat, _animLng);
    final straightM = _calculateDistance(from, to);

    // Need meaningful separation before asking Mapbox again.
    // Tiny hops (1–7 m) cause route flicker and jerky animation.
    if (straightM < _minRoadRouteMeters) {
      _targetRoadSpeedFactor = 1.0;
      return;
    }
    if (!queueEmpty && straightM < 15.0 && _remainingPathMeters(from) > 20.0) {
      _targetRoadSpeedFactor = 1.0;
      return;
    }

    // Avoid reverse Directions loops when GPS lags behind the animated car.
    if (_hasHeading && _isBehind(from, to) && straightM < 50.0) {
      _targetRoadSpeedFactor = 1.0;
      return;
    }

    _lastRoadFetchAt = now;
    _roadFetchInFlight = true;
    final requestId = ++_routeRequestId;
    final fromPt = from;
    final toPt = to;
    final traceCopy = <LatLng>[..._gpsTrace];

    () async {
      try {
        List<LatLng> road = const [];

        // Prefer Directions car→GPS (reliable when marker already on-road).
        road = await _directionsService.getRoute(fromPt, toPt, smooth: false);

        // Fall back to Map Matching on the GPS trace.
        if (road.length < 2 && traceCopy.length >= 2) {
          road = await _directionsService.matchTrace(
            traceCopy,
            radiusMeters: 25,
          );
        }

      if (_disposed) return;
        // Ignore only if a newer fetch already started AND we already have a path.
        if (requestId != _routeRequestId && _roadQueue.length >= 2) return;
        if (road.length < 2) {
          debugPrint(
            '[LiveTrack] Mapbox returned no road '
            '(from→to ${straightM.toStringAsFixed(1)}m)',
          );
          return;
        }

        var routeLenM = 0.0;
        for (var i = 1; i < road.length; i++) {
          routeLenM += _calculateDistance(road[i - 1], road[i]);
        }

        // Reject absurd detours (e.g. 90+ pts for a few meters of GPS).
        if (straightM > 0.5 && routeLenM > straightM * 4.5 && routeLenM > 40.0) {
          debugPrint(
            '[LiveTrack] Mapbox detour ignored '
            'road=${routeLenM.toStringAsFixed(0)}m vs straight=${straightM.toStringAsFixed(0)}m',
          );
          return;
        }

        debugPrint(
          '[LiveTrack] Mapbox road ok pts=${road.length} '
          'road=${routeLenM.toStringAsFixed(0)}m straight=${straightM.toStringAsFixed(0)}m',
        );

        if (straightM > 1.0) {
          _targetRoadSpeedFactor = (routeLenM / straightM).clamp(1.0, 1.45);
        }

        _lastRoadCorridor
          ..clear()
          ..addAll(road);

    // Snap animated pose onto Mapbox geometry softly (not onto raw GPS).
        final current = LatLng(_animLat, _animLng);
        final onRoad = _closestPointOnPolyline(current, road);
        final lateral = _calculateDistance(current, onRoad);
        if (lateral > 2.5) {
          final blend = lateral > _hardSnapOnRoadMeters ? 0.2 : 0.1;
          _animLat =
              current.latitude + (onRoad.latitude - current.latitude) * blend;
          _animLng =
              current.longitude + (onRoad.longitude - current.longitude) * blend;
        }

        var remaining = _trimRouteAhead(
          LatLng(_animLat, _animLng),
          road,
        );
        if (remaining.length < 2) {
          // Car already near end — still keep a short tail so we can ease.
          remaining = _decimatePath(road, _roadWaypointMinM);
        }
        remaining = _orientPathWithTravel(remaining);
        remaining = _decimatePath(remaining, _roadWaypointMinM);
        final trimmed = _trimRouteToUpdate(remaining, toPt);
        if (trimmed.length >= 2) {
          remaining = trimmed;
        }
        if (remaining.length < 2) return;
        _applyRoadQueueSmoothly(remaining);
      } catch (e) {
        debugPrint('[LiveTrack] Mapbox road path failed: $e');
      } finally {
        _roadFetchInFlight = false;
        // Refetch if a newer GPS arrived while we were waiting.
        final pending = _pendingRoadTarget;
        if (!_disposed &&
            pending != null &&
            _calculateDistance(pending, toPt) > _minRoadRouteMeters) {
          _requestRoadPath(pending, force: _roadQueue.length < 2);
        }
      }
    }();
  }

  /// Replace or extend the road queue without teleporting the marker.
  void _applyRoadQueueSmoothly(List<LatLng> remaining) {
    if (remaining.length < 2) return;

    final current = LatLng(_animLat, _animLng);
    final newStartDist = _calculateDistance(current, remaining.first);
    final remainingNow = _remainingPathMeters(current);
    final newLen = _pathLengthMeters(remaining);

    // Already gliding on a good path — ignore tiny replacement routes
    // (1–6 m hops) that yank the car every ping.
    if (_roadQueue.length >= 3 &&
        remainingNow > 18.0 &&
        newLen < 15.0) {
      return;
    }

    // Keep gliding on the existing queue if it still has room and the new
    // path start is far from us (stale/mis-trimmed result).
    if (_roadQueue.length >= 4 &&
        remainingNow > 25.0 &&
        newStartDist > 12.0) {
      return;
    }

    // Soft merge: keep a short lead of the current path, append new tail.
    if (_roadQueue.length >= 3 &&
        newStartDist < 12.0 &&
        _calculateDistance(_roadQueue.first, remaining.first) < 8.0) {
      final merged = <LatLng>[_roadQueue[0], _roadQueue[1]];
      for (final p in remaining.skip(1)) {
        if (_calculateDistance(merged.last, p) >= 2.0) {
          merged.add(p);
        }
      }
      if (merged.length >= 2) {
        _roadQueue
          ..clear()
          ..addAll(merged);
        return;
      }
    }

    if (_roadQueue.length >= 2 && newStartDist < 12.0) {
      _roadQueue
        ..clear()
        ..addAll(remaining);
      return;
    }

    // Far from new path start — only adopt if we have almost nothing left.
    if (_roadQueue.length >= 2 && remainingNow > 12.0) {
      return;
    }

    _roadQueue
      ..clear()
      ..addAll(remaining);
  }

  double _pathLengthMeters(List<LatLng> path) {
    if (path.length < 2) return 0.0;
    var total = 0.0;
    for (var i = 1; i < path.length; i++) {
      total += _calculateDistance(path[i - 1], path[i]);
    }
    return total;
  }

  /// Drop dense Map Matching vertices that cause left/right vibration.
  List<LatLng> _decimatePath(List<LatLng> path, double minMeters) {
    if (path.length <= 2) return path;
    final out = <LatLng>[path.first];
    for (var i = 1; i < path.length - 1; i++) {
      if (_calculateDistance(out.last, path[i]) >= minMeters) {
        out.add(path[i]);
      }
    }
    if (_calculateDistance(out.last, path.last) >= 1.0 || out.length < 2) {
      out.add(path.last);
    } else {
      out[out.length - 1] = path.last;
    }
    return out;
  }

  /// Keep road geometry only up to the latest GPS (projected on the route).
  List<LatLng> _trimRouteToUpdate(List<LatLng> path, LatLng update) {
    if (path.length < 2) return path;

    var bestIdx = 0;
    var bestDist = double.infinity;
    for (var i = 0; i < path.length; i++) {
      final d = _calculateDistance(path[i], update);
      if (d < bestDist) {
        bestDist = d;
        bestIdx = i;
      }
    }

    final onSeg = bestIdx < path.length - 1
        ? _projectOnSegment(update, path[bestIdx], path[bestIdx + 1])
        : (bestIdx > 0
            ? _projectOnSegment(update, path[bestIdx - 1], path[bestIdx])
            : path[bestIdx]);

    final out = <LatLng>[];
    final endIdx =
        bestIdx < path.length - 1 ? bestIdx : math.max(0, bestIdx - 1);
    for (var i = 0; i <= endIdx; i++) {
      out.add(path[i]);
    }
    if (out.isEmpty || _calculateDistance(out.last, onSeg) >= 0.5) {
      out.add(onSeg);
    } else {
      out[out.length - 1] = onSeg;
    }
    return out.length >= 2 ? out : path;
  }

  void _pushGpsTrace(LatLng point) {
    if (_gpsTrace.isNotEmpty &&
        _calculateDistance(_gpsTrace.last, point) < 1.5) {
      _gpsTrace[_gpsTrace.length - 1] = point;
      return;
    }
    _gpsTrace.add(point);
    while (_gpsTrace.length > _gpsTraceMaxPoints) {
      _gpsTrace.removeAt(0);
    }
  }

  /// If [path] runs opposite recent GPS / heading, return it reversed.
  List<LatLng> _orientPathWithTravel(List<LatLng> path) {
    if (path.length < 2) return path;

    final pathBearing = _pathBearingOverMeters(path, 30.0);
    if (pathBearing == null) return path;

    double? travelBearing;
    if (_gpsTrace.length >= 2) {
      final prev = _gpsTrace[_gpsTrace.length - 2];
      final curr = _gpsTrace.last;
      if (_calculateDistance(prev, curr) >= 5.0) {
        travelBearing = _getBearing(prev, curr);
      }
    }
    travelBearing ??= _hasHeading ? _lockedBearing : null;
    if (travelBearing == null) return path;

    final vsTravel =
        _shortestBearingDelta(travelBearing, pathBearing).abs();
    if (vsTravel <= 100.0) return path;

    final reversed = path.reversed.toList();
    final revBearing = _pathBearingOverMeters(reversed, 30.0);
    if (revBearing == null) return path;

    final vsRev =
        _shortestBearingDelta(travelBearing, revBearing).abs();
    // Only flip when reversed clearly matches travel better.
    if (vsRev + 25.0 < vsTravel) {
      return _trimRouteAhead(LatLng(_animLat, _animLng), reversed);
    }
    return path;
  }

  /// Bearing along [path] after traveling about [meters] from the start.
  double? _pathBearingOverMeters(List<LatLng> path, double meters) {
    if (path.length < 2) return null;
    var traveled = 0.0;
    var i = 1;
    while (i < path.length && traveled < meters) {
      traveled += _calculateDistance(path[i - 1], path[i]);
      i++;
    }
    final end = path[math.min(i - 1, path.length - 1)];
    if (_calculateDistance(path.first, end) < 2.0) {
      return _getBearing(path[path.length - 2], path.last);
    }
    return _getBearing(path.first, end);
  }

  /// Closest vertex (or interpolated segment point) on [poly] to [p].
  LatLng _closestPointOnPolyline(LatLng p, List<LatLng> poly) {
    if (poly.isEmpty) return p;
    if (poly.length == 1) return poly.first;

    var best = poly.first;
    var bestDist = _calculateDistance(p, best);

    for (var i = 0; i < poly.length - 1; i++) {
      final a = poly[i];
      final b = poly[i + 1];
      final projected = _projectOnSegment(p, a, b);
      final d = _calculateDistance(p, projected);
      if (d < bestDist) {
        bestDist = d;
        best = projected;
      }
    }
    return best;
  }

  LatLng _projectOnSegment(LatLng p, LatLng a, LatLng b) {
    final ax = a.longitude;
    final ay = a.latitude;
    final bx = b.longitude;
    final by = b.latitude;
    final px = p.longitude;
    final py = p.latitude;
    final dx = bx - ax;
    final dy = by - ay;
    if (dx == 0 && dy == 0) return a;
    final t = (((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy))
        .clamp(0.0, 1.0);
    return LatLng(ay + dy * t, ax + dx * t);
  }

  /// Keep only the portion of [route] still ahead of [from].
  List<LatLng> _trimRouteAhead(LatLng from, List<LatLng> route) {
    if (route.isEmpty) return route;

    var closestIdx = 0;
    var closestDist = double.infinity;
    for (var i = 0; i < route.length; i++) {
      final d = _calculateDistance(from, route[i]);
      if (d < closestDist) {
        closestDist = d;
        closestIdx = i;
      }
    }

    var start = closestIdx;
    if (closestDist < 3.0 && closestIdx + 1 < route.length) {
      start = closestIdx + 1;
    }

    final out = <LatLng>[];
    // Start exactly on the road at the projection of [from].
    if (closestIdx < route.length - 1) {
      final projected = _projectOnSegment(
        from,
        route[closestIdx],
        route[math.min(closestIdx + 1, route.length - 1)],
      );
      out.add(projected);
      start = closestIdx + 1;
    }

    for (var i = start; i < route.length; i++) {
      if (out.isEmpty || _calculateDistance(out.last, route[i]) >= 0.6) {
        out.add(route[i]);
      }
    }
    return out;
  }

  bool _shouldKeepMoving() => _isMovingVehicle;

  double _distanceToLiveGps(LatLng current) {
    if (_liveTarget == null) return double.infinity;
    return _calculateDistance(current, _liveTarget!);
  }

  /// Remaining meters along the road queue (falls back to straight GPS distance).
  double _remainingPathMeters(LatLng current) {
    if (_roadQueue.isEmpty) return _distanceToLiveGps(current);

    var total = _calculateDistance(current, _roadQueue.first);
    for (var i = 1; i < _roadQueue.length; i++) {
      total += _calculateDistance(_roadQueue[i - 1], _roadQueue[i]);
    }
    return total;
  }

  double _resolveTravelBearing(LatLng current) {
    if (_roadQueue.isNotEmpty) {
      return _getBearing(current, _roadQueue.first);
    }
    if (_hasHeading) return _lockedBearing;
    if (_liveTarget != null) {
      final bearing = _getBearing(current, _liveTarget!);
      _lockedBearing = bearing;
      _hasHeading = true;
      return bearing;
    }
    return _lockedBearing;
  }

  /// Single continuous speed — catch-up when behind, roll when at GPS dot.
  double _continuousSpeedMs(double distAlongPath) {
    if (!_isMovingVehicle) return 0;

    var ms = _effectiveSpeedMs();
    if (ms < _wsWaitCreepMinMs) {
      ms = math.max(
        math.max(_lastReportedSpeedKmh, _lastInferredSpeedKmh),
        3.0,
      ) / 3.6;
    }

    // Soft additive catch-up — keep it gentle for a steady glide.
    if (distAlongPath > _catchUpMinLagMeters) {
      final needed =
          distAlongPath / math.max(_expectedPingSec, _catchUpWindowSec * 0.85);
      final gap = (needed - ms).clamp(0.0, 3.5);
      ms += gap * 0.18;
    }

    return (ms * _roadSpeedFactor).clamp(_wsWaitCreepMinMs, _maxGlideSpeedMs);
  }

  /// Animate along the Mapbox road queue. If Mapbox is still loading, ease
  /// toward the latest update along travel heading (capped) so the car
  /// never freezes waiting on the network.
  void _advanceMarkerContinuously({
    required LatLng current,
    required LatLng gpsTarget,
    required double bearing,
    required double step,
    required double distToGps,
  }) {
    if (step <= 0) return;

    if (_roadQueue.isNotEmpty) {
      _advanceAlongRoad(current, step);
      return;
    }

    // Waiting for Mapbox: stay near last road and keep requesting a path.
    _snapOntoKnownRoad(hard: false);
    if (_liveTarget != null) {
      _requestRoadPath(_liveTarget!, force: false);
    }

    // Soft bridge so movement continues while Mapbox is in flight / delayed.
    if (distToGps <= _minRoadRouteMeters) return;
    if (_isBehind(current, gpsTarget)) return;
    final travelBearing = _hasHeading ? bearing : _getBearing(current, gpsTarget);
    final bridgeStep = math.min(step, distToGps);
    final next = _offsetMeters(current, travelBearing, bridgeStep);
    if (_calculateDistance(next, gpsTarget) > distToGps + 0.5) return;
    _animLat = next.latitude;
    _animLng = next.longitude;
  }

  void _advanceAlongRoad(LatLng current, double step) {
    if (_roadQueue.length >= 2) {
      final onRoad = _closestPointOnPolyline(current, _roadQueue);
      final drift = _calculateDistance(current, onRoad);
      if (drift > _maxOffRoadMeters) {
        // Soft pull only — hard snaps feel like vibration.
        final blend = drift >= _hardSnapOnRoadMeters ? 0.22 : 0.12;
        current = LatLng(
          current.latitude + (onRoad.latitude - current.latitude) * blend,
          current.longitude + (onRoad.longitude - current.longitude) * blend,
        );
        _animLat = current.latitude;
        _animLng = current.longitude;
      }
    }

    var remaining = step;
    var pos = current;

    while (remaining > 0.01 && _roadQueue.isNotEmpty) {
      final next = _roadQueue.first;
      final dist = _calculateDistance(pos, next);
      if (dist < 1.2) {
        _roadQueue.removeAt(0);
        continue;
      }

      final segmentBearing = _getBearing(pos, next);
      _easeRotationToward(segmentBearing);

      if (dist <= remaining) {
        pos = next;
        remaining -= dist;
        _roadQueue.removeAt(0);
      } else {
        final fraction = remaining / dist;
        pos = LatLng(
          pos.latitude + (next.latitude - pos.latitude) * fraction,
          pos.longitude + (next.longitude - pos.longitude) * fraction,
        );
        remaining = 0;
      }
    }

    _animLat = pos.latitude;
    _animLng = pos.longitude;
  }

  void _snapOntoKnownRoad({required bool hard}) {
    final poly = _roadQueue.length >= 2
        ? _roadQueue
        : (_lastRoadCorridor.length >= 2 ? _lastRoadCorridor : null);
    if (poly == null) return;

    final current = LatLng(_animLat, _animLng);
    if (current.latitude == 0.0 && current.longitude == 0.0) return;

    final onRoad = _closestPointOnPolyline(current, poly);
    final drift = _calculateDistance(current, onRoad);
    if (drift < 0.7) return;

    if (hard || drift >= _hardSnapOnRoadMeters) {
      _animLat = onRoad.latitude;
      _animLng = onRoad.longitude;
      return;
    }

    final blend = 0.35;
    _animLat = current.latitude + (onRoad.latitude - current.latitude) * blend;
    _animLng =
        current.longitude + (onRoad.longitude - current.longitude) * blend;
  }

  void _easeRotationToward(double bearing) {
    bearing = _normalizeBearing(bearing);
    if (!_hasHeading) {
      _lockedBearing = bearing;
      _uiHeading = bearing;
      _headingNotifier.value = bearing;
      animatedRotation.value = bearing;
      _hasHeading = true;
      return;
    }

    final delta = _shortestBearingDelta(_lockedBearing, bearing);
    if (delta.abs() < 2.0) return;

    final step = delta.clamp(-_maxRotationStepDeg, _maxRotationStepDeg);
    _lockedBearing = _normalizeBearing(_lockedBearing + step);
    animatedRotation.value = _lockedBearing;
  }

  LatLng _offsetMeters(LatLng from, double bearingDeg, double meters) {
    const metersPerLat = 111320.0;
    final latRad = from.latitude * math.pi / 180;
    final metersPerLng = 111320.0 * math.cos(latRad);
    final rad = bearingDeg * math.pi / 180;
    return LatLng(
      from.latitude + (meters * math.cos(rad)) / metersPerLat,
      from.longitude + (meters * math.sin(rad)) / metersPerLng,
    );
  }

  void _updateHeadingFromMovement(
    LatLng location, {
    LatLng? previousGps,
    double? courseDeg,
  }) {
    double? movementBearing;
    double movedM = 0.0;
    if (previousGps != null) {
      movedM = _calculateDistance(previousGps, location);
      if (movedM >= _minGpsBearingMoveM) {
        movementBearing = _getBearing(previousGps, location);
      }
    }
    if (movementBearing == null && _animLat != 0.0) {
      final current = LatLng(_animLat, _animLng);
      movedM = _calculateDistance(current, location);
      // Prefer GPS→GPS over marker→GPS so park-creep lead doesn't invent a bend.
      if (movedM >= _minGpsBearingMoveM * 1.5) {
        movementBearing = _getBearing(current, location);
      }
    }

    if (movementBearing != null) {
      // Ignore wild heading flips from a single noisy ping unless the step is large.
      if (_hasHeading) {
        final flip =
            _shortestBearingDelta(_lockedBearing, movementBearing).abs();
        if (flip > 55.0 && movedM < 25.0) {
          return;
        }
      }
      _setLockedBearing(movementBearing);
      return;
    }

    // On first move, prefer device course over waiting for a noisy GPS delta.
    if (!_hasHeading &&
        courseDeg != null &&
        courseDeg >= 0 &&
        courseDeg <= 360) {
      _setLockedBearing(courseDeg % 360);
    }
  }

  void _setLockedBearing(double bearing) {
    bearing = _normalizeBearing(bearing);
    if (!_hasHeading) {
      _lockedBearing = bearing;
      _uiHeading = bearing;
      _headingNotifier.value = bearing;
      animatedRotation.value = bearing;
      _hasHeading = true;
      return;
    }

    final diff = _shortestBearingDelta(_lockedBearing, bearing).abs();
    // Small GPS zigzags must not rotate the car / dead-reckon path.
    if (diff >= _minRotationChangeDeg) {
      // Ease large turns instead of snapping (reduces bend on start/turn).
      final eased = diff > 50.0
          ? _normalizeBearing(
              _lockedBearing + _shortestBearingDelta(_lockedBearing, bearing) * 0.35,
            )
          : bearing;
      _lockedBearing = eased;
      animatedRotation.value = eased;
    }
  }

  /// True when [point] is generally ahead of [origin] along travel heading.
  bool _isForwardOf(LatLng point, LatLng origin) {
    if (!_hasHeading) return true;
    final bearing = _getBearing(origin, point);
    final diff = _shortestBearingDelta(_lockedBearing, bearing);
    return diff.abs() <= _maxBackwardBearingDeg;
  }

  bool _isBehind(LatLng current, LatLng point) {
    if (!_hasHeading) return false;
    final bearing = _getBearing(current, point);
    final diff = _shortestBearingDelta(_lockedBearing, bearing);
    return diff.abs() > _maxBackwardBearingDeg;
  }

  /// Stale GPS that would pull the marker backward after we've already glided ahead.
  /// Does not block genuine reverse — only lag/jitter behind the animated position.
  bool _isLikelySnapBack(LatLng location, LatLng previousGps) {
    if (!_hasHeading || _animLat == 0.0) return false;

    final animated = LatLng(_animLat, _animLng);
    if (!_isBehind(animated, location)) return false;

    final lagM = _calculateDistance(animated, location);
    if (lagM < _snapBackMinLagMeters) return false;

    final gpsStepM = _calculateDistance(previousGps, location);
    if (gpsStepM < 1.0) return true;

    final gpsMovingBackward =
        !_isForwardOf(location, previousGps) && gpsStepM >= _reverseGpsStepMeters;
    return !gpsMovingBackward;
  }

  double _shortestBearingDelta(double from, double to) {
    return ((to - from + 540) % 360) - 180;
  }

  double _inferSpeedKmh(LatLng location, double reportedKmh, DateTime now) {
    if (_lastAcceptedGps == null || _lastGpsTime == null) return reportedKmh;

    final deltaM = _calculateDistance(_lastAcceptedGps!, location);
    if (deltaM < 1.0) return reportedKmh;

    final seconds = now.difference(_lastGpsTime!).inMilliseconds / 1000.0;
    if (seconds <= 0) return reportedKmh;

    final inferred = (deltaM / seconds) * 3.6;
    return math.max(reportedKmh, inferred);
  }

  double _effectiveSpeedMs() {
    if (_currentSpeedMs >= 0.3) return _currentSpeedMs;
    if (_smoothedSpeedMs < 0.3 || _lastMovingTime == null) return _currentSpeedMs;

    final since =
        DateTime.now().difference(_lastMovingTime!).inMilliseconds / 1000.0;
    if (since > 25.0) return _currentSpeedMs;

    final decay = (1.0 - since / 15.0).clamp(0.0, 1.0);
    return math.max(_currentSpeedMs, _smoothedSpeedMs * decay);
  }

  void _glideTowardTarget() {
    if (_animLat == 0.0 && _animLng == 0.0) return;

    final now = DateTime.now();
    final dtSec = _lastGlideTime == null
        ? _frameSeconds
        : now.difference(_lastGlideTime!).inMicroseconds / 1000000.0;
    _lastGlideTime = now;
    final dt = dtSec.clamp(0.016, 0.08);

    _roadSpeedFactor +=
        (_targetRoadSpeedFactor - _roadSpeedFactor) * 0.08;

    final current = LatLng(_animLat, _animLng);

    if (_liveTarget == null) return;

    // Device stopped: slow forward crawl, and soft-follow if a new GPS update arrived.
    if (!_shouldKeepMoving()) {
      _advanceWhileStopped(current, dt);
      return;
    }

    final pathMeters = _remainingPathMeters(current);
    final distToGps = _distanceToLiveGps(current);
    final bearing = _resolveTravelBearing(current);
    final targetSpeed = _continuousSpeedMs(pathMeters);

    // Prefetch earlier at high speed so the queue never runs dry and freezes.
    final prefetchM =
        math.max(35.0, _smoothedGlideSpeedMs * 4.0).clamp(35.0, 90.0);
    // Keep Mapbox path topped up so animation never falls back to raw GPS.
    if (_liveTarget != null &&
        (pathMeters < prefetchM || _roadQueue.length < 2) &&
        distToGps > _minRoadRouteMeters) {
      _requestRoadPath(_liveTarget!, force: _roadQueue.length < 2);
    }

    // Asymmetric speed easing: rise carefully, coast down slowly.
    // Hard brakes between catch-up and cruise feel like forward/back vibration.
    final speedDelta = targetSpeed - _smoothedGlideSpeedMs;
    final maxDelta = (speedDelta >= 0 ? _maxSpeedAccelMs : _maxSpeedDecelMs) * dt;
    _smoothedGlideSpeedMs += speedDelta.clamp(-maxDelta, maxDelta);
    _smoothedGlideSpeedMs =
        math.max(_smoothedGlideSpeedMs, _wsWaitCreepMinMs);

    // Step cap scales with speed — a fixed 1 m/frame ceiling made highway
    // cars lag, then catch-up, then surge (the high-speed forward/back jerk).
    final desiredStep = _smoothedGlideSpeedMs * dt;
    final maxStep = math.max(
      _maxStepPerFrameM,
      desiredStep * 1.25,
    );
    final step = desiredStep.clamp(_wsWaitCreepMinMs * dt * 0.35, maxStep);

    _advanceMarkerContinuously(
      current: current,
      gpsTarget: _liveTarget!,
      bearing: bearing,
      step: step,
      distToGps: distToGps,
    );

    _smoothUiPosition();
    _smoothUiHeading(dt);
    _publishAnim();
    if (isLocked.value) _smoothFollowCamera(dt);
  }

  /// Stopped: stay on Mapbox road geometry — never crawl toward raw GPS.
  void _advanceWhileStopped(LatLng current, double dt) {
    _smoothedGlideSpeedMs = 0.0;
    _snapOntoKnownRoad(hard: false);
    final here = LatLng(_animLat, _animLng);
    final distToGps = _distanceToLiveGps(here);
    // If Mapbox still has remaining road toward the last update, ease along it.
    if (_liveTarget != null && distToGps > 2.0 && _roadQueue.isNotEmpty) {
      final step = math.min(_stoppedCreepMs * dt, distToGps);
      _advanceAlongRoad(here, step);
    }
    _smoothUiPosition();
    _smoothUiHeading(dt);
    _publishAnim();
    if (isLocked.value) _smoothFollowCamera(dt);
  }

  void _startAnimationLoop() {
    _animationTimer?.cancel();
    _animationTimer = Timer.periodic(const Duration(milliseconds: 33), (_) {
      if (_disposed) return;
      _glideTowardTarget();
    });
  }

  /// Continuous soft camera chase — follows [_uiLat]/[_uiLng] with easing.
  void _smoothFollowCamera(double dt, {bool snap = false}) {
    final now = DateTime.now();
    if (!snap &&
        _lastCameraMove != null &&
        now.difference(_lastCameraMove!).inMilliseconds <
            _cameraMoveIntervalMs) {
      return;
    }

    final lat = _uiLat != 0.0
        ? _uiLat
        : (_animLat != 0.0 ? _animLat : animatedLat.value);
    final lng = _uiLng != 0.0
        ? _uiLng
        : (_animLng != 0.0 ? _animLng : animatedLng.value);
    if (lat == 0.0 || lng == 0.0) return;

    double zoom = _followZoom;
    if (_userAdjustedZoom) {
      try {
        zoom = mapController.camera.zoom;
      } catch (_) {}
    }

    var target = LatLng(lat, lng);
    if (showBottomSheet.value) {
      final latOffset = 0.0012 * math.pow(2, 15.0 - zoom);
      target = LatLng(lat - latOffset, lng);
    }

    if (snap || _smoothCameraLat == 0.0) {
      _smoothCameraLat = target.latitude;
      _smoothCameraLng = target.longitude;
    } else {
      final currentCam = LatLng(_smoothCameraLat, _smoothCameraLng);
      final lagM = _calculateDistance(currentCam, target);
      // Far behind → catch up a bit faster; close → very soft glide.
      final k = lagM > 35.0 ? _cameraCatchUpK : _cameraFollowK;
      final alpha = (1.0 - math.exp(-k * dt)).clamp(0.04, 0.28);

      var nextLat =
          _smoothCameraLat + (target.latitude - _smoothCameraLat) * alpha;
      var nextLng =
          _smoothCameraLng + (target.longitude - _smoothCameraLng) * alpha;
      final stepped = LatLng(nextLat, nextLng);
      final stepM = _calculateDistance(currentCam, stepped);
      // Let camera travel farther at highway speed so it doesn't lag then yank.
      final maxCamStep = math.max(
        _maxCameraStepM,
        _smoothedGlideSpeedMs * dt * 18.0,
      );
      if (stepM > maxCamStep && stepM > 0) {
        final t = maxCamStep / stepM;
        nextLat =
            _smoothCameraLat + (nextLat - _smoothCameraLat) * t;
        nextLng =
            _smoothCameraLng + (nextLng - _smoothCameraLng) * t;
      }
      _smoothCameraLat = nextLat;
      _smoothCameraLng = nextLng;
    }

    _lastCameraMove = now;
    try {
      _ignoreMapGestureUntil =
          DateTime.now().add(const Duration(milliseconds: 80));
      mapController.moveAndRotate(
        LatLng(_smoothCameraLat, _smoothCameraLng),
        zoom,
        0,
      );
    } catch (_) {}
  }

  void _maybeMoveCameraToVehicle() {
    _smoothFollowCamera(_frameSeconds, snap: false);
  }

  void _updateMovementSpeed(double speedKmH, String status, {String? mode}) {
    if (mode != null) _movementMode = mode;

    final speedMs = speedKmH.clamp(0.0, 200.0) / 3.6;

    if (speedKmH <= 0) {
      _currentSpeedMs = 0;
      _smoothedSpeedMs = 0;
      return;
    }

    if (speedMs >= 0.3) {
      _currentSpeedMs = speedMs;
      _smoothedSpeedMs = speedMs;
      _lastMovingTime = DateTime.now();
      return;
    }

    if (_smoothedSpeedMs >= 0.35) {
      _currentSpeedMs = _smoothedSpeedMs;
      return;
    }
    if (_lastMovingTime != null &&
        DateTime.now().difference(_lastMovingTime!).inSeconds < 45) {
      _currentSpeedMs = math.max(_currentSpeedMs, _smoothedSpeedMs * 0.85);
    }
  }

  (double, double)? _readLatLngFromMap(Map<String, dynamic> data) {
    final lat = double.tryParse(
      (data['latitude'] ?? data['lat'])?.toString() ?? '',
    );
    final lng = double.tryParse(
      (data['longitude'] ?? data['lng'] ?? data['lon'])?.toString() ?? '',
    );
    if (lat == null || lng == null || (lat == 0.0 && lng == 0.0)) return null;
    return (lat, lng);
  }

  num? _readSpeedFromMap(Map<String, dynamic> data) {
    final raw = data['speed'];
    if (raw is num) return raw;
    return num.tryParse(raw?.toString() ?? '');
  }

  double? _readCourseFromMap(Map<String, dynamic> data) {
    final raw = data['course'] ??
        data['angle'] ??
        data['heading'] ??
        data['direction'];
    if (raw is num) return raw.toDouble();
    return double.tryParse(raw?.toString() ?? '');
  }

  void onMapGesture() {
    // Camera follow calls mapController.move(); flutter_map often reports those
    // as gestures. Ignoring them prevents unlock → freeze/wrong-way glitches.
    final until = _ignoreMapGestureUntil;
    if (until != null && DateTime.now().isBefore(until)) {
      return;
    }
    if (isLocked.value) {
      isLocked.value = false;
    }
    _userAdjustedZoom = true;
    _ensureNorthUp();
  }

  /// Hard lock: map always looks straight down, north at the top.
  void _ensureNorthUp() {
    try {
      final cam = mapController.camera;
      if (cam.rotation.abs() < 0.05) return;
      _ignoreMapGestureUntil =
          DateTime.now().add(const Duration(milliseconds: 200));
      mapController.moveAndRotate(cam.center, cam.zoom, 0);
    } catch (_) {}
  }

  void zoomIn() => _applyZoomDelta(1.0);

  void zoomOut() => _applyZoomDelta(-1.0);

  void _applyZoomDelta(double delta) {
    try {
      final camera = mapController.camera;
      final nextZoom = (camera.zoom + delta).clamp(3.0, 20.0);
      _userAdjustedZoom = true;
      _ignoreMapGestureUntil =
          DateTime.now().add(const Duration(milliseconds: 200));
      mapController.moveAndRotate(camera.center, nextZoom, 0);
    } catch (e) {
      debugPrint('[LiveTrack] zoom failed: $e');
    }
  }

  void moveMapToVehicle({bool snap = false, bool resetZoom = false}) {
    isLocked.value = true;
    if (resetZoom) _userAdjustedZoom = false;
    // Focus / lock: snap quickly; live follow uses _smoothFollowCamera each frame.
    _smoothFollowCamera(_frameSeconds, snap: snap || resetZoom);
  }

  void toggleBottomSheet() => showBottomSheet.value = !showBottomSheet.value;

  String get displayPlate =>
      liveTrackData.value?.vehicleInfo?.vehicleNumber ?? vehiclePlate.value;
  String get displayImei => vehicleImei.value;
  String get displaySpeed =>
      liveTrackData.value?.currentPosition?.speed?.toStringAsFixed(1) ?? '0.0';
  String get displayStatus =>
      liveTrackData.value?.currentStatus ??
      liveTrackData.value?.currentPosition?.derivedStatus ??
      'Stopped';
  String get displayDeviceTime =>
      liveTrackData.value?.currentPosition?.deviceTime ?? '–';
  String get displayLastUpdate =>
      liveTrackData.value?.currentPosition?.lastUpdate ??
      liveTrackData.value?.currentPositionApi?.data?.lastUpdate ??
      '–';

  String get displayLatitude => animatedLat.value != 0.0
      ? animatedLat.value.toStringAsFixed(7)
      : (liveTrackData.value?.currentPosition?.latitude ?? '–');
  String get displayLongitude => animatedLng.value != 0.0
      ? animatedLng.value.toStringAsFixed(7)
      : (liveTrackData.value?.currentPosition?.longitude ?? '–');

  bool get isIgnitionOn =>
      liveTrackData.value?.currentPosition?.isIgnitionOn ?? false;
  bool get isPowerOn =>
      liveTrackData.value?.currentPosition?.isPowerOn ?? false;

  /// GSM from snapshot/WS `position.gsm_signal_strength` only.
  String get displayGsmSignal {
    final raw = liveTrackData.value?.currentPosition?.gsmSignalStrength;
    if (raw == null) return '–';
    final value = raw.trim();
    if (value.isEmpty || value.toLowerCase() == 'null') return '–';
    return value;
  }

  String get displayNetwork {
    final raw = liveTrackData.value?.currentPosition?.network;
    if (raw == null) return '–';
    final value = raw.trim();
    if (value.isEmpty || value.toLowerCase() == 'null') return '–';
    return value;
  }
  String get displayAltitude {
    final fromPos = liveTrackData.value?.currentPosition?.altitude;
    if (fromPos != null && fromPos.trim().isNotEmpty && fromPos != 'null') {
      return fromPos;
    }
    final fromApi = liveTrackData.value?.currentPositionApi?.data?.altitude;
    if (fromApi != null && fromApi.trim().isNotEmpty && fromApi != 'null') {
      return fromApi;
    }
    return '–';
  }

  String get displayTodayKm =>
      liveTrackData.value?.todayStatistics?.totalKilometersToday
          ?.toStringAsFixed(2) ??
      '0.00';
  /// Odometer km from `position.odometer`.
  String get displayOdometer {
    final value =
        odometerKm.value ?? liveTrackData.value?.currentPosition?.odometer;
    if (value == null) return '0.00';
    return value.toStringAsFixed(2);
  }

  /// 8 digit columns under the plate — whole km from `position.odometer`.
  String get displayOdometerDigits {
    final value =
        odometerKm.value ?? liveTrackData.value?.currentPosition?.odometer ?? 0;
    final wholeKm = value.floor().clamp(0, 99999999);
    return wholeKm.toString().padLeft(8, '0');
  }

  /// Total traveled km (`position.kilometer`), not the device odometer.
  String get displayTotalKm {
    final fromVehicle =
        liveTrackData.value?.vehicleInfo?.totalKilometersTraveled;
    if (fromVehicle != null && fromVehicle.trim().isNotEmpty) {
      return fromVehicle;
    }
    return liveTrackData.value?.currentPosition?.kilometer ?? '0.00';
  }

  String get displayStoppedDuration =>
      liveTrackData.value?.todayStatistics?.displayStoppedDuration ??
      '00:00:00';
  String get displayIdleDuration =>
      liveTrackData.value?.todayStatistics?.displayIdleDuration ?? '00:00:00';
  String get displayRunningDuration =>
      liveTrackData.value?.todayStatistics?.displayRunningDuration ??
      '00:00:00';
  String get displayInactiveDuration =>
      liveTrackData.value?.todayStatistics?.displayInactiveDuration ??
      '00:00:00';

  String get displayAvgSpeed =>
      liveTrackData.value?.todayStatistics?.avgSpeed?.toStringAsFixed(2) ??
      '–';
  String get displayMaxSpeed =>
      liveTrackData.value?.todayStatistics?.maxSpeed?.toStringAsFixed(0) ??
      '–';

  Color get displayStatusColor {
    final status =
        liveTrackData.value?.currentPosition?.derivedStatus ?? 'Stopped';
    switch (status) {
      case 'Running':
        return const Color(0xFF28A745);
      case 'Idle':
        return const Color(0xFFFFC107);
      case 'Inactive':
        return const Color(0xFF6C757D);
      default:
        return const Color(0xFFDC3545);
    }
  }

  void _syncMarkerPosition() {
    final lat = _uiLat != 0.0 ? _uiLat : _animLat;
    final lng = _uiLng != 0.0 ? _uiLng : _animLng;
    if (lat == 0.0 && lng == 0.0) {
      if (reactiveMarkers.isNotEmpty) reactiveMarkers.clear();
      _vehicleMarkerChild = null;
      return;
    }

    final point = LatLng(lat, lng);
    _vehicleMarkerChild ??= _buildStableVehicleMarkerChild();

    final marker = Marker(
      key: const ValueKey('live_vehicle_marker'),
      point: point,
      width: 48,
      height: 48,
      alignment: Alignment.center,
      child: _vehicleMarkerChild!,
    );

    if (reactiveMarkers.isEmpty) {
      reactiveMarkers.add(marker);
      return;
    }

    // Index assign notifies Obx once — avoid extra refresh() (double rebuild = flicker).
    reactiveMarkers[0] = marker;
  }

  /// Built once and reused. Top-down car only (transparent PNG, no plate/box).
  Widget _buildStableVehicleMarkerChild() {
    return GestureDetector(
      onTap: toggleBottomSheet,
      behavior: HitTestBehavior.deferToChild,
      child: ValueListenableBuilder<double>(
        valueListenable: _headingNotifier,
        builder: (context, heading, child) {
          // Top icon faces north (screen-up) at 0° — no -45 offset.
          return Transform.rotate(
            angle: heading * (math.pi / 180),
            child: child,
          );
        },
        child: Image.asset(
          'lib/Asset/Icons/Track Vehicle Top.png',
          width: 44,
          height: 44,
          fit: BoxFit.contain,
          gaplessPlayback: true,
          filterQuality: FilterQuality.high,
          // Avoid any default tint / opaque fill around the asset.
          color: null,
        ),
      ),
    );
  }

  RxList<Marker> get mapMarkers => reactiveMarkers;

  double _normalizeBearing(double bearing) => (bearing % 360 + 360) % 360;

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
    return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
  }

  double _calculateDistance(LatLng p1, LatLng p2) {
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

  /// POST update_odometer — body: { imei, odometer }
  /// On success returns the new value; caller must close sheet BEFORE applying UI.
  Future<({bool ok, num? value, String message})> updateOdometer(
    String odometerInput,
  ) async {
    final imei = vehicleImei.value.trim();
    final trimmed = odometerInput.trim();
    final value = num.tryParse(trimmed);

    if (imei.isEmpty) {
      showErrorMessage('Vehicle IMEI is missing');
      return (ok: false, value: null, message: 'Vehicle IMEI is missing');
    }
    if (value == null || value < 0) {
      showErrorMessage('Enter a valid odometer value');
      return (ok: false, value: null, message: 'Enter a valid odometer value');
    }
    if (isUpdatingOdometer.value) {
      return (ok: false, value: null, message: 'Already updating');
    }

    isUpdatingOdometer.value = true;
    try {
      final response = await DioClient().post(
        ApiEndPoints.updateOdometer,
        body: {
          'imei': imei,
          'odometer': value,
        },
      );

      final raw = response.data;
      final ok = raw is Map
          ? (raw['status'] == true ||
              raw['success'] == true ||
              response.statusCode == 200)
          : response.statusCode == 200;

      if (!ok) {
        final msg = raw is Map
            ? (raw['message']?.toString() ?? 'Failed to update odometer')
            : 'Failed to update odometer';
        showErrorMessage(msg);
        clearOdometerUpdating();
        return (ok: false, value: null, message: msg);
      }

      final msg = (raw is Map ? raw['message']?.toString() : null) ??
          'Odometer updated';
      // No UI mutations here — applying while modal is open was freezing the app.
      return (ok: true, value: value, message: msg);
    } catch (e) {
      showErrorMessage(e);
      clearOdometerUpdating();
      return (ok: false, value: null, message: e.toString());
    }
  }

  /// Pull-to-refresh: optional snapshot catch-up only (keeps WebSocket alive).
  Future<void> refreshData() async {
    if (vehicleImei.value.isEmpty || _disposed) return;
    await _fetchLiveTrackSnapshot(vehicleImei.value, reconnectOnly: true);
  }

  Future<void> startTrackingForImei(String imei, {String? plate}) async {
    await _webSocketService.disconnect();
    vehicleImei.value = imei;
    if (plate != null && plate.isNotEmpty) vehiclePlate.value = plate;

    liveTrackData.value = null;
    _wsConfig = null;
    _wsInfo = null;
    _hasInitialCameraFocus = false;
    _smoothCameraLat = 0.0;
    _smoothCameraLng = 0.0;
    _userAdjustedZoom = false;
    _liveTarget = null;
    _lastAcceptedGps = null;
    _lastGlideTime = null;
    _lastGpsTime = null;
    _currentSpeedMs = 0;
    _smoothedSpeedMs = 0;
    _lastMovingTime = null;
    _movementMode = '';
    _lastReportedSpeedKmh = 0;
    _lastInferredSpeedKmh = 0;
    _lastGpsDeltaM = 0;
    _isMovingVehicle = false;
    _roadSpeedFactor = 1.0;
    _targetRoadSpeedFactor = 1.0;
    _smoothedGlideSpeedMs = 0.0;
    _routeRequestId = 0;
    _roadQueue.clear();
    _gpsTrace.clear();
    _lastRoadCorridor.clear();
    _roadFetchInFlight = false;
    _pendingRoadTarget = null;
    _lockedBearing = 0;
    _hasHeading = false;
    _animLat = 0;
    _animLng = 0;
    _uiLat = 0;
    _uiLng = 0;
    _uiHeading = 0;
    _lastUiSync = null;
    _lastUiSyncPoint = null;
    _vehicleMarkerChild = null;
    _headingNotifier.value = 0;
    _pauseMarkerUi = false;
    odometerKm.value = null;
    animatedLat.value = 0;
    animatedLng.value = 0;
    animatedRotation.value = 0;

    await _fetchLiveTrackSnapshot(imei);
  }

  @override
  void onClose() {
    _disposed = true;
    _animationTimer?.cancel();
    _animationTimer = null;
    _headingNotifier.dispose();
    unawaited(_webSocketService.disconnect());
    fenceNameController.dispose();
    super.onClose();
  }
}
