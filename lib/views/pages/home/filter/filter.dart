import 'package:blockatie/constants/colors.dart';
import 'package:blockatie/models/client.dart';
import 'package:blockatie/provider/filter.dart';
import 'package:blockatie/utils/nav.dart';
import 'package:blockatie/utils/size_config.dart';
import 'package:blockatie/utils/spacing.dart';
import 'package:blockatie/views/bottmsheets/calander_sheet.dart';
import 'package:blockatie/views/pages/home/components/order_tile.dart';
import 'package:blockatie/views/pages/home/filter/components/status_btn_widget.dart';
import 'package:blockatie/views/pages/hub/support&assistance/support_assistence.dart';
import 'package:blockatie/views/pages/orders/order_details.dart';
import 'package:blockatie/utils/text_direction.dart';
import 'package:blockatie/views/widgets/cutom-appbar.dart';
import 'package:blockatie/views/widgets/driver_chat_bubble.dart';
import 'package:blockatie/views/widgets/status_update_sheet.dart';
import 'package:blockatie/views/widgets/textfiled_widget.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';

class FilterPage extends StatefulWidget {
  const FilterPage({super.key});

  @override
  State<FilterPage> createState() => _FilterPageState();
}

class _FilterPageState extends State<FilterPage> {
  late final FilterProvider provider;

  bool get _isArabic => Localizations.localeOf(context).languageCode == 'ar';

  /// App-owned copy. The provider returns states and ids; every sentence on
  /// this screen is written here, in the locale MaterialApp resolved.
  String _t(String ar, String en) => _isArabic ? ar : en;

  @override
  void initState() {
    super.initState();
    // The page's own context, not the root navigator's.
    provider = context.read<FilterProvider>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      provider.getStatusShipment();
      provider.getClients();
    });
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: CustomAppBar(
        title: _t('تصفية', 'Filter'),
        // Kept short on purpose: the shared app bar is a fixed 90px, and a
        // subtitle that wraps to a second line overflows it. The Arabic
        // wording here ran to two lines and cost 15px.
        subtitle: _t(
          'حسب التاريخ والحالة والمتجر',
          'Filter by date, status and store',
        ),
        onHelp: () {
          Nav.to(const SupportAssistencePage());
        },
        showBtn: true,
        onBack: Nav.back,
      ),
      backgroundColor: AppColors.bgColor,
      body: Consumer<FilterProvider>(
        builder: (context, filterProvider, child) {
          return _buildFilterForm(context, textTheme, filterProvider);
        },
      ),
    );
  }

  Future<void> _applyFilter() async {
    FocusScope.of(context).unfocus();
    await provider.filterShipment();
  }

  /// The status chips, or the state they are in.
  ///
  /// The list used to be force-unwrapped, so the first build — before the fetch
  /// returned — threw on a null. A failure is now a failure with a retry, never
  /// an empty set of options.
  Widget _buildStatusOptions(FilterProvider filterProvider) {
    switch (filterProvider.statusState) {
      case FilterOptionsState.idle:
      case FilterOptionsState.loading:
        return const SizedBox(
          height: 40,
          child: Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2.2),
            ),
          ),
        );

      case FilterOptionsState.failed:
        return _OptionsError(
          message: _t(
            'تعذر تحميل حالات الشحنة.',
            'Unable to load shipment statuses.',
          ),
          retryLabel: _t('إعادة المحاولة', 'Retry'),
          onRetry: filterProvider.getStatusShipment,
        );

      case FilterOptionsState.ready:
        final statuses = filterProvider.statusShipmentData?.status ?? const [];
        return SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              // Explicit "All": 0 is the value the request omits, so the driver
              // can always get back to an unfiltered status.
              Padding(
                padding: const EdgeInsetsDirectional.symmetric(horizontal: 2.5),
                child: CustomStatusButton(
                  label: _t('الكل', 'All'),
                  selected: filterProvider.draft.statusId == 0,
                  onTap: filterProvider.clearStatusFilter,
                ),
              ),
              for (final status in statuses)
                Padding(
                  padding: const EdgeInsetsDirectional.symmetric(
                    horizontal: 2.5,
                  ),
                  child: CustomStatusButton(
                    // The one shared table every shipment screen uses. The
                    // provider stores the id; the label is resolved here, so a
                    // language switch re-renders it.
                    label: getStatusLabel(
                      context,
                      status.id,
                      statusNameEn: status.statusNameEn,
                      statusNameAr: status.statusNameAr,
                    ),
                    selected: filterProvider.draft.statusId == status.id,
                    onTap: () => filterProvider.selectStatusId(status.id),
                  ),
                ),
            ],
          ),
        );
    }
  }

  Widget _buildFilterForm(
    BuildContext context,
    TextTheme textTheme,
    FilterProvider filterProvider,
  ) {
    // A CustomScrollView, not a SingleChildScrollView: the results below are a
    // SliverList, so a row — and the map preview inside it — is built only when
    // it scrolls into view. Under the old `shrinkWrap: true` +
    // `NeverScrollableScrollPhysics` ListView every matching shipment was built
    // at once, which meant twenty map previews and twenty address lookups the
    // moment a search returned.
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 30),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade400),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 8,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    // Date Picker
                    Consumer<FilterProvider>(
                      builder: (context, dateNotifier, child) {
                        return TextFiledWidget(
                          ontap: () async {
                            CalendarSheet.show(context);
                          },
                          controller: provider.dateController,
                          hint: _t('التصفية حسب التاريخ', 'Filter by date'),
                          readOnly: true,
                          isEnabled: true,
                          icon: Icons.calendar_today_outlined,
                        );
                      },
                    ),

                    Spacing.y(3),

                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        _t('حالة الشحنة', 'Shipment status'),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _buildStatusOptions(filterProvider),

                    Spacing.y(3),
                    Spacing.y(3),

                    // Replace the existing dropdown Consumer widget with this:
                    if (filterProvider.clientsState ==
                        FilterOptionsState.failed)
                      // The store list is optional: only this control reports
                      // the problem, and the rest of the filter stays usable.
                      _OptionsError(
                        message: _t(
                          'تعذر تحميل قائمة المتاجر.',
                          'Unable to load the store list.',
                        ),
                        retryLabel: _t('إعادة المحاولة', 'Retry'),
                        onRetry: filterProvider.getClients,
                      )
                    else
                      // A minimum, not a fixed height: the field carries both a
                      // label and a hint, which need more room than 5.5% of the
                      // screen, and it overflowed by 15px on a 390x844 device.
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: SizeConfig.heightMultiplier * 5.5,
                        ),
                        child: DropdownButtonFormField<ClientModel?>(
                          initialValue: filterProvider.selectedClient,
                          items: [
                            // Null is "all stores"; the request omits store_id.
                            // Without this the driver could never undo a store
                            // choice except by resetting everything.
                            DropdownMenuItem<ClientModel?>(
                              value: null,
                              child: Text(
                                _t('جميع المتاجر', 'All stores'),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            ...filterProvider.clientList.map((client) {
                              return DropdownMenuItem<ClientModel?>(
                                value: client,
                                child: Text(
                                  client.nclient,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              );
                            }),
                          ],
                          onChanged: filterProvider.setSelectedClient,
                          isExpanded: true,
                          // Prevents overflow
                          menuMaxHeight: 200,
                          icon: const SizedBox.shrink(),
                          decoration: InputDecoration(
                            hintText: _t('اسم المتجر', 'Store name'),
                            labelText: _t('اسم المتجر', 'Store name'),
                            filled: true,
                            fillColor: Colors.white,
                            hintStyle: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.normal,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 12,
                            ),
                            suffixIcon: Icon(
                              Icons.expand_more,
                              size: 15,
                              color: Colors.grey,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderSide: BorderSide(
                                color: Colors.grey.shade500,
                                width: 0.5,
                              ),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderSide: const BorderSide(
                                color: Colors.black,
                                width: 1,
                              ),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            errorBorder: OutlineInputBorder(
                              borderSide: const BorderSide(
                                color: Colors.red,
                                width: 1,
                              ),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            border: OutlineInputBorder(
                              borderSide: BorderSide(
                                color: Colors.grey.shade200,
                              ),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      ),

                    Spacing.y(3),

                    // Buttons
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.primary,
                              side: BorderSide(color: AppColors.primary),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            // No longer clears TimeProvider: nothing in the
                            // filter contract uses it.
                            onPressed:
                                filterProvider.isQuerying
                                    ? null
                                    : filterProvider.resetFilters,
                            child: Text(_t('إعادة تعيين', 'Reset')),
                          ),
                        ),
                        Spacing.x(3),
                        Expanded(
                          child: ElevatedButton(
                            // Disabled while the request is in flight; the
                            // provider refuses re-entry as well, so a tap that
                            // lands before this rebuild is still ignored.
                            onPressed:
                                filterProvider.isQuerying ? null : _applyFilter,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              disabledBackgroundColor: AppColors.primary
                                  .withValues(alpha: 0.6),
                              foregroundColor: Colors.white,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child:
                                filterProvider.isQuerying
                                    ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.2,
                                        color: Colors.white,
                                      ),
                                    )
                                    : Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Flexible(
                                          child: Text(
                                            _t('بحث', 'Search'),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: textTheme.bodyLarge!
                                                .copyWith(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                          ),
                                        ),
                                        Spacing.x(2.5),
                                        Image.asset(
                                          'assets/images/search.png',
                                          height: 15,
                                          width: 15,
                                          color: Colors.white,
                                        ),
                                      ],
                                    ),
                          ),
                        ),
                      ],
                    ),
                    Spacing.y(3),
                  ],
                ),
              ),
            ),
          ),
        ),
        ..._buildResults(filterProvider),
        // Clears the floating chat launcher so the last result stays reachable.
        SliverToBoxAdapter(
          child: SizedBox(height: DriverChatBubble.reservedBottomSpace + 16),
        ),
      ],
    );
  }

  /// The five result states, each distinct.
  ///
  /// A failed request used to render the same "No shipments found" as a genuine
  /// empty result, so an offline driver was told they had no work.
  List<Widget> _buildResults(FilterProvider filterProvider) {
    switch (filterProvider.queryState) {
      case FilterQueryState.idle:
        return [
          SliverToBoxAdapter(
            child: _ResultNotice(
              icon: Icons.tune_rounded,
              title: _t('اختر عوامل التصفية', 'Choose your filters'),
              message: _t(
                'حدد التاريخ أو الحالة أو المتجر ثم اضغط بحث.',
                'Pick a date, status or store, then press Search.',
              ),
            ),
          ),
        ];

      case FilterQueryState.loading:
        return const [
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
        ];

      case FilterQueryState.failed:
        return [
          SliverToBoxAdapter(
            child: _ResultNotice(
              icon: Icons.cloud_off_rounded,
              title: _t('تعذر تنفيذ البحث', 'Search failed'),
              message: _t(
                'تعذر الاتصال. يرجى المحاولة مرة أخرى.',
                'Unable to connect. Please try again.',
              ),
              actionLabel: _t('إعادة المحاولة', 'Retry'),
              onAction: _applyFilter,
            ),
          ),
        ];

      case FilterQueryState.empty:
        return [
          SliverToBoxAdapter(
            child: _ResultNotice(
              icon: Icons.search_off_rounded,
              title: _t('لا توجد شحنات مطابقة', 'No shipments found'),
              // The filters are still on screen, so this tells the driver what
              // to do next rather than wiping what they entered.
              message: _t(
                'جرّب تعديل عوامل التصفية.',
                'Try adjusting your filters.',
              ),
            ),
          ),
        ];

      case FilterQueryState.rows:
        return [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  _t(
                    'عدد النتائج: ${isolateIdentifier('${filterProvider.totalResults}')}',
                    '${filterProvider.totalResults} result(s)',
                  ),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Color(0xff64748B),
                    fontSize: 12.5,
                  ),
                ),
              ),
            ),
          ),
          _buildShipmentsList(filterProvider),
          SliverToBoxAdapter(child: _buildLoadMore(filterProvider)),
        ];
    }
  }

  /// The next-page control. A failed page keeps the rows already on screen and
  /// offers a retry beside them rather than replacing them with an error.
  Widget _buildLoadMore(FilterProvider filterProvider) {
    if (filterProvider.loadMoreFailed) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: _OptionsError(
          message: _t(
            'تعذر تحميل المزيد من النتائج.',
            'Unable to load more results.',
          ),
          retryLabel: _t('إعادة المحاولة', 'Retry'),
          onRetry: filterProvider.retryLoadMore,
        ),
      );
    }
    if (!filterProvider.hasMore) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child:
          filterProvider.isLoadingMore
              ? const Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.2),
                ),
              )
              : OutlinedButton(
                onPressed: filterProvider.loadMore,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(46),
                  foregroundColor: AppColors.primary,
                  side: BorderSide(color: AppColors.primary),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(_t('تحميل المزيد', 'Load more')),
              ),
    );
  }

  /// The matching shipments, built lazily.
  ///
  /// Each row carries a map preview, so building the whole result set up front
  /// — which is what the previous shrink-wrapped ListView did — cost one map
  /// per match the instant a search returned.
  Widget _buildShipmentsList(FilterProvider filterProvider) {
    final shipments = filterProvider.shipments;

    return SliverPadding(
      padding: const EdgeInsets.all(16),
      sliver: SliverList.builder(
        itemCount: shipments.length,
        itemBuilder: (context, index) {
          final shipment = shipments[index];

          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: OrderTile(
              username: shipment.recipientName,
              dphno: shipment.recipientPhone,
              orderId: shipment.policyNum,
              orderIdInt: shipment.id,
              currentStatusId:
                  shipment.shipmentStatusId != 0
                      ? shipment.shipmentStatusId
                      : shipment.shipmentStatus,
              doorFeeCollectable:
                  shipment.financial?.doorFeeCollectable ?? 0,
              recipientPhone: shipment.recipientPhone,
              driverName: shipment.driverName ?? '',
              imagePath: shipment.driverImage,
              isPending: shipment.shipmentStatus == 0,
              isNonAccountant: shipment.accountingShipment == 0,
              hasReturn: shipment.returnedShipment == 1,
              clientLocation: shipment.deliveryAddress,
              // The server's amount to collect: 0 on a prepaid shipment.
              shipmentCost: shipment.isPrepaid
                  ? _t('0 (JOD) · مدفوعة مسبقاً', '0 (JOD) · Prepaid')
                  : '${shipment.productToCollect} (JOD)',
              deliveryDate: shipment.formattedShipmentDate,
              deliveryType: shipment.deliveryTypeId,
              showBtnrow: true,
              locationStore: LatLng(
                double.tryParse(shipment.latitude ?? '') ?? 0.0,
                double.tryParse(shipment.longitude ?? '') ?? 0.0,
              ),
              ondetailtap: () {
                Nav.to(
                  OrderDetailPage(
                    shipment: shipment,
                    phoneCustomer: shipment.phclient,
                    shipmentId: shipment.id,
                    deliveryAdd: shipment.lclient,
                    storeAdd: shipment.nstore,
                    orderDate: shipment.createdAt,
                  ),
                  withNav: false,
                  navIndex: 1,
                );
              },
            ),
          );
        },
      ),
    );
  }
}

/// A failure beside the control it belongs to, with the action that fixes it.
class _OptionsError extends StatelessWidget {
  const _OptionsError({
    required this.message,
    required this.retryLabel,
    required this.onRetry,
  });

  final String message;
  final String retryLabel;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xffFEF4E4),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xffF6DDB4)),
      ),
      child: Column(
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: Color(0xff7A4E05),
            ),
          ),
          TextButton(
            onPressed: onRetry,
            style: TextButton.styleFrom(minimumSize: const Size(0, 40)),
            child: Text(retryLabel),
          ),
        ],
      ),
    );
  }
}

/// The neutral, empty and failed result states.
class _ResultNotice extends StatelessWidget {
  const _ResultNotice({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
      child: Column(
        children: [
          Icon(icon, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: Color(0xff334155),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: Color(0xff64748B)),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 14),
            ElevatedButton(
              onPressed: onAction,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                minimumSize: const Size(140, 44),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(actionLabel!),
            ),
          ],
        ],
      ),
    );
  }
}
