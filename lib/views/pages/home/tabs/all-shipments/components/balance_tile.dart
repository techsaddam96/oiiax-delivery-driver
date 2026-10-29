import 'package:blockatie/utils/spacing.dart';
import 'package:flutter/material.dart';

class BalanceCard extends StatelessWidget {
  final String amount;
  final String description;
  final String iconPath;
  final Color iconColor;

  const BalanceCard({
    super.key,
    required this.amount,
    required this.description,
    required this.iconPath,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      // margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      padding: const EdgeInsets.only(left: 10, top: 20, bottom: 20, right: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          // Icon
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Image.asset(iconPath, width: 25, height: 25),
          ),
          Spacing.x(2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  description,
                  style: textTheme.bodySmall!.copyWith(
                    color: Colors.black,
                    fontSize: 8,
                  ),
                ),
                Text(
                  amount,
                  style: textTheme.bodyMedium!.copyWith(
                    color: Colors.black,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          // Text Column
          Spacing.x(3),
        ],
      ),
    );
  }
}
