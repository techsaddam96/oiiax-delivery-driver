class NotificationResponse {
  final String status;
  final String message;
  final int unreadCount;
  final List<NotificationItem> notifications;

  /// Server paging. `pages`/`total` describe the whole inbox, not this page.
  final int page;
  final int pages;
  final int total;
  final bool hasMore;

  NotificationResponse({
    required this.status,
    required this.message,
    required this.unreadCount,
    required this.notifications,
    this.page = 1,
    this.pages = 0,
    this.total = 0,
    this.hasMore = false,
  });

  factory NotificationResponse.fromJson(Map<String, dynamic> json) {
    final data = json['data'];
    final dataMap =
        data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
    final rawNotifications =
        json['notifications'] ?? dataMap['notifications'] ?? <dynamic>[];

    final total = _asInt(json['total'] ?? dataMap['total']);
    final pages = _asInt(json['pages'] ?? dataMap['pages']);
    final page = _asInt(json['page'] ?? dataMap['page']);

    return NotificationResponse(
      status: (json['status'] ?? json['success'])?.toString() ?? '',
      // Backend prose is never shown; this is kept for diagnostics only.
      message:
          (json['message'] ??
                  json['message_en'] ??
                  json['message_ar'] ??
                  dataMap['message'])
              ?.toString() ??
          '',
      unreadCount: _asInt(json['unread_count'] ?? dataMap['unread_count']),
      notifications:
          rawNotifications is List
              ? rawNotifications.whereType<Map>().map((item) {
                return NotificationItem.fromJson(
                  Map<String, dynamic>.from(item),
                );
              }).toList()
              : [],
      page: page < 1 ? 1 : page,
      pages: pages,
      total: total,
      // A server that does not page says so by omission.
      hasMore:
          json.containsKey('has_more')
              ? json['has_more'] == true
              : (dataMap['has_more'] == true),
    );
  }

  NotificationResponse copyWith({
    String? status,
    String? message,
    int? unreadCount,
    List<NotificationItem>? notifications,
    int? page,
    int? pages,
    int? total,
    bool? hasMore,
  }) {
    return NotificationResponse(
      status: status ?? this.status,
      message: message ?? this.message,
      unreadCount: unreadCount ?? this.unreadCount,
      notifications: notifications ?? this.notifications,
      page: page ?? this.page,
      pages: pages ?? this.pages,
      total: total ?? this.total,
      hasMore: hasMore ?? this.hasMore,
    );
  }
}

class NotificationItem {
  final int id;
  final String senderRole;
  final int senderId;
  final String type;
  final int itemId;
  final String titleEn;
  final String titleAr;
  final String messageEn;
  final String messageAr;
  final String message;
  final String url;
  final int isRead;
  final String? readAt;
  final String createdAt;
  final String? createdAtJordan;
  final String? createdAtUtc;

  NotificationItem({
    required this.id,
    required this.senderRole,
    required this.senderId,
    required this.type,
    required this.itemId,
    required this.titleEn,
    required this.titleAr,
    required this.messageEn,
    required this.messageAr,
    required this.message,
    required this.url,
    required this.isRead,
    required this.readAt,
    required this.createdAt,
    this.createdAtJordan,
    this.createdAtUtc,
  });

  factory NotificationItem.fromJson(Map<String, dynamic> json) {
    return NotificationItem(
      id: _asInt(json['id'] ?? json['notification_recipient_id']),
      senderRole: json['sender_role']?.toString() ?? '',
      senderId: _asInt(json['sender_id']),
      type: json['type']?.toString() ?? '',
      itemId: _asInt(json['item_id'] ?? json['shipment_id']),
      // Strictly the matching language. `title` is whichever one the server
      // picked for its own `lang`, so borrowing it would put English into an
      // Arabic screen.
      titleEn: json['title_en']?.toString() ?? '',
      titleAr: json['title_ar']?.toString() ?? '',
      messageEn: json['message_en']?.toString() ?? '',
      messageAr: json['message_ar']?.toString() ?? '',
      message: json['message']?.toString() ?? '',
      url: json['url']?.toString() ?? '',
      isRead: _asBoolInt(json['is_read']),
      readAt: json['read_at']?.toString(),
      createdAt:
          (json['created_at'] ?? json['date'] ?? json['createdAt'])
              ?.toString() ??
          '',
      createdAtJordan: json['created_at_jordan']?.toString(),
      createdAtUtc: json['created_at_utc']?.toString(),
    );
  }

  bool get isUnread => isRead == 0;

  NotificationItem copyWith({int? isRead, String? readAt}) {
    return NotificationItem(
      id: id,
      senderRole: senderRole,
      senderId: senderId,
      type: type,
      itemId: itemId,
      titleEn: titleEn,
      titleAr: titleAr,
      messageEn: messageEn,
      messageAr: messageAr,
      message: message,
      url: url,
      isRead: isRead ?? this.isRead,
      readAt: readAt ?? this.readAt,
      createdAt: createdAt,
      createdAtJordan: createdAtJordan,
      createdAtUtc: createdAtUtc,
    );
  }
}

int _asInt(dynamic value) {
  if (value is int) return value;
  if (value is bool) return value ? 1 : 0;
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

int _asBoolInt(dynamic value) {
  if (value is bool) return value ? 1 : 0;
  final normalized = value?.toString().trim().toLowerCase();
  if (normalized == 'true' || normalized == 'yes') return 1;
  if (normalized == 'false' || normalized == 'no') return 0;
  return _asInt(value);
}
