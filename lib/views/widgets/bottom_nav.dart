import 'dart:async';

import 'package:blockatie/constants/colors.dart';
import 'package:blockatie/provider/bottom_nav.dart';
import 'package:blockatie/provider/chat/driver_chat_launcher_provider.dart';
import 'package:blockatie/provider/home.dart';
import 'package:blockatie/provider/notification.dart';
import 'package:blockatie/provider/operational_readiness.dart';
import 'package:blockatie/utils/app_images.dart';
import 'package:blockatie/utils/nav.dart';
import 'package:blockatie/views/pages/driver-location/driver_location.dart';
import 'package:blockatie/views/pages/home/home.dart';
import 'package:blockatie/views/pages/hub/hub.dart';
import 'package:blockatie/views/pages/notifications/notifications.dart';
import 'package:blockatie/views/pages/shipments/shipments_page.dart';
import 'package:blockatie/views/pages/wallet/wallet.dart';
import 'package:blockatie/views/widgets/unread_count_badge.dart';
import 'package:blockatie/views/widgets/operational_guard.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class CustomBottomNavBar extends StatefulWidget {
  const CustomBottomNavBar({super.key, this.overlayPage});

  final Widget? overlayPage;

  @override
  State<CustomBottomNavBar> createState() => _CustomBottomNavBarState();
}

class _CustomBottomNavBarState extends State<CustomBottomNavBar> {
  final Set<int> _builtTabs = {0};
  DriverChatLauncherProvider? _launcher;
  StreamSubscription<void>? _readinessLaunchSubscription;
  bool _openingReadiness = false;

  @override
  void initState() {
    super.initState();
    // This scaffold is the authenticated Driver area. The floating chat
    // launcher belongs to it and to nothing that comes before it, so splash
    // and the auth screens never show it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _launcher = context.read<DriverChatLauncherProvider>();
      _launcher?.setAuthenticatedShellVisible(true);
      _launcher?.syncSession();
      final readiness = context.read<OperationalReadinessProvider>();
      _readinessLaunchSubscription = readiness.locationLaunchRequests.listen(
        (_) => _openReadinessPage(),
      );
      unawaited(
        readiness.start(
          isArabic: Localizations.localeOf(context).languageCode == 'ar',
        ),
      );
      unawaited(
        readiness.consumePendingLocationLaunch().then((shouldOpen) {
          if (shouldOpen) _openReadinessPage();
        }),
      );
    });
  }

  void _openReadinessPage() {
    if (!mounted || _openingReadiness) return;
    _openingReadiness = true;
    Nav.to(const DriverLocationPage(), withNav: true, navIndex: 4);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _openingReadiness = false;
    });
  }

  @override
  void dispose() {
    unawaited(_readinessLaunchSubscription?.cancel());
    _launcher?.setAuthenticatedShellVisible(false);
    super.dispose();
  }

  late final List<Widget Function()> _pageBuilders = [
    () => const HomePage(),
    () => const ShipmentSectionPage(),
    () => const WalletPage(),
    () => const NotificationsPage(),
    () => const HubPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Consumer<BottomNavProvider>(
      builder: (context, navProvider, _) {
        final selectedIndex =
            navProvider.selectedIndex
                .clamp(0, _pageBuilders.length - 1)
                .toInt();
        _builtTabs.add(selectedIndex);

        return PopScope(
          canPop: selectedIndex == 0 && navProvider.overlayPage == null,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) return;
            if (navProvider.overlayPage != null) {
              navProvider.clearOverlay();
              return;
            }
            if (selectedIndex != 0) {
              navProvider.setIndex(0);
            }
          },
          child: Scaffold(
            resizeToAvoidBottomInset: false,
            extendBody: true,
            backgroundColor: const Color(0xffF4F7FB),
            body: Stack(
              children: [
                IndexedStack(
                  index: selectedIndex,
                  children: List.generate(_pageBuilders.length, (index) {
                    if (!_builtTabs.contains(index)) {
                      return const SizedBox.shrink();
                    }
                    return _pageBuilders[index]();
                  }),
                ),
                if (widget.overlayPage != null) widget.overlayPage!,
                if (navProvider.overlayPage != null) navProvider.overlayPage!,
                if (selectedIndex == 0 || selectedIndex == 1)
                  const OperationalGuardOverlay(),
              ],
            ),
            bottomNavigationBar: SafeArea(
              top: false,
              child: Container(
                margin: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                padding: const EdgeInsets.fromLTRB(8, 7, 8, 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: const Color(0xffE2E8F0)),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xff0F172A).withValues(alpha: 0.12),
                      blurRadius: 28,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const _BottomNavBrandStrip(),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        _NavItem(
                          icon: Icons.home_rounded,
                          label: _label(context, 'Home', 'الرئيسية'),
                          index: 0,
                          selectedIndex: selectedIndex,
                        ),
                        _NavItem(
                          icon: Icons.local_shipping_outlined,
                          activeIcon: Icons.local_shipping_rounded,
                          label: _label(context, 'Shipments', 'الشحنات'),
                          index: 1,
                          selectedIndex: selectedIndex,
                        ),
                        _NavItem(
                          icon: Icons.account_balance_wallet_outlined,
                          activeIcon: Icons.account_balance_wallet_rounded,
                          label: _label(context, 'Wallet', 'المحفظة'),
                          index: 2,
                          selectedIndex: selectedIndex,
                        ),
                        Consumer<NotificationProvider>(
                          builder: (context, provider, _) {
                            return _NavItem(
                              icon: Icons.notifications_none_rounded,
                              activeIcon: Icons.notifications_rounded,
                              label: _label(
                                context,
                                'Notifications',
                                'الإشعارات',
                              ),
                              index: 3,
                              selectedIndex: selectedIndex,
                              badgeCount: provider.unreadCount,
                            );
                          },
                        ),
                        _NavItem(
                          icon: Icons.person_outline_rounded,
                          activeIcon: Icons.person_rounded,
                          label: _label(context, 'My Account', 'حسابي'),
                          index: 4,
                          selectedIndex: selectedIndex,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  static String _label(BuildContext context, String en, String ar) {
    return Localizations.localeOf(context).languageCode == 'ar' ? ar : en;
  }
}

class _BottomNavBrandStrip extends StatelessWidget {
  const _BottomNavBrandStrip();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Row(
        children: [
          const Expanded(child: _BrandDivider()),
          Container(
            height: 22,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: const Color(0xffF8FBFF),
              borderRadius: BorderRadius.circular(99),
              border: Border.all(color: const Color(0xffD7E5F4)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  AppImages.iconImage,
                  width: 16,
                  height: 16,
                  fit: BoxFit.contain,
                  errorBuilder:
                      (context, error, stackTrace) => Icon(
                        Icons.local_shipping_rounded,
                        color: AppColors.primary,
                        size: 14,
                      ),
                ),
                const SizedBox(width: 6),
                Text(
                  'OIIAX DRIVER',
                  maxLines: 1,
                  style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
          const Expanded(child: _BrandDivider()),
        ],
      ),
    );
  }
}

class _BrandDivider extends StatelessWidget {
  const _BrandDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: const Color(0xffE2E8F0),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.index,
    required this.selectedIndex,
    this.activeIcon,
    this.badgeCount = 0,
  });

  final IconData icon;
  final IconData? activeIcon;
  final String label;
  final int index;
  final int selectedIndex;
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    final isSelected = selectedIndex == index;

    return Expanded(
      child: Tooltip(
        message: label,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            // Deliberate, and not only a Home-tab concern: every other way of
            // switching tabs does the same — the dashboard's Wallet, Profile
            // and Notifications shortcuts and both header shortcuts all call
            // this before setIndex. Home's inner tab selection is scoped to a
            // visit, so leaving Home ends it and returning shows the dashboard
            // rather than whichever sub-tab was open last time.
            context.read<HomeProvider>().resetToHome();
            context.read<BottomNavProvider>().setIndex(index);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            height: 53,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color:
                  isSelected
                      ? AppColors.primary.withValues(alpha: 0.10)
                      : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(
                      isSelected ? activeIcon ?? icon : icon,
                      size: 22,
                      color:
                          isSelected
                              ? AppColors.primary
                              : const Color(0xff94A3B8),
                    ),
                    // Directional, so the pill mirrors to the icon's trailing
                    // corner in Arabic.
                    if (badgeCount > 0)
                      PositionedDirectional(
                        end: -7,
                        top: -6,
                        child: UnreadCountBadge(count: badgeCount),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color:
                        isSelected
                            ? AppColors.primary
                            : const Color(0xff64748B),
                    fontSize: 10,
                    fontWeight: isSelected ? FontWeight.w800 : FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
