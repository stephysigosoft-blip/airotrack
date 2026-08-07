import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'dart:math' as math;
import '../../../../widgets/map_widget.dart';
import '../controllers/track_controller.dart';
import '../../../routes/app_routes.dart';
import 'lock_command_view.dart';

class TrackView extends GetView<TrackController> {
  const TrackView({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final height = MediaQuery.of(context).size.height;
    return SafeArea(
      top: false,
      child: Scaffold(
        backgroundColor: Colors.white,
        resizeToAvoidBottomInset: false,
        body: Stack(
          children: [
            // 1. Map Background — top-down overhead (north-up)
            Obx(
              () => AiroMapWidget(
                key: ValueKey(
                  '${controller.vehicleImei.value}-${controller.mapStyle.value}',
                ),
                mapController: controller.mapController,
                initialZoom: 18,
                mapStyle: controller.mapStyle.value,
                lockNorthUp: true,
                onTap: () => controller.showBottomSheet.value = false,
                markers: controller.mapMarkers,
                onPositionChanged: (position, hasGesture) {
                  // Keep a true top-down view (never tilted / spun).
                  if (position.rotation.abs() > 0.05) {
                    controller.mapController.moveAndRotate(
                      position.center,
                      position.zoom,
                      0,
                    );
                  }
                  if (hasGesture) {
                    controller.onMapGesture();
                  }
                },
              ),
            ),

            // 2. Control Layout
            Stack(
              children: [
                // Top Left: Back Button
                Positioned(
                  top: height * 0.053,
                  left: width * 0.04,
                  child: GestureDetector(
                    onTap: () => Get.back(),
                    child: Icon(
                      Icons.arrow_back_ios_new,
                      size: width * 0.055,
                      color: Colors.black87,
                    ),
                  ),
                ),

                // Left Control Group
                Positioned(
                  top: height * 0.21,
                  left: width * 0.04,
                  child: Column(
                    children: [
                      _buildMapControl(
                        'lib/Asset/Icons/routes detail.png',
                        context,
                      ),
                      SizedBox(height: height * 0.012),
                      _buildMapControl(
                        'lib/Asset/Icons/Focus.png',
                        context,
                        onTap: () =>
                            controller.moveMapToVehicle(snap: true, resetZoom: true),
                      ),
                      SizedBox(height: height * 0.012),
                      _buildMapControl(
                        'lib/Asset/Icons/Customer service.png',
                        context,
                      ),
                      SizedBox(height: height * 0.012),
                      _buildMapControl(
                        'lib/Asset/Icons/zoomin.png',
                        context,
                        onTap: controller.zoomIn,
                      ),
                    ],
                  ),
                ),

                // Top Right: Control Group
                Positioned(
                  top: height * 0.053,
                  right: width * 0.04,
                  child: Column(
                    children: [
                      _buildMapControl(
                        'lib/Asset/Icons/map.png',
                        context,
                        onTap: controller.toggleMapStyle,
                      ),
                      SizedBox(height: height * 0.012),
                      GestureDetector(
                        onTap: () => Get.to(() => const LockCommandView()),
                        child: _buildMapControl(
                          'lib/Asset/Icons/Lock.png',
                          context,
                        ),
                      ),
                      SizedBox(height: height * 0.012),
                      _buildMapControl(
                        null,
                        context,
                        text: 'P',
                        textColor: Colors.red,
                      ),
                      SizedBox(height: height * 0.012),
                      _buildMapControl('lib/Asset/Icons/Video.png', context),
                      SizedBox(height: height * 0.012),
                      _buildMapControl('lib/Asset/Icons/profile.png', context),
                      SizedBox(height: height * 0.012),
                      _buildMapControl(
                        'lib/Asset/Icons/Locations.png',
                        context,
                        onTap: () =>
                            controller.moveMapToVehicle(snap: true, resetZoom: true),
                      ),
                      SizedBox(height: height * 0.012),
                      _buildMapControl(
                        'lib/Asset/Icons/zoomin.png',
                        context,
                        onTap: controller.zoomIn,
                      ),
                      SizedBox(height: height * 0.012),
                      _buildMapControl(
                        'lib/Asset/Icons/zoomout.png',
                        context,
                        onTap: controller.zoomOut,
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // 2. Bottom Sheet
            Obx(
              () => controller.showBottomSheet.value
                  ? _buildDraggableBottomSheet()
                  : const SizedBox.shrink(),
            ),

            // 3. Bottom Navigation Bar (Always visible)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _buildBottomNavBar(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMapControl(
    String? imagePath,
    BuildContext context, {
    IconData? iconData,
    Color? color,
    String? text,
    Color? textColor,
    VoidCallback? onTap,
  }) {
    final width = MediaQuery.of(context).size.width;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: width * 0.085,
        height: width * 0.085,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(width * 0.025),
          boxShadow: const [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 4,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Center(
          child: imagePath != null
              ? Image.asset(
                  imagePath,
                  width: width * 0.05,
                  height: width * 0.05,
                )
              : text != null
              ? Text(
                  text,
                  style: TextStyle(
                    color: textColor ?? Colors.black,
                    fontWeight: FontWeight.bold,
                    fontSize: width * 0.045,
                  ),
                )
              : Icon(
                  iconData,
                  color: color ?? Colors.black,
                  size: width * 0.06,
                ),
        ),
      ),
    );
  }

  // Widget _buildAddRemoveControl() {
  //   return Container(
  //     decoration: BoxDecoration(
  //       color: Colors.white,
  //       borderRadius: BorderRadius.circular(10),
  //       boxShadow: const [
  //         BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2)),
  //       ],
  //     ),
  //     child: Column(
  //       children: [
  //         _buildControlPart(Icons.add),
  //         Container(width: 25, height: 1, color: Colors.grey[200]),
  //         _buildControlPart(Icons.remove),
  //       ],
  //     ),
  //   );
  // }

  // Widget _buildControlPart(IconData icon) {
  //   return SizedBox(
  //     width: 40,
  //     height: 40,
  //     child: Icon(icon, color: Colors.black, size: 24),
  //   );
  // }

  Widget _buildSpeedometerIndicator() {
    return Obx(() {
      final speedStr = controller.displaySpeed;
      final speed = double.tryParse(speedStr) ?? 0.0;
      // Gauge starts at 0.75pi and ends at 2.25pi (sweep 1.5pi)
      // The needle is vertical by default (pointing at 1.5pi position if not rotated)
      // So we rotate relative to 1.5pi.
      // 0 speed should be at 0.75pi. 140 speed at 2.25pi.
      final targetAngle = (speed / 140) * 1.5 * math.pi - (0.75 * math.pi);

      final width = MediaQuery.of(Get.context!).size.width;
      return Container(
        width: width * 0.24,
        height: width * 0.22,
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 8)],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            CustomPaint(
              size: Size(width * 0.19, width * 0.19),
              painter: GaugePainter(),
            ),
            Positioned(
              bottom: width * 0.032,
              child: Column(
                children: [
                  Text(
                    speedStr,
                    style: TextStyle(
                      fontSize: width * 0.042,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    "Km/h",
                    style: TextStyle(
                      fontSize: width * 0.022,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
            // Needle
            Transform.rotate(
              angle: targetAngle,
              child: Container(
                width: width * 0.005,
                height: width * 0.075,
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(width * 0.004),
                ),
                margin: EdgeInsets.only(bottom: width * 0.075),
              ),
            ),
          ],
        ),
      );
    });
  }

  Widget _buildDraggableBottomSheet() {
    return DraggableScrollableSheet(
      // Peek by default so the map stays dominant; drag up for full details.
      initialChildSize: 0.20,
      minChildSize: 0.18,
      maxChildSize: 0.92,
      snap: true,
      snapSizes: const [0.20, 0.45, 0.92],
      builder: (context, scrollController) {
        final height = MediaQuery.of(context).size.height;
        final width = MediaQuery.of(context).size.width;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 12,
                    offset: Offset(0, -5),
                  ),
                ],
              ),
              child: RefreshIndicator(
                onRefresh: () => controller.refreshData(),
                color: const Color(0xFF009FE3),
                child: ListView(
                  controller: scrollController,
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    SizedBox(height: height * 0.008),
                    Center(
                      child: Container(
                        width: width * 0.11,
                        height: height * 0.005,
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(width * 0.005),
                        ),
                      ),
                    ),
                    SizedBox(height: height * 0.01),

                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Obx(
                                () => Text(
                                  controller.displayPlate,
                                  style: TextStyle(
                                    fontSize: width * 0.042,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black,
                                  ),
                                ),
                              ),
                              SizedBox(height: height * 0.006),
                              Obx(() {
                                // Digits under plate = position.odometer (8 columns)
                                controller.odometerKm.value;
                                final digits = controller.displayOdometerDigits;
                                return Row(
                                  children: List.generate(
                                    digits.length,
                                    (index) => _buildIdBox(digits[index]),
                                  ),
                                );
                              }),
                              SizedBox(height: height * 0.006),
                              Obx(
                                () => Text(
                                  controller.displayLastUpdate,
                                  style: TextStyle(
                                    color: Colors.black,
                                    fontSize: width * 0.028,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Green Car Visualization
                        Container(
                          width: width * 0.28,
                          height: height * 0.07,
                          alignment: Alignment.centerRight,
                          child: Image.asset(
                            'lib/Asset/Images/Green Car.png',
                            fit: BoxFit.contain,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Status Icons Box
                    Container(
                      height: height * 0.057,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(width * 0.025),
                        border: Border.all(
                          color: Colors.grey.shade100,
                          width: 1.5,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          Image.asset(
                            'lib/Asset/Icons/Mask.png',
                            width: width * 0.053,
                            height: width * 0.053,
                            color: const Color(0xFF03A9F4),
                          ),
                          Image.asset(
                            'lib/Asset/Icons/Key start.png',
                            width: width * 0.053,
                            height: width * 0.053,
                            color: const Color.fromARGB(255, 3, 145, 62),
                          ),
                          Image.asset(
                            'lib/Asset/Icons/power.png',
                            width: width * 0.053,
                            height: width * 0.053,
                            color: const Color.fromARGB(255, 3, 145, 62),
                          ),
                          Image.asset(
                            'lib/Asset/Icons/Network.png',
                            width: width * 0.053,
                            height: width * 0.053,
                            color: const Color.fromARGB(255, 3, 145, 62),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 25),

                    // Time boxes
                    Row(
                      children: [
                        Expanded(
                          child: Obx(
                            () => _buildTimeBox(
                              "Device Time",
                              controller.displayDeviceTime,
                            ),
                          ),
                        ),
                        const SizedBox(width: 15),
                        Expanded(
                          child: Obx(
                            () => _buildTimeBox(
                              "Server Time",
                              controller.displayLastUpdate,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 25),

                    // Status Capsules
                    Obx(
                      () => Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _buildDurationStatusCard(
                            "Running",
                            controller.displayRunningDuration,
                            const Color.fromARGB(255, 3, 145, 62),
                          ),
                          _buildDurationStatusCard(
                            "Idle",
                            controller.displayIdleDuration,
                            const Color(0xFFFFB300),
                          ),
                          _buildDurationStatusCard(
                            "Stopped",
                            controller.displayStoppedDuration,
                            const Color(0xFFFF4B2B),
                          ),
                          _buildDurationStatusCard(
                            "Inactive",
                            controller.displayInactiveDuration,
                            const Color(0xFF00BCD4),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 25),

                    // Metric Cards section
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEDF8FF),
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Obx(
                        () => Row(
                          children: [
                            Expanded(
                              child: _buildMetricCard(
                                "Avg Speed",
                                controller.displayAvgSpeed,
                                "Kmph",
                                'lib/Asset/Icons/AVG speed.png',
                                const Color(0xFF009FE3),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildMetricCard(
                                "Max Speed",
                                controller.displayMaxSpeed,
                                "Kmph",
                                'lib/Asset/Icons/Max Distance.png',
                                const Color(0xFFFF5252),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildMetricCard(
                                "Today Km",
                                controller.displayTodayKm,
                                "Km",
                                'lib/Asset/Icons/location outlined.png',
                                Colors.black,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 25),

                    // Small Grid Items
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      child: Obx(
                        () => Row(
                          children: [
                            _buildSmallGridItem(
                              "Battery",
                              controller.isPowerOn ? "ON" : "OFF",
                              'lib/Asset/Icons/Battery.png',
                            ),
                            const SizedBox(width: 12),
                            _buildSmallGridItem(
                              "GSM Signal",
                              controller.displayGsmSignal,
                              'lib/Asset/Icons/Network.png',
                            ),
                            const SizedBox(width: 12),
                            _buildSmallGridItem(
                              "Ignition",
                              controller.isIgnitionOn ? "ON" : "OFF",
                              'lib/Asset/Icons/Key start.png',
                            ),
                            const SizedBox(width: 12),
                            _buildSmallGridItem(
                              "Network",
                              controller.displayNetwork,
                              'lib/Asset/Icons/Network.png',
                            ),
                            const SizedBox(width: 12),
                            _buildSmallGridItem(
                              "Altitude",
                              controller.displayAltitude,
                              'lib/Asset/Icons/Distance.png',
                            ),
                            const SizedBox(width: 12),
                            _buildSmallGridItem(
                              "Fuel",
                              "N/A",
                              'lib/Asset/Icons/Fuel.png',
                            ),
                            const SizedBox(width: 12),
                            _buildSmallGridItem(
                              "Temperature",
                              "N/A",
                              'lib/Asset/Icons/temperature.png',
                            ),
                            const SizedBox(width: 12),
                            _buildSmallGridItem(
                              "Movement",
                              controller.displaySpeed != "0.0"
                                  ? "True"
                                  : "False",
                              'lib/Asset/Icons/Movement.png',
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 35),

                    // Action Buttons
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      child: Row(
                        children: [
                          GestureDetector(
                            onTap: () => _showShareLocationBottomSheet(context),
                            child: _buildActionButton(
                              "Share Location",
                              'lib/Asset/Icons/Share Location.png',
                            ),
                          ),
                          const SizedBox(width: 18),
                          GestureDetector(
                            onTap: () => Get.toNamed(Routes.ADD_GEOFENCE),
                            child: _buildActionButton(
                              "Add \n Geofence",
                              'lib/Asset/Icons/Add geofence.png',
                            ),
                          ),
                          const SizedBox(width: 18),
                          GestureDetector(
                            onTap: () => _showStreetViewDetailsDialog(context),
                            child: _buildActionButton(
                              "Street \n View",
                              'lib/Asset/Icons/Street View.png',
                            ),
                          ),
                          const SizedBox(width: 18),
                          GestureDetector(
                            onTap: () => _showUpdateOdometerDialog(context),
                            child: _buildActionButton(
                              "Update \n Odometer",
                              'lib/Asset/Icons/Update Odometer.png',
                            ),
                          ),
                          const SizedBox(width: 18),
                          GestureDetector(
                            onTap: () => Get.toNamed(Routes.ADD_REMINDER),
                            child: _buildActionButton(
                              "Add \n Reminder",
                              'lib/Asset/Icons/Bells.png',
                            ),
                          ),
                          const SizedBox(width: 18),
                          GestureDetector(
                            onTap: () => _showOverspeedLimitDialog(context),
                            child: _buildActionButton(
                              "Overspeed \n Limit",
                              'lib/Asset/Icons/Top speed.png',
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 80),
                  ],
                ),
              ),
            ),
            // Speedometer floating above (over the small peek sheet)
            Positioned(
              top: -height * 0.055,
              left: 0,
              right: 0,
              child: Center(child: _buildSpeedometerIndicator()),
            ),
          ],
        );
      },
    );
  }

  Widget _buildIdBox(String text) {
    final width = MediaQuery.of(Get.context!).size.width;
    final height = MediaQuery.of(Get.context!).size.height;
    return Container(
      width: width * 0.038,
      height: height * 0.024,
      margin: EdgeInsets.only(right: width * 0.015),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F2F5),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: Colors.grey.shade300, width: 0.8),
      ),
      child: Center(
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
      ),
    );
  }

  Widget _buildTimeBox(String label, String time) {
    final width = MediaQuery.of(Get.context!).size.width;
    final height = MediaQuery.of(Get.context!).size.height;
    return Container(
      padding: EdgeInsets.symmetric(
        vertical: height * 0.018,
        horizontal: width * 0.025,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(width * 0.04),
        boxShadow: [
          BoxShadow(
            color: const Color(0x12000000),
            blurRadius: width * 0.025,
            offset: Offset(0, height * 0.005),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            time,
            style: const TextStyle(
              color: Color(0xFF009FE3),
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDurationStatusCard(String label, String time, Color color) {
    final width = MediaQuery.of(Get.context!).size.width;
    final height = MediaQuery.of(Get.context!).size.height;
    return Column(
      children: [
        Container(
          width: width * 0.18,
          height: height * 0.038,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(width * 0.04),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          time,
          style: const TextStyle(
            fontSize: 11,
            color: Colors.black,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildMetricCard(
    String label,
    String value,
    String unit,
    String iconPath,
    Color color,
  ) {
    final width = MediaQuery.of(Get.context!).size.width;
    final height = MediaQuery.of(Get.context!).size.height;
    return Container(
      width: width * 0.2,
      height: height * 0.12,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(width * 0.04),
        boxShadow: [
          BoxShadow(
            color: const Color(0x10000000),
            blurRadius: width * 0.02,
            offset: Offset(0, height * 0.003),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Image.asset(iconPath, width: 28, height: 28, color: color),
          const SizedBox(height: 10),
          Text(
            label,
            style: const TextStyle(
              fontSize: 9,
              color: Colors.grey,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
              const SizedBox(width: 2),
              Text(
                unit,
                style: const TextStyle(
                  fontSize: 10,
                  color: Colors.grey,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSmallGridItem(String label, String value, String iconPath) {
    final width = MediaQuery.of(Get.context!).size.width;
    return Container(
      width: width * 0.16,
      height: width * 0.16,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(width * 0.03),
        boxShadow: [
          BoxShadow(
            color: const Color(0x08000000).withOpacity(0.1),
            blurRadius: width * 0.01,
            offset: Offset(0, width * 0.01),
          ),
        ],
        border: Border.all(color: Colors.grey.shade50, width: 1),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(iconPath, width: 22, height: 22),
            const SizedBox(height: 6),
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                color: Colors.grey,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            Text(
              value,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton(String label, String iconPath) {
    final width = MediaQuery.of(Get.context!).size.width;
    final height = MediaQuery.of(Get.context!).size.height;
    return Container(
      width: width * 0.19,
      height: height * 0.105,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(width * 0.03),
        boxShadow: [
          BoxShadow(
            color: const Color(0x10000000).withOpacity(0.1),
            blurRadius: width * 0.015,
            offset: Offset(0, height * 0.005),
          ),
        ],
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(iconPath, width: 28, height: 28),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showShareLocationBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final height = MediaQuery.of(context).size.height;
        final width = MediaQuery.of(context).size.width;
        return Container(
          width: width,
          height: height * 0.63,
          margin: EdgeInsets.only(top: height * 0.02),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(23),
              topRight: Radius.circular(23),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 15),
              Center(
                child: Text(
                  "Share Live Location",
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
              ),
              const Divider(height: 30),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 23),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "KL 07 D 0518",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 20),
                    _buildShareOption("Only Once"),
                    const SizedBox(height: 15),
                    _buildShareOption("1 Hour"),
                    const SizedBox(height: 15),
                    _buildShareOption("1 Day"),
                    const SizedBox(height: 15),
                    _buildShareOption("1 Week"),
                    const SizedBox(height: 15),
                    _buildShareOption("2 Weeks"),
                    const SizedBox(height: 15),
                    _buildShareOption("Custom Hours"),
                    const SizedBox(height: 30),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildShareActionButton(
                          "Cancel",
                          isSelected: false,
                          onTap: () => Navigator.pop(context),
                        ),
                        _buildShareActionButton(
                          "Share",
                          isSelected: true,
                          onTap: () {
                            // Logic for sharing
                            Navigator.pop(context);
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildShareOption(String title) {
    final width = MediaQuery.of(Get.context!).size.width;
    final height = MediaQuery.of(Get.context!).size.height;
    return Obx(() {
      final isSelected = controller.selectedShareOption.value == title;
      return GestureDetector(
        onTap: () => controller.updateShareOption(title),
        child: Container(
          width: width * 0.88,
          height: height * 0.047,
          padding: EdgeInsets.symmetric(horizontal: width * 0.04),
          decoration: BoxDecoration(
            color: isSelected ? Colors.transparent : const Color(0xFFF5F5F5),
            borderRadius: BorderRadius.circular(16),
            border: isSelected
                ? Border.all(color: const Color(0xFF009FE3), width: 1)
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  color: isSelected ? Colors.black : Colors.grey[700],
                  fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
                ),
              ),
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xFF009FE3),
                    width: 1.5,
                  ),
                ),
                child: isSelected
                    ? Center(
                        child: Container(
                          width: 12,
                          height: 12,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Color(0xFF009FE3),
                          ),
                        ),
                      )
                    : null,
              ),
            ],
          ),
        ),
      );
    });
  }

  Widget _buildShareActionButton(
    String label, {
    required bool isSelected,
    required VoidCallback onTap,
    double? width,
  }) {
    final width_ = MediaQuery.of(Get.context!).size.width;
    final height_ = MediaQuery.of(Get.context!).size.height;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: width ?? width_ * 0.35,
        height: height_ * 0.047,
        alignment: Alignment.center,
        padding: EdgeInsets.symmetric(
          vertical: height_ * 0.008,
          horizontal: width_ * 0.07,
        ),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF009FE3) : Colors.white,
          borderRadius: BorderRadius.circular(width_ * 0.015),
          border: isSelected ? null : Border.all(color: Colors.grey[300]!),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.black,
            fontWeight: FontWeight.bold,
            fontSize: width_ * 0.035,
          ),
        ),
      ),
    );
  }

  void _showUpdateOdometerDialog(BuildContext context) {
    final odometerController = TextEditingController(
      text: controller.displayOdometer == '0.00'
          ? ''
          : controller.displayOdometer,
    );
    final focusNode = FocusNode();
    var disposed = false;
    var submitting = false;

    controller.setInputSheetOpen(true);

    // Modal sheet + root navigator avoids IME fight with DraggableScrollableSheet.
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setModalState) {
            final width = MediaQuery.of(sheetContext).size.width;
            final bottomInset = MediaQuery.viewInsetsOf(sheetContext).bottom;

            Future<void> submit() async {
              if (submitting) return;
              submitting = true;
              setModalState(() {});
              FocusManager.instance.primaryFocus?.unfocus();

              final result =
                  await controller.updateOdometer(odometerController.text);

              if (!result.ok) {
                submitting = false;
                controller.clearOdometerUpdating();
                if (sheetContext.mounted) setModalState(() {});
                return;
              }

              // Success: close first, then apply UI.
              if (sheetContext.mounted) {
                Navigator.pop(sheetContext);
              }
              await Future<void>.delayed(const Duration(milliseconds: 80));
              controller.clearOdometerUpdating();
              controller.applyOdometerLocal(result.value!);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(result.message),
                    duration: const Duration(seconds: 2),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            }

            return Padding(
              padding: EdgeInsets.only(bottom: bottomInset),
              child: Container(
                width: width,
                padding: EdgeInsets.fromLTRB(
                  width * 0.05,
                  width * 0.04,
                  width * 0.05,
                  width * 0.05 + MediaQuery.paddingOf(sheetContext).bottom,
                ),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Text(
                      'Update Odometer',
                      style: TextStyle(
                        fontSize: width * 0.04,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                    SizedBox(height: width * 0.045),
                    Container(
                      height: 48,
                      alignment: Alignment.centerLeft,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF5F5F5),
                        borderRadius: BorderRadius.circular(width * 0.008),
                      ),
                      child: TextField(
                        controller: odometerController,
                        focusNode: focusNode,
                        enabled: !submitting,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        textInputAction: TextInputAction.done,
                        style: TextStyle(fontSize: width * 0.035),
                        decoration: InputDecoration(
                          hintText: 'Enter odometer (km)',
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: width * 0.03,
                            vertical: 12,
                          ),
                        ),
                        onSubmitted: (_) => submit(),
                      ),
                    ),
                    SizedBox(height: width * 0.05),
                    Row(
                      children: [
                        Expanded(
                          child: _buildShareActionButton(
                            'Cancel',
                            isSelected: false,
                            width: double.infinity,
                            onTap: submitting
                                ? () {}
                                : () => Navigator.pop(sheetContext),
                          ),
                        ),
                        SizedBox(width: width * 0.04),
                        Expanded(
                          child: _buildShareActionButton(
                            submitting ? 'Updating...' : 'Update',
                            isSelected: true,
                            width: double.infinity,
                            onTap: submitting ? () {} : submit,
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
      },
    ).whenComplete(() {
      disposed = true;
      controller.clearOdometerUpdating();
      // Resume marker loop after sheet teardown settles.
      Future<void>.delayed(const Duration(milliseconds: 120), () {
        controller.setInputSheetOpen(false);
      });
      focusNode.dispose();
      odometerController.dispose();
    });

    // Focus after the sheet is laid out (avoids IME show→cancel race).
    Future<void>.delayed(const Duration(milliseconds: 300), () {
      if (!disposed && focusNode.canRequestFocus) {
        focusNode.requestFocus();
      }
    });
  }

  void _showOverspeedLimitDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        final width = MediaQuery.of(context).size.width;
        final height = MediaQuery.of(context).size.height;
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: EdgeInsets.symmetric(horizontal: width * 0.025),
          child: Container(
            width: width * 0.95,
            height: height * 0.2,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(width * 0.035),
            ),
            child: Stack(
              children: [
                Positioned(
                  top: height * 0.018,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Text(
                      "Update Speed Limit",
                      style: TextStyle(
                        fontSize: width * 0.04,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: height * 0.068,
                  left: width * 0.035,
                  child: Container(
                    width: width * 0.88,
                    height: height * 0.047,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F5F5),
                      borderRadius: BorderRadius.circular(width * 0.008),
                    ),
                    child: TextField(
                      style: TextStyle(fontSize: width * 0.035),
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: width * 0.025,
                          vertical: height * 0.01,
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  bottom: height * 0.018,
                  left: width * 0.05,
                  right: width * 0.05,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildShareActionButton(
                        "Cancel",
                        isSelected: false,
                        width: width * 0.4,
                        onTap: () => Navigator.pop(context),
                      ),
                      _buildShareActionButton(
                        "Update",
                        isSelected: true,
                        width: width * 0.4,
                        onTap: () {
                          Navigator.pop(context);
                        },
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

  void _showStreetViewDetailsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        final width = MediaQuery.of(context).size.width;
        final height = MediaQuery.of(context).size.height;
        return Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: Container(
            width: width * 0.6,
            height: height * 0.13,
            padding: EdgeInsets.fromLTRB(
              width * 0.04,
              height * 0.01,
              width * 0.04,
              height * 0.01,
            ),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(width * 0.04),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: width * 0.025,
                  offset: Offset(0, height * 0.005),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildStreetViewDetailRow(
                  "Arrival Time:",
                  "08 Oct 2025 11:00 AM",
                ),
                SizedBox(height: height * 0.006),
                _buildStreetViewDetailRow(
                  "Departure Time:",
                  "08 Oct 2025 12:30 PM",
                ),
                SizedBox(height: height * 0.006),
                _buildStreetViewDetailRow("Duration:", "01h 30m"),
                SizedBox(height: height * 0.006),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: width * 0.19,
                        child: Text(
                          "Address:",
                          style: TextStyle(
                            fontSize: width * 0.025,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          "Puthiyakavu Junction, Karunagappalli, Kerala 690539, India",
                          style: TextStyle(
                            fontSize: width * 0.025,
                            color: Colors.black87,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
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

  Widget _buildStreetViewDetailRow(String label, String value) {
    final width = MediaQuery.of(Get.context!).size.width;
    return Row(
      children: [
        SizedBox(
          width: width * 0.19,
          child: Text(
            label,
            style: TextStyle(
              fontSize: width * 0.025,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(fontSize: width * 0.025, color: Colors.black87),
        ),
      ],
    );
  }

  Widget _buildBottomNavBar() {
    final height = MediaQuery.of(Get.context!).size.height;
    return Container(
      height: height * 0.1,
      padding: EdgeInsets.only(bottom: height * 0.015),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Color(0x10000000),
            blurRadius: 12,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildBottomNavItem(
            "Track",
            'lib/Asset/Icons/Location.png',
            true,
            onTap: () {
              controller.startTrackingForImei(
                controller.vehicleImei.value,
                plate: controller.displayPlate,
              );
            },
          ),
          _buildBottomNavItem(
            "History",
            'lib/Asset/Icons/history.png',
            false,
            onTap: () => Get.offNamed(
              Routes.HISTORY,
              parameters: {
                'imei': controller.vehicleImei.value,
                'vehicleId': controller.displayPlate,
              },
            ),
          ),
          _buildBottomNavItem(
            "Alerts",
            'lib/Asset/Icons/notification.png',
            false,
            onTap: () => Get.offNamed(Routes.ALERTS),
          ),
          _buildBottomNavItem(
            "Statistics",
            'lib/Asset/Icons/statistics.png',
            false,
            onTap: () => Get.toNamed(Routes.STATISTICS),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNavItem(
    String label,
    String iconPath,
    bool isSelected, {
    VoidCallback? onTap,
  }) {
    final width = MediaQuery.of(Get.context!).size.width;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Image.asset(
            iconPath,
            width: width * 0.063,
            height: width * 0.063,
            color: isSelected ? const Color(0xFF009FE3) : Colors.black,
          ),
          SizedBox(height: width * 0.015),
          Text(
            label,
            style: TextStyle(
              color: isSelected ? const Color(0xFF009FE3) : Colors.black,
              fontSize: width * 0.032,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
}

class GaugePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 8;
    final strokeW = (size.width * 0.08).clamp(8.0, 12.0);

    final sections = [
      {'color': const Color(0xFF00C853), 'start': 0.75, 'sweep': 0.5},
      {'color': const Color(0xFFFFD600), 'start': 1.25, 'sweep': 0.5},
      {'color': const Color(0xFFFF3D00), 'start': 1.75, 'sweep': 0.5},
    ];

    for (var section in sections) {
      final paint = Paint()
        ..color = section['color'] as Color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeW
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        math.pi * (section['start'] as double),
        math.pi * (section['sweep'] as double),
        false,
        paint,
      );
    }

    final paintMark = Paint()
      ..color = Colors.black38
      ..strokeWidth = 1.2;

    for (int i = 0; i <= 20; i++) {
      final double angle = math.pi * (0.75 + (i * 1.5 / 20));
      final double dx = math.cos(angle);
      final double dy = math.sin(angle);
      final double outerR = radius + 4;
      final double innerR = i % 5 == 0 ? radius - 4 : radius - 1.5;
      canvas.drawLine(
        Offset(center.dx + innerR * dx, center.dy + innerR * dy),
        Offset(center.dx + outerR * dx, center.dy + outerR * dy),
        paintMark,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
