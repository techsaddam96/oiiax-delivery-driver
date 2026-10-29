import 'package:blockatie/constants/notification_routes.dart';
import 'package:blockatie/models/notifications.dart';
import 'package:flutter/material.dart';

/// Turns an inbox row into the payload the routing resolver understands.
///
/// An inbox notification and a push are the same event recorded two ways, so
/// this maps the row's authoritative fields onto the payload keys the resolver
/// already validates. Only fields the verified type contract defines are
/// mapped; nothing is inferred from prose, and `url` is never parsed for an
/// entity id.
///
/// Returns null when the row carries nothing routable, which is the signal to
/// show the notification's own text instead of guessing a screen.
Map<String, dynamic>? notificationRoutePayload(NotificationItem notification) {
  final type = notification.type.trim();
  if (type.isEmpty) return null;

  final itemId = notification.itemId;
  final payload = <String, dynamic>{
    'type': type,
    if (notification.id > 0) 'notification_id': notification.id,
  };

  if (type == DriverNotificationTypes.driverSettlement) {
    if (itemId <= 0) return null;
    payload['settlement_id'] = itemId;
    return payload;
  }

  if (DriverNotificationTypes.assignedShipment.contains(type)) {
    if (itemId <= 0) return null;
    payload['shipment_id'] = itemId;
    return payload;
  }

  if (DriverNotificationTypes.availableShipment.contains(type)) {
    // The tab is the destination with or without an id; the shipment is an
    // offer, not something this driver owns.
    if (itemId > 0) payload['shipment_id'] = itemId;
    return payload;
  }

  if (type == DriverNotificationTypes.driverChatMessage) {
    // `item_id` on a chat row is the message id, never the conversation, and
    // only a conversation can select a screen. The inbox does not carry one,
    // so a chat row is opened from the Chat screen rather than routed from a
    // fabricated id.
    return null;
  }

  return null;
}

/// The app's own wording for a type, used when the server sent no title.
///
/// Never the raw type prettified into English: `available_shipment` became
/// "Available Shipment" in Latin script inside an Arabic page.
String notificationTypeTitle(BuildContext context, String type) {
  final isArabic = Localizations.localeOf(context).languageCode == 'ar';
  final normalized = type.trim();

  if (normalized == DriverNotificationTypes.driverSettlement) {
    return isArabic ? 'تسوية' : 'Settlement';
  }
  if (normalized == DriverNotificationTypes.driverChatMessage) {
    return isArabic ? 'رسالة جديدة' : 'New message';
  }
  if (DriverNotificationTypes.availableShipment.contains(normalized)) {
    return isArabic ? 'شحنة متاحة' : 'Available shipment';
  }
  if (DriverNotificationTypes.assignedShipment.contains(normalized)) {
    return isArabic ? 'تحديث شحنة' : 'Shipment update';
  }

  return isArabic ? 'إشعار' : 'Notification';
}

/// One icon per type, matched exactly rather than by looking for English
/// words inside the type string.
IconData notificationTypeIcon(String type) {
  final normalized = type.trim();

  if (normalized == DriverNotificationTypes.driverSettlement) {
    return Icons.receipt_long_outlined;
  }
  if (normalized == DriverNotificationTypes.driverChatMessage) {
    return Icons.chat_bubble_outline_rounded;
  }
  if (DriverNotificationTypes.availableShipment.contains(normalized)) {
    return Icons.local_offer_outlined;
  }
  if (DriverNotificationTypes.assignedShipment.contains(normalized)) {
    return Icons.local_shipping_outlined;
  }

  return Icons.notifications_none_rounded;
}
