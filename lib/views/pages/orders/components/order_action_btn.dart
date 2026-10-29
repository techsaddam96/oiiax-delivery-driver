import 'package:blockatie/constants/colors.dart';
import 'package:blockatie/provider/orders.dart';
import 'package:blockatie/utils/size_config.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class OrderActionButtons extends StatelessWidget {
  const OrderActionButtons({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<OrderStatusProvider>(context);

    if (provider.currentStatus == 'In Progress' ||
        provider.currentStatus == 'Delivered') {
      if (provider.inProgressSubState == 0) {
        // Partner assigned state - Single button
        return SizedBox(
          width: SizeConfig.widthMultiplier * 60,
          child: ElevatedButton.icon(
            onPressed: () {
              provider.callDeliveryPartner();
            },
            icon: Image.asset('assets/images/phone.png', width: 20, height: 20),
            label: const Text('Call Delivery Partner'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 9),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        );
      } else {
        // Out for delivery state - Two buttons
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {},
                  icon: Image.asset(
                    'assets/images/phone.png',
                    width: 20,
                    height: 20,
                    color: AppColors.primary,
                  ),
                  label: const Text('Call Partner'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: BorderSide(color: AppColors.primary),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {},
                  icon: Image.asset(
                    'assets/images/track_order.png',
                    width: 20,
                    height: 20,
                  ),
                  label: const Text('Track order'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      }
    }

    return const SizedBox(); // Return empty widget for other states
  }
}
