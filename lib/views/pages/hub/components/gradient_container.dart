import 'package:blockatie/constants/colors.dart';
import 'package:blockatie/provider/profile.dart';
import 'package:blockatie/utils/spacing.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';

class GradientBorderRankBox extends StatefulWidget {
  const GradientBorderRankBox({super.key});

  @override
  State<GradientBorderRankBox> createState() => _GradientBorderRankBoxState();
}

class _GradientBorderRankBoxState extends State<GradientBorderRankBox> {
  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addPostFrameCallback((_) {
      Provider.of<ProfileProvider>(context, listen: false).getDriverRating();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ProfileProvider>(
      builder: (_, data, __) {
        if (data.isLoading) return const SizedBox.shrink();

        final info = data.ratingInfo;
        final img = info?.driverImage;
        final imageUrl =
            img != null && img.isNotEmpty
                ? 'https://dashboard.blockatie.com$img'
                : 'https://cdn-icons-png.flaticon.com/512/2922/2922510.png'; // fallback
        return Container(
          padding: const EdgeInsets.all(1), // Border thickness
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            gradient: LinearGradient(
              colors: [AppColors.gradient1, AppColors.gradient2],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 8,
                  backgroundImage: NetworkImage(imageUrl),
                ),
                const SizedBox(width: 8),

                Text(
                  tr('rankLabel'),
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium!.copyWith(color: Colors.black),
                ),
                Spacing.x(0.3),
                Text('${info?.avgRating.floor() ?? '0'}'),
              ],
            ),
          ),
        );
      },
    );
  }
}
