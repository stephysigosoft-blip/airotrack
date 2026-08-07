import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../Configs/ApiConfigs.dart';

/// Reverse-geocodes lat/lng to a human-readable place name via Mapbox.
///
/// Prefers street / POI level results so History locations stay accurate to
/// the GPS coordinates (not a coarse Area + City + State label).
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

  /// ~0.1 m precision — avoids merging nearby but distinct GPS points.
  static String _cacheKey(double lat, double lng) =>
      'v3:${lat.toStringAsFixed(6)},${lng.toStringAsFixed(6)}';

  /// Strips postal code and country only — keeps street / area / city / state.
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

    // Keep all meaningful segments (street → state). Do not truncate —
    // truncating to 3 parts was dropping the accurate street / POI label.
    text = parts.join(', ');

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

  /// Most specific label first: street/POI → neighborhood → city → state.
  static String? _placeFromFeature(Map<dynamic, dynamic> feature) {
    String? street;
    String? area;
    String? city;
    String? state;

    final placeTypes = feature['place_type'];
    final types = placeTypes is List
        ? placeTypes.map((e) => e.toString()).toList()
        : const <String>[];
    final primary = feature['text']?.toString().trim();
    final houseNumber = feature['address']?.toString().trim();

    if (primary != null && primary.isNotEmpty) {
      if (types.any((t) => t == 'address')) {
        street = (houseNumber != null && houseNumber.isNotEmpty)
            ? '$houseNumber $primary'
            : primary;
      } else if (types.any((t) => t == 'poi')) {
        street = primary;
      } else if (types.any(
        (t) =>
            t == 'neighborhood' ||
            t == 'locality' ||
            t == 'district' ||
            t == 'place',
      )) {
        if (types.any((t) => t == 'place')) {
          city ??= primary;
        } else {
          area ??= primary;
        }
      } else if (types.any((t) => t == 'region')) {
        state ??= primary;
      } else {
        street ??= primary;
      }
    }

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

        if (id.startsWith('address.') || id.startsWith('street.')) {
          street ??= name;
        } else if (id.startsWith('region.')) {
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

    final parts = <String>[];
    void addUnique(String? value) {
      if (value == null || value.isEmpty) return;
      if (parts.any((p) => p.toLowerCase() == value.toLowerCase())) return;
      parts.add(value);
    }

    addUnique(street);
    addUnique(area);
    addUnique(city);
    addUnique(state);

    if (parts.isNotEmpty) {
      return withoutPincode(parts.join(', '));
    }

    // Fallback: full Mapbox place_name (still stripped of PIN / country).
    final placeName = feature['place_name']?.toString().trim();
    if (placeName == null || placeName.isEmpty) return null;
    return withoutPincode(placeName);
  }

  Future<String?> _queryMapbox(
    double latitude,
    double longitude, {
    required String types,
  }) async {
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
        '&types=$types';

    final response = await _dio.get<Map<String, dynamic>>(url);
    if (response.statusCode != 200 || response.data == null) return null;

    final features = response.data!['features'];
    if (features is! List || features.isEmpty) return null;

    final first = features.first;
    if (first is! Map) return null;

    final place = _placeFromFeature(first);
    if (place == null || place.isEmpty) return null;
    return place;
  }

  /// Returns the most accurate place name for the coordinates, or null.
  ///
  /// Tries street `address` first, then broader types (POI / locality / city).
  Future<String?> reverse(double latitude, double longitude) async {
    if (!latitude.isFinite || !longitude.isFinite) return null;
    if (latitude == 0 && longitude == 0) return null;

    final key = _cacheKey(latitude, longitude);
    final cached = _cache[key];
    if (cached != null && cached.isNotEmpty) return withoutPincode(cached);

    try {
      // 1) Street-level when Mapbox has an address near the point.
      String? place = await _queryMapbox(
        latitude,
        longitude,
        types: 'address',
      );

      // 2) Fall back to POI / neighborhood / city so we still get a label.
      place ??= await _queryMapbox(
        latitude,
        longitude,
        types:
            'address,poi,neighborhood,locality,place,district,region',
      );

      if (place == null || place.isEmpty) return null;

      _cache[key] = place;
      return place;
    } catch (e) {
      debugPrint('[ReverseGeocode] failed for $key: $e');
      return null;
    }
  }
}
