import 'package:blockatie/services/driver_action_service.dart';
import 'dart:async';

import 'package:blockatie/constants/colors.dart';
import 'package:blockatie/constants/fonts.dart';
import 'package:blockatie/models/order_status_modle.dart';
import 'package:blockatie/models/shipment.dart';
import 'package:blockatie/provider/home.dart';
import 'package:blockatie/provider/order_location.dart';
import 'package:blockatie/provider/shipment.dart';
import 'package:blockatie/provider/shipment_instsnt.dart';
import 'package:blockatie/services/user_session_state.dart';
import 'package:blockatie/utils/driver_shipment_actions.dart';
import 'package:blockatie/utils/external_action.dart';
import 'package:blockatie/utils/location_failure.dart';
import 'package:blockatie/utils/nav.dart';
import 'package:blockatie/utils/text_direction.dart';
import 'package:blockatie/utils/time/jordan_time.dart';
import 'package:blockatie/views/pages/hub/support&assistance/support_assistence.dart';
import 'package:blockatie/views/widgets/driver_chat_bubble.dart';
import 'package:blockatie/views/widgets/status_update_sheet.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart'
    as ph
    show openAppSettings;
import 'package:provider/provider.dart';

enum _TrackingStage {
  scheduled,
  beforeAccept,
  storePickup,
  arrivedAtStore,
  delivery,
  finalSummary,
}

enum _TrackingDestinationKind { none, store, customer }

const Set<int> _finalStatusIds = {6, 7, 8, 11};

class LocationOrderPage extends StatefulWidget {
  const LocationOrderPage({
    super.key,
    required this.shipmentId,
    required this.phoneCustomer,
    this.locationDriver,
    this.storeLocation,
    this.shipment,
    this.isInstantFlow = false,
    this.policyNumber,
    this.shipmentTypeLabel,
    this.statusLabel,
    this.stageLabel,
    this.storeName,
    this.storePhone,
    this.storeAddress,
    this.customerName,
    this.customerAddress,
  });

  final int shipmentId;
  final String phoneCustomer;

  // Kept for older callers. In this screen it is treated as the destination
  // location, not the driver's live location.
  final LatLng? locationDriver;
  final LatLng? storeLocation;
  final Shipment? shipment;
  final bool isInstantFlow;
  final String? policyNumber;
  final String? shipmentTypeLabel;
  final String? statusLabel;
  final String? stageLabel;
  final String? storeName;
  final String? storePhone;
  final String? storeAddress;
  final String? customerName;
  final String? customerAddress;

  @override
  State<LocationOrderPage> createState() => _LocationOrderPageState();
}

class _LocationOrderPageState extends State<LocationOrderPage> {
  final Completer<GoogleMapController> _controller = Completer();
  int? _statusOverride;
  String? _busyAction;

  /// Set when a step was refused because the shipment is no longer this
  /// driver's and the re-read no longer finds it; no step is offered after.
  Shipment? _authoritativeShipment;
  Shipment? get _actionShipment => _authoritativeShipment ?? widget.shipment;
  Future<void> _refreshActionSnapshot() async {
    if (!mounted || !_sessionIsCurrent) return;
    final fresh = await DriverActionService.read(
      context,
    ).fetch(widget.shipmentId);
    if (!mounted || !_sessionIsCurrent) return;
    setState(() {
      _authoritativeShipment =
          fresh ??
          _actionShipment?.copyWith(
            shipmentStatusId: _statusId(_actionShipment!),
          );
      _statusOverride = null;
    });

    // A notification/deep link can open this screen before its authoritative
    // shipment snapshot arrives. Re-evaluate the destination so it never
    // keeps a stale customer route during the store-pickup phase.
    if (fresh != null) {
      unawaited(_prepareTracking());
    }
  }

  bool _lostAssignment = false;

  /// The session every field on this screen belongs to.
  ///
  /// The shipment, the recipient's phone and the store address arrive through
  /// the constructor and cannot be erased from an immutable Widget, so this
  /// stamp is what decides whether they may still be rendered or acted on.
  final int _generation = UserSessionState.generation;

  /// Set once the session moves on. Everything the previous driver could read
  /// or press is gated on this.
  bool _sessionEnded = false;

  /// Captured in [didChangeDependencies] so [dispose] never reads a
  /// BuildContext: the tracking session this page starts has to be stopped
  /// from there, after the element is already defunct.
  OrderLocationProvider? _locationProvider;

  bool get _sessionIsCurrent =>
      !_sessionEnded && UserSessionState.isCurrent(_generation);

  @override
  void initState() {
    super.initState();
    UserSessionState.changes.addListener(_onSessionChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_prepareTracking());
      unawaited(_refreshActionSnapshot());
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _locationProvider = context.read<OrderLocationProvider>();
  }

  /// A logout, an account switch or a disabled account ends this screen.
  ///
  /// The provider clears its own coordinates, but the recipient's name, phone
  /// and address live in the Widget — so without this the next driver would
  /// still be looking at them, and the Call button would still dial them.
  void _onSessionChanged() {
    if (!mounted || UserSessionState.isCurrent(_generation)) return;
    _locationProvider?.stopDriverLocationUpdates(notify: false);
    setState(() {
      _sessionEnded = true;
      _statusOverride = null;
      _busyAction = null;
    });
    if (Navigator.of(context).canPop()) Nav.back();
  }

  @override
  void dispose() {
    UserSessionState.changes.removeListener(_onSessionChanged);
    // This page started the 30-second GPS + network loop, so it owns ending
    // it. Previously the timer ran for the rest of the session once the driver
    // had left the screen.
    _locationProvider?.stopDriverLocationUpdates(notify: false);
    super.dispose();
  }

  Future<void> _prepareTracking() async {
    if (!_sessionIsCurrent) return;
    final provider = context.read<OrderLocationProvider>();
    final destinationKind = getPrimaryDestination(_actionShipment);
    final destinationLocation = _primaryDestinationLocation(destinationKind);
    final destinationAddress = _primaryDestinationAddress(destinationKind);

    if (destinationKind == _TrackingDestinationKind.none) {
      await provider.startRouteTracking(
        destinationTitleValue: _copy(
          context,
          'Destination unavailable',
          'الوجهة غير متوفرة',
        ),
      );
    } else if (destinationLocation != null || destinationAddress.isNotEmpty) {
      await provider.startRouteTracking(
        destination: destinationLocation,
        destinationAddressValue: destinationAddress,
        destinationTitleValue: _destinationTitle(context, destinationKind),
      );
      await provider.loadDriverLocationFallback(widget.shipmentId);
    } else {
      await provider.getShipmentCords(widget.shipmentId);
    }

    if (!mounted) return;
    await provider.startDriverLocationUpdates(context: context);
    if (!mounted) return;
    await _fitMarkersInView();
  }

  Future<void> _fitMarkersInView() async {
    if (!_controller.isCompleted || !mounted) return;

    final provider = context.read<OrderLocationProvider>();
    final driver = provider.driverLocation;
    final destination = provider.destinationLocation;
    final controller = await _controller.future;
    if (!mounted) return;

    if (driver == null && destination == null) return;
    if (driver == null || destination == null) {
      final target = driver ?? destination!;
      await controller.animateCamera(CameraUpdate.newLatLngZoom(target, 15));
      return;
    }

    final minLat =
        driver.latitude < destination.latitude
            ? driver.latitude
            : destination.latitude;
    final maxLat =
        driver.latitude > destination.latitude
            ? driver.latitude
            : destination.latitude;
    final minLng =
        driver.longitude < destination.longitude
            ? driver.longitude
            : destination.longitude;
    final maxLng =
        driver.longitude > destination.longitude
            ? driver.longitude
            : destination.longitude;

    await controller.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat - 0.008, minLng - 0.008),
          northeast: LatLng(maxLat + 0.008, maxLng + 0.008),
        ),
        76,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final stage = _stageFor(_actionShipment);

    return Scaffold(
      backgroundColor: const Color(0xffF4F7FB),
      appBar: _TrackingTopBar(
        title: _copy(context, 'Shipment Tracking', 'تتبع الشحنة'),
        subtitle: getTrackingSubtitle(context, _actionShipment),
        onHelp: () => Nav.to(const SupportAssistencePage()),
      ),
      body: Consumer<OrderLocationProvider>(
        builder: (context, provider, _) {
          if (provider.isLoading) {
            return const _TrackingLoadingState();
          }

          final banner = getTrackingBannerState(context, provider);

          return RefreshIndicator(
            color: AppColors.primary,
            onRefresh: _prepareTracking,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              slivers: [
                SliverPadding(
                  // Read from the launcher rather than guessed: 150 + 30
                  // happened to clear today's bubble by four pixels.
                  padding: EdgeInsets.fromLTRB(
                    16,
                    16,
                    16,
                    DriverChatBubble.reservedBottomSpace + 16,
                  ),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      _TrackingMapCard(
                        provider: provider,
                        initialPosition: _initialCameraPosition(provider),
                        banner: banner,
                        onMapCreated: (controller) {
                          if (!_controller.isCompleted) {
                            _controller.complete(controller);
                          }
                          Future.delayed(
                            const Duration(milliseconds: 350),
                            _fitMarkersInView,
                          );
                        },
                        onRecenter: _fitMarkersInView,
                        onOpenMaps: () => _openExternalMap(provider),
                      ),
                      const SizedBox(height: 14),
                      _RouteSummaryCard(
                        policyNumber: _policyNumber,
                        primaryLabel: _directionLabel(context),
                        primarySubtitle: getTrackingSubtitle(
                          context,
                          _actionShipment,
                        ),
                        primaryIcon:
                            getPrimaryDestination(_actionShipment) ==
                                    _TrackingDestinationKind.store
                                ? Icons.storefront_rounded
                                : Icons.near_me_rounded,
                        primaryColor: _stageColor(stage),
                        items: [
                          _SummaryItem(
                            label: _copy(
                              context,
                              'Shipment type',
                              'نوع الشحنة',
                            ),
                            value: _shipmentTypeLabel(context),
                            icon: Icons.category_outlined,
                            color: AppColors.primary,
                          ),
                          _SummaryItem(
                            label: _copy(
                              context,
                              'Shipment status',
                              'حالة الشحنة',
                            ),
                            value: _statusLabel(context),
                            icon: Icons.fact_check_outlined,
                            color: _stageColor(stage),
                          ),
                          _SummaryItem(
                            label: _copy(
                              context,
                              'Current stage',
                              'المرحلة الحالية',
                            ),
                            value: _stageLabel(context, stage),
                            icon: Icons.timeline_outlined,
                            color: AppColors.primary,
                          ),
                          _SummaryItem(
                            label: _copy(
                              context,
                              'Current distance',
                              'المسافة الحالية',
                            ),
                            value: _distanceLabel(context, provider),
                            icon: Icons.social_distance_outlined,
                            color: const Color(0xff7C3AED),
                          ),
                          _SummaryItem(
                            label: _copy(
                              context,
                              'Current direction',
                              'الاتجاه الحالي',
                            ),
                            value: _directionLabel(context),
                            icon: Icons.near_me_outlined,
                            color: const Color(0xff0EA5E9),
                          ),
                          _SummaryItem(
                            label: _copy(
                              context,
                              'Location status',
                              'حالة الموقع',
                            ),
                            value: _compactLocationStatus(context, provider),
                            icon: Icons.my_location_outlined,
                            color: _trackingStatusColor(
                              provider.trackingStatus,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _LocationInfoCard(
                        title: _copy(context, 'Driver Location', 'موقع السائق'),
                        subtitle:
                            provider.driverAddress.trim().isEmpty
                                ? _copy(
                                  context,
                                  'Waiting for live location update',
                                  'بانتظار تحديث الموقع الحي',
                                )
                                : provider.driverAddress,
                        trailing: _lastUpdateLabel(context, provider),
                        icon: Icons.person_pin_circle_outlined,
                        color: AppColors.primary,
                      ),
                      const SizedBox(height: 12),
                      _LocationInfoCard(
                        title: _destinationTitle(
                          context,
                          getPrimaryDestination(_actionShipment),
                        ),
                        subtitle: _destinationSubtitle(context, provider),
                        trailing: _destinationName(context),
                        icon:
                            getPrimaryDestination(_actionShipment) ==
                                    _TrackingDestinationKind.store
                                ? Icons.storefront_outlined
                                : Icons.flag_outlined,
                        color:
                            getPrimaryDestination(_actionShipment) ==
                                    _TrackingDestinationKind.store
                                ? const Color(0xffF59E0B)
                                : const Color(0xff16A06D),
                      ),
                      const SizedBox(height: 14),
                      _ActionPanel(
                        primaryStep: _stepButton(
                          context,
                          _driverActions.primary,
                        ),
                        secondaryStep: _stepButton(
                          context,
                          _driverActions.secondary,
                          isOutlined: true,
                        ),
                        nextStepHint: driverNextStepHint(
                          context,
                          _driverActions,
                        ),
                        statusActionLabel: _copy(
                          context,
                          'Update Status',
                          'تحديث الحالة',
                        ),
                        isStatusActionLoading: _busyAction == 'status',
                        onStatusAction:
                            _canUpdateShipmentStatus()
                                ? _showUpdateStatusSheet
                                : null,
                        canCall: _phoneForCurrentStage().isNotEmpty,
                        callLabel:
                            getPrimaryDestination(_actionShipment) ==
                                    _TrackingDestinationKind.store
                                ? _copy(context, 'Call Store', 'اتصال بالمتجر')
                                : _copy(
                                  context,
                                  'Call Recipient',
                                  'اتصال بالمستلم',
                                ),
                        onCall: () => _call(_phoneForCurrentStage()),
                        onOpenMaps: () => _openExternalMap(provider),
                        onRecenter: _fitMarkersInView,
                        onSupport: () => Nav.to(const SupportAssistencePage()),
                      ),
                    ]),
                  ),
                ),
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: MediaQuery.of(context).padding.bottom + 30,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  bool isInstantShipment(Shipment? shipment) {
    return widget.isInstantFlow ||
        shipment?.deliveryTypeId == 1 ||
        shipment?.driverId == 0 ||
        widget.storeLocation != null ||
        widget.locationDriver != null;
  }

  bool isBeforePickup(Shipment? shipment) {
    return shipment != null && driverShipmentIsPrePickup(shipment);
  }

  bool isAfterPickup(Shipment? shipment) {
    return shipment != null &&
        shipment.driverId > 0 &&
        !_isFinalStatus(shipment) &&
        !driverShipmentIsPrePickup(shipment);
  }

  /// The driver's next steps, from the status and the assignment — the same
  /// resolver the details screen uses. This screen used to offer only arrival
  /// and pickup, and only on the instant stages, so a shipment in transit had
  /// no Delivered button here at all: the active instant card leads here.
  DriverShipmentActions get _driverActions {
    final shipment = _actionShipment;
    if (shipment == null || !_sessionIsCurrent) {
      return const DriverShipmentActions(block: DriverStepBlock.notAccepted);
    }
    if (_lostAssignment && !_isFinalStatus(shipment)) {
      return const DriverShipmentActions(block: DriverStepBlock.reassigned);
    }
    return driverShipmentActionsFor(
      statusId: _statusId(shipment),
      driverId: shipment.driverId,
      shipment: shipment,
    );
  }

  static String _busyKey(DriverShipmentStep step) => switch (step) {
    DriverShipmentStep.arriveAtStore => 'arrived',
    DriverShipmentStep.pickUp => 'pickup',
    DriverShipmentStep.deliver => 'deliver',
  };

  _StepButtonData? _stepButton(
    BuildContext context,
    DriverShipmentStep? step, {
    bool isOutlined = false,
  }) {
    if (step == null) return null;
    final canAct =
        _busyAction == null && _actionShipment != null && _sessionIsCurrent;
    return _StepButtonData(
      key: driverStepKey(step),
      label: driverStepLabel(context, step),
      icon: driverStepIcon(step),
      isLoading: _busyAction == _busyKey(step),
      isOutlined: isOutlined,
      isDeliver: step == DriverShipmentStep.deliver,
      onTap:
          canAct
              ? switch (step) {
                DriverShipmentStep.arriveAtStore => _markArrivedAtStore,
                DriverShipmentStep.pickUp => _pickupShipmentFromStore,
                DriverShipmentStep.deliver => _deliverShipment,
              }
              : null,
    );
  }

  /// Cancelled / Returned / Failed Delivery, from any open status the driver
  /// holds — what update_shipment_status.php accepts.
  bool _canUpdateShipmentStatus() {
    final shipment = _actionShipment;
    if (shipment == null || _busyAction != null || !_sessionIsCurrent) {
      return false;
    }
    return driverStatusSheetModeForShipment(shipment) !=
        DriverStatusSheetMode.unavailable;
  }

  /// Re-reads both lists after a refused step and adopts the server's status
  /// for this shipment, so the screen stops offering a step that no longer
  /// applies. When [refusal] says the shipment is no longer this driver's
  /// and the lists no longer hold it, every step is withdrawn.
  Future<void> _reloadStatusFromLists(ShipmentActionResult refusal) async {
    await _refreshActionSnapshot();
    final assigned = context.read<ShipmentProvider>();
    final instant = context.read<ShipmentInstantprovider>();
    await Future.wait([
      assigned.getAllShipments(force: true),
      instant.getShipmentsInstant(force: true),
    ]);
    if (!mounted || !_sessionIsCurrent) return;
    final rows = <Shipment>[
      ...assigned.paginatedShipments,
      ...instant.allShipments,
    ];
    for (final row in rows) {
      if (row.id == widget.shipmentId) {
        setState(() => _statusOverride = driverStatusIdOf(row));
        return;
      }
    }
    if (driverStepRefusalLostShipment(refusal)) {
      setState(() => _lostAssignment = true);
    }
  }

  Future<void> _markArrivedAtStore() async {
    if (_busyAction != null) return;
    await _refreshActionSnapshot();
    if (!mounted ||
        !_sessionIsCurrent ||
        _actionShipment?.allowsAction('arrive_at_pickup') != true)
      return;
    final shipment = _actionShipment;
    if (shipment == null || _busyAction != null || !_sessionIsCurrent) return;

    setState(() => _busyAction = 'arrived');
    final result = await context
        .read<ShipmentInstantprovider>()
        .markArrivedAtStore(
          shipment.id,
          // Request language, not UI copy: the server localizes its own reply.
          languageCode: Localizations.localeOf(context).languageCode,
        );

    // A result that lands after the session moved on belongs to the previous
    // driver and must not reach this screen.
    if (!mounted || !_sessionIsCurrent) return;
    _showSnack(
      _actionMessage(
        result,
        successEn: 'Arrival confirmed.',
        successAr: 'تم تأكيد الوصول.',
        failureEn: 'Unable to confirm arrival.',
        failureAr: 'تعذر تأكيد الوصول.',
      ),
      isError: !result.success,
    );
    setState(() {
      if (result.success) {
        _statusOverride = 10;
      }
      _busyAction = null;
    });

    if (result.success) {
      unawaited(_prepareTracking());
      unawaited(_refreshActionSnapshot());
    } else {
      await _reloadStatusFromLists(result);
    }
  }

  /// Picked up from the store (2 or 10 -> 4). From 2 it skips the geofenced
  /// arrival, which the server allows, so the driver is asked first.
  Future<void> _pickupShipmentFromStore() async {
    if (_busyAction != null) return;
    await _refreshActionSnapshot();
    if (!mounted ||
        !_sessionIsCurrent ||
        _actionShipment?.allowsAction('confirm_pickup') != true)
      return;
    final shipment = _actionShipment;
    if (shipment == null || _busyAction != null || !_sessionIsCurrent) return;
    if (_statusId(shipment) != 10) {
      final confirmed = await confirmDirectPickup(
        context,
        policyNumber: _policyNumber,
      );
      if (!confirmed || !mounted || _busyAction != null || !_sessionIsCurrent) {
        return;
      }
    }

    setState(() => _busyAction = 'pickup');
    final result = await context
        .read<ShipmentInstantprovider>()
        .pickupShipmentFromStore(
          shipment.id,
          languageCode: Localizations.localeOf(context).languageCode,
        );

    if (!mounted || !_sessionIsCurrent) return;
    _showSnack(
      _actionMessage(
        result,
        successEn: 'Shipment picked up successfully.',
        successAr: 'تم استلام الشحنة بنجاح.',
        failureEn: 'Unable to pickup shipment from store.',
        failureAr: 'تعذر استلام الشحنة من المتجر.',
      ),
      isError: !result.success,
    );
    setState(() {
      if (result.success) {
        _statusOverride = 4;
      }
      _busyAction = null;
    });

    if (result.success) {
      unawaited(_prepareTracking());
      unawaited(_refreshActionSnapshot());
    } else {
      await _reloadStatusFromLists(result);
    }
  }

  /// Delivered (4 -> 11), asked first. Shown as delivered only once the
  /// server says so; a refusal or a missing reply re-reads the lists instead
  /// (a manual retry reuses the request id, see
  /// ShipmentInstantprovider.deliverShipment).
  Future<void> _deliverShipment() async {
    if (_busyAction != null) return;
    await _refreshActionSnapshot();
    if (!mounted ||
        !_sessionIsCurrent ||
        _actionShipment?.allowsAction('complete_delivery') != true)
      return;
    final shipment = _actionShipment;
    if (shipment == null || _busyAction != null || !_sessionIsCurrent) return;
    final confirmed = await confirmDriverDelivery(
      context,
      policyNumber: _policyNumber,
      amountToCollect: shipment.productToCollect,
    );
    if (!confirmed || !mounted || _busyAction != null || !_sessionIsCurrent) {
      return;
    }
    if (!canMarkDelivered(_statusId(shipment))) return;

    setState(() => _busyAction = 'deliver');
    final result = await context
        .read<ShipmentInstantprovider>()
        .deliverShipment(
          shipment.id,
          languageCode:
              Localizations.localeOf(context).languageCode == 'ar'
                  ? 'ar'
                  : 'en',
        );
    if (!mounted || !_sessionIsCurrent) return;

    if (result.success) {
      _showSnack(
        _actionMessage(
          result,
          successEn: 'Shipment has been marked as delivered successfully.',
          successAr: 'تم تعليم الشحنة كمسلّمة بنجاح.',
          failureEn: '',
          failureAr: '',
        ),
        isError: false,
      );
      setState(() {
        _statusOverride = driverDeliveredStatusId;
        _busyAction = null;
      });
      unawaited(
        context.read<HomeProvider>().getDriverStatistics(context, force: true),
      );
      unawaited(context.read<ShipmentProvider>().getAllShipments(force: true));
      await _refreshActionSnapshot();
      return;
    }

    if (result.code != 'SESSION_CHANGED') {
      _showSnack(
        _actionMessage(
          result,
          successEn: '',
          successAr: '',
          failureEn: 'Unable to mark the shipment as delivered.',
          failureAr: 'تعذر تأكيد تسليم الشحنة.',
        ),
      );
    }
    setState(() => _busyAction = null);
    if (!result.success) {
      await _reloadStatusFromLists(result);
    }
  }

  /// What the driver reads after an action.
  ///
  /// The server's own sentence when it sent one — it arrives already in the
  /// requested language — and this screen's wording otherwise. A success with
  /// no `message_en`/`message_ar` used to produce a blank green bar.
  String _actionMessage(
    ShipmentActionResult result, {
    required String successEn,
    required String successAr,
    required String failureEn,
    required String failureAr,
  }) {
    final serverMessage = result.message.trim();
    if (serverMessage.isNotEmpty) return serverMessage;
    return result.success
        ? _copy(context, successEn, successAr)
        : _copy(context, failureEn, failureAr);
  }

  Future<void> _showUpdateStatusSheet() async {
    final shipment = _actionShipment;
    if (shipment == null ||
        _busyAction != null ||
        !_sessionIsCurrent ||
        driverStatusSheetModeForShipment(shipment) ==
            DriverStatusSheetMode.unavailable) {
      return;
    }

    final homeProvider = context.read<HomeProvider>();
    if (homeProvider.orderStatusData == null && !homeProvider.isStatusLoading) {
      await homeProvider.getOrderStatus();
    }
    if (!mounted) return;

    // Filtered through the same set the sheet itself enforces. Filtering on a
    // different set meant a server that returned only 6 and 11 opened a sheet
    // the driver could see no options in.
    final currentStatusId = _statusId(shipment);
    final List<Status> statuses =
        homeProvider.orderStatusData?.status.where((status) {
          final statusId = int.tryParse(status.id);
          return statusId != null &&
              driverSelectableStatusIds.contains(statusId) &&
              statusId != currentStatusId;
        }).toList() ??
        <Status>[];

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) {
        return ShipmentStatusUpdateSheet(
          shipmentId: widget.shipmentId,
          statuses: statuses,
          currentStatusId: _statusId(shipment),
          currentStatusLabel: _statusLabel(context),
          currentStageLabel: _stageLabel(context, _stageFor(shipment)),
          policyNumber: _policyNumber,
          doorFeeCollectable: shipment.financial?.doorFeeCollectable ?? 0,
          onSubmit: (status, reason) async {
            if (!mounted) return false;
            setState(() => _busyAction = 'status');

            final success = await homeProvider.updateStatus(
              shipmentId: widget.shipmentId,
              statusId: status.id,
              reasonId: reason?.reasonId,
              reasonNote: reason?.note,
              feeCollectedAmount: reason?.feeCollectedAmount,
              isInstant: isInstantShipment(shipment),
              showSuccessDialog: false,
            );

            if (!mounted) return false;
            if (success) {
              _statusOverride = int.tryParse(status.id) ?? _statusOverride;
              unawaited(
                context.read<ShipmentProvider>().getAllShipments(force: true),
              );
              unawaited(
                // Refetches whichever page the driver is on; the pinned instant
                // job comes back from the server either way.
                context.read<ShipmentInstantprovider>().getShipmentsInstant(
                  force: true,
                ),
              );
              _showSnack(
                _copy(
                  context,
                  'Shipment status updated.',
                  'تم تحديث حالة الشحنة.',
                ),
                isError: false,
              );
            }

            setState(() => _busyAction = null);
            return success;
          },
        );
      },
    );
    if (mounted) await _refreshActionSnapshot();
  }

  String getTrackingSubtitle(BuildContext context, Shipment? shipment) {
    final stage = _stageFor(shipment);
    return switch (stage) {
      _TrackingStage.scheduled => _copy(
        context,
        'Current route and delivery destination',
        'المسار الحالي ووجهة التسليم',
      ),
      _TrackingStage.beforeAccept => _copy(
        context,
        'Accept the shipment before opening private route details',
        'اقبل الشحنة قبل عرض تفاصيل المسار الخاصة',
      ),
      _TrackingStage.storePickup => _copy(
        context,
        'Your current route to the store',
        'توجهك الحالي نحو المتجر',
      ),
      _TrackingStage.arrivedAtStore => _copy(
        context,
        'Store reached, pickup is the next step',
        'تم الوصول إلى المتجر، الاستلام هو الخطوة التالية',
      ),
      _TrackingStage.delivery => _copy(
        context,
        'Follow the road to the customer',
        'متابعة الطريق نحو العميل',
      ),
      _TrackingStage.finalSummary => _copy(
        context,
        'Read-only shipment route summary',
        'ملخص قراءة لمسار الشحنة',
      ),
    };
  }

  _TrackingDestinationKind getPrimaryDestination(Shipment? shipment) {
    final stage = _stageFor(shipment);
    if (stage == _TrackingStage.beforeAccept ||
        stage == _TrackingStage.scheduled ||
        stage == _TrackingStage.finalSummary) {
      return _TrackingDestinationKind.none;
    }
    if (isBeforePickup(shipment)) {
      return _TrackingDestinationKind.store;
    }
    return _TrackingDestinationKind.customer;
  }

  String getLocationStatusText(
    BuildContext context,
    OrderLocationProvider provider,
  ) {
    return switch (provider.trackingStatus) {
      DriverLocationTrackingStatus.active => _copy(
        context,
        'Location is active and updating safely.',
        'الموقع مفعل ويتم تحديثه بأمان.',
      ),
      DriverLocationTrackingStatus.disabled => _copy(
        context,
        'Please enable GPS to keep delivery tracking accurate.',
        'يرجى تفعيل GPS للحفاظ على دقة تتبع التوصيل.',
      ),
      DriverLocationTrackingStatus.permissionRequired => _copy(
        context,
        'Please allow location permission for tracking.',
        'يرجى السماح بصلاحية الموقع للتتبع.',
      ),
      DriverLocationTrackingStatus.permissionPermanentlyDenied => _copy(
        context,
        'Open app settings and allow location permission.',
        'افتح إعدادات التطبيق واسمح بصلاحية الموقع.',
      ),
      DriverLocationTrackingStatus.unavailable => _copy(
        context,
        'Location is unavailable now. Try recentering or opening Maps.',
        'الموقع غير متوفر حالياً. حاول إعادة التمركز أو فتح الخرائط.',
      ),
      DriverLocationTrackingStatus.syncFailed => _copy(
        context,
        'Current location is available, but server sync failed.',
        'الموقع الحالي متوفر، لكن تعذر تحديثه على الخادم.',
      ),
      DriverLocationTrackingStatus.idle => _copy(
        context,
        'Preparing tracking data.',
        'جاري تجهيز بيانات التتبع.',
      ),
    };
  }

  /// Maps this page's tracking status onto the app-wide location failure type,
  /// so the wording and the offered control come from one table rather than
  /// being written again here.
  LocationFailure _locationFailureFor(DriverLocationTrackingStatus status) {
    return switch (status) {
      DriverLocationTrackingStatus.disabled => LocationFailure.serviceDisabled,
      DriverLocationTrackingStatus.permissionRequired =>
        LocationFailure.permissionPermanentlyDenied,
      DriverLocationTrackingStatus.permissionPermanentlyDenied =>
        LocationFailure.permissionPermanentlyDenied,
      DriverLocationTrackingStatus.unavailable ||
      DriverLocationTrackingStatus.syncFailed ||
      DriverLocationTrackingStatus.active ||
      DriverLocationTrackingStatus.idle => LocationFailure.unavailable,
    };
  }

  /// Open Settings where only the system settings screen can fix it, and a
  /// retry where asking again is what is needed.
  _TrackingRemedy _remedyFor(BuildContext context, LocationFailure failure) {
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    if (locationFailureOffersSettings(failure)) {
      return _TrackingRemedy(
        label: openSettingsActionLabel(isArabic: isArabic),
        onPressed: ph.openAppSettings,
      );
    }
    return _TrackingRemedy(
      label: _copy(context, 'Retry', 'إعادة المحاولة'),
      onPressed: () => unawaited(_prepareTracking()),
    );
  }

  _TrackingBannerData getTrackingBannerState(
    BuildContext context,
    OrderLocationProvider provider,
  ) {
    final stage = _stageFor(_actionShipment);
    final target = getPrimaryDestination(_actionShipment);

    if (stage == _TrackingStage.finalSummary) {
      return _TrackingBannerData(
        title: _copy(context, 'Closed shipment', 'الشحنة مغلقة'),
        message: _copy(
          context,
          'No active stage can be changed or tracked for this shipment.',
          'لا يمكن تعديل أو تتبع مرحلة نشطة لهذه الشحنة.',
        ),
        icon: Icons.lock_outline_rounded,
        color: const Color(0xff64748B),
      );
    }

    if (target == _TrackingDestinationKind.none) {
      return _TrackingBannerData(
        title:
            stage == _TrackingStage.beforeAccept
                ? _copy(context, 'Accept first', 'اقبل الشحنة أولاً')
                : _copy(
                  context,
                  'Destination unavailable',
                  'موقع الوجهة غير متوفر',
                ),
        message:
            stage == _TrackingStage.beforeAccept
                ? _copy(
                  context,
                  'Accept the shipment before opening route tracking.',
                  'اقبل الشحنة قبل فتح تتبع المسار.',
                )
                : _copy(
                  context,
                  'There are not enough coordinates to show the route.',
                  'لا توجد إحداثيات كافية لعرض المسار.',
                ),
        icon:
            stage == _TrackingStage.beforeAccept
                ? Icons.lock_outline_rounded
                : Icons.location_off_outlined,
        color:
            stage == _TrackingStage.beforeAccept
                ? AppColors.primary
                : const Color(0xffF59E0B),
      );
    }

    if (!provider.hasFreshDeviceLocation &&
        provider.trackingStatus != DriverLocationTrackingStatus.active) {
      final failure = _locationFailureFor(provider.trackingStatus);
      return _TrackingBannerData(
        title: _copy(context, 'Location unavailable', 'الموقع غير متوفر'),
        // App-owned wording from the shared table, chosen by the typed
        // tracking status rather than by inspecting a message.
        message: locationFailureMessage(
          failure,
          isArabic: Localizations.localeOf(context).languageCode == 'ar',
        ),
        icon: Icons.gps_off_rounded,
        color: const Color(0xffDC2626),
        remedy: _remedyFor(context, failure),
      );
    }

    if (provider.hasImplausibleRouteDistance) {
      return _TrackingBannerData(
        title: _copy(context, 'Location unavailable', 'الموقع غير متوفر'),
        message: _copy(
          context,
          'Please set the device GPS near the active delivery area.',
          'تأكد من ضبط موقع الجهاز بالقرب من منطقة التوصيل الحالية.',
        ),
        icon: Icons.gps_off_rounded,
        color: const Color(0xffDC2626),
      );
    }

    if (provider.destinationLocation == null) {
      return _TrackingBannerData(
        title: _copy(
          context,
          'Destination unavailable',
          'موقع الوجهة غير متوفر',
        ),
        message: _copy(
          context,
          'There are not enough coordinates to show the route.',
          'لا توجد إحداثيات كافية لعرض المسار.',
        ),
        icon: Icons.location_off_outlined,
        color: const Color(0xffF59E0B),
      );
    }

    if (target == _TrackingDestinationKind.store) {
      return _TrackingBannerData(
        title: _copy(context, 'Route to store', 'المسار إلى المتجر'),
        message: _copy(
          context,
          'Head to the store to pick up the shipment.',
          'توجه إلى المتجر لاستلام الشحنة.',
        ),
        icon: Icons.storefront_rounded,
        color: AppColors.primary,
      );
    }

    if (target == _TrackingDestinationKind.customer) {
      return _TrackingBannerData(
        title: _copy(context, 'Route to customer', 'المسار إلى العميل'),
        message: _copy(
          context,
          'Head to the customer to deliver the shipment.',
          'توجه إلى العميل لتسليم الشحنة.',
        ),
        icon: Icons.near_me_rounded,
        color: const Color(0xff16A06D),
      );
    }

    return _TrackingBannerData(
      title: _copy(context, 'Route ready', 'المسار جاهز'),
      message: _copy(
        context,
        'You can continue from the map.',
        'يمكنك متابعة الطريق من الخريطة.',
      ),
      icon: Icons.route_outlined,
      color: const Color(0xff16A06D),
    );
  }

  _TrackingStage _stageFor(Shipment? shipment) {
    if (shipment == null || shipment.driverId == 0) {
      // A tracking route without an authoritative row cannot safely choose a
      // destination. The normal call paths supply a row; this protects a
      // notification deep link while its action snapshot is still loading.
      return isInstantShipment(shipment)
          ? _TrackingStage.beforeAccept
          : _TrackingStage.scheduled;
    }
    if (_isFinalStatus(shipment)) return _TrackingStage.finalSummary;
    // Server states 1/2/3/10 are the verified pickup boundary for both an
    // accepted offer and a direct Admin assignment. Delivery type is not an
    // authorization signal and must not choose a customer route.
    if (driverShipmentIsPrePickup(shipment)) {
      return _statusId(shipment) == 10
          ? _TrackingStage.arrivedAtStore
          : _TrackingStage.storePickup;
    }
    return _TrackingStage.delivery;
  }

  int _statusId(Shipment shipment) {
    if (_statusOverride != null) return _statusOverride!;
    return shipment.shipmentStatusId != 0
        ? shipment.shipmentStatusId
        : shipment.shipmentStatus;
  }

  bool _isFinalStatus(Shipment? shipment) {
    if (shipment == null) return false;
    return _finalStatusIds.contains(_statusId(shipment));
  }

  LatLng? _primaryDestinationLocation(_TrackingDestinationKind kind) {
    if (kind == _TrackingDestinationKind.store) {
      final source = _actionShipment?.pickupSource;
      if (source != null && source['kind'] != 'merchant') return null;
      return _validLatLng(widget.storeLocation) ??
          _shipmentStoreLocation(_actionShipment);
    }
    if (kind == _TrackingDestinationKind.customer) {
      return _shipmentCustomerLocation(_actionShipment);
    }
    return null;
  }

  String _primaryDestinationAddress(_TrackingDestinationKind kind) {
    if (kind == _TrackingDestinationKind.store) {
      return _firstClean([
        widget.storeAddress,
        _actionShipment?.lclient,
        _actionShipment?.nstore,
      ]);
    }
    if (kind == _TrackingDestinationKind.customer) {
      return _firstClean([
        widget.customerAddress,
        _actionShipment?.deliveryAddress,
      ]);
    }
    return '';
  }

  LatLng? _shipmentStoreLocation(Shipment? shipment) {
    return _latLngFromValues(shipment?.latitude, shipment?.longitude);
  }

  LatLng? _shipmentCustomerLocation(Shipment? shipment) {
    return _latLngFromValues(
      shipment?.deliveryLatitude,
      shipment?.deliveryLongitude,
    );
  }

  CameraPosition _initialCameraPosition(OrderLocationProvider provider) {
    final target =
        provider.destinationLocation ??
        provider.driverLocation ??
        _primaryDestinationLocation(getPrimaryDestination(_actionShipment)) ??
        const LatLng(31.9539, 35.9106);

    return CameraPosition(target: target, zoom: 13.5);
  }

  String get _policyNumber => _firstClean([
    widget.policyNumber,
    _actionShipment?.policyNum,
    '#${widget.shipmentId}',
  ]);

  String _shipmentTypeLabel(BuildContext context) {
    final explicit = _clean(widget.shipmentTypeLabel);
    if (explicit.isNotEmpty) return explicit;
    final shipment = _actionShipment;
    final localized =
        Localizations.localeOf(context).languageCode == 'ar'
            ? _clean(shipment?.typeNameAr)
            : _clean(shipment?.typeNameEn);
    if (localized.isNotEmpty) return localized;

    return switch (shipment?.deliveryTypeId ?? 0) {
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

  /// The visible status, resolved by the one helper every shipment screen
  /// uses.
  ///
  /// This screen used to carry its own copy of the eleven status labels, whose
  /// Arabic for status 9 had already drifted from the shared table.
  String _statusLabel(BuildContext context) {
    final shipment = _actionShipment;
    if (_statusOverride == null) {
      final explicit = _clean(widget.statusLabel);
      if (explicit.isNotEmpty) return explicit;
    }

    final statusId =
        _statusOverride ??
        (shipment == null
            ? 0
            : shipment.shipmentStatusId != 0
            ? shipment.shipmentStatusId
            : shipment.shipmentStatus);

    if (statusId <= 0) {
      return _copy(context, 'Status unavailable', 'الحالة غير متوفرة');
    }

    // Once an action has moved the status, the names that came with the old
    // status no longer describe it, so only the id is trusted.
    return getStatusLabel(
      context,
      statusId,
      statusNameEn: _statusOverride == null ? shipment?.statusNameEn : null,
      statusNameAr: _statusOverride == null ? shipment?.statusNameAr : null,
    );
  }

  String _stageLabel(BuildContext context, _TrackingStage stage) {
    // The caller's label describes the stage the shipment was in when this
    // screen opened. Once an action here has moved the status, that sentence is
    // stale — the icon and the action had already advanced while the stage row
    // still read "Go to Store".
    if (_statusOverride == null) {
      final explicit = _clean(widget.stageLabel);
      if (explicit.isNotEmpty) return explicit;
    }
    return switch (stage) {
      _TrackingStage.scheduled => _copy(
        context,
        'Scheduled Shipment',
        'شحنة مجدولة',
      ),
      _TrackingStage.beforeAccept => _copy(
        context,
        'Available Shipment',
        'شحنة متاحة',
      ),
      _TrackingStage.storePickup => _copy(
        context,
        'Go to Store',
        'توجه إلى المتجر',
      ),
      _TrackingStage.arrivedAtStore => _copy(
        context,
        'Arrived at Store',
        'تم الوصول إلى المتجر',
      ),
      _TrackingStage.delivery => _copy(
        context,
        'Go to Customer',
        'توجه إلى العميل',
      ),
      _TrackingStage.finalSummary => _copy(
        context,
        'Closed shipment',
        'شحنة مغلقة',
      ),
    };
  }

  String _directionLabel(BuildContext context) {
    return switch (getPrimaryDestination(_actionShipment)) {
      _TrackingDestinationKind.store => _copy(
        context,
        'To store',
        'إلى المتجر',
      ),
      _TrackingDestinationKind.customer => _copy(
        context,
        'To customer',
        'إلى العميل',
      ),
      _TrackingDestinationKind.none => _copy(
        context,
        'No private route yet',
        'لا يوجد مسار خاص بعد',
      ),
    };
  }

  String _destinationTitle(
    BuildContext context,
    _TrackingDestinationKind kind,
  ) {
    return switch (kind) {
      _TrackingDestinationKind.store => _copy(
        context,
        'Store Location',
        'موقع المتجر',
      ),
      _TrackingDestinationKind.customer => _copy(
        context,
        'Customer Location',
        'موقع العميل',
      ),
      _TrackingDestinationKind.none => _copy(context, 'Destination', 'الوجهة'),
    };
  }

  String _destinationName(BuildContext context) {
    final kind = getPrimaryDestination(_actionShipment);
    if (kind == _TrackingDestinationKind.none) {
      return _copy(context, 'Not available', 'غير متوفر');
    }
    final value =
        kind == _TrackingDestinationKind.store
            ? _firstClean([
              widget.storeName,
              _actionShipment?.nstore,
              _actionShipment?.nclient,
            ])
            : _firstClean([
              widget.customerName,
              _actionShipment?.recipientName,
            ]);
    return value.isEmpty ? _copy(context, 'Not available', 'غير متوفر') : value;
  }

  String _destinationSubtitle(
    BuildContext context,
    OrderLocationProvider provider,
  ) {
    final address =
        provider.destinationAddress.trim().isNotEmpty
            ? provider.destinationAddress
            : _primaryDestinationAddress(
              getPrimaryDestination(_actionShipment),
            );
    if (address.isNotEmpty) return address;
    return _copy(
      context,
      'Destination coordinates are not available.',
      'إحداثيات الوجهة غير متوفرة.',
    );
  }

  String _phoneForCurrentStage() {
    final kind = getPrimaryDestination(_actionShipment);
    if (kind == _TrackingDestinationKind.store) {
      return _firstClean([widget.storePhone, _actionShipment?.phclient]);
    }
    if (kind == _TrackingDestinationKind.customer) {
      return _firstClean([
        _actionShipment?.recipientPhone,
        widget.phoneCustomer,
      ]);
    }
    return '';
  }

  Color _stageColor(_TrackingStage stage) {
    return switch (stage) {
      _TrackingStage.scheduled => AppColors.primary,
      _TrackingStage.beforeAccept => const Color(0xff64748B),
      _TrackingStage.storePickup => AppColors.primary,
      _TrackingStage.arrivedAtStore => const Color(0xffF59E0B),
      _TrackingStage.delivery => const Color(0xff16A06D),
      _TrackingStage.finalSummary => const Color(0xff64748B),
    };
  }

  String _distanceLabel(BuildContext context, OrderLocationProvider provider) {
    final distance = provider.distanceInKm;
    if (distance == null || !distance.isFinite || distance <= 0) {
      return _copy(context, 'Calculating', 'قيد الحساب');
    }
    // The figure is isolated so its decimal point cannot be pulled to the wrong
    // end of the number by the surrounding Arabic.
    if (distance < 1) {
      final metres = isolateIdentifier('${(distance * 1000).round()}');
      return '$metres ${_copy(context, 'm', 'م')}';
    }
    final km = isolateIdentifier(distance.toStringAsFixed(1));
    return '$km ${_copy(context, 'km', 'كم')}';
  }

  String _compactLocationStatus(
    BuildContext context,
    OrderLocationProvider provider,
  ) {
    return switch (provider.trackingStatus) {
      DriverLocationTrackingStatus.active => _copy(
        context,
        'Connected',
        'متصل',
      ),
      DriverLocationTrackingStatus.disabled => _copy(
        context,
        'GPS disabled',
        'GPS غير مفعل',
      ),
      DriverLocationTrackingStatus.permissionRequired => _copy(
        context,
        'Permission required',
        'الصلاحية مطلوبة',
      ),
      DriverLocationTrackingStatus.permissionPermanentlyDenied => _copy(
        context,
        'Open app settings',
        'افتح إعدادات التطبيق',
      ),
      DriverLocationTrackingStatus.unavailable => _copy(
        context,
        'Unavailable',
        'غير متوفر',
      ),
      DriverLocationTrackingStatus.syncFailed => _copy(
        context,
        'Server sync failed',
        'تعذر التحديث على الخادم',
      ),
      DriverLocationTrackingStatus.idle => _copy(
        context,
        'Preparing',
        'جاري التجهيز',
      ),
    };
  }

  String _lastUpdateLabel(
    BuildContext context,
    OrderLocationProvider provider,
  ) {
    final updatedAt = provider.lastLocationSentAt;
    if (updatedAt == null) {
      return _copy(context, 'Not updated yet', 'لم يتم التحديث بعد');
    }
    // Locale pinned to 'en' so the clock is always Western digits, and the run
    // isolated so it cannot be reordered inside the Arabic sentence.
    final time = isolateIdentifier(
      DateFormat('HH:mm', 'en').format(JordanTime.toJordan(updatedAt)),
    );
    return '${_copy(context, 'Last update', 'آخر تحديث')} $time';
  }

  /// Dials the number for the current stage.
  ///
  /// Routed through the shared external-action helper: `launchUrl` throws a
  /// PlatformException on a device with no dialer, and this is reached from an
  /// onTap through an async gap, so the throw used to vanish and the driver saw
  /// nothing at all.
  Future<void> _call(String phone) async {
    if (!_sessionIsCurrent) return;
    final trimmed = phone.trim();
    if (trimmed.isEmpty) {
      _showSnack(
        _copy(context, 'Phone is not available.', 'رقم الهاتف غير متوفر.'),
      );
      return;
    }

    final result = await openExternalUri(Uri(scheme: 'tel', path: trimmed));
    if (!mounted || result.isSuccess) return;
    _showSnack(externalActionFailureMessage(context));
  }

  Future<void> _openExternalMap(OrderLocationProvider provider) async {
    if (!_sessionIsCurrent) return;
    final destination = provider.destinationLocation;
    final destinationText =
        provider.destinationAddress.trim().isNotEmpty
            ? provider.destinationAddress.trim()
            : _primaryDestinationAddress(
              getPrimaryDestination(_actionShipment),
            );

    if (destination == null && destinationText.isEmpty) {
      _showSnack(
        _copy(context, 'Destination is not available.', 'الوجهة غير متوفرة.'),
      );
      return;
    }

    final query =
        destination != null
            ? '${destination.latitude},${destination.longitude}'
            : destinationText;
    final uri = Uri.https('www.google.com', '/maps/dir/', {
      'api': '1',
      'destination': query,
    });

    final result = await openExternalUri(uri);
    if (!mounted || result.isSuccess) return;
    _showSnack(_copy(context, 'Unable to open maps.', 'تعذر فتح الخرائط.'));
  }

  void _showSnack(String message, {bool isError = true}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor:
              isError ? const Color(0xffDC2626) : const Color(0xff16A06D),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      );
  }

  String _copy(BuildContext context, String en, String ar) {
    return Localizations.localeOf(context).languageCode == 'ar' ? ar : en;
  }
}

class _TrackingLoadingState extends StatelessWidget {
  const _TrackingLoadingState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(22),
        padding: const EdgeInsets.all(22),
        decoration: _panelDecoration(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: AppColors.primary),
            const SizedBox(height: 14),
            Text(
              Localizations.localeOf(context).languageCode == 'ar'
                  ? 'جاري تحميل بيانات التتبع...'
                  : 'Loading tracking data...',
              style: const TextStyle(
                color: Color(0xff0F172A),
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrackingTopBar extends StatelessWidget implements PreferredSizeWidget {
  const _TrackingTopBar({
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
    final isRtl = Localizations.localeOf(context).languageCode == 'ar';

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
                  _BlueTopIconButton(
                    // One direction-aware icon. `chevron_left_rounded` carries
                    // matchTextDirection, so Flutter mirrors it under RTL —
                    // swapping it by hand as well mirrored it twice and left
                    // the Arabic back arrow pointing the wrong way.
                    icon: Icons.chevron_left_rounded,
                    onTap: Nav.back,
                    tooltip: isRtl ? 'رجوع' : 'Back',
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
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
                  _BlueHelpPill(onTap: onHelp),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BlueTopIconButton extends StatelessWidget {
  const _BlueTopIconButton({
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

class _BlueHelpPill extends StatelessWidget {
  const _BlueHelpPill({required this.onTap});

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
              size: 15,
              color: AppColors.primary,
            ),
            const SizedBox(width: 5),
            Text(
              Localizations.localeOf(context).languageCode == 'ar'
                  ? 'مساعدة'
                  : 'Help',
              style: TextStyle(
                color: AppColors.primary,
                fontSize: 10.5,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrackingMapCard extends StatelessWidget {
  const _TrackingMapCard({
    required this.provider,
    required this.initialPosition,
    required this.banner,
    required this.onMapCreated,
    required this.onRecenter,
    required this.onOpenMaps,
  });

  final OrderLocationProvider provider;
  final CameraPosition initialPosition;
  final _TrackingBannerData banner;
  final ValueChanged<GoogleMapController> onMapCreated;
  final VoidCallback onRecenter;
  final VoidCallback onOpenMaps;

  @override
  Widget build(BuildContext context) {
    final hasMapSignal =
        provider.driverLocation != null || provider.destinationLocation != null;

    return Container(
      decoration: _panelDecoration(radius: 24),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          SizedBox(
            height: 318,
            child: Stack(
              children: [
                Positioned.fill(
                  child:
                      hasMapSignal
                          ? GoogleMap(
                            initialCameraPosition: initialPosition,
                            markers: provider.markers,
                            polylines: provider.polylines,
                            onMapCreated: onMapCreated,
                            mapType: MapType.normal,
                            myLocationEnabled: false,
                            myLocationButtonEnabled: false,
                            zoomControlsEnabled: false,
                            compassEnabled: false,
                          )
                          : const _MapUnavailableState(),
                ),
                PositionedDirectional(
                  top: 12,
                  start: 12,
                  end: 12,
                  child: _TrackingStatusPill(banner: banner),
                ),
                PositionedDirectional(
                  end: 12,
                  bottom: 12,
                  child: Column(
                    children: [
                      _MapControlButton(
                        icon: Icons.my_location_rounded,
                        tooltip:
                            Localizations.localeOf(context).languageCode == 'ar'
                                ? 'توسيط المسار'
                                : 'Center route',
                        onTap: onRecenter,
                      ),
                      const SizedBox(height: 10),
                      _MapControlButton(
                        icon: Icons.map_outlined,
                        tooltip:
                            Localizations.localeOf(context).languageCode == 'ar'
                                ? 'فتح في الخرائط'
                                : 'Open in Maps',
                        onTap: onOpenMaps,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Row(
              children: [
                _LegendDot(
                  color: AppColors.primary,
                  label:
                      Localizations.localeOf(context).languageCode == 'ar'
                          ? 'السائق'
                          : 'Driver',
                ),
                const SizedBox(width: 12),
                const _LegendDot(color: Color(0xffEF4444), label: ''),
                const SizedBox(width: 4),
                Text(
                  Localizations.localeOf(context).languageCode == 'ar'
                      ? 'الوجهة'
                      : 'Destination',
                  style: const TextStyle(
                    color: Color(0xff64748B),
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
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

class _MapUnavailableState extends StatelessWidget {
  const _MapUnavailableState();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xffEAF1F8),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.map_outlined, color: AppColors.primary, size: 42),
            const SizedBox(height: 10),
            Text(
              Localizations.localeOf(context).languageCode == 'ar'
                  ? 'الخريطة بانتظار بيانات الموقع'
                  : 'Map is waiting for location data',
              style: const TextStyle(
                color: Color(0xff0F172A),
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        if (label.isNotEmpty) ...[
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xff64748B),
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ],
    );
  }
}

class _TrackingStatusPill extends StatelessWidget {
  const _TrackingStatusPill({required this.banner});

  final _TrackingBannerData banner;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: banner.color.withValues(alpha: 0.18)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: banner.color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(banner.icon, color: banner.color, size: 17),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  banner.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xff0F172A),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  banner.message,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xff64748B),
                    fontSize: 11,
                    height: 1.25,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                // A location problem the driver can actually fix gets the
                // control that fixes it. Before this the pill only described
                // the problem and left them with nothing to press.
                if (banner.remedy != null) ...[
                  const SizedBox(height: 6),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton(
                      onPressed: banner.remedy!.onPressed,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        minimumSize: const Size(0, 36),
                        tapTargetSize: MaterialTapTargetSize.padded,
                        foregroundColor: banner.color,
                      ),
                      child: Text(
                        banner.remedy!.label,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The one control offered beside a location problem.
class _TrackingRemedy {
  const _TrackingRemedy({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;
}

class _TrackingBannerData {
  const _TrackingBannerData({
    required this.title,
    required this.message,
    required this.icon,
    required this.color,
    this.remedy,
  });

  final String title;
  final String message;
  final IconData icon;
  final Color color;
  final _TrackingRemedy? remedy;
}

class _MapControlButton extends StatelessWidget {
  const _MapControlButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Icon(icon, color: AppColors.primary, size: 22),
        ),
      ),
    );
  }
}

class _RouteSummaryCard extends StatelessWidget {
  const _RouteSummaryCard({
    required this.policyNumber,
    required this.primaryLabel,
    required this.primarySubtitle,
    required this.primaryIcon,
    required this.primaryColor,
    required this.items,
  });

  final String policyNumber;
  final String primaryLabel;
  final String primarySubtitle;
  final IconData primaryIcon;
  final Color primaryColor;
  final List<_SummaryItem> items;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _panelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(
                  Icons.route_outlined,
                  color: AppColors.primary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      Localizations.localeOf(context).languageCode == 'ar'
                          ? 'ملخص المسار'
                          : 'Route Summary',
                      style: const TextStyle(
                        color: Color(0xff0F172A),
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      policyNumber,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      // A reference is read left-to-right in both languages;
                      // without this its digits and separators reorder inside
                      // an Arabic paragraph.
                      textDirection: identifierTextDirection(policyNumber),
                      style: const TextStyle(
                        color: Color(0xff64748B),
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  primaryColor.withValues(alpha: 0.13),
                  primaryColor.withValues(alpha: 0.05),
                ],
                begin: AlignmentDirectional.topStart,
                end: AlignmentDirectional.bottomEnd,
              ),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: primaryColor.withValues(alpha: 0.18)),
            ),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: primaryColor.withValues(alpha: 0.10),
                        blurRadius: 14,
                        offset: const Offset(0, 7),
                      ),
                    ],
                  ),
                  child: Icon(primaryIcon, color: primaryColor, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        primaryLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xff0F172A),
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        primarySubtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xff64748B),
                          fontSize: 12,
                          height: 1.25,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Column(
            children:
                items
                    .map(
                      (item) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _SummaryRow(item: item),
                      ),
                    )
                    .toList(),
          ),
        ],
      ),
    );
  }
}

class _SummaryItem {
  const _SummaryItem({
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

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.item});

  final _SummaryItem item;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: const Color(0xffF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xffE2E8F0)),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: item.color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(item.icon, color: item.color, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xff64748B),
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Text(
                item.value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: const TextStyle(
                  color: Color(0xff0F172A),
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LocationInfoCard extends StatelessWidget {
  const _LocationInfoCard({
    required this.title,
    required this.subtitle,
    required this.trailing,
    required this.icon,
    required this.color,
  });

  final String title;
  final String subtitle;
  final String trailing;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _panelDecoration(),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xff0F172A),
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        trailing,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xff64748B),
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xff64748B),
                    fontSize: 12.5,
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

/// One forward step for [_ActionPanel] (see driverShipmentActionsFor).
class _StepButtonData {
  const _StepButtonData({
    required this.key,
    required this.label,
    required this.icon,
    required this.isLoading,
    required this.isOutlined,
    required this.isDeliver,
    required this.onTap,
  });

  final Key key;
  final String label;
  final IconData icon;
  final bool isLoading;
  final bool isOutlined;
  final bool isDeliver;
  final VoidCallback? onTap;
}

class _ActionPanel extends StatelessWidget {
  const _ActionPanel({
    required this.primaryStep,
    required this.secondaryStep,
    required this.nextStepHint,
    required this.statusActionLabel,
    required this.isStatusActionLoading,
    required this.onStatusAction,
    required this.canCall,
    required this.callLabel,
    required this.onCall,
    required this.onOpenMaps,
    required this.onRecenter,
    required this.onSupport,
  });

  final _StepButtonData? primaryStep;
  final _StepButtonData? secondaryStep;

  /// What comes next, or why nothing does.
  final String? nextStepHint;
  final String statusActionLabel;
  final bool isStatusActionLoading;
  final VoidCallback? onStatusAction;
  final bool canCall;
  final String callLabel;
  final VoidCallback onCall;
  final VoidCallback onOpenMaps;
  final VoidCallback onRecenter;
  final VoidCallback onSupport;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _panelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (nextStepHint != null) ...[
            Padding(
              key: const ValueKey('next_step_hint'),
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
              child: Text(
                nextStepHint!,
                style: TextStyle(
                  color:
                      primaryStep == null
                          ? const Color(0xffB45309)
                          : const Color(0xff334155),
                  fontSize: 12.5,
                  height: 1.35,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
          for (final step in [primaryStep, secondaryStep])
            if (step != null) ...[
              _TrackingButton(
                key: step.key,
                label: step.label,
                icon: step.icon,
                isOutlined: step.isOutlined,
                isLoading: step.isLoading,
                color: step.isDeliver ? const Color(0xff16A06D) : null,
                onTap: step.onTap,
              ),
              const SizedBox(height: 10),
            ],
          if (onStatusAction != null) ...[
            _TrackingButton(
              label: statusActionLabel,
              icon: Icons.fact_check_outlined,
              isOutlined: true,
              isLoading: isStatusActionLoading,
              onTap: onStatusAction,
            ),
            const SizedBox(height: 10),
          ],
          Row(
            children: [
              Expanded(
                child: _TrackingButton(
                  label:
                      Localizations.localeOf(context).languageCode == 'ar'
                          ? 'فتح الخرائط'
                          : 'Open Maps',
                  icon: Icons.map_outlined,
                  onTap: onOpenMaps,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _TrackingButton(
                  label: callLabel,
                  icon: Icons.call_outlined,
                  isOutlined: true,
                  onTap: canCall ? onCall : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _TrackingButton(
                  label:
                      Localizations.localeOf(context).languageCode == 'ar'
                          ? 'توسيط المسار'
                          : 'Center Route',
                  icon: Icons.center_focus_strong_rounded,
                  isOutlined: true,
                  onTap: onRecenter,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _TrackingButton(
                  label:
                      Localizations.localeOf(context).languageCode == 'ar'
                          ? 'الدعم'
                          : 'Support',
                  icon: Icons.support_agent_outlined,
                  isOutlined: true,
                  onTap: onSupport,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TrackingButton extends StatelessWidget {
  const _TrackingButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    this.isOutlined = false,
    this.isLoading = false,
    this.color,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool isOutlined;
  final bool isLoading;

  /// Fill colour of a solid button; the app primary when null.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final fill = color ?? AppColors.primary;
    return SizedBox(
      height: 48,
      child: ElevatedButton.icon(
        onPressed: isLoading ? null : onTap,
        icon:
            isLoading
                ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
                : Icon(icon, size: 18),
        label: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: AppFonts.currentFontFamily,
            fontWeight: FontWeight.w900,
            fontSize: 14,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: isOutlined ? Colors.white : fill,
          foregroundColor: isOutlined ? AppColors.primary : Colors.white,
          disabledBackgroundColor: const Color(0xffE2E8F0),
          disabledForegroundColor: const Color(0xff94A3B8),
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
          textStyle: TextStyle(
            fontFamily: AppFonts.currentFontFamily,
            fontWeight: FontWeight.w900,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}

Color _trackingStatusColor(DriverLocationTrackingStatus status) {
  return switch (status) {
    DriverLocationTrackingStatus.active => const Color(0xff16A06D),
    DriverLocationTrackingStatus.disabled => const Color(0xffF59E0B),
    DriverLocationTrackingStatus.permissionRequired => const Color(0xffF59E0B),
    DriverLocationTrackingStatus.permissionPermanentlyDenied => const Color(
      0xffDC2626,
    ),
    DriverLocationTrackingStatus.unavailable => const Color(0xffDC2626),
    DriverLocationTrackingStatus.syncFailed => const Color(0xffDC2626),
    DriverLocationTrackingStatus.idle => AppColors.primary,
  };
}

LatLng? _validLatLng(LatLng? location) {
  if (location == null) return null;
  final lat = location.latitude;
  final lng = location.longitude;
  // Finiteness first: every comparison against NaN is false, so a NaN pair
  // passed the range check below and reached the map.
  if (!lat.isFinite || !lng.isFinite) return null;
  if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return null;
  if (lat == 0 && lng == 0) return null;
  return location;
}

LatLng? _latLngFromValues(String? latitudeValue, String? longitudeValue) {
  final lat = double.tryParse(latitudeValue ?? '');
  final lng = double.tryParse(longitudeValue ?? '');
  if (lat == null || lng == null) return null;

  if (_looksLikeSwappedJordanPair(lat, lng)) {
    return _validLatLng(LatLng(lng, lat));
  }

  return _validLatLng(LatLng(lat, lng));
}

bool _looksLikeSwappedJordanPair(double lat, double lng) {
  return !_isJordanLatitude(lat) &&
      !_isJordanLongitude(lng) &&
      _isJordanLongitude(lat) &&
      _isJordanLatitude(lng);
}

bool _isJordanLatitude(double value) => value >= 29.0 && value <= 34.0;

bool _isJordanLongitude(double value) => value >= 34.0 && value <= 40.0;

String _firstClean(List<String?> values) {
  for (final value in values) {
    final clean = _clean(value);
    if (clean.isNotEmpty) return clean;
  }
  return '';
}

String _clean(String? value) {
  final clean = value?.trim() ?? '';
  if (clean.isEmpty || clean.toLowerCase() == 'null') return '';
  if (clean == 'غير متوفر' || clean == 'Not available') return '';
  if (_looksLikeImagePath(clean)) return '';
  return clean;
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

BoxDecoration _panelDecoration({double radius = 18}) {
  return BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: const Color(0xffE2E8F0)),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.035),
        blurRadius: 18,
        offset: const Offset(0, 8),
      ),
    ],
  );
}
