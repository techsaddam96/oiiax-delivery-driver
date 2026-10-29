import 'package:blockatie/constants/colors.dart';
import 'package:flutter/material.dart';

/// Header for the chat screens.
///
/// Matches the Driver app's card-on-light-grey language (see the settlements
/// screens) but adds the explicit back control a pushed chat screen needs —
/// `HomeHeader` has none because it is only used on tabs.
class DriverChatHeader extends StatelessWidget {
  const DriverChatHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.icon = Icons.forum_rounded,
    this.onBack,
    this.trailing,
    this.badgeCount = 0,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback? onBack;

  /// Optional action shown before the icon, e.g. the shipment shortcut.
  final Widget? trailing;

  /// Shown on the header icon. Zero hides it.
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    // The back arrow must point the way the page actually slides out, so it
    // follows the resolved direction rather than a fixed icon.
    final isRtl = Directionality.of(context) == TextDirection.rtl;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: const Color(0xff0F172A).withValues(alpha: 0.05),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Material(
            color: const Color(0xffEEF5FF),
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: onBack ?? () => Navigator.of(context).maybePop(),
              child: SizedBox(
                width: 42,
                height: 42,
                child: Icon(
                  isRtl
                      ? Icons.arrow_forward_rounded
                      : Icons.arrow_back_rounded,
                  color: AppColors.primary,
                  size: 20,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.start,
                  style: const TextStyle(
                    color: Color(0xff0F172A),
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.start,
                  style: const TextStyle(
                    color: Color(0xff64748B),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            trailing!,
          ],
          const SizedBox(width: 8),
          _HeaderIcon(icon: icon, badgeCount: badgeCount),
        ],
      ),
    );
  }
}

class _HeaderIcon extends StatelessWidget {
  const _HeaderIcon({required this.icon, required this.badgeCount});

  final IconData icon;
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: const Color(0xffEAF2FF),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: const Color(0xffD8E7FB)),
          ),
          alignment: Alignment.center,
          child: Icon(icon, color: AppColors.primary, size: 22),
        ),
        if (badgeCount > 0)
          PositionedDirectional(
            top: -4,
            end: -4,
            child: DriverChatUnreadBadge(count: badgeCount, compact: true),
          ),
      ],
    );
  }
}

/// Unread pill. Counts above 99 collapse to `99+` so the badge keeps its size.
class DriverChatUnreadBadge extends StatelessWidget {
  const DriverChatUnreadBadge({
    super.key,
    required this.count,
    this.compact = false,
  });

  final int count;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final label = count > 99 ? '99+' : '$count';
    final size = compact ? 19.0 : 23.0;

    return Semantics(
      label: '$label ${chatUnreadSemanticsLabel(context)}',
      child: Container(
        constraints: BoxConstraints(minWidth: size, minHeight: size),
        padding: EdgeInsets.symmetric(horizontal: compact ? 5 : 6),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(12),
          border: compact ? Border.all(color: Colors.white, width: 1.5) : null,
        ),
        child: Text(
          label,
          // Digits stay left-to-right even in Arabic, so `99+` never renders
          // as `+99`.
          textDirection: TextDirection.ltr,
          style: TextStyle(
            color: Colors.white,
            fontSize: compact ? 9.5 : 11,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

String chatUnreadSemanticsLabel(BuildContext context) =>
    Localizations.localeOf(context).languageCode == 'ar'
        ? 'رسائل غير مقروءة'
        : 'unread messages';
