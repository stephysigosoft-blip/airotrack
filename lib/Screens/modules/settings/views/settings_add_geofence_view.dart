import 'dart:math' as math;

import 'package:airotrack/Configs/ApiConfigs.dart';
import 'package:airotrack/Utils/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:get/get.dart';
import 'package:latlong2/latlong.dart';

import '../controllers/geofence_controller.dart';

class SettingsAddGeofenceView extends GetView<GeofenceController> {
  const SettingsAddGeofenceView({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Scaffold(
      backgroundColor: Colors.white,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.black, size: 20),
          onPressed: () => Get.back(),
        ),
        title: Obx(
          () => Text(
            controller.isEditing.value ? 'Edit Geofence' : 'Add Geofence',
            style: const TextStyle(
              color: Colors.black,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.only(bottom: bottomInset > 0 ? 8 : 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _MapSection(),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _label('Fence Name'),
                        const SizedBox(height: 8),
                        _input(
                          controller: controller.fenceNameController,
                          hint: 'Enter Fence Name',
                        ),
                        Obx(() {
                          final err = controller.fenceNameError.value;
                          if (err == null || err.isEmpty) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              err,
                              style: const TextStyle(
                                color: Colors.red,
                                fontSize: 12,
                              ),
                            ),
                          );
                        }),
                        const SizedBox(height: 16),
                        _label('Event Type'),
                        const SizedBox(height: 8),
                        Obx(
                          () => _dropdown<String>(
                            value: controller.selectedEventType.value,
                            items: GeofenceController.eventTypes,
                            onChanged: (v) {
                              if (v != null) {
                                controller.selectedEventType.value = v;
                              }
                            },
                            labelBuilder: (v) => v,
                          ),
                        ),
                        const SizedBox(height: 16),
                        _label('Address'),
                        const SizedBox(height: 8),
                        _input(
                          controller: controller.addressController,
                          hint: 'Enter your address',
                        ),
                        const SizedBox(height: 16),
                        _label('Description'),
                        const SizedBox(height: 8),
                        _input(
                          controller: controller.descriptionController,
                          hint: 'Give a short description',
                          maxLines: 3,
                          height: 90,
                        ),
                        const SizedBox(height: 16),
                        _label('Tolerance'),
                        const SizedBox(height: 8),
                        Obx(
                          () => _dropdown<int>(
                            value: controller.selectedTolerance.value,
                            items: GeofenceController.tolerances,
                            onChanged: (v) {
                              if (v != null) {
                                controller.selectedTolerance.value = v;
                              }
                            },
                            labelBuilder: (v) => '$v',
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ],
              ),
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
                      onPressed: () => Get.back(),
                      style: OutlinedButton.styleFrom(
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
                      onPressed: () {
                        if (controller.submitGeofenceForm()) {
                          Get.back();
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryBlue,
                        minimumSize: const Size.fromHeight(48),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text(
                        'Submit',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
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
    );
  }

  Widget _label(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: Colors.black87,
      ),
    );
  }

  Widget _input({
    required TextEditingController controller,
    required String hint,
    int maxLines = 1,
    double height = 48,
  }) {
    return Container(
      height: maxLines > 1 ? height : 48,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Colors.grey, fontSize: 13),
          border: InputBorder.none,
        ),
      ),
    );
  }

  Widget _dropdown<T>({
    required T value,
    required List<T> items,
    required ValueChanged<T?> onChanged,
    required String Function(T) labelBuilder,
  }) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down),
          items: items
              .map(
                (e) => DropdownMenuItem<T>(
                  value: e,
                  child: Text(labelBuilder(e)),
                ),
              )
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _MapSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final controller = Get.find<GeofenceController>();
    final mapController = MapController();

    return SizedBox(
      height: 280,
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
        child: Stack(
          children: [
            Obx(
              () => FlutterMap(
                mapController: mapController,
                options: MapOptions(
                  initialCenter: controller.mapCenter.value,
                  initialZoom: controller.mapZoom.value,
                  onPositionChanged: (pos, _) {
                    controller.mapCenter.value = pos.center;
                    controller.mapZoom.value = pos.zoom;
                  },
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://api.mapbox.com/styles/v1/mapbox/streets-v12/tiles/256/{z}/{x}/{y}@2x?access_token=${ApiConfig.mapboxAccessToken}',
                    userAgentPackageName: 'com.example.airotrack',
                  ),
                  Obx(() => _shapeOverlay(controller)),
                ],
              ),
            ),
            Positioned(
              top: 12,
              left: 12,
              right: 12,
              child: Container(
                height: 42,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: controller.searchPlaceController,
                        decoration: const InputDecoration(
                          hintText: 'Search for a place',
                          hintStyle:
                              TextStyle(color: Colors.grey, fontSize: 13),
                          border: InputBorder.none,
                          isDense: true,
                        ),
                      ),
                    ),
                    Icon(Icons.search, color: Colors.grey.shade400),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 12,
              bottom: 12,
              child: Column(
                children: [
                  _mapBtn(
                    icon: Icons.add,
                    onTap: () {
                      final z = (controller.mapZoom.value + 1).clamp(3.0, 18.0);
                      controller.mapZoom.value = z;
                      mapController.move(controller.mapCenter.value, z);
                    },
                  ),
                  const SizedBox(height: 8),
                  _mapBtn(
                    icon: Icons.remove,
                    onTap: () {
                      final z = (controller.mapZoom.value - 1).clamp(3.0, 18.0);
                      controller.mapZoom.value = z;
                      mapController.move(controller.mapCenter.value, z);
                    },
                  ),
                ],
              ),
            ),
            Positioned(
              right: 12,
              bottom: 12,
              child: Column(
                children: [
                  _mapBtn(icon: Icons.zoom_out_map, onTap: () {}),
                  const SizedBox(height: 8),
                  Obx(
                    () => _shapeBtn(
                      icon: Icons.crop_square,
                      selected:
                          controller.selectedShape.value ==
                          GeofenceShape.rectangle,
                      onTap: () =>
                          controller.selectedShape.value =
                              GeofenceShape.rectangle,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Obx(
                    () => _shapeBtn(
                      icon: Icons.circle_outlined,
                      selected:
                          controller.selectedShape.value ==
                          GeofenceShape.circle,
                      onTap: () =>
                          controller.selectedShape.value = GeofenceShape.circle,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Obx(
                    () => _shapeBtn(
                      icon: Icons.hexagon_outlined,
                      selected:
                          controller.selectedShape.value ==
                          GeofenceShape.polygon,
                      onTap: () =>
                          controller.selectedShape.value =
                              GeofenceShape.polygon,
                      assetFallback: 'lib/Asset/Images/geofence_icon.png',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _shapeOverlay(GeofenceController controller) {
    final center = controller.mapCenter.value;
    final shape = controller.selectedShape.value;
    final color = AppColors.primaryBlue.withValues(alpha: 0.25);
    final border = AppColors.primaryBlue.withValues(alpha: 0.8);

    if (shape == GeofenceShape.circle) {
      return CircleLayer(
        circles: [
          CircleMarker(
            point: center,
            radius: 120,
            useRadiusInMeter: true,
            color: color,
            borderStrokeWidth: 2,
            borderColor: border,
          ),
        ],
      );
    }

    final points = shape == GeofenceShape.rectangle
        ? _rectanglePoints(center, 0.0012, 0.0010)
        : _polygonPoints(center, 0.0013);

    return PolygonLayer(
      polygons: [
        Polygon(
          points: points,
          color: color,
          borderStrokeWidth: 2,
          borderColor: border,
        ),
      ],
    );
  }

  List<LatLng> _rectanglePoints(LatLng c, double dLat, double dLng) {
    return [
      LatLng(c.latitude + dLat, c.longitude - dLng),
      LatLng(c.latitude + dLat, c.longitude + dLng),
      LatLng(c.latitude - dLat, c.longitude + dLng),
      LatLng(c.latitude - dLat, c.longitude - dLng),
    ];
  }

  List<LatLng> _polygonPoints(LatLng c, double r) {
    const n = 5;
    return List.generate(n, (i) {
      final a = (2 * math.pi * i / n) - (math.pi / 2);
      return LatLng(
        c.latitude + r * math.cos(a),
        c.longitude + r * math.sin(a) * 1.15,
      );
    });
  }

  Widget _mapBtn({required IconData icon, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 4,
            ),
          ],
        ),
        child: Icon(icon, size: 20, color: Colors.black87),
      ),
    );
  }

  Widget _shapeBtn({
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
    String? assetFallback,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryBlue : Colors.white,
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 4,
            ),
          ],
        ),
        alignment: Alignment.center,
        child: assetFallback != null && selected
            ? Image.asset(
                assetFallback,
                width: 20,
                height: 20,
                color: Colors.white,
                errorBuilder: (_, __, ___) => Icon(
                  icon,
                  size: 20,
                  color: Colors.white,
                ),
              )
            : Icon(
                icon,
                size: 20,
                color: selected ? Colors.white : Colors.black87,
              ),
      ),
    );
  }
}
