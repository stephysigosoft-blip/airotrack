import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:airotrack/Utils/app_colors.dart';
import 'package:airotrack/Models/HistoryModel.dart';
import 'package:airotrack/Services/ReverseGeocodeService.dart';
import '../../controllers/history_controller.dart';
import 'history_icon_stat.dart';
import 'history_playback_controls.dart';
import 'history_row_detail.dart';
import 'history_dashed_line.dart';
import 'history_section_divider.dart';

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
        final stops = controller.stopLocations;
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
            if (stops.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: height * 0.03),
                  child: Text(
                    'No stops for selected dates',
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
                  final selected = controller.selectedStopIndex.value;
                  return SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final stop = stops[index];
                        final isSelected = selected == index;
                        return Padding(
                          padding: EdgeInsets.only(bottom: height * 0.012),
                          child: Material(
                            color: isSelected
                                ? const Color(0xFFE8F7FC)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () => controller.selectStop(index),
                              child: Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: width * 0.01,
                                  vertical: height * 0.008,
                                ),
                                child: _StopAnalysisItem(
                                  stop: stop,
                                  stopNumber: stop.index ?? (index + 1),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                      childCount: stops.length,
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

class _StopAnalysisItem extends StatelessWidget {
  final HistoryStopLocation stop;
  final int stopNumber;

  const _StopAnalysisItem({
    required this.stop,
    required this.stopNumber,
  });

  @override
  Widget build(BuildContext context) {
    final hasAddress =
        stop.address != null &&
        stop.address!.trim().isNotEmpty &&
        stop.address!.toLowerCase() != 'null';
    final locationText = hasAddress
        ? ReverseGeocodeService.withoutPincode(stop.address)
        : 'Fetching location…';
    final showAddress = locationText.isNotEmpty && hasAddress;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: Color(0xFF009FE3),
                shape: BoxShape.circle,
              ),
              child: Text(
                '$stopNumber',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,  
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                showAddress ? locationText : 'Fetching location…',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: showAddress ? Colors.black87 : Colors.grey,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.red.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Ignition off',
                style: TextStyle(
                  color: Colors.red.shade700,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const HistoryDashedLine(),
        const SizedBox(height: 8),
        HistoryRowDetail(
          icon: Icons.play_circle_outline,
          label: 'Arrival:',
          value: stop.arrivalTime ?? '–',
        ),
        const SizedBox(height: 8),
        const HistoryDashedLine(),
        const SizedBox(height: 8),
        HistoryRowDetail(
          icon: Icons.access_time,
          label: 'Duration:',
          value: stop.duration ?? '–',
        ),
        const SizedBox(height: 8),
        const HistoryDashedLine(),
        const SizedBox(height: 8),
        HistoryRowDetail(
          icon: Icons.stop_circle_outlined,
          label: 'Departure:',
          value: stop.departureTime ?? '–',
        ),
        const SizedBox(height: 16),
        const HistorySectionDivider(),
        const SizedBox(height: 8),
      ],
    );
  }
}
