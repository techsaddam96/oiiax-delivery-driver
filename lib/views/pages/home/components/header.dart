import 'dart:async';

import 'package:blockatie/constants/colors.dart';
import 'package:blockatie/provider/bottom_nav.dart';
import 'package:blockatie/provider/home.dart';
import 'package:blockatie/provider/notification.dart';
import 'package:blockatie/provider/shipment.dart';
import 'package:blockatie/utils/nav.dart';
import 'package:blockatie/views/pages/home/components/tabbar.dart';
import 'package:blockatie/views/pages/home/filter/filter.dart';
import 'package:blockatie/views/widgets/unread_count_badge.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class HomeHeader extends StatefulWidget {
  const HomeHeader({
    super.key,
    this.tabController,
    this.showSearchFiled = false,
    this.notificationCount = 0,
    this.searchController,
    this.onSearchChanged,
    this.title,
    this.subtitle,
    this.showNotificationShortcut = true,
    this.showProfileShortcut = true,
    this.showBack = false,
    this.onBack,
  });

  final TabController? tabController;
  final int notificationCount;
  final bool? showSearchFiled;
  final TextEditingController? searchController;
  final Function(String)? onSearchChanged;
  final String? title;
  final String? subtitle;
  final bool showNotificationShortcut;
  final bool showProfileShortcut;

  /// Shows a leading back control. Off by default, because this header started
  /// life on the tab screens, which have nothing to go back to.
  ///
  /// A pushed screen that used it therefore had no way out at all: the details
  /// screen is opened without the bottom bar, so the driver was left with only
  /// the system back gesture.
  final bool showBack;

  /// What the back control does. The two settlement screens need different
  /// answers — one is a bottom-nav overlay, the other a pushed route — so the
  /// header never guesses.
  final VoidCallback? onBack;

  @override
  State<HomeHeader> createState() => _HomeHeaderState();
}

class _HomeHeaderState extends State<HomeHeader> {
  late final TextEditingController _searchController;
  late final bool _ownsSearchController;
  final FocusNode _searchFocusNode = FocusNode();
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _ownsSearchController = widget.searchController == null;
    _searchController = widget.searchController ?? TextEditingController();
    _searchController.addListener(_onSearchChanged);
  }

  void _onSearchChanged() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 450), () {
      if (!mounted) return;
      final value = _searchController.text;
      widget.onSearchChanged?.call(value);
      if (widget.onSearchChanged == null) {
        context.read<ShipmentProvider>().searchShipments(value);
      }
    });
  }

  void _clearSearch() {
    _searchController.clear();
    context.read<HomeProvider>().setQuery('');
    context.read<ShipmentProvider>().clearSearch();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.removeListener(_onSearchChanged);
    if (_ownsSearchController) {
      _searchController.dispose();
    }
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final showSearch = widget.showSearchFiled ?? false;
    final title = widget.title ?? _copy(context, 'OIIAX Driver', 'OIIAX');
    final subtitle =
        widget.subtitle ??
        _copy(context, 'Delivery operations', 'عمليات التوصيل');

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(16, 14, 16, showSearch ? 12 : 10),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: const Color(0xff0F172A).withValues(alpha: 0.05),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (widget.showBack) ...[
                _HeaderIconButton(
                  // The row mirrors in Arabic, so the control sits on the
                  // right; an arrow still pointing left would contradict it.
                  icon:
                      Directionality.of(context) == TextDirection.rtl
                          ? Icons.arrow_forward_ios_rounded
                          : Icons.arrow_back_ios_new_rounded,
                  tooltip: _copy(context, 'Back', 'رجوع'),
                  onTap:
                      widget.onBack ?? () => Navigator.of(context).maybePop(),
                ),
                const SizedBox(width: 8),
              ],
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
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xff64748B),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.showNotificationShortcut)
                Consumer<NotificationProvider>(
                  builder: (context, provider, _) {
                    return _HeaderIconButton(
                      icon: Icons.notifications_none_rounded,
                      tooltip: _copy(context, 'Notifications', 'الإشعارات'),
                      badgeCount: provider.unreadCount,
                      onTap: () {
                        context.read<HomeProvider>().resetToHome();
                        context.read<BottomNavProvider>().setIndex(3);
                      },
                    );
                  },
                ),
              if (widget.showProfileShortcut) ...[
                const SizedBox(width: 8),
                _HeaderIconButton(
                  icon: Icons.person_outline_rounded,
                  tooltip: _copy(context, 'My Account', 'حسابي'),
                  onTap: () {
                    context.read<HomeProvider>().resetToHome();
                    context.read<BottomNavProvider>().setIndex(4);
                  },
                ),
              ],
            ],
          ),
          if (showSearch) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    focusNode: _searchFocusNode,
                    textInputAction: TextInputAction.search,
                    onChanged: context.read<HomeProvider>().setQuery,
                    onSubmitted: (_) => _searchFocusNode.unfocus(),
                    decoration: InputDecoration(
                      hintText: _copy(
                        context,
                        'Search by policy, name, or phone',
                        'ابحث برقم الشحنة أو الاسم أو الهاتف',
                      ),
                      prefixIcon: const Icon(
                        Icons.search_rounded,
                        color: Color(0xff64748B),
                      ),
                      suffixIcon:
                          _searchController.text.isNotEmpty
                              ? IconButton(
                                icon: const Icon(Icons.close_rounded),
                                color: const Color(0xff64748B),
                                tooltip: _copy(context, 'Clear', 'مسح'),
                                onPressed: _clearSearch,
                              )
                              : null,
                      filled: true,
                      fillColor: const Color(0xffF1F5F9),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 0,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                _HeaderIconButton(
                  icon: Icons.tune_rounded,
                  tooltip: _copy(context, 'Filter', 'تصفية'),
                  filled: true,
                  onTap: () => Nav.to(FilterPage()),
                ),
              ],
            ),
            if (widget.tabController != null) ...[
              const SizedBox(height: 12),
              HomeTabbar(tabController: widget.tabController!),
            ],
          ],
        ],
      ),
    );
  }

  String _copy(BuildContext context, String en, String ar) {
    return Localizations.localeOf(context).languageCode == 'ar' ? ar : en;
  }
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.badgeCount = 0,
    this.filled = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final int badgeCount;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: filled ? AppColors.primary : const Color(0xffF1F5F9),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: filled ? AppColors.primary : const Color(0xffE2E8F0),
            ),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Center(
                child: Icon(
                  icon,
                  size: 22,
                  color: filled ? Colors.white : AppColors.primary,
                ),
              ),
              // Directional, so the pill sits on the trailing corner in Arabic
              // instead of staying physically right.
              if (badgeCount > 0)
                PositionedDirectional(
                  end: 4,
                  top: 5,
                  child: UnreadCountBadge(
                    count: badgeCount,
                    fontSize: 8.5,
                    minSize: 15,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
