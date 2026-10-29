import 'dart:async';

import 'package:blockatie/constants/colors.dart';
import 'package:blockatie/models/driver_tour.dart';
import 'package:blockatie/provider/driver_tours.dart';
import 'package:blockatie/services/driver_tour_service.dart';
import 'package:blockatie/services/user_session_state.dart';
import 'package:blockatie/utils/nav.dart';
import 'package:blockatie/views/pages/orders/order_details.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Driver-facing execution screen for the server-owned Driver Tours lifecycle.
///
/// The page intentionally has no route planner, ETA, custody, barcode, COD or
/// shipment-status writer. It shows only the tour projection and sends only
/// server-supported lifecycle commands; shipment work opens the existing
/// canonical shipment screen after the server authorizes tour visibility.
class DriverToursPage extends StatefulWidget {
  const DriverToursPage({super.key});

  @override
  State<DriverToursPage> createState() => _DriverToursPageState();
}

class _DriverToursPageState extends State<DriverToursPage>
    with WidgetsBindingObserver {
  int? _generation;

  bool get _arabic => Localizations.localeOf(context).languageCode == 'ar';

  String _copy(String en, String ar) => _arabic ? ar : en;

  @override
  void initState() {
    super.initState();
    _generation = UserSessionState.generation;
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(context.read<DriverToursProvider>().refresh());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !mounted) return;
    // A single foreground refresh gives a driver current lifecycle state
    // without background polling or processing while the app is hidden.
    unawaited(context.read<DriverToursProvider>().refresh());
  }

  Future<void> _refresh() => context.read<DriverToursProvider>().refresh();

  Future<void> _runAction(
    DriverToursProvider provider,
    DriverTourDetails details,
    String action,
  ) async {
    final request = await _confirmAction(action);
    if (!mounted || request == null) return;

    try {
      final result = await provider.command(
        action: action,
        tour: details.tour,
        reason: request.reason,
      );
      if (!mounted || _generation != UserSessionState.generation) return;
      _message(
        result.idempotent
            ? _copy(
              'Tour state was already confirmed.',
              'حالة الجولة مؤكدة مسبقاً.',
            )
            : _copy('Tour updated.', 'تم تحديث الجولة.'),
      );
    } on SessionChanged {
      // The shared session boundary clears the provider and redirects as
      // needed. Avoid showing information from the session that just ended.
    } on DriverTourException catch (error) {
      if (!mounted || _generation != UserSessionState.generation) return;
      _message(_failureText(error), error: true);
    }
  }

  Future<_TourActionRequest?> _confirmAction(String action) async {
    final needsReason = action == 'interrupt';
    String? validation;
    var reasonText = '';
    return showDialog<_TourActionRequest>(
      context: context,
      barrierDismissible: false,
      builder:
          (dialogContext) => StatefulBuilder(
            builder: (context, setDialogState) {
              final title = switch (action) {
                'start' => _copy('Start tour?', 'بدء الجولة؟'),
                'interrupt' => _copy('Interrupt tour?', 'إيقاف الجولة؟'),
                'resume' => _copy('Resume tour?', 'استئناف الجولة؟'),
                'complete' => _copy('Complete tour?', 'إكمال الجولة؟'),
                _ => _copy('Confirm tour action', 'تأكيد إجراء الجولة'),
              };
              final detail = switch (action) {
                'start' => _copy(
                  'Starting confirms that you are beginning this tour. It does not confirm custody or change shipment status.',
                  'البدء يؤكد أنك ستباشر هذه الجولة. لا يثبت الحيازة ولا يغير حالة أي شحنة.',
                ),
                'interrupt' => _copy(
                  'The tour stays assigned until an authorized dispatcher resolves it.',
                  'تبقى الجولة مسندة حتى يعالجها مسؤول مخوّل.',
                ),
                'resume' => _copy(
                  'Resume only when you can continue the same assigned tour.',
                  'استأنف فقط عندما تستطيع متابعة الجولة المسندة نفسها.',
                ),
                'complete' => _copy(
                  'Complete only after every stop has a recorded canonical outcome.',
                  'أكمل فقط بعد تسجيل نتيجة معتمدة لكل محطة.',
                ),
                _ => '',
              };
              return AlertDialog(
                title: Text(title),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(detail),
                    if (needsReason) ...[
                      const SizedBox(height: 16),
                      TextField(
                        autofocus: true,
                        enabled: true,
                        maxLength: 255,
                        maxLines: 2,
                        textInputAction: TextInputAction.done,
                        onChanged: (value) {
                          reasonText = value;
                          if (validation != null) {
                            setDialogState(() => validation = null);
                          }
                        },
                        decoration: InputDecoration(
                          labelText: _copy('Reason', 'السبب'),
                          hintText: _copy(
                            'Explain the interruption',
                            'اشرح سبب الإيقاف',
                          ),
                          errorText: validation,
                        ),
                      ),
                    ],
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: Text(_copy('Cancel', 'إلغاء')),
                  ),
                  FilledButton(
                    onPressed: () {
                      final reason = reasonText.trim();
                      if (needsReason &&
                          (reason.isEmpty ||
                              reason.runes.length > 255 ||
                              RegExp(r'[\x00-\x1F\x7F]').hasMatch(reason))) {
                        setDialogState(
                          () =>
                              validation = _copy(
                                'Enter a valid reason (1–255 characters).',
                                'أدخل سبباً صالحاً من 1 إلى 255 حرفاً.',
                              ),
                        );
                        return;
                      }
                      Navigator.of(
                        dialogContext,
                      ).pop(_TourActionRequest(needsReason ? reason : null));
                    },
                    child: Text(_actionLabel(action)),
                  ),
                ],
              );
            },
          ),
    );
  }

  void _openShipment(DriverTourStop stop) {
    if (!stop.driverHasAccepted) return;
    // The shipment page remains the only client-side route to the canonical
    // shipment workflow. No stop outcome, status, finance or customer field is
    // carried from the Tour UI.
    Nav.to(OrderDetailPage(shipmentId: stop.shipmentId, phoneCustomer: ''));
  }

  void _message(String text, {bool error = false}) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor:
            error ? const Color(0xffB42318) : const Color(0xff0F766E),
        content: Text(text),
      ),
    );
  }

  String _failureText(DriverTourException error) {
    return switch (error.kind) {
      DriverTourFailureKind.authentication => _copy(
        'Your session has ended. Please sign in again.',
        'انتهت جلستك. يرجى تسجيل الدخول مجدداً.',
      ),
      DriverTourFailureKind.authorization => _copy(
        'You are not allowed to access this tour.',
        'لا تملك صلاحية الوصول إلى هذه الجولة.',
      ),
      DriverTourFailureKind.conflict => _copy(
        'This tour changed. The latest details were loaded for review.',
        'تغيّرت الجولة. تم تحميل أحدث التفاصيل للمراجعة.',
      ),
      DriverTourFailureKind.validation => _copy(
        'This action is no longer available. Refresh and review the tour.',
        'لم يعد هذا الإجراء متاحاً. حدّث الجولة وراجعها.',
      ),
      DriverTourFailureKind.network => _copy(
        'No connection. Your action was not confirmed; retry when connected.',
        'لا يوجد اتصال. لم يتم تأكيد الإجراء؛ أعد المحاولة عند الاتصال.',
      ),
      DriverTourFailureKind.unavailable ||
      DriverTourFailureKind.invalidResponse => _copy(
        'Tour service is unavailable. Try again shortly.',
        'خدمة الجولات غير متاحة. حاول مرة أخرى بعد قليل.',
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xffF4F7FB),
      appBar: AppBar(
        title: Text(_copy('My tour', 'جولتي')),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: _copy('Back', 'رجوع'),
          onPressed: Nav.back,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: _copy('Refresh', 'تحديث'),
            onPressed: _refresh,
          ),
        ],
      ),
      body: Consumer<DriverToursProvider>(
        builder: (context, provider, _) {
          if (provider.isLoadingCurrent &&
              provider.tours.isEmpty &&
              provider.details == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return RefreshIndicator(
            color: AppColors.primary,
            onRefresh: _refresh,
            child: ListView(
              key: const Key('driver-tour-page'),
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 118),
              children: [
                _IntroCard(arabic: _arabic),
                const SizedBox(height: 14),
                if (provider.currentError != null) ...[
                  _ErrorCard(
                    text: _failureText(provider.currentError!),
                    retry: _refresh,
                  ),
                  const SizedBox(height: 14),
                ],
                if (provider.tours.isEmpty &&
                    provider.details == null &&
                    provider.currentError == null)
                  _EmptyCard(arabic: _arabic)
                else ...[
                  if (provider.tours.length > 1) ...[
                    _SectionLabel(_copy('Available tours', 'الجولات المتاحة')),
                    const SizedBox(height: 8),
                    for (final tour in provider.tours) ...[
                      _TourPicker(
                        tour: tour,
                        selected: tour.id == provider.selectedTourId,
                        arabic: _arabic,
                        onTap: () => provider.selectTour(tour.id),
                      ),
                      const SizedBox(height: 8),
                    ],
                    const SizedBox(height: 8),
                  ],
                  if (provider.isLoadingDetails && provider.details == null)
                    const Padding(
                      padding: EdgeInsets.all(28),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  if (provider.detailsError != null && provider.details == null)
                    _ErrorCard(
                      text: _failureText(provider.detailsError!),
                      retry: () {
                        final id = provider.selectedTourId;
                        if (id != null) return provider.loadDetails(id);
                        return _refresh();
                      },
                    ),
                  if (provider.details case final details?) ...[
                    _TourHeaderCard(
                      tour: details.tour,
                      summary: details.summary,
                      arabic: _arabic,
                    ),
                    const SizedBox(height: 14),
                    _TourActions(
                      details: details,
                      busy: provider.isCommandBusy(details.tour.id),
                      arabic: _arabic,
                      actionLabel: _actionLabel,
                      onAction:
                          (action) => _runAction(provider, details, action),
                    ),
                    const SizedBox(height: 18),
                    _SectionLabel(_copy('Stops', 'المحطات')),
                    const SizedBox(height: 8),
                    if (provider.detailsError != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _InlineError(
                          text: _failureText(provider.detailsError!),
                          retry: () => provider.loadDetails(details.tour.id),
                        ),
                      ),
                    if (details.stops.isEmpty)
                      _StopsEmptyCard(arabic: _arabic)
                    else
                      for (final stop in details.stops) ...[
                        _TourStopCard(
                          stop: stop,
                          arabic: _arabic,
                          onOpenShipment:
                              stop.driverHasAccepted
                                  ? () => _openShipment(stop)
                                  : null,
                        ),
                        const SizedBox(height: 8),
                      ],
                  ],
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  String _actionLabel(String action) => switch (action) {
    'start' => _copy('Start tour', 'بدء الجولة'),
    'interrupt' => _copy('Interrupt', 'إيقاف مؤقت'),
    'resume' => _copy('Resume', 'استئناف'),
    'complete' => _copy('Complete tour', 'إكمال الجولة'),
    _ => _copy('Continue', 'متابعة'),
  };
}

class _TourActionRequest {
  const _TourActionRequest(this.reason);
  final String? reason;
}

class _IntroCard extends StatelessWidget {
  const _IntroCard({required this.arabic});
  final bool arabic;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(20),
      gradient: const LinearGradient(
        colors: [AppColors.primary, AppColors.gradient2],
      ),
    ),
    child: Row(
      children: [
        const Icon(Icons.route_rounded, color: Colors.white, size: 28),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            arabic
                ? 'اتبع ترتيب الجولة وسجّل نتائج الشحنات من شاشة الشحنة المعتمدة.'
                : 'Follow the tour order and record shipment outcomes from the approved shipment screen.',
            style: const TextStyle(
              color: Colors.white,
              height: 1.45,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
}

class _TourPicker extends StatelessWidget {
  const _TourPicker({
    required this.tour,
    required this.selected,
    required this.arabic,
    required this.onTap,
  });
  final DriverTour tour;
  final bool selected;
  final bool arabic;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    borderRadius: BorderRadius.circular(16),
    child: InkWell(
      key: Key('driver-tour-${tour.id}'),
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? AppColors.primary : const Color(0xffE2E8F0),
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '${arabic ? 'جولة' : 'Tour'} #${tour.id}',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            _StateBadge(state: tour.state, arabic: arabic),
          ],
        ),
      ),
    ),
  );
}

class _TourHeaderCard extends StatelessWidget {
  const _TourHeaderCard({
    required this.tour,
    required this.summary,
    required this.arabic,
  });
  final DriverTour tour;
  final DriverTourSummary summary;
  final bool arabic;

  @override
  Widget build(BuildContext context) {
    final max = summary.snapshotStopCount == 0 ? 1 : summary.snapshotStopCount;
    final progress = (summary.outcomeStopCount / max).clamp(0.0, 1.0);
    final text = arabic;
    return Container(
      key: const Key('driver-tour-details'),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xffE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${text ? 'جولة' : 'Tour'} #${tour.id}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 19,
                  ),
                ),
              ),
              _StateBadge(state: tour.state, arabic: text),
            ],
          ),
          const SizedBox(height: 18),
          LinearProgressIndicator(
            value: progress,
            minHeight: 9,
            borderRadius: BorderRadius.circular(9),
            color: AppColors.primary,
            backgroundColor: const Color(0xffE8EEF6),
          ),
          const SizedBox(height: 13),
          Row(
            children: [
              _Metric(
                value: '${summary.plannedStopCount}',
                label: text ? 'مخطط' : 'Planned',
              ),
              _Metric(
                value: '${summary.outcomeStopCount}',
                label: text ? 'منتهية' : 'Completed',
              ),
              _Metric(
                value: '${summary.remainingStopCount}',
                label: text ? 'متبقية' : 'Remaining',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      children: [
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            color: Color(0xff64748B),
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

class _TourActions extends StatelessWidget {
  const _TourActions({
    required this.details,
    required this.busy,
    required this.arabic,
    required this.actionLabel,
    required this.onAction,
  });
  final DriverTourDetails details;
  final bool busy;
  final bool arabic;
  final String Function(String) actionLabel;
  final ValueChanged<String> onAction;

  @override
  Widget build(BuildContext context) {
    final tour = details.tour;
    String? action;
    String? note;
    switch (tour.state) {
      case DriverTourState.ready:
        action = 'start';
      case DriverTourState.active:
        action = details.summary.canComplete ? 'complete' : 'interrupt';
        if (!details.summary.canComplete) {
          note =
              arabic
                  ? 'يمكن إكمال الجولة بعد تسجيل نتيجة معتمدة لكل محطة.'
                  : 'Complete becomes available after every stop has a canonical outcome.';
        }
      case DriverTourState.interrupted:
        action = 'resume';
      case DriverTourState.completed ||
          DriverTourState.cancelled ||
          DriverTourState.superseded:
        action = null;
    }
    if (action == null) return const SizedBox.shrink();
    final destructive = action == 'interrupt';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xffF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xffE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (note != null) ...[
            Text(
              note,
              style: const TextStyle(
                color: Color(0xff64748B),
                fontSize: 12,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 10),
          ],
          FilledButton.icon(
            key: Key('driver-tour-action-$action'),
            onPressed: busy ? null : () => onAction(action!),
            style: FilledButton.styleFrom(
              backgroundColor:
                  destructive ? const Color(0xffB42318) : AppColors.primary,
              minimumSize: const Size.fromHeight(48),
            ),
            icon:
                busy
                    ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                    : Icon(_actionIcon(action)),
            label: Text(actionLabel(action)),
          ),
        ],
      ),
    );
  }

  IconData _actionIcon(String action) => switch (action) {
    'start' => Icons.play_arrow_rounded,
    'interrupt' => Icons.pause_circle_outline_rounded,
    'resume' => Icons.play_circle_outline_rounded,
    'complete' => Icons.task_alt_rounded,
    _ => Icons.arrow_forward_rounded,
  };
}

class _TourStopCard extends StatelessWidget {
  const _TourStopCard({
    required this.stop,
    required this.arabic,
    required this.onOpenShipment,
  });
  final DriverTourStop stop;
  final bool arabic;
  final VoidCallback? onOpenShipment;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xffE2E8F0)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 16,
          backgroundColor: AppColors.primary.withValues(alpha: 0.10),
          foregroundColor: AppColors.primary,
          child: Text(
            '${stop.order}',
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                stop.driverHasAccepted && stop.policyNumber != null
                    ? stop.policyNumber!
                    : '${arabic ? 'شحنة' : 'Shipment'} #${stop.shipmentId}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              _StopStateBadge(state: stop.state, arabic: arabic),
              if (!stop.driverHasAccepted) ...[
                const SizedBox(height: 7),
                Text(
                  arabic
                      ? 'تظهر تفاصيل المستلم بعد تأكيد بدء الجولة من الخادم.'
                      : 'Recipient details remain hidden until the server confirms tour start.',
                  style: const TextStyle(
                    color: Color(0xff64748B),
                    fontSize: 11.5,
                    height: 1.35,
                  ),
                ),
              ],
              if (onOpenShipment != null) ...[
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: onOpenShipment,
                  icon: const Icon(Icons.open_in_new_rounded, size: 17),
                  label: Text(arabic ? 'فتح الشحنة' : 'Open shipment'),
                  style: TextButton.styleFrom(padding: EdgeInsets.zero),
                ),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}

class _StateBadge extends StatelessWidget {
  const _StateBadge({required this.state, required this.arabic});
  final DriverTourState state;
  final bool arabic;

  @override
  Widget build(BuildContext context) {
    final value = switch (state) {
      DriverTourState.ready => (
        arabic ? 'جاهزة' : 'Ready',
        const Color(0xffA15C00),
        const Color(0xffFFF4D6),
      ),
      DriverTourState.active => (
        arabic ? 'نشطة' : 'Active',
        const Color(0xff087443),
        const Color(0xffDCFCE7),
      ),
      DriverTourState.interrupted => (
        arabic ? 'متوقفة' : 'Interrupted',
        const Color(0xffB42318),
        const Color(0xffFEE4E2),
      ),
      DriverTourState.completed => (
        arabic ? 'مكتملة' : 'Completed',
        const Color(0xff075985),
        const Color(0xffE0F2FE),
      ),
      DriverTourState.cancelled => (
        arabic ? 'ملغاة' : 'Cancelled',
        const Color(0xff475569),
        const Color(0xffE2E8F0),
      ),
      DriverTourState.superseded => (
        arabic ? 'مستبدلة' : 'Superseded',
        const Color(0xff475569),
        const Color(0xffE2E8F0),
      ),
    };
    return _Badge(label: value.$1, foreground: value.$2, background: value.$3);
  }
}

class _StopStateBadge extends StatelessWidget {
  const _StopStateBadge({required this.state, required this.arabic});
  final DriverTourStopState state;
  final bool arabic;

  @override
  Widget build(BuildContext context) {
    final label = switch (state) {
      DriverTourStopState.pending => arabic ? 'معلقة' : 'Pending',
      DriverTourStopState.inProgress => arabic ? 'قيد التنفيذ' : 'In progress',
      DriverTourStopState.delivered => arabic ? 'تم التسليم' : 'Delivered',
      DriverTourStopState.cancelled => arabic ? 'ملغاة' : 'Cancelled',
      DriverTourStopState.failed => arabic ? 'فشلت' : 'Failed',
      DriverTourStopState.returned => arabic ? 'مرتجعة' : 'Returned',
      DriverTourStopState.unattempted => arabic ? 'لم تحاول' : 'Unattempted',
      DriverTourStopState.replanned => arabic ? 'أعيد تخطيطها' : 'Replanned',
    };
    final terminal = const {
      DriverTourStopState.delivered,
      DriverTourStopState.cancelled,
      DriverTourStopState.failed,
      DriverTourStopState.returned,
      DriverTourStopState.replanned,
    }.contains(state);
    return _Badge(
      label: label,
      foreground: terminal ? const Color(0xff087443) : const Color(0xff475569),
      background: terminal ? const Color(0xffDCFCE7) : const Color(0xffF1F5F9),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
    required this.label,
    required this.foreground,
    required this.background,
  });
  final String label;
  final Color foreground;
  final Color background;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(99),
    ),
    child: Text(
      label,
      style: TextStyle(
        color: foreground,
        fontWeight: FontWeight.w800,
        fontSize: 11,
      ),
    ),
  );
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
  );
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.arabic});
  final bool arabic;
  @override
  Widget build(BuildContext context) => _InfoCard(
    icon: Icons.route_outlined,
    title:
        arabic ? 'لا توجد جولة تنفيذية الآن' : 'No executable tour right now',
    message:
        arabic
            ? 'ستظهر الجولة هنا بعد اعتمادها وإسنادها لك.'
            : 'An approved tour assigned to you will appear here.',
  );
}

class _StopsEmptyCard extends StatelessWidget {
  const _StopsEmptyCard({required this.arabic});
  final bool arabic;
  @override
  Widget build(BuildContext context) => _InfoCard(
    icon: Icons.inbox_outlined,
    title: arabic ? 'لا توجد محطات' : 'No stops',
    message:
        arabic
            ? 'لا يمكن تنفيذ أو إكمال جولة بلا محطات.'
            : 'A tour without stops cannot be operated or completed.',
  );
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.text, required this.retry});
  final String text;
  final Future<void> Function() retry;
  @override
  Widget build(BuildContext context) => _InfoCard(
    icon: Icons.wifi_off_rounded,
    title: text,
    message: '',
    action: TextButton(
      onPressed: retry,
      child: Text(
        Localizations.localeOf(context).languageCode == 'ar'
            ? 'إعادة المحاولة'
            : 'Retry',
      ),
    ),
  );
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.text, required this.retry});
  final String text;
  final Future<void> Function() retry;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xffFEF2F2),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        const Icon(Icons.error_outline_rounded, color: Color(0xffB42318)),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 12))),
        TextButton(onPressed: retry, child: const Icon(Icons.refresh_rounded)),
      ],
    ),
  );
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0xffE2E8F0)),
    ),
    child: Column(
      children: [
        Icon(icon, color: AppColors.primary, size: 30),
        const SizedBox(height: 10),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        if (message.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xff64748B), height: 1.4),
          ),
        ],
        if (action != null) action!,
      ],
    ),
  );
}
