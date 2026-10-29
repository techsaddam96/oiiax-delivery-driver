import 'package:blockatie/services/driver_action_service.dart';
import 'dart:async';

import 'package:blockatie/constants/colors.dart';
import 'package:blockatie/constants/fonts.dart';
import 'package:blockatie/constants/helper.dart';
import 'package:blockatie/models/order_status_modle.dart';
import 'package:blockatie/models/shipment.dart';
import 'package:blockatie/provider/home.dart';
import 'package:blockatie/provider/order_location.dart';
import 'package:blockatie/provider/orders.dart';
import 'package:blockatie/provider/shipment.dart';
import 'package:blockatie/provider/shipment_instsnt.dart';
import 'package:blockatie/services/user_session_state.dart';
import 'package:blockatie/utils/driver_shipment_actions.dart';
import 'package:blockatie/utils/nav.dart';
import 'package:blockatie/utils/text_direction.dart';
import 'package:blockatie/views/pages/chat/widgets/driver_shipment_chat_action.dart';
import 'package:blockatie/views/pages/hub/support&assistance/support_assistence.dart';
import 'package:blockatie/views/pages/order-location/order_location.dart';
import 'package:blockatie/views/widgets/driver_chat_bubble.dart';
import 'package:blockatie/views/widgets/status_update_sheet.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

/// The locale MaterialApp resolved — the same source Login, the hub and both
/// shipment lists read, and the one Directionality and the theme font are
/// built from.
///
/// The Arabic argument is used as given. A 74-entry table keyed by the English
/// sentence used to shadow it, which made the inline Arabic at the call sites
/// dead and let the two copies drift apart — it is how status 8 came to read
/// "مرتجع" here and "تم الإرجاع" everywhere else.
String _copy(BuildContext context, String en, String ar) {
  return Localizations.localeOf(context).languageCode == 'ar' ? ar : en;
}

/// The canonical code for anything that selects a language rather than renders
/// one: the message the server sends back for an action.
String _requestLanguageCode(BuildContext context) =>
    Localizations.localeOf(context).languageCode == 'ar' ? 'ar' : 'en';

class OrderDetailPage extends StatefulWidget {
  const OrderDetailPage({
    super.key,
    required this.shipmentId,
    this.deliveryAdd,
    this.storeAdd,
    this.orderDate,
    required this.phoneCustomer,
    this.shipment,
    this.isInstantFlow = false,
    this.allowChatEntry = true,
  });

  final int shipmentId;
  final String? storeAdd;
  final String? deliveryAdd;
  final String? orderDate;
  final String phoneCustomer;
  final Shipment? shipment;
  final bool isInstantFlow;

  /// False when this screen was opened from a chat thread, so the chat action
  /// does not offer to push that same thread back on top of itself.
  final bool allowChatEntry;

  @override
  State<OrderDetailPage> createState() => _OrderDetailPageState();
}

class _OrderDetailPageState extends State<OrderDetailPage> with Helper {
  late final OrderStatusProvider _statusProvider;
  late final OrderLocationProvider _locationProvider;
  Shipment? _localShipment;
  int? _statusOverride;
  String? _busyAction;

  /// The session this screen's data belongs to. Every async result is checked
  /// against it, so a response addressed to the previous driver can never land
  /// on the next one's screen.
  late int _generation;
  bool _isLoading = true;
  bool _loadFailed = false;

  /// Set once the session this screen belongs to has ended. The shipment
  /// handed in by the caller belongs to that session too, so it has to stop
  /// being readable — clearing only the locally resolved copy would leave the
  /// widget's own argument on screen.
  bool _sessionEnded = false;

  /// Set when the server refused a step because the shipment is no longer
  /// this driver's, and the re-read no longer finds it. No step is offered
  /// after that; the server would refuse every one.
  bool _lostAssignment = false;

  bool get _isBusy => _busyAction != null;
  Shipment? get _shipment =>
      _sessionEnded ? null : (_localShipment ?? widget.shipment);
  bool get _isInstantShipment =>
      widget.isInstantFlow ||
      _shipment?.deliveryTypeId == 1 ||
      _shipment?.driverId == 0;

  int get _statusId {
    if (_statusOverride != null) return _statusOverride!;
    final shipment = _shipment;
    if (shipment == null) return 0;
    return shipment.shipmentStatusId != 0
        ? shipment.shipmentStatusId
        : shipment.shipmentStatus;
  }

  _DetailsStage get _stage {
    final shipment = _shipment;
    if (isFinalShipmentStatus(_statusId)) return _DetailsStage.finalStatus;
    if (shipment == null) return _DetailsStage.delivery;
    if (shipment.driverId == 0) return _DetailsStage.beforeAccept;
    // An admin assignment has the same server-defined pickup boundary as an
    // accepted instant job. Do not use the delivery type here: it used to send
    // every scheduled/admin assignment straight to customer mode.
    if (driverShipmentIsPrePickup(shipment)) {
      return _statusId == 10
          ? _DetailsStage.arrivedAtStore
          : _DetailsStage.storePickup;
    }
    return _DetailsStage.delivery;
  }

  /// What the driver can do next. From the status and the assignment alone,
  /// never from the delivery type: the server accepts arrival, pickup and
  /// delivery for scheduled shipments exactly as for instant ones.
  DriverShipmentActions get _driverActions {
    final shipment = _shipment;
    if (shipment == null) {
      return const DriverShipmentActions(block: DriverStepBlock.notAccepted);
    }
    if (_lostAssignment && !isFinalShipmentStatus(_statusId)) {
      return const DriverShipmentActions(block: DriverStepBlock.reassigned);
    }
    return driverShipmentActionsFor(
      statusId: _statusId,
      driverId: shipment.driverId,
      shipment: shipment,
    );
  }

  /// Mirrors the shared sheet's own fresh-contract filter.  This only decides
  /// whether to render the launcher; [ShipmentStatusUpdateSheet] fetches and
  /// applies the contract again before it displays any action.
  DriverStatusSheetMode get _statusSheetMode {
    final shipment = _shipment;
    if (shipment == null || _lostAssignment) {
      return DriverStatusSheetMode.unavailable;
    }
    return driverStatusSheetModeForShipment(shipment);
  }

  /// Customer data belongs only to the customer-delivery stage. Closed
  /// cancellation/return pages retain their established presentation below;
  /// this guard only changes active, pre-pickup work.
  bool get _canShowCustomerDetails =>
      _stage == _DetailsStage.finalStatus
          ? (!_isInstantShipment ||
              const <int>{6, 8, 9, 11}.contains(_statusId))
          : _stage == _DetailsStage.delivery;

  LatLng? get _shipmentStoreLatLng {
    final shipment = _shipment;
    if (shipment?.pickupSource != null &&
        shipment!.pickupSource!['kind'] != 'merchant')
      return null;
    final lat = double.tryParse(shipment?.latitude ?? '');
    final lng = double.tryParse(shipment?.longitude ?? '');
    if (lat == null || lng == null) return null;

    if (_looksLikeSwappedJordanPair(lat, lng)) {
      return LatLng(lng, lat);
    }

    if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return null;
    if (lat == 0 && lng == 0) return null;
    return LatLng(lat, lng);
  }

  bool _looksLikeSwappedJordanPair(double lat, double lng) {
    return !_isJordanLatitude(lat) &&
        !_isJordanLongitude(lng) &&
        _isJordanLongitude(lat) &&
        _isJordanLatitude(lng);
  }

  bool _isJordanLatitude(double value) => value >= 29.0 && value <= 34.0;

  bool _isJordanLongitude(double value) => value >= 34.0 && value <= 40.0;

  @override
  void initState() {
    super.initState();
    _generation = UserSessionState.generation;
    _localShipment = widget.shipment;
    // Data handed in by the caller is already authoritative for this session;
    // only a screen opened by id has nothing to show yet.
    _isLoading = _localShipment == null;
    _statusProvider = OrderStatusProvider();
    _locationProvider = OrderLocationProvider();
    UserSessionState.changes.addListener(_onSessionChanged);
    unawaited(_locationProvider.getShipmentCords(widget.shipmentId));
    unawaited(_statusProvider.getShipmentStatus(widget.shipmentId));
    WidgetsBinding.instance.addPostFrameCallback((_) => _resolveShipment());
  }

  /// A logout or an account switch invalidates everything on this screen. The
  /// shipment lives in State, so clearing the providers is not enough — the
  /// previous driver's recipient, phone, address and COD would stay on screen
  /// until the route happened to be popped.
  void _onSessionChanged() {
    if (!mounted) return;
    if (UserSessionState.isCurrent(_generation)) return;
    setState(() {
      _sessionEnded = true;
      _localShipment = null;
      _statusOverride = null;
      _busyAction = null;
      _isLoading = false;
      _loadFailed = true;
    });
    // Leave the route as well when there is somewhere to go back to; the
    // cleared state above is what guarantees nothing is readable either way.
    if (Navigator.of(context).canPop()) Nav.back();
  }

  @override
  void dispose() {
    UserSessionState.changes.removeListener(_onSessionChanged);
    _statusProvider.dispose();
    _locationProvider.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final date = _safeDate(widget.orderDate ?? _shipment?.createdAt);

    return ChangeNotifierProvider.value(
      value: _statusProvider,
      child: SafeArea(
        child: Scaffold(
          backgroundColor: const Color(0xffF4F7FB),
          appBar: _DetailsTopBar(
            title: _copy(context, 'Shipment Details', 'تفاصيل الشحنة'),
            subtitle:
                date.isEmpty
                    ? _copy(context, 'Operational view', 'عرض تشغيلي')
                    : '${_copy(context, 'Placed on', 'بتاريخ')} $date',
            onHelp: () => Nav.to(const SupportAssistencePage()),
          ),
          body: Consumer<OrderStatusProvider>(
            builder: (context, orderProvider, _) {
              if (_isLoading && _shipment == null) {
                return const Center(child: CircularProgressIndicator());
              }
              if (_loadFailed && _shipment == null) {
                return _DetailsErrorState(
                  message: _copy(
                    context,
                    'Unable to load shipment details. Please try again.',
                    'تعذر تحميل تفاصيل الشحنة. يرجى المحاولة مرة أخرى.',
                  ),
                  retryLabel: _copy(context, 'Retry', 'حاول مرة أخرى'),
                  onRetry: _retry,
                );
              }
              return RefreshIndicator(
                color: AppColors.primary,
                onRefresh: _retry,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: BouncingScrollPhysics(),
                  ),
                  // Clears the floating chat launcher as well as the
                  // bottom-navigation pill: at 110 the primary action and the
                  // chat button sat underneath the bubble.
                  padding: EdgeInsets.fromLTRB(
                    16,
                    16,
                    16,
                    DriverChatBubble.reservedBottomSpace + 16,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _HeaderCard(
                        policyNumber: _policyNumber,
                        statusLabel: _statusLabel(orderProvider),
                        stageLabel: _stageLabel(context),
                        isInstant: _isInstantShipment,
                      ),
                      const SizedBox(height: 14),
                      _StepCard(
                        title: _stepTitle(context),
                        message: _stepMessage(context),
                        icon: _stepIcon,
                        color: _stepColor,
                      ),
                      const SizedBox(height: 14),
                      _StageTimeline(
                        stages: _stageItems(context),
                        currentStatusId: _statusId,
                      ),
                      const SizedBox(height: 14),
                      _AllShipmentStatusesCard(currentStatusId: _statusId),
                      const SizedBox(height: 14),
                      _ShipmentSummaryCard(chips: _summaryChips(orderProvider)),
                      const SizedBox(height: 14),
                      if (_stage == _DetailsStage.beforeAccept)
                        _PrivacyNotice(
                          title: _copy(
                            context,
                            'Private details are hidden',
                            'التفاصيل الخاصة مخفية',
                          ),
                          message: _copy(
                            context,
                            'Accept the shipment first, then follow the pickup steps.',
                            'اقبل الشحنة أولاً ثم اتبع خطوات الاستلام من المتجر.',
                          ),
                        ),
                      if (_shouldShowStoreCard) ...[
                        _InfoCard(
                          title: _copy(context, 'Store', 'المتجر'),
                          icon: Icons.storefront_rounded,
                          rows: [
                            _InfoItem(
                              _copy(context, 'Name', 'الاسم'),
                              _storeName,
                              Icons.storefront_outlined,
                            ),
                            _InfoItem(
                              _copy(context, 'Phone', 'الهاتف'),
                              _storePhone,
                              Icons.phone_outlined,
                            ),
                            _InfoItem(
                              _copy(context, 'Address', 'العنوان'),
                              _storeAddress,
                              Icons.place_outlined,
                              maxLines: 3,
                            ),
                          ],
                          actions: [
                            _SmallAction(
                              label: _copy(context, 'Call', 'اتصال'),
                              icon: Icons.call_outlined,
                              onTap: () => _call(_storePhone),
                            ),
                            _SmallAction(
                              label: _copy(context, 'Open Map', 'فتح الخريطة'),
                              icon: Icons.map_outlined,
                              onTap: () => _openMap(_storeMapQuery),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                      ],
                      if (_canShowCustomerDetails) ...[
                        _InfoCard(
                          title: _copy(context, 'Recipient', 'المستلم'),
                          icon: Icons.person_pin_circle_outlined,
                          rows: [
                            _InfoItem(
                              _copy(context, 'Name', 'الاسم'),
                              _recipientName,
                              Icons.person_outline_rounded,
                            ),
                            _InfoItem(
                              _copy(context, 'Phone', 'الهاتف'),
                              _recipientPhone,
                              Icons.phone_outlined,
                            ),
                            _InfoItem(
                              _copy(context, 'Address', 'العنوان'),
                              _customerAddress,
                              Icons.place_outlined,
                              maxLines: 3,
                            ),
                          ],
                          actions: [
                            _SmallAction(
                              label: _copy(context, 'Call', 'اتصال'),
                              icon: Icons.call_outlined,
                              onTap: () => _call(_recipientPhone),
                            ),
                            _SmallAction(
                              label: _copy(context, 'Open Map', 'فتح الخريطة'),
                              icon: Icons.map_outlined,
                              onTap: () => _openMap(_customerMapQuery),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        _FinanceCard(shipment: _shipment),
                        const SizedBox(height: 14),
                        _NotesCard(note: _shipment?.shipmentNote ?? ''),
                        if (_shipment != null) ...[
                          const SizedBox(height: 14),
                          _DriverActionReasonCard(shipment: _shipment!),
                        ],
                        const SizedBox(height: 14),
                      ],
                      _ActionsCard(
                        stage: _stage,
                        actions: _driverActions,
                        isBusy: _isBusy,
                        busyAction: _busyAction,
                        onStep:
                            _shipment == null
                                ? null
                                : (step) => _runStep(step, _shipment!),
                        onTrack: _openTracking,
                        onUpdateStatus: _showUpdateStatusSheet,
                        statusSheetMode: _statusSheetMode,
                        chatAction:
                            widget.allowChatEntry
                                ? DriverShipmentChatAction(
                                  shipmentId: widget.shipmentId,
                                )
                                : null,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  bool get _shouldShowStoreCard =>
      _stage == _DetailsStage.finalStatus
          // Keep the existing closed scheduled/admin card intact so return
          // and custody information is not removed by this presentation fix.
          ? !_isInstantShipment
          : _stage == _DetailsStage.storePickup ||
              _stage == _DetailsStage.arrivedAtStore;

  List<_SummaryChipData> _summaryChips(OrderStatusProvider provider) {
    final chips = <_SummaryChipData>[
      _SummaryChipData(
        label: _copy(context, 'Shipment type', 'نوع الشحنة'),
        value: _shipmentTypeLabel,
        icon: Icons.category_outlined,
        color: AppColors.primary,
      ),
      _SummaryChipData(
        label: _copy(context, 'Shipment status', 'حالة الشحنة'),
        value: _statusLabel(provider),
        icon: Icons.fact_check_outlined,
        color: _stepColor,
      ),
      _SummaryChipData(
        label: _copy(context, 'Journey stage', 'مرحلة الرحلة'),
        value: _stageLabel(context),
        icon: Icons.timeline_outlined,
        color: AppColors.primary,
      ),
    ];

    if (_canShowCustomerDetails) {
      chips.addAll([
        _SummaryChipData(
          label: _copy(context, 'Return status', 'حالة المرتجع'),
          value: _returnStatusLabel,
          icon: Icons.assignment_return_outlined,
          color: _returnStatusColor,
        ),
        _SummaryChipData(
          label: _copy(context, 'Accounting status', 'حالة المحاسبة'),
          value: _accountingStatusLabel,
          icon: Icons.account_balance_wallet_outlined,
          color: _accountingStatusColor,
        ),
      ]);
    }

    return chips;
  }

  String get _policyNumber {
    final value = _shipment?.policyNum.trim() ?? '';
    return value.isEmpty ? _copy(context, 'Not available', 'غير متوفر') : value;
  }

  String get _shipmentTypeLabel {
    final shipment = _shipment;
    if (shipment == null) return _copy(context, 'Not available', 'غير متوفر');

    final localized =
        getLocalizedTypeName(shipment.typeNameEn, shipment.typeNameAr).trim();
    if (localized.isNotEmpty) return localized;

    return switch (shipment.deliveryTypeId) {
      1 => _copy(context, 'Instant', 'فوري'),
      2 => _copy(context, 'Scheduled', 'مجدولة'),
      3 => _copy(context, 'Same-Day', 'نفس اليوم'),
      4 => _copy(context, 'Next-Day', 'اليوم التالي'),
      5 => _copy(context, 'Economy', 'اقتصادي'),
      6 => _copy(context, 'Express', 'سريع'),
      7 => _copy(context, 'Contactless', 'بدون تلامس'),
      _ => _copy(context, 'Not available', 'غير متوفر'),
    };
  }

  String get _returnStatusLabel {
    final shipment = _shipment;
    final returnCode = shipment?.returnedShipment ?? 0;
    final localized =
        shipment == null
            ? ''
            : getLocalizedTypeName(
              shipment.returnTypeNameEn,
              shipment.returnTypeNameAr,
            ).trim();
    if (returnCode != 0 && localized.isNotEmpty) {
      return localized;
    }
    if (_statusId == 8) {
      return _copy(context, 'Returned', 'مرتجع');
    }
    if (returnCode == 0) {
      return _copy(context, 'No return', 'لا يوجد مرتجع');
    }
    if (returnCode == 2) {
      return _copy(context, 'Return requested', 'يوجد مرتجع');
    }
    return _copy(context, 'Returned', 'مرتجع');
  }

  Color get _returnStatusColor {
    final returnCode = _shipment?.returnedShipment ?? 0;
    if (_statusId == 8 || returnCode != 0) {
      return const Color(0xffEF4444);
    }
    return const Color(0xff16A06D);
  }

  String get _accountingStatusLabel {
    final accountingCode = _shipment?.accountingShipment ?? 0;
    if (accountingCode == 0) {
      return _copy(context, 'Non-accounting', 'غير محسوب');
    }
    if (accountingCode == 1) {
      return _copy(context, 'Driver-accounting', 'محاسبة السائق');
    }
    return _copy(context, 'Client-accounting', 'محاسبة العملاء');
  }

  Color get _accountingStatusColor {
    final accountingCode = _shipment?.accountingShipment ?? 0;
    if (accountingCode == 0) {
      return const Color(0xffF59E0B);
    }
    if (accountingCode == 1) {
      return AppColors.primary;
    }
    return const Color(0xff16A06D);
  }

  /// The one status resolver, shared with both shipment lists and the update
  /// sheet, so the same shipment cannot be worded differently in two places.
  ///
  /// `provider.currentStatus` is deliberately not a fallback: it is a raw
  /// backend string that defaults to the English literal "Order Placed".
  String _statusLabel(OrderStatusProvider provider) {
    if (_statusId <= 0) {
      return _copy(context, 'Status unavailable', 'الحالة غير متوفرة');
    }
    final shipment = _shipment;
    return getStatusLabel(
      context,
      _statusId,
      statusNameEn: shipment?.statusNameEn,
      statusNameAr: shipment?.statusNameAr,
    );
  }

  String _stageLabel(BuildContext context) {
    switch (_stage) {
      case _DetailsStage.beforeAccept:
        return _copy(context, 'Available Shipment', 'شحنة متاحة');
      case _DetailsStage.storePickup:
        return _copy(context, 'Go to Store', 'توجه إلى المتجر');
      case _DetailsStage.arrivedAtStore:
        return _copy(context, 'Arrived at Store', 'وصلت إلى المتجر');
      case _DetailsStage.delivery:
        return _copy(context, 'Customer Delivery', 'توصيل إلى العميل');
      case _DetailsStage.finalStatus:
        return _finalStatusLabel(context);
    }
  }

  String _stepTitle(BuildContext context) {
    switch (_stage) {
      case _DetailsStage.beforeAccept:
        return _copy(context, 'Accept first', 'اقبل الشحنة أولاً');
      case _DetailsStage.storePickup:
        return _copy(context, 'Go to Store', 'توجه إلى المتجر');
      case _DetailsStage.arrivedAtStore:
        return _copy(context, 'Pick up shipment', 'استلام الشحنة');
      case _DetailsStage.delivery:
        return _copy(context, 'Delivery stage', 'مرحلة التوصيل');
      case _DetailsStage.finalStatus:
        return _copy(context, 'Closed shipment', 'شحنة مغلقة');
    }
  }

  String _stepMessage(BuildContext context) {
    switch (_stage) {
      case _DetailsStage.beforeAccept:
        return _copy(
          context,
          'Customer details are protected until the shipment is accepted and picked up.',
          'بيانات العميل محمية حتى يتم قبول الشحنة واستلامها من المتجر.',
        );
      case _DetailsStage.storePickup:
        return _copy(
          context,
          'Only store pickup information is visible now.',
          'المتاح الآن هو معلومات استلام الشحنة من المتجر فقط.',
        );
      case _DetailsStage.arrivedAtStore:
        return _copy(
          context,
          'Confirm pickup after receiving the shipment from the store.',
          'أكد استلام الشحنة بعد أخذها من المتجر.',
        );
      case _DetailsStage.delivery:
        return _copy(
          context,
          'Customer delivery details and status actions are available.',
          'تفاصيل العميل وإجراءات حالة التوصيل متاحة الآن.',
        );
      case _DetailsStage.finalStatus:
        return _copy(
          context,
          'This shipment is in a final status and is read-only.',
          'هذه الشحنة في حالة نهائية ولا يمكن تعديلها.',
        );
    }
  }

  List<_StageStepData> _stageItems(BuildContext context) {
    if (!_isInstantShipment) {
      final active = _assignedStageIndex;
      return [
        _StageStepData(
          title: _copy(context, 'Assigned', 'مسندة'),
          icon: Icons.assignment_turned_in_outlined,
          state: _timelineState(0, active),
        ),
        _StageStepData(
          title: _copy(context, 'Store', 'المتجر'),
          icon: Icons.storefront_outlined,
          state: _timelineState(1, active),
        ),
        _StageStepData(
          title: _copy(context, 'Arrived', 'الوصول'),
          icon: Icons.location_on_outlined,
          state: _timelineState(2, active),
        ),
        _StageStepData(
          title: _copy(context, 'Pickup', 'الاستلام'),
          icon: Icons.inventory_2_outlined,
          state: _timelineState(3, active),
        ),
        _StageStepData(
          title:
              isFinalShipmentStatus(_statusId)
                  ? _finalStatusLabel(context)
                  : _copy(context, 'Delivery', 'التوصيل'),
          icon: Icons.near_me_outlined,
          state: _timelineState(4, active),
        ),
      ];
    }

    final active = _instantStageIndex;
    return [
      _StageStepData(
        title: _copy(context, 'Accepted', 'القبول'),
        icon: Icons.check_circle_outline_rounded,
        state: _timelineState(0, active),
      ),
      _StageStepData(
        title: _copy(context, 'Store', 'المتجر'),
        icon: Icons.storefront_outlined,
        state: _timelineState(1, active),
      ),
      _StageStepData(
        title: _copy(context, 'Arrived', 'الوصول'),
        icon: Icons.location_on_outlined,
        state: _timelineState(2, active),
      ),
      _StageStepData(
        title: _copy(context, 'Pickup', 'الاستلام'),
        icon: Icons.inventory_2_outlined,
        state: _timelineState(3, active),
      ),
      _StageStepData(
        title:
            isFinalShipmentStatus(_statusId)
                ? _finalStatusLabel(context)
                : _copy(context, 'Delivery', 'التوصيل'),
        icon: Icons.near_me_outlined,
        state: _timelineState(4, active),
      ),
    ];
  }

  int get _instantStageIndex {
    switch (_stage) {
      case _DetailsStage.beforeAccept:
        return 0;
      case _DetailsStage.storePickup:
        return 1;
      case _DetailsStage.arrivedAtStore:
        return 2;
      case _DetailsStage.delivery:
        return 4;
      case _DetailsStage.finalStatus:
        return 4;
    }
  }

  int get _assignedStageIndex {
    return switch (_stage) {
      _DetailsStage.beforeAccept => 0,
      _DetailsStage.storePickup => 1,
      _DetailsStage.arrivedAtStore => 2,
      _DetailsStage.delivery || _DetailsStage.finalStatus => 4,
    };
  }

  _StageStepState _timelineState(int index, int activeIndex) {
    if (index < activeIndex) return _StageStepState.completed;
    if (index == activeIndex) return _StageStepState.active;
    return _StageStepState.pending;
  }

  IconData get _stepIcon {
    switch (_stage) {
      case _DetailsStage.beforeAccept:
        return Icons.lock_outline_rounded;
      case _DetailsStage.storePickup:
        return Icons.storefront_rounded;
      case _DetailsStage.arrivedAtStore:
        return Icons.inventory_2_outlined;
      case _DetailsStage.delivery:
        return Icons.local_shipping_outlined;
      case _DetailsStage.finalStatus:
        return Icons.lock_outline_rounded;
    }
  }

  Color get _stepColor {
    switch (_stage) {
      case _DetailsStage.beforeAccept:
        return const Color(0xff64748B);
      case _DetailsStage.storePickup:
        return AppColors.primary;
      case _DetailsStage.arrivedAtStore:
        return const Color(0xffF59E0B);
      case _DetailsStage.delivery:
        return const Color(0xff16A06D);
      case _DetailsStage.finalStatus:
        return _finalStatusColor;
    }
  }

  /// The shared resolver again, so a closed shipment is worded exactly as the
  /// lists word it. The local table used to say "مرتجع" for status 8 — the
  /// return-flag wording — where everywhere else says "تم الإرجاع".
  String _finalStatusLabel(BuildContext context) {
    if (!isFinalShipmentStatus(_statusId)) {
      return _copy(context, 'Closed shipment', 'شحنة مغلقة');
    }
    return getStatusLabel(context, _statusId);
  }

  /// By id, and by the same table the lists and the sheet use, so a status can
  /// never be one colour here and another there.
  Color get _finalStatusColor =>
      isFinalShipmentStatus(_statusId)
          ? getStatusColor(_statusId)
          : const Color(0xff64748B);

  String get _storeName => _display(_raw(_shipment?.nstore, widget.storeAdd));
  String get _storePhone => _display(_raw(_shipment?.phclient));
  String get _storeAddress {
    final candidate = _raw(_shipment?.lclient, widget.storeAdd);
    if (_looksLikeImagePath(candidate ?? '')) return '';
    return _display(candidate);
  }

  String get _recipientName => _display(_raw(_shipment?.recipientName));
  String get _recipientPhone =>
      _display(_raw(_shipment?.recipientPhone, widget.phoneCustomer));
  String get _customerAddress =>
      _display(_raw(_shipment?.deliveryAddress, widget.deliveryAdd));

  String get _storeMapQuery {
    final lat = double.tryParse(_shipment?.latitude ?? '');
    final lng = double.tryParse(_shipment?.longitude ?? '');
    if (lat != null && lng != null && (lat != 0 || lng != 0)) {
      return '$lat,$lng';
    }
    final address = _raw(_shipment?.lclient, widget.storeAdd);
    if (address != null && !_looksLikeImagePath(address)) {
      return address;
    }
    return _raw(_shipment?.nstore, widget.storeAdd) ?? '';
  }

  String get _customerMapQuery {
    final lat = double.tryParse(_shipment?.deliveryLatitude ?? '');
    final lng = double.tryParse(_shipment?.deliveryLongitude ?? '');
    if (lat != null && lng != null && (lat != 0 || lng != 0)) {
      return '$lat,$lng';
    }
    return _raw(_shipment?.deliveryAddress, widget.deliveryAdd) ?? '';
  }

  Future<void> _runStep(DriverShipmentStep step, Shipment shipment) {
    return switch (step) {
      DriverShipmentStep.arriveAtStore => _markArrivedAtStore(shipment),
      DriverShipmentStep.pickUp => _pickupShipment(shipment),
      DriverShipmentStep.deliver => _deliverShipment(shipment),
    };
  }

  Future<void> _markArrivedAtStore(Shipment shipment) async {
    final fresh = await DriverActionService.read(context).fetch(shipment.id);
    if (!mounted ||
        !UserSessionState.isCurrent(_generation) ||
        fresh == null ||
        !fresh.allowsAction('arrive_at_pickup')) {
      await _refreshFromServer();
      return;
    }
    shipment = fresh;
    setState(() {
      _localShipment = fresh;
      _statusOverride = null;
    });
    if (_isBusy) return;
    setState(() => _busyAction = 'arrived');
    final result = await context
        .read<ShipmentInstantprovider>()
        .markArrivedAtStore(
          shipment.id,
          languageCode: _requestLanguageCode(context),
        );
    if (!mounted) return;
    _showSnack(result.message, isError: !result.success);
    if (result.success) {
      await _adoptStatus(10);
    } else {
      await _reconcileRefusal(result);
    }
    if (!mounted) return;
    setState(() => _busyAction = null);
  }

  /// Picked up from the store (2 or 10 -> 4). From 2 it skips the geofenced
  /// arrival, which the server allows, so the driver is asked first.
  Future<void> _pickupShipment(Shipment shipment) async {
    final fresh = await DriverActionService.read(context).fetch(shipment.id);
    if (!mounted ||
        !UserSessionState.isCurrent(_generation) ||
        fresh == null ||
        !fresh.allowsAction('confirm_pickup')) {
      await _refreshFromServer();
      return;
    }
    shipment = fresh;
    setState(() {
      _localShipment = fresh;
      _statusOverride = null;
    });
    if (_isBusy) return;
    if (_statusId != 10) {
      final confirmed = await confirmDirectPickup(
        context,
        policyNumber: _policyNumber,
      );
      if (!confirmed || !mounted || _isBusy) return;
    }
    setState(() => _busyAction = 'pickup');
    final result = await context
        .read<ShipmentInstantprovider>()
        .pickupShipmentFromStore(
          shipment.id,
          languageCode: _requestLanguageCode(context),
        );
    if (!mounted) return;
    _showSnack(result.message, isError: !result.success);
    if (result.success) {
      await _adoptStatus(4);
    } else {
      await _reconcileRefusal(result);
    }
    if (!mounted) return;
    setState(() => _busyAction = null);
  }

  /// "Delivered" (تم التسليم). Offered only from in transit (4), see
  /// [canMarkDelivered]; the server is the authority on whether it applies.
  ///
  /// The screen never shows the shipment as delivered before the server says
  /// so. A refusal re-reads the shipment, and so does a missing reply: a
  /// timeout is not resent automatically, because the delivery may already be
  /// recorded (a manual retry reuses the request id, see
  /// ShipmentInstantprovider.deliverShipment).
  Future<void> _deliverShipment(Shipment shipment) async {
    final fresh = await DriverActionService.read(context).fetch(shipment.id);
    if (!mounted ||
        !UserSessionState.isCurrent(_generation) ||
        fresh == null ||
        !fresh.allowsAction('complete_delivery')) {
      await _refreshFromServer();
      return;
    }
    shipment = fresh;
    setState(() {
      _localShipment = fresh;
      _statusOverride = null;
    });
    if (_isBusy) return;
    final confirmed = await confirmDriverDelivery(
      context,
      policyNumber: _policyNumber,
      amountToCollect: shipment.productToCollect,
    );
    // The shipment may have changed, or another action started, while the
    // dialog was open.
    if (!confirmed || !mounted || _isBusy) return;
    if (!canMarkDelivered(_statusId)) return;

    setState(() => _busyAction = 'deliver');
    final languageCode = _requestLanguageCode(context);
    final result = await context
        .read<ShipmentInstantprovider>()
        .deliverShipment(shipment.id, languageCode: languageCode);
    if (!mounted || !UserSessionState.isCurrent(_generation)) return;

    if (result.success) {
      _showSnack(result.message, isError: false);
      await _adoptConfirmedDelivery();
    } else if (result.code == 'SESSION_CHANGED') {
      // The session listener has already cleared this screen.
    } else if (result.unconfirmed) {
      _showSnack(result.message);
      await _refreshFromServer();
      if (mounted && isFinalShipmentStatus(_statusId)) {
        _showSnack(
          _copy(
            context,
            'The shipment is now closed on the server.',
            'الشحنة مغلقة الآن على الخادم.',
          ),
          isError: false,
        );
      }
    } else {
      _showSnack(result.message);
      // 409 (status changed), 403 (no longer assigned), 404: what is on screen
      // is out of date. Read it again instead of leaving the button there.
      await _reconcileRefusal(result);
    }
    if (!mounted) return;
    setState(() => _busyAction = null);
  }

  /// After a refused step: when the refusal says the screen is out of date,
  /// read the shipment again; when it says the shipment is no longer this
  /// driver's and the re-read no longer finds it, stop offering steps.
  Future<void> _reconcileRefusal(ShipmentActionResult result) async {
    await _refreshFromServer();
    if (!mounted || !UserSessionState.isCurrent(_generation)) return;
    if (driverStepRefusalLostShipment(result) &&
        _findShipmentInProviders() == null) {
      setState(() => _lostAssignment = true);
    }
  }

  /// Tracking offers the same steps, Delivered included, so whatever the
  /// driver did there is read back on return instead of leaving this screen
  /// on the status it had before the push.
  Future<void> _openTracking() async {
    await Navigator.push(
      Nav.context,
      MaterialPageRoute<void>(
        builder:
            (_) => LocationOrderPage(
              shipmentId: widget.shipmentId,
              phoneCustomer: _recipientPhone,
              shipment: _shipment,
              isInstantFlow: _isInstantShipment,
              storeLocation: _shipmentStoreLatLng,
              policyNumber: _policyNumber,
              shipmentTypeLabel: _shipmentTypeLabel,
              statusLabel: _statusLabel(_statusProvider),
              stageLabel: _stageLabel(context),
              storeName: _storeName,
              storePhone: _storePhone,
              storeAddress: _storeAddress,
              customerName: _recipientName,
              customerAddress: _customerAddress,
            ),
      ),
    );
    if (!mounted || !UserSessionState.isCurrent(_generation)) return;
    await _refreshFromServer();
  }

  /// The server confirmed the delivery, so that reply is authoritative: the
  /// screen shows Completed straight away, even if the lists are slow or still
  /// serve a cached row, and adopts the server's row once it is closed there
  /// too. Counters and cash figures are reloaded as well.
  Future<void> _adoptConfirmedDelivery() async {
    final base = _shipment;
    setState(() {
      _statusOverride = null;
      if (base != null) {
        _localShipment = base.copyWith(
          shipmentStatusId: driverDeliveredStatusId,
          shipmentStatus: driverDeliveredStatusId,
          statusNameEn: 'Completed',
          statusNameAr: 'مكتمل',
          updatedAt: DateTime.now().toIso8601String(),
        );
      }
    });

    final home = context.read<HomeProvider>();
    unawaited(home.getDriverStatistics(context, force: true));
    await context.read<ShipmentProvider>().getAllShipments(force: true);
    if (!mounted || !UserSessionState.isCurrent(_generation)) return;
    final refreshed = _findShipmentInProviders();
    unawaited(_statusProvider.getShipmentStatus(widget.shipmentId));
    if (refreshed != null &&
        isFinalShipmentStatus(refreshed.shipmentStatusId)) {
      setState(() => _localShipment = refreshed);
    }
  }

  /// A targeted refresh works independently of the loaded type, search and page.
  /// Failure withdraws capabilities instead of re-authorizing from a cached row.
  Future<void> _refreshFromServer() async {
    if (!mounted || !UserSessionState.isCurrent(_generation)) return;
    final fresh = await DriverActionService.read(
      context,
    ).fetch(widget.shipmentId);
    if (!mounted || !UserSessionState.isCurrent(_generation)) return;
    setState(() {
      _localShipment =
          fresh ?? _shipment?.copyWith(shipmentStatusId: _statusId);
      _statusOverride = null;
    });
    unawaited(_statusProvider.getShipmentStatus(widget.shipmentId));
  }

  Future<void> _showUpdateStatusSheet() async {
    if (_isBusy || _statusSheetMode == DriverStatusSheetMode.unavailable) {
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
          shipmentId: widget.shipmentId,
          statuses: statuses,
          currentStatusId: _statusId,
          currentStatusLabel: _statusLabel(_statusProvider),
          currentStageLabel: _stageLabel(context),
          policyNumber: _policyNumber,
          doorFeeCollectable: _shipment?.financial?.doorFeeCollectable ?? 0,
          onSubmit: (status, reason) async {
            if (!mounted) return false;
            setState(() => _busyAction = 'status');
            final success = await homeProvider.updateStatus(
              shipmentId: widget.shipmentId,
              statusId: status.id,
              reasonId: reason?.reasonId,
              reasonNote: reason?.note,
              feeCollectedAmount: reason?.feeCollectedAmount,
              isInstant: _isInstantShipment,
              showSuccessDialog: false,
            );
            if (!mounted) return false;
            if (success) {
              _statusOverride = int.tryParse(status.id) ?? _statusOverride;
              if (_localShipment != null) {
                setState(() {
                  _localShipment = _localShipment!.copyWith(
                    shipmentStatusId: int.tryParse(status.id) ?? _statusId,
                    shipmentStatus: int.tryParse(status.id) ?? _statusId,
                    statusNameEn: status.statusNameEn,
                    statusNameAr: status.statusNameAr,
                    messageEn: status.messageEn,
                    messageAr: status.messageAr,
                    actionReasonType:
                        reason == null
                            ? _localShipment!.actionReasonType
                            : _mapReasonActionType(
                              int.tryParse(status.id) ?? 0,
                            ),
                    actionReasonId:
                        reason?.reasonId ?? _localShipment!.actionReasonId,
                    actionReasonTitleAr:
                        reason?.titleAr ?? _localShipment!.actionReasonTitleAr,
                    actionReasonTitleEn:
                        reason?.titleEn ?? _localShipment!.actionReasonTitleEn,
                    actionReasonNote:
                        reason?.note?.trim().isNotEmpty == true
                            ? reason!.note!.trim()
                            : _localShipment!.actionReasonNote,
                    actionReasonCreatedAt: DateTime.now().toIso8601String(),
                  );
                });
              }
              unawaited(
                context.read<ShipmentProvider>().getAllShipments(force: true),
              );
              unawaited(_statusProvider.getShipmentStatus(widget.shipmentId));
              _showSnack(
                _copy(
                  context,
                  'Shipment status updated.',
                  'تم تحديث حالة الشحنة.',
                ),
              );
            }
            setState(() => _busyAction = null);
            return success;
          },
        );
      },
    );
    if (mounted) await _refreshFromServer();
  }

  Future<void> _resolveShipment() async {
    if (!mounted) return;
    final fresh = await DriverActionService.read(
      context,
    ).fetch(widget.shipmentId);
    if (!mounted || !UserSessionState.isCurrent(_generation)) return;
    if (fresh != null) {
      setState(() {
        _localShipment = fresh;
        _statusOverride = null;
        _isLoading = false;
      });
      return;
    }
    _localShipment = _shipment?.copyWith(shipmentStatusId: _statusId);
    if (_localShipment != null) {
      setState(() => _isLoading = false);
      return;
    }

    setState(() {
      _isLoading = true;
      _loadFailed = false;
    });

    Shipment? found = _findShipmentInProviders();
    if (found == null) {
      await context.read<ShipmentProvider>().getAllShipments(force: true);
      // A reply addressed to the previous driver must never populate this
      // screen for the next one.
      if (!mounted || !UserSessionState.isCurrent(_generation)) return;
      found = _findShipmentInProviders();
    }

    if (!mounted || !UserSessionState.isCurrent(_generation)) return;
    setState(() {
      _localShipment = found;
      _isLoading = false;
      // Nothing came back. That is a failed read, not a shipment whose every
      // field happens to be empty, and it must not be drawn as one.
      _loadFailed = found == null;
    });
  }

  /// Adopts a step the server has just confirmed ([statusId] is the status it
  /// set), then reconciles with the lists.
  ///
  /// When the lists hold the shipment, their row is the authority. When they
  /// do not — a later page of the assigned list, or a screen opened from a
  /// notification — the server's confirmation still stands. Rolling back to
  /// the status before the step used to offer that step again and hide the
  /// next one, so Delivered never appeared after a pickup.
  Future<void> _adoptStatus(int statusId) async {
    if (!mounted) return;
    setState(() => _statusOverride = statusId);

    await context.read<ShipmentProvider>().getAllShipments(force: true);
    if (!mounted || !UserSessionState.isCurrent(_generation)) return;

    final refreshed = _findShipmentInProviders();
    await _statusProvider.getShipmentStatus(widget.shipmentId);
    if (!mounted || !UserSessionState.isCurrent(_generation)) return;

    setState(() {
      if (refreshed != null) {
        _localShipment = refreshed;
      } else {
        final base = _shipment;
        if (base != null) {
          // Names cleared so the label comes from the shared table for the
          // new id, not from the status before the step.
          _localShipment = base.copyWith(
            shipmentStatusId: statusId,
            shipmentStatus: statusId,
            statusNameEn: '',
            statusNameAr: '',
          );
        }
      }
      _statusOverride = null;
    });
    await _refreshFromServer();
  }

  Future<void> _retry() async {
    await _resolveShipment();
    if (!mounted || !UserSessionState.isCurrent(_generation)) return;
    await _statusProvider.getShipmentStatus(widget.shipmentId);
  }

  Shipment? _findShipmentInProviders() {
    // The loaded page of the assigned list (the same rows the list shows).
    final assigned = context.read<ShipmentProvider>().paginatedShipments;
    for (final shipment in assigned) {
      if (shipment.id == widget.shipmentId) return shipment;
    }

    final instant = context.read<ShipmentInstantprovider>().allShipments;
    for (final shipment in instant) {
      if (shipment.id == widget.shipmentId) return shipment;
    }
    return null;
  }

  String _mapReasonActionType(int statusId) {
    switch (statusId) {
      case 7:
        return 'cancel';
      case 8:
        return 'return';
      case 9:
        return 'failed_delivery';
      default:
        return '';
    }
  }

  /// Opening an external app can fail in three ways: a false return, a
  /// PlatformException when no app can handle it, or anything else the plugin
  /// throws. All three end in the same localized sentence — never a raw
  /// platform error.
  Future<bool> _launchExternal(Uri uri) async {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('External launch failed: ${e.runtimeType}');
      return false;
    }
  }

  Future<void> _call(String phone) async {
    if (_isMissingValue(phone)) {
      _showSnack(
        _copy(context, 'Phone is not available.', 'رقم الهاتف غير متوفر.'),
      );
      return;
    }
    final launched = await _launchExternal(Uri.parse('tel:${phone.trim()}'));
    if (!mounted || launched) return;
    _showSnack(_copy(context, 'Unable to start call.', 'تعذر بدء الاتصال.'));
  }

  Future<void> _openMap(String query) async {
    if (_isMissingValue(query)) {
      _showSnack(
        _copy(context, 'Location is not available.', 'الموقع غير متوفر.'),
      );
      return;
    }
    final launched = await _launchExternal(
      Uri.https('www.google.com', '/maps/search/', {
        'api': '1',
        'query': query,
      }),
    );
    if (!mounted || launched) return;
    _showSnack(_copy(context, 'Unable to open maps.', 'تعذر فتح الخرائط.'));
  }

  void _showSnack(String message, {bool isError = true}) {
    final clean =
        message.trim().isEmpty
            ? _copy(context, 'Something went wrong.', 'حدث خطأ ما.')
            : message.trim();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(clean),
          backgroundColor:
              isError ? const Color(0xffDC2626) : const Color(0xff16A06D),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  String? _raw(String? primary, [String? fallback]) {
    final value = primary?.trim() ?? '';
    if (value.isNotEmpty && value.toLowerCase() != 'null') return value;
    final fallbackValue = fallback?.trim() ?? '';
    if (fallbackValue.isNotEmpty && fallbackValue.toLowerCase() != 'null') {
      return fallbackValue;
    }
    return null;
  }

  String _display(String? value) {
    final text = value?.trim() ?? '';
    return text.isEmpty ? _copy(context, 'Not available', 'غير متوفر') : text;
  }

  bool _isMissingValue(String value) {
    final cleaned = value.trim();
    return cleaned.isEmpty ||
        cleaned == 'Not available' ||
        cleaned == 'غير متوفر';
  }

  /// A date the driver can trust, or nothing.
  ///
  /// Never the raw column: MySQL's zero date and anything unparseable used to
  /// be printed verbatim, and the format disagreed with both shipment lists.
  /// Pinned to `en` digits so the date matches the money and identifiers on
  /// the same screen.
  String _safeDate(String? value) {
    final parsed = Shipment.safeDateTime(value);
    if (parsed == null) return '';
    return DateFormat('dd/MM/yyyy', 'en').format(parsed);
  }
}

/// Shown instead of the details when nothing could be loaded.
///
/// The page used to render every field as "Not available", which reads as a
/// shipment with no data rather than a read that failed.
class _DetailsErrorState extends StatelessWidget {
  const _DetailsErrorState({
    required this.message,
    required this.retryLabel,
    required this.onRetry,
  });

  final String message;
  final String retryLabel;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_rounded,
              size: 44,
              color: Color(0xff94A3B8),
            ),
            const SizedBox(height: 14),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xff0F172A),
                fontSize: 14,
                fontWeight: FontWeight.w800,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text(retryLabel),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                minimumSize: const Size.fromHeight(46),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _DetailsStage {
  beforeAccept,
  storePickup,
  arrivedAtStore,
  delivery,
  finalStatus,
}

enum _StageStepState { completed, active, pending }

class _StageStepData {
  const _StageStepData({
    required this.title,
    required this.icon,
    required this.state,
  });

  final String title;
  final IconData icon;
  final _StageStepState state;
}

class _StageTimeline extends StatelessWidget {
  const _StageTimeline({required this.stages, required this.currentStatusId});

  final List<_StageStepData> stages;
  final int currentStatusId;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _copy(context, 'Shipment Stages', 'مراحل الشحنة'),
            style: const TextStyle(
              color: Color(0xff0F172A),
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < stages.length; i++) ...[
                Expanded(child: _TimelineNode(data: stages[i])),
                if (i != stages.length - 1)
                  Container(
                    width: 18,
                    height: 2,
                    margin: const EdgeInsets.only(top: 20),
                    decoration: BoxDecoration(
                      color:
                          stages[i].state == _StageStepState.completed
                              ? const Color(0xff16A06D)
                              : const Color(0xffCBD5E1),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
              ],
            ],
          ),
          if (_isFinalTimelineStatus(currentStatusId)) ...[
            const SizedBox(height: 16),
            _FinalOutcomeStrip(currentStatusId: currentStatusId),
          ],
        ],
      ),
    );
  }
}

bool _isFinalTimelineStatus(int statusId) {
  return const <int>{6, 7, 8, 9, 11}.contains(statusId);
}

class _FinalOutcomeStrip extends StatelessWidget {
  const _FinalOutcomeStrip({required this.currentStatusId});

  final int currentStatusId;

  @override
  Widget build(BuildContext context) {
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    final outcomes = <_FinalOutcomeData>[
      _FinalOutcomeData(
        id: 6,
        title: isArabic ? 'تم التسليم' : 'Delivered',
        icon: Icons.verified_outlined,
        color: const Color(0xff16A06D),
      ),
      _FinalOutcomeData(
        id: 7,
        title: isArabic ? 'تم الإلغاء' : 'Cancelled',
        icon: Icons.cancel_outlined,
        color: const Color(0xff64748B),
      ),
      _FinalOutcomeData(
        id: 8,
        title: isArabic ? 'مرتجع' : 'Returned',
        icon: Icons.assignment_return_outlined,
        color: const Color(0xffF59E0B),
      ),
      _FinalOutcomeData(
        id: 9,
        title: isArabic ? 'فشل التسليم' : 'Failed',
        icon: Icons.error_outline_rounded,
        color: const Color(0xffDC2626),
      ),
      _FinalOutcomeData(
        id: 11,
        title: isArabic ? 'مكتمل' : 'Completed',
        icon: Icons.task_alt_rounded,
        color: const Color(0xff16A06D),
      ),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xffF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xffE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isArabic ? 'نتيجة الشحنة' : 'Shipment outcome',
            style: const TextStyle(
              color: Color(0xff334155),
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children:
                outcomes.map((outcome) {
                  final isActive = outcome.id == currentStatusId;
                  final color =
                      isActive ? outcome.color : const Color(0xff94A3B8);
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: isActive ? 0.14 : 0.08),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: color.withValues(alpha: isActive ? 0.28 : 0.14),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(outcome.icon, color: color, size: 15),
                        const SizedBox(width: 6),
                        Text(
                          outcome.title,
                          style: TextStyle(
                            color:
                                isActive
                                    ? const Color(0xff0F172A)
                                    : const Color(0xff64748B),
                            fontSize: 11,
                            fontWeight:
                                isActive ? FontWeight.w900 : FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
          ),
        ],
      ),
    );
  }
}

class _FinalOutcomeData {
  const _FinalOutcomeData({
    required this.id,
    required this.title,
    required this.icon,
    required this.color,
  });

  final int id;
  final String title;
  final IconData icon;
  final Color color;
}

class _AllShipmentStatusesCard extends StatelessWidget {
  const _AllShipmentStatusesCard({required this.currentStatusId});

  final int currentStatusId;

  @override
  Widget build(BuildContext context) {
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    final statuses = List<int>.generate(11, (index) => index + 1);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.fact_check_outlined,
                  color: AppColors.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  isArabic ? 'جميع حالات الشحنة' : 'All Shipment Statuses',
                  style: const TextStyle(
                    color: Color(0xff0F172A),
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth < 360 ? 1 : 2;
              const gap = 8.0;
              final width =
                  (constraints.maxWidth - (gap * (columns - 1))) / columns;

              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children:
                    statuses.map((statusId) {
                      return SizedBox(
                        width: width,
                        child: _ShipmentStatusTile(
                          statusId: statusId,
                          currentStatusId: currentStatusId,
                        ),
                      );
                    }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ShipmentStatusTile extends StatelessWidget {
  const _ShipmentStatusTile({
    required this.statusId,
    required this.currentStatusId,
  });

  final int statusId;
  final int currentStatusId;

  @override
  Widget build(BuildContext context) {
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    final isCurrent = statusId == currentStatusId;
    final isPrevious = currentStatusId > 0 && statusId < currentStatusId;
    final isFinal = isFinalShipmentStatus(statusId);
    final baseColor =
        isCurrent
            ? getStatusColor(statusId)
            : isPrevious
            ? const Color(0xff16A06D)
            : const Color(0xff94A3B8);
    final stateLabel =
        isCurrent
            ? (isArabic ? 'الحالية' : 'Current')
            : isPrevious
            ? (isArabic ? 'سابقة' : 'Previous')
            : (isArabic ? 'قادمة' : 'Upcoming');

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: baseColor.withValues(alpha: isCurrent ? 0.12 : 0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: baseColor.withValues(alpha: isCurrent ? 0.30 : 0.14),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: baseColor.withValues(alpha: isCurrent ? 0.16 : 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(getStatusIcon(statusId), color: baseColor, size: 18),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  getStatusLabel(context, statusId),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color:
                        isCurrent
                            ? const Color(0xff0F172A)
                            : const Color(0xff475569),
                    fontSize: 12.2,
                    fontWeight: isCurrent ? FontWeight.w900 : FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 5),
                Wrap(
                  spacing: 5,
                  runSpacing: 5,
                  children: [
                    _MiniStatusBadge(label: stateLabel, color: baseColor),
                    if (isFinal)
                      _MiniStatusBadge(
                        label: isArabic ? 'نهائية' : 'Final',
                        color: const Color(0xffEF4444),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniStatusBadge extends StatelessWidget {
  const _MiniStatusBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 9.8,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _TimelineNode extends StatelessWidget {
  const _TimelineNode({required this.data});

  final _StageStepData data;

  @override
  Widget build(BuildContext context) {
    final color = switch (data.state) {
      _StageStepState.completed => const Color(0xff16A06D),
      _StageStepState.active => AppColors.primary,
      _StageStepState.pending => const Color(0xff94A3B8),
    };
    final fill = switch (data.state) {
      _StageStepState.completed => const Color(0xffDCFCE7),
      _StageStepState.active => const Color(0xffEAF2FF),
      _StageStepState.pending => const Color(0xffF1F5F9),
    };

    return Column(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 240),
          width: data.state == _StageStepState.active ? 42 : 38,
          height: data.state == _StageStepState.active ? 42 : 38,
          decoration: BoxDecoration(
            color: fill,
            shape: BoxShape.circle,
            border: Border.all(color: color.withValues(alpha: 0.28)),
            boxShadow:
                data.state == _StageStepState.active
                    ? [
                      BoxShadow(
                        color: color.withValues(alpha: 0.18),
                        blurRadius: 14,
                        offset: const Offset(0, 6),
                      ),
                    ]
                    : null,
          ),
          child: Icon(data.icon, color: color, size: 19),
        ),
        const SizedBox(height: 7),
        Text(
          data.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            color:
                data.state == _StageStepState.pending
                    ? const Color(0xff64748B)
                    : const Color(0xff0F172A),
            fontSize: 10.5,
            height: 1.15,
            fontWeight:
                data.state == _StageStepState.active
                    ? FontWeight.w900
                    : FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _DetailsTopBar extends StatelessWidget implements PreferredSizeWidget {
  const _DetailsTopBar({
    required this.title,
    required this.subtitle,
    required this.onHelp,
  });

  final String title;
  final String subtitle;
  final VoidCallback onHelp;

  @override
  Size get preferredSize => const Size.fromHeight(88);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: const Border(
            bottom: BorderSide(color: Color(0xffE2E8F0), width: 1),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.035),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: SafeArea(
          bottom: false,
          child: SizedBox(
            height: preferredSize.height,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: Row(
                children: [
                  // One chevron, mirrored once. `chevron_left_rounded`
                  // carries matchTextDirection, so Flutter flips the glyph in
                  // Arabic — choosing the right-pointing icon as well flipped
                  // it twice and left Back pointing the wrong way.
                  _TopIconButton(
                    icon: Icons.chevron_left_rounded,
                    onTap: Nav.back,
                    tooltip: _copy(context, 'Back', 'رجوع'),
                  ),

                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,

                      // Directional already: `start` is the right edge in
                      // Arabic. Asking for `end` under RTL pinned the title
                      // to the left, the opposite of what was intended.
                      crossAxisAlignment: CrossAxisAlignment.start,

                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.start,
                          style: const TextStyle(
                            color: Color(0xff0F172A),
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.start,
                          style: const TextStyle(
                            color: Color(0xff64748B),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  _HelpPill(onTap: onHelp),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TopIconButton extends StatelessWidget {
  const _TopIconButton({
    required this.icon,
    required this.onTap,
    required this.tooltip,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: const Color(0xffF8FAFC),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xffE2E8F0)),
          ),
          child: Icon(icon, color: AppColors.primary, size: 24),
        ),
      ),
    );
  }
}

class _HelpPill extends StatelessWidget {
  const _HelpPill({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.14)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.support_agent_rounded,
              size: 16,
              color: AppColors.primary,
            ),
            const SizedBox(width: 6),
            Text(
              Localizations.localeOf(context).languageCode == 'ar'
                  ? '\u0645\u0633\u0627\u0639\u062f\u0629'
                  : 'Help',
              style: TextStyle(
                color: AppColors.primary,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({
    required this.policyNumber,
    required this.statusLabel,
    required this.stageLabel,
    required this.isInstant,
  });

  final String policyNumber;
  final String statusLabel;
  final String stageLabel;
  final bool isInstant;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.14)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.045),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 4,
            width: 64,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.primary, AppColors.primary],
              ),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Text(
                  policyNumber,
                  textDirection: identifierTextDirection(policyNumber),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xff0F172A),
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.16),
                  ),
                ),
                child: Text(
                  isInstant
                      ? _copy(context, 'Instant', 'فوري')
                      : _copy(context, 'Scheduled', 'مجدولة'),
                  style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            stageLabel,
            style: const TextStyle(
              color: Color(0xff64748B),
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          _StatusPill(label: statusLabel, color: AppColors.primary),
        ],
      ),
    );
  }
}

class _SummaryChipData {
  const _SummaryChipData({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
}

class _ShipmentSummaryCard extends StatelessWidget {
  const _ShipmentSummaryCard({required this.chips});

  final List<_SummaryChipData> chips;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.summarize_outlined,
                color: AppColors.primary,
                size: 22,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  _copy(context, 'Operational Summary', 'ملخص التشغيل'),
                  style: const TextStyle(
                    color: Color(0xff0F172A),
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: chips.map((chip) => _SummaryChip(data: chip)).toList(),
          ),
        ],
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({required this.data});

  final _SummaryChipData data;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 128, maxWidth: 230),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
        decoration: BoxDecoration(
          color: data.color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: data.color.withValues(alpha: 0.16)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: data.color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(data.icon, color: data.color, size: 17),
            ),
            const SizedBox(width: 9),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    data.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xff64748B),
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    data.value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xff0F172A),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepCard extends StatelessWidget {
  const _StepCard({
    required this.title,
    required this.message,
    required this.icon,
    required this.color,
  });

  final String title;
  final String message;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: color, size: 26),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xff0F172A),
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  message,
                  style: const TextStyle(
                    color: Color(0xff64748B),
                    fontSize: 12,
                    height: 1.35,
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

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.title,
    required this.icon,
    required this.rows,
    this.actions = const [],
  });

  final String title;
  final IconData icon;
  final List<_InfoItem> rows;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppColors.primary, size: 22),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xff0F172A),
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...rows.map((row) => row),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(spacing: 10, runSpacing: 10, children: actions),
          ],
        ],
      ),
    );
  }
}

// A date for a row that must show something, or a localized placeholder.
String _detailsDateLabel(BuildContext context, String? raw) {
  final parsed = Shipment.safeDateTime(raw);
  if (parsed == null) return _copy(context, 'Not available', 'غير متوفر');
  return DateFormat('dd/MM/yyyy', 'en').format(parsed);
}

class _InfoItem extends StatelessWidget {
  const _InfoItem(this.label, this.value, this.icon, {this.maxLines = 1});

  final String label;
  final String value;
  final IconData icon;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xff64748B), size: 17),
          const SizedBox(width: 9),
          SizedBox(
            width: 82,
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xff64748B),
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              maxLines: maxLines,
              overflow: TextOverflow.ellipsis,
              // Phones, policy numbers and coordinates stay left-to-right; a
              // customer name or an Arabic address keeps the page direction.
              textDirection: identifierTextDirection(value),
              style: const TextStyle(
                color: Color(0xff0F172A),
                fontSize: 12.5,
                height: 1.35,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FinanceCard extends StatelessWidget {
  const _FinanceCard({required this.shipment});

  final Shipment? shipment;

  @override
  Widget build(BuildContext context) {
    final financial = shipment?.financial;
    final feeDue = financial?.feeDue ?? 0;
    return _InfoCard(
      title: _copy(context, 'Costs', 'التكاليف'),
      icon: Icons.payments_outlined,
      rows: [
        // The server's product_to_collect: 0 on a prepaid shipment.
        _InfoItem(
          _copy(context, 'COD amount', 'مبلغ التحصيل'),
          _moneyLabel(context, shipment?.productToCollect ?? 0),
          Icons.receipt_long_outlined,
        ),
        if (shipment?.isPrepaid ?? false)
          _InfoItem(
            _copy(context, 'Payment', 'الدفع'),
            _copy(
              context,
              'Prepaid: collect nothing from the customer.',
              'مدفوعة مسبقاً: لا تحصّل أي مبلغ من العميل.',
            ),
            Icons.verified_outlined,
            maxLines: 2,
          ),
        _InfoItem(
          _copy(context, 'Delivery Cost', 'تكلفة التوصيل'),
          _moneyLabel(context, shipment?.deliveryCost ?? 0),
          Icons.local_atm_outlined,
        ),
        if (feeDue > 0) ...[
          _InfoItem(
            _copy(context, 'Delivery fee due', 'أجرة التوصيل المستحقة'),
            _moneyLabel(context, feeDue),
            Icons.request_quote_outlined,
          ),
          _InfoItem(
            _copy(context, 'Fee collected', 'المحصّل من الأجرة'),
            _moneyLabel(context, financial?.feeCollected ?? 0),
            Icons.task_alt_rounded,
          ),
        ],
        if ((financial?.feeRemaining ?? 0) > 0)
          _InfoItem(
            _copy(context, 'Fee remaining', 'المتبقي من الأجرة'),
            _moneyLabel(context, financial!.feeRemaining!),
            Icons.hourglass_bottom_rounded,
          ),
        if ((financial?.driverCashToRemit ?? 0) > 0)
          _InfoItem(
            _copy(context, 'Cash to hand over', 'النقد الواجب تسليمه'),
            _moneyLabel(context, financial!.driverCashToRemit!),
            Icons.account_balance_wallet_outlined,
          ),
        if ((financial?.driverCommission ?? 0) > 0)
          _InfoItem(
            _copy(context, 'Your commission', 'عمولتك'),
            _moneyLabel(context, financial!.driverCommission!),
            Icons.savings_outlined,
          ),
      ],
    );
  }
}

class _NotesCard extends StatelessWidget {
  const _NotesCard({required this.note});

  final String note;

  @override
  Widget build(BuildContext context) {
    final value =
        note.trim().isEmpty
            ? _copy(context, 'Not available', 'غير متوفر')
            : note.trim();
    return _InfoCard(
      title: _copy(context, 'Notes', 'الملاحظات'),
      icon: Icons.notes_rounded,
      rows: [
        _InfoItem(
          _copy(context, 'Note', 'ملاحظة'),
          value,
          Icons.sticky_note_2_outlined,
          maxLines: 4,
        ),
      ],
    );
  }
}

class _DriverActionReasonCard extends StatelessWidget {
  const _DriverActionReasonCard({required this.shipment});

  final Shipment shipment;

  @override
  Widget build(BuildContext context) {
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    final reasonTitle = shipment.actionReasonTitle(isArabic).trim();
    final reasonDescription = shipment.actionReasonDescription(isArabic).trim();
    final reasonNote = shipment.actionReasonNote.trim();
    final createdAt = shipment.actionReasonCreatedAt.trim();

    if (reasonTitle.isEmpty && reasonNote.isEmpty) {
      return _InfoCard(
        title: isArabic ? 'إجراء السائق' : 'Driver action',
        icon: Icons.gpp_maybe_outlined,
        rows: [
          _InfoItem(
            isArabic ? 'سبب الإجراء' : 'Action reason',
            isArabic
                ? 'لم يتم تسجيل إجراء من السائق بعد.'
                : 'No driver action has been recorded yet.',
            Icons.info_outline_rounded,
            maxLines: 3,
          ),
        ],
      );
    }

    final rows = <_InfoItem>[
      _InfoItem(
        isArabic ? 'سبب الإجراء' : 'Action reason',
        reasonTitle.isEmpty
            ? (isArabic ? 'غير متوفر' : 'Not available')
            : reasonTitle,
        Icons.rule_folder_outlined,
        maxLines: 3,
      ),
    ];

    if (reasonDescription.isNotEmpty) {
      rows.add(
        _InfoItem(
          isArabic ? 'الوصف' : 'Description',
          reasonDescription,
          Icons.short_text_rounded,
          maxLines: 4,
        ),
      );
    }

    if (reasonNote.isNotEmpty) {
      rows.add(
        _InfoItem(
          isArabic ? 'ملاحظة السائق' : 'Driver note',
          reasonNote,
          Icons.sticky_note_2_outlined,
          maxLines: 4,
        ),
      );
    }

    if (createdAt.isNotEmpty) {
      rows.add(
        _InfoItem(
          isArabic ? 'وقت التسجيل' : 'Logged at',
          // Formatted, never the raw ISO string the optimistic local update
          // writes with toIso8601String().
          _detailsDateLabel(context, createdAt),

          Icons.schedule_rounded,
          maxLines: 2,
        ),
      );
    }

    return _InfoCard(
      title: isArabic ? 'إجراء السائق' : 'Driver action',
      icon: Icons.gpp_maybe_outlined,
      rows: rows,
    );
  }
}

/// The driver's next step first, then tracking, the off-ramps and chat.
///
/// Every step comes from [actions] (driverShipmentActionsFor), so a scheduled
/// shipment is offered arrival and pickup exactly like an instant one, and
/// Delivered appears as soon as the shipment is in transit. The stage is only
/// consulted for the two states with nothing to do: an offer not yet accepted
/// and a closed shipment.
class _ActionsCard extends StatelessWidget {
  const _ActionsCard({
    required this.stage,
    required this.actions,
    required this.isBusy,
    required this.busyAction,
    required this.onStep,
    required this.onTrack,
    required this.onUpdateStatus,
    required this.statusSheetMode,
    required this.chatAction,
  });

  final _DetailsStage stage;
  final DriverShipmentActions actions;
  final bool isBusy;
  final String? busyAction;
  final ValueChanged<DriverShipmentStep>? onStep;
  final VoidCallback onTrack;
  final VoidCallback onUpdateStatus;
  final DriverStatusSheetMode statusSheetMode;

  /// Hidden by the widget itself when this shipment has no chat to open.
  final Widget? chatAction;

  static String _busyKey(DriverShipmentStep step) => switch (step) {
    DriverShipmentStep.arriveAtStore => 'arrived',
    DriverShipmentStep.pickUp => 'pickup',
    DriverShipmentStep.deliver => 'deliver',
  };

  Widget _stepButton(
    BuildContext context,
    DriverShipmentStep step, {
    bool isOutlined = false,
  }) {
    return _PrimaryAction(
      key: driverStepKey(step),
      label: driverStepLabel(context, step),
      icon: driverStepIcon(step),
      isLoading: busyAction == _busyKey(step),
      isOutlined: isOutlined,
      color:
          step == DriverShipmentStep.deliver ? const Color(0xff16A06D) : null,
      onTap: isBusy || onStep == null ? null : () => onStep!(step),
    );
  }

  @override
  Widget build(BuildContext context) {
    final buttons = <Widget>[];
    final isOpen =
        stage != _DetailsStage.beforeAccept &&
        stage != _DetailsStage.finalStatus;
    final hint = isOpen ? driverNextStepHint(context, actions) : null;
    final primary = actions.primary;

    if (isOpen) {
      final secondary = actions.secondary;
      if (primary != null) buttons.add(_stepButton(context, primary));
      if (secondary != null) {
        buttons.add(_stepButton(context, secondary, isOutlined: true));
      }
      buttons.add(
        _PrimaryAction(
          label: _copy(context, 'Track Shipment', 'تتبع الشحنة'),
          icon: Icons.near_me_outlined,
          isOutlined: true,
          onTap: isBusy ? null : onTrack,
        ),
      );
    }
    if (statusSheetMode != DriverStatusSheetMode.unavailable) {
      buttons.add(
        _PrimaryAction(
          key: const ValueKey('update_status_action'),
          label: _copy(context, 'Update Status', 'تحديث الحالة'),
          icon: Icons.edit_note_rounded,
          isOutlined: primary != null,
          isLoading: busyAction == 'status',
          onTap: isBusy ? null : onUpdateStatus,
        ),
      );
    }

    if (chatAction != null) {
      buttons.add(chatAction!);
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _copy(context, 'Actions', 'الإجراءات'),
            style: const TextStyle(
              color: Color(0xff0F172A),
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          if (hint != null) ...[
            _NextStepHint(text: hint, isBlocked: actions.primary == null),
            const SizedBox(height: 12),
          ],
          if (buttons.isEmpty)
            Text(
              _copy(
                context,
                'No actions are available for this stage.',
                'لا توجد إجراءات متاحة لهذه المرحلة.',
              ),
              style: const TextStyle(
                color: Color(0xff64748B),
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            )
          else
            ...buttons.map(
              (action) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: action,
              ),
            ),
        ],
      ),
    );
  }
}

/// What comes next, or why nothing does, above the action buttons.
class _NextStepHint extends StatelessWidget {
  const _NextStepHint({required this.text, required this.isBlocked});

  final String text;
  final bool isBlocked;

  @override
  Widget build(BuildContext context) {
    final color = isBlocked ? const Color(0xffB45309) : AppColors.primary;
    return Container(
      key: const ValueKey('next_step_hint'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isBlocked ? Icons.info_outline_rounded : Icons.flag_outlined,
            size: 18,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: color,
                fontSize: 12.5,
                height: 1.35,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SmallAction extends StatelessWidget {
  const _SmallAction({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 17),
      label: Text(
        label,
        style: TextStyle(
          fontFamily: AppFonts.currentFontFamily,
          fontWeight: FontWeight.w700,
        ),
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primary,
        side: BorderSide(color: AppColors.primary.withValues(alpha: 0.22)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}

class _PrimaryAction extends StatelessWidget {
  const _PrimaryAction({
    super.key,
    required this.label,
    required this.icon,
    this.onTap,
    this.isLoading = false,
    this.isOutlined = false,
    this.color,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool isLoading;
  final bool isOutlined;

  /// Fill colour of a solid action; the app primary when null.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final fill = color ?? AppColors.primary;
    return SizedBox(
      height: 50,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon:
            isLoading
                ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2.2,
                  ),
                )
                : Icon(icon, size: 19),
        label: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: AppFonts.currentFontFamily,
            fontWeight: FontWeight.w800,
            fontSize: 14,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: isOutlined ? Colors.white : fill,
          foregroundColor: isOutlined ? AppColors.primary : Colors.white,
          disabledBackgroundColor: fill.withValues(alpha: 0.65),
          disabledForegroundColor: Colors.white,
          elevation: 0,
          side: BorderSide(
            color:
                isOutlined
                    ? AppColors.primary.withValues(alpha: 0.22)
                    : Colors.transparent,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }
}

class _PrivacyNotice extends StatelessWidget {
  const _PrivacyNotice({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xffEFF6FF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xffBFDBFE)),
      ),
      child: Row(
        children: [
          Icon(Icons.privacy_tip_outlined, color: AppColors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xff0F172A),
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  message,
                  style: const TextStyle(
                    color: Color(0xff475569),
                    fontSize: 12,
                    height: 1.35,
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

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 190),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.22)),
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

BoxDecoration _cardDecoration() {
  return BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(20),
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

/// Currency first in English, amount first in Arabic, two decimals always —
/// the same presentation as both shipment lists. The value is untouched.
String _moneyLabel(BuildContext context, double value) {
  final amount = value.toStringAsFixed(2);
  return _copy(context, 'JOD $amount', '$amount دينار أردني');
}

bool _looksLikeImagePath(String value) {
  final lower = value.trim().toLowerCase();
  return lower.contains('/store-logo/') ||
      lower.endsWith('.png') ||
      lower.endsWith('.jpg') ||
      lower.endsWith('.jpeg') ||
      lower.endsWith('.webp') ||
      lower.endsWith('.gif') ||
      lower.endsWith('.svg');
}
