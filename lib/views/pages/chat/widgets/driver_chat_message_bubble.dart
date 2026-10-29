import 'package:blockatie/constants/colors.dart';
import 'package:blockatie/models/chat/driver_chat_message.dart';
import 'package:blockatie/utils/time/jordan_time.dart';
import 'package:blockatie/views/pages/chat/widgets/driver_chat_copy.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

/// One message.
///
/// Outgoing (this driver) sits at the end of the row in the app's primary
/// blue; incoming (Admin / Operations) sits at the start in a light card. The
/// alignment is directional, so Arabic mirrors correctly instead of looking
/// like a flipped LTR layout.
class DriverChatMessageBubble extends StatelessWidget {
  const DriverChatMessageBubble({
    super.key,
    required this.message,
    required this.onRetry,
  });

  final DriverChatMessage message;

  /// Only supplied for a failed outgoing message.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final isMine = message.isMine;
    final locale = Localizations.localeOf(context);
    final time = DriverChatDateFormatter.formatTime(message.createdAt, locale);
    final readTime = DriverChatDateFormatter.formatTime(message.readAt, locale);
    final senderName = message.senderName.trim();

    return Semantics(
      label: isMine
          ? chatCopy(context, 'My message', 'رسالتي')
          : senderName.isEmpty
              ? chatCopy(context, 'Support message', 'رسالة من الدعم')
              : senderName,
      child: Align(
        alignment: isMine
            ? AlignmentDirectional.centerEnd
            : AlignmentDirectional.centerStart,
        child: ConstrainedBox(
          // Bounded against the viewport so a long message stays readable on a
          // narrow phone instead of running edge to edge.
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.78,
          ),
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 3),
            padding: const EdgeInsetsDirectional.fromSTEB(12, 9, 12, 7),
            decoration: BoxDecoration(
              color: isMine ? AppColors.primary : Colors.white,
              borderRadius: BorderRadiusDirectional.only(
                topStart: const Radius.circular(16),
                topEnd: const Radius.circular(16),
                bottomStart: Radius.circular(isMine ? 16 : 4),
                bottomEnd: Radius.circular(isMine ? 4 : 16),
              ),
              border:
                  isMine ? null : Border.all(color: const Color(0xffE2E8F0)),
              boxShadow: isMine
                  ? null
                  : const [
                      BoxShadow(
                        color: Color(0x0A0F172A),
                        blurRadius: 8,
                        offset: Offset(0, 3),
                      ),
                    ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!isMine && senderName.isNotEmpty) ...[
                  Text(
                    senderName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xff33506F),
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                ],
                Text(
                  message.message,
                  style: TextStyle(
                    color: isMine ? Colors.white : const Color(0xff1C3048),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 5),
                _BubbleFooter(
                  message: message,
                  time: time,
                  readTime: readTime,
                ),
                if (isMine && message.hasFailed) ...[
                  const SizedBox(height: 4),
                  _RetryRow(onRetry: onRetry),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BubbleFooter extends StatelessWidget {
  const _BubbleFooter({
    required this.message,
    required this.time,
    required this.readTime,
  });

  final DriverChatMessage message;
  final String time;
  final String readTime;

  @override
  Widget build(BuildContext context) {
    final isMine = message.isMine;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (time.isNotEmpty)
          Text(
            time,
            // Clock values are always read left-to-right.
            textDirection: TextDirection.ltr,
            style: TextStyle(
              color: isMine
                  ? Colors.white.withValues(alpha: 0.78)
                  : const Color(0xff718096),
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        if (isMine && message.isPending) ...[
          const SizedBox(width: 5),
          SizedBox(
            width: 11,
            height: 11,
            child: CircularProgressIndicator(
              strokeWidth: 1.7,
              color: Colors.white.withValues(alpha: 0.9),
            ),
          ),
        ],
        if (isMine && message.status == DriverChatMessageStatus.sent) ...[
          const SizedBox(width: 5),
          // One tick: stored by the server. Two: an admin has read it.
          Icon(
            message.isRead ? Icons.done_all_rounded : Icons.check_rounded,
            size: 13,
            color: message.isRead
                ? const Color(0xffB8F2DF)
                : Colors.white.withValues(alpha: 0.85),
          ),
          if (message.isRead && readTime.isNotEmpty) ...[
            const SizedBox(width: 4),
            Text(
              readTime,
              textDirection: TextDirection.ltr,
              style: const TextStyle(
                color: Color(0xffB8F2DF),
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
        if (isMine && message.hasFailed) ...[
          const SizedBox(width: 5),
          const Icon(
            Icons.error_outline_rounded,
            color: Color(0xffFEE2E2),
            size: 13,
          ),
        ],
      ],
    );
  }
}

class _RetryRow extends StatelessWidget {
  const _RetryRow({required this.onRetry});

  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          chatCopy(context, 'Not sent', 'لم تُرسل'),
          style: const TextStyle(
            color: Color(0xffFEE2E2),
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: 4),
        TextButton(
          onPressed: onRetry,
          style: TextButton.styleFrom(
            foregroundColor: Colors.white,
            minimumSize: const Size(44, 32),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text(
            chatCopy(context, 'Retry', 'إعادة المحاولة'),
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
  }
}

/// Day marker between message groups.
class DriverChatDateSeparator extends StatelessWidget {
  const DriverChatDateSeparator({super.key, required this.value});

  final DateTime value;

  @override
  Widget build(BuildContext context) {
    final label = DriverChatDateFormatter.formatDay(context, value);
    return Semantics(
      label: label,
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 12),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: const Color(0xffE7EDF5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            label,
            style: const TextStyle(
              color: Color(0xff5E7188),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class DriverChatDateFormatter {
  DriverChatDateFormatter._();

  static final Map<String, DateFormat> _timeFormats = <String, DateFormat>{};
  static final Map<String, DateFormat> _dateFormats = <String, DateFormat>{};

  static String formatTime(DateTime? value, Locale locale) {
    if (value == null) return '';
    final localeName = locale.toLanguageTag();
    return _timeFormats
        .putIfAbsent(
          localeName,
          () => chatSafeDateFormat(localeName, DateFormat.jm),
        )
        .format(JordanTime.toJordan(value));
  }

  static String formatDay(BuildContext context, DateTime value) {
    final localValue = JordanTime.toJordan(value);
    final now = JordanTime.now();
    if (DateUtils.isSameDay(localValue, now)) {
      return chatCopy(context, 'Today', 'اليوم');
    }
    if (DateUtils.isSameDay(
      localValue,
      now.subtract(const Duration(days: 1)),
    )) {
      return chatCopy(context, 'Yesterday', 'أمس');
    }
    final localeName = Localizations.localeOf(context).toLanguageTag();
    return _dateFormats
        .putIfAbsent(
          localeName,
          () => chatSafeDateFormat(
            localeName,
            (locale) => DateFormat('d MMMM y', locale),
          ),
        )
        .format(localValue);
  }

  /// Whether a separator belongs between two messages, using the business day.
  static bool isDifferentDay(DateTime? first, DateTime? second) {
    if (first == null || second == null) return first != second;
    return !DateUtils.isSameDay(JordanTime.toJordan(first), JordanTime.toJordan(second));
  }
}
