import 'package:blockatie/constants/colors.dart';
import 'package:blockatie/provider/home.dart';
import 'package:blockatie/utils/size_config.dart';
import 'package:blockatie/utils/spacing.dart';
import 'package:blockatie/utils/time/jordan_time.dart';
import 'package:blockatie/views/widgets/shipment_map_preview.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';

import '../../../../../../utils/localization.dart';

class AcceptOrderTile extends StatefulWidget {
  const AcceptOrderTile({
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
    this.accountentCode,
    this.deliveryType,
    this.returnCode,
    this.onAccepttap,
    this.statusName,
    required this.statusId,
    required this.locationStore,
  });

  final String? statusName;
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
  final int? accountentCode;
  final int? returnCode;
  final int statusId;
  final int? deliveryType;
  final VoidCallback? onAccepttap;
  final LatLng locationStore;

  @override
  State<AcceptOrderTile> createState() => _AcceptOrderTileState();
}

class _AcceptOrderTileState extends State<AcceptOrderTile> {
  late String? deltype;
  late HomeProvider provider;

  @override
  void initState() {
    // TODO: implement initState
    super.initState();
    provider = Provider.of<HomeProvider>(context, listen: false);
    deltype = provider.getDeliveryTypeNameById(widget.deliveryType ?? 0);
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
            SizedBox(
              height: 120,
              width: double.infinity,
              child: Stack(
                children: [
                  // One lite-mode preview instead of two full interactive maps
                  // built per row. Available shipments is the longest list in
                  // the app, so this is where the map engines piled up fastest.
                  ShipmentMapPreview(
                    markerId: 'selected',
                    target:
                        widget.locationStore.latitude == 0.0
                            ? null
                            : widget.locationStore,
                  ),
                  Positioned(
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: Colors.grey.withValues(alpha: 0.2),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 30.0,
                    left: 100.0,
                    child: Center(child: AnimatedSearchIcon()),
                  ),
                ],
              ),
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
                      extractDate(
                        widget.orderCreationDate ?? '2025-08-18 12:30:00',
                      ),
                      style: textTheme.bodySmall!.copyWith(
                        fontSize: SizeConfig.textMultiplier * 1,
                        color:
                            widget.isDevlivered ? Colors.white : Colors.black,
                      ),
                    ),
                    Text(
                      extractTime(
                        widget.orderCreationDate ?? "2025-08-18 12:30:00",
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
                        Spacing.x(2),
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
                // InkWell(
                //   // onTap: widget.ondetailtap,
                //   child: Container(
                //     height: SizeConfig.heightMultiplier * 5,
                //     width: SizeConfig.widthMultiplier * 40,
                //     decoration: BoxDecoration(
                //       borderRadius: BorderRadius.circular(12),
                //       border: Border.all(color: AppColors.primary),
                //     ),
                //     child: Center(
                //       child: Text(
                //         tr('hero_not_specified'),
                //         style: textTheme.bodyMedium!.copyWith(
                //           color: AppColors.primary,
                //         ),
                //       ),
                //     ),
                //   ),
                // ),
                //  AnimatedSearchIcon(),
                Expanded(
                  child: InkWell(
                    onTap: widget.onAccepttap,
                    child: Container(
                      height: SizeConfig.heightMultiplier * 5,
                      width: SizeConfig.widthMultiplier * 40,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: Text(
                          tr('acceptOrderButton'),
                          // tr(''),
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

  // دالة لإرجاع التاريخ فقط
  String extractDate(String dateTimeStr) {
    final dt = JordanTime.parse(dateTimeStr);
    if (dt == null) return dateTimeStr;
    return "${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}";
  }

  String extractTime(String dateTimeStr) {
    final dt = JordanTime.parse(dateTimeStr);
    if (dt == null) return dateTimeStr;

    int hour = dt.hour;
    String period = hour >= 12 ? tr('pm') : tr('am');

    // تحويل الساعة إلى صيغة 12 ساعة
    hour = hour % 12;
    if (hour == 0) hour = 12;

    String minute = dt.minute.toString().padLeft(2, '0');

    return "$hour:$minute $period";
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

  Widget statusTag({
    required String text,
    required String icon,
    required Color color,
    required Color bgColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Image.asset(icon, width: 10, height: 10),
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
      children: [
        Image.asset(
          icon,
          height: 10,
          color: widget.isDevlivered ? Colors.white : Colors.grey,
        ),
        Spacing.x(1),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: textTheme.bodySmall!.copyWith(
                fontWeight: FontWeight.w600,
                color: widget.isDevlivered ? Colors.white : Colors.black,
              ),
            ),
            Spacing.y(.3),
            Text(
              value,
              style: textTheme.bodySmall!.copyWith(
                color: widget.isDevlivered ? Colors.white : Colors.black,
              ),
            ),
          ],
        ),
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

// دالة لإرجاع التاريخ فقط
String extractDate(String dateTimeStr) {
  final dt = JordanTime.parse(dateTimeStr);
  if (dt == null) return dateTimeStr;
  return "${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}";
}

String extractTime(String dateTimeStr) {
  final dt = JordanTime.parse(dateTimeStr);
  if (dt == null) return dateTimeStr;

  int hour = dt.hour;
  String period = hour >= 12 ? tr('pm') : tr('am');

  // تحويل الساعة إلى صيغة 12 ساعة
  hour = hour % 12;
  if (hour == 0) hour = 12;

  String minute = dt.minute.toString().padLeft(2, '0');

  return "$hour:$minute $period";
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
          children: [
            Image.asset(
              icon ?? 'assets/images/user.png',
              width: 15,
              height: 15,
            ),
            Spacing.x(3),
            Text(
              title ?? '',
              style: textTheme.bodyMedium!.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
            ),
            const Spacer(),
            Text(
              desc ?? '',
              style: textTheme.bodySmall!.copyWith(color: Colors.white),
            ),
          ],
        ),
        Spacing.y(0.5),
        const Divider(color: Colors.grey, thickness: 0.5),
      ],
    );
  }
}

// Animated search icon with Lottie animation
class AnimatedSearchIcon extends StatefulWidget {
  const AnimatedSearchIcon({super.key});

  @override
  State<AnimatedSearchIcon> createState() => _AnimatedSearchIconState();
}

class _AnimatedSearchIconState extends State<AnimatedSearchIcon>
    with TickerProviderStateMixin {
  late AnimationController _lottieController;

  @override
  void initState() {
    super.initState();
    _lottieController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );
    _lottieController.repeat();
  }

  @override
  void dispose() {
    _lottieController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isRTL = AppLocalizations.isRTL;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Animated search icon
        AnimatedBuilder(
          animation: _lottieController,
          builder: (context, child) {
            return Transform.rotate(
              angle: _lottieController.value * 2 * 3.14159,
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.primary, width: 2),
                ),
                child: Center(
                  child: Icon(Icons.search, color: AppColors.primary, size: 15),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 4),
        // Text underneath the animation
        Text(
          tr('looking_for_driver'),
          style: TextStyle(
            color: AppColors.primary.withValues(alpha: 0.8),
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
          textAlign: isRTL ? TextAlign.right : TextAlign.left,
        ),
      ],
    );
  }
}
