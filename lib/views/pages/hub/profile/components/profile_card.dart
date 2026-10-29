import 'package:blockatie/provider/profile.dart';
import 'package:blockatie/utils/spacing.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class ProfileCard extends StatelessWidget {
  const ProfileCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(0),
      child: Stack(
        children: [
          // Background Image
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.asset(
              "assets/images/balance_card_bg.png",
              width: double.infinity,
              fit: BoxFit.cover,
              height: 180,
            ),
          ),

          // Foreground Content
          Positioned.fill(
            child: Consumer<ProfileProvider>(
              builder: (context, provider, _) {
                final profileInfo = provider.profileInfo;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top Row with Padding
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 16,
                      ),
                      child: Consumer<ProfileProvider>(
                        builder: (context, provider, _) {
                          final profile = provider.profileInfo;
                          final imageUrl =
                              profile?.img.isNotEmpty == true
                                  ? 'https://dashboard.blockatie.com${profile!.img}'
                                  : null;
                          final name = profile?.dname ?? '';

                          return Row(
                            children: [
                              // 👇 Exact same non-rounded design, just with dynamic image
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image(
                                  image:
                                      imageUrl != null
                                          ? NetworkImage(imageUrl)
                                          : const AssetImage(
                                                "assets/images/profilepic.png",
                                              )
                                              as ImageProvider,
                                  width: 70,
                                  height: 70,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              Spacing.x(2),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      width: 63,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.green.withValues(
                                          alpha: 0.2,
                                        ),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Row(
                                        children: [
                                          Image.asset(
                                            'assets/images/active-status.png',
                                            width: 10,
                                            height: 10,
                                          ),
                                          const SizedBox(width: 4),
                                          const Text(
                                            'Active',
                                            style: TextStyle(
                                              color: Colors.green,
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Text(
                                      name,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const Text(
                                      'Hero',
                                      style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),

                    // 🔹 Divider with full width
                    Container(
                      width: double.infinity,
                      height: 1,
                      color: Colors.white30,
                    ),

                    // Bottom Row with same Padding
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 16,
                      ),
                      child: Row(
                        children: [
                          // Orders
                          Expanded(
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Image.asset(
                                    'assets/images/no_oforders.png',
                                    width: 20,
                                    height: 20,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      tr("car_number"),
                                      style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: 10,
                                      ),
                                    ),
                                    Text(
                                      (profileInfo?.numcd.isEmpty ?? true)
                                          ? '0'
                                          : profileInfo!.numcd,
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),

                          // Balance
                          Expanded(
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Image.asset(
                                    'assets/images/walletIcon.png',
                                    width: 20,
                                    height: 20,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      tr('driver_percentage'),
                                      style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: 10,
                                      ),
                                    ),
                                    Text(
                                      "${profileInfo?.dpercent} %",
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
