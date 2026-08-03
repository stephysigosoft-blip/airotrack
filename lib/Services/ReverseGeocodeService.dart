import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../Configs/ApiConfigs.dart';

/// Reverse-geocodes lat/lng to a human-readable place name via Mapbox.
class ReverseGeocodeService {
  ReverseGeocodeService._();
  static final ReverseGeocodeService instance = ReverseGeocodeService._();

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 8),
    ),
  );

  final Map<String, String> _cache = <String, String>{};

  static String _cacheKey(double lat, double lng) =>
      'v2:${lat.toStringAsFixed(5)},${lng.toStringAsFixed(5)}';

  /// Keeps area + city + state — strips pincode and country (e.g. India).
  static String withoutPincode(String? raw) {
    if (raw == null) return '';
    var text = raw.trim();
    if (text.isEmpty) return '';

    // Drop postal / PIN codes.
    text = text.replaceAll(
      RegExp(
        r'(?:,\s*)?(?:\bPIN\b|\bPincode\b|\bPostal\s*Code\b)?\s*[A-Z]{0,2}\s*\d{3}\s*-?\s*\d{3}\b',
        caseSensitive: false,
      ),
      '',
    );
    text = text.replaceAll(
      RegExp(r'(?:,\s*)?\b\d{5}(?:-\d{4})?\b'),
      '',
    );

    // Drop country only.
    text = text.replaceAll(
      RegExp(r'(?:,\s*)?\bIndia\b\.?', caseSensitive: false),
      '',
    );

    final parts = text
        .split(',')
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .where((p) => !_isCountry(p))
        .toList();

    if (parts.length > 3) {
      // Keep area, city, state (last three meaningful segments).
      text =
          '${parts[parts.length - 3]}, ${parts[parts.length - 2]}, ${parts.last}';
    } else {
      text = parts.join(', ');
    }

    return text
        .replaceAll(RegExp(r'\s*,\s*,+'), ', ')
        .replaceAll(RegExp(r'^[\s,]+|[\s,]+$'), '')
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .trim();
  }

  static bool _isCountry(String value) {
    const blocked = <String>{'india', 'in'};
    return blocked.contains(value.trim().toLowerCase());
  }

  /// Build "Area, City, State" from Mapbox feature context.
  static String? _placeFromFeature(Map<dynamic, dynamic> feature) {
    String? area;
    String? city;
    String? state;

    final context = feature['context'];
    if (context is List) {
      for (final item in context) {
        if (item is! Map) continue;
        final id = item['id']?.toString() ?? '';
        final name = item['text']?.toString().trim();
        if (name == null || name.isEmpty) continue;

        if (id.startsWith('postcode.') ||
            id.startsWith('postalcode.') ||
            id.startsWith('country.')) {
          continue;
        }

        if (id.startsWith('region.')) {
          state ??= name;
        } else if (id.startsWith('place.')) {
          city ??= name;
        } else if (id.startsWith('neighborhood.') ||
            id.startsWith('locality.') ||
            id.startsWith('district.')) {
          area ??= name;
        }
      }
    }

    // Feature itself may be the area/city/poi/region.
    final placeTypes = feature['place_type'];
    final primary = feature['text']?.toString().trim();
    if (primary != null && primary.isNotEmpty) {
      final types = placeTypes is List
          ? placeTypes.map((e) => e.toString()).toList()
          : const <String>[];
      if (types.any((t) => t == 'region')) {
        state ??= primary;
      } else if (types.any((t) => t == 'place')) {
        city ??= primary;
      } else if (types.any(
        (t) =>
            t == 'neighborhood' ||
            t == 'locality' ||
            t == 'district' ||
            t == 'address' ||
            t == 'poi',
      )) {
        area ??= primary;
      } else {
        area ??= primary;
      }
    }

    final parts = <String>[];
    if (area != null && area.isNotEmpty) parts.add(area);
    if (city != null && city.isNotEmpty && city != area) parts.add(city);
    if (state != null &&
        state.isNotEmpty &&
        state != city &&
        state != area) {
      parts.add(state);
    }

    if (parts.isNotEmpty) {
      return withoutPincode(parts.join(', '));
    }

    final placeName = feature['place_name']?.toString().trim();
    if (placeName == null || placeName.isEmpty) return null;
    return withoutPincode(placeName);
  }

  /// Returns "Area, City, State" (no pincode / India), or null if lookup fails.
  Future<String?> reverse(double latitude, double longitude) async {
    if (!latitude.isFinite || !longitude.isFinite) return null;
    if (latitude == 0 && longitude == 0) return null;

    final key = _cacheKey(latitude, longitude);
    final cached = _cache[key];
    if (cached != null && cached.isNotEmpty) return withoutPincode(cached);

    final token = ApiConfig.mapboxAccessToken.trim();
    if (token.isEmpty ||
        token.toLowerCase().contains('your_mapbox_access_token')) {
      return null;
    }

    final url =
        'https://api.mapbox.com/geocoding/v5/mapbox.places/'
        '$longitude,$latitude.json'
        '?access_token=$token'
        '&limit=1'
        '&language=en'
        '&types=address,poi,neighborhood,locality,place,district,region';

    try {
      final response = await _dio.get<Map<String, dynamic>>(url);
      if (response.statusCode != 200 || response.data == null) return null;

      final features = response.data!['features'];
      if (features is! List || features.isEmpty) return null;

      final first = features.first;
      if (first is! Map) return null;

      final place = _placeFromFeature(first);
      if (place == null || place.isEmpty) return null;

      _cache[key] = place;
      return place;
    } catch (e) {
      debugPrint('[ReverseGeocode] failed for $key: $e');
      return null;
    }
  }
}
