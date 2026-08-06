import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:latlong2/latlong.dart';

import '../../home/controllers/home_controller.dart';

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

class GeofenceItem {
  final String id;
  final String name;
  final String address;
  final GeofenceShape shape;
  final List<String> vehiclePlates;
  final LatLng center;
  final double radiusMeters;
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
    this.eventType = 'Entry',
    this.description = '',
    this.tolerance = 5,
  });

  GeofenceItem copyWith({
    String? id,
    String? name,
    String? address,
    GeofenceShape? shape,
    List<String>? vehiclePlates,
    LatLng? center,
    double? radiusMeters,
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
  final selectedVehiclePlates = <String>{}.obs;

  // Add / Edit form
  final isEditing = false.obs;
  final editingId = RxnString();
  final selectedShape = GeofenceShape.circle.obs;
  final selectedEventType = 'Entry'.obs;
  final selectedTolerance = 5.obs;
  final mapCenter = const LatLng(12.3095, 75.1302).obs;
  final mapZoom = 15.0.obs;
  final fenceNameError = RxnString();

  final fenceNameController = TextEditingController();
  final addressController = TextEditingController();
  final descriptionController = TextEditingController();
  final searchPlaceController = TextEditingController();

  static const eventTypes = ['Entry', 'Exit', 'Both'];
  static const tolerances = [5, 10, 15, 20, 30, 50];

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

  List<String> get availableVehiclePlates {
    if (Get.isRegistered<HomeController>()) {
      final plates = Get.find<HomeController>()
          .vehicles
          .map((v) => v.plateNumber)
          .where((p) => p.trim().isNotEmpty)
          .toList();
      if (plates.isNotEmpty) return plates;
    }
    return const [
      'KL 07 D 0518',
      'KL 07 D 6788',
      'KL 07 D 1234',
      'KL 07 D 9876',
      'KL 07 D 4321',
    ];
  }

  List<String> get filteredVehiclePlates {
    final q = vehicleSearchQuery.value.trim().toLowerCase();
    final all = availableVehiclePlates;
    if (q.isEmpty) return all;
    return all.where((p) => p.toLowerCase().contains(q)).toList();
  }

  bool get allVehiclesSelected {
    final list = filteredVehiclePlates;
    if (list.isEmpty) return false;
    return list.every(selectedVehiclePlates.contains);
  }

  @override
  void onInit() {
    super.onInit();
    _seedSampleGeofences();
  }

  void _seedSampleGeofences() {
    geofences.assignAll([
      GeofenceItem(
        id: '1',
        name: 'Vennakkad',
        address: 'Vennakkad',
        shape: GeofenceShape.circle,
        center: const LatLng(12.3095, 75.1302),
        vehiclePlates: const ['KL 07 D 0518'],
      ),
      GeofenceItem(
        id: '2',
        name: 'Kodakkad, Kerala',
        address: 'Kodakkad, Kerala',
        shape: GeofenceShape.rectangle,
        center: const LatLng(12.3010, 75.1350),
      ),
      GeofenceItem(
        id: '3',
        name: 'Bharath Petroleum petrol Puthiyandam, Kanhangad',
        address: 'Vennakkad',
        shape: GeofenceShape.polygon,
        center: const LatLng(12.3150, 75.1280),
      ),
    ]);
  }

  void prepareCreate() {
    isEditing.value = false;
    editingId.value = null;
    selectedShape.value = GeofenceShape.circle;
    selectedEventType.value = 'Entry';
    selectedTolerance.value = 5;
    fenceNameError.value = null;
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
    selectedTolerance.value = item.tolerance;
    fenceNameError.value = null;
    fenceNameController.text = item.name;
    addressController.text = item.address;
    descriptionController.text = item.description;
    mapCenter.value = item.center;
  }

  void deleteGeofence(String id) {
    geofences.removeWhere((g) => g.id == id);
  }

  void openUpdateVehicles(GeofenceItem item) {
    vehicleSearchQuery.value = '';
    selectedVehiclePlates.clear();
    selectedVehiclePlates.addAll(item.vehiclePlates);
    selectedVehiclePlates.refresh();
  }

  void toggleVehicle(String plate) {
    if (selectedVehiclePlates.contains(plate)) {
      selectedVehiclePlates.remove(plate);
    } else {
      selectedVehiclePlates.add(plate);
    }
    selectedVehiclePlates.refresh();
  }

  void toggleSelectAllVehicles() {
    final list = filteredVehiclePlates;
    if (allVehiclesSelected) {
      selectedVehiclePlates.removeWhere(list.contains);
    } else {
      selectedVehiclePlates.addAll(list);
    }
    selectedVehiclePlates.refresh();
  }

  void submitVehicleUpdate(GeofenceItem item) {
    final index = geofences.indexWhere((g) => g.id == item.id);
    if (index < 0) return;
    geofences[index] = item.copyWith(
      vehiclePlates: selectedVehiclePlates.toList(),
    );
    Get.back();
    Get.snackbar(
      'Updated',
      'Vehicles updated for ${item.name}',
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: Colors.black87,
      colorText: Colors.white,
      margin: const EdgeInsets.all(12),
      duration: const Duration(seconds: 2),
    );
  }

  bool submitGeofenceForm() {
    final name = fenceNameController.text.trim();
    if (name.isEmpty) {
      fenceNameError.value = 'Geofence name is required';
      return false;
    }
    fenceNameError.value = null;

    final address = addressController.text.trim().isEmpty
        ? name
        : addressController.text.trim();

    if (isEditing.value && editingId.value != null) {
      final index = geofences.indexWhere((g) => g.id == editingId.value);
      if (index >= 0) {
        final existing = geofences[index];
        geofences[index] = existing.copyWith(
          name: name,
          address: address,
          shape: selectedShape.value,
          center: mapCenter.value,
          eventType: selectedEventType.value,
          description: descriptionController.text.trim(),
          tolerance: selectedTolerance.value,
        );
      }
    } else {
      geofences.insert(
        0,
        GeofenceItem(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          name: name,
          address: address,
          shape: selectedShape.value,
          center: mapCenter.value,
          eventType: selectedEventType.value,
          description: descriptionController.text.trim(),
          tolerance: selectedTolerance.value,
        ),
      );
    }
    return true;
  }

  @override
  void onClose() {
    fenceNameController.dispose();
    addressController.dispose();
    descriptionController.dispose();
    searchPlaceController.dispose();
    super.onClose();
  }
}
