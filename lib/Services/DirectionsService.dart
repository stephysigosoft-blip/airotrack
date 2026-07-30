import 'dart:math' as math;
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import '../Configs/ApiConfigs.dart';

class DirectionsService {
  final Dio _dio = Dio();
  final String _accessToken = ApiConfig.mapboxAccessToken;

  /// Road route between two points (Mapbox Directions). Empty on failure —
  /// never returns a straight off-road chord for live tracking.
  Future<List<LatLng>> getRoute(
    LatLng origin,
    LatLng destination, {
    bool smooth = false,
  }) async {
    final String url =
        'https://api.mapbox.com/directions/v5/mapbox/driving'
        '/${origin.longitude},${origin.latitude}'
        ';${destination.longitude},${destination.latitude}'
        '?geometries=geojson&overview=full&access_token=$_accessToken';

    try {
      final response = await _dio.get<Map<String, dynamic>>(url);
      if (response.statusCode == 200 && response.data != null) {
        final List routes = response.data!['routes'] as List? ?? [];
        if (routes.isNotEmpty) {
          final geometry = routes[0]['geometry'];
          final points = _coordsFromGeoJson(geometry);
          if (points.length >= 2) {
            return _densify(points, maxSegmentM: 2.5);
          }
        }
      }
    } catch (e) {
      debugPrint('DirectionsService: Error fetching route: $e');
    }
    return const [];
  }

  /// Snaps a GPS trace onto the road network (Map Matching).
  /// Returns empty list on failure (caller should keep previous on-road path).
  Future<List<LatLng>> matchTrace(
    List<LatLng> points, {
    double radiusMeters = 25,
  }) async {
    if (points.length < 2) return const [];

    final cleaned = <LatLng>[points.first];
    for (var i = 1; i < points.length; i++) {
      if (_approxDistanceM(cleaned.last, points[i]) >= 2.0) {
        cleaned.add(points[i]);
      }
    }
    if (cleaned.length < 2) return const [];

    final input =
        cleaned.length > 100 ? cleaned.sublist(cleaned.length - 100) : cleaned;

    final coords = input.map((p) => '${p.longitude},${p.latitude}').join(';');
    final radiuses = List.filled(input.length, radiusMeters.round()).join(';');
    final url =
        'https://api.mapbox.com/matching/v5/mapbox/driving/$coords.json'
        '?geometries=geojson&overview=full&radiuses=$radiuses'
        '&tidy=true&access_token=$_accessToken';

    try {
      final response = await _dio.get<Map<String, dynamic>>(url);
      if (response.statusCode != 200 || response.data == null) {
        return getRoute(input.first, input.last);
      }

      final data = response.data!;
      if (data['code']?.toString() != 'Ok') {
        debugPrint('DirectionsService matchTrace: code=${data['code']}');
        return getRoute(input.first, input.last);
      }

      final matchings = data['matchings'];
      if (matchings is! List || matchings.isEmpty) {
        return getRoute(input.first, input.last);
      }

      final snapped = <LatLng>[];
      for (final m in matchings) {
        if (m is! Map) continue;
        snapped.addAll(_coordsFromGeoJson(m['geometry']));
      }

      if (snapped.length < 2) {
        return getRoute(input.first, input.last);
      }
      return _densify(snapped, maxSegmentM: 2.5);
    } catch (e) {
      debugPrint('DirectionsService matchTrace error: $e');
      return getRoute(input.first, input.last);
    }
  }

  List<LatLng> _coordsFromGeoJson(dynamic geometry) {
    final out = <LatLng>[];
    if (geometry is! Map) return out;
    final coordinates = geometry['coordinates'];
    if (coordinates is! List) return out;
    for (final c in coordinates) {
      if (c is List && c.length >= 2) {
        final lng = (c[0] as num).toDouble();
        final lat = (c[1] as num).toDouble();
        final pt = LatLng(lat, lng);
        if (out.isEmpty || _approxDistanceM(out.last, pt) >= 0.6) {
          out.add(pt);
        }
      }
    }
    return out;
  }

  /// Insert points so the marker never jumps long chords that look off-road.
  List<LatLng> _densify(List<LatLng> points, {required double maxSegmentM}) {
    if (points.length < 2) return points;
    final out = <LatLng>[points.first];
    for (var i = 1; i < points.length; i++) {
      final a = out.last;
      final b = points[i];
      final dist = _approxDistanceM(a, b);
      if (dist <= maxSegmentM) {
        out.add(b);
        continue;
      }
      final steps = (dist / maxSegmentM).ceil();
      for (var s = 1; s <= steps; s++) {
        final t = s / steps;
        out.add(LatLng(
          a.latitude + (b.latitude - a.latitude) * t,
          a.longitude + (b.longitude - a.longitude) * t,
        ));
      }
    }
    return out;
  }

  double _approxDistanceM(LatLng a, LatLng b) {
    const metersPerLat = 111320.0;
    final dLat = (a.latitude - b.latitude) * metersPerLat;
    final midLatRad = (a.latitude + b.latitude) * 0.5 * math.pi / 180.0;
    final metersPerLng = 111320.0 * math.cos(midLatRad);
    final dLng = (a.longitude - b.longitude) * metersPerLng;
    return math.sqrt(dLat * dLat + dLng * dLng);
  }
}
