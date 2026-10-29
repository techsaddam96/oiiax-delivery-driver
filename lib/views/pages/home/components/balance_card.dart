import 'package:blockatie/provider/home.dart';
import 'package:blockatie/utils/size_config.dart';
import 'package:blockatie/utils/spacing.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class BalanceCard extends StatelessWidget {
  const BalanceCard({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Stack(
      alignment: Alignment.center,
      children: [
        //BACKGROUND
        Padding(
          padding: EdgeInsets.symmetric(
            vertical: SizeConfig.heightMultiplier * 2,
            horizontal: SizeConfig.widthMultiplier * 5,
          ),
          child: Image.asset("assets/images/balance_card_bg.png"),
        ),
        //DETAILS
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              height: SizeConfig.heightMultiplier * 8,
              width: SizeConfig.widthMultiplier * 18,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Image.asset("assets/icons/wallet_2.png"),
              ),
            ),
            Spacing.x(5),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Consumer<HomeProvider>(
                  builder: (context, homeProvider, _) {
                    final balance =
                        homeProvider.driverStats?.totalAccrued ?? 0.0;
                    return Text(
                      "${balance.toStringAsFixed(2)} JOD",
                      style: textTheme.headlineMedium!.copyWith(
                        color: Colors.white,
                      ),
                    );
                  },
                ),

                Text(
                  tr('total_balance_shipments'),
                  style: textTheme.bodySmall!.copyWith(color: Colors.white),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}
