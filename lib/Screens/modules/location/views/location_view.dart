import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../Utils/app_colors.dart';
import '../../../../widgets/map_widget.dart';
import '../controllers/location_controller.dart';

class LocationView extends GetView<LocationController> {
  const LocationView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          AiroMapWidget(),
          Positioned(
            top: 45,
            left: 15,
            child: _buildFloatingButton(
              'lib/Asset/Icons/map.png',
              onTap: () {},
            ),
          ),
          Positioned(
            top: 45,
            right: 15,
            child: Column(
              children: [
                _buildFloatingButton(
                  'lib/Asset/Icons/Filters.png',
                  onTap: () {},
                ),
                const SizedBox(height: 10),
                _buildFloatingButton('lib/Asset/Icons/Zoom.png', onTap: () {}),
                const SizedBox(height: 10),
                _buildFloatingButton(
                  'lib/Asset/Icons/Traffic.png',
                  onTap: controller.toggleTraffic,
                ),
                const SizedBox(height: 10),
                _buildFloatingButton(
                  'lib/Asset/Icons/Refresh.png',
                  onTap: () {},
                ),
              ],
            ),
          ),
          Positioned(
            left: 5,
            top: MediaQuery.of(context).size.height * 0.45,
            child: _buildSideArrow(Icons.chevron_left),
          ),
          Positioned(
            right: 5,
            top: MediaQuery.of(context).size.height * 0.45,
            child: _buildSideArrow(Icons.chevron_right),
          ),
          Center(
            child: Obx(() {
              final vehicle = controller.selectedVehicle.value;
              final plate = vehicle?.name ?? 'KL 07 A 0518';
              return GestureDetector(
                onTap: () {
                  if (vehicle != null) {
                    _showVehicleDetailsDialog(context, vehicle);
                  }
                },
                behavior: HitTestBehavior.opaque,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(15),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Text(
                        plate,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Image.asset(
                      'lib/Asset/Images/Green right Car.png',
                      width: 55,
                      height: 55,
                    ),
                  ],
                ),
              );
            }),
          ),
          Positioned(
            bottom: 130,
            right: 15,
            child: Column(
              children: [
                _buildFloatingButton(
                  'lib/Asset/Icons/Locations.png',
                  onTap: controller.centerOnVehicle,
                ),
                const SizedBox(height: 10),
                _buildFloatingButton(
                  'lib/Asset/Icons/zoomin.png',
                  onTap: controller.zoomIn,
                ),
                const SizedBox(height: 10),
                _buildFloatingButton(
                  'lib/Asset/Icons/zoomout.png',
                  onTap: controller.zoomOut,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showVehicleDetailsDialog(
    BuildContext context,
    LocationVehicleInfo vehicle,
  ) {
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.white,
          insetPadding: const EdgeInsets.symmetric(horizontal: 28),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _detailRow('Name:', vehicle.name),
                const SizedBox(height: 10),
                _detailRow(
                  'Status:',
                  '${vehicle.status} Since ${vehicle.statusDuration}',
                ),
                const SizedBox(height: 10),
                _detailRow('Device Time:', vehicle.deviceTime),
                const SizedBox(height: 10),
                _detailRow('Location:', vehicle.location, maxLines: 2),
                const SizedBox(height: 10),
                _detailRow('Engine:', vehicle.engine),
                const SizedBox(height: 10),
                _detailRow('Voltage:', vehicle.voltage),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(40),
                          side: BorderSide(color: Colors.grey.shade300),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
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
                          // Track navigation will be wired when integrated.
                          Navigator.pop(dialogContext);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryBlue,
                          minimumSize: const Size.fromHeight(40),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text(
                          'Track',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _detailRow(String label, String value, {int maxLines = 3}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 95,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Colors.black,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Colors.black87,
              height: 1.25,
            ),
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildFloatingButton(String iconPath, {required VoidCallback onTap}) {
    return Container(
      width: 35,
      height: 35,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Center(
            child: Image.asset(
              iconPath,
              width: 20,
              height: 20,
              color: Colors.black,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSideArrow(IconData icon) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.25),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Icon(icon, color: Colors.black.withOpacity(0.7), size: 32),
      ),
    );
  }
}
