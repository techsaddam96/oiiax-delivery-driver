import 'package:flutter/material.dart';

/// The unread pill used by the header bell and the bottom-navigation tab.
///
/// It follows the pattern the chat badge already proved: a rounded pill rather
/// than a circle, because `BoxDecoration(shape: BoxShape.circle)` paints from
/// the shortest side and clips a three-character `99+`; and content forced
/// left-to-right so the `+` cannot be reordered by the surrounding Arabic
/// paragraph.
///
/// Callers place it with [PositionedDirectional] so it mirrors in Arabic.
class UnreadCountBadge extends StatelessWidget {
  const UnreadCountBadge({
    super.key,
    required this.count,
    this.fontSize = 9,
    this.minSize = 16,
  });

  final int count;
  final double fontSize;
  final double minSize;

  @override
  Widget build(BuildContext context) {
    final label = count > 99 ? '99+' : '$count';

    return Semantics(
      label: '$label ${unreadNotificationsSemanticsLabel(context)}',
      child: Container(
        constraints: BoxConstraints(minWidth: minSize, minHeight: minSize),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xffEF4444),
          borderRadius: BorderRadius.circular(minSize),
        ),
        child: Text(
          label,
          textDirection: TextDirection.ltr,
          style: TextStyle(
            color: Colors.white,
            fontSize: fontSize,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

String unreadNotificationsSemanticsLabel(BuildContext context) =>
    Localizations.localeOf(context).languageCode == 'ar'
        ? 'إشعارات غير مقروءة'
        : 'unread notifications';
