import 'dart:async';

import 'package:blockatie/constants/colors.dart';
import 'package:blockatie/models/settlements/driver_settlement_line.dart';
import 'package:blockatie/provider/settlements/driver_settlement_details_provider.dart';
import 'package:blockatie/views/pages/home/components/header.dart';
import 'package:blockatie/views/pages/settlements/settlement_copy.dart';
import 'package:blockatie/views/widgets/driver_chat_bubble.dart';
import 'package:blockatie/views/widgets/status_update_sheet.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class DriverSettlementDetailsPage extends StatefulWidget {
  const DriverSettlementDetailsPage({super.key, required this.settlementId});
  final int settlementId;
  @override
  State<DriverSettlementDetailsPage> createState() =>
      _DriverSettlementDetailsPageState();
}

class _DriverSettlementDetailsPageState
    extends State<DriverSettlementDetailsPage> {
  final _scrollController = ScrollController();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted)
        unawaited(
          context.read<DriverSettlementDetailsProvider>().load(
            widget.settlementId,
          ),
        );
    });
    _scrollController.addListener(() {
      if (_scrollController.position.extentAfter < 240)
        unawaited(context.read<DriverSettlementDetailsProvider>().loadMore());
    });
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
              title: ar ? 'تفاصيل التسوية' : 'Settlement Details',
              subtitle:
                  ar
                      ? 'كشف الشحنات والقيم المثبتة'
                      : 'Settlement shipment records',
              showNotificationShortcut: false,
              showProfileShortcut: false,
              showBack: true,
              // A pushed route, so it pops. Deliberately NOT Nav.back(): that
              // clears the bottom-nav overlay first, and the settlements list
              // underneath IS that overlay — so it would close the list and
              // leave this screen on top.
              onBack: () => Navigator.of(context).pop(),
            ),
            Expanded(
              child: Consumer<DriverSettlementDetailsProvider>(
                builder: (context, p, _) {
                  if (p.isLoading && p.settlement == null)
                    return const Center(child: CircularProgressIndicator());
                  final s = p.settlement;
                  // A failed or missing read is an error, never a zeroed
                  // settlement drawn as if it were real.
                  if (s == null)
                    return _DetailsError(
                      ar: ar,
                      message: settlementErrorCopy(context, p.error),
                      onRetry: () => p.load(widget.settlementId),
                    );
                  final trailing =
                      (p.isLoadingMore || p.loadMoreError != null) ? 1 : 0;
                  return RefreshIndicator(
                    color: AppColors.primary,
                    onRefresh: p.refresh,
                    child: ListView.builder(
                      controller: _scrollController,
                      physics: const AlwaysScrollableScrollPhysics(
                        parent: BouncingScrollPhysics(),
                      ),
                      // Clears the floating chat launcher, so the last
                      // shipment line stays readable.
                      padding: EdgeInsets.fromLTRB(
                        16,
                        16,
                        16,
                        DriverChatBubble.reservedBottomSpace + 16,
                      ),
                      itemCount:
                          2 + (p.lines.isEmpty ? 1 : p.lines.length) + trailing,
                      itemBuilder: (context, index) {
                        if (index == 0) return _HeaderCard(ar: ar, provider: p);
                        if (index == 1)
                          return Padding(
                            padding: const EdgeInsets.only(top: 18, bottom: 10),
                            child: Text(
                              ar ? 'شحنات التسوية' : 'Settlement shipments',
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          );

                        final lineIndex = index - 2;
                        if (p.lines.isEmpty && lineIndex == 0)
                          return _NoLines(ar: ar);

                        if (p.lines.isEmpty || lineIndex >= p.lines.length) {
                          if (p.loadMoreError != null && !p.isLoadingMore) {
                            return _LinesLoadMoreError(
                              ar: ar,
                              message: settlementErrorCopy(
                                context,
                                p.loadMoreError,
                              ),
                              onRetry: () => unawaited(p.retryLoadMore()),
                            );
                          }
                          return const Padding(
                            padding: EdgeInsets.all(16),
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 9),
                          child: _LineTile(line: p.lines[lineIndex], ar: ar),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.ar, required this.provider});
  final bool ar;
  final DriverSettlementDetailsProvider provider;
  @override
  Widget build(BuildContext context) {
    final s = provider.settlement!;
    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primary, const Color(0xff00346F)],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  s.statementNumber.isEmpty
                      ? (ar ? 'تسوية' : 'Settlement')
                      : settlementReference(context, s.statementNumber),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
              ),
              if (s.hasPdf)
                IconButton(
                  tooltip: ar ? 'عرض PDF' : 'View PDF',
                  onPressed:
                      provider.isDownloadingPdf
                          ? null
                          : () async {
                            final opened = await provider.downloadPdf();
                            if (!context.mounted) return;
                            if (!opened) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    settlementPdfErrorCopy(
                                      context,
                                      provider.pdfError,
                                    ),
                                  ),
                                ),
                              );
                            }
                          },
                  icon:
                      provider.isDownloadingPdf
                          ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                          : const Icon(
                            Icons.picture_as_pdf_outlined,
                            color: Colors.white,
                          ),
                ),
            ],
          ),
          Text(
            settlementPeriod(context, s.periodFrom, s.periodTo),
            style: TextStyle(
              color: Colors.white.withValues(alpha: .82),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 15),
          Row(
            children: [
              // `net_amount` is SUM(shipment_cost): the COD this driver
              // collected and owes the company, with commission and delivery
              // fees stored as zero.
              Expanded(
                child: _LightValue(
                  label: ar ? 'تحصيل مستحق للشركة' : 'COD to hand over',
                  value: settlementMoney(context, s.netAmount),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: _LightValue(
                  label: ar ? 'المتبقي' : 'Remaining',
                  value: settlementMoney(context, s.remainingAmount),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: _LightValue(
                  label: ar ? 'عدد الشحنات' : 'Shipments',
                  // The stored column can be zero while lines exist, so the
                  // provider picks the most authoritative count available.
                  value: '${provider.shipmentsCount}',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LightValue extends StatelessWidget {
  const _LightValue({required this.label, required this.value});
  final String label, value;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(9),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .15),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 9,
            color: Colors.white.withValues(alpha: .75),
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    ),
  );
}

class _LineTile extends StatelessWidget {
  const _LineTile({required this.line, required this.ar});
  final DriverSettlementLine line;
  final bool ar;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xffE5EDF7)),
    ),
    child: Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: const Color(0xffEAF2FF),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            Icons.local_shipping_outlined,
            color: AppColors.primary,
            size: 20,
          ),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                line.shipmentReference.isEmpty
                    ? (ar ? 'شحنة' : 'Shipment')
                    : settlementReference(context, line.shipmentReference),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 3),
              Text(
                // The one shared status table every shipment screen uses, so
                // this row reads the same words as the rest of the app and
                // follows the locale MaterialApp resolved.
                '${line.shipmentStatusId > 0 ? getStatusLabel(context, line.shipmentStatusId, statusNameEn: line.statusNameEn, statusNameAr: line.statusNameAr) : (ar ? 'غير متوفر' : 'Not available')}  •  ${settlementDate(line.shipmentDate)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: Color(0xff64748B)),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Nothing is netted off a line: `net_amount` equals
            // `shipment_amount`, which is the shipment's COD.
            Text(
              ar ? 'مبلغ التحصيل' : 'COD',
              style: const TextStyle(fontSize: 10, color: Color(0xff64748B)),
            ),
            Text(
              settlementMoney(context, line.shipmentAmount),
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
            ),
          ],
        ),
      ],
    ),
  );
}

class _NoLines extends StatelessWidget {
  const _NoLines({required this.ar});
  final bool ar;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
    ),
    child: Center(
      child: Text(
        ar
            ? 'لا توجد شحنات ضمن هذه التسوية'
            : 'No shipments in this settlement',
      ),
    ),
  );
}

class _DetailsError extends StatelessWidget {
  const _DetailsError({
    required this.ar,
    required this.message,
    required this.onRetry,
  });
  final bool ar;
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.cloud_off_outlined,
            size: 38,
            color: Color(0xff64748B),
          ),
          const SizedBox(height: 10),
          Text(message, textAlign: TextAlign.center),
          TextButton(
            onPressed: onRetry,
            child: Text(ar ? 'إعادة المحاولة' : 'Try again'),
          ),
        ],
      ),
    ),
  );
}

/// Shown in place of the next page of lines when it could not be loaded.
class _LinesLoadMoreError extends StatelessWidget {
  const _LinesLoadMoreError({
    required this.ar,
    required this.message,
    required this.onRetry,
  });
  final bool ar;
  final String message;
  final VoidCallback onRetry;
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
