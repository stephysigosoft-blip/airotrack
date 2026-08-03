import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:airotrack/Utils/app_colors.dart';
import 'package:airotrack/Models/HistoryModel.dart';
import 'package:airotrack/Services/ReverseGeocodeService.dart';
import '../../controllers/history_controller.dart';
import 'history_icon_stat.dart';
import 'history_playback_controls.dart';

class HistoryBottomSheet extends StatelessWidget {
  final ScrollController scrollController;
  final HistoryController controller;

  const HistoryBottomSheet({
    Key? key,
    required this.scrollController,
    required this.controller,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final height = MediaQuery.sizeOf(context).height;
    final horizontalPadding = width * 0.04;
    final verticalSpacing = height * 0.02;
    final cornerRadius = width * 0.09;
    final handleWidth = width * 0.13;
    final handleHeight = height * 0.005;
    final iconSize = width * 0.055;
    final smallSpacing = width * 0.02;

    return Container(
      width: width,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(cornerRadius),
          topRight: Radius.circular(cornerRadius),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: width * 0.025,
            offset: Offset(0, -height * 0.006),
          ),
        ],
      ),
      child: Obx(() {
        if (controller.isLoading.value) {
          return Center(
            child: CircularProgressIndicator(color: AppColors.primaryBlue),
          );
        }
        final items = controller.vehicleHistoryItems;
        return CustomScrollView(
          controller: scrollController,
          slivers: [
            SliverToBoxAdapter(
              child: Column(
                children: [
                  SizedBox(height: height * 0.015),
                  Center(
                    child: Container(
                      width: handleWidth,
                      height: handleHeight,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(width * 0.005),
                      ),
                    ),
                  ),
                  SizedBox(height: height * 0.018),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        GestureDetector(
                          onTap: () => controller.pickFromDate(context),
                          behavior: HitTestBehavior.opaque,
                          child: Row(
                            children: [
                              Image.asset(
                                'lib/Asset/Icons/Calender.png',
                                width: iconSize,
                                height: iconSize,
                                color: Colors.red,
                              ),
                              SizedBox(width: smallSpacing),
                              Obx(
                                () => Text(
                                  "From: ${controller.fromDate.value}",
                                  style: TextStyle(
                                    fontSize: width * 0.028,
                                    color: Colors.black,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Obx(
                          () => Text(
                            controller.vehicleId.value,
                            style: TextStyle(
                              color: const Color(0xFF009FE3),
                              fontWeight: FontWeight.bold,
                              fontSize: width * 0.022,
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: () => controller.pickToDate(context),
                          behavior: HitTestBehavior.opaque,
                          child: Row(
                            children: [
                              Image.asset(
                                'lib/Asset/Icons/Calender.png',
                                width: iconSize,
                                height: iconSize,
                                color: Colors.red,
                              ),
                              SizedBox(width: smallSpacing),
                              Obx(
                                () => Text(
                                  "To: ${controller.toDate.value}",
                                  style: TextStyle(
                                    fontSize: width * 0.028,
                                    color: Colors.black,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: verticalSpacing),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        HistoryIconStat(
                          assetPath: 'lib/Asset/Icons/KmPh.png',
                          value: controller.currentSpeed,
                          iconColor: Colors.red,
                        ),
                        HistoryIconStat(
                          assetPath: 'lib/Asset/Icons/Time.png',
                          value: controller.duration,
                          iconColor: Colors.red,
                        ),
                        HistoryIconStat(
                          assetPath: 'lib/Asset/Icons/Distance.png',
                          value: controller.totalDistance,
                          iconColor: Colors.red,
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: verticalSpacing * 0.6),
                  HistoryPlaybackControls(controller: controller),
                  SizedBox(height: verticalSpacing),
                ],
              ),
            ),
            if (items.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: height * 0.03),
                  child: Text(
                    'No history for selected dates',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: width * 0.035,
                      color: Colors.grey,
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                sliver: Obx(() {
                  final selected =
                      controller.selectedVehicleHistoryIndex.value;
                  return SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final item = items[index];
                        final isSelected = selected == index;
                        return Padding(
                          padding: EdgeInsets.only(bottom: height * 0.014),
                          child: _VehicleHistoryCard(
                            item: item,
                            selected: isSelected,
                            onTap: () =>
                                controller.selectVehicleHistoryItem(index),
                          ),
                        );
                      },
                      childCount: items.length,
                    ),
                  );
                }),
              ),
            SliverToBoxAdapter(child: SizedBox(height: height * 0.12)),
          ],
        );
      }),
    );
  }
}

class _VehicleHistoryCard extends StatelessWidget {
  final HistoryVehicleHistoryItem item;
  final bool selected;
  final VoidCallback onTap;

  const _VehicleHistoryCard({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  static final _displayFormat = DateFormat('hh:mm:ss a - dd MMM, yyyy');
  static final _parseFormats = <DateFormat>[
    DateFormat('yyyy-MM-dd HH:mm:ss'),
    DateFormat("yyyy-MM-dd'T'HH:mm:ss"),
    DateFormat('dd MMM yyyy HH:mm:ss'),
  ];

  String _formatTime(String? raw) {
    if (raw == null || raw.trim().isEmpty) return '–';
    final text = raw.trim();
    DateTime? parsed = DateTime.tryParse(text);
    if (parsed == null) {
      for (final format in _parseFormats) {
        try {
          parsed = format.parse(text);
          break;
        } catch (_) {}
      }
    }
    if (parsed == null) return text;
    return _displayFormat.format(parsed);
  }

  @override
  Widget build(BuildContext context) {
    final isTrip = item.isTrip;
    final bg = isTrip ? const Color(0xFFE8F8EE) : const Color(0xFFFFEBEE);
    final badgeBg = isTrip ? const Color(0xFFC8E6C9) : Colors.red;
    final badgeFg = isTrip ? const Color(0xFF2E7D32) : Colors.white;
    final badgeLabel = isTrip ? 'Trip' : 'Ignition off';
    final startLocationText = _locationLabel(
      address: item.startAddress,
      hasCoords: item.hasValidStartCoordinates,
    );
    final endLocationText = _locationLabel(
      address: item.endAddress,
      hasCoords: item.hasValidEndCoordinates,
    );

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(14),
      elevation: selected ? 2 : 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (isTrip)
                _TripHeader(item: item, badgeBg: badgeBg, badgeFg: badgeFg)
              else
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: badgeBg,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      badgeLabel,
                      style: TextStyle(
                        color: badgeFg,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              _TimeRow(
                icon: Icons.play_arrow,
                label: isTrip ? 'Started:' : 'Parked at:',
                value: _formatTime(item.startTime),
              ),
              const SizedBox(height: 8),
              _LocationLine(
                text: startLocationText,
                resolved: item.startAddress?.trim().isNotEmpty == true,
              ),
              const Divider(height: 18, thickness: 0.6),
              _TimeRow(
                icon: Icons.access_time,
                label: 'Duration:',
                value: HistoryVehicleHistoryItem.formatDurationDisplay(
                  item.duration,
                ),
              ),
              const Divider(height: 18, thickness: 0.6),
              _TimeRow(
                icon: Icons.stop,
                label: isTrip ? 'Stopped:' : 'Moved at:',
                value: _formatTime(item.endTime),
              ),
              if (isTrip) ...[
                const SizedBox(height: 8),
                _LocationLine(
                  text: endLocationText,
                  resolved: item.endAddress?.trim().isNotEmpty == true,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _locationLabel({required String? address, required bool hasCoords}) {
    final text = address?.trim();
    if (text != null && text.isNotEmpty && text.toLowerCase() != 'null') {
      return ReverseGeocodeService.withoutPincode(text);
    }
    if (hasCoords) return 'Fetching location…';
    return 'Location unavailable';
  }
}

class _LocationLine extends StatelessWidget {
  final String text;
  final bool resolved;

  const _LocationLine({
    required this.text,
    required this.resolved,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.location_on_outlined,
          size: 16,
          color: Colors.grey.shade700,
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: resolved ? Colors.black87 : Colors.grey,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _TripHeader extends StatelessWidget {
  final HistoryVehicleHistoryItem item;
  final Color badgeBg;
  final Color badgeFg;

  const _TripHeader({
    required this.item,
    required this.badgeBg,
    required this.badgeFg,
  });

  @override
  Widget build(BuildContext context) {
    final km = item.totalKm;
    final distanceText = km == null
        ? 'Distance: –'
        : 'Distance: ${km.toStringAsFixed(2)} Km';
    final speedRaw = item.speed?.trim();
    final speedText = (speedRaw == null || speedRaw.isEmpty)
        ? 'Max speed: –'
        : 'Max speed: $speedRaw km/h';

    return Row(
      children: [
        Expanded(
          child: Row(
            children: [
              Icon(Icons.directions_run, size: 16, color: Colors.grey.shade700),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  distanceText,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade800,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          decoration: BoxDecoration(
            color: badgeBg,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            'Trip',
            style: TextStyle(
              color: badgeFg,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ),
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Icon(Icons.speed, size: 16, color: Colors.grey.shade700),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  speedText,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade800,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TimeRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _TimeRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.grey.shade400),
          ),
          child: Icon(icon, size: 16, color: Colors.grey.shade700),
        ),
        const SizedBox(width: 10),
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
              height: 1.25,
            ),
            textAlign: TextAlign.right,
            softWrap: true,
          ),
        ),
      ],
    );
  }
}
