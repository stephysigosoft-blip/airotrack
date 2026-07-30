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
      '${lat.toStringAsFixed(5)},${lng.toStringAsFixed(5)}';

  /// Keeps area + city only — strips pincode, state, and country (e.g. India).
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

    // Drop country.
    text = text.replaceAll(
      RegExp(r'(?:,\s*)?\bIndia\b\.?', caseSensitive: false),
      '',
    );

    final parts = text
        .split(',')
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .where((p) => !_isCountryOrState(p))
        .toList();

    if (parts.length > 2) {
      // Keep area + city only.
      text = '${parts[parts.length - 2]}, ${parts.last}';
    } else {
      text = parts.join(', ');
    }

    return text
        .replaceAll(RegExp(r'\s*,\s*,+'), ', ')
        .replaceAll(RegExp(r'^[\s,]+|[\s,]+$'), '')
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .trim();
  }

  static bool _isCountryOrState(String value) {
    const blocked = <String>{
      'india',
      'in',
      'kerala',
      'tamil nadu',
      'karnataka',
      'maharashtra',
      'andhra pradesh',
      'telangana',
      'delhi',
      'gujarat',
      'rajasthan',
      'west bengal',
      'uttar pradesh',
      'madhya pradesh',
      'punjab',
      'haryana',
      'odisha',
      'bihar',
      'assam',
      'goa',
    };
    return blocked.contains(value.trim().toLowerCase());
  }

  /// Build "Area, City" from Mapbox feature context (no state/country/pincode).
  static String? _placeFromFeature(Map<dynamic, dynamic> feature) {
    String? area;
    String? city;

    final context = feature['context'];
    if (context is List) {
      for (final item in context) {
        if (item is! Map) continue;
        final id = item['id']?.toString() ?? '';
        final name = item['text']?.toString().trim();
        if (name == null || name.isEmpty) continue;

        if (id.startsWith('postcode.') ||
            id.startsWith('postalcode.') ||
            id.startsWith('country.') ||
            id.startsWith('region.')) {
          continue;
        }

        if (id.startsWith('place.')) {
          city ??= name;
        } else if (id.startsWith('neighborhood.') ||
            id.startsWith('locality.') ||
            id.startsWith('district.')) {
          area ??= name;
        }
      }
    }

    // Feature itself may be the area/city/poi.
    final placeTypes = feature['place_type'];
    final primary = feature['text']?.toString().trim();
    if (primary != null && primary.isNotEmpty) {
      final types = placeTypes is List
          ? placeTypes.map((e) => e.toString()).toList()
          : const <String>[];
      if (types.any((t) => t == 'place')) {
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

    if (parts.isNotEmpty) {
      return withoutPincode(parts.join(', '));
    }

    final placeName = feature['place_name']?.toString().trim();
    if (placeName == null || placeName.isEmpty) return null;
    return withoutPincode(placeName);
  }

  /// Returns "Area, City" (no pincode / India), or null if lookup fails.
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
        '&types=address,poi,neighborhood,locality,place,district';

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
