import 'package:blockatie/constants/colors.dart';
import 'package:blockatie/provider/withdrawal.dart';
import 'package:blockatie/utils/size_config.dart';
import 'package:blockatie/utils/spacing.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class WithdrawalOptionsWidget extends StatelessWidget {
  const WithdrawalOptionsWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      children: [
        // Cash Withdrawal Option
        Consumer<WithdrawalProvider>(
          builder: (context, withdrawalProvider, child) {
            return GestureDetector(
              onTap: () {
                withdrawalProvider.selectOption('cash');
              },
              child: Container(
                height: SizeConfig.heightMultiplier * 9,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border:
                      withdrawalProvider.selectedOption == 'cash'
                          ? Border(
                            bottom: BorderSide(
                              color: AppColors.primary,
                              width: 1,
                            ),
                          )
                          : null,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.withValues(alpha: 0.1),
                      spreadRadius: 1,
                      blurRadius: 3,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      // Cash Icon
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(100),
                        ),
                        child: Image.asset(
                          'assets/images/cash.png',
                          width: 20,
                          height: 20,
                        ),
                      ),
                      Spacing.x(4),
                      // Title
                      Expanded(
                        child: Text(
                          tr('cash_option'),
                          style: textTheme.bodyLarge!.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      // Radio Button
                      Radio<String>(
                        value: 'cash',
                        groupValue: withdrawalProvider.selectedOption,
                        onChanged: (value) {
                          withdrawalProvider.selectOption(value!);
                        },
                        activeColor: AppColors.primary,
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),

        Spacing.y(2),

        // Click Withdrawal Option
        Consumer<WithdrawalProvider>(
          builder: (context, withdrawalProvider, child) {
            return GestureDetector(
              onTap: () {
                withdrawalProvider.selectOption('click');
              },
              child: Container(
                height: SizeConfig.heightMultiplier * 9,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border:
                      withdrawalProvider.selectedOption == 'click'
                          ? Border(
                            bottom: BorderSide(
                              color: AppColors.primary,
                              width: 1,
                            ),
                          )
                          : null,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.withValues(alpha: 0.1),
                      spreadRadius: 1,
                      blurRadius: 3,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      // Click Icon
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.blue[50],
                          borderRadius: BorderRadius.circular(100),
                        ),
                        child: Image.asset(
                          'assets/images/clickoption.png',
                          width: 20,
                          height: 20,
                        ),
                      ),
                      const SizedBox(width: 16),
                      // Title
                      Expanded(
                        child: Text(
                          tr('click_option'),
                          style: textTheme.bodyLarge!.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      // Radio Button
                      Radio<String>(
                        value: 'click',
                        groupValue: withdrawalProvider.selectedOption,
                        onChanged: (value) {
                          withdrawalProvider.selectOption(value!);
                        },
                        activeColor: Colors.blue,
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
