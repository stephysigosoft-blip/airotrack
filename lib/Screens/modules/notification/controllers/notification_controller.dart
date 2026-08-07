import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../home/controllers/home_controller.dart';

enum NotificationFilterCategory { eventTypes, vehicles, date }

class NotificationController extends GetxController {
  final RxString selectedTab = 'Alerts'.obs;
  final ScrollController scrollController = ScrollController();
  var notifications = <int>[].obs;
  var isLoading = false.obs;
  var hasMore = true.obs;
  var currentPage = 1;

  // Applied filters
  final selectedEventTypes = <String>{'All Events'}.obs;
  final selectedVehicles = <String>{}.obs;
  final fromDate = Rxn<DateTime>();
  final toDate = Rxn<DateTime>();

  // Draft filters while sheet is open
  final filterCategory = NotificationFilterCategory.eventTypes.obs;
  final draftEventTypes = <String>{'All Events'}.obs;
  final draftVehicles = <String>{}.obs;
  final draftFromDate = Rxn<DateTime>();
  final draftToDate = Rxn<DateTime>();
  final vehicleFilterQuery = ''.obs;

  static const eventTypeOptions = <String>[
    'All Events',
    'Command Result',
    'Device Online',
    'Device Unknown',
    'Device Offline',
    'Device Inactive',
    'Device Moving',
    'Device Stopped',
    'Device Overspeed',
    'Device Fuel Drop',
  ];

  List<String> get vehicleOptions {
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
      'KL 07 D 0510',
      'KL 07 D 1234',
      'KL 07 D 9876',
    ];
  }

  List<String> get filteredVehicleOptions {
    final q = vehicleFilterQuery.value.trim().toLowerCase();
    final all = vehicleOptions;
    if (q.isEmpty) return all;
    return all.where((p) => p.toLowerCase().contains(q)).toList();
  }

  @override
  void onInit() {
    super.onInit();
    loadNotifications();
    scrollController.addListener(() {
      if (scrollController.position.pixels ==
          scrollController.position.maxScrollExtent) {
        if (!isLoading.value && hasMore.value) {
          loadMoreNotifications();
        }
      }
    });
  }

  void beginFilterEdit() {
    filterCategory.value = NotificationFilterCategory.eventTypes;
    vehicleFilterQuery.value = '';
    draftEventTypes
      ..clear()
      ..addAll(selectedEventTypes);
    draftVehicles
      ..clear()
      ..addAll(selectedVehicles);
    draftFromDate.value = fromDate.value;
    draftToDate.value = toDate.value;
    draftEventTypes.refresh();
    draftVehicles.refresh();
  }

  void cancelFilterEdit() {
    // Discard draft — applied filters stay unchanged.
  }

  void applyFilters() {
    selectedEventTypes
      ..clear()
      ..addAll(draftEventTypes);
    selectedVehicles
      ..clear()
      ..addAll(draftVehicles);
    fromDate.value = draftFromDate.value;
    toDate.value = draftToDate.value;
    selectedEventTypes.refresh();
    selectedVehicles.refresh();
    // Reload list with filters (UI-ready; hook API later).
    currentPage = 1;
    hasMore.value = true;
    loadNotifications();
  }

  void toggleDraftEventType(String option) {
    if (option == 'All Events') {
      draftEventTypes
        ..clear()
        ..add('All Events');
    } else {
      draftEventTypes.remove('All Events');
      if (draftEventTypes.contains(option)) {
        draftEventTypes.remove(option);
      } else {
        draftEventTypes.add(option);
      }
      if (draftEventTypes.isEmpty) {
        draftEventTypes.add('All Events');
      }
    }
    draftEventTypes.refresh();
  }

  void toggleDraftVehicle(String plate) {
    if (draftVehicles.contains(plate)) {
      draftVehicles.remove(plate);
    } else {
      draftVehicles.add(plate);
    }
    draftVehicles.refresh();
  }

  Future<void> pickDraftFromDate(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: draftFromDate.value ?? now,
      firstDate: DateTime(now.year - 5),
      lastDate: draftToDate.value ?? now,
    );
    if (picked != null) draftFromDate.value = picked;
  }

  Future<void> pickDraftToDate(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: draftToDate.value ?? draftFromDate.value ?? now,
      firstDate: draftFromDate.value ?? DateTime(now.year - 5),
      lastDate: now,
    );
    if (picked != null) draftToDate.value = picked;
  }

  void loadNotifications() {
    isLoading.value = true;
    Future.delayed(const Duration(seconds: 1), () {
      notifications.assignAll(List.generate(10, (index) => index));
      isLoading.value = false;
    });
  }

  void loadMoreNotifications() {
    isLoading.value = true;
    currentPage++;
    Future.delayed(const Duration(seconds: 1), () {
      notifications.addAll(List.generate(10, (index) => index));
      if (currentPage >= 5) {
        hasMore.value = false;
      }
      isLoading.value = false;
    });
  }

  void changeTab(String tab) {
    selectedTab.value = tab;
  }

  @override
  void onClose() {
    scrollController.dispose();
    super.onClose();
  }
}
