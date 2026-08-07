import 'package:flutter/material.dart';
import 'package:get/get.dart';

class AddReminderController extends GetxController {
  final odometerController = TextEditingController();
  final periodController = TextEditingController();

  final reminderTypes = const [
    'Service',
    'Oil Change',
    'AC Service',
    'Filter Change',
    'Tyre Change',
    'Battery Change',
    'Others',
  ];

  final selectedType = RxnString();
  final isTypeDropdownOpen = false.obs;

  final typeError = ''.obs;
  final odometerError = ''.obs;
  final periodError = ''.obs;

  void toggleTypeDropdown() {
    isTypeDropdownOpen.value = !isTypeDropdownOpen.value;
  }

  void closeTypeDropdown() {
    if (isTypeDropdownOpen.value) {
      isTypeDropdownOpen.value = false;
    }
  }

  void selectType(String type) {
    selectedType.value = type;
    typeError.value = '';
    isTypeDropdownOpen.value = false;
  }

  bool validate() {
    bool isValid = true;

    if (selectedType.value == null || selectedType.value!.isEmpty) {
      typeError.value = 'Reminder type is required';
      isValid = false;
    } else {
      typeError.value = '';
    }

    if (odometerController.text.trim().isEmpty) {
      odometerError.value = 'Starting odometer is required';
      isValid = false;
    } else {
      odometerError.value = '';
    }

    if (periodController.text.trim().isEmpty) {
      periodError.value = 'Odometer period is required';
      isValid = false;
    } else {
      periodError.value = '';
    }
    return isValid;
  }

  void submit() {
    closeTypeDropdown();
    if (validate()) {
      Get.back();
      Get.snackbar(
        'Success',
        'Reminder added successfully',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.green,
        colorText: Colors.white,
      );
    }
  }

  @override
  void onClose() {
    odometerController.dispose();
    periodController.dispose();
    super.onClose();
  }
}
