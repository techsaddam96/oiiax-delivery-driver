import 'dart:async';
import 'statement_handovers_page.dart';

import 'package:blockatie/constants/colors.dart';
import 'package:blockatie/models/settlements/driver_settlement.dart';
import 'package:blockatie/provider/settlements/driver_settlements_provider.dart';
import 'package:blockatie/utils/nav.dart';
import 'package:blockatie/views/pages/home/components/header.dart';
import 'package:blockatie/views/pages/settlements/driver_settlement_details_page.dart';
import 'package:blockatie/views/pages/settlements/settlement_copy.dart';
import 'package:blockatie/views/widgets/driver_chat_bubble.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class DriverSettlementsPage extends StatefulWidget {
  const DriverSettlementsPage({super.key});
  @override
  State<DriverSettlementsPage> createState() => _DriverSettlementsPageState();
}

class _DriverSettlementsPageState extends State<DriverSettlementsPage> {
  final _scrollController = ScrollController();
  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_loadMoreWhenNeeded);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted)
        unawaited(context.read<DriverSettlementsProvider>().loadInitial());
    });
  }

  void _loadMoreWhenNeeded() {
    if (_scrollController.position.extentAfter < 260) {
      unawaited(context.read<DriverSettlementsProvider>().loadMore());
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    return Scaffold(
      backgroundColor: const Color(0xffF6F8FC),
      body: SafeArea(
        child: Column(
          children: [
            HomeHeader(
              title: ar ? 'تسوياتي' : 'My Settlements',
              subtitle:
                  ar
                      ? 'الملخص المالي وكشوفات التسوية'
                      : 'Financial summary and settlement records',
              showBack: true,
              // Opened from the hub as a bottom-nav overlay, so Nav.back() is
              // the right exit here: it clears the overlay and returns to the
              // hub tab rather than popping a route that was never pushed.
              onBack: Nav.back,
            ),
            Expanded(
              child: Consumer<DriverSettlementsProvider>(
                builder:
                    (_, provider, __) => RefreshIndicator(
                      color: AppColors.primary,
                      onRefresh: provider.refresh,
                      child: _SettlementContent(
                        provider: provider,
                        controller: _scrollController,
                        ar: ar,
                      ),
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettlementContent extends StatelessWidget {
  const _SettlementContent({
    required this.provider,
    required this.controller,
    required this.ar,
  });
  final DriverSettlementsProvider provider;
  final ScrollController controller;
  final bool ar;

  @override
  Widget build(BuildContext context) {
    if (provider.isInitialLoading &&
        provider.items.isEmpty &&
        provider.financialSummary == null)
      return const Center(child: CircularProgressIndicator());
    if (provider.listError != null && provider.items.isEmpty)
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _RetryCard(
            message: settlementErrorCopy(context, provider.listError),
            onTap: provider.refresh,
            ar: ar,
          ),
        ],
      );
    return ListView(
      controller: controller,
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      // Clears the floating chat launcher, so the last settlement card stays
      // reachable.
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        DriverChatBubble.reservedBottomSpace + 16,
      ),
      children: [
        OutlinedButton.icon(
          icon: const Icon(Icons.payments_outlined),
          label: Text(ar ? 'تسليم النقد للعملاء' : 'Merchant cash handovers'),
          onPressed:
              () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const StatementHandoversPage(),
                ),
              ),
        ),
        _FinancialSection(provider: provider, ar: ar),
        const SizedBox(height: 18),
        _PerformanceSection(provider: provider, ar: ar),
        const SizedBox(height: 22),
        _Title(text: ar ? 'سجل التسويات' : 'Settlement history'),
        const SizedBox(height: 10),
        // Every status the API will filter on, not just two of the five.
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final filter in const [
              (null, 'All', 'الكل'),
              ('approved', 'Approved', 'معتمدة'),
              ('pdf_generated', 'Ready', 'جاهزة'),
              ('sent', 'Sent', 'تم الإرسال'),
              ('partial', 'Partial', 'جزئية'),
              ('paid', 'Paid', 'تمت التسوية'),
            ])
              _FilterChip(
                label: ar ? filter.$3 : filter.$2,
                selected: provider.statusFilter == filter.$1,
                onSelected:
                    () => unawaited(provider.setStatusFilter(filter.$1)),
              ),
          ],
        ),
        const SizedBox(height: 10),
        if (provider.isFiltering)
          const Padding(
            padding: EdgeInsets.all(18),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (provider.items.isEmpty)
          _EmptyCard(ar: ar),
        if (!provider.isFiltering)
          for (final settlement in provider.items) ...[
            _SettlementTile(settlement: settlement, ar: ar),
            const SizedBox(height: 10),
          ],
        if (provider.isLoadingMore)
          const Padding(
            padding: EdgeInsets.all(18),
            child: Center(child: CircularProgressIndicator()),
          ),
        // A page that failed is said so beside the rows it could not extend —
        // it used to look exactly like reaching the end of the list.
        if (provider.loadMoreError != null && !provider.isLoadingMore)
          _LoadMoreError(
            message: settlementErrorCopy(context, provider.loadMoreError),
            onRetry: () => unawaited(provider.retryLoadMore()),
            ar: ar,
          ),
      ],
    );
  }
}

/// Shown under the rows when the next page could not be loaded.
class _LoadMoreError extends StatelessWidget {
  const _LoadMoreError({
    required this.message,
    required this.onRetry,
    required this.ar,
  });
  final String message;
  final VoidCallback onRetry;
  final bool ar;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xffFEF4E4),
      borderRadius: BorderRadius.circular(16),
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
          child: Text(ar ? 'إعادة المحاولة' : 'Try again'),
        ),
      ],
    ),
  );
}

class _FinancialSection extends StatelessWidget {
  const _FinancialSection({required this.provider, required this.ar});
  final DriverSettlementsProvider provider;
  final bool ar;
  @override
  Widget build(BuildContext context) {
    final summary = provider.financialSummary;
    // Still in flight is not a failure. This card used to say "unable to
    // connect" for a read that had simply not arrived yet.
    if (summary == null &&
        provider.financialState != SettlementSectionState.failed) {
      return const _SectionLoading();
    }
    if (summary == null)
      return _RetryCard(
        message: settlementErrorCopy(context, provider.financialError),
        onTap: provider.refresh,
        ar: ar,
      );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Title(text: ar ? 'الملخص المالي' : 'Financial summary'),
        const SizedBox(height: 10),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.48,
          children: [
            // Each figure is gross cash, never the Wallet's commission-netted
            // "Cash to settle" — the wording is kept distinct on purpose. Cash
            // in hand includes any delivery fee taken at the door.
            _Metric(
              icon: Icons.payments_outlined,
              label: ar ? 'نقد بذمتك (تحصيل + أجور)' : 'Cash in hand (COD + fees)',
              value: settlementMoney(context, summary.cashInHand),
              color: const Color(0xffEAF2FF),
            ),
            _Metric(
              icon: Icons.verified_outlined,
              label: ar ? 'تحصيل تمت تسويته' : 'Settled COD',
              value: settlementMoney(context, summary.settledTotal),
              color: const Color(0xffE9F9F1),
            ),
            _Metric(
              icon: Icons.receipt_long_outlined,
              label: ar ? 'تحصيل ضمن تسويات مفتوحة' : 'Open settlement COD',
              value: settlementMoney(context, summary.openSettlementsTotal),
              color: const Color(0xffFFF6E6),
            ),
            _Metric(
              icon: Icons.local_shipping_outlined,
              label: ar ? 'شحنات بانتظار التسوية' : 'Pending shipments',
              value: '${summary.deliveredUnsettledShipmentsCount}',
              color: const Color(0xffF3EEFF),
            ),
          ],
        ),
      ],
    );
  }
}

class _PerformanceSection extends StatelessWidget {
  const _PerformanceSection({required this.provider, required this.ar});
  final DriverSettlementsProvider provider;
  final bool ar;
  @override
  Widget build(BuildContext context) {
    final summary = provider.performanceSummary;
    if (summary == null &&
        provider.performanceState != SettlementSectionState.failed) {
      return const _SectionLoading(compact: true);
    }
    if (summary == null)
      return _RetryCard(
        message: settlementErrorCopy(context, provider.performanceError),
        onTap: provider.refresh,
        ar: ar,
        compact: true,
      );
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Title(text: ar ? 'أدائي' : 'My performance'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _MiniMetric(
                icon: Icons.star_rounded,
                label: ar ? 'التقييم' : 'Rating',
                value:
                    summary.ratingsCount == 0
                        ? (ar ? 'لا يوجد تقييم' : 'No ratings')
                        : '${summary.averageRating.toStringAsFixed(1)} ★',
              ),
              _MiniMetric(
                icon: Icons.check_circle_outline,
                label: ar ? 'تم التسليم' : 'Delivered',
                value: '${summary.deliveredShipments}',
              ),
              _MiniMetric(
                icon: Icons.error_outline,
                label: ar ? 'فشل التسليم' : 'Failed',
                value: '${summary.failedShipments}',
              ),
              _MiniMetric(
                icon: Icons.assignment_return_outlined,
                label: ar ? 'مرتجع' : 'Returned',
                value: '${summary.returnedShipments}',
              ),
              _MiniMetric(
                icon: Icons.trending_up_rounded,
                label: ar ? 'نسبة النجاح' : 'Success rate',
                value: '${summary.successRate.toStringAsFixed(1)}%',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SettlementTile extends StatelessWidget {
  const _SettlementTile({required this.settlement, required this.ar});
  final DriverSettlement settlement;
  final bool ar;
  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(18),
    onTap:
        () => Nav.to(
          DriverSettlementDetailsPage(settlementId: settlement.settlementId),
        ),
    child: Container(
      padding: const EdgeInsets.all(15),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  settlement.statementNumber.isEmpty
                      ? (ar ? 'تسوية' : 'Settlement')
                      : settlementReference(
                        context,
                        settlement.statementNumber,
                      ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              _StatusBadge(status: settlement.status),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right_rounded, color: Color(0xff64748B)),
            ],
          ),
          const SizedBox(height: 9),
          Text(
            settlementPeriod(
              context,
              settlement.periodFrom,
              settlement.periodTo,
            ),
            style: const TextStyle(
              color: Color(0xff64748B),
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 13),
          Row(
            children: [
              Expanded(
                // `net_amount` is SUM(shipment_cost) with commission and
                // delivery fees stored as zero: the COD the driver hands over,
                // not money owed to them.
                child: _TileValue(
                  label: ar ? 'تحصيل مستحق للشركة' : 'COD to hand over',
                  value: settlementMoney(context, settlement.netAmount),
                ),
              ),
              Expanded(
                child: _TileValue(
                  label: ar ? 'عدد الشحنات' : 'Shipments',
                  value: '${settlement.shipmentsCount}',
                ),
              ),
              if (settlement.hasPdf)
                const Icon(
                  Icons.picture_as_pdf_outlined,
                  color: Color(0xffE53935),
                ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });
  final IconData icon;
  final String label, value;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Icon(icon, color: AppColors.primary, size: 20),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
        ),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 10,
            color: Color(0xff64748B),
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });
  final String label;
  final bool selected;
  final VoidCallback onSelected;
  @override
  Widget build(BuildContext context) => ChoiceChip(
    label: Text(label),
    selected: selected,
    onSelected: (_) => onSelected(),
    selectedColor: AppColors.primary,
    labelStyle: TextStyle(
      color: selected ? Colors.white : const Color(0xff475569),
      fontWeight: FontWeight.w800,
      fontSize: 12,
    ),
    side: BorderSide(
      color: selected ? Colors.transparent : const Color(0xffDCE7F4),
    ),
    backgroundColor: Colors.white,
  );
}

class _MiniMetric extends StatelessWidget {
  const _MiniMetric({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label, value;
  @override
  Widget build(BuildContext context) => Container(
    width: 132,
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: const Color(0xffF8FAFC),
      borderRadius: BorderRadius.circular(13),
      border: Border.all(color: const Color(0xffE5EDF7)),
    ),
    child: Row(
      children: [
        Icon(icon, color: AppColors.primary, size: 17),
        const SizedBox(width: 7),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 10, color: Color(0xff64748B)),
              ),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _TileValue extends StatelessWidget {
  const _TileValue({required this.label, required this.value});
  final String label, value;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(fontSize: 10, color: Color(0xff64748B)),
      ),
      const SizedBox(height: 2),
      Text(
        value,
        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
      ),
    ],
  );
}

/// One chip per status value, each with its own colour: every status used to
/// be green, so an approved-but-unpaid settlement read as settled.
class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});
  final String status;
  @override
  Widget build(BuildContext context) {
    final style = settlementStatusStyle(context, status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: style.background,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        style.label,
        style: TextStyle(
          fontSize: 10,
          color: style.foreground,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

/// A section that has not answered yet. Neutral on purpose: no zeros, no
/// error wording.
class _SectionLoading extends StatelessWidget {
  const _SectionLoading({this.compact = false});
  final bool compact;
  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.all(compact ? 18 : 28),
    decoration: _cardDecoration(),
    child: const Center(child: CircularProgressIndicator()),
  );
}

class _Title extends StatelessWidget {
  const _Title({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      fontSize: 17,
      fontWeight: FontWeight.w900,
      color: Color(0xff0F172A),
    ),
  );
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.ar});
  final bool ar;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(28),
    decoration: _cardDecoration(),
    child: Column(
      children: [
        const Icon(
          Icons.receipt_long_outlined,
          color: Color(0xff64748B),
          size: 34,
        ),
        const SizedBox(height: 10),
        Text(
          ar ? 'لا توجد تسويات حتى الآن' : 'No settlements yet',
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 4),
        Text(
          ar
              ? 'ستظهر تسوياتك هنا بعد اعتمادها.'
              : 'Your settlements will appear here after they are confirmed.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xff64748B), fontSize: 12),
        ),
      ],
    ),
  );
}

class _RetryCard extends StatelessWidget {
  const _RetryCard({
    required this.message,
    required this.onTap,
    required this.ar,
    this.compact = false,
  });
  final String message;
  final VoidCallback onTap;
  final bool ar, compact;
  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.all(compact ? 14 : 22),
    decoration: _cardDecoration(),
    child: Column(
      children: [
        Icon(Icons.cloud_off_outlined, color: AppColors.primary),
        const SizedBox(height: 8),
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 8),
        TextButton(
          onPressed: onTap,
          child: Text(ar ? 'إعادة المحاولة' : 'Try again'),
        ),
      ],
    ),
  );
}

BoxDecoration _cardDecoration() => BoxDecoration(
  color: Colors.white,
  borderRadius: BorderRadius.circular(18),
  boxShadow: [
    BoxShadow(
      color: const Color(0xff0F172A).withValues(alpha: .05),
      blurRadius: 14,
      offset: const Offset(0, 5),
    ),
  ],
);
