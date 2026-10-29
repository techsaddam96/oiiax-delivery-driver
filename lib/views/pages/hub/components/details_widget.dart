import 'package:blockatie/utils/app_images.dart';
import 'package:blockatie/utils/spacing.dart';
import 'package:flutter/material.dart';

class HubDetailRow extends StatelessWidget {
  const HubDetailRow({
    super.key,
    this.ontap,
    required this.icon,
    required this.text,
  });
  final String icon;
  final VoidCallback? ontap;
  final String text;
  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return InkWell(
      onTap: ontap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          children: [
            Image.asset(icon, width: 20, height: 20),
            Spacing.x(2),
            Text(
              text,
              style: textTheme.bodyMedium!.copyWith(
                color: Colors.black,
                fontWeight: FontWeight.w500,
              ),
            ),
            const Spacer(),
            Image.asset(AppImages.farwrdIcon, width: 12, height: 12),
          ],
        ),
      ),
    );
  }
}
