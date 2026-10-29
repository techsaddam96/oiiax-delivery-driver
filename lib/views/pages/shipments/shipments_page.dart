import 'dart:async';

import 'package:blockatie/constants/colors.dart';
import 'package:blockatie/models/shipment.dart';
import 'package:blockatie/provider/bottom_nav.dart';
import 'package:blockatie/provider/driver_shipment_sections.dart';
import 'package:blockatie/provider/home.dart';
import 'package:blockatie/provider/shipment_instsnt.dart';
import 'package:blockatie/utils/driver_shipment_actions.dart';
import 'package:blockatie/utils/nav.dart';
import 'package:blockatie/views/pages/home/components/header.dart';
import 'package:blockatie/views/pages/home/tabs/all-shipments/table_all_shipment.dart';
import 'package:blockatie/views/pages/orders/order_details.dart';
import 'package:blockatie/views/widgets/driver_chat_bubble.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

/// Shows three server-defined, mutually exclusive operational categories.
/// Category membership, custody and finality are never reconstructed in Flutter.
class ShipmentSectionPage extends StatefulWidget {
  const ShipmentSectionPage({super.key});

  @override
  State<ShipmentSectionPage> createState() => _ShipmentSectionPageState();
}

class _ShipmentSectionPageState extends State<ShipmentSectionPage>
    with WidgetsBindingObserver {
  DriverShipmentSection _selected = DriverShipmentSection.activeWork;
  final _search = TextEditingController();
  final Set<int> _accepting = <int>{};
  bool _wasCoveredByOverlay = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_refresh());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _search.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) unawaited(_refresh());
  }

  Future<void> _refresh() =>
      context.read<DriverShipmentSectionsProvider>().refreshAll();

  void _select(DriverShipmentSection section) {
    if (_selected == section) return;
    final query =
        context
            .read<DriverShipmentSectionsProvider>()
            .stateFor(section)
            .searchQuery;
    setState(() {
      _selected = section;
      _search.value = TextEditingValue(
        text: query,
        selection: TextSelection.collapsed(offset: query.length),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final sections = context.watch<DriverShipmentSectionsProvider>();
    final navigation = context.watch<BottomNavProvider>();
    final showAvailable = sections.canShowAvailableInstantOffers;
    final isCovered = navigation.overlayPage != null;
    if (_wasCoveredByOverlay && !isCovered) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_refresh());
      });
    }
    _wasCoveredByOverlay = isCovered;

    if (_selected == DriverShipmentSection.availableInstant && !showAvailable) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _selected == DriverShipmentSection.availableInstant) {
          _select(DriverShipmentSection.activeWork);
        }
      });
    }
    final selected =
        showAvailable || _selected != DriverShipmentSection.availableInstant
            ? _selected
            : DriverShipmentSection.activeWork;
    final state = sections.stateFor(selected);
    final ar = Localizations.localeOf(context).languageCode == 'ar';

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: const Color(0xffF4F7FB),
      body: SafeArea(
        child: Column(
          children: [
            HomeHeader(
              title: ar ? 'الشحنات' : 'Shipments',
              subtitle: ar ? 'حسب حالة العمل' : 'By operational status',
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
              child: _Selector(
                selected: selected,
                showAvailable: showAvailable,
                onSelected: _select,
              ),
            ),
            if (!showAvailable)
              _AvailabilityNotice(
                pending: sections.availabilityVerificationPending,
                failed: sections.availabilityVerificationFailed,
                activeWork: sections.hasActiveOperationalWork,
                onRetry: () => unawaited(_refresh()),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 4),
              child: TextField(
                key: ValueKey('shipment-search-${selected.wireValue}'),
                controller: _search,
                onChanged: (value) => sections.setSearchQuery(selected, value),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search_rounded),
                  hintText: ar ? 'البحث في الشحنات' : 'Search shipments',
                  filled: true,
                  fillColor: Colors.white,
                  border: _inputBorder(),
                  enabledBorder: _inputBorder(),
                ),
              ),
            ),
            Expanded(
              child: _List(
                state: state,
                onRefresh: _refresh,
                onPage: (page) => sections.setPage(selected, page),
                onDetails: _details,
                onCall: _call,
                onMap: _openMap,
                onStep: _step,
                onAccept:
                    selected == DriverShipmentSection.availableInstant
                        ? _accept
                        : null,
                accepting: _accepting,
              ),
            ),
          ],
        ),
      ),
    );
  }

  OutlineInputBorder _inputBorder() => OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: const BorderSide(color: Color(0xffE2E8F0)),
  );

  void _details(Shipment shipment) {
    final prePickup = driverShipmentIsPrePickup(shipment);
    Nav.to(
      OrderDetailPage(
        shipment: shipment,
        shipmentId: shipment.id,
        isInstantFlow: shipment.deliveryTypeId == 1,
        phoneCustomer: prePickup ? shipment.phclient : shipment.recipientPhone,
        deliveryAdd: prePickup ? shipment.lclient : shipment.deliveryAddress,
        storeAdd: shipment.nstore,
        orderDate: shipment.createdAt,
      ),
      withNav: true,
      navIndex: 1,
    );
  }

  Future<void> _call(Shipment shipment) async {
    final prePickup = driverShipmentIsPrePickup(shipment);
    final phone =
        (prePickup ? shipment.phclient : shipment.recipientPhone).trim();
    if (phone.isEmpty) {
      _showSnack(
        Localizations.localeOf(context).languageCode == 'ar'
            ? 'رقم الهاتف غير متوفر.'
            : 'Phone number is not available.',
      );
      return;
    }
    final launched = await launchUrl(
      Uri.parse('tel:$phone'),
      mode: LaunchMode.externalApplication,
    );
    if (!mounted || launched) return;
    _showSnack(
      Localizations.localeOf(context).languageCode == 'ar'
          ? 'تعذر بدء الاتصال.'
          : 'Unable to start call.',
    );
  }

  Future<void> _openMap(Shipment shipment) async {
    final prePickup = driverShipmentIsPrePickup(shipment);
    final latitude = double.tryParse(
      prePickup ? shipment.latitude ?? '' : shipment.deliveryLatitude ?? '',
    );
    final longitude = double.tryParse(
      prePickup ? shipment.longitude ?? '' : shipment.deliveryLongitude ?? '',
    );
    final fallback =
        (prePickup ? shipment.lclient : shipment.deliveryAddress).trim();
    final query =
        latitude != null && longitude != null && latitude != 0 && longitude != 0
            ? '$latitude,$longitude'
            : fallback;
    if (query.isEmpty) {
      _showSnack(
        Localizations.localeOf(context).languageCode == 'ar'
            ? 'الموقع غير متوفر.'
            : 'Location is not available.',
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
    _showSnack(
      Localizations.localeOf(context).languageCode == 'ar'
          ? 'تعذر فتح الخريطة.'
          : 'Unable to open map.',
    );
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _step(Shipment shipment, DriverShipmentStep step) async {
    final result = await performDriverShipmentStep(
      context,
      shipment: shipment,
      step: step,
    );
    if (!mounted || result == null || result.code == 'SESSION_CHANGED') return;
    _showResult(result);
    // Never optimistically change a status, ownership, or available-offer
    // capability. The new category contract owns the next display.
    await _refresh();
    if (result.success && step == DriverShipmentStep.deliver && mounted) {
      unawaited(
        context.read<HomeProvider>().getDriverStatistics(context, force: true),
      );
    }
  }

  Future<void> _accept(Shipment shipment) async {
    if (!shipment.allowsAction('accept_shipment') ||
        shipment.id <= 0 ||
        _accepting.contains(shipment.id)) {
      return;
    }
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (dialog) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
            ),
            title: Text(ar ? 'قبول الشحنة؟' : 'Accept shipment?'),
            content: Text(
              ar
                  ? 'سيتم إسناد هذه الشحنة إلى حساب السائق الخاص بك.'
                  : 'This shipment will be assigned to your driver account.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialog, false),
                child: Text(ar ? 'إلغاء' : 'Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(dialog, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
                child: Text(ar ? 'قبول' : 'Accept'),
              ),
            ],
          ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _accepting.add(shipment.id));
    final result = await context.read<ShipmentInstantprovider>().acceptShipment(
      shipment.id,
      acceptedShipment: shipment,
      languageCode: ar ? 'ar' : 'en',
    );
    if (!mounted) return;
    setState(() => _accepting.remove(shipment.id));
    _showResult(result);
    // Only a confirmed accept can move the row. A refusal is also reconciled,
    // because another driver/admin may have changed its ownership.
    await _refresh();
  }

  void _showResult(ShipmentActionResult result) {
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    final fallback =
        result.success
            ? (ar ? 'تم تحديث الشحنة.' : 'Shipment updated.')
            : (ar ? 'تعذر تحديث الشحنة.' : 'Unable to update shipment.');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.message.trim().isEmpty ? fallback : result.message,
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor:
            result.success ? const Color(0xff16803C) : const Color(0xffB91C1C),
      ),
    );
  }
}

class _Selector extends StatelessWidget {
  const _Selector({
    required this.selected,
    required this.showAvailable,
    required this.onSelected,
  });

  final DriverShipmentSection selected;
  final bool showAvailable;
  final ValueChanged<DriverShipmentSection> onSelected;

  @override
  Widget build(BuildContext context) {
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    final choices = <DriverShipmentSection>[
      DriverShipmentSection.activeWork,
      DriverShipmentSection.history,
      if (showAvailable) DriverShipmentSection.availableInstant,
    ];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xffE1E8F2)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children:
            choices
                .map(
                  (choice) => ChoiceChip(
                    key: ValueKey('shipment-section-${choice.wireValue}'),
                    selected: selected == choice,
                    showCheckmark: false,
                    side: BorderSide.none,
                    selectedColor: AppColors.primary,
                    backgroundColor: Colors.transparent,
                    label: Text(driverShipmentSectionLabel(choice, ar)),
                    labelStyle: TextStyle(
                      color:
                          selected == choice
                              ? Colors.white
                              : const Color(0xff475569),
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                    onSelected: (_) => onSelected(choice),
                  ),
                )
                .toList(),
      ),
    );
  }
}

class _AvailabilityNotice extends StatelessWidget {
  const _AvailabilityNotice({
    required this.pending,
    required this.failed,
    required this.activeWork,
    required this.onRetry,
  });

  final bool pending;
  final bool failed;
  final bool activeWork;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    final text =
        pending
            ? (ar
                ? 'جارٍ التحقق من الشحنات المتاحة للاستلام…'
                : 'Checking available shipments…')
            : failed
            ? (ar
                ? 'تعذر التحقق من الشحنات المتاحة. حاول مرة أخرى.'
                : 'Unable to verify available shipments. Try again.')
            : activeWork
            ? (ar
                ? 'أكمل الشحنات الحالية لعرض الشحنات المتاحة للاستلام.'
                : 'Finish current work to view available shipments.')
            : (ar
                ? 'لم يتم التحقق من الشحنات المتاحة بعد.'
                : 'Available shipments have not been verified yet.');
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 4),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: pending ? const Color(0xffEFF6FF) : const Color(0xffF8FAFC),
          border: Border.all(color: const Color(0xffD7E5F4)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            if (pending)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              const Icon(
                Icons.info_outline_rounded,
                size: 18,
                color: Color(0xff475569),
              ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                  color: Color(0xff475569),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (failed)
              TextButton(
                onPressed: onRetry,
                child: Text(ar ? 'إعادة المحاولة' : 'Retry'),
              ),
          ],
        ),
      ),
    );
  }
}

class _List extends StatelessWidget {
  const _List({
    required this.state,
    required this.onRefresh,
    required this.onPage,
    required this.onDetails,
    required this.onCall,
    required this.onMap,
    required this.onStep,
    required this.onAccept,
    required this.accepting,
  });

  final DriverShipmentSectionState state;
  final Future<void> Function() onRefresh;
  final ValueChanged<int> onPage;
  final ValueChanged<Shipment> onDetails;
  final Future<void> Function(Shipment) onCall;
  final Future<void> Function(Shipment) onMap;
  final Future<void> Function(Shipment, DriverShipmentStep) onStep;
  final Future<void> Function(Shipment)? onAccept;
  final Set<int> accepting;

  @override
  Widget build(BuildContext context) {
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    final children = <Widget>[
      _ListHeader(
        title: driverShipmentSectionLabel(state.section, ar),
        total: state.total,
        loading: state.isLoading && !state.hasLoaded,
      ),
      const SizedBox(height: 16),
    ];
    if (state.isLoading && !state.hasLoaded) {
      children.add(const _Loading());
    } else if (state.hasError && !state.hasLoaded) {
      children.add(
        _Retry(message: _failureText(state.failure, ar), onRetry: onRefresh),
      );
    } else if (state.hasError && state.shipments.isEmpty) {
      // Do not call an unavailable category an empty one. In particular, a
      // failed Available-for-Acceptance read must never render the zero-offer
      // copy, because the app did not receive proof of that result.
      children.add(
        _Retry(message: _failureText(state.failure, ar), onRetry: onRefresh),
      );
    } else if (state.shipments.isEmpty) {
      children.add(_Empty(section: state.section));
    } else {
      if (state.hasError) {
        children.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _Retry(
              message: _failureText(state.failure, ar),
              onRetry: onRefresh,
            ),
          ),
        );
      }
      children.addAll(
        state.shipments.map((shipment) {
          final offer = state.section == DriverShipmentSection.availableInstant;
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child:
                offer
                    ? _Card(
                      shipment: shipment,
                      offer: true,
                      accepting: accepting.contains(shipment.id),
                      onDetails: () => onDetails(shipment),
                      onStep: (step) => onStep(shipment, step),
                      onAccept:
                          onAccept == null ? null : () => onAccept!(shipment),
                    )
                    : DriverAssignedShipmentCard(
                      shipment: shipment,
                      statusLabel:
                          ar ? shipment.statusNameAr : shipment.statusNameEn,
                      showDetails: driverShipmentDetailsCardLauncherIsVisible(
                        shipment,
                      ),
                      onViewDetails: () => onDetails(shipment),
                      onCall: () => onCall(shipment),
                      onMap: () => onMap(shipment),
                      // Details remains the shared, contract-gated entry to
                      // the action sheet. Do not restore the legacy list
                      // launcher, which could bypass its fresh-state gate.
                      onUpdateStatus: null,
                      onStep: (step) => onStep(shipment, step),
                    ),
          );
        }),
      );
      if (state.totalPages > 1) {
        children.add(_Pager(state: state, onPage: onPage));
      }
    }
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: onRefresh,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        slivers: [
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              18,
              12,
              18,
              DriverChatBubble.reservedBottomSpace + 18,
            ),
            sliver: SliverList(delegate: SliverChildListDelegate(children)),
          ),
        ],
      ),
    );
  }
}

class _ListHeader extends StatelessWidget {
  const _ListHeader({
    required this.title,
    required this.total,
    required this.loading,
  });
  final String title;
  final int total;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, AppColors.gradient2],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .14),
              borderRadius: BorderRadius.circular(12),
            ),
            child:
                loading
                    ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                    : Column(
                      children: [
                        Text(
                          '$total',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          ar ? 'المجموع' : 'Total',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: .76),
                            fontSize: 9,
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

class _Card extends StatelessWidget {
  const _Card({
    required this.shipment,
    required this.offer,
    required this.accepting,
    required this.onDetails,
    required this.onStep,
    required this.onAccept,
  });
  final Shipment shipment;
  final bool offer;
  final bool accepting;
  final VoidCallback onDetails;
  final ValueChanged<DriverShipmentStep> onStep;
  final VoidCallback? onAccept;

  @override
  Widget build(BuildContext context) {
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    final prePickup = driverShipmentIsPrePickup(shipment);
    final actions = driverShipmentActionsForShipment(shipment);
    final policy =
        shipment.policyNum.trim().isEmpty
            ? '#${shipment.id}'
            : shipment.policyNum.trim();
    final status = ar ? shipment.statusNameAr : shipment.statusNameEn;
    final title =
        prePickup ? (ar ? 'المتجر' : 'Store') : (ar ? 'المستلم' : 'Recipient');
    final person =
        prePickup ? shipment.nstore.trim() : shipment.recipientName.trim();
    final address =
        prePickup ? shipment.lclient.trim() : shipment.deliveryAddress.trim();
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color:
              offer
                  ? const Color(0xffF59E0B).withValues(alpha: .42)
                  : const Color(0xffE2E8F0),
        ),
      ),
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
                      ar ? 'رقم الشحنة' : 'Policy number',
                      style: const TextStyle(
                        color: Color(0xff64748B),
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      policy,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textDirection: TextDirection.ltr,
                      style: const TextStyle(
                        color: Color(0xff0F172A),
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              if (status.trim().isNotEmpty)
                Container(
                  constraints: const BoxConstraints(maxWidth: 130),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: .09),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    status,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (offer)
            Text(
              ar
                  ? 'متاحة للقبول وفق صلاحية الخادم.'
                  : 'Available to accept when authorized by the server.',
              style: const TextStyle(
                color: Color(0xff64748B),
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            )
          else ...[
            _Info(
              icon:
                  prePickup
                      ? Icons.storefront_outlined
                      : Icons.person_outline_rounded,
              label: title,
              value:
                  person.isEmpty
                      ? (ar ? 'غير متوفر' : 'Not available')
                      : person,
            ),
            if (address.isNotEmpty) ...[
              const SizedBox(height: 8),
              _Info(
                icon: Icons.place_outlined,
                label:
                    prePickup
                        ? (ar ? 'عنوان المتجر' : 'Store address')
                        : (ar ? 'العنوان' : 'Address'),
                value: address,
                lines: 2,
              ),
            ],
          ],
          const SizedBox(height: 14),
          if (offer)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                key: ValueKey('accept-offer-${shipment.id}'),
                onPressed: onAccept == null || accepting ? null : onAccept,
                icon:
                    accepting
                        ? const SizedBox(
                          width: 17,
                          height: 17,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                        : const Icon(Icons.assignment_turned_in_outlined),
                label: Text(ar ? 'قبول الشحنة' : 'Accept Shipment'),
                style: _buttonStyle(AppColors.primary),
              ),
            )
          else ...[
            if (actions.primary != null) ...[
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  key: driverStepKey(actions.primary!),
                  onPressed: () => onStep(actions.primary!),
                  icon: Icon(driverStepIcon(actions.primary!)),
                  label: Text(driverStepLabel(context, actions.primary!)),
                  style: _buttonStyle(
                    actions.primary == DriverShipmentStep.deliver
                        ? const Color(0xff16803C)
                        : AppColors.primary,
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onDetails,
                icon: const Icon(Icons.open_in_new_rounded),
                label: Text(ar ? 'التفاصيل والإجراءات' : 'Details & actions'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: BorderSide(
                    color: AppColors.primary.withValues(alpha: .3),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(13),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  ButtonStyle _buttonStyle(Color color) => ElevatedButton.styleFrom(
    backgroundColor: color,
    foregroundColor: Colors.white,
    padding: const EdgeInsets.symmetric(vertical: 12),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
  );
}

class _Info extends StatelessWidget {
  const _Info({
    required this.icon,
    required this.label,
    required this.value,
    this.lines = 1,
  });
  final IconData icon;
  final String label;
  final String value;
  final int lines;
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, color: AppColors.primary, size: 17),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          '$label: $value',
          maxLines: lines,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Color(0xff334155),
            fontSize: 12,
            height: 1.3,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ],
  );
}

class _Pager extends StatelessWidget {
  const _Pager({required this.state, required this.onPage});
  final DriverShipmentSectionState state;
  final ValueChanged<int> onPage;
  @override
  Widget build(BuildContext context) {
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    return Row(
      children: [
        OutlinedButton.icon(
          onPressed:
              state.isLoading || state.page <= 1
                  ? null
                  : () => onPage(state.page - 1),
          icon: const Icon(Icons.chevron_left_rounded),
          label: Text(ar ? 'السابق' : 'Previous'),
        ),
        Expanded(
          child: Text(
            '${ar ? 'صفحة' : 'Page'} ${state.page} / ${state.totalPages}',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xff64748B),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        OutlinedButton.icon(
          onPressed:
              state.isLoading || state.page >= state.totalPages
                  ? null
                  : () => onPage(state.page + 1),
          icon: const Icon(Icons.chevron_right_rounded),
          label: Text(ar ? 'التالي' : 'Next'),
        ),
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.section});
  final DriverShipmentSection section;
  @override
  Widget build(BuildContext context) {
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    final title = driverShipmentSectionEmptyTitle(section, ar);
    final message =
        section == DriverShipmentSection.availableInstant
            ? (ar
                ? 'ستظهر هنا الشحنات الفورية المؤهلة عند توفرها.'
                : 'Eligible instant shipments will appear here when available.')
            : (ar ? 'اسحب للتحديث.' : 'Pull down to refresh.');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xffE2E8F0)),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          Icon(Icons.inventory_2_outlined, color: AppColors.primary, size: 32),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xff0F172A),
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xff64748B), fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _Retry extends StatelessWidget {
  const _Retry({required this.message, required this.onRetry});
  final String message;
  final Future<void> Function() onRetry;
  @override
  Widget build(BuildContext context) {
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: const Color(0xffFFF7ED),
        border: Border.all(color: const Color(0xffFDBA74)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(Icons.wifi_off_rounded, color: Color(0xffC2410C)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xff9A3412),
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          TextButton(
            onPressed: () => unawaited(onRetry()),
            child: Text(ar ? 'إعادة المحاولة' : 'Retry'),
          ),
        ],
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();
  @override
  Widget build(BuildContext context) => Column(
    children: List.generate(
      3,
      (_) => Container(
        height: 154,
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
      ),
    ),
  );
}

@visibleForTesting
String driverShipmentSectionLabel(DriverShipmentSection section, bool ar) =>
    switch (section) {
      DriverShipmentSection.activeWork =>
        ar ? 'المتاحة والمسندة' : 'Available & Assigned',
      DriverShipmentSection.history => ar ? 'سجل الشحنات' : 'Shipment History',
      DriverShipmentSection.availableInstant =>
        ar ? 'المتاحة للاستلام' : 'Available for Acceptance',
    };

@visibleForTesting
String driverShipmentSectionEmptyTitle(
  DriverShipmentSection section,
  bool ar,
) => switch (section) {
  DriverShipmentSection.availableInstant =>
    ar ? 'لا توجد شحنات متاحة حاليًا' : 'No shipments available right now',
  DriverShipmentSection.activeWork =>
    ar ? 'لا توجد شحنات حالية' : 'No current shipments',
  DriverShipmentSection.history =>
    ar ? 'لا يوجد سجل شحنات' : 'No shipment history',
};

String _failureText(DriverShipmentSectionFailure? failure, bool ar) {
  if (failure == DriverShipmentSectionFailure.network) {
    return ar
        ? 'لا يوجد اتصال. تحقق من الشبكة ثم حاول مرة أخرى.'
        : 'No connection. Check your network and try again.';
  }
  if (failure == DriverShipmentSectionFailure.contract) {
    return ar
        ? 'تعذر التحقق من بيانات الشحنات. حاول مرة أخرى.'
        : 'Unable to verify shipment data. Try again.';
  }
  return ar
      ? 'تعذر تحميل الشحنات. حاول مرة أخرى.'
      : 'Unable to load shipments. Try again.';
}
