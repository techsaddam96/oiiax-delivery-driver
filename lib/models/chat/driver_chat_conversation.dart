import 'chat_parsing.dart';

/// One row of the Driver's conversation list.
///
/// Mirrors the `list_conversations` contract exactly. Every field the backend
/// documents is represented; nothing is invented. `shipmentId`, `policyNum` and
/// `shipmentStatusId` are null for `admin_driver` threads, which carry no
/// shipment, so they must stay nullable.
class DriverChatConversation {
  const DriverChatConversation({
    required this.conversationId,
    required this.conversationType,
    required this.title,
    required this.lastMessage,
    required this.lastMessageType,
    required this.unreadCount,
    this.shipmentId,
    this.policyNum,
    this.shipmentStatusId,
    this.lastMessageSenderRole,
    this.lastMessageAt,
  });

  final int conversationId;

  /// `shipment_driver` or `admin_driver`.
  final String conversationType;
  final int? shipmentId;
  final String? policyNum;
  final int? shipmentStatusId;
  final String title;
  final String lastMessage;
  final String lastMessageType;

  /// Null when the thread has no messages yet.
  final String? lastMessageSenderRole;
  final DateTime? lastMessageAt;
  final int unreadCount;

  bool get isShipmentConversation => conversationType == 'shipment_driver';

  factory DriverChatConversation.fromJson(Map<String, dynamic> json) {
    return DriverChatConversation(
      conversationId: chatRequiredPositiveInt(
        json['conversation_id'],
        fieldName: 'conversation_id',
      ),
      conversationType: chatString(json['conversation_type']),
      shipmentId: chatInt(json['shipment_id']),
      policyNum: chatNullableString(json['policy_num']),
      shipmentStatusId: chatInt(json['shipment_status_id']),
      title: chatString(json['title']),
      lastMessage: chatString(json['last_message']),
      lastMessageType: chatString(json['last_message_type'], fallback: 'text'),
      lastMessageSenderRole:
          chatNullableString(json['last_message_sender_role']),
      lastMessageAt: chatDateTime(
        json['last_message_at_utc'] ?? json['last_message_at'],
      ),
      unreadCount: chatNonNegativeInt(json['unread_count']),
    );
  }

  DriverChatConversation copyWith({
    int? conversationId,
    String? conversationType,
    int? shipmentId,
    bool clearShipmentId = false,
    String? policyNum,
    bool clearPolicyNum = false,
    int? shipmentStatusId,
    bool clearShipmentStatusId = false,
    String? title,
    String? lastMessage,
    String? lastMessageType,
    String? lastMessageSenderRole,
    bool clearLastMessageSenderRole = false,
    DateTime? lastMessageAt,
    bool clearLastMessageAt = false,
    int? unreadCount,
  }) {
    return DriverChatConversation(
      conversationId: conversationId ?? this.conversationId,
      conversationType: conversationType ?? this.conversationType,
      shipmentId: clearShipmentId ? null : (shipmentId ?? this.shipmentId),
      policyNum: clearPolicyNum ? null : (policyNum ?? this.policyNum),
      shipmentStatusId: clearShipmentStatusId
          ? null
          : (shipmentStatusId ?? this.shipmentStatusId),
      title: title ?? this.title,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageType: lastMessageType ?? this.lastMessageType,
      lastMessageSenderRole: clearLastMessageSenderRole
          ? null
          : (lastMessageSenderRole ?? this.lastMessageSenderRole),
      lastMessageAt:
          clearLastMessageAt ? null : (lastMessageAt ?? this.lastMessageAt),
      unreadCount: unreadCount ?? this.unreadCount,
    );
  }
}
