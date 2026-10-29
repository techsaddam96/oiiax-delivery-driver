import 'dart:async';

import 'package:blockatie/constants/colors.dart';
import 'package:blockatie/models/driver_profile.dart';
import 'package:blockatie/provider/bottom_nav.dart';
import 'package:blockatie/provider/home.dart';
import 'package:blockatie/provider/localization.dart';
import 'package:blockatie/provider/chat/driver_chat_conversations_provider.dart';
import 'package:blockatie/provider/notification.dart';
import 'package:blockatie/provider/profile.dart';
import 'package:blockatie/services/auth_services.dart';
import 'package:blockatie/utils/money.dart';
import 'package:blockatie/utils/nav.dart';
import 'package:blockatie/utils/text_direction.dart';
import 'package:blockatie/views/bottmsheets/logout_sheet.dart';
import 'package:blockatie/views/pages/chat/driver_chat_navigation.dart';
import 'package:blockatie/views/pages/home/components/header.dart';
import 'package:blockatie/views/pages/driver-location/driver_location.dart';
import 'package:blockatie/views/pages/hub/profile/profile.dart';
import 'package:blockatie/views/pages/chat/widgets/driver_chat_header.dart';
import 'package:blockatie/views/pages/hub/setting/settings.dart';
import 'package:blockatie/views/pages/hub/support&assistance/support_assistence.dart';
import 'package:blockatie/views/pages/settlements/driver_settlements_page.dart';
import 'package:blockatie/views/widgets/driver_chat_bubble.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class HubPage extends StatefulWidget {
  const HubPage({super.key});

  @override
  State<HubPage> createState() => _HubPageState();
}

class _HubPageState extends State<HubPage> {
  String? _localName;
  String? _localPhone;
  String? _localDriverId;

  @override
  void initState() {
    super.initState();
    unawaited(_loadLocalSessionData());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final profileProvider = context.read<ProfileProvider>();
      if (profileProvider.profileInfo == null) {
        unawaited(profileProvider.fetchDriverProfile());
      }
      if (profileProvider.ratingInfo == null) {
        unawaited(profileProvider.getDriverRating());
      }
      // Not forced: a no-op when Home already loaded the figures, and it is
      // what makes the loading state below deterministic when the driver
      // lands on this tab first.
      unawaited(context.read<HomeProvider>().getDriverStatistics(context));
    });
  }

  Future<void> _loadLocalSessionData() async {
    final values = await Future.wait([
      AuthService.getDrivername(),
      AuthService.getPhone(),
      AuthService.getuserId(),
    ]);
    if (!mounted) return;
    setState(() {
      _localName = values[0];
      _localPhone = values[1];
      _localDriverId = values[2];
    });
  }

  @override
  Widget build(BuildContext context) {
    final profileProvider = context.watch<ProfileProvider>();
    final homeProvider = context.watch<HomeProvider>();
    final localeProvider = context.watch<LocaleProvider>();
    final profile = profileProvider.profileInfo;
    final statsLoading =
        homeProvider.isLoading && homeProvider.driverStats == null;
    final statItems = _statItems(context, profileProvider, homeProvider);

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: const Color(0xffF4F7FB),
      body: SafeArea(
        child: Column(
          children: [
            HomeHeader(
              title: _copy(context, 'My Account', 'حسابي'),
              subtitle: _copy(
                context,
                'Profile, settings, and support',
                'الملف الشخصي والإعدادات والدعم',
              ),
              showProfileShortcut: false,
            ),
            Expanded(
              child: RefreshIndicator(
                color: AppColors.primary,
                onRefresh: () => _refreshHubData(context),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final padding = constraints.maxWidth < 360 ? 14.0 : 18.0;
                    return SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(
                        parent: BouncingScrollPhysics(),
                      ),
                      // Clears the floating chat launcher as well as the
                      // bottom-navigation pill: at 110 the launcher sat on top
                      // of the logout button once the page was scrolled home.
                      padding: EdgeInsets.fromLTRB(
                        padding,
                        16,
                        padding,
                        DriverChatBubble.reservedBottomSpace + 16,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _ProfileHeroCard(
                            name: _profileName(context, profileProvider),
                            // The raw value, so the avatar never builds
                            // initials out of a localized placeholder.
                            rawName: profile?.dname ?? _localName,
                            phone: _profilePhone(context, profileProvider),
                            role: _copy(
                              context,
                              'Delivery Driver',
                              'مندوب توصيل',
                            ),
                            statusLabel: _statusLabel(context, profileProvider),
                            imageUrl: _profileImageUrl(profile),
                          ),
                          if (statItems.isNotEmpty) ...[
                            const SizedBox(height: 14),
                            _StatsStrip(items: statItems),
                          ],
                          if (statsLoading) ...[
                            const SizedBox(height: 14),
                            _StatsNotice(
                              icon: Icons.hourglass_empty_rounded,
                              message: _copy(
                                context,
                                'Loading statistics…',
                                'جارٍ تحميل الإحصائيات…',
                              ),
                              showSpinner: true,
                            ),
                          ] else if (homeProvider.hasStatisticsError) ...[
                            const SizedBox(height: 14),
                            // In place of the cards, never beside them: a
                            // failed read produces zeros, and a zero balance
                            // shown as fact is worse than no figure at all.
                            _StatsNotice(
                              icon: Icons.cloud_off_rounded,
                              message: _copy(
                                context,
                                'Statistics unavailable',
                                'تعذر تحميل الإحصائيات',
                              ),
                            ),
                          ],
                          const SizedBox(height: 18),
                          _SectionCard(
                            title: _copy(
                              context,
                              'Account information',
                              'معلومات الحساب',
                            ),
                            children: [
                              _InfoRow(
                                icon: Icons.phone_rounded,
                                label: _copy(context, 'Phone', 'الهاتف'),
                                value: _profilePhone(context, profileProvider),
                              ),
                              _InfoRow(
                                icon: Icons.badge_outlined,
                                label: _copy(
                                  context,
                                  'Driver ID',
                                  'رقم السائق',
                                ),
                                value: _safeValue(
                                  context,
                                  _localDriverId,
                                  profileProvider,
                                ),
                              ),
                              _InfoRow(
                                icon: Icons.verified_user_outlined,
                                label: _copy(
                                  context,
                                  'Account status',
                                  'حالة الحساب',
                                ),
                                value: _statusLabel(context, profileProvider),
                              ),
                              _InfoRow(
                                icon: Icons.workspace_premium_outlined,
                                label: _copy(
                                  context,
                                  'Subscription',
                                  'الاشتراك',
                                ),
                                value: _subscriptionLabel(
                                  context,
                                  profileProvider,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          _SectionCard(
                            title: _copy(context, 'Actions', 'الإجراءات'),
                            children: [
                              _ActionRow(
                                icon: Icons.my_location_rounded,
                                label: _copy(context, 'My Location', 'موقعي'),
                                subtitle: _copy(
                                  context,
                                  'GPS readiness, accuracy, and last update',
                                  'جاهزية الموقع والدقة وآخر تحديث',
                                ),
                                onTap:
                                    () => Nav.to(
                                      const DriverLocationPage(),
                                      withNav: true,
                                      navIndex: 4,
                                    ),
                              ),
                              _ActionRow(
                                icon: Icons.receipt_long_outlined,
                                label: _copy(
                                  context,
                                  'My Settlements',
                                  'تسوياتي',
                                ),
                                subtitle: _copy(
                                  context,
                                  'Financial summary and settlement records',
                                  'الملخص المالي وكشوفات التسوية',
                                ),
                                onTap:
                                    () => Nav.to(
                                      const DriverSettlementsPage(),
                                      withNav: true,
                                      navIndex: 4,
                                    ),
                              ),
                              _ConversationsRow(copy: _copy),
                              _ActionRow(
                                icon: Icons.account_balance_wallet_outlined,
                                label: _copy(context, 'Wallet', 'المحفظة'),
                                subtitle: _copy(
                                  context,
                                  'Earnings and withdrawals',
                                  'الأرباح وطلبات السحب',
                                ),
                                onTap:
                                    () => context
                                        .read<BottomNavProvider>()
                                        .setIndex(2),
                              ),
                              _ActionRow(
                                icon: Icons.notifications_none_rounded,
                                label: _copy(
                                  context,
                                  'Notifications',
                                  'الإشعارات',
                                ),
                                subtitle: _copy(
                                  context,
                                  'Shipment and account updates',
                                  'تحديثات الشحنات والحساب',
                                ),
                                onTap:
                                    () => context
                                        .read<BottomNavProvider>()
                                        .setIndex(3),
                              ),
                              _ActionRow(
                                icon: Icons.person_outline_rounded,
                                label: _copy(
                                  context,
                                  'Profile details',
                                  'تفاصيل الملف الشخصي',
                                ),
                                subtitle: _copy(
                                  context,
                                  'View saved driver information',
                                  'عرض بيانات السائق المحفوظة',
                                ),
                                onTap:
                                    () => Nav.to(
                                      const ProfilePage(),
                                      withNav: true,
                                      navIndex: 4,
                                    ),
                              ),
                              _ActionRow(
                                icon: Icons.settings_outlined,
                                label: _copy(
                                  context,
                                  'Edit profile',
                                  'تعديل الملف الشخصي',
                                ),
                                subtitle: _copy(
                                  context,
                                  'Update photo and password',
                                  'تحديث الصورة وكلمة المرور',
                                ),
                                onTap:
                                    () => Nav.to(
                                      const SettingsPage(),
                                      withNav: true,
                                      navIndex: 4,
                                    ),
                              ),
                              _ActionRow(
                                icon: Icons.support_agent_rounded,
                                label: _copy(context, 'Support', 'الدعم'),
                                subtitle: _copy(
                                  context,
                                  'Contact the support team',
                                  'التواصل مع فريق الدعم',
                                ),
                                onTap:
                                    () => Nav.to(
                                      const SupportAssistencePage(),
                                      withNav: true,
                                      navIndex: 4,
                                    ),
                              ),
                              _LanguageRow(localeProvider: localeProvider),
                            ],
                          ),
                          const SizedBox(height: 18),
                          _DeactivateAccountButton(
                            onTap: () => _showDeactivateAccountSheet(context),
                          ),
                          const SizedBox(height: 12),
                          _LogoutButton(onTap: () => showLogoutSheet(context)),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Everything the hub shows, refreshed in one pass.
  ///
  /// Each provider reports its own failure through the state the hub already
  /// renders — a stale figure is never presented as a fresh one — so this
  /// neither swallows a result nor stacks error dialogs on top of each other.
  Future<void> _refreshHubData(BuildContext context) async {
    final profileProvider = context.read<ProfileProvider>();
    final homeProvider = context.read<HomeProvider>();
    final notifications = context.read<NotificationProvider>();
    final conversations = context.read<DriverChatConversationsProvider>();

    await Future.wait([
      _guarded(profileProvider.fetchDriverProfile()),
      _guarded(profileProvider.getDriverRating()),
      _guarded(homeProvider.getDriverStatistics(context, force: true)),
      _guarded(notifications.refreshUnreadCount(force: true)),
      // One read, not a poller: the shared provider owns the chat figure and
      // this only asks it for a fresh one.
      _guarded(conversations.refreshUnreadCount()),
    ]);
  }

  /// A refresh is a best-effort read of five independent sources. One of them
  /// throwing must not abandon the other four, and none of them surfaces a
  /// message here.
  Future<void> _guarded(Future<void> work) async {
    try {
      await work;
    } catch (e) {
      debugPrint('Hub refresh step failed: ${e.runtimeType}');
    }
  }

  List<_ProfileStatItem> _statItems(
    BuildContext context,
    ProfileProvider profileProvider,
    HomeProvider homeProvider,
  ) {
    final items = <_ProfileStatItem>[];
    final rating = profileProvider.ratingInfo;
    if (rating != null) {
      items.add(
        _ProfileStatItem(
          icon: Icons.star_rounded,
          value: rating.avgRating.toStringAsFixed(1),
          label: _copy(context, 'Rating', 'التقييم'),
        ),
      );
    }
    // A failed read leaves `DriverStatisticsData.empty()` behind, which is
    // indistinguishable from a genuine run of zeros. The cards are dropped in
    // that case and the notice in `build` takes their place; a real zero from
    // a successful call still renders as zero.
    final stats =
        homeProvider.hasStatisticsError ? null : homeProvider.driverStats;
    if (stats != null) {
      items.addAll([
        _ProfileStatItem(
          icon: Icons.check_circle_outline_rounded,
          value: stats.shipmentsDelivered.toString(),
          label: _copy(context, 'Delivered', 'تم التسليم'),
        ),
        _ProfileStatItem(
          icon: Icons.route_rounded,
          value: stats.shipmentsInProgress.toString(),
          label: _copy(context, 'Active', 'نشطة'),
        ),
        _ProfileStatItem(
          icon: Icons.account_balance_wallet_outlined,
          value: _money(context, stats.totalDriverDue),
          label: _copy(context, 'Earnings due', 'الأرباح المستحقة'),
        ),
      ]);
    }
    return items;
  }

  /// Amount first in Arabic, currency first in English — the natural order in
  /// each. The precision is unchanged. Shared with the financial screens so
  /// the same field cannot be formatted two ways.
  String _money(BuildContext context, double value) =>
      formatMoney(context, value);

  String _profileName(BuildContext context, ProfileProvider provider) {
    return _safeValue(
      context,
      provider.profileInfo?.dname ?? _localName,
      provider,
    );
  }

  String _profilePhone(BuildContext context, ProfileProvider provider) {
    return _safeValue(
      context,
      provider.profileInfo?.dphone ?? _localPhone,
      provider,
    );
  }

  String _statusLabel(BuildContext context, ProfileProvider provider) {
    final profile = provider.profileInfo;
    if (profile == null) return _safeValue(context, null, provider);
    if (profile.status == 0) return _copy(context, 'Active', 'نشط');
    if (profile.status == 1) return _copy(context, 'Inactive', 'غير نشط');
    if (profile.status == 2) return _copy(context, 'Deactivated', 'موقوف');
    return _copy(context, 'Unknown', 'غير معروف');
  }

  String _subscriptionLabel(BuildContext context, ProfileProvider provider) {
    final profile = provider.profileInfo;
    if (profile == null) return _safeValue(context, null, provider);
    return profile.subscription == 1
        ? _copy(context, 'Subscribed', 'مشترك')
        : _copy(context, 'Standard', 'عادي');
  }

  String? _profileImageUrl(DriverInfo? profile) {
    final image = profile?.img.trim() ?? '';
    if (image.isEmpty) return null;
    if (image.startsWith('http')) return image;
    return 'https://dashboard.blockatie.com$image';
  }

  /// Three different things, told apart. A value that is merely slow must not
  /// be reported as missing, and one that could not be fetched must not be
  /// reported as empty.
  String _safeValue(
    BuildContext context,
    String? value,
    ProfileProvider provider,
  ) {
    final text = value?.trim();
    if (text != null && text.isNotEmpty) return text;
    if (provider.isProfileLoading) return '—';
    if (provider.hasProfileError) {
      return _copy(context, 'Unavailable', 'غير متاح');
    }
    return _copy(context, 'Not available', 'غير متوفر');
  }

  String _copy(BuildContext context, String en, String ar) {
    return Localizations.localeOf(context).languageCode == 'ar' ? ar : en;
  }

  void _showDeactivateAccountSheet(BuildContext context) {
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) {
        return _DeactivateAccountSheet(
          title: isArabic ? 'إيقاف الحساب' : 'Deactivate Account',
          message:
              isArabic
                  ? 'سيتم إيقاف حسابك ولن تتمكن من تسجيل الدخول بعد التأكيد.'
                  : 'Your account will be deactivated and you will not be able to log in after confirming.',
          cancelLabel: isArabic ? 'إلغاء' : 'Cancel',
          confirmLabel: isArabic ? 'إيقاف الحساب' : 'Deactivate',
          // The sheet stays up and shows its own progress, then closes itself.
          // Popping first left the request running behind a global loader
          // dialog that was dismissed with an unconditional pop.
          onConfirm: () => context.read<ProfileProvider>().deleteAccount(),
        );
      },
    );
  }
}

class _ProfileHeroCard extends StatelessWidget {
  const _ProfileHeroCard({
    required this.name,
    required this.rawName,
    required this.phone,
    required this.role,
    required this.statusLabel,
    required this.imageUrl,
  });

  /// What the driver reads, which may be a localized placeholder.
  final String name;

  /// What the driver is actually called, or null. Only this feeds initials.
  final String? rawName;
  final String phone;
  final String role;
  final String statusLabel;
  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xff0B63CE), Color(0xff00346F)],
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.20),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Row(
        children: [
          _Avatar(name: rawName, imageUrl: imageUrl),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  role,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.78),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    height: 1.1,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  phone,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  // A number reads left-to-right in both languages; without
                  // this a leading '+' is pushed to the wrong end in Arabic.
                  textDirection: identifierTextDirection(phone),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.84),
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.22),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.verified_rounded,
                        color: Colors.white,
                        size: 15,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        statusLabel,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name, required this.imageUrl});

  /// The driver's real name, or null when it is not known yet. A localized
  /// placeholder must never be passed here: initials taken from
  /// "Not available" read as "NA", and from "غير متوفر" as "غم", which look
  /// like somebody's actual initials.
  final String? name;
  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final fallback = _fallback();

    return Container(
      width: 78,
      height: 78,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
      ),
      clipBehavior: Clip.antiAlias,
      child:
          imageUrl == null
              ? fallback
              : Image.network(
                imageUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => fallback,
              ),
    );
  }

  Widget _fallback() {
    final initials = _initials();
    if (initials.isEmpty) {
      // Nothing to abbreviate: a neutral mark, in no language at all.
      return const Center(
        child: Icon(Icons.person_rounded, color: Colors.white, size: 34),
      );
    }
    return Center(
      child: Text(
        initials,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 24,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  String _initials() {
    final value = name?.trim() ?? '';
    if (value.isEmpty) return '';
    return value
        .split(RegExp(r'\s+'))
        .where((part) => part.trim().isNotEmpty)
        .take(2)
        .map((part) => part.characters.first.toUpperCase())
        .join();
  }
}

/// Replaces the statistics cards while they are loading or after a failed
/// read, so the hub never shows a zero it cannot stand behind.
class _StatsNotice extends StatelessWidget {
  const _StatsNotice({
    required this.icon,
    required this.message,
    this.showSpinner = false,
  });

  final IconData icon;
  final String message;
  final bool showSpinner;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xffE1E8F2)),
      ),
      child: Row(
        children: [
          if (showSpinner)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2.2),
            )
          else
            Icon(icon, color: const Color(0xff94A3B8), size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xff64748B),
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatsStrip extends StatelessWidget {
  const _StatsStrip({required this.items});

  final List<_ProfileStatItem> items;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 520 ? 4 : 2;
        final width = (constraints.maxWidth - ((columns - 1) * 10)) / columns;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children:
              items.map((item) {
                return SizedBox(width: width, child: _StatCard(item: item));
              }).toList(),
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.item});

  final _ProfileStatItem item;

  @override
  Widget build(BuildContext context) {
    // A minimum rather than a fixed height: at a large accessibility text
    // scale the three lines no longer fit in 104 and the card grows instead
    // of overflowing.
    return Container(
      constraints: const BoxConstraints(minHeight: 104),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xffE1E8F2)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(item.icon, color: AppColors.primary, size: 21),
          const SizedBox(height: 14),
          Text(
            item.value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xff0F172A),
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            item.label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xff64748B),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileStatItem {
  const _ProfileStatItem({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xffE1E8F2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Color(0xff0F172A),
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          _IconBox(icon: icon),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xff64748B),
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              // Phone numbers and driver ids stay left-to-right inside the
              // Arabic layout; a localized label keeps the page direction.
              textDirection: identifierTextDirection(value),
              style: const TextStyle(
                color: Color(0xff0F172A),
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
    this.badgeCount = 0,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  /// Optional unread pill shown before the chevron. Zero hides it.
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          children: [
            _IconBox(icon: icon),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xff0F172A),
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    // Two lines, because the Arabic wording plus an unread
                    // pill does not fit on one at 360px.
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xff64748B),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            if (badgeCount > 0) ...[
              const SizedBox(width: 10),
              DriverChatUnreadBadge(count: badgeCount),
            ],
            const SizedBox(width: 10),
            const Icon(
              Icons.chevron_right_rounded,
              color: Color(0xff94A3B8),
              size: 24,
            ),
          ],
        ),
      ),
    );
  }
}

/// Chat entry point for the hub.
///
/// The badge reads the one app-wide conversations provider, so it shows the
/// same figure the chat screens do.
class _ConversationsRow extends StatefulWidget {
  const _ConversationsRow({required this.copy});

  final String Function(BuildContext, String, String) copy;

  @override
  State<_ConversationsRow> createState() => _ConversationsRowState();
}

class _ConversationsRowState extends State<_ConversationsRow> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // One read per visit to the hub, so the badge means something before the
      // driver opens chat. This is not a poll and starts no timer.
      unawaited(
        context.read<DriverChatConversationsProvider>().refreshUnreadCount(),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final copy = widget.copy;
    final unread = context.select<DriverChatConversationsProvider, int>(
      (provider) => provider.unreadCount,
    );

    return _ActionRow(
      icon: Icons.forum_outlined,
      label: copy(context, 'Conversations', 'المحادثات'),
      subtitle: copy(
        context,
        'Messages with operations and support',
        'الرسائل مع فريق العمليات والدعم',
      ),
      badgeCount: unread,
      // The same named push the floating launcher uses: a plain Navigator
      // route, not the bottom-nav overlay whose back handling would close the
      // wrong thing, and named so the launcher hides while it is on top.
      onTap: () {
        final navigator = Navigator.maybeOf(context) ?? Nav.key.currentState;
        if (navigator != null) {
          DriverChatNavigation.openConversations(navigator);
        }
      },
    );
  }
}

class _LanguageRow extends StatelessWidget {
  const _LanguageRow({required this.localeProvider});

  final LocaleProvider localeProvider;

  @override
  Widget build(BuildContext context) {
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          const _IconBox(icon: Icons.language_rounded),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isArabic ? 'اللغة' : 'Language',
                  style: const TextStyle(
                    color: Color(0xff0F172A),
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  // The endonym, not the storage key: this used to read
                  // "Arabic" inside the Arabic interface.
                  localeProvider.getLanguageDisplayName(
                    localeProvider.selectedLanguage,
                  ),
                  style: const TextStyle(
                    color: Color(0xff64748B),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: localeProvider.selectedLanguage,
              borderRadius: BorderRadius.circular(14),
              // Built from the provider's own list, so the options and the
              // stored values cannot drift apart.
              items:
                  localeProvider.languages
                      .map(
                        (language) => DropdownMenuItem<String>(
                          value: language,
                          child: Text(
                            localeProvider.getLanguageDisplayName(language),
                          ),
                        ),
                      )
                      .toList(),
              onChanged: (value) async {
                if (value == null) return;
                await localeProvider.setLanguage(value, context);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _LogoutButton extends StatelessWidget {
  const _LogoutButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    // `minimumSize` rather than a fixed SizedBox, so a larger accessibility
    // text scale grows the button instead of overflowing it.
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: const Icon(Icons.logout_rounded),
      label: Text(isArabic ? 'تسجيل الخروج' : 'Logout'),
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xffDC2626),
        side: const BorderSide(color: Color(0xffFECACA)),
        backgroundColor: const Color(0xffFEF2F2),
        minimumSize: const Size.fromHeight(54),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
      ),
    );
  }
}

class _DeactivateAccountButton extends StatelessWidget {
  const _DeactivateAccountButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: const Icon(Icons.pause_circle_outline_rounded),
      label: Text(isArabic ? 'إيقاف الحساب' : 'Deactivate Account'),
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xffB45309),
        side: const BorderSide(color: Color(0xffFCD34D)),
        backgroundColor: const Color(0xffFFFBEB),
        minimumSize: const Size.fromHeight(54),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
      ),
    );
  }
}

/// The deactivation confirmation.
///
/// It stays on screen while the request runs and shows its own progress. The
/// flow used to close the sheet first and raise a global loader dialog, which
/// was dismissed with an unconditional pop — and a throw after that dismissal
/// popped a real page instead.
class _DeactivateAccountSheet extends StatefulWidget {
  const _DeactivateAccountSheet({
    required this.title,
    required this.message,
    required this.cancelLabel,
    required this.confirmLabel,
    required this.onConfirm,
  });

  final String title;
  final String message;
  final String cancelLabel;
  final String confirmLabel;

  /// Runs the deactivation. Completes whether it succeeded or failed; on
  /// success the app has already navigated away from this sheet.
  final Future<void> Function() onConfirm;

  @override
  State<_DeactivateAccountSheet> createState() =>
      _DeactivateAccountSheetState();
}

class _DeactivateAccountSheetState extends State<_DeactivateAccountSheet> {
  bool _busy = false;

  Future<void> _confirm() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.onConfirm();
    } finally {
      // On success the navigator has replaced everything below, so this sheet
      // is gone and must not be touched.
      if (mounted) {
        setState(() => _busy = false);
        Navigator.of(context).maybePop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.title;
    final message = widget.message;
    final cancelLabel = widget.cancelLabel;
    final confirmLabel = widget.confirmLabel;

    // A destructive request is in flight; a stray back gesture must not
    // abandon it half-done.
    return PopScope(
      canPop: !_busy,
      child: _buildSheet(context, title, message, cancelLabel, confirmLabel),
    );
  }

  Widget _buildSheet(
    BuildContext context,
    String title,
    String message,
    String cancelLabel,
    String confirmLabel,
  ) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 48,
              height: 5,
              decoration: BoxDecoration(
                color: const Color(0xffCBD5E1),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(height: 22),
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: const Color(0xffFFFBEB),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(
                Icons.pause_circle_outline_rounded,
                color: Color(0xffB45309),
                size: 30,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xff0F172A),
                fontSize: 21,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xff64748B),
                fontSize: 14,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy ? null : () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: BorderSide(color: AppColors.primary),
                      minimumSize: const Size.fromHeight(52),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Text(
                      cancelLabel,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    // Disabled while the request runs; the provider refuses
                    // re-entry as well, so a tap that lands before this
                    // rebuild is still ignored.
                    onPressed: _busy ? null : _confirm,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xffB45309),
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(52),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child:
                        _busy
                            ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                                color: Colors.white,
                              ),
                            )
                            : Text(
                              confirmLabel,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _IconBox extends StatelessWidget {
  const _IconBox({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(icon, color: AppColors.primary, size: 21),
    );
  }
}
