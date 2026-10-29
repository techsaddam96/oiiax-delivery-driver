import 'package:blockatie/utils/spacing.dart';
import 'package:flutter/material.dart';

class CustomElevatedBtn extends StatelessWidget {
  const CustomElevatedBtn({
    super.key,
    required this.label,
    this.onTap,
    this.bgColor,
    this.isenabled = true,
    this.width,
    this.height,
    this.textColor,
    this.fontSize,
    this.borderRadius,
    this.showIcon = false,
  });
  final String label;
  final VoidCallback? onTap;
  final Color? bgColor;
  final bool isenabled;
  final double? width;
  final double? height;
  final double? fontSize;
  final Color? textColor;
  final double? borderRadius;
  final bool? showIcon;
  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return SizedBox(
      width: width ?? double.infinity,
      height: height ?? 48,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: bgColor,

          //  const Color(0xFF3D3D3D),
          // backgroundColor: const Color(0xFF3D3D3D),
          // padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(borderRadius ?? 7.47),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (showIcon!) Icon(Icons.delete, color: Colors.white),
            Spacing.x(2),
            Text(label, style: textTheme.bodyLarge!.copyWith(color: textColor)),
          ],
        ),
      ),
    );
  }
}
