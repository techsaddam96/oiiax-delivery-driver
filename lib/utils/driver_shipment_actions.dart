import 'package:blockatie/services/driver_action_service.dart';
import 'package:blockatie/models/shipment.dart';
import 'package:blockatie/provider/shipment_instsnt.dart';
import 'package:blockatie/utils/money.dart';
import 'package:blockatie/views/widgets/status_update_sheet.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Presentation adapter for the server's versioned per-shipment capabilities.
/// Endpoint methods still independently validate every action. Missing contracts
/// expose no executable quick step; the existing sheet can reload capabilities.
enum DriverShipmentStep { arriveAtStore, pickUp, deliver }

/// The shared "Update Status" sheet has two deliberately separate uses:
///
/// * while the shipment is still at pickup, it is an exception-only surface;
/// * once the server has confirmed pickup, it may expose delivery actions.
///
/// This is intentionally derived from the server action contract as well as
/// the authoritative pickup boundary.  A cached label such as "In Transit"
/// is never sufficient to make a delivery action visible.
enum DriverStatusSheetMode { unavailable, prePickupExceptions, delivery }

/// Why a shipment shows no forward step.
enum DriverStepBlock {
  contractUnavailable,

  /// Not accepted by anyone yet; the instant list offers Accept.
  notAccepted,

  /// A status only dispatch moves on, such as 5 (Out for Delivery): delivery
  /// is accepted from 4 alone, and nothing lets the driver return to 4.
  dispatchControlled,

  /// A final status (see [finalShipmentStatusIds]).
  closed,

  /// The server refused a step because the shipment is no longer this
  /// driver's (reassigned, released or removed), and a re-read confirmed it.
  reassigned,
}

/// check_driver_arrival.php ARRIVAL_FROM_STATUSES.
const Set<int> driverArrivalFromStatusIds = {1, 2, 3};

/// mark_as_arrived_driver.php, DRIVER_PICKUP_FROM_STATUS_IDS.
const Set<int> driverPickupFromStatusIds = {2, 10};

/// The backend states in which a driver-owned shipment is still at its
/// pickup source. This is deliberately status-based rather than inferred from
/// a card label or delivery type:
///
/// * check_driver_arrival.php accepts 1, 2 and 3 and moves to 10;
/// * mark_as_arrived_driver.php accepts 2 or 10 and moves to 4.
///
/// A direct dispatch assignment has the same pickup boundary as an accepted
/// instant shipment. Keeping this in the shared presentation adapter prevents
/// a scheduled/admin-assigned card from routing to, calling, or displaying a
/// recipient before the backend has confirmed pickup.
const Set<int> driverPrePickupStatusIds = {1, 2, 3, 10};

/// Whether this driver's currently owned shipment is still in the store (or
/// other pickup-source) stage. Terminal/cancellation branches deliberately do
/// not pass through here: their existing screens keep their own return and
/// custody presentation unchanged.
bool driverShipmentIsPrePickup(Shipment shipment) =>
    shipment.driverId > 0 &&
    driverPrePickupStatusIds.contains(driverStatusIdOf(shipment));

class DriverShipmentActions {
  const DriverShipmentActions({
    this.primary,
    this.secondary,
    this.canReportException = false,
    this.block,
  });

  /// The next step, shown prominently.
  final DriverShipmentStep? primary;

  /// A second step the server accepts from the same status: pickup straight
  /// from 2, for a driver who already holds the shipment (arrival is optional
  /// on the server, and a store without coordinates can never confirm it).
  final DriverShipmentStep? secondary;

  /// Cancelled / Returned / Failed Delivery through the shared status sheet,
  /// which update_shipment_status.php accepts from any open status.
  final bool canReportException;

  /// Set when [primary] is null.
  final DriverStepBlock? block;
}

/// The status the shipment is in, preferring the dedicated column.
int driverStatusIdOf(Shipment shipment) =>
    shipment.shipmentStatusId != 0
        ? shipment.shipmentStatusId
        : shipment.shipmentStatus;

/// The steps for a shipment in [statusId] held by [driverId] (0 when nobody
/// has accepted it). The driver lists only ever carry the driver's own
/// shipments and unclaimed offers, so any other id is this driver's; the
/// server refuses the call otherwise.
DriverShipmentActions driverShipmentActionsFor({
  required int statusId,
  required int driverId,
  Shipment? shipment,
}) {
  if (shipment == null ||
      !shipment.hasActionContract ||
      driverStatusIdOf(shipment) != statusId) {
    return const DriverShipmentActions(
      block: DriverStepBlock.contractUnavailable,
    );
  }
  final allowed = shipment.allowsAction;
  final arrive = allowed('arrive_at_pickup');
  final pickup = allowed('confirm_pickup');
  final deliver = allowed('complete_delivery');
  return DriverShipmentActions(
    primary:
        deliver
            ? DriverShipmentStep.deliver
            : arrive
            ? DriverShipmentStep.arriveAtStore
            : pickup
            ? DriverShipmentStep.pickUp
            : null,
    secondary: arrive && pickup ? DriverShipmentStep.pickUp : null,
    canReportException:
        allowed('cancel_shipment') ||
        allowed('return_shipment') ||
        allowed('failed_delivery'),
    block:
        deliver || arrive || pickup
            ? null
            : isFinalShipmentStatus(statusId)
            ? DriverStepBlock.closed
            : driverId <= 0
            ? DriverStepBlock.notAccepted
            : DriverStepBlock.dispatchControlled,
  );
}

DriverShipmentActions driverShipmentActionsForShipment(Shipment shipment) =>
    driverShipmentActionsFor(
      statusId: driverStatusIdOf(shipment),
      driverId: shipment.driverId,
      shipment: shipment,
    );

/// Resolves whether the shared status sheet can be opened for this snapshot.
///
/// Unclaimed instant offers deliberately have no sheet: their only action is
/// the dedicated Accept Shipment control.  Before confirmed pickup, the
/// driver may still use any server-authorized cancellation/return/failure
/// off-ramp, but cannot see delivery-stage actions.  Closed and contract-less
/// snapshots fail closed.
DriverStatusSheetMode driverStatusSheetModeForShipment(Shipment shipment) {
  if (!shipment.hasActionContract ||
      shipment.driverId <= 0 ||
      isFinalShipmentStatus(driverStatusIdOf(shipment))) {
    return DriverStatusSheetMode.unavailable;
  }

  final actions = driverShipmentActionsForShipment(shipment);
  if (driverShipmentIsPrePickup(shipment)) {
    return actions.canReportException
        ? DriverStatusSheetMode.prePickupExceptions
        : DriverStatusSheetMode.unavailable;
  }

  return shipment.allowsAction('complete_delivery') ||
          actions.canReportException
      ? DriverStatusSheetMode.delivery
      : DriverStatusSheetMode.unavailable;
}

/// Whether a card may render its compact Update Status launcher.
///
/// The shared sheet can still serve server-authorized pre-pickup exceptions
/// from the tracking screen.  The compact card launcher, however, must not
/// compete with the primary Arrived at Store action.  It becomes visible only
/// after the backend has recorded arrival (10), or after confirmed pickup.
/// This deliberately requires the current server action contract; a cached
/// label, a locally changed status, a reassignment, or a missing contract all
/// fail closed.
bool driverStatusSheetCardLauncherIsVisible(Shipment shipment) {
  if (driverStatusSheetModeForShipment(shipment) ==
      DriverStatusSheetMode.unavailable) {
    return false;
  }

  final statusId = driverStatusIdOf(shipment);
  return statusId == 10 || !driverShipmentIsPrePickup(shipment);
}

/// Whether the card may open the full shipment-details route.
///
/// The card must not expose that route while the driver is merely assigned or
/// travelling to the store. A successful arrival request is reflected by the
/// fresh server snapshot as status 10 *and* an enabled pickup action. This
/// pairs the lifecycle state with the current action contract instead of
/// trusting a visible label or a locally optimistic state change. Once pickup
/// is confirmed, or for later return/history states, the route remains
/// available as before.
bool driverShipmentDetailsCardLauncherIsVisible(Shipment shipment) {
  if (!shipment.hasActionContract || shipment.driverId <= 0) return false;

  final statusId = driverStatusIdOf(shipment);
  if (shipment.allowsAction('arrive_at_pickup')) return false;
  if (statusId == 10) return shipment.allowsAction('confirm_pickup');
  return !driverShipmentIsPrePickup(shipment);
}

/// Whether one action from the *fresh* contract belongs in the shared sheet.
///
/// Keeping this rule next to the lifecycle adapter means every launcher (list,
/// details, tracking and deep-link screens) applies exactly the same boundary.
/// The sheet still re-fetches its snapshot before rendering, so this helper is
/// never an authorization substitute for the server.
bool driverStatusSheetAllowsAction({
  required DriverStatusSheetMode mode,
  required String actionId,
  required String actionGroup,
  required bool canExecute,
}) {
  if (!canExecute) return false;
  return switch (mode) {
    DriverStatusSheetMode.prePickupExceptions => actionGroup == 'exception',
    DriverStatusSheetMode.delivery =>
      actionGroup == 'exception' || actionId == 'complete_delivery',
    DriverStatusSheetMode.unavailable => false,
  };
}

bool _isArabic(BuildContext context) =>
    Localizations.localeOf(context).languageCode == 'ar';

String _text(BuildContext context, String en, String ar) =>
    _isArabic(context) ? ar : en;

String driverStepLabel(BuildContext context, DriverShipmentStep step) {
  return switch (step) {
    DriverShipmentStep.arriveAtStore => _text(
      context,
      'Arrived at Store',
      'وصلت إلى المتجر',
    ),
    DriverShipmentStep.pickUp => _text(
      context,
      'Picked Up Shipment',
      'استلام الشحنة',
    ),
    DriverShipmentStep.deliver => _text(
      context,
      'Mark as Delivered',
      'تم التسليم',
    ),
  };
}

IconData driverStepIcon(DriverShipmentStep step) {
  return switch (step) {
    DriverShipmentStep.arriveAtStore => Icons.store_mall_directory_outlined,
    DriverShipmentStep.pickUp => Icons.inventory_2_outlined,
    DriverShipmentStep.deliver => Icons.task_alt_rounded,
  };
}

/// Stable keys, so a step can be found the same way on every screen.
ValueKey<String> driverStepKey(DriverShipmentStep step) {
  return switch (step) {
    DriverShipmentStep.arriveAtStore => const ValueKey('arrive_action'),
    DriverShipmentStep.pickUp => const ValueKey('pickup_action'),
    DriverShipmentStep.deliver => const ValueKey('deliver_action'),
  };
}

/// One sentence telling the driver what comes next, or why nothing does.
///
/// [offersStatusUpdate] is false on a card without the Update Status entry
/// (the active instant card), so the hint never points at a control the
/// driver cannot see.
String? driverNextStepHint(
  BuildContext context,
  DriverShipmentActions actions, {
  bool offersStatusUpdate = true,
}) {
  switch (actions.primary) {
    case DriverShipmentStep.arriveAtStore:
      return actions.secondary == DriverShipmentStep.pickUp
          ? _text(
            context,
            'Next: confirm your arrival at the store. Already holding the shipment? Confirm the pickup directly.',
            'الخطوة التالية: أكّد وصولك إلى المتجر. استلمت الشحنة بالفعل؟ أكّد الاستلام مباشرة.',
          )
          : _text(
            context,
            'Next: confirm your arrival at the store. The server checks your location.',
            'الخطوة التالية: أكّد وصولك إلى المتجر، ويتحقق الخادم من موقعك.',
          );
    case DriverShipmentStep.pickUp:
      return _text(
        context,
        'Next: confirm you received the shipment from the store.',
        'الخطوة التالية: أكّد استلام الشحنة من المتجر.',
      );
    case DriverShipmentStep.deliver:
      return _text(
        context,
        'Next: hand the shipment to the recipient, then mark it as delivered.',
        'الخطوة التالية: سلّم الشحنة للمستلم ثم أكّد التسليم.',
      );
    case null:
      break;
  }
  return switch (actions.block) {
    DriverStepBlock.dispatchControlled when offersStatusUpdate => _text(
      context,
      'Delivery can be confirmed only from In Transit, and dispatch controls this status. Contact dispatch, or report a problem with Update Status.',
      'لا يمكن تأكيد التسليم إلا من حالة «في الطريق»، وهذه الحالة يتحكم بها فريق التوزيع. تواصل مع فريق التوزيع أو أبلغ عن مشكلة من «تحديث الحالة».',
    ),
    DriverStepBlock.dispatchControlled => _text(
      context,
      'Dispatch controls this status. Contact dispatch, or open tracking to report a problem.',
      'يتحكم فريق التوزيع بهذه الحالة. تواصل مع فريق التوزيع أو افتح التتبع للإبلاغ عن مشكلة.',
    ),
    DriverStepBlock.reassigned => _text(
      context,
      'This shipment is no longer assigned to you.',
      'لم تعد هذه الشحنة مسندة إليك.',
    ),
    DriverStepBlock.contractUnavailable => _text(
      context,
      'Refresh shipment actions. The server action contract is unavailable.',
      'حدّث إجراءات الشحنة. بيانات الإجراءات من الخادم غير متاحة.',
    ),
    _ => null,
  };
}

/// Asks before Delivered (تم التسليم), which is final and settles the COD.
Future<bool> confirmDriverDelivery(
  BuildContext context, {
  required String policyNumber,
  required double amountToCollect,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder:
        (dialogContext) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          title: Text(_text(context, 'Mark as Delivered?', 'تأكيد التسليم؟')),
          content: Text(
            [
              _text(
                context,
                'Confirm that shipment $policyNumber was handed to the recipient.',
                'أكّد أنه تم تسليم الشحنة $policyNumber إلى المستلم.',
              ),
              if (amountToCollect > 0)
                _text(
                  context,
                  'Amount to collect: ${formatMoney(context, amountToCollect)}',
                  'المبلغ المطلوب تحصيله: ${formatMoney(context, amountToCollect)}',
                ),
              _text(
                context,
                'This is final and cannot be changed afterwards.',
                'هذه حالة نهائية ولا يمكن تعديلها بعد ذلك.',
              ),
            ].join('\n\n'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(_text(context, 'Cancel', 'إلغاء')),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xff16A06D),
                foregroundColor: Colors.white,
              ),
              child: Text(_text(context, 'Mark as Delivered', 'تم التسليم')),
            ),
          ],
        ),
  );
  return confirmed == true;
}

/// Asks before a pickup straight from 2, which skips the geofenced arrival
/// (and the store's arrival notice with it).
Future<bool> confirmDirectPickup(
  BuildContext context, {
  required String policyNumber,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder:
        (dialogContext) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          title: Text(_text(context, 'Confirm pickup?', 'تأكيد الاستلام؟')),
          content: Text(
            _text(
              context,
              'Confirm that you received shipment $policyNumber from the pickup source. The optional arrival check is skipped.',
              'أكّد أنك استلمت الشحنة $policyNumber من مصدر الاستلام. سيتم تخطي تأكيد الوصول الاختياري.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(_text(context, 'Cancel', 'إلغاء')),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(_text(context, 'Confirm pickup', 'تأكيد الاستلام')),
            ),
          ],
        ),
  );
  return confirmed == true;
}

/// Whether a refused step means the screen is out of date and the shipment has
/// to be read again rather than offered for another tap: its status, its
/// driver or its existence changed on the server, or no reply came back.
bool driverStepRefusalIsStale(ShipmentActionResult result) {
  if (result.success) return false;
  return result.unconfirmed ||
      result.isStateConflict ||
      result.httpStatus == 403 ||
      result.httpStatus == 404 ||
      const {
        'TRANSITION_NOT_ALLOWED',
        'SHIPMENT_ALREADY_FINAL',
        'SHIPMENT_STATUS_FINAL_LOCKED',
        'NOT_ASSIGNED',
        'SHIPMENT_NOT_ASSIGNED',
        'SHIPMENT_ASSIGNED_TO_ANOTHER_DRIVER',
        'SHIPMENT_NOT_FOUND',
      }.contains(result.code);
}

/// Whether a refused step says the shipment is no longer this driver's at
/// all — reassigned, released or removed — rather than only in another
/// status. Codes only: a bare 403 also means an inactive subscription.
bool driverStepRefusalLostShipment(ShipmentActionResult result) {
  if (result.success) return false;
  return result.httpStatus == 404 ||
      const {
        'NOT_ASSIGNED',
        'SHIPMENT_NOT_ASSIGNED',
        'SHIPMENT_ASSIGNED_TO_ANOTHER_DRIVER',
        'SHIPMENT_NOT_FOUND',
      }.contains(result.code);
}

/// Runs [step] for [shipment] through the one provider method for it, asking
/// first where the step needs it. Null when the driver cancelled.
///
/// For the list cards; the details screen keeps its own handlers because it
/// also reconciles its local copy of the shipment.
Future<ShipmentActionResult?> performDriverShipmentStep(
  BuildContext context, {
  required Shipment shipment,
  required DriverShipmentStep step,
}) async {
  final fresh = await DriverActionService.read(context).fetch(shipment.id);
  if (!context.mounted) return null;
  if (fresh == null)
    return const ShipmentActionResult(
      success: false,
      code: 'ACTION_CONTRACT_UNAVAILABLE',
      message: 'Refresh shipment actions.',
    );
  final actionId = switch (step) {
    DriverShipmentStep.arriveAtStore => 'arrive_at_pickup',
    DriverShipmentStep.pickUp => 'confirm_pickup',
    DriverShipmentStep.deliver => 'complete_delivery',
  };
  if (!fresh.allowsAction(actionId))
    return const ShipmentActionResult(
      success: false,
      code: 'ACTION_NOT_ALLOWED',
      message: 'This action is no longer available.',
    );
  shipment = fresh;
  final provider = context.read<ShipmentInstantprovider>();
  if (provider.isShipmentBusy(shipment.id)) return null;
  final policyNumber = shipment.policyNum.trim();

  if (step == DriverShipmentStep.deliver) {
    final confirmed = await confirmDriverDelivery(
      context,
      policyNumber: policyNumber,
      amountToCollect: shipment.productToCollect,
    );
    if (!confirmed || !context.mounted) return null;
  } else if (step == DriverShipmentStep.pickUp &&
      driverStatusIdOf(shipment) != 10) {
    final confirmed = await confirmDirectPickup(
      context,
      policyNumber: policyNumber,
    );
    if (!confirmed || !context.mounted) return null;
  }

  final languageCode = _isArabic(context) ? 'ar' : 'en';
  return switch (step) {
    DriverShipmentStep.arriveAtStore => provider.markArrivedAtStore(
      shipment.id,
      languageCode: languageCode,
    ),
    DriverShipmentStep.pickUp => provider.pickupShipmentFromStore(
      shipment.id,
      languageCode: languageCode,
    ),
    DriverShipmentStep.deliver => provider.deliverShipment(
      shipment.id,
      languageCode: languageCode,
    ),
  };
}
