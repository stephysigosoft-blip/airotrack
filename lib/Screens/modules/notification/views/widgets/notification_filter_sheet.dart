import 'package:airotrack/Utils/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../../controllers/notification_controller.dart';

Future<void> showNotificationFilterSheet(BuildContext context) {
  final controller = Get.find<NotificationController>();
  controller.beginFilterEdit();

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) {
      return Material(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        clipBehavior: Clip.antiAlias,
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: 120,
                      child: Obx(
                        () => Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const SizedBox(height: 16),
                            _FilterCategory(
                              label: 'Event Types',
                              selected: controller.filterCategory.value ==
                                  NotificationFilterCategory.eventTypes,
                              onTap: () => controller.filterCategory.value =
                                  NotificationFilterCategory.eventTypes,
                            ),
                            _FilterCategory(
                              label: 'Vehicles',
                              selected: controller.filterCategory.value ==
                                  NotificationFilterCategory.vehicles,
                              onTap: () => controller.filterCategory.value =
                                  NotificationFilterCategory.vehicles,
                            ),
                            _FilterCategory(
                              label: 'Date',
                              selected: controller.filterCategory.value ==
                                  NotificationFilterCategory.date,
                              onTap: () => controller.filterCategory.value =
                                  NotificationFilterCategory.date,
                            ),
                            const Spacer(),
                          ],
                        ),
                      ),
                    ),
                    Container(width: 1, color: Colors.grey.shade200),
                    Expanded(
                      child: Obx(() {
                        switch (controller.filterCategory.value) {
                          case NotificationFilterCategory.eventTypes:
                            return _EventTypesPane(controller: controller);
                          case NotificationFilterCategory.vehicles:
                            return _VehiclesPane(controller: controller);
                          case NotificationFilterCategory.date:
                            return _DatePane(controller: controller);
                        }
                      }),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          controller.cancelFilterEdit();
                          Get.back();
                        },
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
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          controller.applyFilters();
                          Get.back();
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
                          'Apply',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
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

class _FilterCategory extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterCategory({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: selected ? AppColors.primaryBlue : Colors.black87,
          ),
        ),
      ),
    );
  }
}

class _EventTypesPane extends StatelessWidget {
  final NotificationController controller;

  const _EventTypesPane({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final selected = controller.draftEventTypes.toList();
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final option in NotificationController.eventTypeOptions)
              InkWell(
                onTap: () => controller.toggleDraftEventType(option),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  child: Row(
                    children: [
                      _CheckBox(selected: selected.contains(option)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          option,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: Colors.black87,
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
    });
  }
}

class _VehiclesPane extends StatelessWidget {
  final NotificationController controller;

  const _VehiclesPane({required this.controller});

  @override
  Widget build(BuildContext context) {
    final maxListHeight = MediaQuery.sizeOf(context).height * 0.38;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Container(
            height: 42,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    onChanged: (v) => controller.vehicleFilterQuery.value = v,
                    decoration: const InputDecoration(
                      hintText: 'Search Vehicles',
                      hintStyle: TextStyle(color: Colors.grey, fontSize: 13),
                      border: InputBorder.none,
                      isDense: true,
                    ),
                  ),
                ),
                Icon(Icons.search, color: Colors.grey.shade400, size: 22),
              ],
            ),
          ),
        ),
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxListHeight),
          child: Obx(() {
            final plates = controller.filteredVehicleOptions;
            final selected = controller.draftVehicles.toList();
            return ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(16, 4, 12, 8),
              itemCount: plates.length,
              itemBuilder: (context, index) {
                final plate = plates[index];
                final isSelected = selected.contains(plate);
                return InkWell(
                  onTap: () => controller.toggleDraftVehicle(plate),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(
                      children: [
                        _CheckBox(selected: isSelected),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            plate,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          }),
        ),
      ],
    );
  }
}

class _DatePane extends StatelessWidget {
  final NotificationController controller;

  const _DatePane({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
      child: Obx(() {
        final from = controller.draftFromDate.value;
        final to = controller.draftToDate.value;
        final format = DateFormat('dd MMM yyyy');
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'From Date',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            const SizedBox(height: 8),
            _DateField(
              value: from == null ? 'Select date' : format.format(from),
              onTap: () => controller.pickDraftFromDate(context),
            ),
            const SizedBox(height: 20),
            const Text(
              'To Date',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            const SizedBox(height: 8),
            _DateField(
              value: to == null ? 'Select date' : format.format(to),
              onTap: () => controller.pickDraftToDate(context),
            ),
          ],
        );
      }),
    );
  }
}

class _DateField extends StatelessWidget {
  final String value;
  final VoidCallback onTap;

  const _DateField({required this.value, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 13,
                  color: value == 'Select date'
                      ? Colors.grey
                      : Colors.black87,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Icon(
              Icons.calendar_today_outlined,
              size: 18,
              color: Colors.grey.shade600,
            ),
          ],
        ),
      ),
    );
  }
}

class _CheckBox extends StatelessWidget {
  final bool selected;

  const _CheckBox({required this.selected});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: selected ? AppColors.primaryBlue : Colors.grey.shade300,
        borderRadius: BorderRadius.circular(4),
      ),
      child: selected
          ? const Icon(Icons.check, size: 14, color: Colors.white)
          : null,
    );
  }
}
