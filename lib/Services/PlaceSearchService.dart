import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../Configs/ApiConfigs.dart';
import 'ReverseGeocodeService.dart';

class PlaceSearchResult {
  final String name;
  final String address;
  final LatLng location;

  const PlaceSearchResult({
    required this.name,
    required this.address,
    required this.location,
  });
}

/// Forward geocode (place text → coordinates) via Mapbox Geocoding API.
class PlaceSearchService {
  PlaceSearchService._();
  static final PlaceSearchService instance = PlaceSearchService._();

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 8),
    ),
  );

  Future<List<PlaceSearchResult>> search(
    String query, {
    LatLng? proximity,
    int limit = 6,
  }) async {
    final q = query.trim();
    if (q.length < 2) return const [];

    final token = ApiConfig.mapboxAccessToken.trim();
    if (token.isEmpty ||
        token.toLowerCase().contains('your_mapbox_access_token')) {
      return const [];
    }

    try {
      final encoded = Uri.encodeComponent(q);
      final proximityParam = proximity == null
          ? ''
          : '&proximity=${proximity.longitude},${proximity.latitude}';
      final url =
          'https://api.mapbox.com/geocoding/v5/mapbox.places/$encoded.json'
          '?access_token=$token'
          '&autocomplete=true'
          '&limit=$limit'
          '&language=en'
          '&types=address,poi,neighborhood,locality,place,district,region'
          '$proximityParam';

      final response = await _dio.get<Map<String, dynamic>>(url);
      if (response.statusCode != 200 || response.data == null) {
        return const [];
      }

      final features = response.data!['features'];
      if (features is! List) return const [];

      final results = <PlaceSearchResult>[];
      for (final feature in features) {
        if (feature is! Map) continue;
        final center = feature['center'];
        if (center is! List || center.length < 2) continue;
        final lng = (center[0] as num?)?.toDouble();
        final lat = (center[1] as num?)?.toDouble();
        if (lat == null || lng == null) continue;

        final placeName = feature['place_name']?.toString().trim() ?? '';
        final text = feature['text']?.toString().trim() ?? '';
        final address = ReverseGeocodeService.withoutPincode(
          placeName.isNotEmpty ? placeName : text,
        );
        if (address.isEmpty && text.isEmpty) continue;

        results.add(
          PlaceSearchResult(
            name: text.isNotEmpty ? text : address,
            address: address.isNotEmpty ? address : text,
            location: LatLng(lat, lng),
          ),
        );
      }
      return results;
    } catch (e) {
      debugPrint('[PlaceSearch] failed for "$q": $e');
      return const [];
    }
  }
}
