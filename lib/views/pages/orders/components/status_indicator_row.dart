// import 'package:blockatie/provider/orders.dart';
// import 'package:blockatie/views/pages/orders/components/dotted_line.dart';
// import 'package:blockatie/views/pages/orders/components/status_indicator.dart';
// import 'package:flutter/material.dart';
// import 'package:provider/provider.dart';

// class StatusIndicatorRow extends StatelessWidget {
//   const StatusIndicatorRow({
//     super.key,
//   });

//   @override
//   Widget build(BuildContext context) {
//     return Consumer<OrderStatusProvider>(
//       builder: (context, orderProvider, child) {
//         return Padding(
//           padding: const EdgeInsets.symmetric(horizontal: 25),
//           child: SizedBox(
//             child: SingleChildScrollView(
//               scrollDirection: Axis.horizontal,
//               child: IntrinsicWidth(
//                 child: Row(
//                   crossAxisAlignment: CrossAxisAlignment.center,
//                   mainAxisSize: MainAxisSize.min,
//                   children: [
//                     // Pending
//                     StatusIndicator(
//                       icon: 'assets/images/icn_pending.png',
//                       label: 'Pending',
//                       isActive: orderProvider.isStatusActive(0),
//                       isCompleted: orderProvider.isStatusCompleted(0),
//                       onTap: () => orderProvider.updateStatusByIndex(0),
//                     ),
//                     SizedBox(
//                       width: 30,
//                       child: Align(
//                         alignment: Alignment.center,
//                         child: DottedLine(
//                           isCompleted: orderProvider.currentStatusIndex > 0,
//                         ),
//                       ),
//                     ),
//                     // Processing
//                     StatusIndicator(
//                       icon: 'assets/images/icn_processing.png',
//                       label: 'Processing',
//                       isActive: orderProvider.isStatusActive(1),
//                       isCompleted: orderProvider.isStatusCompleted(1),
//                       onTap: () => orderProvider.updateStatusByIndex(1),
//                     ),
//                     SizedBox(
//                       width: 30,
//                       child: DottedLine(
//                         isCompleted: orderProvider.currentStatusIndex > 1,
//                       ),
//                     ),
//                     // Dispatched
//                     StatusIndicator(
//                       icon: 'assets/images/icn_dispatched.png',
//                       label: 'Dispatched',
//                       isActive: orderProvider.isStatusActive(2),
//                       isCompleted: orderProvider.isStatusCompleted(2),
//                       onTap: () => orderProvider.updateStatusByIndex(2),
//                     ),
//                     SizedBox(
//                       width: 30,
//                       child: DottedLine(
//                         isCompleted: orderProvider.currentStatusIndex > 2,
//                       ),
//                     ),
//                     // In Transit
//                     StatusIndicator(
//                       icon: 'assets/images/icn_intransit.png',
//                       label: 'In Transit',
//                       isActive: orderProvider.isStatusActive(3),
//                       isCompleted: orderProvider.isStatusCompleted(3),
//                       onTap: () => orderProvider.updateStatusByIndex(3),
//                     ),
//                     SizedBox(
//                       width: 30,
//                       child: DottedLine(
//                         isCompleted: orderProvider.currentStatusIndex > 3,
//                       ),
//                     ),
//                     // Out for Delivery
//                     StatusIndicator(
//                       icon: 'assets/images/icn_outfordelivery.png',
//                       label: 'Out for Delivery',
//                       isActive: orderProvider.isStatusActive(4),
//                       isCompleted: orderProvider.isStatusCompleted(4),
//                       onTap: () => orderProvider.updateStatusByIndex(4),
//                     ),
//                     SizedBox(
//                       width: 30,
//                       child: DottedLine(
//                         isCompleted: orderProvider.currentStatusIndex > 4,
//                       ),
//                     ),
//                     // Delivered
//                     StatusIndicator(
//                       icon: 'assets/images/icn_delivered.png',
//                       label: 'Delivered',
//                       isActive: orderProvider.isStatusActive(5),
//                       isCompleted: orderProvider.isStatusCompleted(5),
//                       onTap: () => orderProvider.updateStatusByIndex(5),
//                     ),
//                     SizedBox(
//                       width: 30,
//                       child: DottedLine(
//                         isCompleted: orderProvider.currentStatusIndex > 5,
//                       ),
//                     ),
//                     // Cancelled
//                     StatusIndicator(
//                       icon: 'assets/images/icn_cancelled.png',
//                       label: 'Cancelled',
//                       isActive: orderProvider.isStatusActive(6),
//                       isCompleted: orderProvider.isStatusCompleted(6),
//                       onTap: () => orderProvider.updateStatusByIndex(6),
//                     ),
//                     SizedBox(
//                       width: 30,
//                       child: DottedLine(
//                         isCompleted: orderProvider.currentStatusIndex > 6,
//                       ),
//                     ),
//                     // Returned
//                     StatusIndicator(
//                       icon: 'assets/images/icn_returned.png',
//                       label: 'Returned',
//                       isActive: orderProvider.isStatusActive(7),
//                       isCompleted: orderProvider.isStatusCompleted(7),
//                       onTap: () => orderProvider.updateStatusByIndex(7),
//                     ),
//                     SizedBox(
//                       width: 30,
//                       child: DottedLine(
//                         isCompleted: orderProvider.currentStatusIndex > 7,
//                       ),
//                     ),
//                     // Failed Delivery
//                     StatusIndicator(
//                       icon: 'assets/images/icn_failed_delivery.png',
//                       label: 'Failed Delivery',
//                       isActive: orderProvider.isStatusActive(8),
//                       isCompleted: orderProvider.isStatusCompleted(8),
//                       onTap: () => orderProvider.updateStatusByIndex(8),
//                     ),
//                     SizedBox(
//                       width: 30,
//                       child: DottedLine(
//                         isCompleted: orderProvider.currentStatusIndex > 8,
//                       ),
//                     ),
//                     // Awaiting Pickup
//                     StatusIndicator(
//                       icon: 'assets/images/icn_awaiting_pickup.png',
//                       label: 'Awaiting Pickup',
//                       isActive: orderProvider.isStatusActive(9),
//                       isCompleted: orderProvider.isStatusCompleted(9),
//                       onTap: () => orderProvider.updateStatusByIndex(9),
//                     ),
//                     SizedBox(
//                       width: 30,
//                       child: DottedLine(
//                         isCompleted: orderProvider.currentStatusIndex > 9,
//                       ),
//                     ),
//                     // Completed
//                     StatusIndicator(
//                       icon: 'assets/images/icn_cmplted.png',
//                       label: 'Completed',
//                       isActive: orderProvider.isStatusActive(10),
//                       isCompleted: orderProvider.isStatusCompleted(10),
//                       onTap: () => orderProvider.updateStatusByIndex(10),
//                     ),
//                   ],
//                 ),
//               ),
//             ),
//           ),
//         );
//       },
//     );
//   }
// }

import 'package:blockatie/provider/orders.dart';
import 'package:blockatie/views/pages/orders/components/dotted_line.dart';
import 'package:blockatie/views/pages/orders/components/status_indicator.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class StatusIndicatorRow extends StatefulWidget {
  const StatusIndicatorRow({super.key});

  @override
  State<StatusIndicatorRow> createState() => _StatusIndicatorRowState();
}

class _StatusIndicatorRowState extends State<StatusIndicatorRow> {
  late ScrollController _scrollController;
  int _lastActiveIndex = -1;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToActiveStatus(int activeIndex) {
    if (_lastActiveIndex != activeIndex && mounted) {
      _lastActiveIndex = activeIndex;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients && mounted) {
          // Calculate the position to scroll to
          // Each status indicator + dotted line takes approximately 68 pixels (38 + 30)
          const double itemWidth = 68.0;
          final double screenWidth = MediaQuery.of(context).size.width;
          final double targetPosition =
              (activeIndex * itemWidth) - (screenWidth / 2) + (itemWidth / 2);

          // Ensure we don't scroll beyond bounds
          final double maxScroll = _scrollController.position.maxScrollExtent;
          final double scrollPosition = targetPosition.clamp(0.0, maxScroll);

          _scrollController.animateTo(
            scrollPosition,
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeInOut,
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<OrderStatusProvider>(
      builder: (context, orderProvider, child) {
        // Auto-scroll to active status when it changes
        _scrollToActiveStatus(orderProvider.currentStatusIndex);

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 25),
          child: SizedBox(
            child: SingleChildScrollView(
              controller: _scrollController,
              scrollDirection: Axis.horizontal,
              child: IntrinsicWidth(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Pending
                    StatusIndicator(
                      icon: 'assets/images/icn_pending.png',
                      label: tr("pending"),
                      isActive: orderProvider.isStatusActive(0),
                      isCompleted: orderProvider.isStatusCompleted(0),
                      // onTap: () => orderProvider.updateStatusByIndex(0),
                    ),
                    SizedBox(
                      width: 30,
                      child: Align(
                        alignment: Alignment.center,
                        child: DottedLine(
                          isCompleted: orderProvider.currentStatusIndex > 0,
                        ),
                      ),
                    ),
                    // Processing
                    StatusIndicator(
                      icon: 'assets/images/icn_processing.png',
                      label: tr("processing"),
                      isActive: orderProvider.isStatusActive(1),
                      isCompleted: orderProvider.isStatusCompleted(1),
                      // onTap: () => orderProvider.updateStatusByIndex(1),
                    ),
                    SizedBox(
                      width: 30,
                      child: DottedLine(
                        isCompleted: orderProvider.currentStatusIndex > 1,
                      ),
                    ),
                    // Dispatched
                    StatusIndicator(
                      icon: 'assets/images/icn_dispatched.png',
                      label: tr("dispatched"),
                      isActive: orderProvider.isStatusActive(2),
                      isCompleted: orderProvider.isStatusCompleted(2),
                      // onTap: () => orderProvider.updateStatusByIndex(2),
                    ),
                    SizedBox(
                      width: 30,
                      child: DottedLine(
                        isCompleted: orderProvider.currentStatusIndex > 2,
                      ),
                    ),
                    // In Transit
                    StatusIndicator(
                      icon: 'assets/images/icn_intransit.png',
                      label: tr("inTransit"),
                      isActive: orderProvider.isStatusActive(3),
                      isCompleted: orderProvider.isStatusCompleted(3),
                      // onTap: () => orderProvider.updateStatusByIndex(3),
                    ),
                    SizedBox(
                      width: 30,
                      child: DottedLine(
                        isCompleted: orderProvider.currentStatusIndex > 3,
                      ),
                    ),
                    // Out for Delivery
                    StatusIndicator(
                      icon: 'assets/images/icn_outfordelivery.png',
                      label: tr("outForDelivery"),
                      isActive: orderProvider.isStatusActive(4),
                      isCompleted: orderProvider.isStatusCompleted(4),
                      // onTap: () => orderProvider.updateStatusByIndex(4),
                    ),
                    SizedBox(
                      width: 30,
                      child: DottedLine(
                        isCompleted: orderProvider.currentStatusIndex > 4,
                      ),
                    ),
                    // Delivered
                    StatusIndicator(
                      icon: 'assets/images/icn_delivered.png',
                      label: tr("delivered"),
                      isActive: orderProvider.isStatusActive(5),
                      isCompleted: orderProvider.isStatusCompleted(5),
                      // onTap: () => orderProvider.updateStatusByIndex(5),
                    ),
                    SizedBox(
                      width: 30,
                      child: DottedLine(
                        isCompleted: orderProvider.currentStatusIndex > 5,
                      ),
                    ),
                    // Cancelled
                    StatusIndicator(
                      icon: 'assets/images/icn_cancelled.png',
                      label: tr("cancelled"),
                      isActive: orderProvider.isStatusActive(6),
                      isCompleted: orderProvider.isStatusCompleted(6),
                      // onTap: () => orderProvider.updateStatusByIndex(6),
                    ),
                    SizedBox(
                      width: 30,
                      child: DottedLine(
                        isCompleted: orderProvider.currentStatusIndex > 6,
                      ),
                    ),
                    // Returned
                    StatusIndicator(
                      icon: 'assets/images/icn_returned.png',
                      label: tr("returned"),
                      isActive: orderProvider.isStatusActive(7),
                      isCompleted: orderProvider.isStatusCompleted(7),
                      // onTap: () => orderProvider.updateStatusByIndex(7),
                    ),
                    SizedBox(
                      width: 30,
                      child: DottedLine(
                        isCompleted: orderProvider.currentStatusIndex > 7,
                      ),
                    ),
                    // Failed Delivery
                    StatusIndicator(
                      icon: 'assets/images/icn_failed_delivery.png',
                      label: tr("failedDelivery"),
                      isActive: orderProvider.isStatusActive(8),
                      isCompleted: orderProvider.isStatusCompleted(8),
                      // onTap: () => orderProvider.updateStatusByIndex(8),
                    ),
                    SizedBox(
                      width: 30,
                      child: DottedLine(
                        isCompleted: orderProvider.currentStatusIndex > 8,
                      ),
                    ),
                    // Awaiting Pickup
                    StatusIndicator(
                      icon: 'assets/images/icn_awaiting_pickup.png',
                      label: tr("awaitingPickup"),
                      isActive: orderProvider.isStatusActive(9),
                      isCompleted: orderProvider.isStatusCompleted(9),
                      // onTap: () => orderProvider.updateStatusByIndex(9),
                    ),
                    SizedBox(
                      width: 30,
                      child: DottedLine(
                        isCompleted: orderProvider.currentStatusIndex > 9,
                      ),
                    ),
                    // Completed
                    StatusIndicator(
                      icon: 'assets/images/icn_cmplted.png',
                      label: tr("completed"),
                      isActive: orderProvider.isStatusActive(10),
                      isCompleted: orderProvider.isStatusCompleted(10),
                      // onTap: () => orderProvider.updateStatusByIndex(10),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
