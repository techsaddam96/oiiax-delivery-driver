import 'package:blockatie/constants/colors.dart';
import 'package:blockatie/provider/withdrawal.dart';
import 'package:blockatie/utils/size_config.dart';
import 'package:blockatie/utils/spacing.dart';
import 'package:blockatie/views/dialoges/confirmation_acceptance_dialoge.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class AmountInputSheet extends StatelessWidget {
  const AmountInputSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<WithdrawalProvider>(
      builder:
          (_, provider, __) => Container(
            height: MediaQuery.of(context).size.height * 0.85,
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(10),
                topRight: Radius.circular(10),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tr('enterAmount'),
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(height: 0),
                      Text(
                        tr('enter_the_amount_to_withdraw'),
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
                Spacing.y(5),
                Center(
                  child: GestureDetector(
                    onTap: () {
                      if (provider.showAgreement) {
                        context
                            .read<WithdrawalProvider>()
                            .hideAgreementSection();
                      }
                    },
                    child: AnimatedContainer(
                      duration: Duration(milliseconds: 350),
                      padding: EdgeInsetsDirectional.all(8),
                      decoration: BoxDecoration(
                        color:
                            provider.showAgreement
                                ? AppColors.primary.withAlpha(30)
                                : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        provider.amount,
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w700,
                          color:
                              provider.showAgreement
                                  ? AppColors.primary
                                  : Colors.black54,
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                  ),
                ),

                SizedBox(height: SizeConfig.heightMultiplier * 25),

                // Content Area - Keypad or Agreement
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(20),
                        topRight: Radius.circular(20),
                      ),
                    ),
                    child: Consumer<WithdrawalProvider>(
                      builder: (context, provider, child) {
                        return provider.showAgreement
                            ? const _AgreementSection()
                            : const _CustomKeypad();
                      },
                    ),
                  ),
                ),

                const SizedBox(height: 20),
              ],
            ),
          ),
    );
  }
}

// Agreement Section Widget
class _AgreementSection extends StatelessWidget {
  const _AgreementSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        const Spacer(),

        // Agreement Checkbox
        Consumer<WithdrawalProvider>(
          builder: (context, provider, child) {
            return Row(
              children: [
                Checkbox(
                  value: provider.agreedToTerms,
                  onChanged: (value) {
                    provider.toggleAgreement();
                  },
                  activeColor: AppColors.primary,
                ),
                Expanded(
                  child: Text(
                    tr('agreeTerms'),
                    style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                  ),
                ),
              ],
            );
          },
        ),

        const SizedBox(height: 20),

        // Withdrawal Button
        Consumer<WithdrawalProvider>(
          builder: (context, provider, child) {
            return SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed:
                    provider.agreedToTerms
                        ? () {
                          showConfirmationDialog(
                            context,
                            tr('withdrawal_title_message'),
                            tr('withdrawal_title_desc'),
                            () {
                              provider.makeWithdrawal();
                            },
                          );
                        }
                        : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  elevation: 0,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      tr('withdrawal'),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(width: 8),
                    Icon(Icons.arrow_forward, size: 18),
                  ],
                ),
              ),
            );
          },
        ),

        const SizedBox(height: 30),
      ],
    );
  }
}

// Custom Keypad Widget
class _CustomKeypad extends StatelessWidget {
  const _CustomKeypad();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Row 1: 1, 2, 3
        Expanded(
          child: Row(
            children: [
              _buildKeypadButton(context, '1', 'abc'),
              _buildKeypadButton(context, '2', 'def'),
              _buildKeypadButton(context, '3', 'ghi'),
            ],
          ),
        ),

        // Row 2: 4, 5, 6
        Expanded(
          child: Row(
            children: [
              _buildKeypadButton(context, '4', 'ghi'),
              _buildKeypadButton(context, '5', 'jkl'),
              _buildKeypadButton(context, '6', 'mno'),
            ],
          ),
        ),

        // Row 3: 7, 8, 9
        Expanded(
          child: Row(
            children: [
              _buildKeypadButton(context, '7', 'pqrs'),
              _buildKeypadButton(context, '8', 'tuv'),
              _buildKeypadButton(context, '9', 'wxyz'),
            ],
          ),
        ),

        // Row 4: Tick, 0, Backspace
        Expanded(
          child: Row(
            children: [
              _buildTickButton(context), // Added tick button
              _buildKeypadButton(context, '0', ''),
              _buildBackspaceButton(context),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildKeypadButton(
    BuildContext context,
    String number,
    String letters,
  ) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        height: 65,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              context.read<WithdrawalProvider>().addDigit(number);
            },
            borderRadius: BorderRadius.circular(8),
            child: Container(
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: Colors.grey[300]!, width: 1),
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    number,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w400,
                      color: Colors.black87,
                    ),
                  ),
                  if (letters.isNotEmpty) ...[
                    const SizedBox(height: 1),
                    Text(
                      letters,
                      style: TextStyle(
                        fontSize: 8,
                        color: Colors.grey[600],
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTickButton(BuildContext context) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        height: 65,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              context.read<WithdrawalProvider>().showAgreementSection();
            },
            borderRadius: BorderRadius.circular(8),
            child: Container(
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: Colors.grey[300]!, width: 1),
                ),
              ),
              child: Icon(Icons.check, size: 24, color: AppColors.primary),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBackspaceButton(BuildContext context) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        height: 65,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              context.read<WithdrawalProvider>().removeLastDigit();
            },
            borderRadius: BorderRadius.circular(8),
            child: Container(
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: Colors.grey[300]!, width: 1),
                ),
              ),
              child: const Icon(
                Icons.backspace_outlined,
                size: 18,
                color: Colors.black54,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
