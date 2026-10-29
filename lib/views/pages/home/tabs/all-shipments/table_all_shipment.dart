import 'dart:async';

import 'package:blockatie/constants/colors.dart';
import 'package:blockatie/constants/helper.dart';
import 'package:blockatie/models/order_status_modle.dart';
import 'package:blockatie/models/shipment.dart';
import 'package:blockatie/provider/home.dart';
import 'package:blockatie/provider/shipment.dart';
import 'package:blockatie/provider/shipment_instsnt.dart';
import 'package:blockatie/utils/driver_shipment_actions.dart';
import 'package:blockatie/utils/nav.dart';
import 'package:blockatie/utils/text_direction.dart';
import 'package:blockatie/views/pages/home/components/header.dart';
import 'package:blockatie/views/pages/home/tabs/all-shipments/components/pagination_row.dart';
import 'package:blockatie/views/pages/orders/order_details.dart';
import 'package:blockatie/views/widgets/driver_chat_bubble.dart';
import 'package:blockatie/views/widgets/status_update_sheet.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

class TableAllShipment extends StatefulWidget {
  const TableAllShipment({
    super.key,
    this.showHeader = false,
    this.shipmentScope,
  });

  final bool? showHeader;
  final String? shipmentScope;

  @override
  State<TableAllShipment> createState() => _TableAllShipmentState();
}

class _TableAllShipmentState extends State<TableAllShipment> with Helper {
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadInitialData());
  }

  Future<void> _loadInitialData() async {
    if (!mounted || _isInitialized) return;
    _isInitialized = true;

    final shipmentProvider = context.read<ShipmentProvider>();
    if (widget.shipmentScope != null) {
      await shipmentProvider.selectShipmentScope(widget.shipmentScope!);
    } else if (!shipmentProvider.hasLoaded && !shipmentProvider.isLoading) {
      unawaited(shipmentProvider.getAllShipments());
    }

    unawaited(context.read<HomeProvider>().getOrderStatus());
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: SafeArea(
        child: Consumer2<ShipmentProvider, HomeProvider>(
          builder: (context, shipmentProvider, homeProvider, _) {
            if (widget.shipmentScope != null &&
                shipmentProvider.shipmentScope != widget.shipmentScope) {
              return const Center(child: CircularProgressIndicator());
            }
            return RefreshIndicator(
              color: AppColors.primary,
              onRefresh: () async {
                await Future.wait([
                  shipmentProvider.onRefresh(),
                  homeProvider.getOrderStatus(force: true),
                ]);
              },
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                slivers: [
                  if (widget.showHeader == true)
                    const SliverToBoxAdapter(
                      child: HomeHeader(notificationCount: 1),
                    ),
                  SliverPadding(
                    // Clears the floating chat launcher, not just the
                    // bottom-navigation pill: at 110 the last card sat under
                    // the bubble.
                    padding: EdgeInsets.fromLTRB(
                      18,
                      16,
                      18,
                      DriverChatBubble.reservedBottomSpace + 16,
                    ),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        _AssignedShipmentsHeader(
                          totalCount: shipmentProvider.totalCount,
                          // Only the very first read blanks the total. A page
                          // change keeps the figure, which has not changed.
                          isLoading:
                              shipmentProvider.isLoading &&
                              !shipmentProvider.hasLoaded,
                        ),
                        const SizedBox(height: 18),
                        // One state at a time, in this order. A failed read
                        // used to render the error card *and* the empty state,
                        // telling the driver there is no work when the app
                        // simply could not ask.
                        ..._buildListState(context, shipmentProvider),
                      ]),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  /// Exactly one of: loading, error, empty, list.
  List<Widget> _buildListState(
    BuildContext context,
    ShipmentProvider provider,
  ) {
    if (provider.isLoading && !provider.hasLoaded) {
      return const [_AssignedLoadingList()];
    }

    if (provider.hasError) {
      final error = _AssignedErrorCard(
        message: _errorMessage(context, provider.failure),
        onRetry: () => provider.getAllShipments(force: true),
      );

      // Nothing has ever loaded: the error is the whole story. Showing the
      // empty state here would tell the driver they have no work when the app
      // only failed to ask.
      if (!provider.hasLoaded) return [error];

      // A page already on screen failed to change. The rows stay — they are
      // still the page `currentPage` names, and blanking them would lose the
      // driver's place — with the failure stated above them.
      return [
        error,
        const SizedBox(height: 18),
        ..._buildList(context, provider),
      ];
    }

    if (provider.paginatedShipments.isEmpty) {
      return [
        _AssignedEmptyState(
          title: _copy(
            context,
            'No assigned shipments right now.',
            'لا توجد شحنات مسندة حالياً.',
          ),
          message: _copy(
            context,
            'Pull to refresh or check instant shipments.',
            'اسحب للتحديث أو افتح الشحنات الفورية.',
          ),
        ),
      ];
    }

    return _buildList(context, provider);
  }

  List<Widget> _buildList(BuildContext context, ShipmentProvider provider) {
    return [
      if (provider.totalPages > 1) buildPagination(context, provider),
      ...provider.paginatedShipments.map(
        (shipment) => Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: DriverAssignedShipmentCard(
            shipment: shipment,
            statusLabel: _shipmentStatusLabel(context, shipment),
            onViewDetails: () => _openShipmentDetails(shipment),
            onCall: () => _callRecipient(shipment),
            onMap: () => _openMap(shipment),
            onUpdateStatus: () => _showUpdateStatusSheet(shipment),
            onStep: (step) => _runStep(shipment, step),
            showDetails: driverShipmentDetailsCardLauncherIsVisible(shipment),
          ),
        ),
      ),
      // The same widget again, so a driver who has read to the bottom of a
      // page does not have to scroll back up to reach the next one.
      if (provider.totalPages > 1) buildPagination(context, provider),
    ];
  }

  /// The card's next step (arrival, pickup or delivery). Whatever the server
  /// answers, the list is read again, so the card shows the server's state
  /// rather than a guess and never offers a step twice.
  Future<void> _runStep(Shipment shipment, DriverShipmentStep step) async {
    final result = await performDriverShipmentStep(
      context,
      shipment: shipment,
      step: step,
    );
    if (result == null || !mounted) return;
    if (result.code == 'SESSION_CHANGED') return;

    final message = result.message.trim();
    _showSnack(
      message.isNotEmpty
          ? message
          : result.success
          ? _copy(context, 'Shipment updated.', 'تم تحديث الشحنة.')
          : _copy(
            context,
            'Unable to update the shipment.',
            'تعذر تحديث الشحنة.',
          ),
    );
    if (result.success && step == DriverShipmentStep.deliver) {
      unawaited(
        context.read<HomeProvider>().getDriverStatistics(context, force: true),
      );
    }
    unawaited(context.read<ShipmentProvider>().getAllShipments(force: true));
  }

  /// Two categories, both worded by the app. The backend's message is never
  /// shown: it is not localized for this endpoint and can carry detail the
  /// driver must not see.
  String _errorMessage(BuildContext context, ShipmentLoadFailure? failure) {
    if (failure == ShipmentLoadFailure.network) {
      return _copy(
        context,
        'No connection. Check your network and try again.',
        'لا يوجد اتصال. تحقق من الشبكة وحاول مرة أخرى.',
      );
    }
    return _copy(
      context,
      'Unable to load shipments. Please try again.',
      'تعذر تحميل الشحنات. حاول مرة أخرى.',
    );
  }

  void _openShipmentDetails(Shipment shipment) {
    Nav.to(
      OrderDetailPage(
        shipment: shipment,
        phoneCustomer: _phoneFor(shipment),
        shipmentId: shipment.id,
        deliveryAdd: shipment.lclient,
        storeAdd: shipment.nstore,
        orderDate: shipment.createdAt,
      ),
      withNav: true,
      navIndex: 1,
    );
  }

  Future<void> _callRecipient(Shipment shipment) async {
    final phone = _phoneFor(shipment);
    if (phone.isEmpty) {
      _showSnack(
        _copy(
          context,
          'Phone number is not available.',
          'رقم الهاتف غير متوفر.',
        ),
      );
      return;
    }

    final uri = Uri.parse('tel:$phone');
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!mounted || launched) return;
    _showSnack(_copy(context, 'Unable to start call.', 'تعذر بدء الاتصال.'));
  }

  Future<void> _openMap(Shipment shipment) async {
    final query = _mapQueryFor(shipment);
    if (query.isEmpty) {
      _showSnack(
        _copy(context, 'Location is not available.', 'الموقع غير متوفر.'),
      );
      return;
    }

    final uri = Uri.https('www.google.com', '/maps/search/', {
      'api': '1',
      'query': query,
    });
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!mounted || launched) return;
    _showSnack(_copy(context, 'Unable to open map.', 'تعذر فتح الخريطة.'));
  }

  Future<void> _showUpdateStatusSheet(Shipment shipment) async {
    if (driverStatusSheetModeForShipment(shipment) ==
        DriverStatusSheetMode.unavailable) {
      return;
    }
    final homeProvider = context.read<HomeProvider>();
    if (homeProvider.orderStatusData == null && !homeProvider.isStatusLoading) {
      await homeProvider.getOrderStatus();
    }
    if (!mounted) return;

    final statuses =
        homeProvider.orderStatusData?.status
            .where((status) => status.id.isNotEmpty && status.id != '1')
            .toList() ??
        <Status>[];

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) {
        return ShipmentStatusUpdateSheet(
          shipmentId: shipment.id,
          statuses: statuses,
          currentStatusId: shipment.shipmentStatusId,
          currentStatusLabel: _shipmentStatusLabel(context, shipment),
          currentStageLabel: _copy(context, 'Assigned shipment', 'شحنة مسندة'),
          policyNumber: shipment.policyNum,
          doorFeeCollectable: shipment.financial?.doorFeeCollectable ?? 0,
          onSubmit: (status, reason) async {
            final success = await homeProvider.updateStatus(
              shipmentId: shipment.id,
              statusId: status.id,
              reasonId: reason?.reasonId,
              reasonNote: reason?.note,
              feeCollectedAmount: reason?.feeCollectedAmount,
              showSuccessDialog: false,
            );
            if (success && mounted) {
              unawaited(
                context.read<ShipmentProvider>().getAllShipments(force: true),
              );
              _showSnack(
                _copy(
                  context,
                  'Shipment status updated.',
                  'تم تحديث حالة الشحنة.',
                ),
              );
            }
            return success;
          },
        );
      },
    );
    if (mounted)
      await context.read<ShipmentProvider>().getAllShipments(force: true);
  }

  /// The one status resolver, shared with the update sheet, so a shipment
  /// cannot be worded differently on the card and inside the sheet.
  ///
  /// The shipment's own `message` is deliberately not a fallback: it is a
  /// sentence about the shipment, not the name of its status.
  String _shipmentStatusLabel(BuildContext context, Shipment shipment) {
    return getStatusLabel(
      context,
      _statusIdOf(shipment),
      statusNameEn: shipment.statusNameEn,
      statusNameAr: shipment.statusNameAr,
    );
  }

  String _phoneFor(Shipment shipment) {
    if (driverShipmentIsPrePickup(shipment)) {
      return shipment.phclient.trim();
    }
    if (shipment.recipientPhone.trim().isNotEmpty) {
      return shipment.recipientPhone.trim();
    }
    return shipment.phclient.trim();
  }

  String _mapQueryFor(Shipment shipment) {
    final isStoreStage = driverShipmentIsPrePickup(shipment);
    final latitude = double.tryParse(
      isStoreStage ? shipment.latitude ?? '' : shipment.deliveryLatitude ?? '',
    );
    final longitude = double.tryParse(
      isStoreStage
          ? shipment.longitude ?? ''
          : shipment.deliveryLongitude ?? '',
    );
    if (latitude != null &&
        longitude != null &&
        latitude != 0 &&
        longitude != 0) {
      return '$latitude,$longitude';
    }

    if (isStoreStage) {
      final storeAddress = shipment.lclient.trim();
      return storeAddress.isNotEmpty ? storeAddress : shipment.nstore.trim();
    }
    return shipment.deliveryAddress.trim();
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }
}

class _AssignedShipmentsHeader extends StatelessWidget {
  const _AssignedShipmentsHeader({
    required this.totalCount,
    required this.isLoading,
  });

  final int totalCount;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primary, AppColors.gradient2],
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.18),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _copy(context, 'Assigned Shipments', 'الشحنات المسندة'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _copy(
                    context,
                    'Review, call, map, and update your delivery work.',
                    'راجع الشحنات واتصل وافتح الخريطة وحدّث الحالة.',
                  ),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.75),
                    fontSize: 12.5,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (isLoading)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2.4,
                    ),
                  )
                else
                  Text(
                    '$totalCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                const SizedBox(height: 3),
                Text(
                  _copy(context, 'Total', 'المجموع'),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.75),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The established assigned-shipment card visual, shared by every
/// server-authoritative assigned-work list.
class DriverAssignedShipmentCard extends StatelessWidget {
  const DriverAssignedShipmentCard({
    super.key,
    required this.shipment,
    required this.statusLabel,
    required this.onViewDetails,
    required this.onCall,
    required this.onMap,
    required this.onUpdateStatus,
    required this.onStep,
    this.showDetails = true,
  });

  final Shipment shipment;
  final String statusLabel;

  /// Runs the shipment's next step (see driverShipmentActionsFor).
  final ValueChanged<DriverShipmentStep> onStep;
  final VoidCallback onViewDetails;
  final VoidCallback onCall;
  final VoidCallback onMap;
  final VoidCallback? onUpdateStatus;
  final bool showDetails;

  @override
  Widget build(BuildContext context) {
    final statusId = _statusIdOf(shipment);
    // By id, never by the English status text: "Failed Delivery" and "Out for
    // Delivery" both contain "deliver", so the old substring match painted
    // both of them success green.
    final statusColor = getStatusColor(statusId);
    final isStoreStage = driverShipmentIsPrePickup(shipment);
    // This list held only the off-ramp sheet, so a driver had no way to move
    // an assigned shipment forward from here.
    final nextStep = driverShipmentActionsForShipment(shipment).primary;
    final canOpenStatusSheet = driverStatusSheetCardLauncherIsVisible(shipment);
    // Before confirmed arrival the only card controls are the next pickup
    // step plus the store call/map shortcuts. Keep those three controls in
    // one row instead of making the driver scan two separate rows.
    final compactPickupActions = nextStep != null && !showDetails;
    final isBusy = context.select<ShipmentInstantprovider, bool>(
      (provider) => provider.isShipmentBusy(shipment.id),
    );
    final policyNumber =
        shipment.policyNum.trim().isEmpty
            ? _copy(context, 'No policy number', 'لا يوجد رقم شحنة')
            : shipment.policyNum.trim();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _copy(context, 'Policy number', 'رقم الشحنة'),
                      style: const TextStyle(
                        color: Color(0xff64748B),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      policyNumber,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      // An identifier reads left-to-right in both languages.
                      textDirection: identifierTextDirection(policyNumber),
                      style: const TextStyle(
                        color: Color(0xff0F172A),
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _StatusBadge(label: statusLabel, color: statusColor),
            ],
          ),
          const SizedBox(height: 14),
          _InfoRow(
            icon:
                isStoreStage
                    ? Icons.storefront_outlined
                    : Icons.person_outline_rounded,
            label:
                isStoreStage
                    ? _copy(context, 'Store', 'المتجر')
                    : _copy(context, 'Recipient', 'المستلم'),
            value: _fallback(
              isStoreStage ? shipment.nstore : shipment.recipientName,
              _copy(context, 'Not available', 'غير متوفر'),
            ),
          ),
          _InfoRow(
            icon: Icons.phone_outlined,
            label:
                isStoreStage
                    ? _copy(context, 'Store phone', 'هاتف المتجر')
                    : _copy(context, 'Phone', 'الهاتف'),
            value: _fallback(
              isStoreStage ? shipment.phclient : shipment.recipientPhone,
              _copy(context, 'Not available', 'غير متوفر'),
            ),
          ),
          _InfoRow(
            icon: Icons.place_outlined,
            label:
                isStoreStage
                    ? _copy(context, 'Store address', 'عنوان المتجر')
                    : _copy(context, 'Address', 'العنوان'),
            value: _fallback(
              isStoreStage ? shipment.lclient : shipment.deliveryAddress,
              _copy(context, 'Not available', 'غير متوفر'),
            ),
            maxLines: 2,
          ),
          _InfoRow(
            icon: Icons.route_outlined,
            label: _copy(context, 'Current destination', 'الوجهة الحالية'),
            value:
                isStoreStage
                    ? _copy(context, 'Store pickup', 'استلام من المتجر')
                    : _copy(context, 'Customer delivery', 'توصيل إلى العميل'),
          ),
          const SizedBox(height: 8),
          // Two tiles per row where they fit, one where they do not, rather
          // than a rigid 148 that forces a four-row stack at 360px.
          LayoutBuilder(
            builder: (context, constraints) {
              final tileWidth =
                  constraints.maxWidth >= 316
                      ? (constraints.maxWidth - 10) / 2
                      : constraints.maxWidth;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children:
                    <_MiniMetric>[
                      // The server's product_to_collect: 0 on a prepaid shipment.
                      _MiniMetric(
                        label:
                            shipment.isPrepaid
                                ? _copy(
                                  context,
                                  'COD amount · Prepaid',
                                  'مبلغ التحصيل · مدفوعة مسبقاً',
                                )
                                : _copy(context, 'COD amount', 'مبلغ التحصيل'),
                        value: _money(context, shipment.productToCollect),
                        icon: Icons.receipt_long_outlined,
                      ),
                      _MiniMetric(
                        label: _copy(context, 'Delivery cost', 'تكلفة التوصيل'),
                        value: _money(context, shipment.deliveryCost),
                        icon: Icons.payments_outlined,
                      ),
                      _MiniMetric(
                        label: _copy(context, 'Date', 'التاريخ'),
                        value: _shipmentDate(context, shipment),
                        icon: Icons.calendar_today_outlined,
                      ),
                      _MiniMetric(
                        label: _copy(context, 'Store', 'المتجر'),
                        value: _fallback(
                          shipment.nstore,
                          _copy(context, 'Not available', 'غير متوفر'),
                        ),
                        icon: Icons.storefront_outlined,
                      ),
                    ].map((metric) {
                      return SizedBox(width: tileWidth, child: metric);
                    }).toList(),
              );
            },
          ),
          const SizedBox(height: 14),
          if (nextStep != null) ...[
            if (compactPickupActions)
              Row(
                children: [
                  Expanded(
                    child: _NextStepButton(
                      key: driverStepKey(nextStep),
                      label: driverStepLabel(context, nextStep),
                      icon: driverStepIcon(nextStep),
                      color:
                          nextStep == DriverShipmentStep.deliver
                              ? const Color(0xff16A06D)
                              : AppColors.primary,
                      isLoading: isBusy,
                      onTap: isBusy ? null : () => onStep(nextStep),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _SquareAction(
                    tooltip: _copy(context, 'Call', 'اتصال'),
                    icon: Icons.call_outlined,
                    onTap: onCall,
                  ),
                  const SizedBox(width: 8),
                  _SquareAction(
                    tooltip: _copy(context, 'Map', 'الخريطة'),
                    icon: Icons.map_outlined,
                    onTap: onMap,
                  ),
                ],
              )
            else
              _NextStepButton(
                key: driverStepKey(nextStep),
                label: driverStepLabel(context, nextStep),
                icon: driverStepIcon(nextStep),
                color:
                    nextStep == DriverShipmentStep.deliver
                        ? const Color(0xff16A06D)
                        : AppColors.primary,
                isLoading: isBusy,
                onTap: isBusy ? null : () => onStep(nextStep),
              ),
            const SizedBox(height: 10),
          ],
          if (!compactPickupActions)
            Row(
              children: [
                if (showDetails) ...[
                  Expanded(
                    child: _ActionButton(
                      label: _copy(context, 'Details', 'التفاصيل'),
                      icon: Icons.open_in_new_rounded,
                      onTap: onViewDetails,
                      // The next step, when there is one, is the prominent action.
                      isPrimary: nextStep == null,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                _SquareAction(
                  tooltip: _copy(context, 'Call', 'اتصال'),
                  icon: Icons.call_outlined,
                  onTap: onCall,
                ),
                const SizedBox(width: 8),
                _SquareAction(
                  tooltip: _copy(context, 'Map', 'الخريطة'),
                  icon: Icons.map_outlined,
                  onTap: onMap,
                ),
                if (canOpenStatusSheet && onUpdateStatus != null) ...[
                  const SizedBox(width: 8),
                  _SquareAction(
                    tooltip: _copy(context, 'Update status', 'تحديث الحالة'),
                    icon: Icons.edit_note_rounded,
                    onTap: onUpdateStatus!,
                  ),
                ],
              ],
            ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.maxLines = 1,
  });

  final IconData icon;
  final String label;
  final String value;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: const Color(0xff64748B)),
          const SizedBox(width: 9),
          // A minimum rather than a fixed width: a longer Arabic label, or a
          // larger accessibility text scale, grows the column instead of
          // clipping inside it.
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 76, maxWidth: 110),
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xff64748B),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              maxLines: maxLines,
              overflow: TextOverflow.ellipsis,
              // Phones and identifiers stay left-to-right; a recipient name or
              // an Arabic address keeps the page direction.
              textDirection: identifierTextDirection(value),
              style: const TextStyle(
                color: Color(0xff0F172A),
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniMetric extends StatelessWidget {
  const _MiniMetric({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xffF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xffE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.primary),
          const SizedBox(height: 8),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textDirection: identifierTextDirection(value),
            style: const TextStyle(
              color: Color(0xff0F172A),
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xff64748B),
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// The card's next step, full width so it reads as the thing to do now.
class _NextStepButton extends StatelessWidget {
  const _NextStepButton({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
    required this.isLoading,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final bool isLoading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon:
          isLoading
              ? const SizedBox(
                width: 17,
                height: 17,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
              : Icon(icon, size: 18),
      label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        disabledBackgroundColor: color.withValues(alpha: 0.65),
        disabledForegroundColor: Colors.white,
        elevation: 0,
        minimumSize: const Size.fromHeight(46),
        textStyle: const TextStyle(fontWeight: FontWeight.w800),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.isPrimary = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool isPrimary;

  @override
  Widget build(BuildContext context) {
    // `minimumSize` rather than a fixed SizedBox, so a larger text scale grows
    // the button instead of overflowing it.
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 17),
      label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      style: ElevatedButton.styleFrom(
        backgroundColor: isPrimary ? AppColors.primary : Colors.white,
        foregroundColor: isPrimary ? Colors.white : AppColors.primary,
        elevation: 0,
        minimumSize: const Size.fromHeight(44),
        side: BorderSide(
          color:
              isPrimary
                  ? Colors.transparent
                  : AppColors.primary.withValues(alpha: 0.24),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}

class _SquareAction extends StatelessWidget {
  const _SquareAction({
    required this.tooltip,
    required this.icon,
    required this.onTap,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.14),
            ),
          ),
          child: Icon(icon, color: AppColors.primary, size: 20),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 132),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _AssignedErrorCard extends StatelessWidget {
  const _AssignedErrorCard({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xffFFF7ED),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xffFDBA74)),
      ),
      child: Row(
        children: [
          const Icon(Icons.wifi_off_rounded, color: Color(0xffEA580C)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xff9A3412),
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          TextButton(
            onPressed: onRetry,
            child: Text(_copy(context, 'Retry', 'حاول مرة أخرى')),
          ),
        ],
      ),
    );
  }
}

class _AssignedEmptyState extends StatelessWidget {
  const _AssignedEmptyState({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: _cardDecoration(),
      child: Column(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.09),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(
              Icons.inventory_2_outlined,
              color: AppColors.primary,
              size: 28,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xff0F172A),
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xff64748B),
              fontSize: 12.5,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _AssignedLoadingList extends StatelessWidget {
  const _AssignedLoadingList();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(
        3,
        (index) => Container(
          constraints: const BoxConstraints(minHeight: 176),
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(16),
          decoration: _cardDecoration(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              ),
              const SizedBox(height: 34),
              _LoadingLine(width: 150),
              const SizedBox(height: 10),
              _LoadingLine(width: 230, opacity: 0.08),
              const SizedBox(height: 10),
              _LoadingLine(width: 190, opacity: 0.08),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoadingLine extends StatelessWidget {
  const _LoadingLine({required this.width, this.opacity = 0.12});

  final double width;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: 11,
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: opacity),
        borderRadius: BorderRadius.circular(999),
      ),
    );
  }
}

BoxDecoration _cardDecoration() {
  return BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(18),
    border: Border.all(color: const Color(0xffE2E8F0)),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.04),
        blurRadius: 18,
        offset: const Offset(0, 8),
      ),
    ],
  );
}

String _fallback(String value, String fallback) {
  return value.trim().isEmpty ? fallback : value.trim();
}

/// The locale MaterialApp resolved — the same source Login and the hub read,
/// and the one Directionality and the theme font are built from.
String _copy(BuildContext context, String en, String ar) {
  return Localizations.localeOf(context).languageCode == 'ar' ? ar : en;
}

/// The authoritative status id, preferring the dedicated column and falling
/// back to the legacy one.
int _statusIdOf(Shipment shipment) {
  return shipment.shipmentStatusId != 0
      ? shipment.shipmentStatusId
      : shipment.shipmentStatus;
}

/// Currency first in English, amount first in Arabic — the natural order in
/// each — with the two decimals always shown. The value is untouched.
String _money(BuildContext context, double value) {
  final amount = value.toStringAsFixed(2);
  return _copy(context, 'JOD $amount', '$amount دينار أردني');
}

/// A date the driver can trust, or a localized placeholder.
///
/// Never the raw column: MySQL's zero date and anything unparseable used to be
/// printed verbatim. The format is pinned to `en` so the digits match the
/// money, phone and page numbers elsewhere on the card rather than switching
/// to Arabic-Indic numerals for this one field.
String _shipmentDate(BuildContext context, Shipment shipment) {
  final date = shipment.shipmentDateTime;
  if (date == null) return _copy(context, 'Not available', 'غير متوفر');
  return DateFormat('dd/MM/yyyy', 'en').format(date);
}
