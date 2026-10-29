// ignore_for_file: deprecated_member_use

import 'package:blockatie/constants/colors.dart';
import 'package:blockatie/constants/helper.dart';
import 'package:blockatie/constants/logic.dart';
import 'package:blockatie/provider/home.dart';
import 'package:blockatie/utils/address_geocoder.dart';
import 'package:blockatie/utils/nav.dart';
import 'package:blockatie/utils/size_config.dart';
import 'package:blockatie/utils/spacing.dart';
import 'package:blockatie/views/pages/orders/order_details.dart';
import 'package:blockatie/views/widgets/shipment_map_preview.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../../../provider/order_location.dart';
import '../../../../order-location/order_location.dart';

class OrderInstantTile extends StatefulWidget {
  const OrderInstantTile({
    super.key,
    this.profileImg,
    this.showLocationRow = true,
    this.padding,
    this.showBtnrow = true,
    this.isInstantScren = false,
    this.isDevlivered = false,
    this.orderCreationDate,
    this.ontap,
    this.btnLabel,
    this.customername,
    this.location,
    this.orderStatus,
    this.dphno,
    this.deliveryCost,
    this.shipmentCost,
    this.orderid,
    this.dname,
    this.username,
    this.clientLocation,
    this.cphno,
    this.showDelBtn = false,
    this.shipmentType,
    this.orderStatusid,
    this.id,
    this.storeAdd,
    this.clientAddress,
    this.statusName,

    this.accountentCode,
    this.deliveryType,
    this.returnCode,
    this.shipmentStatus,
    this.isComplte = true,
    this.withinRadius = false,
    required this.statusId,
    required this.locationStore,
    this.shipmentNote,
  });

  final String? statusName;
  final int statusId;
  final bool withinRadius;
  final double? padding;
  final bool? showBtnrow;
  final bool? isInstantScren;
  final String? profileImg;
  final String? username;
  final String? orderid;
  final String? customername;
  final String? dphno;
  final String? location;
  final String? orderStatus;
  final String? orderCreationDate;
  final String? btnLabel;
  final String? shipmentCost;
  final String? deliveryCost;
  final bool isDevlivered;
  final String? dname;
  final bool showLocationRow;
  final VoidCallback? ontap;
  final String? clientLocation;
  final String? cphno;
  final String? shipmentType;
  final bool? showDelBtn;
  final int? orderStatusid;
  final int? id;
  final String? storeAdd;
  final String? clientAddress;
  final int? accountentCode;
  final int? returnCode;
  final int? deliveryType;
  final String? shipmentStatus;
  final bool? isComplte;
  final LatLng locationStore;
  final String? shipmentNote;

  @override
  State<OrderInstantTile> createState() => _OrderInstantTileState();
}

class _OrderInstantTileState extends State<OrderInstantTile> with Helper {
  late String? deltype;
  late HomeProvider provider;

  /// Resolved once per tile. It used to be built inside `build()`, so every
  /// rebuild started a fresh network geocode for every visible row.
  Future<LatLng>? _clientCoordinates;

  @override
  void initState() {
    super.initState();
    provider = Provider.of<HomeProvider>(context, listen: false);
    deltype = provider.getDeliveryTypeNameById(widget.deliveryType ?? 0);
    provider.getOrderStatus();
    _clientCoordinates = AddressGeocoder.resolve(widget.clientLocation ?? '');
  }

  @override
  void didUpdateWidget(covariant OrderInstantTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The list recycles tiles, so re-resolve only when the address changed.
    if (oldWidget.clientLocation != widget.clientLocation) {
      _clientCoordinates = AddressGeocoder.resolve(widget.clientLocation ?? '');
    }
    if (oldWidget.deliveryType != widget.deliveryType) {
      deltype = provider.getDeliveryTypeNameById(widget.deliveryType ?? 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: EdgeInsets.only(
        bottom: SizeConfig.heightMultiplier * 1.5,
        left: widget.padding ?? SizeConfig.widthMultiplier * 5,
        right: widget.padding ?? SizeConfig.widthMultiplier * 5,
      ),
      child: Container(
        padding: EdgeInsets.symmetric(
          vertical: SizeConfig.heightMultiplier * 1.5,
          horizontal: SizeConfig.widthMultiplier * 3,
        ),
        decoration: BoxDecoration(
          color: widget.isDevlivered ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.withValues(alpha: 0.4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!widget.isComplte! && widget.statusId == 4)
              FutureBuilder<LatLng>(
                future: _clientCoordinates,
                // Already resolved earlier in the session: paint on the first
                // frame instead of flashing a spinner again.
                initialData: AddressGeocoder.cached(
                  widget.clientLocation ?? '',
                ),
                builder: (context, snapshot) {
                  final coordinates = snapshot.data;
                  if (coordinates == null) {
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
                    // The pin was keyed off the store's coordinates while being
                    // positioned at the client's, so a shipment without store
                    // coordinates silently lost its marker.
                    target: coordinates.latitude == 0 ? null : coordinates,
                  );
                },
              ),
            Spacing.y(1),
            Row(
              children: [
                Container(
                  height: SizeConfig.heightMultiplier * 7,
                  width: SizeConfig.widthMultiplier * 16,
                  decoration: BoxDecoration(
                    image: DecorationImage(
                      image:
                          (widget.profileImg != null &&
                                  (widget.profileImg?.isNotEmpty ?? false))
                              ? NetworkImage(
                                'https://dashboard.blockatie.com${widget.profileImg}',
                              )
                              : const AssetImage(
                                    'assets/images/default_user.png',
                                  )
                                  as ImageProvider,
                      fit: BoxFit.cover,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                Spacing.x(2),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.dname != null)
                      Text(
                        widget.dname ?? 'no name',
                        style: textTheme.bodyMedium!.copyWith(
                          fontWeight: FontWeight.w600,
                          color:
                              widget.isDevlivered ? Colors.white : Colors.black,
                        ),
                      ),
                    Text(
                      widget.orderid ?? "",
                      style: textTheme.bodyMedium!.copyWith(
                        fontWeight: FontWeight.w600,
                        color:
                            widget.isDevlivered ? Colors.white : Colors.black,
                      ),
                    ),
                    if (widget.orderCreationDate != null)
                      Text(
                        tr("order_creation_date"),
                        style: textTheme.bodySmall!.copyWith(
                          fontSize: SizeConfig.textMultiplier * 1,
                          fontWeight: FontWeight.bold,
                          color:
                              widget.isDevlivered ? Colors.white : Colors.black,
                        ),
                      ),
                    Text(
                      Logic.getCreatedFrom(
                        widget.orderCreationDate!,
                        lang: context.locale.languageCode,
                      ),
                      style: textTheme.bodySmall!.copyWith(
                        fontSize: SizeConfig.textMultiplier * 1,
                        color:
                            widget.isDevlivered ? Colors.white : Colors.black,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                if (!widget.isDevlivered)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Row(
                        children: [
                          if (widget.statusName != null &&
                              widget.statusName!.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: statusTag(
                                text: widget.statusName ?? '',
                                // tr('non_accountant'),
                                icon: 'assets/images/pending.png',
                                color: _getStatusColor(widget.statusId),
                                bgColor: _getStatusBgColor(widget.statusId),
                              ),
                            ),
                          Spacing.x(2),
                          statusTag(
                            text: widget.shipmentType ?? 'unknown',
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
                                      ? tr('non-accounting')
                                      : widget.accountentCode == 1
                                      ? tr('driver-accounting')
                                      : tr('client-accounting'),
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
                                  ? tr('there_no_return')
                                  : widget.returnCode == 2
                                  ? tr('has_return')
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
                          iconcolor:
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
                if (widget.isDevlivered)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Row(
                        children: [
                          if (widget.statusName != null &&
                              widget.statusName!.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: statusTag(
                                text: widget.statusName ?? '',
                                // tr('non_accountant'),
                                icon: 'assets/images/pending.png',
                                color: Colors.white,
                                bgColor: Colors.grey.withValues(alpha: 0.5),
                              ),
                            ),
                          Spacing.x(2),
                          statusTag(
                            text: widget.shipmentType ?? 'unknown',
                            //  tr('pending'),
                            icon: 'assets/images/pending.png',
                            color: Colors.white,
                            bgColor: Colors.grey.withValues(alpha: 0.5),
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
                                      ? tr('non-accounting')
                                      : widget.accountentCode == 1
                                      ? tr('driver-accounting')
                                      : tr('client-accounting'),
                              // tr('non_accountant'),
                              icon: 'assets/images/non-return.png',
                              color: Colors.white,
                              bgColor: Colors.grey.withValues(alpha: 0.5),
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
                                  ? tr('there_no_return')
                                  : widget.returnCode == 2
                                  ? tr('has_return')
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
                          iconcolor:
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

            if (widget.isInstantScren! ||
                widget.statusId == 11 ||
                widget.statusId == 7 ||
                widget.statusId == 8 ||
                widget.statusId == 9 ||
                widget.statusId == 6)
              Container(
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _rowInfo(
                          textTheme,
                          tr("customer_name"),
                          widget.username ?? '-',
                          'assets/images/profile.png',
                        ),

                        _rowInfo(
                          textTheme,
                          tr("phone_number"),
                          widget.dphno ?? "-",
                          'assets/images/phone.png',
                        ),
                        _rowInfo(
                          textTheme,
                          tr("shipment_cost"),
                          '${widget.shipmentCost} (JOD)',
                          'assets/icons/shipment_cost.png',
                        ),
                      ],
                    ),
                    SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _rowInfo(
                          textTheme,
                          tr("delivery_cost"),
                          '${widget.deliveryCost} (JOD)',
                          'assets/icons/delivered_at.png',
                        ),

                        _rowInfo(
                          textTheme,
                          tr("location"),
                          widget.location ?? '_',
                          'assets/icons/shipment_cost.png',
                        ),
                        _rowInfo(
                          textTheme,
                          tr("notes"),
                          widget.shipmentNote ?? '_',
                          'assets/images/user.png',
                        ),
                      ],
                    ),
                  ],
                ),
              ),

            Spacing.y(2),
            if (widget.showBtnrow!)
              !widget.withinRadius &&
                      (widget.statusId != 4 &&
                          widget.statusId != 3 &&
                          widget.statusId != 5 &&
                          widget.statusId != 10)
                  ? Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // InkWell(
                      //   onTap: widget.ontap,
                      //   child: Container(
                      //     height: SizeConfig.heightMultiplier * 5,
                      //     width: SizeConfig.widthMultiplier * 40,
                      //     decoration: BoxDecoration(
                      //       color: AppColors.primary,
                      //       borderRadius: BorderRadius.circular(12),
                      //     ),
                      //     child: Center(
                      //       child: Text(
                      //         tr('receivingOrder'),
                      //
                      //         // tr('order_delivery'),
                      //         style: textTheme.bodyMedium!.copyWith(
                      //           color: Colors.white,
                      //         ),
                      //       ),
                      //     ),
                      //   ),
                      // ),
                      InkWell(
                        onTap: widget.ontap,
                        child: Container(
                          height: SizeConfig.heightMultiplier * 5,
                          width: SizeConfig.widthMultiplier * 40,
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Center(
                            child: Text(
                              tr('the_store_has_been_reached'),

                              // tr('order_delivery'),
                              style: textTheme.bodyMedium!.copyWith(
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                      InkWell(
                        onTap: () async {
                          // Nav.to(
                          //   OrderDetailPage(
                          //     phoneCustomer: widget.dphno ?? '',
                          //     shipmentId: widget.id ?? 0,
                          //     storeAdd: widget.storeAdd,
                          //     deliveryAdd: widget.clientAddress,
                          //   ),
                          //   withNav: true,
                          //   navIndex: 1,
                          // );
                          final providerLocation =
                              Provider.of<OrderLocationProvider>(
                                context,
                                listen: false,
                              );
                          providerLocation.starTrackStore(
                            storeLocation: LatLng(
                              widget.locationStore.latitude,
                              widget.locationStore.longitude,
                            ),
                          );
                          Nav.to(
                            LocationOrderPage(
                              shipmentId: widget.id ?? 0,
                              phoneCustomer: widget.cphno ?? '',
                              storeLocation: widget.locationStore,
                              storeName: widget.username,
                              storePhone: widget.cphno,
                              storeAddress: widget.storeAdd,
                            ),
                          );
                        },
                        child: Container(
                          height: SizeConfig.heightMultiplier * 5,
                          width: SizeConfig.widthMultiplier * 40,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.primary),
                          ),
                          child: Center(
                            child: Text(
                              tr('trackStoreAddress'),
                              style: textTheme.bodyMedium!.copyWith(
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  )
                  : widget.withinRadius &&
                      (widget.statusId != 4 ||
                          widget.statusId != 3 ||
                          widget.statusId != 5 ||
                          widget.statusId != 10)
                  ? Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // InkWell(
                      //   onTap: widget.ontap,
                      //   child: Container(
                      //     height: SizeConfig.heightMultiplier * 5,
                      //     width: SizeConfig.widthMultiplier * 40,
                      //     decoration: BoxDecoration(
                      //       color: AppColors.primary,
                      //       borderRadius: BorderRadius.circular(12),
                      //     ),
                      //     child: Center(
                      //       child: Text(
                      //         tr('receivingOrder'),
                      //
                      //         // tr('order_delivery'),
                      //         style: textTheme.bodyMedium!.copyWith(
                      //           color: Colors.white,
                      //         ),
                      //       ),
                      //     ),
                      //   ),
                      // ),
                      InkWell(
                        onTap: widget.ontap,
                        child: Container(
                          height: SizeConfig.heightMultiplier * 5,
                          width: SizeConfig.widthMultiplier * 40,
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Center(
                            child: Text(
                              tr('receive_order'),

                              // tr('order_delivery'),
                              style: textTheme.bodyMedium!.copyWith(
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                      InkWell(
                        onTap: () async {
                          await launchUrl(
                            Uri.parse("tel:${widget.cphno}"),
                            mode: LaunchMode.externalApplication,
                          );
                          // Nav.to(
                          //   OrderDetailPage(
                          //     phoneCustomer: widget.dphno ?? '',
                          //     shipmentId: widget.id ?? 0,
                          //     storeAdd: widget.storeAdd,
                          //     deliveryAdd: widget.clientAddress,
                          //   ),
                          //   withNav: true,
                          //   navIndex: 1,
                          // );
                        },
                        child: Container(
                          height: SizeConfig.heightMultiplier * 5,
                          width: SizeConfig.widthMultiplier * 40,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.primary),
                          ),
                          child: Center(
                            child: Text(
                              tr('callStore'),
                              style: textTheme.bodyMedium!.copyWith(
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  )
                  : (widget.statusId == 4 ||
                      widget.statusId == 3 ||
                      widget.statusId == 5 ||
                      widget.statusId == 10)
                  ? Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      InkWell(
                        onTap: () => _orderStatus(orderId: widget.id ?? 0),
                        child: Container(
                          height: SizeConfig.heightMultiplier * 5,
                          width: SizeConfig.widthMultiplier * 40,
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Center(
                            child: Text(
                              tr('change_of_state_of_order'),
                              // tr('order_delivery'),
                              style: textTheme.bodyMedium!.copyWith(
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                      InkWell(
                        onTap: () {
                          Nav.to(
                            OrderDetailPage(
                              phoneCustomer: widget.dphno ?? '',
                              shipmentId: widget.id ?? 0,
                              storeAdd: widget.storeAdd,
                              deliveryAdd: widget.clientAddress,
                            ),
                            withNav: true,
                            navIndex: 1,
                          );
                        },
                        child: Container(
                          height: SizeConfig.heightMultiplier * 5,
                          width: SizeConfig.widthMultiplier * 40,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.primary),
                          ),
                          child: Center(
                            child: Text(
                              tr('orderDetailButton'),
                              style: textTheme.bodyMedium!.copyWith(
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  )
                  : SizedBox(),

            // if (widget.orderStatusid != 11 && !widget.showBtnrow!)
            //   InkWell(
            //     onTap: widget.ontap,
            //     child: Container(
            //       width: double.infinity,
            //       padding: const EdgeInsets.symmetric(vertical: 12),
            //       decoration: BoxDecoration(
            //         color:
            //             widget.isDevlivered
            //                 ? AppColors.green
            //                 : AppColors.primary,
            //         borderRadius: BorderRadius.circular(10),
            //       ),
            //       child: Row(
            //         mainAxisAlignment: MainAxisAlignment.center,
            //         children: [
            //           Text(
            //             widget.btnLabel ?? tr("accept_first"),
            //             style: textTheme.bodyMedium!.copyWith(
            //               color: Colors.white,
            //               fontWeight: FontWeight.w500,
            //             ),
            //           ),
            //           Spacing.x(2),
            //           if (!widget.isInstantScren!)
            //             Image.asset(
            //               'assets/images/stars.png',
            //               height: 20,
            //               width: 20,
            //             ),
            //         ],
            //       ),
            //     ),
            //   ),
          ],
        ),
      ),
    );
  }

  _orderStatus({required int orderId}) {
    int? indexNumber;
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder:
              (context, setState) => Consumer<HomeProvider>(
                builder: (context, value, child) {
                  // فلترة العناصر قبل GridView
                  final filteredList =
                      value.orderStatusData!.status
                          .where((item) => item.id != '1')
                          .toList();
                  return Dialog(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadiusDirectional.circular(10),
                    ),
                    child: SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsetsDirectional.symmetric(
                          vertical: 10,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.start,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                IconButton(
                                  onPressed: () => Navigator.pop(context),
                                  icon: const Icon(Icons.close),
                                ),
                                Text(''),
                              ],
                            ),
                            GridView.builder(
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 3,
                                    childAspectRatio: 1.5,
                                  ),
                              itemCount: filteredList.length,
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemBuilder: (context, index) {
                                final statusItem =
                                    filteredList[index]; // العنصر الجديد بعد الفلترة

                                return Padding(
                                  padding:
                                      const EdgeInsetsDirectional.symmetric(
                                        vertical: 5,
                                        horizontal: 10,
                                      ),
                                  child: GestureDetector(
                                    onTap: () {
                                      // setState(() {
                                      //   indexNumber = index;
                                      // });
                                      value.updateStatus(
                                        isInstant: true,
                                        shipmentId: widget.id ?? 0,
                                        statusId: statusItem.id,
                                      );
                                      Navigator.pop(context);
                                    },
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color:
                                            indexNumber == index
                                                ? AppColors.primary.withValues(
                                                  alpha: 0.20,
                                                )
                                                : Colors.black12,
                                        borderRadius:
                                            BorderRadiusDirectional.circular(8),
                                      ),
                                      child: Center(
                                        child: Text(
                                          textAlign: TextAlign.center,
                                          getLocalizedTypeName(
                                            statusItem.statusNameEn,
                                            statusItem.statusNameAr,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
        );
      },
    );
  }

  Widget _pill({
    required String icon,
    required String label,
    Color? color,
    Color? background,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Image.asset(icon, width: 10, height: 10, color: color),
          Spacing.x(1),
          Text(
            label,
            style: TextStyle(
              fontSize: 8,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _rowInfo(
    TextTheme textTheme,
    String title,
    String value,
    String icon,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        Image.asset(
          icon,
          height: 10,
          color: widget.isDevlivered ? Colors.white : Colors.grey,
        ),
        SizedBox(width: 2),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: textTheme.bodySmall!.copyWith(
                fontWeight: FontWeight.w600,
                fontSize: 10,
                color: widget.isDevlivered ? Colors.white : Colors.black,
              ),
            ),
            Spacing.y(.3),
            SizedBox(
              width: SizeConfig.widthMultiplier * 20,
              child: Text(
                value,
                style: textTheme.bodySmall!.copyWith(
                  fontSize: 10,
                  color: widget.isDevlivered ? Colors.white : Colors.black,
                ),
              ),
            ),
          ],
        ),
        //Spacing.x(1)
      ],
    );
  }

  Widget _actionButton(
    TextTheme textTheme,
    String text,
    Color textColor, {
    bool outlined = false,
  }) {
    return Container(
      height: SizeConfig.heightMultiplier * 5,
      width: SizeConfig.widthMultiplier * 40,
      decoration: BoxDecoration(
        color: outlined ? Colors.transparent : AppColors.primary,
        border: outlined ? Border.all(color: AppColors.primary) : null,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: Text(
          text,
          style: textTheme.bodyMedium!.copyWith(color: textColor),
        ),
      ),
    );
  }
}

class UserInfoRow extends StatelessWidget {
  const UserInfoRow({
    super.key,
    required this.textTheme,
    this.title,
    this.desc,
    this.icon,
  });

  final TextTheme textTheme;
  final String? title;
  final String? desc;
  final String? icon;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Image.asset(
              icon ?? 'assets/images/user.png',
              width: 15,
              height: 15,
            ),
            Spacing.x(3),
            Expanded(
              child: Text(
                desc ?? '',
                style: textTheme.bodySmall!.copyWith(color: Colors.white),
              ),
            ),
          ],
        ),
        Spacing.y(0.5),
        const Divider(color: Colors.grey, thickness: 0.5),
      ],
    );
  }
}

Widget statusTag({
  required String text,
  required String icon,
  required Color color,
  required Color bgColor,
  Color? iconcolor,
}) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: bgColor,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Row(
      children: [
        Image.asset(icon, width: 10, height: 10, color: iconcolor),
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

Color _getStatusBgColor(int statusId) {
  switch (statusId) {
    case 1:
      return Colors.blue.withAlpha(30);
    case 2:
      return Colors.orange.withAlpha(30);
    case 4:
      return Colors.purple.withAlpha(30);
    case 11:
      return Colors.green.withAlpha(30);
    case 6:
      return Colors.green.withAlpha(30);
    case 3:
      return Colors.indigo.withAlpha(30);
    case 5:
      return Colors.teal.withAlpha(30);
    case 10:
      return Colors.amber.withAlpha(30);
    case 7:
    case 8:
    case 9:
      return Colors.red.withAlpha(30);
    default:
      return Colors.grey.withAlpha(30);
  }
}

Color _getStatusColor(int statusId) {
  switch (statusId) {
    case 1:
      return Colors.blue;
    case 2:
      return Colors.orange;
    case 4:
      return Colors.purple;
    case 11:
      return Colors.green;
    case 6:
      return Colors.green;
    case 3:
      return Colors.indigo;
    case 5:
      return Colors.teal;
    case 10:
      return Colors.amber;
    case 7:
    case 8:
    case 9:
      return Colors.red;
    default:
      return Colors.grey;
  }
}
