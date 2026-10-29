/// Maps an incoming FCM payload to a Driver destination.
///
/// Kept free of Firebase and widget imports so the mapping can be unit tested
/// directly. Resolution is pure: it decides *where* to go, never *what to show*.
/// Screen content is always re-fetched from the backend, because a notification
/// is a signal and its payload is not the source of truth.
library;

enum DriverNotificationDestination {
  /// Settlement detail for `settlement_id`.
  settlementDetails,

  /// Details for a shipment assigned to this driver (`shipment_id`).
  shipmentDetails,

  /// The available/instant shipments tab. These are offers, not assignments,
  /// so there is no owned shipment to open yet.
  availableShipments,

  /// One chat thread, named by `conversation_id`. Ownership is proven against
  /// the Chat API before anything is opened; the payload only says which
  /// resource to ask about.
  chatConversation,
}

/// A resolved, validated navigation target.
class DriverNotificationTarget {
  const DriverNotificationTarget({
    required this.destination,
    required this.type,
    this.shipmentId,
    this.settlementId,
    this.policyNum,
    this.conversationId,
    this.messageId,
    this.notificationId,
  });

  final DriverNotificationDestination destination;
  final String type;
  final int? shipmentId;
  final int? settlementId;
  final String? policyNum;

  /// The chat thread to open. The only chat identifier that selects a screen.
  final int? conversationId;

  /// Carried for de-duplication only. Never used to decide access.
  final int? messageId;
  final int? notificationId;

  /// Stable identity for duplicate suppression. Scoped per driver by the caller.
  String get dedupeKey => switch (destination) {
    DriverNotificationDestination.settlementDetails =>
      'driver_settlement:$settlementId',
    DriverNotificationDestination.shipmentDetails => 'shipment:$shipmentId',
    DriverNotificationDestination.availableShipments =>
      'available_shipment:${shipmentId ?? 0}',
    // Keyed on the server's own row id, falling back to the message id, so two
    // notifications about different messages stay distinct and a tap on the
    // second is not swallowed as a repeat of the first. Only when the backend
    // sent neither does this collapse to the thread, which at worst means two
    // taps open the same screen once.
    DriverNotificationDestination.chatConversation =>
      'driver_chat:${notificationId ?? messageId ?? 'conversation:$conversationId'}',
  };
}

/// Notification types the Driver app knows how to route.
///
/// Values match the `type` field the backend puts in its FCM data payload.
/// Anything not listed here is ignored rather than guessed at.
class DriverNotificationTypes {
  const DriverNotificationTypes._();

  static const String driverSettlement = 'driver_settlement';

  /// Shipments already assigned to this driver.
  static const Set<String> assignedShipment = {
    'shipment_assigned',
    'shipment_updated',
    'shipment_status_updated',
    'shipment_collected',
    'shipment',
    'new_shipment',
  };

  /// Offers broadcast to nearby drivers; not yet owned by anyone.
  static const Set<String> availableShipment = {'available_shipment'};

  /// A new incoming chat message, emitted by services/api_driver_chat.php.
  static const String driverChatMessage = 'driver_chat_message';
}

/// Resolves a payload to a target, or null when it cannot be routed safely.
///
/// Returns null for an unknown type, a missing id or an unparsable id, so a
/// malformed notification is a no-op rather than a crash or a wrong screen.
DriverNotificationTarget? resolveDriverNotificationTarget(
  Map<String, dynamic> data,
) {
  final type = data['type']?.toString().trim() ?? '';
  if (type.isEmpty) return null;

  if (type == DriverNotificationTypes.driverSettlement) {
    final settlementId = _positiveId(data['settlement_id']);
    if (settlementId == null) return null;
    return DriverNotificationTarget(
      destination: DriverNotificationDestination.settlementDetails,
      type: type,
      settlementId: settlementId,
    );
  }

  if (DriverNotificationTypes.assignedShipment.contains(type)) {
    final shipmentId = _positiveId(data['shipment_id']);
    if (shipmentId == null) return null;
    return DriverNotificationTarget(
      destination: DriverNotificationDestination.shipmentDetails,
      type: type,
      shipmentId: shipmentId,
      policyNum: _cleanText(data['policy_num']),
    );
  }

  if (type == DriverNotificationTypes.driverChatMessage) {
    // conversation_id is the only field that can select a screen. Everything
    // else here is metadata: shipment_id is never consulted for access, and a
    // driver_id in the payload is simply never read, so a forged one cannot
    // redirect anything.
    final conversationId = _positiveId(data['conversation_id']);
    if (conversationId == null) return null;
    return DriverNotificationTarget(
      destination: DriverNotificationDestination.chatConversation,
      type: type,
      conversationId: conversationId,
      messageId: _positiveId(data['message_id']),
      notificationId: _positiveId(data['notification_id']),
      shipmentId: _positiveId(data['shipment_id']),
    );
  }

  if (DriverNotificationTypes.availableShipment.contains(type)) {
    // The tab is still a valid destination without an id, so this one is
    // routable either way.
    return DriverNotificationTarget(
      destination: DriverNotificationDestination.availableShipments,
      type: type,
      shipmentId: _positiveId(data['shipment_id']),
      policyNum: _cleanText(data['policy_num']),
    );
  }

  return null;
}

/// Accepts ints and numeric strings; rejects zero, negatives and junk.
int? _positiveId(dynamic value) {
  if (value == null) return null;
  final parsed = value is int ? value : int.tryParse(value.toString().trim());
  if (parsed == null || parsed <= 0) return null;
  return parsed;
}

String? _cleanText(dynamic value) {
  final text = value?.toString().trim() ?? '';
  if (text.isEmpty || text.toLowerCase() == 'null') return null;
  return text;
}
