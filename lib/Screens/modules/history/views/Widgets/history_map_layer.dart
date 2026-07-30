import 'dart:math' as math;

import 'package:airotrack/Configs/ApiConfigs.dart';
import 'package:airotrack/Models/HistoryModel.dart';
import 'package:airotrack/Services/ReverseGeocodeService.dart';
import 'package:airotrack/Utils/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart' as ll;

class HistoryMapLayer extends StatefulWidget {
  const HistoryMapLayer({
    Key? key,
    required this.initialCenter,
    required this.initialZoom,
    required this.polylinePoints,
    required this.markerPoints,
    this.mapController,
    this.stopLocations = const [],
    this.selectedStopIndex,
    this.showStopMarkers = true,
    this.onStopTap,
    this.movingMarkerPosition,
    this.movingMarkerBearing,
    this.isFollowCameraEnabled = true,
    this.isPlaybackActive = false,
    this.bottomSheetVisible = true,
    this.onManualFollowDisable,
    this.movingMarkerAssetPath = 'lib/Asset/Images/marker2.png',
  }) : super(key: key);

  final ll.LatLng initialCenter;
  final double initialZoom;
  final List<ll.LatLng> polylinePoints;
  final List<ll.LatLng> markerPoints;
  final MapController? mapController;
  final List<HistoryStopLocation> stopLocations;
  final int? selectedStopIndex;
  final bool showStopMarkers;
  final ValueChanged<int>? onStopTap;
  final ll.LatLng? movingMarkerPosition;
  final double? movingMarkerBearing;
  final bool isFollowCameraEnabled;
  final bool isPlaybackActive;
  final bool bottomSheetVisible;
  final VoidCallback? onManualFollowDisable;
  final String movingMarkerAssetPath;

  @override
  State<HistoryMapLayer> createState() => _HistoryMapLayerState();
}

class _HistoryMapLayerState extends State<HistoryMapLayer>
    with SingleTickerProviderStateMixin {
  late final MapController _mapController;
  static const double _fitPadding = 48.0;
  static const double _followVerticalOffsetFraction = 0.22;
  static const double _playbackFollowZoom = 16.0;
  bool _hasAutoFittedCurrentRoute = false;
  ll.LatLng? _lastFollowTarget;
  ll.LatLng? _smoothCameraCenter;
  double _lastKnownZoom = 15.0;
  double _fixedBearing = 0.0;
  bool _usePlaybackFollowZoom = false;
  bool _tileSourceLogged = false;
  bool _isProgrammaticCameraMove = false;
  bool _isMapReady = false;

  Ticker? _smoothTicker;
  ll.LatLng? _renderPosition;
  double _renderBearing = 0.0;

  double _positionAlpha(double latDelta, double lngDelta, bool isPlaying) {
    if (!isPlaying) return 1.0;
    // Controller already moves along polyline vertices each frame. Lat/lng lerp
    // cuts corners and makes the car look like it is driving off the blue route.
    return 1.0;
  }

  double _bearingAlpha(bool isPlaying) => isPlaying ? 0.55 : 1.0;

  @override
  void initState() {
    super.initState();
    _mapController = widget.mapController ?? MapController();
    _smoothTicker = createTicker(_onSmoothTick)..start();
  }

  void _onSmoothTick(Duration elapsed) {
    final target = widget.movingMarkerPosition;
    if (target == null) {
      if (_renderPosition != null && mounted) {
        setState(() => _renderPosition = null);
      }
      return;
    }

    final targetBearing = widget.movingMarkerBearing ?? 0.0;
    if (_renderPosition == null) {
      if (!mounted) return;
      setState(() {
        _renderPosition = target;
        _renderBearing = targetBearing;
      });
      if (widget.isFollowCameraEnabled &&
          (widget.isPlaybackActive || widget.movingMarkerPosition != null)) {
        _enterFollowMode(snapImmediately: true);
      }
      return;
    }

    final latDelta = target.latitude - _renderPosition!.latitude;
    final lngDelta = target.longitude - _renderPosition!.longitude;
    final bearingDelta =
        _shortestBearingDelta(_renderBearing, targetBearing);

    if (latDelta.abs() < 1e-8 &&
        lngDelta.abs() < 1e-8 &&
        bearingDelta.abs() < 0.05) {
      return;
    }

    final isPlaying = widget.isPlaybackActive;
    final positionAlpha = _positionAlpha(latDelta, lngDelta, isPlaying);
    final bearingAlpha = _bearingAlpha(isPlaying);

    if (!mounted) return;
    setState(() {
      _renderPosition = ll.LatLng(
        _renderPosition!.latitude + latDelta * positionAlpha,
        _renderPosition!.longitude + lngDelta * positionAlpha,
      );
      _renderBearing =
          (_renderBearing + bearingDelta * bearingAlpha) % 360;
    });

    if (widget.isFollowCameraEnabled && widget.isPlaybackActive) {
      _followMovingMarker();
    }
  }

  double _shortestBearingDelta(double from, double to) {
    return ((to - from + 540) % 360) - 180;
  }

  @override
  void didUpdateWidget(HistoryMapLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.polylinePoints.length < 2) {
      // New route load starts with empty/short polyline; allow one auto-fit when route appears again.
      _hasAutoFittedCurrentRoute = false;
      return;
    }
    final wasNotDrawable = oldWidget.polylinePoints.length < 2;
    if (wasNotDrawable && _isMapReady && !_hasAutoFittedCurrentRoute) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _isMapReady) {
          _fitToPolyline();
          _hasAutoFittedCurrentRoute = true;
        }
      });
    }
    final moved =
        widget.movingMarkerPosition != null &&
        widget.movingMarkerPosition != oldWidget.movingMarkerPosition;
    final followToggledOn =
        widget.isFollowCameraEnabled && !oldWidget.isFollowCameraEnabled;
    final playbackStarted =
        widget.isPlaybackActive && !oldWidget.isPlaybackActive;
    if (playbackStarted && widget.isFollowCameraEnabled) {
      _enterFollowMode(snapImmediately: true);
    }
    if ((moved || followToggledOn) &&
        widget.isFollowCameraEnabled &&
        widget.isPlaybackActive &&
        _renderPosition != null) {
      if (followToggledOn) _enterFollowMode(snapImmediately: true);
      _followMovingMarker();
    }
  }

  void _enterFollowMode({bool snapImmediately = false}) {
    _usePlaybackFollowZoom = true;
    _lastKnownZoom = _playbackFollowZoom;
    final marker = _renderPosition ?? widget.movingMarkerPosition;
    if (marker == null || !_isMapReady) return;
    final target = _cameraTargetWithVisualOffset(marker);
    if (snapImmediately) {
      _smoothCameraCenter = target;
      _lastFollowTarget = target;
      _isProgrammaticCameraMove = true;
      try {
        _mapController.moveAndRotate(target, _playbackFollowZoom, _fixedBearing);
      } finally {
        _isProgrammaticCameraMove = false;
      }
    }
  }

  double _activeFollowZoom() =>
      _usePlaybackFollowZoom ? _playbackFollowZoom : _lastKnownZoom;

  Future<void> _followMovingMarker() async {
    if (!_isMapReady || _renderPosition == null) return;
    if (!widget.isFollowCameraEnabled) return;

    final markerPosition = _renderPosition!;
    final target = _cameraTargetWithVisualOffset(markerPosition);
    final zoom = _activeFollowZoom();

    if (_smoothCameraCenter == null) {
      _smoothCameraCenter = target;
    } else {
      const cameraAlpha = 0.88;
      _smoothCameraCenter = ll.LatLng(
        _smoothCameraCenter!.latitude +
            (target.latitude - _smoothCameraCenter!.latitude) * cameraAlpha,
        _smoothCameraCenter!.longitude +
            (target.longitude - _smoothCameraCenter!.longitude) * cameraAlpha,
      );
    }

    if (_lastFollowTarget != null) {
      final movedDistance =
          (_smoothCameraCenter!.latitude - _lastFollowTarget!.latitude).abs() +
          (_smoothCameraCenter!.longitude - _lastFollowTarget!.longitude).abs();
      if (movedDistance < 0.000001) return;
    }
    _lastFollowTarget = _smoothCameraCenter;
    _isProgrammaticCameraMove = true;
    try {
      _mapController.moveAndRotate(
        _smoothCameraCenter!,
        zoom,
        _fixedBearing,
      );
    } finally {
      _isProgrammaticCameraMove = false;
    }
  }

  ll.LatLng _cameraTargetWithVisualOffset(ll.LatLng marker) {
    if (!widget.bottomSheetVisible) {
      return marker;
    }
    final heightPx = MediaQuery.sizeOf(context).height;
    final offsetPx = heightPx * _followVerticalOffsetFraction;
    final zoom = _activeFollowZoom();
    final metersPerPixel =
        156543.03392 * math.cos(marker.latitude * math.pi / 180.0) /
        math.pow(2.0, zoom);
    final offsetMeters = offsetPx * metersPerPixel;
    final deltaLat = offsetMeters / 111320.0;
    final adjustedLat = (marker.latitude - deltaLat).clamp(-85.0, 85.0);
    return ll.LatLng(adjustedLat, marker.longitude);
  }

  void _fitToPolyline() {
    final points = widget.polylinePoints;
    if (points.length < 2 || !_isMapReady) return;
    final bounds = LatLngBounds.fromPoints(points);

    // If the bounds are zero-area (e.g. all points same), fitCamera can crash on non-finite zoom calculation.
    final isZeroArea = bounds.southWest.latitude == bounds.northEast.latitude &&
        bounds.southWest.longitude == bounds.northEast.longitude;

    _isProgrammaticCameraMove = true;
    try {
      if (isZeroArea) {
        _mapController.move(bounds.center, _lastKnownZoom);
        debugPrint('[History] Camera: zero-area move applied');
      } else {
        _mapController.fitCamera(
          CameraFit.bounds(
            bounds: bounds,
            padding: const EdgeInsets.all(_fitPadding),
          ),
        );
        debugPrint('[History] Camera: initial fit applied');
      }
    } finally {
      _isProgrammaticCameraMove = false;
    }
  }

  @override
  void dispose() {
    _smoothTicker?.dispose();
    super.dispose();
  }

  String _mapboxTileUrl() {
    final token = ApiConfig.mapboxAccessToken.trim();
    final hasInvalidTokenFormat =
        token.isEmpty ||
        token.contains('<') ||
        token.contains('>') ||
        token.toLowerCase().contains('your_mapbox_access_token');
    if (hasInvalidTokenFormat) {
      if (!_tileSourceLogged) {
        _tileSourceLogged = true;
        debugPrint(
          '[History] Tiles: Mapbox token missing/invalid, falling back to OSM tiles',
        );
      }
      return 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
    }
    if (!_tileSourceLogged) {
      _tileSourceLogged = true;
      debugPrint('[History] Tiles: using Mapbox style tiles');
    }
    return 'https://api.mapbox.com/styles/v1/mapbox/streets-v12/tiles/256/{z}/{x}/{y}@2x?access_token=$token';
  }

  @override
  Widget build(BuildContext context) {
    final initialTarget = widget.initialCenter;
    final hasPolyline = widget.polylinePoints.length >= 2;

    final polylines = <Polyline>[];
    if (hasPolyline) {
      polylines.add(
        Polyline(
          points: widget.polylinePoints,
          color: AppColors.primaryBlue,
          strokeWidth: 4,
        ),
      );
    }

    final markers = <Marker>[];
    final pointCount = widget.markerPoints.length;
    for (var i = 0; i < pointCount; i++) {
      final isStart = i == 0;
      final isEnd = i == pointCount - 1;
      markers.add(
        Marker(
          point: widget.markerPoints[i],
          width: 30,
          height: 30,
          child: Icon(
            Icons.location_pin,
            color: isStart
                ? Colors.green
                : isEnd
                ? Colors.red
                : Colors.blue,
            size: 30,
          ),
        ),
      );
    }

    if (widget.showStopMarkers) {
      for (var i = 0; i < widget.stopLocations.length; i++) {
        final stop = widget.stopLocations[i];
        final selected = widget.selectedStopIndex == i;
        final number = stop.index ?? (i + 1);
        markers.add(
          Marker(
            point: ll.LatLng(stop.markerLatitude, stop.markerLongitude),
            width: selected ? 250 : 28,
            height: selected ? 170 : 28,
            alignment: selected ? Alignment.bottomCenter : Alignment.center,
            child: _HistoryStopMarker(
              number: number,
              selected: selected,
              stop: stop,
              onTap: () => widget.onStopTap?.call(i),
            ),
          ),
        );
      }
    }

    if (_renderPosition != null) {
      markers.add(
        Marker(
          point: _renderPosition!,
          width: 44,
          height: 44,
          child: Transform.rotate(
            angle: _renderBearing * (math.pi / 180.0),
            child: Image.asset(
              widget.movingMarkerAssetPath,
              width: 40,
              height: 40,
              fit: BoxFit.contain,
            ),
          ),
        ),
      );
    } else if (widget.movingMarkerPosition != null) {
      markers.add(
        Marker(
          point: widget.movingMarkerPosition!,
          width: 44,
          height: 44,
          child: Transform.rotate(
            angle: (widget.movingMarkerBearing ?? 0.0) * (math.pi / 180.0),
            child: Image.asset(
              widget.movingMarkerAssetPath,
              width: 40,
              height: 40,
              fit: BoxFit.contain,
            ),
          ),
        ),
      );
    }

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: initialTarget,
        initialZoom: widget.initialZoom,
        initialRotation: 0.0,
        onTap: (_, _) {
          if (widget.selectedStopIndex != null) {
            widget.onStopTap?.call(-1);
          }
        },
        onMapReady: () {
          _isMapReady = true;
          _lastKnownZoom = widget.initialZoom;
          _fixedBearing = 0.0;
          if (widget.polylinePoints.length >= 2 && !_hasAutoFittedCurrentRoute) {
            _fitToPolyline();
            _hasAutoFittedCurrentRoute = true;
          }
        },
        onPositionChanged: (camera, hasGesture) {
          if (camera.zoom.isFinite) {
            _lastKnownZoom = camera.zoom;
            if (hasGesture && !_isProgrammaticCameraMove) {
              _usePlaybackFollowZoom = false;
            }
          }
          if (hasGesture &&
              !_isProgrammaticCameraMove &&
              widget.isPlaybackActive &&
              widget.isFollowCameraEnabled) {
            widget.onManualFollowDisable?.call();
            debugPrint('[History] Camera: manual move detected, follow disabled');
          }
        },
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
        ),
      ),
      children: [
        TileLayer(
          urlTemplate: _mapboxTileUrl(),
          userAgentPackageName: 'com.airotrack.app',
          fallbackUrl: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
        ),
        PolylineLayer(polylines: polylines),
        MarkerLayer(markers: markers),
      ],
    );
  }
}

class _HistoryStopMarker extends StatelessWidget {
  const _HistoryStopMarker({
    required this.number,
    required this.selected,
    required this.stop,
    required this.onTap,
  });

  final int number;
  final bool selected;
  final HistoryStopLocation stop;
  final VoidCallback onTap;

  static final _displayTimeFormat = DateFormat('dd MMM yyyy hh:mm a');
  static final _apiTimeFormat = DateFormat('yyyy-MM-dd HH:mm:ss');

  String _formatTime(String? raw) {
    if (raw == null || raw.trim().isEmpty) return '–';
    try {
      final parsed = _apiTimeFormat.parse(raw.trim());
      return _displayTimeFormat.format(parsed);
    } catch (_) {
      return raw;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (selected) ...[
            Material(
              color: Colors.transparent,
              child: Container(
                width: 236,
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 8,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _detailRow('Arrival Time:', _formatTime(stop.arrivalTime)),
                    const SizedBox(height: 4),
                    _detailRow(
                      'Departure Time:',
                      _formatTime(stop.departureTime),
                    ),
                    const SizedBox(height: 4),
                    _detailRow('Duration:', stop.duration ?? '–'),
                    const SizedBox(height: 4),
                    _detailRow(
                      'Latlong:',
                      '${stop.latitude.toStringAsFixed(6)}, ${stop.longitude.toStringAsFixed(6)}',
                      valueColor: const Color(0xFF009FE3),
                    ),
                    const SizedBox(height: 4),
                    _detailRow(
                      'Address:',
                      (stop.address?.trim().isNotEmpty ?? false)
                          ? ReverseGeocodeService.withoutPincode(stop.address)
                          : 'Address unavailable',
                      maxLines: 2,
                    ),
                    const Align(
                      alignment: Alignment.centerRight,
                      child: Icon(
                        Icons.near_me,
                        size: 14,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 4),
          ],
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.red.shade700,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.white, width: 1.5),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 3,
                  offset: Offset(0, 1),
                ),
              ],
            ),
            child: Text(
              '$number',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                height: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(
    String label,
    String value, {
    Color? valueColor,
    int maxLines = 1,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 88,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              color: valueColor ?? Colors.black87,
              fontWeight:
                  valueColor != null ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
      ],
    );
  }
}
