import 'package:blockatie/models/shipment.dart';
import 'package:blockatie/models/driver_action.dart';
import 'package:blockatie/services/driver_action_service.dart';
import 'package:blockatie/services/user_session_state.dart';
import 'package:blockatie/provider/shipment_instsnt.dart';
import 'package:blockatie/utils/driver_shipment_actions.dart';
import 'package:provider/provider.dart';
import 'package:blockatie/constants/app_urls.dart';
import 'package:blockatie/constants/colors.dart';
import 'package:blockatie/models/order_status_modle.dart';
import 'package:blockatie/services/auth_services.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

const Set<int> finalShipmentStatusIds = {6, 7, 8, 11};

/// Exception targets submitted to update_shipment_status.php; progression uses
/// the shipment-specific action contract and dedicated endpoints. Mirrors what PHP accepts (see services/helpers/driver_status_transitions.php).
///
/// The forward steps — accept (→2), picked up (→4) and delivered (→11) — are not
/// here on purpose: each has its own endpoint and its own from-status check, and
/// endpoint-specific handler, shared with the quick buttons. They are now
/// offered in this sheet only when the shipment contract authorizes them.
const Set<int> driverSelectableStatusIds = {7, 8, 9};

/// Status eligibility for the "Delivered" (تم التسليم) button.
///
/// Verified against the server: the driver action catalog
/// (driver_status_transitions.php, action "delivered") and
/// complete_shipment_driver.php both accept only 4 (in transit, i.e. picked up
/// from the store) and move the shipment to 11 (Completed). The button is a
/// hint only: the server re-checks the status, the driver and the assignment
/// under a row lock and refuses anything else with 409/403.
const Set<int> driverDeliverableFromStatusIds = {4};
const int driverDeliveredStatusId = 11;

bool canMarkDelivered(int statusId) =>
    driverDeliverableFromStatusIds.contains(statusId);

bool isFinalShipmentStatus(int statusId) {
  return finalShipmentStatusIds.contains(statusId);
}

bool isFinalTargetStatus(int statusId) {
  return finalShipmentStatusIds.contains(statusId);
}

String getStatusLabel(
  BuildContext context,
  int statusId, {
  String? statusNameEn,
  String? statusNameAr,
}) {
  // The locale MaterialApp resolved, which is also what Directionality and the
  // theme font are built from. Reading EasyLocalization's own locale here can
  // disagree for a frame after a language switch.
  final isArabic = Localizations.localeOf(context).languageCode == 'ar';
  final preferred = isArabic ? statusNameAr : statusNameEn;
  final fallback = isArabic ? statusNameEn : statusNameAr;

  if (preferred != null && preferred.trim().isNotEmpty) {
    return preferred.trim();
  }
  if (fallback != null && fallback.trim().isNotEmpty) {
    return fallback.trim();
  }

  return isArabic
      ? _fallbackStatusLabelsAr[statusId] ?? 'الحالة #$statusId'
      : _fallbackStatusLabelsEn[statusId] ?? 'Status #$statusId';
}

String getStatusHelperText(BuildContext context, int statusId) {
  final isArabic = Localizations.localeOf(context).languageCode == 'ar';
  final helpers = isArabic ? _statusHelpersAr : _statusHelpersEn;
  return helpers[statusId] ??
      (isArabic
          ? 'راجع الحالة بعناية قبل التأكيد.'
          : 'Review this status carefully before confirming.');
}

IconData getStatusIcon(int statusId) {
  return switch (statusId) {
    2 => Icons.inventory_2_outlined,
    3 => Icons.local_shipping_outlined,
    4 => Icons.route_outlined,
    5 => Icons.near_me_outlined,
    6 => Icons.verified_rounded,
    7 => Icons.cancel_outlined,
    8 => Icons.assignment_return_outlined,
    9 => Icons.report_gmailerrorred_outlined,
    10 => Icons.storefront_outlined,
    11 => Icons.task_alt_rounded,
    _ => Icons.fact_check_outlined,
  };
}

Color getStatusColor(int statusId) {
  return switch (statusId) {
    6 || 11 => const Color(0xff16A06D),
    7 || 8 || 9 => const Color(0xffEF4444),
    4 || 5 => AppColors.primary,
    2 || 3 || 10 => const Color(0xffF59E0B),
    _ => AppColors.primary,
  };
}

class ShipmentStatusUpdateSheet extends StatefulWidget {
  const ShipmentStatusUpdateSheet({
    super.key,
    required this.statuses,
    required this.currentStatusId,
    required this.currentStatusLabel,
    required this.onSubmit,
    this.shipmentId,
    this.shipment,
    this.loadShipment,
    this.executeProgression,
    this.policyNumber,
    this.currentStageLabel,
    this.doorFeeCollectable = 0,
  });

  final int? shipmentId;
  final Shipment? shipment;
  final Future<Shipment?> Function(int)? loadShipment;
  final Future<ShipmentActionResult?> Function(Shipment, DriverAction)?
  executeProgression;
  final List<Status> statuses;
  final int currentStatusId;
  final String currentStatusLabel;
  final String? policyNumber;
  final String? currentStageLabel;

  /// Server ceiling for a delivery fee taken at the door on a cancel/return.
  final double doorFeeCollectable;
  final Future<bool> Function(Status status, StatusUpdateReasonPayload? reason)
  onSubmit;

  @override
  State<ShipmentStatusUpdateSheet> createState() =>
      _ShipmentStatusUpdateSheetState();
}

class _ShipmentStatusUpdateSheetState extends State<ShipmentStatusUpdateSheet> {
  Shipment? _snapshot;
  bool _refreshing = true;
  String? _actionMessage;
  final int _sessionGeneration = UserSessionState.generation;
  int get _currentStatusId =>
      _snapshot?.shipmentStatusId ?? widget.currentStatusId;
  String get _currentStatusLabel =>
      _snapshot == null
          ? widget.currentStatusLabel
          : getStatusLabel(
            context,
            _currentStatusId,
            statusNameEn: _snapshot!.statusNameEn,
            statusNameAr: _snapshot!.statusNameAr,
          );
  bool get _currentSession => UserSessionState.isCurrent(_sessionGeneration);

  /// The launchers use the same resolver for their affordance, but the sheet
  /// resolves it again from the fetched shipment before it renders an option.
  /// That keeps a stale card, notification or deep link from exposing a
  /// delivery action after the shipment has been cancelled, reassigned or is
  /// still waiting for pickup.
  DriverStatusSheetMode get _sheetMode {
    final row = _snapshot;
    if (_refreshing || !_currentSession || row == null) {
      return DriverStatusSheetMode.unavailable;
    }
    return driverStatusSheetModeForShipment(row);
  }

  bool _belongsInSheet(DriverAction action) => driverStatusSheetAllowsAction(
    mode: _sheetMode,
    actionId: action.id,
    actionGroup: action.group,
    canExecute: action.canExecute,
  );

  @override
  void initState() {
    super.initState();
    UserSessionState.changes.addListener(_onSessionChanged);
    _refreshContract();
  }

  void _onSessionChanged() {
    if (!mounted || _currentSession) return;
    setState(() {
      _snapshot = null;
      _selectedStatus = null;
      _refreshing = false;
    });
    Navigator.maybePop(context);
  }

  Future<void> _refreshContract() async {
    if (!mounted || !_currentSession) return;
    final id = widget.shipmentId ?? widget.shipment?.id;
    if (id == null) {
      if (mounted)
        setState(() {
          _snapshot = null;
          _refreshing = false;
        });
      return;
    }
    Shipment? fresh;
    try {
      fresh = await (widget.loadShipment ??
          DriverActionService.read(context).fetch)(id);
    } catch (_) {
      fresh = null;
    }
    if (!mounted || !_currentSession) return;
    setState(() {
      _snapshot = fresh;
      _refreshing = false;
      _selectedStatus = null;
      _selectedReason = null;
      _reasons = [];
    });
  }

  DriverAction? _actionFor(int statusId) {
    final row = _snapshot;
    if (_refreshing ||
        !_currentSession ||
        row == null ||
        !row.hasActionContract)
      return null;
    for (final action in row.driverActions) {
      if (action.targetStatusId == statusId && _belongsInSheet(action)) {
        return action;
      }
    }
    return null;
  }

  bool _canSelect(int statusId) =>
      !_isSubmitting && (_actionFor(statusId)?.canExecute ?? false);

  String _explanation(int statusId) {
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    if (statusId == _currentStatusId)
      return ar ? 'الحالة الحالية' : 'Current state';
    if (_snapshot?.hasActionContract != true)
      return ar
          ? 'بيانات الإجراءات غير متاحة؛ أعد التحديث.'
          : 'Action contract unavailable; refresh to retry.';
    final action = _actionFor(statusId);
    if (action != null && action.canExecute) {
      if (action.id == 'arrive_at_pickup')
        return ar
            ? 'يتحقق الخادم من موقع GPS ضمن ١٥٠ متراً من موقع الاستلام.'
            : 'The server checks GPS within 150m of the pickup location.';
      return action.group == 'exception'
          ? (ar
              ? 'إجراء استثنائي يتطلب اختيار سبب.'
              : 'Exception action; a reason is required.')
          : (ar
              ? 'الإجراء التالي المسموح به من الخادم'
              : 'Next action authorized by the server');
    }
    return switch (action?.blockedReason) {
      'SHIPMENT_IN_WAREHOUSE' =>
        ar
            ? 'بانتظار تسليم المستودع الموقّع للسائق.'
            : 'Await the signed warehouse handover.',
      'SHIPMENT_IN_OTHER_DRIVER_CUSTODY' =>
        ar ? 'الشحنة بعهدة سائق آخر.' : 'Held by another driver.',
      'DRIVER_SUBSCRIPTION_INACTIVE' =>
        ar ? 'الاشتراك غير نشط.' : 'Subscription is inactive.',
      'ACTIVE_INSTANT_LIMIT' =>
        ar
            ? 'لديك شحنة فورية نشطة بالفعل.'
            : 'An instant job is already active.',
      'PICKUP_LOCATION_UNAVAILABLE' =>
        ar
            ? 'موقع الاستلام غير متاح؛ تواصل مع التوزيع.'
            : 'Pickup location is unavailable; contact dispatch.',
      _ =>
        ar
            ? 'غير متاح من الحالة الحالية؛ يتحكم الخادم في الانتقالات.'
            : 'Unavailable from the current state; transitions are controlled by the server.',
    };
  }

  Future<void> _submitProgression(DriverAction action, Shipment row) async {
    setState(() => _isSubmitting = true);
    try {
      ShipmentActionResult? result;
      if (widget.executeProgression != null) {
        result = await widget.executeProgression!(row, action);
      } else if (action.id == 'accept_shipment') {
        final confirmed = await showDialog<bool>(
          context: context,
          builder:
              (dialogContext) => AlertDialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(22),
                ),
                actionsPadding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                title: Text(
                  Localizations.localeOf(context).languageCode == 'ar'
                      ? 'هل تريد قبول هذه الشحنة؟'
                      : 'Accept shipment?',
                ),
                content: Text(
                  Localizations.localeOf(context).languageCode == 'ar'
                      ? 'سيتم إسناد هذه الشحنة إلى حساب السائق الخاص بك.'
                      : 'This shipment will be assigned to your driver account.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: Text(
                      Localizations.localeOf(context).languageCode == 'ar'
                          ? 'إلغاء'
                          : 'Cancel',
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(dialogContext, true),
                    child: Text(
                      Localizations.localeOf(context).languageCode == 'ar'
                          ? 'تأكيد'
                          : 'Confirm',
                    ),
                  ),
                ],
              ),
        );
        if (confirmed == true && mounted && _currentSession)
          result = await context.read<ShipmentInstantprovider>().acceptShipment(
            row.id,
            acceptedShipment: row,
            languageCode: Localizations.localeOf(context).languageCode,
          );
      } else {
        final step = switch (action.id) {
          'arrive_at_pickup' => DriverShipmentStep.arriveAtStore,
          'confirm_pickup' => DriverShipmentStep.pickUp,
          'complete_delivery' => DriverShipmentStep.deliver,
          _ => null,
        };
        if (step != null)
          result = await performDriverShipmentStep(
            context,
            shipment: row,
            step: step,
          );
      }
      if (mounted && _currentSession)
        setState(() => _actionMessage = result?.message);
    } catch (_) {
      if (mounted && _currentSession)
        setState(
          () =>
              _actionMessage =
                  Localizations.localeOf(context).languageCode == 'ar'
                      ? 'تعذر تنفيذ الإجراء؛ تم تحديث الشحنة.'
                      : 'Unable to complete the action; shipment refreshed.',
        );
    } finally {
      await _refreshContract();
      if (mounted && _currentSession) setState(() => _isSubmitting = false);
    }
  }

  Status? _selectedStatus;
  StatusReasonOption? _selectedReason;
  final TextEditingController _reasonNoteController = TextEditingController();
  List<StatusReasonOption> _reasons = const [];
  bool _isLoadingReasons = false;
  String? _reasonError;
  bool _isSubmitting = false;
  bool _isConfirming = false;
  DoorFeeChoice _feeChoice = DoorFeeChoice.none;
  final TextEditingController _feeController = TextEditingController();

  @override
  void dispose() {
    UserSessionState.changes.removeListener(_onSessionChanged);
    _reasonNoteController.dispose();
    _feeController.dispose();
    super.dispose();
  }

  /// A fee can be taken at the door on a return, or on a cancel once the
  /// driver has left (3 dispatched, 4 in transit, 5 out for delivery, 9 failed
  /// attempt). The server re-validates the amount against the fee it makes due.
  bool _offersDoorFee(int statusId) {
    if ((_snapshot?.financial?.doorFeeCollectable ??
            widget.doorFeeCollectable) <=
        0)
      return false;
    if (statusId == 8) return true;
    return statusId == 7 && const <int>{3, 4, 5, 9}.contains(_currentStatusId);
  }

  @override
  Widget build(BuildContext context) {
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    final availableStatuses = _availableStatuses;

    // The keyboard takes real estate from the bottom of the screen, and this
    // sheet is anchored there. Without this the reason note and the confirm
    // button sat underneath it, reachable only by guesswork.
    //
    // The inset is added as margin rather than padding so it disappears the
    // moment the keyboard closes — no permanent gap under the sheet — and the
    // maximum height is reduced by the same amount so the sheet shrinks to the
    // space that is actually left rather than being pushed off-screen.
    final viewInsetBottom = MediaQuery.viewInsetsOf(context).bottom;
    final availableHeight =
        (MediaQuery.sizeOf(context).height - viewInsetBottom) * 0.86;

    return SafeArea(
      top: false,
      child: Container(
        margin: EdgeInsets.fromLTRB(12, 12, 12, 12 + viewInsetBottom),
        constraints: BoxConstraints(
          maxHeight: availableHeight < 240 ? 240 : availableHeight,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.14),
              blurRadius: 30,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _StatusSheetHeader(
                title:
                    isArabic ? 'تحديث حالة الشحنة' : 'Update shipment status',
                subtitle:
                    isArabic
                        ? 'اختر الحالة التالية بعناية'
                        : 'Choose the next status carefully',
                policyNumber: widget.policyNumber,
                currentStatusLabel: _currentStatusLabel,
              ),
              _CurrentStatusCard(
                label: isArabic ? 'الحالة الحالية' : 'Current status',
                statusLabel: _currentStatusLabel,
                stageLabel:
                    const {1, 2, 3, 10}.contains(_currentStatusId) &&
                            _snapshot?.pickupSource != null
                        ? _snapshot!
                            .pickupSource![isArabic ? 'label_ar' : 'label_en']
                            ?.toString()
                        : (_currentStatusId == 5
                            ? (isArabic
                                ? 'تواصل مع فريق التوزيع؛ لا يوجد انتقال تسليم متاح من هذه الحالة.'
                                : 'Contact dispatch; delivery is unavailable from this state.')
                            : null),
                statusId: _currentStatusId,
              ),
              // One scroll region for everything between the header
              // and the confirm button. The reason selector used to
              // sit outside the scrollable, so with the keyboard up it
              // and the button were pushed past the bottom edge with
              // no way to reach them. Putting the note field inside a
              // Scrollable also lets Flutter bring it into view when
              // it takes focus.
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_refreshing) const LinearProgressIndicator(),
                      if (_actionMessage?.isNotEmpty == true)
                        Text(_actionMessage!),
                      if (_snapshot?.hasActionContract != true && !_refreshing)
                        TextButton(
                          onPressed:
                              _isSubmitting
                                  ? null
                                  : () {
                                    setState(() => _refreshing = true);
                                    _refreshContract();
                                  },
                          child: Text(
                            isArabic
                                ? 'إعادة تحميل الإجراءات'
                                : 'Reload actions',
                          ),
                        ),
                      if (!_refreshing && availableStatuses.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Text(
                            isArabic
                                ? 'لا توجد إجراءات حالة متاحة لهذه الشحنة.'
                                : 'No status actions are available for this shipment.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Color(0xff64748B),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      for (final status in availableStatuses) ...[
                        _StatusOptionCard(
                          key: ValueKey('lifecycle_status_${status.id}'),
                          status: status,
                          helperText: _explanation(
                            int.tryParse(status.id) ?? 0,
                          ),
                          statusId: int.tryParse(status.id) ?? 0,
                          selected: status.id == _selectedStatus?.id,
                          onTap:
                              !_canSelect(int.tryParse(status.id) ?? 0)
                                  ? null
                                  : () {
                                    setState(() {
                                      _selectedStatus = status;
                                      _selectedReason = null;
                                      _reasons = const [];
                                      _reasonError = null;
                                      _reasonNoteController.clear();
                                      _feeChoice = DoorFeeChoice.none;
                                      _feeController.clear();
                                    });
                                    _loadReasonsIfNeeded(
                                      int.tryParse(status.id) ?? 0,
                                    );
                                  },
                        ),
                        if (status != availableStatuses.last)
                          const SizedBox(height: 10),
                      ],
                      if (_selectedStatusId != null &&
                          _requiresReason(_selectedStatusId!))
                        _ReasonSelector(
                          reasons: _reasons,
                          selectedReason: _selectedReason,
                          isLoading: _isLoadingReasons,
                          error: _reasonError,
                          noteController: _reasonNoteController,
                          onChanged: (reason) {
                            setState(() => _selectedReason = reason);
                          },
                          onRetry: () {
                            final statusId = _selectedStatusId;
                            if (statusId != null) {
                              _loadReasonsIfNeeded(statusId, force: true);
                            }
                          },
                        ),
                      if (_selectedStatusId != null &&
                          _offersDoorFee(_selectedStatusId!))
                        _DoorFeeSelector(
                          maxAmount:
                              _snapshot?.financial?.doorFeeCollectable ??
                              widget.doorFeeCollectable,
                          choice: _feeChoice,
                          controller: _feeController,
                          onChanged: (choice) {
                            setState(() => _feeChoice = choice);
                          },
                        ),
                      if (_selectedStatusId != null &&
                          isFinalTargetStatus(_selectedStatusId!))
                        _FinalStatusWarning(statusId: _selectedStatusId!),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                child: SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed:
                        _selectedStatus == null || _isSubmitting
                            ? null
                            : _submit,
                    icon:
                        _isSubmitting
                            ? const SizedBox(
                              width: 19,
                              height: 19,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2.3,
                              ),
                            )
                            : const Icon(Icons.check_rounded),
                    label: Text(
                      isArabic ? 'تأكيد التحديث' : 'Confirm update',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: const Color(0xffCBD5E1),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Status> get _availableStatuses {
    final row = _snapshot;
    // Never fall back to the caller's broad lifecycle list.  It is only a
    // label source; the freshly fetched action contract is the sole source of
    // selectable options.  In particular, it prevents 4/11 delivery actions
    // appearing while a shipment is still at the store.
    if (_refreshing || row == null || !row.hasActionContract) return const [];

    final labelsByStatus = <int, Status>{
      for (final state in row.driverLifecycle)
        if (int.tryParse(state['id']?.toString() ?? '') case final id?)
          id: Status.fromJson(state),
      for (final status in widget.statuses)
        if (int.tryParse(status.id) case final id?) id: status,
    };
    final actions =
        row.driverActions.where(_belongsInSheet).toList()..sort(
          (left, right) => left.targetStatusId.compareTo(right.targetStatusId),
        );

    return actions.map((action) {
      final status = labelsByStatus[action.targetStatusId];
      return Status.fromJson({
        'id': action.targetStatusId,
        'status_name_en':
            action.labelEn.isEmpty ? status?.statusNameEn : action.labelEn,
        'status_name_ar':
            action.labelAr.isEmpty ? status?.statusNameAr : action.labelAr,
      });
    }).toList();
  }

  int? get _selectedStatusId {
    final selected = _selectedStatus;
    if (selected == null) return null;
    return int.tryParse(selected.id);
  }

  Future<void> _submit() async {
    final selected = _selectedStatus;
    if (selected == null || _isSubmitting || _isConfirming) return;

    final statusId = int.tryParse(selected.id) ?? 0;
    final action = _actionFor(statusId);
    final row = _snapshot;
    if (action == null || !action.canExecute || row == null) return;
    if (action.group == 'progression') {
      await _submitProgression(action, row);
      return;
    }
    if (_requiresReason(statusId) && _selectedReason == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            Localizations.localeOf(context).languageCode == 'ar'
                ? 'يرجى اختيار السبب'
                : 'Please select a reason',
          ),
        ),
      );
      return;
    }
    String? feeAmount;
    if (_offersDoorFee(statusId) && _feeChoice != DoorFeeChoice.none) {
      final max =
          _snapshot?.financial?.doorFeeCollectable ?? widget.doorFeeCollectable;
      final amount =
          _feeChoice == DoorFeeChoice.full
              ? max
              : double.tryParse(_feeController.text.trim());
      // Display-side guard only; the server is the authority on the amount.
      if (amount == null || amount <= 0 || amount > max) {
        final isArabic = Localizations.localeOf(context).languageCode == 'ar';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isArabic
                  ? 'أدخل مبلغاً أكبر من صفر ولا يتجاوز ${max.toStringAsFixed(2)} د.أ'
                  : 'Enter an amount above zero and up to ${max.toStringAsFixed(2)} JOD',
            ),
          ),
        );
        return;
      }
      feeAmount = amount.toStringAsFixed(2);
    }
    if (isFinalTargetStatus(statusId) || statusId == 9) {
      _isConfirming = true;
      final confirmed = await _confirmFinalStatus(selected, statusId);
      _isConfirming = false;
      if (confirmed != true || !mounted || !_currentSession) return;
    }

    setState(() => _isSubmitting = true);
    final selectedReason = _selectedReason;
    try {
      await widget.onSubmit(
        selected,
        selectedReason == null
            ? null
            : StatusUpdateReasonPayload(
              reasonId: selectedReason.id,
              titleAr: selectedReason.titleAr,
              titleEn: selectedReason.titleEn,
              note: _reasonNoteController.text.trim(),
              feeCollectedAmount: feeAmount,
            ),
      );
    } catch (_) {
      if (mounted && _currentSession)
        setState(
          () =>
              _actionMessage =
                  Localizations.localeOf(context).languageCode == 'ar'
                      ? 'تعذر تنفيذ الإجراء؛ تم تحديث الشحنة.'
                      : 'Unable to complete the action; shipment refreshed.',
        );
    } finally {
      await _refreshContract();
      if (mounted && _currentSession) setState(() => _isSubmitting = false);
    }
  }

  bool _requiresReason(int statusId) =>
      statusId == 7 || statusId == 8 || statusId == 9;

  String? _actionTypeForStatus(int statusId) {
    return switch (statusId) {
      7 => 'cancel',
      8 => 'return',
      9 => 'failed_delivery',
      _ => null,
    };
  }

  Future<void> _loadReasonsIfNeeded(int statusId, {bool force = false}) async {
    final actionType = _actionTypeForStatus(statusId);
    if (actionType == null) return;
    if (_reasons.isNotEmpty && !force) return;

    setState(() {
      _isLoadingReasons = true;
      _reasonError = null;
      _reasons = _fallbackReasonsForAction(actionType);
    });

    try {
      final driverId = await AuthService.getuserId();
      final apiKey = await AuthService.getApiKey();
      if (driverId == null || apiKey == null || apiKey.trim().isEmpty) {
        throw Exception('missing_session');
      }
      final response = await Dio().post(
        AppUrls.shipmentActionReasons,
        options: Options(
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
            'X-API-KEY': apiKey,
          },
          validateStatus: (status) => status != null && status < 500,
        ),
        data: {
          'action_type': actionType,
          'actor_scope': 'driver',
          'driver_id': driverId,
        },
      );
      if (response.data is! Map ||
          response.data['status']?.toString().toLowerCase() != 'success') {
        throw Exception('load_failed');
      }
      final raw = response.data['data'];
      final loaded =
          raw is List
              ? raw
                  .whereType<Map>()
                  .map(
                    (item) => StatusReasonOption.fromJson(
                      Map<String, dynamic>.from(item),
                    ),
                  )
                  .where((item) => item.id > 0)
                  .toList(growable: false)
              : <StatusReasonOption>[];
      if (!mounted) return;
      setState(() {
        _reasons = _mergeReasons(_fallbackReasonsForAction(actionType), loaded);
        _reasonError = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _reasonError =
            Localizations.localeOf(context).languageCode == 'ar'
                ? 'تعذر تحميل الأسباب'
                : 'Unable to load reasons';
      });
    } finally {
      if (mounted) setState(() => _isLoadingReasons = false);
    }
  }

  List<StatusReasonOption> _fallbackReasonsForAction(String actionType) {
    return switch (actionType) {
      'failed_delivery' => const [
        StatusReasonOption(
          id: 1,
          titleAr: 'العميل لا يرد على الاتصالات',
          titleEn: 'Customer is not answering calls',
        ),
        StatusReasonOption(
          id: 2,
          titleAr: 'العنوان غير واضح أو غير صحيح',
          titleEn: 'Address is unclear or incorrect',
        ),
        StatusReasonOption(
          id: 3,
          titleAr: 'العميل طلب إعادة المحاولة لاحقاً',
          titleEn: 'Customer requested a later retry',
        ),
        StatusReasonOption(
          id: 4,
          titleAr: 'تعذر الوصول إلى موقع العميل',
          titleEn: 'Unable to access customer location',
        ),
      ],
      'return' => const [
        StatusReasonOption(
          id: 1,
          titleAr: 'العميل رفض استلام الشحنة',
          titleEn: 'Customer refused to receive the shipment',
        ),
        StatusReasonOption(
          id: 2,
          titleAr: 'العميل غير متواجد بعد عدة محاولات',
          titleEn: 'Customer unavailable after multiple attempts',
        ),
        StatusReasonOption(
          id: 3,
          titleAr: 'المستلم طلب إعادة الشحنة للمتجر',
          titleEn: 'Recipient requested return to store',
        ),
      ],
      'cancel' => const [
        StatusReasonOption(
          id: 1,
          titleAr: 'تعذر الوصول إلى نقطة الاستلام',
          titleEn: 'Unable to reach the pickup point',
        ),
        StatusReasonOption(
          id: 2,
          titleAr: 'المتجر طلب إلغاء الشحنة',
          titleEn: 'Store requested shipment cancellation',
        ),
        StatusReasonOption(
          id: 3,
          titleAr: 'لا يمكن تنفيذ الشحنة حالياً',
          titleEn: 'Shipment cannot be fulfilled right now',
        ),
      ],
      _ => const <StatusReasonOption>[],
    };
  }

  List<StatusReasonOption> _mergeReasons(
    List<StatusReasonOption> fallback,
    List<StatusReasonOption> loaded,
  ) {
    final merged = <StatusReasonOption>[];
    final seenKeys = <String>{};

    void push(StatusReasonOption reason) {
      final key =
          '${reason.titleAr.trim().toLowerCase()}|${reason.titleEn.trim().toLowerCase()}';
      if (seenKeys.add(key)) {
        merged.add(reason);
      }
    }

    for (final reason in loaded) {
      push(reason);
    }
    for (final reason in fallback) {
      push(reason);
    }

    return merged;
  }

  Future<bool?> _confirmFinalStatus(Status status, int statusId) {
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    final label = getStatusLabel(
      context,
      statusId,
      statusNameEn: status.statusNameEn,
      statusNameAr: status.statusNameAr,
    );

    return showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
            ),
            title: Text(
              isArabic ? 'تأكيد الحالة النهائية' : 'Confirm final status',
            ),
            content: Text(
              isArabic
                  ? 'بعد تأكيد حالة "$label" لن يمكن تعديل هذه الشحنة مرة أخرى.'
                  : 'After confirming "$label", this shipment cannot be updated again.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(isArabic ? 'إلغاء' : 'Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
                child: Text(isArabic ? 'تأكيد التحديث' : 'Confirm update'),
              ),
            ],
          ),
    );
  }
}

class StatusUpdateReasonPayload {
  const StatusUpdateReasonPayload({
    required this.reasonId,
    required this.titleAr,
    required this.titleEn,
    this.note,
    this.feeCollectedAmount,
  });

  final int reasonId;
  final String titleAr;
  final String titleEn;
  final String? note;

  /// Delivery fee taken at the door on a cancel/return ("12.50"); null = none.
  final String? feeCollectedAmount;
}

enum DoorFeeChoice { none, partial, full }

/// How much of the delivery fee the driver took at the door: none, part, or
/// all of the server's ceiling. Sent as fee_collected_amount.
class _DoorFeeSelector extends StatelessWidget {
  const _DoorFeeSelector({
    required this.maxAmount,
    required this.choice,
    required this.controller,
    required this.onChanged,
  });

  final double maxAmount;
  final DoorFeeChoice choice;
  final TextEditingController controller;
  final ValueChanged<DoorFeeChoice> onChanged;

  @override
  Widget build(BuildContext context) {
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    final max = maxAmount.toStringAsFixed(2);
    String label(DoorFeeChoice value) => switch (value) {
      DoorFeeChoice.none => isArabic ? 'لم أحصّل' : 'None',
      DoorFeeChoice.partial => isArabic ? 'جزء منها' : 'Partial',
      DoorFeeChoice.full => isArabic ? 'كاملة ($max د.أ)' : 'Full ($max JOD)',
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Container(
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
              isArabic
                  ? 'هل حصّلت أجرة التوصيل من العميل؟'
                  : 'Did you collect the delivery fee at the door?',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w900,
                color: Color(0xff0F172A),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final value in DoorFeeChoice.values)
                  ChoiceChip(
                    label: Text(label(value)),
                    selected: choice == value,
                    onSelected: (_) => onChanged(value),
                  ),
              ],
            ),
            if (choice == DoorFeeChoice.partial) ...[
              const SizedBox(height: 10),
              TextField(
                controller: controller,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  hintText:
                      isArabic
                          ? 'المبلغ المحصّل (حتى $max د.أ)'
                          : 'Amount collected (up to $max JOD)',
                  suffixText: isArabic ? 'د.أ' : 'JOD',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 6),
            Text(
              isArabic
                  ? 'أي أجرة تحصّلها تُضاف إلى النقد الواجب تسليمه.'
                  : 'Any fee you collect is added to the cash you hand over.',
              style: const TextStyle(fontSize: 11.5, color: Color(0xff64748B)),
            ),
          ],
        ),
      ),
    );
  }
}

class StatusReasonOption {
  const StatusReasonOption({
    required this.id,
    required this.titleAr,
    required this.titleEn,
  });

  final int id;
  final String titleAr;
  final String titleEn;

  factory StatusReasonOption.fromJson(Map<String, dynamic> json) {
    return StatusReasonOption(
      id: int.tryParse(json['id']?.toString() ?? '') ?? 0,
      titleAr: json['title_ar']?.toString() ?? '',
      titleEn: json['title_en']?.toString() ?? '',
    );
  }

  String title(bool isArabic) {
    final preferred = isArabic ? titleAr : titleEn;
    final fallback = isArabic ? titleEn : titleAr;
    return preferred.trim().isNotEmpty ? preferred : fallback;
  }
}

class _ReasonSelector extends StatelessWidget {
  const _ReasonSelector({
    required this.reasons,
    required this.selectedReason,
    required this.isLoading,
    required this.error,
    required this.noteController,
    required this.onChanged,
    required this.onRetry,
  });

  final List<StatusReasonOption> reasons;
  final StatusReasonOption? selectedReason;
  final bool isLoading;
  final String? error;
  final TextEditingController noteController;
  final ValueChanged<StatusReasonOption?> onChanged;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Container(
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
              isArabic ? 'سبب الإجراء' : 'Action reason',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w900,
                color: Color(0xff0F172A),
              ),
            ),
            const SizedBox(height: 8),
            if (isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(8),
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else if (error != null && reasons.isEmpty)
              Row(
                children: [
                  Expanded(
                    child: Text(
                      error!,
                      style: const TextStyle(color: Color(0xffDC2626)),
                    ),
                  ),
                  TextButton(
                    onPressed: onRetry,
                    child: Text(isArabic ? 'إعادة' : 'Retry'),
                  ),
                ],
              )
            else
              DropdownButtonFormField<StatusReasonOption>(
                value: selectedReason,
                isExpanded: true,
                decoration: InputDecoration(
                  hintText: isArabic ? 'اختر السبب' : 'Select reason',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                items:
                    reasons
                        .map(
                          (reason) => DropdownMenuItem(
                            value: reason,
                            child: Text(
                              reason.title(isArabic),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                onChanged: onChanged,
              ),
            const SizedBox(height: 10),
            TextField(
              controller: noteController,
              maxLines: 2,
              maxLength: 500,
              decoration: InputDecoration(
                hintText: isArabic ? 'ملاحظة اختيارية' : 'Optional note',
                border: OutlineInputBorder(
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

class _StatusSheetHeader extends StatelessWidget {
  const _StatusSheetHeader({
    required this.title,
    required this.subtitle,
    required this.currentStatusLabel,
    this.policyNumber,
  });

  final String title;
  final String subtitle;
  final String currentStatusLabel;
  final String? policyNumber;

  @override
  Widget build(BuildContext context) {
    final policy = policyNumber?.trim();

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primary, AppColors.gradient2],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const Icon(
                  Icons.edit_note_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.76),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (policy != null && policy.isNotEmpty) ...[
            const SizedBox(height: 13),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _HeaderPill(
                  icon: Icons.confirmation_number_outlined,
                  text: policy,
                ),
                _HeaderPill(
                  icon: Icons.fact_check_outlined,
                  text: currentStatusLabel,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _HeaderPill extends StatelessWidget {
  const _HeaderPill({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 15),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 190),
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CurrentStatusCard extends StatelessWidget {
  const _CurrentStatusCard({
    required this.label,
    required this.statusLabel,
    required this.statusId,
    this.stageLabel,
  });

  final String label;
  final String statusLabel;
  final int statusId;
  final String? stageLabel;

  @override
  Widget build(BuildContext context) {
    final color = getStatusColor(statusId);
    final stage = stageLabel?.trim();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xffF8FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xffE2E8F0)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(getStatusIcon(statusId), color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xff64748B),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  statusLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xff0F172A),
                    fontSize: 14.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (stage != null && stage.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    stage,
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
        ],
      ),
    );
  }
}

class _StatusOptionCard extends StatelessWidget {
  const _StatusOptionCard({
    super.key,
    required this.status,
    required this.statusId,
    required this.selected,
    required this.onTap,
    this.helperText,
  });

  final String? helperText;
  final Status status;
  final int statusId;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final label = getStatusLabel(
      context,
      statusId,
      statusNameEn: status.statusNameEn,
      statusNameAr: status.statusNameAr,
    );
    final color = getStatusColor(statusId);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color:
                selected
                    ? color.withValues(alpha: 0.10)
                    : const Color(0xffFFFFFF),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? color : const Color(0xffE2E8F0),
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(getStatusIcon(statusId), color: color, size: 22),
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
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xff0F172A),
                              fontSize: 14.5,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        if (isFinalTargetStatus(statusId))
                          _FinalChip(statusId: statusId),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      helperText ?? getStatusHelperText(context, statusId),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
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
              const SizedBox(width: 8),
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: selected ? color : const Color(0xffCBD5E1),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FinalChip extends StatelessWidget {
  const _FinalChip({required this.statusId});

  final int statusId;

  @override
  Widget build(BuildContext context) {
    final color = getStatusColor(statusId);
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        isArabic ? 'نهائية' : 'Final',
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _FinalStatusWarning extends StatelessWidget {
  const _FinalStatusWarning({required this.statusId});

  final int statusId;

  @override
  Widget build(BuildContext context) {
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    final color = getStatusColor(statusId);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_outline_rounded, color: color, size: 20),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              isArabic
                  ? 'هذه حالة نهائية. بعد تأكيدها لن تتمكن من تعديل الحالة مرة أخرى.'
                  : 'This is a final status. After confirmation, this shipment status cannot be changed again.',
              style: TextStyle(
                color: color,
                fontSize: 12,
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

class _LockedStatusView extends StatelessWidget {
  const _LockedStatusView({
    required this.currentStatusLabel,
    required this.currentStatusId,
    this.policyNumber,
  });

  final String currentStatusLabel;
  final int currentStatusId;
  final String? policyNumber;

  @override
  Widget build(BuildContext context) {
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    final policy = policyNumber?.trim();

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xffCBD5E1),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(height: 20),
          Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              color: const Color(0xffEF4444).withValues(alpha: 0.09),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(
              Icons.lock_outline_rounded,
              color: Color(0xffEF4444),
              size: 30,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            isArabic ? 'حالة الشحنة نهائية' : 'Shipment status is final',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xff0F172A),
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isArabic
                ? 'لا يمكن تعديل حالة هذه الشحنة بعد إغلاقها.'
                : 'This shipment cannot be updated after it has been closed.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xff64748B),
              fontSize: 13,
              height: 1.4,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          _CurrentStatusCard(
            label: isArabic ? 'الحالة الحالية' : 'Current status',
            statusLabel: currentStatusLabel,
            stageLabel: policy == null || policy.isEmpty ? null : policy,
            statusId: currentStatusId,
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: Text(
                isArabic ? 'إغلاق' : 'Close',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

const Map<int, String> _fallbackStatusLabelsEn = {
  1: 'Pending',
  2: 'Processing',
  3: 'Dispatched',
  4: 'In Transit',
  5: 'Out for Delivery',
  6: 'Delivered',
  7: 'Cancelled',
  8: 'Returned',
  9: 'Failed Delivery',
  10: 'Awaiting Pickup',
  11: 'Completed',
};

const Map<int, String> _fallbackStatusLabelsAr = {
  1: 'قيد الانتظار',
  2: 'قيد التجهيز',
  3: 'تم الشحن',
  4: 'في الطريق',
  5: 'في انتظار التسليم',
  6: 'تم التسليم',
  7: 'تم الإلغاء',
  8: 'تم الإرجاع',
  9: 'فشل في التسليم',
  10: 'في انتظار الاستلام',
  11: 'مكتمل',
};

const Map<int, String> _statusHelpersEn = {
  2: 'The shipment has been prepared by the store or operations team.',
  3: 'The shipment is ready for dispatch.',
  4: 'The shipment is with the driver and moving on the route.',
  5: 'The driver is near the customer delivery stage.',
  6: 'The shipment was delivered successfully.',
  7: 'The shipment has been cancelled.',
  8: 'The shipment has been returned.',
  9: 'The shipment could not be delivered to the customer.',
  10: 'The shipment is waiting to be picked up from the store.',
  11: 'The shipment workflow is completed.',
};

const Map<int, String> _statusHelpersAr = {
  2: 'تم تجهيز الشحنة من المتجر أو فريق العمليات.',
  3: 'تم تجهيز الشحنة للشحن.',
  4: 'الشحنة مع السائق وفي الطريق.',
  5: 'السائق قريب من مرحلة تسليم العميل.',
  6: 'تم تسليم الشحنة بنجاح.',
  7: 'تم إلغاء الشحنة.',
  8: 'تم إرجاع الشحنة.',
  9: 'تعذر تسليم الشحنة للعميل.',
  10: 'الشحنة في انتظار الاستلام من المتجر.',
  11: 'تم اكتمال مسار الشحنة.',
};
