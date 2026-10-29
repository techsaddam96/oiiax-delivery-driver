import 'chat_parsing.dart';
import 'driver_chat_conversation.dart';
import 'driver_chat_message.dart';

/// The `pagination` block the Driver conversation list returns.
///
/// Note this is page/limit/total, not the cursor the Client conversation list
/// uses — the two backends differ here deliberately, and the Driver app follows
/// its own contract.
class DriverChatPagination {
  const DriverChatPagination({
    required this.page,
    required this.limit,
    required this.total,
    required this.totalPages,
  });

  final int page;
  final int limit;
  final int total;
  final int totalPages;

  bool get hasNextPage => page < totalPages;
  bool get hasPreviousPage => page > 1;

  factory DriverChatPagination.fromJson(Map<String, dynamic> json) {
    return DriverChatPagination(
      page: chatNonNegativeInt(json['page'], fallback: 1),
      limit: chatNonNegativeInt(json['limit']),
      total: chatNonNegativeInt(json['total']),
      totalPages: chatNonNegativeInt(json['total_pages']),
    );
  }

  static const DriverChatPagination empty = DriverChatPagination(
    page: 1,
    limit: 0,
    total: 0,
    totalPages: 0,
  );
}

/// One page of the Driver's conversations.
class DriverChatConversationPage {
  const DriverChatConversationPage({
    required this.conversations,
    required this.pagination,
  });

  final List<DriverChatConversation> conversations;
  final DriverChatPagination pagination;

  factory DriverChatConversationPage.fromJson(Map<String, dynamic> json) {
    return DriverChatConversationPage(
      conversations: List<DriverChatConversation>.unmodifiable(
        chatJsonList(json['conversations'], fieldName: 'conversations').map(
          (item) => DriverChatConversation.fromJson(
            chatJsonMap(item, fieldName: 'conversation'),
          ),
        ),
      ),
      pagination: DriverChatPagination.fromJson(
        chatJsonMap(json['pagination'], fieldName: 'pagination', allowNull: true),
      ),
    );
  }
}

/// A bounded window of messages, newest-window first or older-than-cursor.
/// The list itself always arrives oldest -> newest.
class DriverChatMessagesPage {
  const DriverChatMessagesPage({
    required this.messages,
    required this.hasMore,
    this.nextBeforeMessageId,
  });

  final List<DriverChatMessage> messages;
  final bool hasMore;

  /// Cursor for the next "load older" call. Null when the thread start is
  /// reached.
  final int? nextBeforeMessageId;

  factory DriverChatMessagesPage.fromJson(Map<String, dynamic> json) {
    return DriverChatMessagesPage(
      messages: List<DriverChatMessage>.unmodifiable(
        chatJsonList(json['messages'], fieldName: 'messages').map(
          (item) => DriverChatMessage.fromJson(
            chatJsonMap(item, fieldName: 'message'),
          ),
        ),
      ),
      hasMore: chatBool(json['has_more']),
      nextBeforeMessageId: chatInt(json['next_before_message_id']),
    );
  }
}

/// Everything after a cursor, for the polling loop.
class DriverChatNewMessagesPage {
  const DriverChatNewMessagesPage({
    required this.messages,
    required this.latestMessageId,
    required this.hasMore,
  });

  final List<DriverChatMessage> messages;

  /// Echoed back so the caller can advance its cursor even when the page was
  /// empty.
  final int latestMessageId;
  final bool hasMore;

  factory DriverChatNewMessagesPage.fromJson(Map<String, dynamic> json) {
    final latestMessageId = chatInt(json['latest_message_id']);
    if (latestMessageId == null || latestMessageId < 0) {
      throw const FormatException(
        'Invalid chat contract field: latest_message_id',
      );
    }
    return DriverChatNewMessagesPage(
      messages: List<DriverChatMessage>.unmodifiable(
        chatJsonList(json['messages'], fieldName: 'messages').map(
          (item) => DriverChatMessage.fromJson(
            chatJsonMap(item, fieldName: 'message'),
          ),
        ),
      ),
      latestMessageId: latestMessageId,
      hasMore: chatBool(json['has_more']),
    );
  }
}

/// Outcome of `send_message`.
///
/// [isDuplicate] is the backend telling us this exact `client_message_id` had
/// already been stored — the send succeeded earlier and this was a retry. The
/// returned message is authoritative either way.
class DriverChatSendResult {
  const DriverChatSendResult({
    required this.message,
    required this.isDuplicate,
  });

  final DriverChatMessage message;
  final bool isDuplicate;
}

/// Outcome of `get_or_create_shipment_conversation`.
///
/// [isCreated] is the backend saying this call opened the thread rather than
/// finding it. Either way the conversation is authoritative and ready to open,
/// so the app never has to fetch the list to learn its id.
class DriverChatConversationResult {
  const DriverChatConversationResult({
    required this.conversation,
    required this.isCreated,
  });

  final DriverChatConversation conversation;
  final bool isCreated;

  factory DriverChatConversationResult.fromJson(Map<String, dynamic> json) {
    return DriverChatConversationResult(
      conversation: DriverChatConversation.fromJson(
        chatJsonMap(json['conversation'], fieldName: 'conversation'),
      ),
      isCreated: chatBool(json['is_created']),
    );
  }
}

/// Outcome of `mark_read`.
///
/// [markedCount] is how many receipts *this call* wrote; a repeat returns 0,
/// which is the idempotency working rather than a failure. [unreadCount] is
/// the authoritative remaining unread for the conversation.
class DriverChatReadResult {
  const DriverChatReadResult({
    required this.conversationId,
    required this.lastReadMessageId,
    required this.markedCount,
    required this.unreadCount,
    required this.unreadBefore,
  });

  final int conversationId;
  final int lastReadMessageId;
  final int markedCount;
  final int unreadCount;
  final int unreadBefore;

  factory DriverChatReadResult.fromJson(Map<String, dynamic> json) {
    return DriverChatReadResult(
      conversationId: chatRequiredPositiveInt(
        json['conversation_id'],
        fieldName: 'conversation_id',
      ),
      // Zero is legal here: a thread with no messages yet has nothing to read
      // up to, so this is non-negative rather than strictly positive.
      lastReadMessageId: chatNonNegativeInt(json['last_read_message_id']),
      markedCount: chatNonNegativeInt(json['marked_count']),
      unreadCount: chatNonNegativeInt(json['unread_count']),
      unreadBefore: chatNonNegativeInt(json['unread_before']),
    );
  }
}
