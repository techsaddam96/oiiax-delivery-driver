import 'package:blockatie/utils/size_config.dart';
import 'package:blockatie/utils/spacing.dart';
import 'package:flutter/material.dart';

class DriverBalanceTile extends StatelessWidget {
  const DriverBalanceTile({
    super.key,
    required this.balance,
    required this.subtitle,
    required this.isDue,
  });
  final double balance;
  final String subtitle;
  final bool isDue;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: SizeConfig.widthMultiplier * 5,
        vertical: SizeConfig.heightMultiplier * 1,
      ),
      child: Container(
        height: SizeConfig.heightMultiplier * 10,
        width: SizeConfig.widthMultiplier * 90,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: Colors.white,
        ),
        padding: EdgeInsets.symmetric(
          horizontal: SizeConfig.widthMultiplier * 5,
        ),
        child: Row(
          children: [
            Container(
              height: SizeConfig.heightMultiplier * 6,
              width: SizeConfig.widthMultiplier * 13,
              decoration: BoxDecoration(
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: .05),
                    blurRadius: 5.57,
                    offset: const Offset(0, 11),
                  ),
                ],
                borderRadius: BorderRadius.circular(12),
                color: (isDue
                        ? const Color(0xFFFF2147)
                        : const Color(0xFF26BF94))
                    .withValues(alpha: .15),
              ),
              child: Padding(
                padding: const EdgeInsets.all(10.0),
                child: Image.asset(
                  isDue
                      ? "assets/icons/curly_arrow_down.png"
                      : "assets/icons/curly_arrow_up.png",
                ),
              ),
            ),
            Spacing.x(3),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  " ${balance.toString()} JOD",
                  // "8.25 JOD",
                  style: textTheme.bodyLarge!.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Spacing.y(.3),
                Text(
                  subtitle,
                  style: textTheme.bodySmall!.copyWith(
                    fontSize: SizeConfig.textMultiplier * 1.2,
                  ),
                ),
              ],
            ),
            const Spacer(),
            Image.asset(
              isDue
                  ? "assets/icons/curly_arrow_down.png"
                  : "assets/icons/curly_arrow_up.png",
              height: 25,
            ),
          ],
        ),
      ),
    );
  }
}

extension ColorWithValues on Color {
  Color withValues({double? alpha}) {
    return withOpacity(alpha ?? 1.0);
  }
}
