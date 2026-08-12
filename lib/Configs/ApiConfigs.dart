class ApiConfig {
  // This is the Test Server URL
  static String baseUrl =
      "https://api-dev.airotrack.in/website/";
      //"https://api.airotrack.in/website/";
      //"https://dev-api.airotrack.in/airotrack-api/public/website/";

  // TCP server base URL — used for real-time device position (live tracking)
  static const String tcpBaseUrl =
      "https://dev-api.airotrack.in/airotrack-tcp/public";

  // This is the base Image URL
  static String imageUrl =
      "https://ourworks.co.in/saimpex-backend/public/storage/";

  /// Mapbox public token for Map Matching API (snap GPS track to road).
  static const String mapboxAccessToken =
      'pk.eyJ1Ijoic2FpbXBleGRldmxvcG1lbnQiLCJhIjoiY21rZXg1ZDA4MGFjZDNqcXptZmN6eXJwYyJ9.MhqmUUhQgPHXj-0nwnz9ww';
}

class ApiEndPoints {
  static String login = "login";
  static String home = "home";
  static String alerts = "alerts";
  static String vehicleHistory = "track_vehicle";
  static String liveTrack = "live_track";
  static String liveTrackSnapshot = "live_track_snapshot";
  static String updateOdometer = "update_odometer";
  static String addGeofence = "add_geofence";
  static String geofences = "geofences";
  static String geofenceSyncedVehicles = "geofence_synced_vehicles";
  static String geofenceUnsyncedVehicles = "geofence_unsynced_vehicles";
  /// Sync selected vehicles onto a geofence: geofence_id + vehicle_ids[]
  static String syncGeofenceVehicles = "sync_geofence_vehicles";
  /// Sync selected geofences onto a vehicle: vehicle_id + geofence_ids[]
  static String syncVehicleGeofences = "sync_vehicle_geofences";
  static String vehicleSyncedGeofences = "vehicle_synced_geofences";
  static String vehicleUnsyncedGeofences = "vehicle_unsynced_geofences";
  /// Linked geofences for a vehicle (full geometry for map display).
  static String vehicleGeofences = "vehicle_geofences";
}
