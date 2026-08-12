import 'dart:convert';

import 'package:airotrack/Configs/ApiConfigs.dart';
import 'package:airotrack/Configs/DioClient.dart';
import 'package:airotrack/Utils/Utils.dart';
import 'package:airotrack/Utils/app_colors.dart';
import 'package:dio/dio.dart' as dio;
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class SelectableGeofence {
  final String id;
  final String name;
  final String location;

  const SelectableGeofence({
    required this.id,
    required this.name,
    required this.location,
  });
}

/// Live Track — Select Geofence bottom sheet (Add Geofence action).
/// Lists [vehicle_synced_geofences] + [vehicle_unsynced_geofences],
/// multi-select, submit via [sync_vehicle_geofences].
Future<void> showSelectGeofenceSheet(
  BuildContext context, {
  int? vehicleId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _SelectGeofenceSheet(vehicleId: vehicleId),
  );
}

class _SelectGeofenceSheet extends StatefulWidget {
  final int? vehicleId;

  const _SelectGeofenceSheet({this.vehicleId});

  @override
  State<_SelectGeofenceSheet> createState() => _SelectGeofenceSheetState();
}

class _SelectGeofenceSheetState extends State<_SelectGeofenceSheet> {
  static const _selectedBg = Color(0xFFB8EAF8);
  static const _selectedBorder = Color(0xFF5BC4E8);
  static const _titleColor = Color(0xFF1B2A4A);
  static const _subtitleColor = Color(0xFF7A97A8);

  final _searchController = TextEditingController();
  final _allGeofences = <SelectableGeofence>[];
  final _selectedIds = <String>{};
  /// Synced geofence ids when the sheet opened (for unsync-all).
  final _baselineSyncedIds = <String>{};

  String _query = '';
  bool _loading = true;
  bool _submitting = false;
  String? _error;

  List<SelectableGeofence> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _allGeofences;
    return _allGeofences
        .where(
          (g) =>
              g.name.toLowerCase().contains(q) ||
              g.location.toLowerCase().contains(q),
        )
        .toList();
  }

  @override
  void initState() {
    super.initState();
    _loadGeofences();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadGeofences() async {
    final vehicleId = widget.vehicleId;
    if (vehicleId == null || vehicleId <= 0) {
      setState(() {
        _loading = false;
        _error = 'Vehicle id not available. Open Live Track again.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        DioClient().get(
          ApiEndPoints.vehicleSyncedGeofences,
          query: {'vehicle_id': vehicleId.toString()},
        ),
        DioClient().get(
          ApiEndPoints.vehicleUnsyncedGeofences,
          query: {'vehicle_id': vehicleId.toString()},
        ),
      ]);

      final synced = _parseGeofenceList(results[0].data);
      final unsynced = _parseGeofenceList(results[1].data);

      final byId = <String, SelectableGeofence>{};
      for (final g in [...synced, ...unsynced]) {
        byId.putIfAbsent(g.id, () => g);
      }

      _allGeofences
        ..clear()
        ..addAll(byId.values);

      _baselineSyncedIds
        ..clear()
        ..addAll(synced.map((g) => g.id));

      _selectedIds
        ..clear()
        ..addAll(synced.map((g) => g.id));
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<SelectableGeofence> _parseGeofenceList(dynamic raw) {
    if (raw is! Map) return [];
    final data = raw['data'];
    dynamic list;
    if (data is Map) {
      list = data['geofences'] ?? data['list'] ?? data['data'];
    } else if (data is List) {
      list = data;
    }
    if (list is! List) return [];

    final items = <SelectableGeofence>[];
    for (final item in list) {
      if (item is! Map) continue;
      final id = item['id']?.toString() ?? '';
      if (id.isEmpty) continue;
      final name = (item['name'] ?? '').toString().trim();
      final address =
          (item['address'] ?? item['location'] ?? '').toString().trim();
      items.add(
        SelectableGeofence(
          id: id,
          name: name.isEmpty ? 'Geofence $id' : name,
          location: address.isEmpty ? 'No address' : address,
        ),
      );
    }
    return items;
  }

  void _toggle(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  Future<void> _onSubmit() async {
    if (_submitting) return;
    final vehicleId = widget.vehicleId;
    if (vehicleId == null || vehicleId <= 0) {
      showErrorMessage('Vehicle id not available');
      return;
    }

    setState(() => _submitting = true);
    try {
      final ids = _selectedIds.toList()..sort();

      if (ids.isEmpty) {
        // `sync_vehicle_geofences` rejects `geofence_ids: []` (Laravel
        // `required|array`). Unsync by removing this vehicle from each
        // previously synced geofence via `sync_geofence_vehicles`.
        await _unsyncAllGeofencesFromVehicle(
          vehicleId: vehicleId,
          geofenceIds: _baselineSyncedIds.toList(),
        );
      } else {
        final response = await _postSyncVehicleGeofences(
          vehicleId: vehicleId,
          geofenceIds: ids,
        );
        final raw = response.data;
        final ok = raw is Map
            ? (raw['status'] == true || raw['success'] == true)
            : response.statusCode == 200;
        if (!ok) {
          final msg = raw is Map
              ? (raw['message']?.toString() ?? 'Failed to sync geofences')
              : 'Failed to sync geofences';
          showErrorMessage(msg);
          return;
        }
      }

      if (!mounted) return;
      Get.back();
      Get.snackbar(
        'Updated',
        ids.isEmpty
            ? 'Geofences unsynced for vehicle'
            : 'Geofences synced for vehicle',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.black87,
        colorText: Colors.white,
        margin: const EdgeInsets.all(12),
        duration: const Duration(seconds: 2),
      );
    } catch (e) {
      showErrorMessage(e);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// Detach [vehicleId] from each geofence by rewriting that geofence's
  /// vehicle list without this vehicle (`sync_geofence_vehicles`).
  Future<void> _unsyncAllGeofencesFromVehicle({
    required int vehicleId,
    required List<String> geofenceIds,
  }) async {
    if (geofenceIds.isEmpty) return;

    for (final geofenceId in geofenceIds) {
      await _removeVehicleFromGeofence(
        vehicleId: vehicleId,
        geofenceId: geofenceId,
      );
    }
  }

  Future<void> _removeVehicleFromGeofence({
    required int vehicleId,
    required String geofenceId,
  }) async {
    final syncedResponse = await DioClient().get(
      ApiEndPoints.geofenceSyncedVehicles,
      query: {'geofence_id': geofenceId},
    );
    final remaining = _parseVehicleIds(syncedResponse.data)
        .where((id) => id != vehicleId)
        .toList();

    await _postSyncGeofenceVehicles(
      geofenceId: geofenceId,
      vehicleIds: remaining,
    );
  }

  List<int> _parseVehicleIds(dynamic raw) {
    if (raw is! Map) return [];
    final data = raw['data'];
    dynamic list;
    if (data is Map) {
      list = data['vehicles'] ?? data['list'] ?? data['data'];
    } else if (data is List) {
      list = data;
    }
    if (list is! List) return [];

    final ids = <int>[];
    for (final item in list) {
      if (item is! Map) continue;
      final id = int.tryParse(item['id']?.toString() ?? '');
      if (id != null) ids.add(id);
    }
    return ids;
  }

  Future<void> _postSyncGeofenceVehicles({
    required String geofenceId,
    required List<int> vehicleIds,
  }) async {
    if (vehicleIds.isEmpty) {
      // Same Laravel rule: empty `vehicle_ids` fails `required|array`.
      // Try JSON []; if that fails, multipart with only geofence_id.
      try {
        final jsonResponse = await DioClient().post(
          ApiEndPoints.syncGeofenceVehicles,
          body: jsonEncode({
            'geofence_id': geofenceId,
            'vehicle_ids': <int>[],
          }),
          options: dio.Options(
            contentType: dio.Headers.jsonContentType,
            headers: <String, dynamic>{
              dio.Headers.contentTypeHeader: dio.Headers.jsonContentType,
            },
          ),
        );
        if (_isOk(jsonResponse)) return;
      } catch (_) {}

      try {
        final formData = dio.FormData();
        formData.fields.add(MapEntry('geofence_id', geofenceId));
        final formResponse = await DioClient().post(
          ApiEndPoints.syncGeofenceVehicles,
          body: formData,
        );
        if (_isOk(formResponse)) return;
        final msg = formResponse.data is Map
            ? (formResponse.data['message']?.toString() ??
                'Failed to unsync geofence')
            : 'Failed to unsync geofence';
        throw msg;
      } catch (e) {
        // Last link on this geofence: backend rejects empty vehicle_ids.
        // Fall through — still try so other geofences can be cleared.
        rethrow;
      }
    }

    final formData = dio.FormData();
    formData.fields.add(MapEntry('geofence_id', geofenceId));
    for (var i = 0; i < vehicleIds.length; i++) {
      formData.fields.add(
        MapEntry('vehicle_ids[$i]', vehicleIds[i].toString()),
      );
    }
    final response = await DioClient().post(
      ApiEndPoints.syncGeofenceVehicles,
      body: formData,
    );
    if (_isOk(response)) return;

    final msg = response.data is Map
        ? (response.data['message']?.toString() ?? 'Failed to unsync geofence')
        : 'Failed to unsync geofence';
    throw msg;
  }

  bool _isOk(dio.Response response) {
    final raw = response.data;
    if (raw is Map) {
      return raw['status'] == true || raw['success'] == true;
    }
    return response.statusCode == 200;
  }

  Future<dio.Response> _postSyncVehicleGeofences({
    required int vehicleId,
    required List<String> geofenceIds,
  }) async {
    final formData = dio.FormData();
    formData.fields.add(MapEntry('vehicle_id', vehicleId.toString()));
    for (var i = 0; i < geofenceIds.length; i++) {
      formData.fields.add(MapEntry('geofence_ids[$i]', geofenceIds[i]));
    }
    return DioClient().post(
      ApiEndPoints.syncVehicleGeofences,
      body: formData,
    );
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * 0.72;
    final filtered = _filtered;

    return Material(
      color: Colors.white,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: height,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Select Geofence',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Get.back(),
                    icon: const Icon(Icons.close, color: Colors.black54),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                height: 46,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Row(
                  children: [
                    Icon(Icons.search, color: Colors.grey.shade400, size: 22),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        onChanged: (v) => setState(() => _query = v),
                        decoration: const InputDecoration(
                          hintText: 'Search geofences',
                          hintStyle:
                              TextStyle(color: Colors.grey, fontSize: 14),
                          border: InputBorder.none,
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _error!,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(color: Colors.black54),
                                ),
                                const SizedBox(height: 12),
                                TextButton(
                                  onPressed: _loadGeofences,
                                  child: const Text('Retry'),
                                ),
                              ],
                            ),
                          ),
                        )
                      : filtered.isEmpty
                          ? const Center(
                              child: Text(
                                'No geofences found',
                                style: TextStyle(color: Colors.black54),
                              ),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                              itemCount: filtered.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (context, index) {
                                final item = filtered[index];
                                final selected =
                                    _selectedIds.contains(item.id);

                                return Material(
                                  color: Colors.transparent,
                                  borderRadius: BorderRadius.circular(16),
                                  child: InkWell(
                                    onTap: () => _toggle(item.id),
                                    borderRadius: BorderRadius.circular(16),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 14,
                                      ),
                                      decoration: BoxDecoration(
                                        color: selected
                                            ? _selectedBg
                                            : Colors.white,
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(
                                          color: selected
                                              ? _selectedBorder
                                              : Colors.grey.shade200,
                                          width: 1,
                                        ),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            item.name,
                                            style: TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w700,
                                              color: selected
                                                  ? _titleColor
                                                  : Colors.black87,
                                            ),
                                          ),
                                          const SizedBox(height: 10),
                                          Container(
                                            height: 1,
                                            width: double.infinity,
                                            color: Colors.white,
                                          ),
                                          const SizedBox(height: 10),
                                          Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Icon(
                                                Icons.location_on_outlined,
                                                size: 16,
                                                color: selected
                                                    ? _subtitleColor
                                                    : Colors.grey.shade500,
                                              ),
                                              const SizedBox(width: 4),
                                              Expanded(
                                                child: Text(
                                                  item.location,
                                                  maxLines: 2,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    fontSize: 13,
                                                    color: selected
                                                        ? _subtitleColor
                                                        : Colors.grey.shade600,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _submitting ? null : () => Get.back(),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.black87,
                          minimumSize: const Size.fromHeight(48),
                          side: BorderSide(color: Colors.grey.shade300),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(
                            color: Colors.black87,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: (_loading || _submitting) ? null : _onSubmit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryBlue,
                          disabledBackgroundColor:
                              AppColors.primaryBlue.withValues(alpha: 0.6),
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(48),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: _submitting
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                'Submit',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
