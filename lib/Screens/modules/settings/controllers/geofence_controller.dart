import 'dart:convert';
import 'dart:math' as math;

import 'package:airotrack/Configs/ApiConfigs.dart';
import 'package:airotrack/Configs/DioClient.dart';
import 'package:airotrack/Utils/Utils.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart' hide FormData, MultipartFile, Response;
import 'package:latlong2/latlong.dart';

enum GeofenceShape { circle, rectangle, polygon }

extension GeofenceShapeX on GeofenceShape {
  String get label {
    switch (this) {
      case GeofenceShape.circle:
        return 'Circle';
      case GeofenceShape.rectangle:
        return 'Rectangle';
      case GeofenceShape.polygon:
        return 'Polygon';
    }
  }

  /// API `type` value.
  String get apiType {
    switch (this) {
      case GeofenceShape.circle:
        return 'circle';
      case GeofenceShape.rectangle:
        return 'rectangle';
      case GeofenceShape.polygon:
        return 'polygon';
    }
  }

  IconData get icon {
    switch (this) {
      case GeofenceShape.circle:
        return Icons.circle_outlined;
      case GeofenceShape.rectangle:
        return Icons.crop_square;
      case GeofenceShape.polygon:
        return Icons.pentagon_outlined;
    }
  }
}

class GeofenceVehicleOption {
  final int id;
  final String plateNumber;
  final String imei;

  const GeofenceVehicleOption({
    required this.id,
    required this.plateNumber,
    this.imei = '',
  });

  factory GeofenceVehicleOption.fromApi(Map<String, dynamic> json) {
    return GeofenceVehicleOption(
      id: int.tryParse(json['id']?.toString() ?? '') ?? 0,
      plateNumber:
          (json['vehicle_number'] ?? json['name'] ?? json['plate'] ?? '')
              .toString(),
      imei: (json['imei'] ?? '').toString(),
    );
  }
}

class GeofenceItem {
  final String id;
  final String name;
  final String address;
  final GeofenceShape shape;
  final List<String> vehiclePlates;
  final LatLng center;
  final double radiusMeters;
  final List<LatLng> coordinates;
  final String eventType;
  final String description;
  final int tolerance;

  const GeofenceItem({
    required this.id,
    required this.name,
    required this.address,
    required this.shape,
    this.vehiclePlates = const [],
    required this.center,
    this.radiusMeters = 200,
    this.coordinates = const [],
    this.eventType = 'Entry',
    this.description = '',
    this.tolerance = 5,
  });

  factory GeofenceItem.fromApi(Map<String, dynamic> json) {
    final typeRaw = json['type']?.toString().toLowerCase() ?? 'circle';
    final shape = typeRaw == 'rectangle'
        ? GeofenceShape.rectangle
        : typeRaw == 'polygon'
            ? GeofenceShape.polygon
            : GeofenceShape.circle;

    final coords = <LatLng>[];
    final rawCoords = json['coordinates'];
    if (rawCoords is List) {
      for (final c in rawCoords) {
        if (c is! Map) continue;
        final clat = double.tryParse(c['lat']?.toString() ?? '');
        final clng = double.tryParse(c['lng']?.toString() ?? '');
        if (clat != null && clng != null) {
          coords.add(LatLng(clat, clng));
        }
      }
    }

    final lat = double.tryParse(json['latitude']?.toString() ?? '');
    final lng = double.tryParse(json['longitude']?.toString() ?? '');

    LatLng center;
    if (shape == GeofenceShape.circle && lat != null && lng != null) {
      center = LatLng(lat, lng);
    } else if (coords.isNotEmpty) {
      final avgLat =
          coords.map((p) => p.latitude).reduce((a, b) => a + b) / coords.length;
      final avgLng =
          coords.map((p) => p.longitude).reduce((a, b) => a + b) /
              coords.length;
      center = LatLng(avgLat, avgLng);
    } else {
      center = LatLng(lat ?? 0, lng ?? 0);
    }

    final radiusKm = double.tryParse(json['radius']?.toString() ?? '');
    final radiusM = radiusKm != null ? radiusKm * 1000 : 200.0;

    final tolKm = double.tryParse(json['tolerance']?.toString() ?? '');
    var tolUi = tolKm != null ? (tolKm * 1000).round() : 5;
    if (tolUi <= 0) tolUi = 5;

    final eventCode = json['event_type'];
    String eventLabel = 'Entry';
    if (eventCode == 2 || eventCode?.toString() == '2') eventLabel = 'Exit';
    if (eventCode == 3 || eventCode?.toString() == '3') eventLabel = 'Both';
    if (eventCode == 1 || eventCode?.toString() == '1') eventLabel = 'Entry';

    return GeofenceItem(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      address: json['address']?.toString() ?? '',
      shape: shape,
      center: center,
      radiusMeters: radiusM,
      coordinates: coords,
      eventType: eventLabel,
      description: json['description']?.toString() ?? '',
      tolerance: tolUi,
    );
  }

  GeofenceItem copyWith({
    String? id,
    String? name,
    String? address,
    GeofenceShape? shape,
    List<String>? vehiclePlates,
    LatLng? center,
    double? radiusMeters,
    List<LatLng>? coordinates,
    String? eventType,
    String? description,
    int? tolerance,
  }) {
    return GeofenceItem(
      id: id ?? this.id,
      name: name ?? this.name,
      address: address ?? this.address,
      shape: shape ?? this.shape,
      vehiclePlates: vehiclePlates ?? this.vehiclePlates,
      center: center ?? this.center,
      radiusMeters: radiusMeters ?? this.radiusMeters,
      coordinates: coordinates ?? this.coordinates,
      eventType: eventType ?? this.eventType,
      description: description ?? this.description,
      tolerance: tolerance ?? this.tolerance,
    );
  }
}

class GeofenceController extends GetxController {
  final geofences = <GeofenceItem>[].obs;
  final searchQuery = ''.obs;
  final vehicleSearchQuery = ''.obs;
  final isLoading = false.obs;
  final listError = ''.obs;

  /// Update Vehicles sheet
  final vehicleOptions = <GeofenceVehicleOption>[].obs;
  final selectedVehicleIds = <int>{}.obs;
  final isLoadingVehicles = false.obs;
  final isSyncingVehicles = false.obs;
  final activeVehicleGeofenceId = RxnString();

  /// After a successful sync submit, keep the checked set as source of truth
  /// so unsynced (unchecked) vehicles stay unchecked even if list APIs lag.
  final Map<String, Set<int>> _syncedIdsOverrideByGeofence = {};

  /// Synced IDs when the sheet last loaded (before user edits).
  final Map<String, Set<int>> _baselineSyncedIdsByGeofence = {};

  // Add / Edit form
  final isEditing = false.obs;
  final editingId = RxnString();
  final selectedShape = GeofenceShape.circle.obs;
  final selectedEventType = 'Entry'.obs;
  final selectedTolerance = 5.obs;
  final mapCenter = const LatLng(12.3095, 75.1302).obs;
  final mapZoom = 15.0.obs;
  final fenceNameError = RxnString();
  final isSubmitting = false.obs;

  /// Circle radius in meters (map overlay + API conversion).
  final circleRadiusMeters = 120.0.obs;

  final fenceNameController = TextEditingController();
  final addressController = TextEditingController();
  final descriptionController = TextEditingController();
  final searchPlaceController = TextEditingController();

  Worker? _searchWorker;

  static const eventTypes = ['Entry', 'Exit', 'Both'];
  static const tolerances = [5, 10, 15, 20, 30, 50];

  /// Server already filters by `keyword`; keep a light local pass as well.
  List<GeofenceItem> get filteredGeofences {
    final q = searchQuery.value.trim().toLowerCase();
    if (q.isEmpty) return geofences.toList();
    return geofences
        .where(
          (g) =>
              g.name.toLowerCase().contains(q) ||
              g.address.toLowerCase().contains(q) ||
              g.shape.label.toLowerCase().contains(q),
        )
        .toList();
  }

  List<GeofenceVehicleOption> get filteredVehicleOptions {
    final q = vehicleSearchQuery.value.trim().toLowerCase();
    final all = vehicleOptions.toList();
    if (q.isEmpty) return all;
    return all
        .where(
          (v) =>
              v.plateNumber.toLowerCase().contains(q) ||
              v.imei.toLowerCase().contains(q),
        )
        .toList();
  }

  bool get allVehiclesSelected {
    final list = filteredVehicleOptions;
    if (list.isEmpty) return false;
    return list.every((v) => selectedVehicleIds.contains(v.id));
  }

  /// Map overlay points for rectangle / polygon (and rectangle API corners).
  List<LatLng> shapePointsFor(LatLng center, GeofenceShape shape) {
    switch (shape) {
      case GeofenceShape.circle:
        return const [];
      case GeofenceShape.rectangle:
        return _rectangleCorners(center);
      case GeofenceShape.polygon:
        return _polygonPoints(center);
    }
  }

  /// Two opposite corners for rectangle API payload.
  List<LatLng> rectangleApiCorners(LatLng center) {
    final box = _rectangleCorners(center);
    // Top-left and bottom-right (diagonal pair).
    return [box[0], box[2]];
  }

  List<LatLng> _rectangleCorners(LatLng c) {
    const dLat = 0.0012;
    const dLng = 0.0010;
    return [
      LatLng(c.latitude + dLat, c.longitude - dLng), // NW
      LatLng(c.latitude + dLat, c.longitude + dLng), // NE
      LatLng(c.latitude - dLat, c.longitude + dLng), // SE
      LatLng(c.latitude - dLat, c.longitude - dLng), // SW
    ];
  }

  List<LatLng> _polygonPoints(LatLng c) {
    const r = 0.0013;
    const n = 5;
    return List.generate(n, (i) {
      final a = (2 * math.pi * i / n) - (math.pi / 2);
      return LatLng(
        c.latitude + r * math.cos(a),
        c.longitude + r * math.sin(a) * 1.15,
      );
    });
  }

  int _eventTypeCode(String label) {
    switch (label.toLowerCase()) {
      case 'entry':
        return 1;
      case 'exit':
        return 2;
      case 'both':
      default:
        return 3;
    }
  }

  /// UI tolerance is meters-like (5–50); API sample uses km (0.01).
  String _toleranceForApi(int metersLike) {
    return (metersLike / 1000).toStringAsFixed(3);
  }

  @override
  void onInit() {
    super.onInit();
    fetchGeofences();
    _searchWorker = debounce(
      searchQuery,
      (_) => fetchGeofences(),
      time: const Duration(milliseconds: 450),
    );
  }

  /// GET `geofences?limit=&keyword=`
  Future<void> fetchGeofences({bool force = false}) async {
    if (isLoading.value && !force) return;
    isLoading.value = true;
    listError.value = '';
    try {
      final query = <String, dynamic>{
        'limit': 50,
      };
      final keyword = searchQuery.value.trim();
      if (keyword.isNotEmpty) {
        query['keyword'] = keyword;
      }

      final response = await DioClient().get(
        ApiEndPoints.geofences,
        query: query,
      );

      final raw = response.data;
      if (raw is! Map || raw['status'] != true) {
        final msg = raw is Map
            ? (raw['message']?.toString() ?? 'Failed to load geofences')
            : 'Failed to load geofences';
        listError.value = msg;
        geofences.clear();
        return;
      }

      final data = raw['data'];
      final list = data is Map ? data['geofences'] : null;
      if (list is! List) {
        geofences.clear();
        return;
      }

      final items = <GeofenceItem>[];
      for (final row in list) {
        if (row is Map<String, dynamic>) {
          items.add(GeofenceItem.fromApi(row));
        } else if (row is Map) {
          items.add(GeofenceItem.fromApi(Map<String, dynamic>.from(row)));
        }
      }
      geofences.assignAll(items);
    } catch (e) {
      listError.value = e.toString();
      showErrorMessage(e);
    } finally {
      isLoading.value = false;
    }
  }

  void prepareCreate() {
    isEditing.value = false;
    editingId.value = null;
    selectedShape.value = GeofenceShape.circle;
    selectedEventType.value = 'Entry';
    selectedTolerance.value = 5;
    fenceNameError.value = null;
    isSubmitting.value = false;
    circleRadiusMeters.value = 120;
    fenceNameController.clear();
    addressController.clear();
    descriptionController.clear();
    searchPlaceController.clear();
  }

  void prepareEdit(GeofenceItem item) {
    isEditing.value = true;
    editingId.value = item.id;
    selectedShape.value = item.shape;
    selectedEventType.value = item.eventType;
    final tol = item.tolerance;
    selectedTolerance.value = tolerances.contains(tol)
        ? tol
        : tolerances.reduce(
            (a, b) => (a - tol).abs() <= (b - tol).abs() ? a : b,
          );
    fenceNameError.value = null;
    fenceNameController.text = item.name;
    addressController.text = item.address;
    descriptionController.text = item.description;
    mapCenter.value = item.center;
    circleRadiusMeters.value =
        item.radiusMeters > 0 ? item.radiusMeters : 120;
  }

  /// Local-only delete (no delete API).
  bool deleteGeofence(String id) {
    geofences.removeWhere((g) => g.id == id);
    Get.snackbar(
      'Deleted',
      'Geofence removed',
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: Colors.black87,
      colorText: Colors.white,
      margin: const EdgeInsets.all(12),
      duration: const Duration(seconds: 2),
    );
    return true;
  }

  /// Loads synced + unsynced vehicles, merges list, pre-selects synced.
  Future<void> openUpdateVehicles(GeofenceItem item) async {
    vehicleSearchQuery.value = '';
    activeVehicleGeofenceId.value = item.id;
    selectedVehicleIds.clear();
    vehicleOptions.clear();
    isSyncingVehicles.value = false;
    await loadVehiclesForGeofence(item.id);
  }

  Future<void> loadVehiclesForGeofence(String geofenceId) async {
    isLoadingVehicles.value = true;
    try {
      final results = await Future.wait([
        DioClient().get(
          ApiEndPoints.geofenceSyncedVehicles,
          query: {'geofence_id': geofenceId},
        ),
        DioClient().get(
          ApiEndPoints.geofenceUnsyncedVehicles,
          query: {'geofence_id': geofenceId},
        ),
      ]);

      final apiSynced = _parseVehicleOptions(results[0].data);
      final apiUnsynced = _parseVehicleOptions(results[1].data);

      // Merge all vehicles into one list (dedupe by id).
      final byId = <int, GeofenceVehicleOption>{};
      for (final v in [...apiSynced, ...apiUnsynced]) {
        if (v.id > 0) byId[v.id] = v;
      }

      final apiSyncedIds =
          apiSynced.where((v) => v.id > 0).map((v) => v.id).toSet();
      // Prefer last successful submit so unsynced stay unchecked in UI.
      final syncedIds =
          _syncedIdsOverrideByGeofence[geofenceId] ?? apiSyncedIds;

      final merged = byId.values.toList()
        ..sort((a, b) {
          final aSynced = syncedIds.contains(a.id);
          final bSynced = syncedIds.contains(b.id);
          if (aSynced != bSynced) return aSynced ? -1 : 1;
          return a.plateNumber.compareTo(b.plateNumber);
        });

      vehicleOptions.assignAll(merged);
      selectedVehicleIds
        ..clear()
        ..addAll(syncedIds.where(byId.containsKey));
      selectedVehicleIds.refresh();
      _baselineSyncedIdsByGeofence[geofenceId] =
          Set<int>.from(selectedVehicleIds);
    } catch (e) {
      showErrorMessage(e);
      vehicleOptions.clear();
      selectedVehicleIds.clear();
    } finally {
      isLoadingVehicles.value = false;
    }
  }

  List<GeofenceVehicleOption> _parseVehicleOptions(dynamic raw) {
    if (raw is! Map) return const [];
    if (raw['status'] == false) return const [];

    dynamic list;
    final data = raw['data'];
    if (data is Map) {
      list = data['vehicles'] ?? data['data'] ?? data['list'];
    } else if (data is List) {
      list = data;
    }
    list ??= raw['vehicles'];
    if (list is! List) return const [];

    final out = <GeofenceVehicleOption>[];
    for (final row in list) {
      if (row is Map<String, dynamic>) {
        final v = GeofenceVehicleOption.fromApi(row);
        if (v.id > 0) out.add(v);
      } else if (row is Map) {
        final v = GeofenceVehicleOption.fromApi(Map<String, dynamic>.from(row));
        if (v.id > 0) out.add(v);
      }
    }
    return out;
  }

  void toggleVehicle(int vehicleId) {
    if (selectedVehicleIds.contains(vehicleId)) {
      selectedVehicleIds.remove(vehicleId);
    } else {
      selectedVehicleIds.add(vehicleId);
    }
    selectedVehicleIds.refresh();
  }

  void toggleSelectAllVehicles() {
    final list = filteredVehicleOptions;
    if (allVehiclesSelected) {
      selectedVehicleIds.removeWhere((id) => list.any((v) => v.id == id));
    } else {
      selectedVehicleIds.addAll(list.map((v) => v.id));
    }
    selectedVehicleIds.refresh();
  }

  /// POST `sync_geofence_vehicles` — replaces synced vehicles with the checked list.
  /// Checked → synced; unchecked (omitted from vehicle_ids) → unsynced.
  Future<void> submitVehicleUpdate(GeofenceItem item) async {
    if (isSyncingVehicles.value) return;
    isSyncingVehicles.value = true;
    try {
      // Only checked vehicles are sent → those stay/become synced.
      // When none are checked, vehicle_ids must still be present (API `required`).
      final ids = selectedVehicleIds.toList()..sort();
      final previous = Set<int>.from(
        _baselineSyncedIdsByGeofence[item.id] ?? const <int>{},
      );

      final response = await _postSyncGeofenceVehicles(
        geofenceId: item.id,
        vehicleIds: ids,
        previouslySynced: previous,
      );

      final raw = response.data;
      final statusCode = response.statusCode;
      final ok = raw is Map
          ? (raw['status'] == true || raw['success'] == true)
          : statusCode == 200;

      if (!ok) {
        final msg = raw is Map
            ? (raw['message']?.toString() ?? 'Failed to update vehicles')
            : 'Failed to update vehicles';
        showErrorMessage(msg);
        return;
      }

      // Keep submitted selection so unchecked vehicles stay unsynced in UI.
      _syncedIdsOverrideByGeofence[item.id] = ids.toSet();
      _baselineSyncedIdsByGeofence[item.id] = ids.toSet();

      final plates = vehicleOptions
          .where((v) => ids.contains(v.id))
          .map((v) => v.plateNumber)
          .toList();
      final index = geofences.indexWhere((g) => g.id == item.id);
      if (index >= 0) {
        geofences[index] = geofences[index].copyWith(vehiclePlates: plates);
      }

      final next = ids.toSet();
      final added = next.difference(previous);
      final removed = previous.difference(next);

      final String toastMessage;
      if (added.isNotEmpty && removed.isEmpty) {
        toastMessage = 'Synced vehicles for ${item.name}';
      } else if (removed.isNotEmpty && added.isEmpty) {
        toastMessage = 'Unsynced vehicles for ${item.name}';
      } else {
        toastMessage = 'Vehicles updated for ${item.name}';
      }

      await loadVehiclesForGeofence(item.id);

      Get.back();
      Get.snackbar(
        'Updated',
        toastMessage,
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.black87,
        colorText: Colors.white,
        margin: const EdgeInsets.all(12),
        duration: const Duration(seconds: 2),
      );
    } catch (e) {
      showErrorMessage(e);
    } finally {
      isSyncingVehicles.value = false;
    }
  }

  /// Sync request.
  ///
  /// Note: `sync_geofence_vehicles` uses Laravel `required|array` on
  /// `vehicle_ids`, which **rejects empty arrays**. So clearing the last
  /// vehicle is done via the reverse API (`sync_vehicle_geofences`) instead.
  Future<Response> _postSyncGeofenceVehicles({
    required String geofenceId,
    required List<int> vehicleIds,
    required Set<int> previouslySynced,
  }) async {
    if (vehicleIds.isEmpty) {
      await _unsyncAllVehiclesFromGeofence(
        geofenceId: geofenceId,
        vehicleIds: previouslySynced.toList(),
      );
      return Response(
        requestOptions: RequestOptions(path: ApiEndPoints.syncGeofenceVehicles),
        data: const {'status': true, 'message': 'Unsynced'},
        statusCode: 200,
      );
    }

    final formData = FormData();
    formData.fields.add(MapEntry('geofence_id', geofenceId));
    for (var i = 0; i < vehicleIds.length; i++) {
      formData.fields.add(
        MapEntry('vehicle_ids[$i]', vehicleIds[i].toString()),
      );
    }
    return DioClient().post(
      ApiEndPoints.syncGeofenceVehicles,
      body: formData,
    );
  }

  /// Detach each vehicle from [geofenceId] by rewriting that vehicle's
  /// geofence list without this fence (`sync_vehicle_geofences`).
  Future<void> _unsyncAllVehiclesFromGeofence({
    required String geofenceId,
    required List<int> vehicleIds,
  }) async {
    for (final vehicleId in vehicleIds) {
      await _removeGeofenceFromVehicle(
        vehicleId: vehicleId,
        geofenceId: geofenceId,
      );
    }
  }

  Future<void> _removeGeofenceFromVehicle({
    required int vehicleId,
    required String geofenceId,
  }) async {
    final syncedResponse = await DioClient().get(
      ApiEndPoints.vehicleSyncedGeofences,
      query: {'vehicle_id': vehicleId.toString()},
    );
    final remaining = _parseGeofenceIds(syncedResponse.data)
        .where((id) => id.toString() != geofenceId)
        .toList();

    if (remaining.isEmpty) {
      // Last geofence for this vehicle — must send an empty list.
      // `sync_geofence_vehicles` rejects `vehicle_ids: []` (Laravel `required`),
      // so clear via the reverse endpoint instead.
      await _syncVehicleGeofences(vehicleId: vehicleId, geofenceIds: const []);
      return;
    }

    await _syncVehicleGeofences(
      vehicleId: vehicleId,
      geofenceIds: remaining,
    );
  }

  Future<void> _syncVehicleGeofences({
    required int vehicleId,
    required List<int> geofenceIds,
  }) async {
    if (geofenceIds.isEmpty) {
      // Prefer JSON empty array; fall back to multipart with only vehicle_id.
      try {
        final jsonResponse = await DioClient().post(
          ApiEndPoints.syncVehicleGeofences,
          body: jsonEncode({
            'vehicle_id': vehicleId,
            'geofence_ids': <int>[],
          }),
          options: Options(
            contentType: Headers.jsonContentType,
            headers: <String, dynamic>{
              Headers.contentTypeHeader: Headers.jsonContentType,
            },
          ),
        );
        if (_isVehicleSyncSuccess(jsonResponse)) return;
      } catch (_) {
        // Fall through.
      }

      final formData = FormData();
      formData.fields.add(MapEntry('vehicle_id', vehicleId.toString()));
      final formResponse = await DioClient().post(
        ApiEndPoints.syncVehicleGeofences,
        body: formData,
      );
      if (_isVehicleSyncSuccess(formResponse)) return;

      final msg = formResponse.data is Map
          ? (formResponse.data['message']?.toString() ??
              'Failed to unsync vehicle')
          : 'Failed to unsync vehicle';
      throw msg;
    }

    final formData = FormData();
    formData.fields.add(MapEntry('vehicle_id', vehicleId.toString()));
    for (var i = 0; i < geofenceIds.length; i++) {
      formData.fields.add(
        MapEntry('geofence_ids[$i]', geofenceIds[i].toString()),
      );
    }
    final response = await DioClient().post(
      ApiEndPoints.syncVehicleGeofences,
      body: formData,
    );
    if (_isVehicleSyncSuccess(response)) return;

    final msg = response.data is Map
        ? (response.data['message']?.toString() ?? 'Failed to unsync vehicle')
        : 'Failed to unsync vehicle';
    throw msg;
  }

  List<int> _parseGeofenceIds(dynamic raw) {
    if (raw is! Map) return [];
    final data = raw['data'];
    dynamic list;
    if (data is Map) {
      list = data['geofences'] ?? data['list'] ?? data['data'];
    } else if (data is List) {
      list = data;
    }
    if (list is! List) return [];

    final ids = <int>[];
    for (final item in list) {
      if (item is! Map) continue;
      final id = item['id'];
      if (id is int) {
        ids.add(id);
      } else if (id != null) {
        final parsed = int.tryParse(id.toString());
        if (parsed != null) ids.add(parsed);
      }
    }
    return ids;
  }

  bool _isVehicleSyncSuccess(Response response) {
    final raw = response.data;
    if (raw is Map) {
      return raw['status'] == true || raw['success'] == true;
    }
    return response.statusCode == 200;
  }

  FormData _buildGeofenceFormData({
    required String name,
    required String address,
    required String description,
  }) {
    final shape = selectedShape.value;
    final center = mapCenter.value;
    final formData = FormData();

    void field(String key, String value) {
      formData.fields.add(MapEntry(key, value));
    }

    field('name', name);
    field('type', shape.apiType);
    field('tolerance', _toleranceForApi(selectedTolerance.value));
    field('event_type', _eventTypeCode(selectedEventType.value).toString());
    field('address', address);
    field('description', description);
    field('is_active', '1');

    switch (shape) {
      case GeofenceShape.circle:
        field('latitude', center.latitude.toStringAsFixed(8));
        field('longitude', center.longitude.toStringAsFixed(8));
        field(
          'radius',
          (circleRadiusMeters.value / 1000).toStringAsFixed(4),
        );
        break;
      case GeofenceShape.rectangle:
        final corners = rectangleApiCorners(center);
        for (var i = 0; i < corners.length; i++) {
          field('coordinates[$i][lat]', corners[i].latitude.toStringAsFixed(6));
          field(
            'coordinates[$i][lng]',
            corners[i].longitude.toStringAsFixed(6),
          );
        }
        break;
      case GeofenceShape.polygon:
        final points = _polygonPoints(center);
        for (var i = 0; i < points.length; i++) {
          field('coordinates[$i][lat]', points[i].latitude.toStringAsFixed(6));
          field(
            'coordinates[$i][lng]',
            points[i].longitude.toStringAsFixed(6),
          );
        }
        break;
    }

    return formData;
  }

  /// Create uses API; Edit is local-only (no update API).
  Future<bool> submitGeofenceForm() async {
    final name = fenceNameController.text.trim();
    if (name.isEmpty) {
      fenceNameError.value = 'Geofence name is required';
      return false;
    }
    fenceNameError.value = null;

    final address = addressController.text.trim().isEmpty
        ? name
        : addressController.text.trim();
    final description = descriptionController.text.trim();

    if (isEditing.value) {
      return _submitLocalEdit(
        name: name,
        address: address,
        description: description,
      );
    }

    if (isSubmitting.value) return false;
    isSubmitting.value = true;

    try {
      final response = await DioClient().post(
        ApiEndPoints.addGeofence,
        body: _buildGeofenceFormData(
          name: name,
          address: address,
          description: description,
        ),
      );

      final raw = response.data;
      final ok = raw is Map
          ? (raw['status'] == true || raw['success'] == true)
          : response.statusCode == 200;

      if (!ok) {
        final msg = raw is Map
            ? (raw['message']?.toString() ?? 'Failed to create geofence')
            : 'Failed to create geofence';
        showErrorMessage(msg);
        return false;
      }

      await fetchGeofences(force: true);

      Get.snackbar(
        'Success',
        (raw is Map ? raw['message']?.toString() : null) ??
            'Geofence created',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.green,
        colorText: Colors.white,
        margin: const EdgeInsets.all(12),
        duration: const Duration(seconds: 2),
      );
      return true;
    } catch (e) {
      showErrorMessage(e);
      return false;
    } finally {
      isSubmitting.value = false;
    }
  }

  bool _submitLocalEdit({
    required String name,
    required String address,
    required String description,
  }) {
    final index = geofences.indexWhere((g) => g.id == editingId.value);
    if (index < 0) return true;

    final existing = geofences[index];
    final shape = selectedShape.value;
    final center = mapCenter.value;
    geofences[index] = existing.copyWith(
      name: name,
      address: address,
      shape: shape,
      center: center,
      radiusMeters: circleRadiusMeters.value,
      coordinates: shape == GeofenceShape.circle
          ? const []
          : shape == GeofenceShape.rectangle
              ? rectangleApiCorners(center)
              : _polygonPoints(center),
      eventType: selectedEventType.value,
      description: description,
      tolerance: selectedTolerance.value,
    );

    Get.snackbar(
      'Updated',
      'Geofence updated',
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: Colors.green,
      colorText: Colors.white,
      margin: const EdgeInsets.all(12),
      duration: const Duration(seconds: 2),
    );
    return true;
  }

  @override
  void onClose() {
    _searchWorker?.dispose();
    fenceNameController.dispose();
    addressController.dispose();
    descriptionController.dispose();
    searchPlaceController.dispose();
    super.onClose();
  }
}
