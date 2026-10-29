import 'package:blockatie/models/chat/driver_chat_conversation.dart';
import 'package:blockatie/constants/colors.dart';
import 'package:blockatie/utils/time/jordan_time.dart';
import 'package:blockatie/views/pages/chat/widgets/driver_chat_copy.dart';
import 'package:blockatie/views/pages/chat/widgets/driver_chat_header.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

/// One row in the Driver's conversation list.
class DriverConversationTile extends StatelessWidget {
  const DriverConversationTile({
    super.key,
    required this.conversation,
    required this.onTap,
  });

  final DriverChatConversation conversation;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context);
    final unread = conversation.unreadCount > 0;
    final policy = conversation.policyNum?.trim() ?? '';
    final title = conversation.title.trim().isEmpty
        ? chatCopy(context, 'Operations', 'العمليات')
        : conversation.title.trim();
    final time = DriverConversationTimeFormatter.format(
      context,
      conversation.lastMessageAt,
      locale,
    );

    return Semantics(
      button: true,
      label: unread
          ? '$title, ${chatUnreadSemanticsLabel(context)}'
          : title,
      child: Material(
        color: unread ? const Color(0xffF0F6FF) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Ink(
            padding: const EdgeInsetsDirectional.fromSTEB(14, 13, 12, 13),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color:
                    unread ? const Color(0xffB9D7FF) : const Color(0xffE4EAF3),
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x0A0F172A),
                  blurRadius: 10,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                _ConversationAvatar(
                  title: title,
                  unread: unread,
                  isShipment: conversation.isShipmentConversation,
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
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: const Color(0xff0F172A),
                                fontSize: 15,
                                fontWeight:
                                    unread ? FontWeight.w800 : FontWeight.w700,
                              ),
                            ),
                          ),
                          if (time.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Text(
                              time,
                              textDirection: TextDirection.ltr,
                              style: TextStyle(
                                color: unread
                                    ? AppColors.primary
                                    : const Color(0xff7B8798),
                                fontSize: 11,
                                fontWeight:
                                    unread ? FontWeight.w700 : FontWeight.w600,
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (policy.isNotEmpty) ...[
                        const SizedBox(height: 5),
                        _PolicyChip(policyNum: policy),
                      ],
                      const SizedBox(height: 6),
                      Text(
                        _preview(context),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: unread
                              ? const Color(0xff263B57)
                              : const Color(0xff718096),
                          fontSize: 12,
                          fontWeight:
                              unread ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                if (unread) ...[
                  const SizedBox(width: 10),
                  DriverChatUnreadBadge(count: conversation.unreadCount),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The preview names the sender when the driver spoke last, which is the
  /// quickest way to tell "waiting on them" from "waiting on me".
  String _preview(BuildContext context) {
    final lastMessage = conversation.lastMessage.trim();
    if (lastMessage.isEmpty) {
      return chatCopy(
        context,
        'No messages yet',
        'لا توجد رسائل بعد',
      );
    }
    if (conversation.lastMessageSenderRole == 'driver') {
      return '${chatCopy(context, 'You', 'أنت')}: $lastMessage';
    }
    return lastMessage;
  }
}

class _PolicyChip extends StatelessWidget {
  const _PolicyChip({required this.policyNum});

  final String policyNum;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(8, 4, 8, 4),
      decoration: BoxDecoration(
        color: const Color(0xffEAF3FF),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Text(
        '${chatCopy(context, 'Shipment', 'الشحنة')}: $policyNum',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Color(0xff31639C),
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ConversationAvatar extends StatelessWidget {
  const _ConversationAvatar({
    required this.title,
    required this.unread,
    required this.isShipment,
  });

  final String title;
  final bool unread;
  final bool isShipment;

  @override
  Widget build(BuildContext context) {
    final foreground =
        unread ? const Color(0xff0756B4) : const Color(0xff63748A);
    final initial = title.trim().isEmpty ? '?' : title.trim().characters.first;

    return Container(
      width: 46,
      height: 46,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: unread ? const Color(0xffDDEBFF) : const Color(0xffEEF3FA),
        borderRadius: BorderRadius.circular(15),
      ),
      child: isShipment
          ? Icon(Icons.local_shipping_outlined, color: foreground, size: 22)
          : Icon(
              Icons.support_agent_rounded,
              color: foreground,
              size: 22,
              semanticLabel: initial,
            ),
    );
  }
}

class DriverConversationTimeFormatter {
  DriverConversationTimeFormatter._();

  static final Map<String, DateFormat> _timeFormats = <String, DateFormat>{};
  static final Map<String, DateFormat> _dayFormats = <String, DateFormat>{};
  static final Map<String, DateFormat> _dateFormats = <String, DateFormat>{};

  /// Today shows a clock, yesterday a word, this week a weekday, older a date —
  /// the same ladder the Client list uses.
  static String format(BuildContext context, DateTime? value, Locale locale) {
    if (value == null) return '';

    final localValue = JordanTime.toJordan(value);
    final now = JordanTime.now();
    final localeName = locale.toLanguageTag();

    if (DateUtils.isSameDay(localValue, now)) {
      return _timeFormats
          .putIfAbsent(
            localeName,
            () => chatSafeDateFormat(localeName, DateFormat.jm),
          )
          .format(localValue);
    }

    if (DateUtils.isSameDay(
      localValue,
      now.subtract(const Duration(days: 1)),
    )) {
      return chatCopy(context, 'Yesterday', 'أمس');
    }

    if (now.difference(localValue).inDays < 7) {
      return _dayFormats
          .putIfAbsent(
            localeName,
            () => chatSafeDateFormat(localeName, DateFormat.E),
          )
          .format(localValue);
    }

    return _dateFormats
        .putIfAbsent(
          localeName,
          () => chatSafeDateFormat(
            localeName,
            (locale) => DateFormat('d/M/y', locale),
          ),
        )
        .format(localValue);
  }
}
