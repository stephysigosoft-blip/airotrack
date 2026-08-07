import 'package:airotrack/Screens/routes/app_routes.dart';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controllers/notification_controller.dart';
import 'widgets/notification_filter_sheet.dart';

class NotificationView extends GetView<NotificationController> {
  const NotificationView({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Notifications',
          style: TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        centerTitle: false,
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.black),
          onPressed: () => Get.back(),
        ),
      ),
      body: Column(
        children: [
          // Search and Filter
          Padding(
            padding: const EdgeInsets.only(
              top: 20,
              left: 13.97,
              right: 13.97,
            ), // Adjusted top to separate from AppBar, left as requested
            child: Row(
              children: [
                Container(
                  width: 297,
                  height: 45,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade300),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.withOpacity(0.1),
                        spreadRadius: 1,
                        blurRadius: 3,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: const TextField(
                    decoration: InputDecoration(
                      hintText: "Search Vehicles",
                      hintStyle: TextStyle(color: Colors.grey, fontSize: 13),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ), // Reduced vertical padding for 45px height
                      suffixIcon: Icon(Icons.search, color: Colors.grey),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: () => showNotificationFilterSheet(context),
                  child: Container(
                    height: 45,
                    width: 45,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade300),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.grey.withOpacity(0.1),
                          spreadRadius: 1,
                          blurRadius: 3,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Image.asset(
                        'lib/Asset/Icons/Filters.png',
                        width: 22,
                        height: 22,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16), // Spacing between Search and Tabs
          // Tabs
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.only(
              left: 13.97,
            ), // Align with search bar
            child: Obx(
              () => Row(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  _buildTab('Alerts', controller.selectedTab.value == 'Alerts'),
                  const SizedBox(width: 8),
                  _buildTab(
                    'Announcements',
                    controller.selectedTab.value == 'Announcements',
                  ),
                  const SizedBox(width: 8),
                  _buildTab(
                    'Reminders',
                    controller.selectedTab.value == 'Reminders',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16), // Height to push list down
          // List
          Expanded(
            child: Obx(
              () => ListView.builder(
                controller: controller.scrollController,
                padding: const EdgeInsets.only(left: 17, right: 17, top: 0),
                itemCount:
                    controller.notifications.length +
                    (controller.isLoading.value && controller.hasMore.value
                        ? 1
                        : 0),
                itemBuilder: (context, index) {
                  if (index < controller.notifications.length) {
                    final type = index % 3; // 0: On, 1: Off, 2: Speed
                    return _buildNotificationCard(context, type);
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
            ),
          ),
        ],
      ),
    );
  }

  // ... (in _buildTab)
  Widget _buildTab(String text, bool isSelected) {
    return GestureDetector(
      onTap: () {
        if (text == 'Reminders') {
          Get.toNamed(Routes.REMINDERS);
        } else if (text == 'Alerts') {
          Get.toNamed(Routes.ALERTS);
        } else {
          controller.changeTab(text);
        }
      },
      child: Container(
        width: 116,
        height: 30,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(13), // Radius 13
          border: Border.all(
            color: isSelected ? const Color(0xFF009FE3) : Colors.grey.shade300,
            width: 1.5,
          ),
          boxShadow: [
            if (!isSelected)
              BoxShadow(
                color: Colors.grey.withOpacity(0.1),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
          ],
        ),
        alignment: Alignment.center,
        child: Text(
          text,
          style: TextStyle(
            color: text == 'Alerts' && isSelected
                ? Colors.black
                : Colors.black87,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  Widget _buildNotificationCard(BuildContext context, int type) {
    double screenWidth = MediaQuery.of(context).size.width;
    Widget iconWidget;
    String statusText;

    if (type == 0) {
      iconWidget = Image.asset(
        'lib/Asset/Icons/power.png',
        width: 28,
        height: 28,
        color: Color(0xFF00C853), // Green
      );
      statusText = "Ignition On";
    } else if (type == 1) {
      iconWidget = Image.asset(
        'lib/Asset/Icons/power.png',
        width: 28,
        height: 28,
        color: Color(0xFFD50000), // Red
      );
      statusText = "Ignition Off";
    } else {
      iconWidget = Image.asset(
        'lib/Asset/Icons/Speed.png',
        width: 28,
        height: 28,
        color: const Color(0xFF009FE3), // Blue
      );
      statusText = "Device Overspeed";
    }

    return Container(
      width: screenWidth - 34,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 10,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12), // Radius 12
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.15),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(2),
            child: iconWidget, // Reduced icon size
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Flexible(
                      child: Text(
                        "KL 07 D 0518",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: Colors.black,
                          height: 1.2,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      "Oct 17, 2025 5:38:08 PM",
                      style: TextStyle(
                        fontSize: 9,
                        color: Colors.grey[500],
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  statusText,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[600],
                    height: 1.2,
                  ),
                ),
                Text(
                  "PuthiyakavuJunction, Karunagappalli, Kollam, Kerala",
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.grey[600],
                    height: 1.2,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
