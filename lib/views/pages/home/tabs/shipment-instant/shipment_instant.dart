import 'dart:async';

import 'package:blockatie/constants/app_urls.dart';
import 'package:blockatie/constants/colors.dart';
import 'package:blockatie/constants/helper.dart';
import 'package:blockatie/models/order_status_modle.dart';
import 'package:blockatie/models/shipment.dart';
import 'package:blockatie/models/shipment_flow_config.dart';
import 'package:blockatie/provider/home.dart';
import 'package:blockatie/provider/profile.dart';
import 'package:blockatie/provider/shipment.dart';
import 'package:blockatie/provider/shipment_flow_config.dart';
import 'package:blockatie/provider/shipment_instsnt.dart';
import 'package:blockatie/utils/driver_shipment_actions.dart';
import 'package:blockatie/utils/driver_shipment_list_rules.dart';
import 'package:blockatie/utils/nav.dart';
import 'package:blockatie/utils/text_direction.dart';
import 'package:blockatie/views/pages/home/components/header.dart';
import 'package:blockatie/views/pages/order-location/order_location.dart';
import 'package:blockatie/views/pages/orders/order_details.dart';
import 'package:blockatie/views/widgets/driver_chat_bubble.dart';
import 'package:blockatie/views/widgets/pagination_widget.dart';
import 'package:blockatie/views/widgets/status_update_sheet.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

class ShipmentInstantPage extends StatefulWidget {
  const ShipmentInstantPage({
    super.key,
    this.showheader = false,
    this.shipmentScope,
  });

  final bool? showheader;
  final String? shipmentScope;

  @override
  State<ShipmentInstantPage> createState() => _ShipmentInstantPageState();
}

class _ShipmentInstantPageState extends State<ShipmentInstantPage> with Helper {
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadInitialData());
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    if (!mounted || _isInitialized) return;
    _isInitialized = true;

    final flowConfig = context.read<ShipmentFlowConfigProvider>();
    if (!flowConfig.hasLoadedRemote && !flowConfig.isLoading) {
      unawaited(flowConfig.fetch());
    }

    final profileProvider = context.read<ProfileProvider>();
    final profile =
        profileProvider.profileInfo ??
        await profileProvider.fetchDriverProfile();
    if (!mounted) return;
    if (!_canViewInstantShipments(profile)) return;

    final provider = context.read<ShipmentInstantprovider>();
    if (widget.shipmentScope != null) {
      await provider.selectShipmentScope(widget.shipmentScope!);
    } else if (!provider.hasLoaded && !provider.isLoading) {
      unawaited(provider.getShipmentsInstant());
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<ProfileProvider>().profileInfo;
    if (!_canViewInstantShipments(profile)) {
      return _InstantAccessRestricted(
        title: _copy(
          context,
          'Available shipments are not included.',
          'الشحنات الفورية المتاحة غير مشمولة.',
        ),
        message: _copy(
          context,
          'Instant shipments are available only for eligible active subscriptions.',
          'الشحنات الفورية تظهر فقط للاشتراكات النشطة المؤهلة.',
        ),
      );
    }

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: SafeArea(
        child: Consumer2<ShipmentInstantprovider, ShipmentFlowConfigProvider>(
          builder: (context, provider, flowConfig, _) {
            if (widget.shipmentScope != null &&
                provider.shipmentScope != widget.shipmentScope) {
              return const Center(child: CircularProgressIndicator());
            }
            final activeInstant = provider.activeInstantShipment;
            final additionalActive = provider.activeInstantShipments;

            return RefreshIndicator(
              color: AppColors.primary,
              onRefresh: provider.refresh,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                slivers: [
                  if (widget.showheader == true)
                    const SliverToBoxAdapter(
                      child: HomeHeader(notificationCount: 1),
                    ),
                  SliverPadding(
                    // Clears the floating chat launcher as well as the
                    // bottom-navigation pill: at 110 the last card's Accept
                    // button sat underneath the bubble.
                    padding: EdgeInsets.fromLTRB(
                      18,
                      16,
                      18,
                      DriverChatBubble.reservedBottomSpace + 16,
                    ),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        _InstantHeader(
                          totalCount: provider.totalCount,
                          // Only the very first read blanks the count. A page
                          // change keeps the figure, which has not changed.
                          isLoading: provider.isLoading && !provider.hasLoaded,
                        ),
                        const SizedBox(height: 14),
                        if (activeInstant != null ||
                            additionalActive.isNotEmpty) ...[
                          _InstantListSectionHeader(
                            title: _copy(
                              context,
                              'Active instant shipments',
                              'الشحنات الفورية النشطة',
                            ),
                          ),
                          const SizedBox(height: 10),
                        ],
                        if (activeInstant != null) ...[
                          _PinnedActiveInstantCard(
                            shipment: activeInstant,
                            statusLabel: _shipmentStatusLabel(
                              activeInstant,
                              flowConfig,
                            ),
                            stageLabel: _instantStageLabel(
                              context,
                              activeInstant,
                            ),
                            isBusy: provider.isShipmentBusy(activeInstant.id),
                            onStep: (step) => _runStep(activeInstant, step),
                            onUpdateStatus:
                                () => _showUpdateStatusSheet(activeInstant),
                            onContinue:
                                () => _openShipmentTracking(activeInstant),
                          ),
                          const SizedBox(height: 14),
                        ],
                        ..._buildActiveRows(
                          provider,
                          flowConfig,
                          additionalActive,
                        ),
                        if (activeInstant != null ||
                            additionalActive.isNotEmpty)
                          const SizedBox(height: 8),
                        _InstantSearchBar(
                          controller: _searchController,
                          onChanged: _onSearchChanged,
                        ),
                        const SizedBox(height: 16),
                        // One state at a time, in this order. A failed read
                        // used to render the error card *and* the empty state,
                        // telling the driver there is no work when the app
                        // simply could not ask.
                        ..._buildQueueState(context, provider, flowConfig),
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

  /// Exactly one of: loading, error, empty, rows. When a page already on
  /// screen fails to change, the rows stay — they are still the page
  /// `currentPage` names — with the failure stated above them.
  List<Widget> _buildQueueState(
    BuildContext context,
    ShipmentInstantprovider provider,
    ShipmentFlowConfigProvider flowConfig,
  ) {
    if (provider.isLoading && !provider.hasLoaded) {
      return const [
        _InstantListSectionHeader(
          title: 'Available now',
          titleAr: 'متاحة الآن',
        ),
        SizedBox(height: 10),
        _InstantLoadingList(),
      ];
    }

    if (provider.hasError) {
      final error = _InstantErrorCard(
        message: _copy(
          context,
          'Unable to load available instant shipments. Please try again.',
          'تعذر تحميل الشحنات الفورية المتاحة. حاول مرة أخرى.',
        ),
        onRetry: () => provider.getShipmentsInstant(force: true),
      );

      if (!provider.hasLoaded) {
        return [
          _InstantListSectionHeader(
            title: 'Available now',
            titleAr: 'متاحة الآن',
          ),
          const SizedBox(height: 10),
          error,
        ];
      }
      return [
        _InstantListSectionHeader(
          title: _copy(context, 'Available now', 'متاحة الآن'),
        ),
        const SizedBox(height: 10),
        error,
        const SizedBox(height: 16),
        ..._buildRows(provider, flowConfig),
      ];
    }

    if (provider.paginatedShipments.isEmpty) {
      return [
        _InstantListSectionHeader(
          title: _copy(context, 'Available now', 'متاحة الآن'),
        ),
        const SizedBox(height: 10),
        _InstantEmptyState(
          title: _copy(
            context,
            'No available instant shipments right now.',
            'لا توجد شحنات فورية متاحة حالياً.',
          ),
          message: _copy(
            context,
            'Pull to refresh and check again.',
            'اسحب للتحديث والتحقق مرة أخرى.',
          ),
        ),
      ];
    }

    return [
      _InstantListSectionHeader(
        title: _copy(context, 'Available now', 'متاحة الآن'),
      ),
      const SizedBox(height: 10),
      ..._buildRows(provider, flowConfig),
    ];
  }

  List<Widget> _buildActiveRows(
    ShipmentInstantprovider provider,
    ShipmentFlowConfigProvider flowConfig,
    List<Shipment> shipments,
  ) {
    return shipments
        .map(
          (shipment) => Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: _InstantShipmentCard(
              shipment: shipment,
              statusLabel: _shipmentStatusLabel(shipment, flowConfig),
              privacyProfile: flowConfig.afterAcceptPrivacy,
              acceptLabel: flowConfig.actionLabelFor(
                actionKey: 'accept_shipment',
                languageCode: _requestLanguageCode(context),
                fallback: _copy(context, 'Accept Shipment', 'قبول الشحنة'),
              ),
              isAccepting: provider.isShipmentBusy(shipment.id),
              onViewDetails: () => _openShipmentDetails(shipment),
              onTrackShipment: () => _openShipmentTracking(shipment),
              onStoreCall: () => _callStore(shipment),
              onStoreMap: () => _openStoreMap(shipment),
              onCustomerCall: () => _callRecipient(shipment),
              onCustomerMap: () => _openCustomerMap(shipment),
              onAccept: () => _confirmAccept(shipment),
              onArrivedAtStore: () => _markArrivedAtStore(shipment),
              onPickupFromStore: () => _pickupShipmentFromStore(shipment),
              onDeliver: () => _runStep(shipment, DriverShipmentStep.deliver),
              onUpdateStatus: () => _showUpdateStatusSheet(shipment),
            ),
          ),
        )
        .toList();
  }

  List<Widget> _buildRows(
    ShipmentInstantprovider provider,
    ShipmentFlowConfigProvider flowConfig,
  ) {
    final pager =
        provider.totalPages > 1
            ? PaginationWidget(
              currentPage: provider.currentPage,
              totalPages: provider.totalPages,
              onPageChanged: provider.setCurrentPage,
              hasNextPage: provider.currentPage < provider.totalPages,
              hasPreviousPage: provider.currentPage > 1,
              isBusy: provider.isPageChanging,
            )
            : null;

    return [
      if (pager != null) ...[pager, const SizedBox(height: 14)],
      ...provider.paginatedShipments.map(
        (shipment) => Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: _InstantShipmentCard(
            shipment: shipment,
            statusLabel: _shipmentStatusLabel(shipment, flowConfig),
            // Ordinarily [paginatedShipments] contains only Available rows.
            // Still use the shared classifier here rather than the list route
            // as a second source of truth: an authoritative owned row must
            // retain its post-accept privacy profile if a caller supplies it.
            privacyProfile:
                DriverShipmentListRules.isAvailableInstantOffer(shipment)
                    ? flowConfig.beforeAcceptPrivacy
                    : flowConfig.afterAcceptPrivacy,
            acceptLabel: flowConfig.actionLabelFor(
              actionKey: 'accept_shipment',
              languageCode: _requestLanguageCode(context),
              fallback: _copy(context, 'Accept Shipment', 'قبول الشحنة'),
            ),
            isAccepting: provider.isShipmentBusy(shipment.id),
            onViewDetails: () => _openShipmentDetails(shipment),
            onTrackShipment: () => _openShipmentTracking(shipment),
            onStoreCall: () => _callStore(shipment),
            onStoreMap: () => _openStoreMap(shipment),
            onCustomerCall: () => _callRecipient(shipment),
            onCustomerMap: () => _openCustomerMap(shipment),
            onAccept: () => _confirmAccept(shipment),
            onArrivedAtStore: () => _markArrivedAtStore(shipment),
            onPickupFromStore: () => _pickupShipmentFromStore(shipment),
            onDeliver: () => _runStep(shipment, DriverShipmentStep.deliver),
            onUpdateStatus: () => _showUpdateStatusSheet(shipment),
          ),
        ),
      ),
      // The same pager again, so a driver who has read to the bottom of a page
      // does not have to scroll back up to reach the next one.
      if (pager != null) ...[const SizedBox(height: 2), pager],
    ];
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      context.read<ShipmentInstantprovider>().setSearchQuery(value);
    });
  }

  Future<void> _confirmAccept(Shipment shipment) async {
    if (!shipment.allowsAction('accept_shipment')) return;
    if (shipment.id <= 0) {
      _showSnack(
        _copy(
          context,
          'Shipment information is missing.',
          'بيانات الشحنة غير متوفرة.',
        ),
      );
      return;
    }

    final provider = context.read<ShipmentInstantprovider>();
    if (provider.isShipmentBusy(shipment.id)) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          title: Text(
            _copy(context, 'Accept shipment?', 'هل تريد قبول هذه الشحنة؟'),
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          content: Text(
            _copy(
              context,
              'This shipment will be assigned to your driver account.',
              'سيتم إسناد هذه الشحنة إلى حساب السائق الخاص بك.',
            ),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(_copy(context, 'Cancel', 'إلغاء')),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Text(_copy(context, 'Accept', 'قبول')),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    final result = await provider.acceptShipment(
      shipment.id,
      acceptedShipment: shipment,
      languageCode: _requestLanguageCode(context),
    );
    if (!mounted) return;

    if (result.success) {
      _showSnack(result.message, backgroundColor: const Color(0xff16A06D));
      unawaited(context.read<ShipmentProvider>().getAllShipments(force: true));
      return;
    }

    // A failure is never dressed as success. When the server says the job is
    // gone, the provider has already refetched from it — nothing is assigned
    // locally — so the card the driver just tapped disappears instead of
    // sitting there inviting another attempt.
    _showSnack(result.message);
  }

  Future<void> _markArrivedAtStore(Shipment shipment) async {
    await _runStep(shipment, DriverShipmentStep.arriveAtStore);
  }

  Future<void> _pickupShipmentFromStore(Shipment shipment) async {
    await _runStep(shipment, DriverShipmentStep.pickUp);
  }

  /// A step from the pinned card, or Delivered from a card in transit. The
  /// provider re-reads this list itself; the assigned list and, after a
  /// delivery, the counters are refreshed here.
  Future<void> _runStep(Shipment shipment, DriverShipmentStep step) async {
    final result = await performDriverShipmentStep(
      context,
      shipment: shipment,
      step: step,
    );
    if (result == null || !mounted) return;
    if (result.code == 'SESSION_CHANGED') return;

    _showSnack(
      result.message.trim().isNotEmpty
          ? result.message
          : result.success
          ? _copy(context, 'Shipment updated.', 'تم تحديث الشحنة.')
          : _copy(
            context,
            'Unable to update the shipment.',
            'تعذر تحديث الشحنة.',
          ),
      backgroundColor:
          result.success ? const Color(0xff16A06D) : const Color(0xffDC2626),
    );
    if (result.success && step == DriverShipmentStep.deliver) {
      unawaited(
        context.read<HomeProvider>().getDriverStatistics(context, force: true),
      );
    }
    unawaited(context.read<ShipmentProvider>().getAllShipments(force: true));
    if (!result.success && driverStepRefusalIsStale(result)) {
      unawaited(
        context.read<ShipmentInstantprovider>().getShipmentsInstant(
          force: true,
        ),
      );
    }
  }

  void _openShipmentDetails(Shipment shipment) {
    Nav.to(
      OrderDetailPage(
        shipment: shipment,
        isInstantFlow: true,
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

  void _openShipmentTracking(Shipment shipment) {
    final flowConfig = context.read<ShipmentFlowConfigProvider>();
    Nav.to(
      LocationOrderPage(
        shipmentId: shipment.id,
        phoneCustomer: _phoneFor(shipment),
        shipment: shipment,
        isInstantFlow: true,
        storeLocation: _shipmentStoreLatLng(shipment),
        policyNumber: shipment.policyNum,
        shipmentTypeLabel: _deliveryTypeLabel(context, shipment),
        statusLabel: _shipmentStatusLabel(shipment, flowConfig),
        stageLabel: _instantStageLabel(context, shipment),
        storeName:
            shipment.nstore.trim().isNotEmpty
                ? shipment.nstore
                : shipment.nclient,
        storePhone: shipment.phclient,
        storeAddress: _storeAddressFor(shipment),
        customerName: shipment.recipientName,
        customerAddress: shipment.deliveryAddress,
      ),
      withNav: true,
      navIndex: 1,
    );
  }

  Future<void> _callStore(Shipment shipment) async {
    final phone = shipment.phclient.trim();
    if (phone.isEmpty) {
      _showSnack(
        _copy(
          context,
          'Store phone is not available.',
          'رقم هاتف المتجر غير متوفر.',
        ),
      );
      return;
    }

    final launched = await launchUrl(
      Uri.parse('tel:$phone'),
      mode: LaunchMode.externalApplication,
    );
    if (!mounted || launched) return;
    _showSnack(_copy(context, 'Unable to start call.', 'تعذر بدء الاتصال.'));
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

    final launched = await launchUrl(
      Uri.parse('tel:$phone'),
      mode: LaunchMode.externalApplication,
    );
    if (!mounted || launched) return;
    _showSnack(_copy(context, 'Unable to start call.', 'تعذر بدء الاتصال.'));
  }

  Future<void> _openStoreMap(Shipment shipment) async {
    final query = _storeMapQueryFor(shipment);
    if (query.isEmpty) {
      _showSnack(
        _copy(context, 'Location is not available.', 'الموقع غير متوفر.'),
      );
      return;
    }

    final launched = await launchUrl(
      Uri.https('www.google.com', '/maps/search/', {
        'api': '1',
        'query': query,
      }),
      mode: LaunchMode.externalApplication,
    );
    if (!mounted || launched) return;
    _showSnack(_copy(context, 'Unable to open map.', 'تعذر فتح الخريطة.'));
  }

  Future<void> _openCustomerMap(Shipment shipment) async {
    final query = shipment.deliveryAddress.trim();
    if (query.isEmpty) {
      _showSnack(
        _copy(context, 'Location is not available.', 'الموقع غير متوفر.'),
      );
      return;
    }

    final launched = await launchUrl(
      Uri.https('www.google.com', '/maps/search/', {
        'api': '1',
        'query': query,
      }),
      mode: LaunchMode.externalApplication,
    );
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

    // The shared sheet, as on every other screen: only the off-ramps
    // update_shipment_status.php takes (7/8/9), each with its reason. This
    // card used to open a private list of every status but Pending, sent
    // without a reason — so the server refused whatever the driver picked.
    final currentStatusId = _effectiveStatusId(shipment);
    final statuses =
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
          shipmentId: shipment.id,
          statuses: statuses,
          currentStatusId: currentStatusId,
          currentStatusLabel: getStatusLabel(
            context,
            currentStatusId,
            statusNameEn: shipment.statusNameEn,
            statusNameAr: shipment.statusNameAr,
          ),
          currentStageLabel: _instantStageLabel(context, shipment),
          policyNumber: shipment.policyNum,
          doorFeeCollectable: shipment.financial?.doorFeeCollectable ?? 0,
          onSubmit: (status, reason) async {
            final success = await homeProvider.updateStatus(
              shipmentId: shipment.id,
              statusId: status.id,
              reasonId: reason?.reasonId,
              reasonNote: reason?.note,
              feeCollectedAmount: reason?.feeCollectedAmount,
              isInstant: true,
              showSuccessDialog: false,
            );
            if (success && mounted) {
              unawaited(
                context.read<ShipmentInstantprovider>().getShipmentsInstant(
                  force: true,
                ),
              );
              unawaited(
                context.read<ShipmentProvider>().getAllShipments(force: true),
              );
              _showSnack(
                _copy(
                  context,
                  'Shipment status updated.',
                  'تم تحديث حالة الشحنة.',
                ),
                backgroundColor: const Color(0xff16A06D),
              );
            }
            return success;
          },
        );
      },
    );
    if (mounted) {
      await context.read<ShipmentInstantprovider>().getShipmentsInstant(
        force: true,
      );
    }
  }

  /// One resolver, shared with the assigned list and the status sheet, so the
  /// same shipment cannot be worded differently in two places.
  ///
  /// Priority: the remote flow-config override, then the shipment's own
  /// bilingual status columns, then the shared table for that id. The
  /// shipment's `message` is deliberately not in that chain — it is a sentence
  /// about the shipment, not the name of its status.
  String _shipmentStatusLabel(
    Shipment shipment,
    ShipmentFlowConfigProvider flowConfig,
  ) {
    final statusId = _statusIdOf(shipment);
    final shared = getStatusLabel(
      context,
      statusId,
      statusNameEn: shipment.statusNameEn,
      statusNameAr: shipment.statusNameAr,
    );

    // Only a config the server actually sent may rename a status. The built-in
    // fallback config carries its own names — "In Progress" where the rest of
    // the app says "In Transit" — and letting that win made this page a third
    // source of wording for the same id.
    if (flowConfig.isFallback) return shared;

    return flowConfig.statusLabelFor(
      statusId: statusId,
      languageCode: _requestLanguageCode(context),
      fallback: shared,
    );
  }

  /// The canonical code for anything that selects a language rather than
  /// renders one: flow-config lookups and the message the server sends back.
  String _requestLanguageCode(BuildContext context) =>
      Localizations.localeOf(context).languageCode == 'ar' ? 'ar' : 'en';

  String _phoneFor(Shipment shipment) {
    if (shipment.recipientPhone.trim().isNotEmpty) {
      return shipment.recipientPhone.trim();
    }
    return shipment.phclient.trim();
  }

  LatLng? _shipmentStoreLatLng(Shipment shipment) {
    final lat = double.tryParse(shipment.latitude ?? '');
    final lng = double.tryParse(shipment.longitude ?? '');
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

  String _storeMapQueryFor(Shipment shipment) {
    final lat = double.tryParse(shipment.latitude ?? '');
    final lng = double.tryParse(shipment.longitude ?? '');
    if (lat != null && lng != null) {
      final storeLocation = _shipmentStoreLatLng(shipment);
      if (storeLocation != null) {
        return '${storeLocation.latitude},${storeLocation.longitude}';
      }
    }

    final storeAddress = _storeAddressFor(shipment);
    if (storeAddress.isNotEmpty) {
      return storeAddress;
    }

    if (shipment.nstore.trim().isNotEmpty) {
      return shipment.nstore.trim();
    }

    return '';
  }

  void _showSnack(
    String message, {
    Color backgroundColor = const Color(0xffDC2626),
  }) {
    final cleanMessage =
        message.trim().isEmpty
            ? _copy(context, 'Something went wrong.', 'حدث خطأ ما.')
            : message.trim();

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(cleanMessage),
          backgroundColor: backgroundColor,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      );
  }
}

class _InstantAccessRestricted extends StatelessWidget {
  const _InstantAccessRestricted({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(18, 20, 18, 110),
            sliver: SliverToBoxAdapter(
              child: Container(
                padding: const EdgeInsets.all(20),
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
                        Icons.workspace_premium_outlined,
                        color: AppColors.primary,
                        size: 30,
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
                    const SizedBox(height: 8),
                    Text(
                      message,
                      textAlign: TextAlign.center,
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
            ),
          ),
        ],
      ),
    );
  }
}

class _InstantHeader extends StatelessWidget {
  const _InstantHeader({required this.totalCount, required this.isLoading});

  final int totalCount;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primary, const Color(0xff063E7F)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
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
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
            ),
            child: const Icon(
              Icons.local_shipping_outlined,
              color: Colors.white,
              size: 27,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _copy(
                    context,
                    'Available Instant Shipments',
                    'الشحنات الفورية المتاحة',
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  _copy(
                    context,
                    'Review and accept instant delivery jobs.',
                    'راجع واقبل شحنات التوصيل الفورية.',
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.82),
                    fontSize: 12.5,
                    height: 1.25,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: [
                if (isLoading)
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: AppColors.primary,
                    ),
                  )
                else
                  Text(
                    '$totalCount',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                const SizedBox(height: 2),
                Text(
                  _copy(context, 'Jobs', 'شحنات'),
                  style: const TextStyle(
                    color: Color(0xff64748B),
                    fontSize: 10,
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

class _InstantListSectionHeader extends StatelessWidget {
  const _InstantListSectionHeader({required this.title, this.titleAr});

  final String title;
  final String? titleAr;

  @override
  Widget build(BuildContext context) {
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    return Text(
      isArabic ? (titleAr ?? title) : title,
      style: const TextStyle(
        color: Color(0xff0F172A),
        fontSize: 15,
        fontWeight: FontWeight.w900,
      ),
    );
  }
}

class _InstantSearchBar extends StatefulWidget {
  const _InstantSearchBar({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  State<_InstantSearchBar> createState() => _InstantSearchBarState();
}

class _InstantSearchBarState extends State<_InstantSearchBar> {
  @override
  void initState() {
    super.initState();
    // Only to show or hide the clear button; the query itself still travels
    // through onChanged and the provider's existing debounce.
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  void _onTextChanged() {
    if (mounted) setState(() {});
  }

  void _clear() {
    widget.controller.clear();
    widget.onChanged('');
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final query = controller.text;
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';

    return TextField(
      controller: controller,
      onChanged: widget.onChanged,
      textInputAction: TextInputAction.search,
      // A policy number reads left-to-right; anything else follows the page,
      // so an Arabic status search still types naturally.
      textDirection: identifierTextDirection(query),
      decoration: InputDecoration(
        hintText: _copy(
          context,
          'Search by policy number or status',
          'ابحث برقم الشحنة أو الحالة',
        ),
        suffixIcon:
            query.isEmpty
                ? null
                : IconButton(
                  icon: const Icon(Icons.close_rounded),
                  color: const Color(0xff64748B),
                  tooltip: isArabic ? 'مسح' : 'Clear',
                  onPressed: _clear,
                ),
        prefixIcon: Icon(Icons.search_rounded, color: AppColors.primary),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xffE2E8F0)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xffE2E8F0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: AppColors.primary, width: 1.4),
        ),
      ),
    );
  }
}

enum _InstantShipmentStage {
  beforeAccept,
  storePickup,
  arrivedAtStore,
  delivery,
}

class _PinnedActiveInstantCard extends StatelessWidget {
  const _PinnedActiveInstantCard({
    required this.shipment,
    required this.statusLabel,
    required this.stageLabel,
    required this.isBusy,
    required this.onStep,
    required this.onContinue,
    required this.onUpdateStatus,
  });

  final Shipment shipment;
  final String statusLabel;
  final String stageLabel;

  /// A request for this shipment is in flight.
  final bool isBusy;

  /// Runs the job's next step (see driverShipmentActionsFor). An accepted
  /// instant job leaves the list and lives only on this card, which used to
  /// offer nothing but Track — the driver had to find the step elsewhere.
  final ValueChanged<DriverShipmentStep> onStep;
  final VoidCallback onContinue;
  final VoidCallback onUpdateStatus;

  @override
  Widget build(BuildContext context) {
    final actions = driverShipmentActionsForShipment(shipment);
    final canOpenStatusSheet = driverStatusSheetCardLauncherIsVisible(shipment);
    final nextStep = actions.primary;
    final secondaryStep = actions.secondary;
    final createdLabel = _createdTimeLabel(
      context,
      shipment,
      showCreatedTime: true,
      showRelativeTime: true,
    );
    final chips = <_OperationalChipData>[
      _OperationalChipData(
        label: _copy(context, 'Shipment type', 'نوع الشحنة'),
        value: _deliveryTypeLabel(context, shipment),
        icon: Icons.bolt_rounded,
        color: AppColors.primary,
      ),
      _OperationalChipData(
        label: _copy(context, 'Shipment status', 'حالة الشحنة'),
        value: statusLabel,
        icon: Icons.fact_check_outlined,
        color: getStatusColor(_statusIdOf(shipment)),
      ),
      _OperationalChipData(
        label: _copy(context, 'Stage', 'المرحلة'),
        value: stageLabel,
        icon: Icons.timeline_outlined,
        color: AppColors.primary,
      ),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.18)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.10),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 4,
            width: 62,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.primary, AppColors.primary],
              ),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(height: 13),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppColors.primary, AppColors.primary],
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.bolt_rounded,
                  color: Colors.white,
                  size: 25,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _PinnedBadge(
                          label: _copy(
                            context,
                            'Your active instant shipment',
                            'شحنتك الفورية الحالية',
                          ),
                        ),
                        _PinnedBadge(
                          label: _copy(context, 'In progress', 'قيد التنفيذ'),
                          isMuted: true,
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _fallback(
                        shipment.policyNum,
                        _copy(context, 'No policy number', 'لا يوجد رقم شحنة'),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xff0F172A),
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      createdLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xff64748B),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _PinnedOperationalWrap(chips: chips),
          const SizedBox(height: 13),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xffEFF6FF),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xffBFDBFE)),
            ),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.route_outlined,
                    size: 16,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    driverNextStepHint(
                          context,
                          actions,
                          offersStatusUpdate: false,
                        ) ??
                        _copy(
                          context,
                          'Continue the active journey from here.',
                          'تابع رحلتك الحالية من هنا.',
                        ),
                    style: const TextStyle(
                      color: Color(0xff1E3A8A),
                      fontSize: 11.5,
                      height: 1.35,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 13),
          if (nextStep != null) ...[
            SizedBox(
              width: double.infinity,
              child: _PrimaryActionButton(
                key: driverStepKey(nextStep),
                label: driverStepLabel(context, nextStep),
                icon: driverStepIcon(nextStep),
                color:
                    nextStep == DriverShipmentStep.deliver
                        ? const Color(0xff16A06D)
                        : null,
                isLoading: isBusy,
                onTap: isBusy ? null : () => onStep(nextStep),
              ),
            ),
            const SizedBox(height: 10),
          ],
          // Pickup straight from 2, which the hint above mentions; the server
          // takes it, and it asks for confirmation (performDriverShipmentStep).
          if (secondaryStep != null) ...[
            SizedBox(
              width: double.infinity,
              child: _PrimaryActionButton(
                key: driverStepKey(secondaryStep),
                label: driverStepLabel(context, secondaryStep),
                icon: driverStepIcon(secondaryStep),
                isOutlined: true,
                onTap: isBusy ? null : () => onStep(secondaryStep),
              ),
            ),
            const SizedBox(height: 10),
          ],
          SizedBox(
            width: double.infinity,
            child: _PrimaryActionButton(
              label: _copy(context, 'Track Shipment', 'تتبع الشحنة'),
              icon: Icons.route_rounded,
              isOutlined: nextStep != null,
              onTap: onContinue,
            ),
          ),
          if (canOpenStatusSheet) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: _PrimaryActionButton(
                label: _copy(context, 'Update Status', 'تحديث الحالة'),
                icon: Icons.edit_note_rounded,
                isOutlined: true,
                onTap: isBusy ? null : onUpdateStatus,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PinnedBadge extends StatelessWidget {
  const _PinnedBadge({required this.label, this.isMuted = false});

  final String label;
  final bool isMuted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color:
            isMuted
                ? const Color(0xffEFF6FF)
                : AppColors.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color:
              isMuted
                  ? const Color(0xffBFDBFE)
                  : AppColors.primary.withValues(alpha: 0.18),
        ),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: AppColors.primary,
          fontSize: 10.5,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _PinnedOperationalWrap extends StatelessWidget {
  const _PinnedOperationalWrap({required this.chips});

  final List<_OperationalChipData> chips;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children:
          chips.map((chip) {
            return Container(
              constraints: const BoxConstraints(minWidth: 118, maxWidth: 168),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xffF8FAFC),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xffE2E8F0)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(chip.icon, color: chip.color, size: 17),
                  const SizedBox(width: 7),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          chip.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xff64748B),
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          chip.value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xff0F172A),
                            fontSize: 11.5,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
    );
  }
}

class _InstantShipmentCard extends StatelessWidget {
  const _InstantShipmentCard({
    required this.shipment,
    required this.statusLabel,
    required this.privacyProfile,
    required this.acceptLabel,
    required this.isAccepting,
    required this.onViewDetails,
    required this.onTrackShipment,
    required this.onStoreCall,
    required this.onStoreMap,
    required this.onCustomerCall,
    required this.onCustomerMap,
    required this.onAccept,
    required this.onArrivedAtStore,
    required this.onPickupFromStore,
    required this.onDeliver,
    required this.onUpdateStatus,
  });

  final Shipment shipment;
  final String statusLabel;
  final ShipmentPrivacyProfile privacyProfile;
  final String acceptLabel;
  final bool isAccepting;
  final VoidCallback onViewDetails;
  final VoidCallback onTrackShipment;
  final VoidCallback onStoreCall;
  final VoidCallback onStoreMap;
  final VoidCallback onCustomerCall;
  final VoidCallback onCustomerMap;
  final VoidCallback onAccept;
  final VoidCallback onArrivedAtStore;
  final VoidCallback onPickupFromStore;
  final VoidCallback onDeliver;
  final VoidCallback onUpdateStatus;

  @override
  Widget build(BuildContext context) {
    final stage = _stageForShipment(shipment);
    // In transit (4) the next step is Delivered; this card used to fall back
    // to View Details there.
    final canDeliver =
        driverShipmentActionsForShipment(shipment).primary ==
        DriverShipmentStep.deliver;
    final isBeforeAccept = stage == _InstantShipmentStage.beforeAccept;
    final isStoreStage =
        stage == _InstantShipmentStage.storePickup ||
        stage == _InstantShipmentStage.arrivedAtStore;
    final isDeliveryStage = stage == _InstantShipmentStage.delivery;
    final canOpenStatusSheet = driverStatusSheetCardLauncherIsVisible(shipment);
    final isInstantBeforeAccept =
        isBeforeAccept && shipment.deliveryTypeId == 1;
    final showPolicyNumber = privacyProfile.allows(
      'show_policy_number',
      defaultValue: true,
    );
    final showStatus = privacyProfile.allows('show_status', defaultValue: true);
    final showCreatedTime = privacyProfile.allows(
      'show_created_time',
      defaultValue: true,
    );
    final showRelativeTime = privacyProfile.allows(
      'show_relative_time',
      defaultValue: isBeforeAccept,
    );
    final showStore =
        isStoreStage ||
        (isDeliveryStage &&
            privacyProfile.allows('show_store', defaultValue: true));
    final showRecipient =
        isDeliveryStage &&
        privacyProfile.allows('show_recipient', defaultValue: true);
    final showPhone =
        isDeliveryStage &&
        privacyProfile.allows('show_phone', defaultValue: true);
    final showAddress =
        isDeliveryStage &&
        privacyProfile.allows('show_address', defaultValue: true);
    final showMap =
        isStoreStage ||
        (isDeliveryStage &&
            privacyProfile.allows('show_map', defaultValue: true));
    final showCosts =
        isDeliveryStage &&
        privacyProfile.allows('show_costs', defaultValue: true);
    final showAcceptButton = privacyProfile.allows(
      'show_accept_button',
      defaultValue: isBeforeAccept,
    );
    final storeName = _fallback(
      shipment.nstore.trim().isNotEmpty ? shipment.nstore : shipment.nclient,
      _copy(context, 'Store not available', 'المتجر غير متوفر'),
    );
    final storeAddress = _storeAddressFor(shipment);
    final storeLogoUrl = isBeforeAccept ? '' : _storeLogoUrlFor(shipment);
    final stageTitle =
        isBeforeAccept
            ? _copy(context, 'Available Shipment', 'شحنة متاحة')
            : stage == _InstantShipmentStage.storePickup
            ? _copy(context, 'Go to Store', 'توجه إلى المتجر')
            : stage == _InstantShipmentStage.arrivedAtStore
            ? _copy(context, 'Arrived at Store', 'تم الوصول إلى المتجر')
            : _copy(context, 'Delivery Details', 'تفاصيل التوصيل');
    final metricWidgets = <Widget>[
      // The server's product_to_collect: 0 on a prepaid shipment.
      if (showCosts)
        _MiniMetric(
          label:
              shipment.isPrepaid
                  ? _copy(
                    context,
                    'COD amount · Prepaid',
                    'مبلغ التحصيل · مدفوعة مسبقاً',
                  )
                  : _copy(context, 'COD amount', 'مبلغ التحصيل'),
          value: _moneyLabel(context, shipment.productToCollect),
          icon: Icons.payments_outlined,
        ),
      if (showCosts)
        _MiniMetric(
          label: _copy(context, 'Delivery cost', 'تكلفة التوصيل'),
          value: _moneyLabel(context, shipment.deliveryCost),
          icon: Icons.account_balance_wallet_outlined,
        ),
      if (showStore && isDeliveryStage)
        _MiniMetric(
          label: _copy(context, 'Store', 'المتجر'),
          value: storeName,
          icon: Icons.storefront_outlined,
        ),
    ];
    final operationalChips = _instantOperationalChips(
      context,
      shipment,
      statusLabel: statusLabel,
      stageLabel:
          isBeforeAccept
              ? _copy(context, 'Available to accept', 'متاحة للقبول')
              : stageTitle,
      includeStatus: isBeforeAccept ? true : showStatus,
      includeSensitive: isDeliveryStage,
    );
    final primaryAction =
        isBeforeAccept
            ? (showAcceptButton
                ? _PrimaryActionButton(
                  label: acceptLabel,
                  icon: Icons.done_rounded,
                  isLoading: isAccepting,
                  onTap:
                      isAccepting || !shipment.allowsAction('accept_shipment')
                          ? null
                          : onAccept,
                )
                : null)
            : stage == _InstantShipmentStage.storePickup
            ? _PrimaryActionButton(
              label: _copy(context, 'Arrived at Store', 'وصلت إلى المتجر'),
              icon: Icons.storefront_rounded,
              isLoading: isAccepting,
              onTap:
                  isAccepting || !shipment.allowsAction('arrive_at_pickup')
                      ? null
                      : onArrivedAtStore,
            )
            : stage == _InstantShipmentStage.arrivedAtStore
            ? _PrimaryActionButton(
              label: _copy(context, 'Picked Up Shipment', 'استلام الشحنة'),
              icon: Icons.inventory_2_rounded,
              isLoading: isAccepting,
              onTap:
                  isAccepting || !shipment.allowsAction('confirm_pickup')
                      ? null
                      : onPickupFromStore,
            )
            : canDeliver
            ? null
            : _PrimaryActionButton(
              label: _copy(context, 'View Details', 'عرض التفاصيل'),
              icon: Icons.receipt_long_outlined,
              isOutlined: true,
              onTap: onViewDetails,
            );
    // Delivered gets a full-width row of its own: beside the three square
    // actions of this stage it was cut to a few letters at 360dp.
    final deliverAction =
        canDeliver
            ? _PrimaryActionButton(
              key: driverStepKey(DriverShipmentStep.deliver),
              label: driverStepLabel(context, DriverShipmentStep.deliver),
              icon: driverStepIcon(DriverShipmentStep.deliver),
              color: const Color(0xff16A06D),
              isLoading: isAccepting,
              onTap: isAccepting ? null : onDeliver,
            )
            : null;
    final trackButton = _PrimaryActionButton(
      label: _copy(context, 'Track Shipment', 'تتبع الشحنة'),
      icon: Icons.route_rounded,
      isOutlined: true,
      onTap: onTrackShipment,
    );
    // Delivered took View Details' place, so the details move next to Track.
    final trackingAction =
        isBeforeAccept
            ? null
            : canDeliver
            ? Row(
              children: [
                Expanded(
                  child: _PrimaryActionButton(
                    label: _copy(context, 'View Details', 'عرض التفاصيل'),
                    icon: Icons.receipt_long_outlined,
                    isOutlined: true,
                    onTap: onViewDetails,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(child: trackButton),
              ],
            )
            : trackButton;
    final secondaryActions = <Widget>[
      if (isStoreStage && shipment.phclient.trim().isNotEmpty)
        _SquareAction(
          tooltip: _copy(context, 'Call', 'اتصال'),
          icon: Icons.call_outlined,
          onTap: onStoreCall,
        ),
      if (isStoreStage && showMap)
        _SquareAction(
          tooltip: _copy(context, 'Map', 'الخريطة'),
          icon: Icons.map_outlined,
          onTap: onStoreMap,
        ),
      if (showPhone)
        _SquareAction(
          tooltip: _copy(context, 'Call customer', 'اتصال بالعميل'),
          icon: Icons.call_outlined,
          onTap: onCustomerCall,
        ),
      if (showAddress)
        _SquareAction(
          tooltip: _copy(context, 'Customer map', 'خريطة العميل'),
          icon: Icons.map_outlined,
          onTap: onCustomerMap,
        ),
      if (canOpenStatusSheet)
        _SquareAction(
          tooltip: _copy(context, 'Update status', 'تحديث الحالة'),
          icon: Icons.edit_note_rounded,
          onTap: onUpdateStatus,
        ),
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _instantCardDecoration(isInstantBeforeAccept),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isInstantBeforeAccept) ...[
            const _InstantUrgencyHeader(),
            const SizedBox(height: 13),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color:
                      storeLogoUrl.isNotEmpty
                          ? Colors.white
                          : AppColors.primary.withValues(alpha: 0.09),
                  borderRadius: BorderRadius.circular(14),
                  border:
                      storeLogoUrl.isNotEmpty
                          ? Border.all(color: const Color(0xffE2E8F0))
                          : null,
                ),
                child:
                    storeLogoUrl.isNotEmpty
                        ? _StoreLogo(url: storeLogoUrl)
                        : Icon(
                          isInstantBeforeAccept
                              ? Icons.bolt_rounded
                              : isBeforeAccept || isStoreStage
                              ? Icons.storefront_rounded
                              : Icons.bolt_rounded,
                          color:
                              isInstantBeforeAccept
                                  ? const Color(0xffD97706)
                                  : AppColors.primary,
                          size: 23,
                        ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      stageTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.primary,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (stageTitle.isEmpty) ...[
                      Text(
                        _copy(context, 'Available Shipment', 'شحنة متاحة'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.primary,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                    ],
                    if (showPolicyNumber)
                      Builder(
                        builder: (context) {
                          final policy = _fallback(
                            shipment.policyNum,
                            _copy(
                              context,
                              'No policy number',
                              'لا يوجد رقم شحنة',
                            ),
                          );
                          return Text(
                            policy,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textDirection: identifierTextDirection(policy),
                            style: const TextStyle(
                              color: Color(0xff0F172A),
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                            ),
                          );
                        },
                      ),
                    if (showCreatedTime || showRelativeTime) ...[
                      const SizedBox(height: 4),
                      Text(
                        _createdTimeLabel(
                          context,
                          shipment,
                          showCreatedTime: showCreatedTime,
                          showRelativeTime: showRelativeTime,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xff64748B),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (showStatus)
                _StatusBadge(
                  label: statusLabel,
                  color: getStatusColor(_statusIdOf(shipment)),
                ),
            ],
          ),
          if (operationalChips.isNotEmpty) ...[
            const SizedBox(height: 12),
            _OperationalChipWrap(chips: operationalChips),
          ],
          if (isStoreStage) ...[
            const SizedBox(height: 15),
            _InfoRow(
              icon: Icons.storefront_outlined,
              label: _copy(context, 'Store', 'المتجر'),
              value: storeName,
            ),
            const SizedBox(height: 9),
            _InfoRow(
              icon: Icons.phone_outlined,
              label: _copy(context, 'Store phone', 'هاتف المتجر'),
              value: _fallback(
                shipment.phclient,
                _copy(context, 'Not available', 'غير متوفر'),
              ),
            ),
            const SizedBox(height: 9),
            _InfoRow(
              icon: Icons.place_outlined,
              label: _copy(context, 'Store address', 'عنوان المتجر'),
              value: _fallback(
                storeAddress,
                _storeLocationFallback(context, shipment),
              ),
              maxLines: 2,
            ),
          ],
          if (isBeforeAccept) ...[
            const SizedBox(height: 14),
            _DriverMatchingBanner(
              title: _copy(context, 'Available to accept', 'متاحة لك الآن'),
              subtitle: _copy(
                context,
                'Accept to view store details and start pickup.',
                'اقبل الشحنة لعرض تفاصيل المتجر وبدء الاستلام.',
              ),
            ),
          ],
          if (showRecipient || showPhone || showAddress) ...[
            const SizedBox(height: 15),
            if (showRecipient) ...[
              _InfoRow(
                icon: Icons.person_outline_rounded,
                label: _copy(context, 'Recipient', 'المستلم'),
                value: _fallback(
                  shipment.recipientName,
                  _copy(context, 'Not available', 'غير متوفر'),
                ),
              ),
            ],
            if (showRecipient && (showPhone || showAddress))
              const SizedBox(height: 9),
            if (showPhone) ...[
              _InfoRow(
                icon: Icons.phone_outlined,
                label: _copy(context, 'Phone', 'الهاتف'),
                value: _fallback(
                  shipment.recipientPhone,
                  _copy(context, 'Not available', 'غير متوفر'),
                ),
              ),
            ],
            if (showPhone && showAddress) const SizedBox(height: 9),
            if (showAddress)
              _InfoRow(
                icon: Icons.place_outlined,
                label: _copy(context, 'Address', 'العنوان'),
                value: _fallback(
                  shipment.deliveryAddress,
                  _copy(context, 'Not available', 'غير متوفر'),
                ),
                maxLines: 2,
              ),
          ],
          if (metricWidgets.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(spacing: 10, runSpacing: 10, children: metricWidgets),
          ],
          if (deliverAction != null) ...[
            const SizedBox(height: 14),
            SizedBox(width: double.infinity, child: deliverAction),
          ],
          if (primaryAction != null || secondaryActions.isNotEmpty) ...[
            SizedBox(height: deliverAction != null ? 10 : 14),
            Row(
              children: [
                if (primaryAction != null) Expanded(child: primaryAction),
                for (final action in secondaryActions) ...[
                  if (primaryAction != null || secondaryActions.first != action)
                    const SizedBox(width: 8),
                  action,
                ],
              ],
            ),
          ],
          if (trackingAction != null) ...[
            const SizedBox(height: 10),
            SizedBox(width: double.infinity, child: trackingAction),
          ],
        ],
      ),
    );
  }
}

int _effectiveStatusId(Shipment shipment) {
  return shipment.shipmentStatusId != 0
      ? shipment.shipmentStatusId
      : shipment.shipmentStatus;
}

_InstantShipmentStage _stageForShipment(Shipment shipment) {
  if (shipment.driverId == 0) return _InstantShipmentStage.beforeAccept;

  final statusId = _effectiveStatusId(shipment);
  if (statusId == 10) return _InstantShipmentStage.arrivedAtStore;
  if (const <int>{1, 2, 3}.contains(statusId)) {
    return _InstantShipmentStage.storePickup;
  }
  return _InstantShipmentStage.delivery;
}

String _instantStageLabel(BuildContext context, Shipment shipment) {
  return switch (_stageForShipment(shipment)) {
    _InstantShipmentStage.beforeAccept => _copy(
      context,
      'Available to accept',
      'متاحة للقبول',
    ),
    _InstantShipmentStage.storePickup => _copy(
      context,
      'Go to Store',
      'توجه إلى المتجر',
    ),
    _InstantShipmentStage.arrivedAtStore => _copy(
      context,
      'Arrived at Store',
      'تم الوصول إلى المتجر',
    ),
    _InstantShipmentStage.delivery => _copy(
      context,
      'Go to Customer',
      'توجه إلى العميل',
    ),
  };
}

List<_OperationalChipData> _instantOperationalChips(
  BuildContext context,
  Shipment shipment, {
  required String statusLabel,
  required String stageLabel,
  required bool includeStatus,
  required bool includeSensitive,
}) {
  final chips = <_OperationalChipData>[
    _OperationalChipData(
      label: _copy(context, 'Shipment type', 'نوع الشحنة'),
      value: _deliveryTypeLabel(context, shipment),
      icon: Icons.category_outlined,
      color: AppColors.primary,
    ),
    if (includeStatus)
      _OperationalChipData(
        label: _copy(context, 'Shipment status', 'حالة الشحنة'),
        value: statusLabel,
        icon: Icons.fact_check_outlined,
        color: getStatusColor(_statusIdOf(shipment)),
      ),
    _OperationalChipData(
      label: _copy(context, 'Stage', 'المرحلة'),
      value: stageLabel,
      icon: Icons.timeline_outlined,
      color: AppColors.primary,
    ),
  ];

  if (includeSensitive) {
    chips.addAll([
      _OperationalChipData(
        label: _copy(context, 'Return status', 'حالة المرتجع'),
        value: _returnStatusLabel(context, shipment),
        icon: Icons.assignment_return_outlined,
        color: _returnStatusColor(shipment),
      ),
      _OperationalChipData(
        label: _copy(context, 'Accounting status', 'حالة المحاسبة'),
        value: _accountingStatusLabel(context, shipment),
        icon: Icons.account_balance_wallet_outlined,
        color: _accountingStatusColor(shipment),
      ),
    ]);
  }

  return chips;
}

String _deliveryTypeLabel(BuildContext context, Shipment shipment) {
  final localized = _localizedValue(
    context,
    shipment.typeNameEn,
    shipment.typeNameAr,
  );
  if (localized.isNotEmpty) return localized;

  return switch (shipment.deliveryTypeId) {
    1 => _copy(context, 'Instant', 'فوري'),
    2 => _copy(context, 'Scheduled', 'مجدول'),
    3 => _copy(context, 'Same-Day', 'نفس اليوم'),
    4 => _copy(context, 'Next-Day', 'اليوم التالي'),
    5 => _copy(context, 'Economy', 'اقتصادي'),
    6 => _copy(context, 'Express', 'سريع'),
    7 => _copy(context, 'Contactless', 'بدون تلامس'),
    _ => _copy(context, 'Not available', 'غير متوفر'),
  };
}

String _returnStatusLabel(BuildContext context, Shipment shipment) {
  final returnCode = shipment.returnedShipment;
  final localized = _localizedValue(
    context,
    shipment.returnTypeNameEn,
    shipment.returnTypeNameAr,
  );
  if (returnCode != 0 && localized.isNotEmpty) return localized;
  if (_effectiveStatusId(shipment) == 8) {
    return _copy(context, 'Returned', 'مرتجع');
  }
  if (returnCode == 0) return _copy(context, 'No return', 'لا يوجد مرتجع');
  if (returnCode == 2) return _copy(context, 'Return requested', 'يوجد مرتجع');
  return _copy(context, 'Returned', 'مرتجع');
}

Color _returnStatusColor(Shipment shipment) {
  if (_effectiveStatusId(shipment) == 8 || shipment.returnedShipment != 0) {
    return const Color(0xffEF4444);
  }
  return const Color(0xff16A06D);
}

String _accountingStatusLabel(BuildContext context, Shipment shipment) {
  if (shipment.accountingShipment == 0) {
    return _copy(context, 'Non-accounting', 'غير محسوب');
  }
  if (shipment.accountingShipment == 1) {
    return _copy(context, 'Driver-accounting', 'محاسبة السائق');
  }
  return _copy(context, 'Client-accounting', 'محاسبة العملاء');
}

Color _accountingStatusColor(Shipment shipment) {
  if (shipment.accountingShipment == 0) return const Color(0xffF59E0B);
  if (shipment.accountingShipment == 1) return AppColors.primary;
  return const Color(0xff16A06D);
}

String _localizedValue(BuildContext context, String en, String ar) {
  final english = en.trim();
  final arabic = ar.trim();
  if (Localizations.localeOf(context).languageCode == 'ar' &&
      arabic.isNotEmpty) {
    return arabic;
  }
  if (english.isNotEmpty) return english;
  return arabic;
}

String _createdTimeLabel(
  BuildContext context,
  Shipment shipment, {
  required bool showCreatedTime,
  required bool showRelativeTime,
}) {
  final parts = <String>[];

  if (showCreatedTime) {
    parts.add(_shipmentDateLabel(context, shipment));
  }

  if (showRelativeTime) {
    final relative = _relativeTime(
      context,
      shipment.createdAtDateTime ?? shipment.shipmentDateTime,
    );
    if (relative.isNotEmpty) parts.add(relative);
  }

  if (parts.isEmpty) {
    return _copy(context, 'Date not available', 'التاريخ غير متوفر');
  }
  return parts.join(' · ');
}

String _relativeTime(BuildContext context, DateTime? parsed) {
  if (parsed == null) return '';

  final diff = DateTime.now().difference(parsed);
  if (diff.inMinutes < 1) {
    return _copy(context, 'just now', 'الآن');
  }
  if (diff.inHours < 1) {
    return _copy(
      context,
      '${diff.inMinutes} min ago',
      _arabicAgo(diff.inMinutes, 'دقيقة', 'دقيقتين', 'دقائق'),
    );
  }
  if (diff.inDays < 1) {
    return _copy(
      context,
      '${diff.inHours} hr ago',
      _arabicAgo(diff.inHours, 'ساعة', 'ساعتين', 'ساعات'),
    );
  }
  return _copy(
    context,
    '${diff.inDays} days ago',
    _arabicAgo(diff.inDays, 'يوم', 'يومين', 'أيام'),
  );
}

/// Arabic counts one, two and few differently. Just enough of it for a
/// relative timestamp — singular, dual, then the plural form up to ten, and
/// the singular again above that, which is how Arabic actually reads.
String _arabicAgo(int value, String one, String two, String few) {
  if (value == 1) return 'قبل $one';
  if (value == 2) return 'قبل $two';
  if (value <= 10) return 'قبل $value $few';
  return 'قبل $value $one';
}

String _storeAddressFor(Shipment shipment) {
  final address = shipment.lclient.trim();
  if (address.isEmpty || _looksLikeImagePath(address)) return '';
  return address;
}

String _storeLocationFallback(BuildContext context, Shipment shipment) {
  final lat = double.tryParse(shipment.latitude ?? '');
  final lng = double.tryParse(shipment.longitude ?? '');
  if (lat != null && lng != null && (lat != 0 || lng != 0)) {
    return _copy(
      context,
      'Open map to view store location',
      'افتح الخريطة لعرض موقع المتجر',
    );
  }
  return _copy(context, 'Not available', 'غير متوفر');
}

String _storeLogoUrlFor(Shipment shipment) {
  final candidates = <String>[shipment.loshop, shipment.lclient];
  for (final candidate in candidates) {
    final logoPath = candidate.trim();
    if (logoPath.isEmpty || !_looksLikeImagePath(logoPath)) continue;
    return Uri.encodeFull(_dashboardPublicUrl(logoPath));
  }
  return '';
}

String _dashboardPublicUrl(String path) {
  final cleanPath = path.trim();
  if (cleanPath.startsWith('http://') || cleanPath.startsWith('https://')) {
    return cleanPath;
  }

  final dashboardRoot = AppUrls.baseUrl.replaceFirst(
    RegExp(r'/services/?$'),
    '',
  );
  if (cleanPath.startsWith('/')) {
    return '$dashboardRoot$cleanPath';
  }
  return '$dashboardRoot/$cleanPath';
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

class _StoreLogo extends StatelessWidget {
  const _StoreLogo({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(5),
        child: Image.network(
          url,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) => _fallbackIcon(),
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return Center(
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 1.8,
                  color: AppColors.primary,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _fallbackIcon() {
    return Icon(Icons.storefront_rounded, color: AppColors.primary, size: 22);
  }
}

class _InstantUrgencyHeader extends StatelessWidget {
  const _InstantUrgencyHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: const Color(0xffFEF3C7),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: const Color(0xffF59E0B).withValues(alpha: 0.28),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.bolt_rounded,
                color: Color(0xffD97706),
                size: 15,
              ),
              const SizedBox(width: 5),
              Text(
                _copy(context, 'Instant Shipment', 'شحنة فورية'),
                style: const TextStyle(
                  color: Color(0xff92400E),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.16),
              ),
            ),
            child: Text(
              _copy(context, 'High Priority', 'أولوية عالية'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColors.primary,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _OperationalChipData {
  const _OperationalChipData({
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

class _OperationalChipWrap extends StatelessWidget {
  const _OperationalChipWrap({required this.chips});

  final List<_OperationalChipData> chips;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xffF8FBFF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.13)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.dashboard_customize_outlined,
                color: AppColors.primary,
                size: 17,
              ),
              const SizedBox(width: 7),
              Text(
                _copy(context, 'Shipment summary', 'ملخص الشحنة'),
                style: const TextStyle(
                  color: Color(0xff0F172A),
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children:
                chips.map((chip) => _OperationalChip(data: chip)).toList(),
          ),
        ],
      ),
    );
  }
}

class _OperationalChip extends StatelessWidget {
  const _OperationalChip({required this.data});

  final _OperationalChipData data;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 132, maxWidth: 236),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: data.color.withValues(alpha: 0.22)),
          boxShadow: [
            BoxShadow(
              color: data.color.withValues(alpha: 0.07),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: data.color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(data.icon, color: data.color, size: 16),
            ),
            const SizedBox(width: 8),
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
                      fontSize: 10,
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
                      fontSize: 12,
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

class _DriverMatchingBanner extends StatefulWidget {
  const _DriverMatchingBanner({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  State<_DriverMatchingBanner> createState() => _DriverMatchingBannerState();
}

class _DriverMatchingBannerState extends State<_DriverMatchingBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xffF8FBFF), Color(0xffEEF7FF)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                final dotLeft = 8.0 + (_controller.value * 14.0);
                final pulse =
                    _controller.value < .5
                        ? .92 + (_controller.value * .18)
                        : 1.10 - ((_controller.value - .5) * .18);

                return Stack(
                  alignment: Alignment.center,
                  children: [
                    Transform.scale(
                      scale: pulse,
                      child: Icon(
                        Icons.route_rounded,
                        color: AppColors.primary,
                        size: 18,
                      ),
                    ),
                    // Directional: the dot travels along the route icon, so in
                    // Arabic it has to travel the way Arabic reads.
                    PositionedDirectional(
                      start: dotLeft,
                      bottom: 7,
                      child: Container(
                        width: 5,
                        height: 5,
                        decoration: const BoxDecoration(
                          color: Color(0xff16A06D),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xff0F172A),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  widget.subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xff64748B),
                    fontSize: 10.8,
                    height: 1.25,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xffDCFCE7),
              borderRadius: BorderRadius.circular(99),
              border: Border.all(color: const Color(0xffBBF7D0)),
            ),
            child: Text(
              _copy(context, 'Ready', 'جاهزة'),
              maxLines: 1,
              style: const TextStyle(
                color: Color(0xff15803D),
                fontSize: 10,
                fontWeight: FontWeight.w900,
              ),
            ),
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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: AppColors.primary),
        const SizedBox(width: 9),
        Expanded(
          child: RichText(
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
            text: TextSpan(
              style: const TextStyle(
                color: Color(0xff334155),
                fontSize: 12.5,
                height: 1.3,
              ),
              children: [
                TextSpan(
                  text: '$label: ',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                TextSpan(
                  text: isolateIdentifier(value),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
      ],
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
      width: 148,
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
            maxLines: 1,
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

class _PrimaryActionButton extends StatelessWidget {
  const _PrimaryActionButton({
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

  /// Fill colour of a solid button; the app primary when null.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final fill = color ?? AppColors.primary;
    return SizedBox(
      height: 46,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon:
            isLoading
                ? const SizedBox(
                  width: 17,
                  height: 17,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: Colors.white,
                  ),
                )
                : Icon(icon, size: 18),
        label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        style: ElevatedButton.styleFrom(
          backgroundColor: isOutlined ? Colors.white : fill,
          foregroundColor: isOutlined ? AppColors.primary : Colors.white,
          disabledBackgroundColor: fill.withValues(alpha: 0.72),
          disabledForegroundColor: Colors.white,
          elevation: 0,
          side: BorderSide(
            color:
                isOutlined
                    ? AppColors.primary.withValues(alpha: 0.22)
                    : Colors.transparent,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
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

class _InstantErrorCard extends StatelessWidget {
  const _InstantErrorCard({required this.message, required this.onRetry});

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

class _InstantEmptyState extends StatelessWidget {
  const _InstantEmptyState({required this.title, required this.message});

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

class _InstantLoadingList extends StatelessWidget {
  const _InstantLoadingList();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(
        3,
        (index) => Container(
          height: 176,
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(16),
          decoration: _cardDecoration(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              ),
              const Spacer(),
              const _LoadingLine(width: 150),
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

BoxDecoration _instantCardDecoration(bool isInstantBeforeAccept) {
  if (!isInstantBeforeAccept) return _cardDecoration();

  return BoxDecoration(
    gradient: const LinearGradient(
      colors: [Color(0xffFFFFFF), Color(0xffF8FBFF), Color(0xffFFF7ED)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    borderRadius: BorderRadius.circular(18),
    border: Border.all(color: const Color(0xffF59E0B).withValues(alpha: 0.34)),
    boxShadow: [
      BoxShadow(
        color: const Color(0xffF59E0B).withValues(alpha: 0.10),
        blurRadius: 20,
        offset: const Offset(0, 9),
      ),
      BoxShadow(
        color: AppColors.primary.withValues(alpha: 0.05),
        blurRadius: 16,
        offset: const Offset(0, 6),
      ),
    ],
  );
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

/// The locale MaterialApp resolved — the same source Login, the hub and the
/// assigned list read, and the one Directionality and the theme font are built
/// from.
///
/// The Arabic argument is used as given. A lookup table used to shadow it,
/// keyed by the English sentence, which made every inline Arabic string at the
/// call sites dead and let the two copies drift apart.
String _copy(BuildContext context, String en, String ar) {
  return Localizations.localeOf(context).languageCode == 'ar' ? ar : en;
}

/// The authoritative status id, preferring the dedicated column.
int _statusIdOf(Shipment shipment) {
  return shipment.shipmentStatusId != 0
      ? shipment.shipmentStatusId
      : shipment.shipmentStatus;
}

/// Currency first in English, amount first in Arabic, two decimals always —
/// the same presentation as the assigned list. The value is untouched.
String _moneyLabel(BuildContext context, double value) {
  final amount = value.toStringAsFixed(2);
  return _copy(context, 'JOD $amount', '$amount دينار أردني');
}

/// A date the driver can trust, or a localized placeholder.
///
/// Never the raw column: this card used to print `2026-01-15 10:30:00`
/// verbatim, and MySQL's zero date with it. Pinned to `en` digits so the date
/// matches the money, phone and page numbers elsewhere on the card.
String _shipmentDateLabel(BuildContext context, Shipment shipment) {
  final date = shipment.createdAtDateTime ?? shipment.shipmentDateTime;
  if (date == null) {
    return _copy(context, 'Date not available', 'التاريخ غير متوفر');
  }
  return DateFormat('dd/MM/yyyy', 'en').format(date);
}

bool _canViewInstantShipments(dynamic profile) {
  if (profile == null) return false;
  return profile.status == 0 && profile.subscription == 1;
}
