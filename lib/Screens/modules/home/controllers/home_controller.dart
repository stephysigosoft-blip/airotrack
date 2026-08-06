import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:airotrack/Configs/ApiConfigs.dart';
import 'package:airotrack/Configs/DioClient.dart';
import 'package:airotrack/Utils/Utils.dart';

class Vehicle {
  final int id;
  final String plateNumber;
  final String status; // 'Running', 'Stopped', 'Idle', 'Inactive'
  final String statusDuration;
  final String lastUpdated;
  final String address;
  final String speed;
  final String distance;
  final String validityDays;
  final bool isIgnitionOn;
  final bool isLocked;
  final String deviceId;

  Vehicle({
    required this.id,
    required this.plateNumber,
    required this.status,
    required this.statusDuration,
    required this.lastUpdated,
    required this.address,
    required this.speed,
    required this.distance,
    required this.validityDays,
    this.isIgnitionOn = false,
    this.isLocked = true,
    required this.deviceId,
  });

  factory Vehicle.fromJson(Map<String, dynamic> json) {
    final mode = json['mode']?.toString().toUpperCase();
    final speed = double.tryParse(json['speed']?.toString() ?? '0') ?? 0;
    final ignitionRaw = json['ignition'];
    final ignition = ignitionRaw == 1 ||
        ignitionRaw == true ||
        ignitionRaw?.toString() == '1';

    // Prefer explicit status string from API when present (not bool flags).
    final rawStatus =
        json['current_status'] ?? json['vehicle_status'] ?? json['status'];
    final apiStatus = rawStatus is String ? rawStatus.trim() : null;

    final derivedStatus = _resolveVehicleStatus(
      apiStatus: apiStatus,
      mode: mode,
      speed: speed,
      ignition: ignition,
    );

    return Vehicle(
      id: json['id'] ?? 0,
      plateNumber: json['vehicle_number'] ?? json['name'] ?? '',
      status: derivedStatus,
      statusDuration: json['duration'] ?? '',
      lastUpdated: json['last_update'] ?? json['device_time'] ?? '',
      address:
          json['location'] ??
          json['address'] ??
          (json['latitude'] != null
              ? "${json['latitude']}, ${json['longitude']}"
              : ''),
      speed: speed.toStringAsFixed(1),
      distance: (json['distance'] ?? 0).toString(),
      validityDays: (json['remaining_days'] ?? 0).toString(),
      isIgnitionOn: ignition,
      isLocked: json['lock'] != 0,
      deviceId: (json['imei'] ?? json['device_id'] ?? '').toString(),
    );
  }

  /// Aligns with live-track modes: M/R = Running, H/I = Idle, S = Stopped.
  static String _resolveVehicleStatus({
    String? apiStatus,
    String? mode,
    required double speed,
    required bool ignition,
  }) {
    if (apiStatus != null && apiStatus.isNotEmpty) {
      final s = apiStatus.toLowerCase();
      if (s.contains('inactive') || s.contains('expired')) return 'Inactive';
      if (s.contains('run') || s.contains('mov')) return 'Running';
      if (s.contains('idle')) return 'Idle';
      if (s.contains('stop')) return 'Stopped';
    }

    final m = mode?.toUpperCase();
    if (m == 'INACTIVE' || m == 'EXPIRED') return 'Inactive';
    // Mode is authoritative — do not override Stopped with noisy speed.
    if (m == 'M' || m == 'R' || m == 'RUNNING' || m == 'MOVING') {
      return 'Running';
    }
    if (m == 'H' || m == 'I' || m == 'IDLE') return 'Idle';
    if (m == 'S' || m == 'STOPPED' || m == 'STOP') return 'Stopped';

    // Fallback when mode is missing.
    if (speed > 1.0) return 'Running';
    if (ignition) return 'Idle';
    return 'Stopped';
  }
}

class HomeController extends GetxController {
  final vehicles = <Vehicle>[].obs;
  final isLoading = false.obs;
  final isMoreLoading = false.obs;
  final hasMore = true.obs;
  final errorMessage = ''.obs;
  final RxInt selectedIndex = 1.obs;
  final ScrollController scrollController = ScrollController();
  int currentPage = 1;

  // Status counts
  final totalCount = "0".obs;
  final runningCount = "0".obs;
  final stoppedCount = "0".obs;
  final idleCount = "0".obs;
  final inactiveCount = "0".obs;

  /// Search query for filtering vehicles (plate number, address, device id).
  final searchQuery = ''.obs;

  /// API type → status: 1 Stopped, 2 Running, 3 Idle, 4 Inactive.
  String? get _selectedStatusFilter {
    switch (selectedType.value) {
      case 1:
        return 'Stopped';
      case 2:
        return 'Running';
      case 3:
        return 'Idle';
      case 4:
        return 'Inactive';
      default:
        return null;
    }
  }

  /// Vehicles for the selected tab (+ search). Always status-filtered on device
  /// so Stopped never appears under Running even if the API mix is wrong.
  List<Vehicle> get filteredVehicles {
    var list = vehicles.toList();
    final status = _selectedStatusFilter;
    if (status != null) {
      list = list.where((v) => v.status == status).toList();
    }

    final q = searchQuery.value.trim().toLowerCase();
    if (q.isEmpty) return list;
    return list
        .where(
          (v) =>
              v.plateNumber.toLowerCase().contains(q) ||
              v.address.toLowerCase().contains(q) ||
              v.deviceId.toLowerCase().contains(q),
        )
        .toList();
  }

  @override
  void onInit() {
    super.onInit();
    _initializeAndFetch();
    scrollController.addListener(() {
      try {
        if (!scrollController.hasClients) return;
        final position = scrollController.position;
        if (position.pixels >= position.maxScrollExtent - 200) {
          if (!isLoading.value && !isMoreLoading.value && hasMore.value) {
            loadMoreVehicles();
          }
        }
      } catch (_) {
        // ScrollController not attached or has multiple clients (e.g. during rebuild)
      }
    });
  }

  Future<void> _initializeAndFetch() async {
    final token = await getSavedObject('token');
    if (token != null) {
      DioClient().updateToken(token is String ? token : token.toString());
    }
    await fetchVehicles();
  }

  final selectedType = RxnInt();

  Future<void> fetchVehicles({int? type}) async {
    try {
      selectedType.value = type;
      currentPage = 1;
      hasMore.value = true;
      isLoading.value = true;
      errorMessage.value = '';

      final response = await DioClient().get(
        ApiEndPoints.home,
        query: {
          'type': type != null ? type.toString() : '',
          'page': '1',
          'limit': '20',
        },
      );
      if (response.data != null && response.data['data'] != null) {
        final data = response.data['data'];
        if (data['vehicles_data'] != null) {
          final List<dynamic> vehiclesList = data['vehicles_data'];
          vehicles.value = _uniqueVehicles(
            vehiclesList.map((json) => Vehicle.fromJson(json)).toList(),
          );
          // No more pages when first page is shorter than the page size.
          hasMore.value = vehiclesList.length >= 20;
        } else {
          vehicles.clear();
          hasMore.value = false;
        }
        if (data['statistics'] != null) {
          final stats = data['statistics'];
          totalCount.value = stats['total_vehicles']?.toString() ?? "0";
          runningCount.value = stats['running_vehicles']?.toString() ?? "0";
          stoppedCount.value = stats['stopped_vehicles']?.toString() ?? "0";
          idleCount.value = stats['idle_vehicles']?.toString() ?? "0";
          inactiveCount.value = stats['expired_vehicles']?.toString() ?? "0";
        } else {
          totalCount.value = vehicles.length.toString();
          runningCount.value = vehicles
              .where((v) => v.status == 'Running')
              .length
              .toString();
          stoppedCount.value = vehicles
              .where((v) => v.status == 'Stopped')
              .length
              .toString();
          idleCount.value = vehicles
              .where((v) => v.status == 'Idle')
              .length
              .toString();
          inactiveCount.value = vehicles
              .where((v) => v.status == 'Inactive')
              .length
              .toString();
        }
      }
    } catch (e) {
      errorMessage.value = "An error occurred: $e";
      print("Error loading data: $e");
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> loadMoreVehicles() async {
    if (isLoading.value || isMoreLoading.value || !hasMore.value) return;
    try {
      isMoreLoading.value = true;
      final nextPage = currentPage + 1;

      final response = await DioClient().get(
        ApiEndPoints.home,
        query: {
          'type': selectedType.value != null
              ? selectedType.value.toString()
              : '',
          'page': nextPage.toString(),
          'limit': '20',
        },
      );

      if (response.data != null && response.data['data'] != null) {
        final data = response.data['data'];

        if (data['vehicles_data'] != null) {
          final List<dynamic> vehiclesList = data['vehicles_data'];
          if (vehiclesList.isEmpty) {
            hasMore.value = false;
          } else {
            final newVehicles = vehiclesList
                .map((json) => Vehicle.fromJson(json))
                .toList();
            final unique = _dedupeVehicles(newVehicles);
            if (unique.isEmpty) {
              // API repeated page-1 vehicles — stop paging.
              hasMore.value = false;
            } else {
              vehicles.addAll(unique);
              currentPage = nextPage;
              if (newVehicles.length < 20) {
                hasMore.value = false;
              }
            }
          }
        } else {
          hasMore.value = false;
        }
      } else {
        hasMore.value = false;
      }
    } catch (e) {
      hasMore.value = false;
    } finally {
      isMoreLoading.value = false;
    }
  }

  /// Keeps only vehicles not already in [vehicles] (by id, else IMEI/plate).
  List<Vehicle> _dedupeVehicles(List<Vehicle> incoming) {
    final existingKeys = <String>{};
    for (final v in vehicles) {
      existingKeys.add(_vehicleKey(v));
    }
    return incoming.where((v) => existingKeys.add(_vehicleKey(v))).toList();
  }

  /// Dedupes within a single page response.
  List<Vehicle> _uniqueVehicles(List<Vehicle> incoming) {
    final seen = <String>{};
    return incoming.where((v) => seen.add(_vehicleKey(v))).toList();
  }

  String _vehicleKey(Vehicle v) {
    if (v.id != 0) return 'id:${v.id}';
    if (v.deviceId.trim().isNotEmpty) return 'imei:${v.deviceId.trim()}';
    return 'plate:${v.plateNumber.trim().toLowerCase()}';
  }

  void changeTab(int index) {
    selectedIndex.value = index;
  }

  @override
  void onClose() {
    scrollController.dispose();
    super.onClose();
  }
}
