import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controllers/home_controller.dart';
import '../../../widgets/custom_bottom_nav_bar.dart';
import '../../dashboard/views/dashboard_view.dart';
import '../../reports/views/reports_view.dart';
import '../../settings/views/settings_view.dart';
import '../../location/views/location_view.dart';

import '../../../routes/app_routes.dart';

class HomeView extends GetView<HomeController> {
  const HomeView({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Screen width usually ~393 on modern devices, designing for that scale.
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: Colors.white, // Pure white background to match design
      body: SafeArea(
        top: false,
        child: Stack(
          children: [
            // Main Content
            Obx(() {
              switch (controller.selectedIndex.value) {
                case 0:
                  return DashboardView();
                case 1:
                  return _buildHome();
                case 2:
                  return const LocationView();
                case 3:
                  return const ReportsView();
                case 4:
                  return const SettingsView();
                default:
                  return _buildPlaceholder("Coming Soon");
              }
            }),

            // Bottom Navigation
            Positioned(
              left: -1.5,
              right: 0,
              bottom: 0,
              child: SizedBox(height: 118, child: const CustomBottomNavBar()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHome() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. Header Area
        const SizedBox(height: 69),
        Padding(
          padding: const EdgeInsets.only(left: 16.41),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Search Bar
              Container(
                width: 297.8,
                height: 45,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(13),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x33000000),
                      blurRadius: 10,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextField(
                        onChanged: (value) =>
                            controller.searchQuery.value = value,
                        decoration: const InputDecoration(
                          hintText: "Search Vehicles",
                          border: InputBorder.none,
                          hintStyle: TextStyle(
                            color: Colors.grey,
                            fontSize: 14,
                          ),
                          contentPadding: EdgeInsets.only(bottom: 12),
                        ),
                      ),
                    ),
                    const Icon(Icons.search, color: Colors.grey),
                    const SizedBox(width: 16),
                  ],
                ),
              ),
              const SizedBox(width: 6.99),
              // Notification Icon
              GestureDetector(
                onTap: () => Get.toNamed(Routes.NOTIFICATION),
                child: Container(
                  width: 53.69,
                  height: 45,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(13),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x33000000),
                        blurRadius: 10,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                  child: const FittedBox(
                    child: Icon(
                      Icons.notifications_outlined,
                      color: Colors.black,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 15.5),
        // 2. Status Filters
        Obx(
          () => SizedBox(
            height: 76,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(left: 15.61, right: 16),
              children: [
                GestureDetector(
                  onTap: () => controller.fetchVehicles(type: null),
                  child: _buildStatusCard(
                    "All Vehicles",
                    controller.totalCount.value,
                    Colors.blue,
                    controller.selectedType.value == null,
                  ),
                ),
                const SizedBox(width: 11),
                GestureDetector(
                  onTap: () => controller.fetchVehicles(type: 2),
                  child: _buildStatusCard(
                    "Running",
                    controller.runningCount.value,
                    const Color(0xFF00C853),
                    controller.selectedType.value == 2,
                  ),
                ),
                const SizedBox(width: 11),
                GestureDetector(
                  onTap: () => controller.fetchVehicles(type: 1),
                  child: _buildStatusCard(
                    "Stopped",
                    controller.stoppedCount.value,
                    const Color(0xFFFF3D00),
                    controller.selectedType.value == 1,
                  ),
                ),
                const SizedBox(width: 11),
                GestureDetector(
                  onTap: () => controller.fetchVehicles(type: 3),
                  child: _buildStatusCard(
                    "Idle",
                    controller.idleCount.value,
                    const Color(0xFFFFD600),
                    controller.selectedType.value == 3,
                  ),
                ),
                const SizedBox(width: 11),
                GestureDetector(
                  onTap: () => controller.fetchVehicles(type: 4),
                  child: _buildStatusCard(
                    "Inactive",
                    controller.inactiveCount.value,
                    const Color.fromARGB(255, 21, 107, 178),
                    controller.selectedType.value == 4,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        // 3. Vehicle List
        Expanded(
          child: Obx(() {
            if (controller.isLoading.value) {
              return const Center(child: CircularProgressIndicator());
            }
            final list = controller.filteredVehicles;
            final showLoadMore =
                controller.searchQuery.value.trim().isEmpty &&
                controller.isMoreLoading.value;
            return RefreshIndicator(
              onRefresh: () =>
                  controller.fetchVehicles(type: controller.selectedType.value),
              color: const Color(0xFF009FE3),
              child: ListView.separated(
                controller: controller.scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(
                  left: 15.61,
                  right: 15.61,
                  bottom: 120,
                ),
                itemCount: list.length + (showLoadMore ? 1 : 0),
                separatorBuilder: (_, __) => const SizedBox(height: 11),
                itemBuilder: (context, index) {
                  if (index < list.length) {
                    final vehicle = list[index];
                    return _buildVehicleCard(context, vehicle);
                  } else {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(16.0),
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Color(0xFF009FE3),
                          ),
                        ),
                      ),
                    );
                  }
                },
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _buildPlaceholder(String title) {
    return Center(
      child: Text(
        title,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildStatusCard(
    String title,
    String count,
    Color color,
    bool isSelected,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      constraints: const BoxConstraints(minWidth: 80, maxHeight: 90),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: isSelected ? color : Colors.transparent,
          width: 1,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Image.asset(
            'lib/Asset/Icons/Car.png',
            width: 25,
            height: 22,
            color: color,
            fit: BoxFit.contain,
          ),
          const SizedBox(height: 2),
          Text(
            title,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            count,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildVehicleCard(BuildContext context, Vehicle vehicle) {
    // Both 'Running' and 'Idle' (Moving or Ignition-On) should show as Active (Green).
    final isStatusActive =
        vehicle.status == 'Running' || vehicle.status == 'Idle';
    final statusColor = isStatusActive
        ? const Color(0xFF00C853)
        : const Color(0xFFFF3D00);

    return GestureDetector(
      onTap: () => _showVehicleDialog(context, vehicle),
      child: Container(
        width: 358,
        height: 165,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1A000000),
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Stack(
          children: [
            // Lock Icon Top Left
            Positioned(
              top: 0,
              left: 0,
              child: vehicle.isLocked
                  ? Image.asset(
                      'lib/Asset/Icons/Lock.png',
                      width: 18,
                      height: 18,
                      color: const Color(0xFF00C853),
                    )
                  : const SizedBox.shrink(),
            ),

            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Top Row: Car Image & Details
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Left Col: Image + Speed
                    Expanded(
                      flex: 4,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(height: 2),
                          SizedBox(
                            height: 48,
                            child: Image.asset(
                              vehicle.isIgnitionOn
                                  ? 'lib/Asset/Images/Green right Car.png'
                                  : 'lib/Asset/Images/Red right Car.png',
                              fit: BoxFit.contain,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            vehicle.speed,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w400,
                              fontFamily: 'Roboto Mono',
                            ),
                          ),
                          const Text(
                            "Kmph",
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Right Col: Timeline Details
                    Expanded(
                      flex: 6,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Plate
                          Row(
                            children: [
                              Icon(
                                Icons.directions_car_filled,
                                size: 16,
                                color: statusColor,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  vehicle.plateNumber,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),

                          // Timeline Items
                          _buildTimelineItem(
                            color: statusColor,
                            icon: null,
                            text:
                                "${vehicle.status.toUpperCase()} since ${vehicle.statusDuration}",
                            isFirst: true,
                          ),
                          _buildTimelineItem(
                            color: Colors.transparent,
                            icon: Icons.access_time,
                            iconColor: statusColor,
                            text: vehicle.lastUpdated,
                          ),
                          _buildTimelineItem(
                            color: Colors.transparent,
                            icon: Icons.location_on_outlined,
                            iconColor: statusColor,
                            text: vehicle.address,
                            isLast: true,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 4),

                // Bottom Buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildSquareBtn(
                      const AssetImage("lib/Asset/Icons/Mask.png"),
                      isStatusActive ? Colors.blue : Colors.black,
                      width: 16,
                      height: 16,
                    ),
                    _buildSquareBtn(
                      const AssetImage("lib/Asset/Icons/satellite.png"),
                      Colors.green,
                      width: 16,
                      height: 16,
                    ),
                    _buildSquareBtn(
                      const AssetImage("lib/Asset/Icons/power.png"),
                      isStatusActive ? Colors.green : Colors.red,
                      width: 16,
                      height: 16,
                    ),
                    _buildSquareBtn(
                      const AssetImage("lib/Asset/Icons/key.png"),
                      isStatusActive ? Colors.green : Colors.red,
                      width: 16,
                      height: 16,
                    ),

                    const SizedBox(width: 10),

                    _buildInfoPill(Icons.speed, vehicle.todayKm),
                    const SizedBox(width: 6),
                    _buildInfoPill(
                      Icons.calendar_today,
                      "${vehicle.validityDays} Days",
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimelineItem({
    required Color color,
    IconData? icon,
    Color? iconColor,
    required String text,
    bool isFirst = false,
    bool isLast = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            if (icon != null)
              Icon(icon, size: 12, color: iconColor)
            else
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
            if (!isLast)
              Container(
                width: 1,
                height: 10,
                color: Colors.grey[300],
                margin: const EdgeInsets.symmetric(vertical: 2),
              ),
          ],
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 10, color: Colors.grey[700]),
          ),
        ),
      ],
    );
  }

  Widget _buildSquareBtn(
    AssetImage image,
    Color color, {
    double width = 16,
    double height = 16,
  }) {
    return Container(
      width: 30,
      height: 30,
      margin: const EdgeInsets.only(right: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1F000000),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Center(
        child: Image(image: image, color: color, width: width, height: height),
      ),
    );
  }

  Widget _buildInfoPill(IconData icon, String text) {
    return Expanded(
      child: Container(
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 12, color: Colors.grey),
            const SizedBox(width: 2),
            Flexible(
              child: Text(
                text,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showVehicleDialog(BuildContext context, Vehicle vehicle) {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Container(
            width: 380,
            height: 250,
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildDialogRow("Name:", vehicle.plateNumber),
                const SizedBox(height: 8),
                _buildDialogRow(
                  "Status:",
                  "${vehicle.status}  Since ${vehicle.statusDuration}",
                ),
                const SizedBox(height: 8),
                _buildDialogRow("Device Time:", vehicle.lastUpdated),
                const SizedBox(height: 8),
                _buildDialogRow("Location:", vehicle.address),
                const SizedBox(height: 8),
                _buildDialogRow("Engine:", vehicle.isIgnitionOn ? "On" : "Off"),
                const SizedBox(height: 8),
                _buildDialogRow("Voltage:", "13.78 V"),
                const Spacer(),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Cancel Button
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          width: 120,
                          height: 35,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(7),
                            border: Border.all(color: Colors.grey.shade200),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.05),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: const Center(
                            child: Text(
                              "Cancel",
                              style: TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.w500,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      GestureDetector(
                        onTap: () {
                          Navigator.pop(context);
                          Get.toNamed(
                            Routes.HISTORY,
                            parameters: {
                              'imei': vehicle.deviceId,
                              'vehicleId': vehicle.plateNumber,
                            },
                          );
                        },
                        child: Container(
                          width: 100,
                          height: 35,
                          decoration: BoxDecoration(
                            color: const Color(0xFF009FE3),
                            borderRadius: BorderRadius.circular(7),
                          ),
                          child: const Center(
                            child: Text(
                              "History",
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      GestureDetector(
                        onTap: () {
                          // Dismiss keyboard before navigating
                          if (FocusManager.instance.primaryFocus != null) {
                            FocusManager.instance.primaryFocus!.unfocus();
                          }
                          Navigator.pop(context);
                          Get.toNamed(
                            Routes.TRACK,
                            parameters: {
                              'imei': vehicle.deviceId,
                              'vehicleId': vehicle.plateNumber,
                            },
                          );
                        },
                        child: Container(
                          width: 120,
                          height: 35,
                          decoration: BoxDecoration(
                            color: const Color(0xFF009FE3),
                            borderRadius: BorderRadius.circular(7),
                          ),
                          child: const Center(
                            child: Text(
                              "Track",
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDialogRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 90,
          child: Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 12,
              color: Colors.black,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade800,
              fontWeight: FontWeight.w400,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
