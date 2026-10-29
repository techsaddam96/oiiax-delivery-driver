import 'dart:async';

import 'package:blockatie/constants/colors.dart';
import 'package:blockatie/models/driver_profile.dart';
import 'package:blockatie/provider/profile.dart';
import 'package:blockatie/services/auth_services.dart';
import 'package:blockatie/services/user_session_state.dart';
import 'package:blockatie/utils/nav.dart';
import 'package:blockatie/utils/text_direction.dart';
import 'package:blockatie/views/pages/hub/setting/settings.dart';
import 'package:blockatie/views/widgets/driver_chat_bubble.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  bool _isLoading = true;
  bool _loadFailed = false;
  String? _localName;
  String? _localPhone;
  String? _localDriverId;

  /// The session this screen's data belongs to. Every async result is checked
  /// against it, so a read addressed to the previous driver can never land on
  /// the next one's screen.
  late int _generation;
  bool _sessionEnded = false;

  @override
  void initState() {
    super.initState();
    _generation = UserSessionState.generation;
    UserSessionState.changes.addListener(_onSessionChanged);
    unawaited(_loadProfile());
  }

  @override
  void dispose() {
    UserSessionState.changes.removeListener(_onSessionChanged);
    super.dispose();
  }

  /// A logout or an account switch invalidates everything on this screen.
  /// These values live in State, so clearing the provider is not enough — the
  /// previous driver's name, phone and id would stay on screen until the route
  /// happened to be popped.
  void _onSessionChanged() {
    if (!mounted || UserSessionState.isCurrent(_generation)) return;
    setState(() {
      _sessionEnded = true;
      _localName = null;
      _localPhone = null;
      _localDriverId = null;
      _isLoading = false;
      _loadFailed = true;
    });
    if (Navigator.of(context).canPop()) Nav.back();
  }

  Future<void> _loadProfile() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _loadFailed = false;
    });

    final provider = context.read<ProfileProvider>();
    final values = await Future.wait([
      AuthService.getDrivername(),
      AuthService.getPhone(),
      AuthService.getuserId(),
      provider.fetchDriverProfile(),
    ]);
    // A reply addressed to the previous driver must never populate this screen
    // for the next one.
    if (!mounted || !UserSessionState.isCurrent(_generation)) return;

    final profile = values[3] as DriverInfo?;
    setState(() {
      _localName = values[0] as String?;
      _localPhone = values[1] as String?;
      _localDriverId = values[2] as String?;
      _isLoading = false;
      // Nothing came back and nothing was cached locally either. That is a
      // failed read, not an account with no data, and it must not be drawn as
      // one.
      _loadFailed =
          profile == null &&
          (_localName ?? '').trim().isEmpty &&
          (_localPhone ?? '').trim().isEmpty;
    });
  }

  @override
  Widget build(BuildContext context) {
    final profile =
        _sessionEnded ? null : context.watch<ProfileProvider>().profileInfo;

    return Scaffold(
      backgroundColor: const Color(0xffF4F7FB),
      body: SafeArea(
        child: Column(
          children: [
            _PageHeader(
              title: _copy(context, 'Profile Details', 'تفاصيل الحساب'),
              subtitle: _copy(
                context,
                'Your saved driver information',
                'بيانات المندوب المحفوظة',
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                color: AppColors.primary,
                onRefresh: _loadProfile,
                child:
                    _isLoading
                        ? const _LoadingState()
                        : _loadFailed
                        ? _ErrorState(
                          message: _copy(
                            context,
                            'Unable to load account details. Please try again.',
                            'تعذر تحميل بيانات الحساب. يرجى المحاولة مرة أخرى.',
                          ),
                          retryLabel: _copy(context, 'Retry', 'حاول مرة أخرى'),
                          onRetry: _loadProfile,
                        )
                        : SingleChildScrollView(
                          physics: const AlwaysScrollableScrollPhysics(
                            parent: BouncingScrollPhysics(),
                          ),
                          // Clears the floating chat launcher as well as the
                          // bottom-navigation pill.
                          padding: EdgeInsets.fromLTRB(
                            18,
                            16,
                            18,
                            DriverChatBubble.reservedBottomSpace + 16,
                          ),
                          child: Column(
                            children: [
                              _ProfileSummaryCard(
                                name: _profileName(context, profile),
                                phone: _profilePhone(context, profile),
                                role: _copy(
                                  context,
                                  'Delivery Driver',
                                  'مندوب توصيل',
                                ),
                                imageUrl: _profileImageUrl(profile),
                                status: _statusLabel(context, profile),
                              ),
                              const SizedBox(height: 16),
                              _DetailsCard(
                                title: _copy(
                                  context,
                                  'Account Information',
                                  'معلومات الحساب',
                                ),
                                rows: [
                                  _DetailRowData(
                                    Icons.badge_outlined,
                                    _copy(context, 'Driver ID', 'رقم السائق'),
                                    _value(context, _localDriverId),
                                  ),
                                  _DetailRowData(
                                    Icons.person_outline_rounded,
                                    _copy(context, 'Name', 'الاسم'),
                                    _profileName(context, profile),
                                  ),
                                  _DetailRowData(
                                    Icons.phone_outlined,
                                    _copy(context, 'Phone', 'الهاتف'),
                                    _profilePhone(context, profile),
                                  ),
                                  _DetailRowData(
                                    Icons.verified_user_outlined,
                                    _copy(
                                      context,
                                      'Account Status',
                                      'حالة الحساب',
                                    ),
                                    _statusLabel(context, profile),
                                  ),
                                  _DetailRowData(
                                    Icons.workspace_premium_outlined,
                                    _copy(context, 'Subscription', 'الاشتراك'),
                                    _subscriptionLabel(context, profile),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              _DetailsCard(
                                title: _copy(context, 'Manage', 'إدارة الحساب'),
                                rows: [
                                  _DetailRowData(
                                    Icons.edit_outlined,
                                    _copy(
                                      context,
                                      'Edit Profile',
                                      'تعديل المعلومات',
                                    ),
                                    _copy(
                                      context,
                                      'Photo and password',
                                      'الصورة وكلمة المرور',
                                    ),
                                    onTap:
                                        () => Nav.to(
                                          const SettingsPage(),
                                          withNav: true,
                                          navIndex: 4,
                                        ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _profileName(BuildContext context, DriverInfo? profile) {
    return _value(context, profile?.dname ?? _localName);
  }

  String _profilePhone(BuildContext context, DriverInfo? profile) {
    return _value(context, profile?.dphone ?? _localPhone);
  }

  String _statusLabel(BuildContext context, DriverInfo? profile) {
    if (profile == null) return _notAvailable(context);
    if (profile.status == 0) return _copy(context, 'Active', 'نشط');
    if (profile.status == 1) return _copy(context, 'Inactive', 'غير نشط');
    if (profile.status == 2) return _copy(context, 'Deactivated', 'موقوف');
    return _copy(context, 'Unknown', 'غير معروف');
  }

  String _subscriptionLabel(BuildContext context, DriverInfo? profile) {
    if (profile == null) return _notAvailable(context);
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
}

class _PageHeader extends StatelessWidget {
  const _PageHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          _HeaderButton(
            icon: Icons.arrow_back_ios_new_rounded,
            onTap: Nav.back,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xff0F172A),
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xff64748B),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
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

class _HeaderButton extends StatelessWidget {
  const _HeaderButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xffE2E8F0)),
        ),
        child: Icon(icon, color: AppColors.primary, size: 18),
      ),
    );
  }
}

class _ProfileSummaryCard extends StatelessWidget {
  const _ProfileSummaryCard({
    required this.name,
    required this.phone,
    required this.role,
    required this.imageUrl,
    required this.status,
  });

  final String name;
  final String phone;
  final String role;
  final String? imageUrl;
  final String status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xff0B63CE), Color(0xff00346F)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.20),
            blurRadius: 26,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Row(
        children: [
          _Avatar(name: name, imageUrl: imageUrl),
          const SizedBox(width: 14),
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
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    height: 1.1,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  phone,
                  textDirection: identifierTextDirection(phone),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.84),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                _StatusPill(label: status),
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

  final String name;
  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final initials =
        name
            .split(RegExp(r'\s+'))
            .where((part) => part.trim().isNotEmpty)
            .take(2)
            .map((part) => part.characters.first.toUpperCase())
            .join();

    return Container(
      width: 74,
      height: 74,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
      ),
      clipBehavior: Clip.antiAlias,
      child:
          imageUrl == null
              ? Center(child: _Initials(initials: initials))
              : Image.network(
                imageUrl!,
                fit: BoxFit.cover,
                errorBuilder:
                    (_, __, ___) =>
                        Center(child: _Initials(initials: initials)),
              ),
    );
  }
}

class _Initials extends StatelessWidget {
  const _Initials({required this.initials});

  final String initials;

  @override
  Widget build(BuildContext context) {
    return Text(
      initials.isEmpty ? 'D' : initials,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 24,
        fontWeight: FontWeight.w900,
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.24)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.verified_rounded, color: Colors.white, size: 14),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11.5,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailsCard extends StatelessWidget {
  const _DetailsCard({required this.title, required this.rows});

  final String title;
  final List<_DetailRowData> rows;

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
            color: Colors.black.withValues(alpha: 0.035),
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
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          ...rows.map((row) => _DetailRow(data: row)),
        ],
      ),
    );
  }
}

class _DetailRowData {
  const _DetailRowData(this.icon, this.label, this.value, {this.onTap});

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.data});

  final _DetailRowData data;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: data.onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          children: [
            _IconBox(icon: data.icon),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                data.label,
                style: const TextStyle(
                  color: Color(0xff64748B),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                data.value,
                textAlign: TextAlign.end,
                // The driver id and the phone read left-to-right in both
                // languages; a name or a localized placeholder does not.
                textDirection: identifierTextDirection(data.value),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xff0F172A),
                  fontSize: 13.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            if (data.onTap != null) ...[
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right_rounded, color: Color(0xff94A3B8)),
            ],
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
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(icon, color: AppColors.primary, size: 20),
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(top: 160),
      children: [
        Center(child: CircularProgressIndicator(color: AppColors.primary)),
      ],
    );
  }
}

String _copy(BuildContext context, String en, String ar) {
  return Localizations.localeOf(context).languageCode == 'ar' ? ar : en;
}

String _notAvailable(BuildContext context) {
  return _copy(context, 'Not available', 'غير متوفر');
}

/// Missing means missing, however the backend spells it: null, an empty
/// column, whitespace, or the literal four characters "null" that a loosely
/// typed column can hand back.
String _value(BuildContext context, String? value) {
  final text = value?.trim();
  if (text == null || text.isEmpty || text.toLowerCase() == 'null') {
    return _notAvailable(context);
  }
  return text;
}

/// Shown instead of the profile when nothing could be loaded.
class _ErrorState extends StatelessWidget {
  const _ErrorState({
    required this.message,
    required this.retryLabel,
    required this.onRetry,
  });

  final String message;
  final String retryLabel;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: const EdgeInsets.fromLTRB(24, 60, 24, 24),
      children: [
        const Icon(Icons.cloud_off_rounded, size: 44, color: Color(0xff94A3B8)),
        const SizedBox(height: 14),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xff0F172A),
            fontSize: 14,
            fontWeight: FontWeight.w800,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: Text(retryLabel),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            elevation: 0,
            minimumSize: const Size.fromHeight(46),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      ],
    );
  }
}
