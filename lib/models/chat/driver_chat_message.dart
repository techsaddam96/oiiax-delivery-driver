import 'chat_parsing.dart';

/// Where a message sits in the local send lifecycle.
///
/// Only messages this driver composed are ever anything but [sent]: anything
/// arriving from the server is authoritative and already stored.
enum DriverChatMessageStatus { sending, sent, failed }

/// One chat message as the Driver app holds it.
///
/// A message is either authoritative (it has a server `messageId`) or
/// optimistic (it has only a `clientMessageId` until the send returns). Both
/// forms live in the same list so the UI can render a pending bubble in place.
class DriverChatMessage {
  const DriverChatMessage({
    required this.conversationId,
    required this.senderRole,
    required this.senderName,
    required this.messageType,
    required this.message,
    required this.isMine,
    required this.isRead,
    required this.status,
    this.messageId,
    this.clientMessageId,
    this.createdAt,
    this.readAt,
  });

  /// Null only while an optimistic message is still in flight.
  final int? messageId;
  final int conversationId;

  /// `driver` or `admin`.
  final String senderRole;
  final String senderName;
  final String messageType;
  final String message;
  final bool isMine;
  final bool isRead;
  final DateTime? createdAt;
  final DateTime? readAt;

  /// The idempotency key. Present on messages this driver sent; absent on
  /// incoming ones, and on older messages sent before the app supplied one.
  final String? clientMessageId;
  final DriverChatMessageStatus status;

  bool get isPending => status == DriverChatMessageStatus.sending;
  bool get hasFailed => status == DriverChatMessageStatus.failed;

  /// Stable key for list rendering and deduplication.
  ///
  /// The server id wins once it exists, so an optimistic row and its
  /// authoritative replacement resolve to the same message rather than two.
  String get identityKey {
    final serverId = messageId;
    if (serverId != null && serverId > 0) {
      return 'server:$serverId';
    }
    final requestId = clientMessageId?.trim() ?? '';
    if (requestId.isNotEmpty) {
      return 'client:$requestId';
    }
    throw StateError('A chat message must have a stable identity');
  }

  factory DriverChatMessage.fromJson(Map<String, dynamic> json) {
    return DriverChatMessage(
      messageId: chatRequiredPositiveInt(
        json['message_id'],
        fieldName: 'message_id',
      ),
      conversationId: chatRequiredPositiveInt(
        json['conversation_id'],
        fieldName: 'conversation_id',
      ),
      senderRole: chatString(json['sender_role']),
      senderName: chatString(json['sender_name']),
      messageType: chatString(json['message_type'], fallback: 'text'),
      message: chatString(json['message']),
      isMine: chatBool(json['is_mine']),
      isRead: chatBool(json['is_read']),
      createdAt: chatDateTime(json['created_at_utc'] ?? json['created_at']),
      readAt: chatDateTime(json['read_at_utc'] ?? json['read_at']),
      // The read contract does not echo client_message_id; it is only known
      // locally, and merging carries it across from the optimistic row.
      clientMessageId: chatNullableString(json['client_message_id']),
      status: DriverChatMessageStatus.sent,
    );
  }

  DriverChatMessage copyWith({
    int? messageId,
    bool clearMessageId = false,
    int? conversationId,
    String? senderRole,
    String? senderName,
    String? messageType,
    String? message,
    bool? isMine,
    bool? isRead,
    DateTime? createdAt,
    bool clearCreatedAt = false,
    DateTime? readAt,
    bool clearReadAt = false,
    String? clientMessageId,
    bool clearClientMessageId = false,
    DriverChatMessageStatus? status,
  }) {
    return DriverChatMessage(
      messageId: clearMessageId ? null : (messageId ?? this.messageId),
      conversationId: conversationId ?? this.conversationId,
      senderRole: senderRole ?? this.senderRole,
      senderName: senderName ?? this.senderName,
      messageType: messageType ?? this.messageType,
      message: message ?? this.message,
      isMine: isMine ?? this.isMine,
      isRead: isRead ?? this.isRead,
      createdAt: clearCreatedAt ? null : (createdAt ?? this.createdAt),
      readAt: clearReadAt ? null : (readAt ?? this.readAt),
      clientMessageId: clearClientMessageId
          ? null
          : (clientMessageId ?? this.clientMessageId),
      status: status ?? this.status,
    );
  }

  /// Value equality, so merging a server page over identical local rows can
  /// tell "nothing changed" from "this row moved on" and skip a needless
  /// re-sort and rebuild.
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is DriverChatMessage &&
        other.messageId == messageId &&
        other.conversationId == conversationId &&
        other.senderRole == senderRole &&
        other.senderName == senderName &&
        other.messageType == messageType &&
        other.message == message &&
        other.isMine == isMine &&
        other.isRead == isRead &&
        other.createdAt == createdAt &&
        other.readAt == readAt &&
        other.clientMessageId == clientMessageId &&
        other.status == status;
  }

  @override
  int get hashCode => Object.hash(
        messageId,
        conversationId,
        senderRole,
        senderName,
        messageType,
        message,
        isMine,
        isRead,
        createdAt,
        readAt,
        clientMessageId,
        status,
      );
}
