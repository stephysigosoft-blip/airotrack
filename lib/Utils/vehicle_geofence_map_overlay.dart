import 'dart:math' as math;

import 'package:airotrack/Utils/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// Builds map circles/polygons from `GET vehicle_geofences` response.
class VehicleGeofenceMapOverlay {
  VehicleGeofenceMapOverlay._();

  static const _fillAlpha = 0.22;
  static const _borderAlpha = 0.85;

  static Color get _fill =>
      AppColors.primaryBlue.withValues(alpha: _fillAlpha);
  static Color get _border =>
      AppColors.primaryBlue.withValues(alpha: _borderAlpha);

  static void parseApiResponse(
    dynamic raw, {
    required List<CircleMarker> circles,
    required List<Polygon> polygons,
  }) {
    circles.clear();
    polygons.clear();

    if (raw is! Map) return;
    final data = raw['data'];
    if (data is! Map) return;

    final list = data['geofences'];
    if (list is! List) return;

    for (final item in list) {
      if (item is! Map) continue;
      _addOverlay(item, circles: circles, polygons: polygons);
    }
  }

  static void _addOverlay(
    Map item, {
    required List<CircleMarker> circles,
    required List<Polygon> polygons,
  }) {
    final type = item['type']?.toString().toLowerCase() ?? 'circle';

    if (type == 'circle') {
      final lat = double.tryParse(item['latitude']?.toString() ?? '');
      final lng = double.tryParse(item['longitude']?.toString() ?? '');
      final radiusKm = double.tryParse(item['radius']?.toString() ?? '');
      if (lat == null || lng == null || radiusKm == null || radiusKm <= 0) {
        return;
      }
      circles.add(
        CircleMarker(
          point: LatLng(lat, lng),
          radius: radiusKm * 1000,
          useRadiusInMeter: true,
          color: _fill,
          borderStrokeWidth: 2,
          borderColor: _border,
        ),
      );
      return;
    }

    var points = _parseCoordinates(item['coordinates']);
    if (points.isEmpty) return;

    if (type == 'rectangle' && points.length == 2) {
      points = _rectangleFromOppositeCorners(points[0], points[1]);
    }

    if (points.length < 3) return;

    polygons.add(
      Polygon(
        points: points,
        color: _fill,
        borderStrokeWidth: 2,
        borderColor: _border,
      ),
    );
  }

  static List<LatLng> _parseCoordinates(dynamic raw) {
    if (raw is! List) return [];
    final points = <LatLng>[];
    for (final c in raw) {
      if (c is! Map) continue;
      final lat = double.tryParse(c['lat']?.toString() ?? '');
      final lng = double.tryParse(c['lng']?.toString() ?? '');
      if (lat != null && lng != null) {
        points.add(LatLng(lat, lng));
      }
    }
    return points;
  }

  static List<LatLng> _rectangleFromOppositeCorners(LatLng a, LatLng b) {
    final minLat = math.min(a.latitude, b.latitude);
    final maxLat = math.max(a.latitude, b.latitude);
    final minLng = math.min(a.longitude, b.longitude);
    final maxLng = math.max(a.longitude, b.longitude);
    return [
      LatLng(minLat, minLng),
      LatLng(minLat, maxLng),
      LatLng(maxLat, maxLng),
      LatLng(maxLat, minLng),
    ];
  }
}
