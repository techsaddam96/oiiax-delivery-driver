import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../../constants/colors.dart';
import '../../../../../provider/login.dart';

class CustomCheckbox extends StatelessWidget {
  const CustomCheckbox({super.key});

  @override
  Widget build(BuildContext context) {
    final checkboxProvider = Provider.of<LoginProvider>(context);

    return GestureDetector(
      onTap: checkboxProvider.toggleCheckbox,
      child: Container(
        width: 18,
        height: 18,
        decoration: BoxDecoration(
          color:
              checkboxProvider.isChecked
                  ? AppColors.primary
                  : Colors.transparent,
          border: Border.all(color: Colors.black),
          borderRadius: BorderRadius.circular(4),
        ),
        child:
            checkboxProvider.isChecked
                ? const Icon(Icons.check, size: 14, color: Colors.white)
                : null,
      ),
    );
  }
}
