import 'package:blockatie/constants/colors.dart';
import 'package:blockatie/constants/helper.dart';
import 'package:blockatie/models/order_status_modle.dart';
import 'package:blockatie/provider/home.dart';
import 'package:blockatie/utils/address_geocoder.dart';
import 'package:blockatie/utils/driver_shipment_actions.dart';
import 'package:blockatie/utils/size_config.dart';
import 'package:blockatie/utils/spacing.dart';
import 'package:blockatie/services/driver_action_service.dart';
import 'package:blockatie/views/widgets/shipment_map_preview.dart';
import 'package:blockatie/views/widgets/status_update_sheet.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';

class OrderTile extends StatefulWidget {
  const OrderTile({
    super.key,
    this.padding,
    this.showBtnrow = true,
    this.isInstantScren = false,
    this.imagePath,
    this.orderId = "NOB-67",
    this.recipientPhone = "0779735616",
    this.driverName = "Ahmad1",
    this.isPending = true,
    this.isNonAccountant = true,
    this.hasReturn = false,
    this.clientLocation = "Al-Muttalib Ibn Rabeeah",
    this.shipmentCost = "250.00 (JOD)",
    this.deliveryDate = "25/05/2025",
    this.ondetailtap,
    this.accountentCode,
    this.returnCode,
    this.deliveryType,
    this.statusName,
    this.statusNameEn,
    this.statusNameAr,
    this.orderIdInt,
    this.currentStatusId = 0,
    this.doorFeeCollectable = 0,
    required this.username,
    required this.dphno,
    required this.locationStore,
    this.notes,
  });

  final double? padding;
  final bool? showBtnrow;
  final bool? isInstantScren;
  final String? statusName;
  final String? statusNameEn;
  final String? statusNameAr;
  final String? imagePath;
  final String orderId;
  final String recipientPhone;
  final String driverName;

  final bool isPending;
  final bool isNonAccountant;
  final bool hasReturn;
  final int? orderIdInt;

  /// The shipment's status id, for the shared status sheet.
  final int currentStatusId;

  /// Server ceiling for a delivery fee taken at the door on a cancel/return.
  final double doorFeeCollectable;
  final String clientLocation;
  final String shipmentCost;
  final String deliveryDate;
  final VoidCallback? ondetailtap;
  final int? accountentCode;
  final int? returnCode;
  final int? deliveryType;
  final String? username;
  final String? dphno;
  final String? notes;
  final LatLng locationStore;

  @override
  State<OrderTile> createState() => _OrderTileState();
}

class _OrderTileState extends State<OrderTile> with Helper {
  late String? deltype;
  late HomeProvider provider;

  /// Resolved once per tile, not once per build.
  ///
  /// This lived in `build()` as `FutureBuilder(future: getCoordinates...)`,
  /// which started a fresh network geocode on every rebuild of every visible
  /// row. That is what made the app stall more the longer it was used.
  Future<LatLng>? _clientCoordinates;

  @override
  void initState() {
    super.initState();
    provider = Provider.of<HomeProvider>(context, listen: false);
    deltype = provider.getDeliveryTypeNameById(widget.deliveryType ?? 0);
    provider.getOrderStatus();
    _resolveClientCoordinates();
  }

  @override
  void didUpdateWidget(covariant OrderTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Recycled by the list for a different shipment: re-resolve, but only when
    // the address actually changed.
    if (oldWidget.clientLocation != widget.clientLocation) {
      _resolveClientCoordinates();
    }
    if (oldWidget.deliveryType != widget.deliveryType) {
      deltype = provider.getDeliveryTypeNameById(widget.deliveryType ?? 0);
    }
  }

  void _resolveClientCoordinates() {
    // Only the non-pending branch shows the client map; a pending shipment
    // maps the store coordinates it was given and needs no lookup at all.
    if (_isPendingStatus) {
      _clientCoordinates = null;
      return;
    }
    _clientCoordinates = AddressGeocoder.resolve(widget.clientLocation);
  }

  /// The tile used to force-unwrap `statusNameEn`, so a shipment that arrived
  /// without a status name threw while building the row.
  String get _statusColorKey =>
      (widget.statusNameEn ?? '').toLowerCase().trim();

  bool get _isPendingStatus => _statusColorKey == 'pending';

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.only(
        bottom: SizeConfig.heightMultiplier * 1.5,
        left: widget.padding ?? SizeConfig.widthMultiplier * 0,
        right: widget.padding ?? SizeConfig.widthMultiplier * 0,
      ),
      child: Container(
        padding: EdgeInsets.symmetric(
          vertical: SizeConfig.heightMultiplier * 1.5,
          horizontal: SizeConfig.widthMultiplier * 3,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200, width: 1),
        ),
        child: Column(
          children: [
            _isPendingStatus
                // A pending shipment already carries the store coordinates, so
                // it needs no address lookup at all.
                ? ShipmentMapPreview(
                  markerId: 'markerStore',
                  target:
                      widget.locationStore.latitude == 0
                          ? null
                          : widget.locationStore,
                )
                : FutureBuilder<LatLng>(
                  future: _clientCoordinates,
                  // Paint immediately when this address was resolved earlier
                  // in the session instead of flashing a spinner again.
                  initialData: AddressGeocoder.cached(widget.clientLocation),
                  builder: (context, snapshot) {
                    final coordinates = snapshot.data;
                    if (coordinates == null) {
                      // The lookup never fails — it falls back to Amman — so
                      // this is only the brief first resolve.
                      return const SizedBox(
                        height: 120,
                        child: Center(
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.2),
                          ),
                        ),
                      );
                    }
                    return ShipmentMapPreview(
                      markerId: 'markerClient',
                      target: coordinates.latitude == 0 ? null : coordinates,
                    );
                  },
                ),

            Spacing.y(1),
            Row(
              children: [
                Container(
                  height: SizeConfig.heightMultiplier * 7,
                  width: SizeConfig.widthMultiplier * 13,
                  decoration: BoxDecoration(
                    image: DecorationImage(
                      image:
                          (widget.imagePath != null &&
                                  widget.imagePath!.isNotEmpty)
                              ? NetworkImage(
                                'https://dashboard.blockatie.com${widget.imagePath}',
                              )
                              : const AssetImage(
                                    'assets/images/default_user.png',
                                  )
                                  as ImageProvider,
                      fit: BoxFit.cover,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  // decoration: BoxDecoration(
                  //   image: DecorationImage(
                  //     image: AssetImage(widget.imagePath),
                  //     fit: BoxFit.cover,
                  //   ),
                  //   borderRadius: BorderRadius.circular(12),
                  // ),
                ),
                Spacing.x(2),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.orderId,
                      style: textTheme.bodyMedium!.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      "${tr("recipientNumber")}: ${widget.recipientPhone}",

                      style: textTheme.bodySmall!.copyWith(
                        fontSize: SizeConfig.textMultiplier * 1,
                      ),
                    ),
                    Text(
                      "${tr("driverNameLabel")}: ${widget.driverName}",
                      style: textTheme.bodySmall!.copyWith(
                        fontSize: SizeConfig.textMultiplier * 1,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Row(
                      children: [
                        if (widget.statusName != null)
                          statusTag(
                            // The locale MaterialApp resolved, which is also
                            // what Directionality and the font come from.
                            // `context.locale` can disagree for a frame after
                            // a language switch.
                            text:
                                Localizations.localeOf(context).languageCode ==
                                        'ar'
                                    ? widget.statusNameAr ?? ''
                                    : widget.statusName ?? '',
                            icon: 'assets/images/pending.png',
                            // Guarded on statusName, but coloured from
                            // statusNameEn: a row carrying one without the
                            // other threw while building.
                            imageColor: _getStatusColor(_statusColorKey),
                            color: _getStatusColor(_statusColorKey),
                            bgColor: _getStatusBgColor(_statusColorKey),
                          ),
                        Spacing.x(2),
                        statusTag(
                          text: deltype ?? 'unknown',
                          //  tr('pending'),
                          icon: 'assets/images/pending.png',
                          color: Colors.red,
                          bgColor: Colors.red.shade50,
                        ),
                      ],
                    ),
                    Spacing.y(1),
                    Row(
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: statusTag(
                            text:
                                widget.accountentCode == 0
                                    ? getLocalizedTypeName(
                                      'Non-accounting',
                                      'غير محسوب',
                                    )
                                    : widget.accountentCode == 1
                                    ? getLocalizedTypeName(
                                      'Driver-accounting',
                                      'محاسبة السائق',
                                    )
                                    : getLocalizedTypeName(
                                      'Client-accounting',
                                      'محاسبة العملاء',
                                    ),
                            // tr('non_accountant'),
                            icon: 'assets/images/non-return.png',
                            color: Colors.blue.shade700,
                            bgColor: Colors.blue.shade50,
                          ),
                        ),
                      ],
                    ),
                    Spacing.y(1),
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: statusTag(
                        text:
                            widget.returnCode == 0
                                ? getLocalizedTypeName(
                                  'There is no return',
                                  'ليس هناك عودة',
                                )
                                : widget.returnCode == 2
                                ? getLocalizedTypeName(
                                  'There is return',
                                  'هناك عودة',
                                )
                                : tr('returned'),

                        // tr('has_return'),
                        icon:
                            widget.returnCode == 0
                                ? 'assets/images/non-return.png'
                                : widget.returnCode == 2
                                ? 'assets/images/return.png'
                                : 'assets/images/return.png',
                        color:
                            widget.returnCode == 0
                                ? Colors.red
                                : widget.returnCode == 2
                                ? Colors.green
                                : Colors.grey,
                        bgColor:
                            widget.returnCode == 0
                                ? Colors.red.withValues(alpha: 0.2)
                                : widget.returnCode == 2
                                ? Colors.green.withValues(alpha: 0.2)
                                : Colors.grey.withValues(alpha: 0.2),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            Spacing.y(2.5),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,

              children: [
                _rowInfo(
                  textTheme,
                  tr("customer_name"),
                  widget.username ?? '-',
                  'assets/images/profile.png',
                ),
                SizedBox(width: 15),
                Padding(
                  padding: EdgeInsetsDirectional.only(end: 15),
                  child: _rowInfo(
                    textTheme,
                    tr("phone_number"),
                    widget.dphno ?? "-",
                    'assets/images/phone.png',
                  ),
                ),
                _rowInfo(
                  textTheme,
                  tr('location_client'),
                  widget.clientLocation,
                  "assets/icons/location.png",
                ),
              ],
            ),
            Spacing.y(2.5),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _rowInfo(
                  textTheme,
                  tr('shipment_cost'),
                  widget.shipmentCost,
                  "assets/icons/shipment_cost.png",
                ),
                _rowInfo(
                  textTheme,
                  tr('delivered_at'),
                  widget.deliveryDate,
                  "assets/icons/delivered_at.png",
                ),
              ],
            ),
            Spacing.y(2.5),
            if (!widget.showBtnrow!)
              SizedBox(
                width: SizeConfig.widthMultiplier * 85,
                child: ElevatedButton.icon(
                  onPressed: () {},
                  label: Text(tr('accept_order')),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.check),
                ),
              ),
            if (widget.showBtnrow!)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: widget.ondetailtap,
                      child: Container(
                        height: SizeConfig.heightMultiplier * 5,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.primary),
                        ),
                        child: Center(
                          child: Text(
                            tr('order_detail'),
                            style: textTheme.bodyMedium!.copyWith(
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: InkWell(
                      onTap: () {
                        if (widget.orderIdInt != null) {
                          _orderStatus(orderId: widget.orderIdInt!);
                        }
                      },
                      child: Container(
                        height: SizeConfig.heightMultiplier * 5,

                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(
                          child: Text(
                            tr('update_order_status'),
                            style: textTheme.bodyMedium!.copyWith(
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget statusTag({
    required String text,
    required String icon,
    required Color color,
    required Color bgColor,
    Color? imageColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Image.asset(icon, width: 10, height: 10, color: imageColor),
          Spacing.x(1),
          Text(
            text,
            style: TextStyle(
              fontSize: 8,
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Row _rowInfo(
    TextTheme textTheme,
    String title,
    String subtitle,
    String icon,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Image.asset(icon, height: 10, color: Colors.black87),
        Spacing.x(1),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: textTheme.bodySmall!.copyWith(
                fontSize: SizeConfig.textMultiplier * 1.1,
                fontWeight: FontWeight.w600,
              ),
            ),
            Spacing.y(.3),
            Text(
              subtitle,
              style: textTheme.bodySmall!.copyWith(
                fontSize: SizeConfig.textMultiplier * 1,
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Cancelled / Returned / Failed Delivery through the shared sheet, as on
  /// every other screen. This tile used to list every status but Pending and
  /// send the choice without a reason, which update_shipment_status.php
  /// refuses for every one of them; the forward steps live on the details
  /// screen.
  Future<void> _orderStatus({required int orderId}) async {
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    String text(String en, String ar) => isArabic ? ar : en;
    final home = provider;

    // This legacy/filter card does not carry a driver action contract itself.
    // Resolve one before it can launch the common sheet, rather than trusting
    // its cached status label or id.  The sheet repeats this fetch and filter
    // before rendering, which also covers a state change during this await.
    final shipment = await DriverActionService.read(context).fetch(orderId);
    if (!mounted ||
        shipment == null ||
        driverStatusSheetModeForShipment(shipment) ==
            DriverStatusSheetMode.unavailable) {
      return;
    }
    if (home.orderStatusData == null && !home.isStatusLoading) {
      await home.getOrderStatus();
    }
    if (!mounted) return;

    final current = driverStatusIdOf(shipment);
    final statuses =
        home.orderStatusData?.status.where((status) {
          final id = int.tryParse(status.id);
          return id != null &&
              driverSelectableStatusIds.contains(id) &&
              id != current;
        }).toList() ??
        <Status>[];

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder:
          (_) => ShipmentStatusUpdateSheet(
            shipmentId: orderId,
            statuses: statuses,
            currentStatusId: current,
            currentStatusLabel: getStatusLabel(
              context,
              current,
              statusNameEn: widget.statusNameEn,
              statusNameAr: widget.statusNameAr,
            ),
            policyNumber:
                shipment.policyNum.isEmpty
                    ? widget.orderId
                    : shipment.policyNum,
            doorFeeCollectable:
                shipment.financial?.doorFeeCollectable ??
                widget.doorFeeCollectable,
            onSubmit: (status, reason) async {
              final success = await home.updateStatus(
                shipmentId: orderId,
                statusId: status.id,
                reasonId: reason?.reasonId,
                reasonNote: reason?.note,
                feeCollectedAmount: reason?.feeCollectedAmount,
                showSuccessDialog: false,
              );
              if (success && mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      text('Shipment status updated.', 'تم تحديث حالة الشحنة.'),
                    ),
                  ),
                );
              }
              return success;
            },
          ),
    );
  }

  Color _getStatusBgColor(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return Colors.blue.withAlpha(30);
      case 'processing':
        return Colors.orange.withAlpha(30);
      case 'in transit':
        return Colors.purple.withAlpha(30);
      case 'completed':
        return Colors.green.withAlpha(30);
      case 'delivered':
        return Colors.green.withAlpha(30);
      case 'dispatched':
        return Colors.indigo.withAlpha(30);
      case 'out for delivery':
        return Colors.teal.withAlpha(30);
      case 'awaiting pickup':
        return Colors.amber.withAlpha(30);
      case 'cancelled':
      case 'returned':
      case 'failed delivery':
        return Colors.red.withAlpha(30);
      default:
        return Colors.grey.withAlpha(30);
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return Colors.blue;
      case 'processing':
        return Colors.orange;
      case 'in transit':
        return Colors.purple;
      case 'completed':
        return Colors.green;
      case 'delivered':
        return Colors.green;
      case 'dispatched':
        return Colors.indigo;
      case 'out for delivery':
        return Colors.teal;
      case 'awaiting pickup':
        return Colors.amber;
      case 'cancelled':
      case 'returned':
      case 'failed delivery':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }
}
