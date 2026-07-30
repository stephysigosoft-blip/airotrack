/// Response model for vehicle history API.
class HistoryModel {
  final bool? status;
  final HistoryData? data;

  const HistoryModel({
    this.status,
    this.data,
  });

  factory HistoryModel.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const HistoryModel();
    return HistoryModel(
      status: json['status'] as bool?,
      data: json['data'] != null
          ? HistoryData.fromJson(json['data'] as Map<String, dynamic>?)
          : null,
    );
  }
}

class HistoryData {
  final VehicleInfo? vehicleInfo;
  final List<LocationHistoryItem>? locationHistory;
  final HistoryKilometerStatistics? kilometerStatistics;
  final HistoryVehicleTiming? vehicleTiming;
  final HistorySpeedStatistics? speedStatistics;
  final HistoryStopAnalysis? stopAnalysis;

  const HistoryData({
    this.vehicleInfo,
    this.locationHistory,
    this.kilometerStatistics,
    this.vehicleTiming,
    this.speedStatistics,
    this.stopAnalysis,
  });

  factory HistoryData.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const HistoryData();
    final rawList = json['location_history'];
    return HistoryData(
      vehicleInfo: json['vehicle_info'] != null
          ? VehicleInfo.fromJson(
              json['vehicle_info'] as Map<String, dynamic>?,
            )
          : null,
      locationHistory: rawList is List
          ? (rawList)
              .map(
                (e) => LocationHistoryItem.fromJson(
                  e is Map<String, dynamic> ? e : null,
                ),
              )
              .toList()
          : null,
      kilometerStatistics: json['kilometer_statistics'] is Map<String, dynamic>
          ? HistoryKilometerStatistics.fromJson(
              json['kilometer_statistics'] as Map<String, dynamic>,
            )
          : null,
      vehicleTiming: json['vehicle_timing'] is Map<String, dynamic>
          ? HistoryVehicleTiming.fromJson(
              json['vehicle_timing'] as Map<String, dynamic>,
            )
          : null,
      speedStatistics: json['speed_statistics'] is Map<String, dynamic>
          ? HistorySpeedStatistics.fromJson(
              json['speed_statistics'] as Map<String, dynamic>,
            )
          : null,
      stopAnalysis: json['stop_analysis'] is Map<String, dynamic>
          ? HistoryStopAnalysis.fromJson(
              json['stop_analysis'] as Map<String, dynamic>,
            )
          : null,
    );
  }
}

class HistoryStopAnalysis {
  final int? totalStops;
  final num? totalStopDuration;
  final List<HistoryStopLocation> stopLocations;

  const HistoryStopAnalysis({
    this.totalStops,
    this.totalStopDuration,
    this.stopLocations = const [],
  });

  factory HistoryStopAnalysis.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const HistoryStopAnalysis();
    final rawStops = json['stop_locations'];
    final stops = <HistoryStopLocation>[];
    if (rawStops is List) {
      for (final item in rawStops) {
        if (item is! Map) continue;
        final stop = HistoryStopLocation.fromJson(
          Map<String, dynamic>.from(item),
        );
        if (stop.hasValidCoordinates) stops.add(stop);
      }
    }
    final total = json['total_stops'];
    final duration = json['total_stop_duration'];
    return HistoryStopAnalysis(
      totalStops: total is int ? total : int.tryParse(total?.toString() ?? ''),
      totalStopDuration: duration is num
          ? duration
          : num.tryParse(duration?.toString() ?? ''),
      stopLocations: stops,
    );
  }
}

/// One stop along the history route (`stop_analysis.stop_locations[]`).
class HistoryStopLocation {
  final double latitude;
  final double longitude;
  /// Map marker position (snapped onto the blue traveled line when available).
  final double? mapLatitude;
  final double? mapLongitude;
  final String? arrivalTime;
  final String? departureTime;
  final String? duration;
  final String? address;
  final int? index;

  const HistoryStopLocation({
    required this.latitude,
    required this.longitude,
    this.mapLatitude,
    this.mapLongitude,
    this.arrivalTime,
    this.departureTime,
    this.duration,
    this.address,
    this.index,
  });

  /// Point used for the map marker (prefer road-snapped coords).
  double get markerLatitude => mapLatitude ?? latitude;
  double get markerLongitude => mapLongitude ?? longitude;

  bool get hasValidCoordinates =>
      latitude.abs() <= 90 &&
      longitude.abs() <= 180 &&
      !(latitude == 0 && longitude == 0);

  HistoryStopLocation copyWith({
    double? latitude,
    double? longitude,
    double? mapLatitude,
    double? mapLongitude,
    String? arrivalTime,
    String? departureTime,
    String? duration,
    String? address,
    int? index,
  }) {
    return HistoryStopLocation(
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      mapLatitude: mapLatitude ?? this.mapLatitude,
      mapLongitude: mapLongitude ?? this.mapLongitude,
      arrivalTime: arrivalTime ?? this.arrivalTime,
      departureTime: departureTime ?? this.departureTime,
      duration: duration ?? this.duration,
      address: address ?? this.address,
      index: index ?? this.index,
    );
  }

  factory HistoryStopLocation.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const HistoryStopLocation(latitude: 0, longitude: 0);
    }

    double? parseCoord(dynamic v) {
      if (v is num) return v.toDouble();
      return double.tryParse(v?.toString() ?? '');
    }

    String? pickString(List<String> keys) {
      for (final key in keys) {
        final value = json[key];
        if (value == null) continue;
        final text = value.toString().trim();
        if (text.isEmpty || text.toLowerCase() == 'null') continue;
        return text;
      }
      return null;
    }

    var lat = parseCoord(
          json['latitude'] ?? json['lat'] ?? json['stop_latitude'],
        ) ??
        0.0;
    var lng = parseCoord(
          json['longitude'] ??
              json['lng'] ??
              json['lon'] ??
              json['stop_longitude'],
        ) ??
        0.0;

    // Nested location / position / coordinates objects.
    for (final key in ['location', 'position', 'coordinates', 'geo']) {
      final nested = json[key];
      if (nested is! Map) continue;
      final m = Map<String, dynamic>.from(nested);
      lat = parseCoord(m['latitude'] ?? m['lat']) ?? lat;
      lng = parseCoord(m['longitude'] ?? m['lng'] ?? m['lon']) ?? lng;
    }

    final durationRaw = json['duration'] ??
        json['stop_duration'] ??
        json['duration_seconds'] ??
        json['duration_text'] ??
        json['stop_time'] ??
        json['total_duration'];

    String? durationText;
    if (durationRaw is num) {
      durationText = HistoryStopLocation.formatDurationSeconds(durationRaw);
    } else if (durationRaw != null) {
      final asNum = num.tryParse(durationRaw.toString());
      durationText = asNum != null
          ? HistoryStopLocation.formatDurationSeconds(asNum)
          : durationRaw.toString().trim();
    }

    final indexRaw = json['index'] ?? json['stop_index'] ?? json['stop_number'];
    final index = indexRaw is int
        ? indexRaw
        : int.tryParse(indexRaw?.toString() ?? '');

    return HistoryStopLocation(
      latitude: lat,
      longitude: lng,
      arrivalTime: pickString([
        'arrival_time',
        'arrived_at',
        'start_time',
        'stop_start_time',
        'from_time',
        'key_off',
        'devicetime',
        'device_time',
      ]),
      departureTime: pickString([
        'departure_time',
        'departed_at',
        'end_time',
        'stop_end_time',
        'to_time',
        'key_on',
        'next_key_on',
      ]),
      duration: durationText,
      address: pickString([
        'address',
        'location_address',
        'place',
        'formatted_address',
        'stop_address',
      ]),
      index: index,
    );
  }

  static String formatDurationSeconds(num seconds) {
    final total = seconds.round().clamp(0, 24 * 3600 * 30);
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    return '$h h $m m';
  }
}

class HistoryKilometerStatistics {
  final num? totalKilometersTraveled;

  const HistoryKilometerStatistics({this.totalKilometersTraveled});

  factory HistoryKilometerStatistics.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const HistoryKilometerStatistics();
    final raw = json['total_kilometers_traveled'];
    return HistoryKilometerStatistics(
      totalKilometersTraveled: raw is num
          ? raw
          : num.tryParse(raw?.toString() ?? ''),
    );
  }
}

class HistoryVehicleTiming {
  final String? vehicleStartTime;
  final String? vehicleEndTime;
  /// Optional ready-made duration from API (seconds or `HH:MM:SS` text).
  final String? totalDuration;

  const HistoryVehicleTiming({
    this.vehicleStartTime,
    this.vehicleEndTime,
    this.totalDuration,
  });

  factory HistoryVehicleTiming.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const HistoryVehicleTiming();

    String? pick(List<String> keys) {
      for (final key in keys) {
        final value = json[key];
        if (value == null) continue;
        final text = value.toString().trim();
        if (text.isEmpty || text.toLowerCase() == 'null') continue;
        return text;
      }
      return null;
    }

    return HistoryVehicleTiming(
      vehicleStartTime: pick([
        'vehicle_start_time',
        'start_time',
        'trip_start_time',
        'start',
      ]),
      vehicleEndTime: pick([
        'vehicle_end_time',
        'end_time',
        'trip_end_time',
        'end',
      ]),
      totalDuration: pick([
        'total_duration',
        'duration',
        'trip_duration',
        'elapsed_time',
        'running_duration',
      ]),
    );
  }
}

class HistorySpeedStatistics {
  final num? averageSpeed;
  final num? maximumSpeed;

  const HistorySpeedStatistics({
    this.averageSpeed,
    this.maximumSpeed,
  });

  factory HistorySpeedStatistics.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const HistorySpeedStatistics();
    final avg = json['average_speed'];
    final max = json['maximum_speed'];
    return HistorySpeedStatistics(
      averageSpeed: avg is num ? avg : num.tryParse(avg?.toString() ?? ''),
      maximumSpeed: max is num ? max : num.tryParse(max?.toString() ?? ''),
    );
  }
}

class VehicleInfo {
  final int? id;
  final String? vehicleNumber;
  final String? imei;
  final int? ignition;
  final int? power;
  final int? gnssFix;
  final String? lastUpdate;
  final String? latitude;
  final String? longitude;
  final String? mode;
  final num? speed;
  final String? expirationTime;

  const VehicleInfo({
    this.id,
    this.vehicleNumber,
    this.imei,
    this.ignition,
    this.power,
    this.gnssFix,
    this.lastUpdate,
    this.latitude,
    this.longitude,
    this.mode,
    this.speed,
    this.expirationTime,
  });

  factory VehicleInfo.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const VehicleInfo();
    return VehicleInfo(
      id: json['id'] as int?,
      vehicleNumber: json['vehicle_number'] as String?,
      imei: json['imei'] as String?,
      ignition: json['ignition'] as int?,
      power: json['power'] as int?,
      gnssFix: json['gnss_fix'] as int?,
      lastUpdate: json['last_update'] as String?,
      latitude: json['latitude'] as String?,
      longitude: json['longitude'] as String?,
      mode: json['mode'] as String?,
      speed: json['speed'] as num?,
      expirationTime: json['expirationtime'] as String?,
    );
  }
}

class LocationHistoryItem {
  final String? imei;
  final String? deviceTime;
  final String? latitude;
  final String? longitude;
  final String? speed;
  final String? mode;
  final String? ignition;
  final String? power;
  final String? alertId;
  final String? createdAt;
  final bool? isStopped;

  const LocationHistoryItem({
    this.imei,
    this.deviceTime,
    this.latitude,
    this.longitude,
    this.speed,
    this.mode,
    this.ignition,
    this.power,
    this.alertId,
    this.createdAt,
    this.isStopped,
  });

  factory LocationHistoryItem.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const LocationHistoryItem();
    return LocationHistoryItem(
      imei: json['imei'] as String?,
      deviceTime: json['devicetime'] as String?,
      latitude: json['latitude'] as String?,
      longitude: json['longitude'] as String?,
      speed: json['speed']?.toString(),
      mode: json['mode'] as String?,
      ignition: json['ignition']?.toString(),
      power: json['power']?.toString(),
      alertId: json['alert_id'] as String?,
      createdAt: json['created_at'] as String?,
      isStopped: json['is_stopped'] as bool?,
    );
  }
}
