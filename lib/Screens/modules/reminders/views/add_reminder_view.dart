import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/add_reminder_controller.dart';

class AddReminderView extends GetView<AddReminderController> {
  const AddReminderView({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Add Reminder',
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
      body: GestureDetector(
        onTap: controller.closeTypeDropdown,
        behavior: HitTestBehavior.opaque,
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 20),

                  // Select Type
                  const Text(
                    'Select Type',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: controller.toggleTypeDropdown,
                    child: Obx(() {
                      final selected = controller.selectedType.value;
                      return Container(
                        width: double.infinity,
                        height: 40,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade300),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.grey.withOpacity(0.05),
                              blurRadius: 2,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              selected ?? 'Select Reminder Type',
                              style: TextStyle(
                                color: selected == null
                                    ? Colors.grey[400]
                                    : Colors.black87,
                                fontSize: 13,
                                fontWeight: selected == null
                                    ? FontWeight.w400
                                    : FontWeight.w500,
                              ),
                            ),
                            Icon(
                              controller.isTypeDropdownOpen.value
                                  ? Icons.arrow_drop_up
                                  : Icons.arrow_drop_down,
                              color: const Color(0xFF009FE3),
                            ),
                          ],
                        ),
                      );
                    }),
                  ),
                  Obx(
                    () => controller.typeError.value.isNotEmpty
                        ? Padding(
                            padding: const EdgeInsets.only(top: 4, left: 4),
                            child: Text(
                              controller.typeError.value,
                              style: const TextStyle(
                                color: Colors.red,
                                fontSize: 12,
                              ),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),

                  const SizedBox(height: 16),

                  // Start
                  const Text(
                    'Start',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade300),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.grey.withOpacity(0.05),
                          blurRadius: 2,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: TextField(
                      controller: controller.odometerController,
                      onTap: controller.closeTypeDropdown,
                      decoration: const InputDecoration(
                        hintText: 'Enter Starting Odometer',
                        hintStyle: TextStyle(color: Colors.grey, fontSize: 13),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                      ),
                      style: const TextStyle(fontSize: 13),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  Obx(
                    () => controller.odometerError.value.isNotEmpty
                        ? Padding(
                            padding: const EdgeInsets.only(top: 4, left: 4),
                            child: Text(
                              controller.odometerError.value,
                              style: const TextStyle(
                                color: Colors.red,
                                fontSize: 12,
                              ),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                  const SizedBox(height: 16),

                  // Period
                  const Text(
                    'Period',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade300),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.grey.withOpacity(0.05),
                          blurRadius: 2,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: TextField(
                      controller: controller.periodController,
                      onTap: controller.closeTypeDropdown,
                      decoration: const InputDecoration(
                        hintText: 'Enter the Odometer Period for Alerts',
                        hintStyle: TextStyle(color: Colors.grey, fontSize: 13),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                      ),
                      style: const TextStyle(fontSize: 13),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  Obx(
                    () => controller.periodError.value.isNotEmpty
                        ? Padding(
                            padding: const EdgeInsets.only(top: 4, left: 4),
                            child: Text(
                              controller.periodError.value,
                              style: const TextStyle(
                                color: Colors.red,
                                fontSize: 12,
                              ),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),

            // Dropdown menu overlay (matches design)
            Obx(() {
              if (!controller.isTypeDropdownOpen.value) {
                return const SizedBox.shrink();
              }
              return Positioned(
                top: 88,
                left: 16,
                right: 16,
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.12),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: controller.reminderTypes.map((type) {
                        final isLast = type == controller.reminderTypes.last;
                        return InkWell(
                          onTap: () => controller.selectType(type),
                          borderRadius: BorderRadius.vertical(
                            top: type == controller.reminderTypes.first
                                ? const Radius.circular(10)
                                : Radius.zero,
                            bottom: isLast
                                ? const Radius.circular(10)
                                : Radius.zero,
                          ),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              border: isLast
                                  ? null
                                  : Border(
                                      bottom: BorderSide(
                                        color: Colors.grey.shade100,
                                      ),
                                    ),
                            ),
                            child: Text(
                              type,
                              style: const TextStyle(
                                fontSize: 14,
                                color: Colors.black87,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              );
            }),

            // Submit Button
            Positioned(
              left: 16,
              right: 16,
              bottom: 30,
              child: GestureDetector(
                onTap: controller.submit,
                child: Container(
                  height: 45,
                  decoration: BoxDecoration(
                    color: const Color(0xFF009FE3),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: const Text(
                    'Submit',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
