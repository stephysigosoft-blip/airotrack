import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../home/controllers/home_controller.dart';

class LocationVehicleInfo {
  final String name;
  final String status;
  final String statusDuration;
  final String deviceTime;
  final String location;
  final String engine;
  final String voltage;
  final String imei;

  const LocationVehicleInfo({
    required this.name,
    required this.status,
    required this.statusDuration,
    required this.deviceTime,
    required this.location,
    required this.engine,
    required this.voltage,
    required this.imei,
  });
}

class LocationController extends GetxController {
  final Rx<LatLng> currentCenter = const LatLng(10.0159, 76.3419).obs;
  final RxDouble zoomLevel = 14.4746.obs;
  final RxBool isTrafficEnabled = false.obs;
  final selectedVehicle = Rxn<LocationVehicleInfo>();

  GoogleMapController? _mapController;

  @override
  void onInit() {
    super.onInit();
    selectedVehicle.value = _resolveInitialVehicle();
  }

  LocationVehicleInfo _resolveInitialVehicle() {
    if (Get.isRegistered<HomeController>()) {
      final vehicles = Get.find<HomeController>().vehicles;
      if (vehicles.isNotEmpty) {
        final v = vehicles.first;
        return LocationVehicleInfo(
          name: v.plateNumber,
          status: v.status,
          statusDuration: v.statusDuration.isEmpty ? '08h 30m' : v.statusDuration,
          deviceTime: v.lastUpdated.isEmpty
              ? 'Aug 02,2025 02:30:40 PM'
              : v.lastUpdated,
          location: v.address.isEmpty
              ? 'Puthiyakavu Junction,Karunagappalli, Kerala 690539, India.'
              : v.address,
          engine: v.isIgnitionOn ? 'On' : 'Off',
          voltage: '13.78 V',
          imei: v.deviceId,
        );
      }
    }
    return const LocationVehicleInfo(
      name: 'KL 07 A 0518',
      status: 'Running',
      statusDuration: '08h 30m',
      deviceTime: 'Aug 02,2025 02:30:40 PM',
      location:
          'Puthiyakavu Junction,Karunagappalli, Kerala 690539, India.',
      engine: 'On',
      voltage: '13.78 V',
      imei: '',
    );
  }

  void onMapCreated(GoogleMapController controller) {
    _mapController = controller;
  }

  void toggleTraffic() {
    isTrafficEnabled.value = !isTrafficEnabled.value;
  }

  void centerOnVehicle() {
    if (_mapController != null) {
      _mapController!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: currentCenter.value, zoom: zoomLevel.value),
        ),
      );
    }
  }

  void zoomIn() {
    zoomLevel.value++;
    _mapController?.animateCamera(CameraUpdate.zoomIn());
  }

  void zoomOut() {
    zoomLevel.value--;
    _mapController?.animateCamera(CameraUpdate.zoomOut());
  }

  @override
  void onClose() {
    _mapController?.dispose();
    super.onClose();
  }
}
