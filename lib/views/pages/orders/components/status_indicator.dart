import 'package:blockatie/constants/colors.dart';
import 'package:flutter/material.dart';

class StatusIndicator extends StatelessWidget {
  final String icon;
  final String label;
  final bool isActive;
  final bool isCompleted;
  final double? containersize;
  final bool showLabel;
  final double? iconsize;
  final double? radius;
  final Color? iconColor;
  final Color? continercolor;
  final VoidCallback? onTap;

  const StatusIndicator({
    super.key,
    required this.icon,
    required this.label,
    required this.isActive,
    required this.isCompleted,
    this.containersize,
    this.showLabel = true,
    this.iconsize,
    this.radius,
    this.iconColor,
    this.continercolor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final lower = label.toLowerCase();

    // Determine red or green status (active state only)
    final isRedStatus =
        lower == 'cancelled' ||
        lower == 'returned' ||
        lower == 'failed delivery';
    final isGreenStatus = lower == 'delivered' || lower == 'completed';

    // Determine background color only when active
    final Color? backgroundColor =
        isActive
            ? (isRedStatus
                ? Colors.red[600]
                : isGreenStatus
                ? Colors.green[600]
                : AppColors.primary)
            : continercolor ?? Colors.white;

    // Apply gradient border when inactive AND (no specific iconColor OR iconColor is not red/green)
    final bool showGradientBorder =
        !isActive &&
        (iconColor == null ||
            (iconColor != Colors.red && iconColor != Colors.green));

    // Only use iconColor as border color for error/success statuses
    final bool shouldUseBorderColor =
        !isActive &&
        iconColor != null &&
        (iconColor == Colors.red || iconColor == Colors.green);

    // Use iconColor as border color only for error/success, otherwise use default logic
    final Color borderColor =
        shouldUseBorderColor ? iconColor! : AppColors.primary;

    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: containersize ?? 38,
            height: containersize ?? 38,
            decoration:
                showGradientBorder
                    ? BoxDecoration(
                      gradient: LinearGradient(
                        colors: [AppColors.gradient1, AppColors.gradient2],
                      ),
                      borderRadius: BorderRadius.circular(radius ?? 12),
                    )
                    : null,
            child: Container(
              width: (containersize ?? 37) - 1,
              height: (containersize ?? 37) - 1,
              margin:
                  showGradientBorder
                      ? EdgeInsets.all(showLabel ? 0.3 : 0.5)
                      : EdgeInsets.zero,
              decoration: BoxDecoration(
                color: backgroundColor,
                borderRadius: BorderRadius.circular(radius ?? 12),
                border:
                    showGradientBorder
                        ? null
                        : shouldUseBorderColor
                        ? Border.all(color: borderColor, width: 2)
                        : null,
              ),
              child: Center(
                child: Image.asset(
                  icon,
                  color:
                      isActive ? Colors.white : iconColor ?? Colors.grey[600],
                  width: iconsize ?? 20,
                  height: iconsize ?? 20,
                ),
              ),
            ),
          ),
          if (showLabel) const SizedBox(height: 8),
          if (showLabel)
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color:
                    isActive
                        ? (isRedStatus
                            ? Colors.red[600]
                            : isGreenStatus
                            ? Colors.green[600]
                            : Colors.black)
                        : const Color.fromARGB(255, 12, 9, 9),
                fontSize: 10,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
        ],
      ),
    );
  }
}
