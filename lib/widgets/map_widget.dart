import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../Configs/ApiConfigs.dart';

enum AiroMapStyle {
  osm,
  mapboxStreets,
  /// Satellite + road labels (top-down hybrid, matches live-track screenshot).
  mapboxSatellite,
}

class AiroMapWidget extends StatelessWidget {
  final LatLng? initialCenter;
  final double initialZoom;
  final MapController? mapController;
  final dynamic markers;
  final dynamic polylines;
  final VoidCallback? onTap;
  final void Function(MapEvent)? onMapEvent;
  final void Function(MapCamera, bool)? onPositionChanged;
  final AiroMapStyle mapStyle;
  /// Keep map north-up (no rotate / perspective). Always a top-down view.
  final bool lockNorthUp;

  AiroMapWidget({
    Key? key,
    this.onPositionChanged,
    this.onMapEvent,
    this.initialCenter,
    this.initialZoom = 13.0,
    this.mapController,
    this.markers,
    this.polylines,
    this.onTap,
    this.mapStyle = AiroMapStyle.osm,
    this.lockNorthUp = true,
  }) : super(key: key);

  String _tileUrl() {
    final token = ApiConfig.mapboxAccessToken.trim();
    final tokenOk = token.isNotEmpty &&
        !token.contains('<') &&
        !token.contains('>') &&
        !token.toLowerCase().contains('your_mapbox_access_token');

    if (!tokenOk || mapStyle == AiroMapStyle.osm) {
      return 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
    }

    final styleId = mapStyle == AiroMapStyle.mapboxSatellite
        ? 'satellite-streets-v12'
        : 'streets-v12';
    return 'https://api.mapbox.com/styles/v1/mapbox/$styleId'
        '/tiles/256/{z}/{x}/{y}@2x?access_token=$token';
  }

  @override
  Widget build(BuildContext context) {
    final interactionFlags = lockNorthUp
        ? (InteractiveFlag.all &
            ~InteractiveFlag.rotate &
            ~InteractiveFlag.pinchMove)
        : InteractiveFlag.all;

    return FlutterMap(
      mapController: mapController,
      options: MapOptions(
        initialCenter: initialCenter ?? const LatLng(11.8745, 75.3704),
        initialZoom: initialZoom,
        initialRotation: 0,
        interactionOptions: InteractionOptions(flags: interactionFlags),
        onTap: (tapPosition, point) => onTap?.call(),
        onMapEvent: onMapEvent,
        onPositionChanged: onPositionChanged,
      ),
      children: [
        TileLayer(
          key: ValueKey(mapStyle),
          urlTemplate: _tileUrl(),
          userAgentPackageName: 'com.airotrack.app',
          maxZoom: 22,
        ),
        Builder(
          builder: (context) {
            final p = polylines;
            if (p is RxList<Polyline>) {
              return Obx(() {
                if (p.length >= 0) {
                  return PolylineLayer(polylines: p.toList());
                }
                return const SizedBox.shrink();
              });
            } else if (p is List<Polyline>) {
              return PolylineLayer(polylines: p);
            }
            return const SizedBox.shrink();
          },
        ),
        Builder(
          builder: (context) {
            final m = markers;
            if (m is RxList<Marker>) {
              return Obx(() {
                if (m.length >= 0) {
                  return MarkerLayer(markers: m.toList());
                }
                return const SizedBox.shrink();
              });
            } else if (m is List<Marker>) {
              return MarkerLayer(markers: m);
            }
            return const SizedBox.shrink();
          },
        ),
      ],
    );
  }
}
