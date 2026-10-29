import 'dart:async';

import 'package:blockatie/constants/app_urls.dart';
import 'package:blockatie/constants/colors.dart';
import 'package:blockatie/constants/helper.dart';
import 'package:blockatie/constants/notification_system.dart';
import 'package:blockatie/models/shipment.dart';
import 'package:blockatie/models/statistics.dart';
import 'package:blockatie/provider/bottom_nav.dart';
import 'package:blockatie/provider/home.dart';
import 'package:blockatie/provider/driver_work_session.dart';
import 'package:blockatie/provider/notification.dart';
import 'package:blockatie/provider/profile.dart';
import 'package:blockatie/provider/shipment.dart';
import 'package:blockatie/provider/shipment_flow_config.dart';
import 'package:blockatie/provider/shipment_instsnt.dart';
import 'package:blockatie/services/auth_services.dart';
import 'package:blockatie/utils/driver_shipment_actions.dart';
import 'package:blockatie/services/in_app_notification_service.dart';
import 'package:blockatie/utils/money.dart';
import 'package:blockatie/utils/nav.dart';
import 'package:blockatie/views/pages/home/components/header.dart';
import 'package:blockatie/views/pages/hub/support&assistance/support_assistence.dart';
import 'package:blockatie/views/pages/orders/order_details.dart';
import 'package:blockatie/views/pages/tours/driver_tours_page.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:upgrader/upgrader.dart';

import '../../../provider/order_location.dart';
import '../../../provider/operational_readiness.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with
        TickerProviderStateMixin,
        AutomaticKeepAliveClientMixin,
        WidgetsBindingObserver,
        Helper {
  @override
  bool get wantKeepAlive => true;

  late final TabController tabController;
  late final TextEditingController searchController;

  final InAppNotificationService _inAppNotificationService =
      InAppNotificationService();
  bool _notificationStartupDone = false;
  bool _didLoadInitialHomeData = false;
  OperationalReadinessProvider? _observedReadiness;
  OperationalReadinessState? _lastReadinessState;

  @override
  void initState() {
    super.initState();

    final homeProvider = context.read<HomeProvider>();
    searchController = TextEditingController();
    tabController = TabController(
      length: homeProvider.tabViews.length,
      vsync: this,
    );

    WidgetsBinding.instance.addObserver(this);
    NotificationSystem.onForegroundNotificationReceived =
        _handleForegroundNotification;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_loadInitialHomeData());
    });
  }

  Future<void> getStatistics() async {
    await context.read<HomeProvider>().getDriverStatistics(context);
  }

  Future<void> getShipments() async {
    await context.read<ShipmentProvider>().getAllShipments();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (AppUrls.driverWorkSessionsEnabled) {
      context.read<DriverWorkSessionProvider>().bindLocationProvider(
        context.read<OrderLocationProvider>(),
      );
    }
    final readiness = context.read<OperationalReadinessProvider>();
    if (identical(readiness, _observedReadiness)) return;
    _observedReadiness?.removeListener(_handleReadinessChange);
    _observedReadiness = readiness;
    _lastReadinessState = readiness.state;
    readiness.addListener(_handleReadinessChange);
  }

  void _handleReadinessChange() {
    if (!mounted) return;
    final readiness = _observedReadiness;
    if (readiness == null) return;
    final previous = _lastReadinessState;
    final current = readiness.state;
    _lastReadinessState = current;

    // A service/permission recovery must produce a real current fix. The
    // location provider refuses cached positions for server upload.
    if (current == OperationalReadinessState.ready &&
        previous != null &&
        previous != OperationalReadinessState.ready) {
      unawaited(context.read<OrderLocationProvider>().refreshCurrentLocation());
    }
  }

  Future<void> _loadInitialHomeData() async {
    if (_didLoadInitialHomeData) return;
    _didLoadInitialHomeData = true;

    final session = await AuthService.getSessionSnapshot();
    if (!mounted || !session.isAuthenticated) return;

    unawaited(
      context.read<OperationalReadinessProvider>().start(
        isArabic: Localizations.localeOf(context).languageCode == 'ar',
      ),
    );
    unawaited(_startLocationServicesIfAuthenticated());
    unawaited(context.read<HomeProvider>().getDriverStatistics(context));
    unawaited(context.read<ShipmentProvider>().getAllShipments());
    unawaited(
      context.read<NotificationProvider>().refreshUnreadCount(force: true),
    );
    unawaited(_initializeDeferredNotifications());
    unawaited(_inAppNotificationService.checkAndDisplay(context));
    unawaited(context.read<ShipmentFlowConfigProvider>().fetch());
  }

  Future<void> _resumeAuthenticatedServices() async {
    final session = await AuthService.getSessionSnapshot();
    if (!mounted || !session.isAuthenticated) return;

    // Admin assignment/reassignment can occur while the app is backgrounded.
    // Refresh the authenticated driver's authoritative counts and assigned
    // work on resume; refresh an already-open instant page without initiating
    // an offer-list request for a driver who has never opened it.
    unawaited(
      context.read<HomeProvider>().getDriverStatistics(context, force: true),
    );
    unawaited(context.read<ShipmentProvider>().getAllShipments(force: true));
    final instantShipments = context.read<ShipmentInstantprovider>();
    if (instantShipments.hasLoaded) {
      unawaited(instantShipments.getShipmentsInstant(force: true));
    }

    unawaited(
      context.read<OperationalReadinessProvider>().start(
        isArabic: Localizations.localeOf(context).languageCode == 'ar',
      ),
    );
    unawaited(_startLocationServicesIfAuthenticated());
    unawaited(
      context.read<NotificationProvider>().refreshUnreadCount(force: true),
    );
    unawaited(_inAppNotificationService.checkAndDisplay(context));
  }

  Future<void> _startLocationServicesIfAuthenticated() async {
    final session = await AuthService.getSessionSnapshot();
    if (!mounted || !session.isAuthenticated) return;

    if (AppUrls.driverWorkSessionsEnabled) {
      final workSessions = context.read<DriverWorkSessionProvider>();
      workSessions.bindLocationProvider(context.read<OrderLocationProvider>());
      // A stored raw key is not an active work state. The provider asks the
      // server on every Home/resume entry before it enables any v2 GPS write.
      await workSessions.restoreWorkSessionIfActive();
      return;
    }

    await context.read<OrderLocationProvider>().startDriverLocationUpdates(
      context: context,
    );
  }

  void _stopLocationServices() {
    if (!mounted) return;
    context.read<OrderLocationProvider>().stopDriverLocationUpdates();
  }

  Future<void> _requestLocationAccess() async {
    await context.read<OperationalReadinessProvider>().requestPermission(
      isArabic: Localizations.localeOf(context).languageCode == 'ar',
    );
    if (!mounted) return;
    await context.read<OrderLocationProvider>().startDriverLocationUpdates();
  }

  bool _shouldShowLocationNotice(OperationalReadinessState state) {
    return state == OperationalReadinessState.locationServiceOff ||
        state == OperationalReadinessState.locationPermissionDenied ||
        state ==
            OperationalReadinessState.locationPermissionPermanentlyDenied ||
        state == OperationalReadinessState.locationUnavailable;
  }

  Future<void> _initializeDeferredNotifications() async {
    if (_notificationStartupDone) return;
    _notificationStartupDone = true;

    final session = await AuthService.getSessionSnapshot();
    if (!mounted || !session.isAuthenticated) return;

    try {
      final notifications = NotificationSystem();
      await notifications.notificationReady();
      await notifications.subscribeDriverTopics(ensureTokenRegistered: false);
    } catch (e) {
      debugPrint('Deferred notification setup failed: ${e.runtimeType}');
    }
  }

  Future<void> _handleForegroundNotification() async {
    if (!mounted) return;
    await context.read<NotificationProvider>().refreshUnreadCount(force: true);
    if (!mounted) return;
    await _inAppNotificationService.checkAndDisplay(context);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    NotificationSystem.onForegroundNotificationReceived = null;
    _observedReadiness?.removeListener(_handleReadinessChange);
    context.read<OrderLocationProvider>().stopDriverLocationUpdates();
    tabController.dispose();
    searchController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (!mounted) return;
    if (state == AppLifecycleState.resumed) {
      unawaited(_resumeAuthenticatedServices());
    } else if (state == AppLifecycleState.paused) {
      _stopLocationServices();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return UpgradeAlert(
      showIgnore: false,
      barrierDismissible: false,
      child: SafeArea(
        child: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: Scaffold(
            resizeToAvoidBottomInset: false,
            backgroundColor: const Color(0xffF4F7FB),
            body: Column(
              children: [
                HomeHeader(
                  title: _copy(context, 'Welcome back', 'أهلاً بعودتك'),
                  subtitle: _copy(
                    context,
                    'Here is your delivery summary today',
                    'هذا ملخص عمليات التوصيل اليوم',
                  ),
                ),
                Expanded(child: _buildInitialHomeContent()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInitialHomeContent() {
    return Consumer3<HomeProvider, ShipmentProvider, ProfileProvider>(
      builder: (context, homeProvider, shipmentProvider, profileProvider, _) {
        final stats = homeProvider.safeStats;
        final readinessState =
            context.watch<OperationalReadinessProvider>().state;
        final activeShipments =
            shipmentProvider.activeOperationalShipments.take(2).toList();

        return RefreshIndicator(
          color: AppColors.primary,
          onRefresh: () async {
            await Future.wait([
              homeProvider.refresh(),
              shipmentProvider.onRefresh(),
            ]);
          },
          child: LayoutBuilder(
            builder: (context, constraints) {
              final horizontalPadding =
                  constraints.maxWidth < 360 ? 14.0 : 18.0;

              return SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  16,
                  horizontalPadding,
                  110,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _DashboardWelcomeCard(
                      // The profile result is server-authoritative. The fresh
                      // login name remains a safe, same-session fallback while
                      // that request is loading or temporarily unavailable.
                      driverName: _driverName(
                        context,
                        profileProvider.profileInfo?.dname ??
                            homeProvider.driverName,
                      ),
                      stats: stats,
                      readiness: readinessState,
                    ),
                    if (_shouldShowLocationNotice(readinessState)) ...[
                      const SizedBox(height: 12),
                      _LocationRequiredNotice(
                        readiness: readinessState,
                        onFix: _requestLocationAccess,
                      ),
                    ],
                    if (AppUrls.driverWorkSessionsEnabled) ...[
                      const SizedBox(height: 12),
                      const _DriverWorkSessionCard(),
                    ],
                    const SizedBox(height: 18),
                    if (homeProvider.hasStatisticsError) ...[
                      _DashboardErrorCard(
                        message: _copy(
                          context,
                          'Unable to load data. Please try again.',
                          'تعذر تحميل البيانات. حاول مرة أخرى.',
                        ),
                        onRetry:
                            () => homeProvider.getDriverStatistics(
                              context,
                              force: true,
                            ),
                      ),
                      const SizedBox(height: 18),
                    ],
                    _SectionHeader(
                      title: _copy(context, 'Delivery summary', 'ملخص التوصيل'),
                      subtitle: _copy(
                        context,
                        'Your live operational numbers',
                        'أرقام عملياتك الحالية',
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (homeProvider.isLoading &&
                        homeProvider.driverStats == null)
                      const _DashboardLoadingGrid()
                    else
                      _StatsGrid(stats: stats),
                    const SizedBox(height: 22),
                    _SectionHeader(
                      title: _copy(context, 'Quick actions', 'إجراءات سريعة'),
                      subtitle: _copy(
                        context,
                        'Move to the screens you use most',
                        'انتقل للشاشات الأكثر استخداماً',
                      ),
                    ),
                    const SizedBox(height: 12),
                    _QuickActionsGrid(actions: _quickActions(context)),
                    const SizedBox(height: 22),
                    _SectionHeader(
                      title: _copy(context, 'Active shipment', 'الشحنة النشطة'),
                      subtitle: _copy(
                        context,
                        'Latest assigned work preview',
                        'معاينة آخر الشحنات المسندة',
                      ),
                    ),
                    const SizedBox(height: 12),
                    _ActiveShipmentPreview(
                      isLoading:
                          shipmentProvider.isLoading &&
                          shipmentProvider.paginatedShipments.isEmpty,
                      shipments: activeShipments,
                      statusLabel:
                          (shipment) => getLocalizedTypeName(
                            shipment.statusNameEn,
                            shipment.statusNameAr,
                          ),
                      onOpen: (shipment) {
                        Nav.to(
                          OrderDetailPage(
                            shipment: shipment,
                            phoneCustomer: shipment.phclient,
                            shipmentId: shipment.id,
                            deliveryAdd: shipment.lclient,
                            storeAdd: shipment.nstore,
                            orderDate: shipment.createdAt,
                          ),
                          withNav: true,
                          navIndex: 1,
                        );
                      },
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  List<_DashboardAction> _quickActions(BuildContext context) {
    final scheduledVisible =
        context
            .watch<ShipmentFlowConfigProvider>()
            .config
            .scheduledShipments
            .isVisible;
    return [
      if (scheduledVisible)
        _DashboardAction(
          title: _copy(context, 'Scheduled shipments', 'الشحنات المجدولة'),
          subtitle: _copy(context, 'View shipments', 'عرض الشحنات'),
          icon: Icons.inventory_2_outlined,
          color: const Color(0xff0B63CE),
          onTap: () {
            context.read<BottomNavProvider>().setShipmentsTabScope('scheduled');
            context.read<BottomNavProvider>().setIndex(1);
          },
        ),
      // Hidden until Driver Tours is activated for the build (D6).
      if (AppUrls.driverToursEnabled)
        _DashboardAction(
          title: _copy(context, 'My tour', 'جولتي'),
          subtitle: _copy(context, 'Stops and progress', 'المحطات والتقدم'),
          icon: Icons.route_rounded,
          color: const Color(0xff7755D6),
          // An in-app overlay preserves the authenticated shell and the
          // driver's existing dashboard/navigation state.
          onTap:
              () => Nav.to(const DriverToursPage(), withNav: true, navIndex: 0),
        ),
      _DashboardAction(
        title: _copy(context, 'Instant', 'الفورية'),
        subtitle: _copy(
          context,
          'Available instant shipments',
          'الشحنات الفورية المتاحة',
        ),
        icon: Icons.flash_on_rounded,
        color: AppColors.primary,
        onTap: () {
          context.read<BottomNavProvider>().setShipmentsTab(0, offers: true);
          context.read<BottomNavProvider>().setIndex(1);
        },
      ),
      _DashboardAction(
        title: _copy(context, 'Wallet', 'المحفظة'),
        subtitle: _copy(context, 'Earnings', 'الأرباح'),
        icon: Icons.account_balance_wallet_outlined,
        color: const Color(0xff16A06D),
        onTap: () {
          context.read<HomeProvider>().resetToHome();
          context.read<BottomNavProvider>().setIndex(2);
        },
      ),
      _DashboardAction(
        title: _copy(context, 'Notifications', 'الإشعارات'),
        subtitle: _copy(context, 'Updates', 'التحديثات'),
        icon: Icons.notifications_none_rounded,
        color: const Color(0xff7755D6),
        onTap: () => context.read<BottomNavProvider>().setIndex(3),
      ),
      _DashboardAction(
        title: _copy(context, 'Support', 'الدعم'),
        subtitle: _copy(context, 'Need help?', 'تحتاج مساعدة؟'),
        icon: Icons.support_agent_rounded,
        color: const Color(0xffF59E0B),
        onTap:
            () => Nav.to(
              const SupportAssistencePage(),
              withNav: true,
              navIndex: 4,
            ),
      ),
      _DashboardAction(
        title: _copy(context, 'Profile', 'الملف'),
        subtitle: _copy(context, 'Account hub', 'مركز الحساب'),
        icon: Icons.person_outline_rounded,
        color: const Color(0xff334155),
        onTap: () {
          context.read<HomeProvider>().resetToHome();
          context.read<BottomNavProvider>().setIndex(4);
        },
      ),
    ];
  }

  String _driverName(BuildContext context, String? value) {
    final name = value?.trim();
    if (name == null || name.isEmpty) {
      return _copy(context, 'Driver', 'المندوب');
    }
    return name;
  }
}

class _DashboardWelcomeCard extends StatelessWidget {
  const _DashboardWelcomeCard({
    required this.driverName,
    required this.stats,
    required this.readiness,
  });

  final String driverName;
  final DriverStatisticsData stats;
  final OperationalReadinessState readiness;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primary, AppColors.gradient2],
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.20),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Stack(
        children: [
          const PositionedDirectional(
            top: -38,
            end: -28,
            child: _SoftCircle(size: 126, opacity: 0.12),
          ),
          const PositionedDirectional(
            bottom: -54,
            start: -36,
            child: _SoftCircle(size: 136, opacity: 0.08),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _copy(context, 'Welcome back', 'أهلاً بعودتك'),
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          driverName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _copy(
                            context,
                            'Here is your delivery summary today',
                            'هذا ملخص عمليات التوصيل اليوم',
                          ),
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _LocationStatusBadge(readiness: readiness),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    height: 46,
                    width: 46,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.20),
                      ),
                    ),
                    child: const Icon(
                      Icons.route_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: _HeroMetric(
                      value: stats.shipments.toString(),
                      label: _copy(context, 'Assigned', 'مسندة'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _HeroMetric(
                      value: stats.shipmentsInProgress.toString(),
                      label: _copy(context, 'In progress', 'قيد التنفيذ'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _HeroMetric(
                      value: formatMoney(context, stats.totalDriverDue),
                      label: _copy(context, 'Earnings due', 'الأرباح المستحقة'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LocationStatusBadge extends StatelessWidget {
  const _LocationStatusBadge({required this.readiness});

  final OperationalReadinessState readiness;

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = switch (readiness) {
      OperationalReadinessState.ready => (
        _copy(context, 'Location active', 'الموقع مفعل'),
        const Color(0xff16A06D),
        Icons.location_on_rounded,
      ),
      OperationalReadinessState.locationServiceOff => (
        _copy(context, 'Location service is off', 'خدمة الموقع متوقفة'),
        const Color(0xffF59E0B),
        Icons.location_disabled_rounded,
      ),
      OperationalReadinessState.locationPermissionDenied => (
        _copy(context, 'Location permission required', 'صلاحية الموقع مطلوبة'),
        const Color(0xffF59E0B),
        Icons.location_searching_rounded,
      ),
      OperationalReadinessState.locationPermissionPermanentlyDenied => (
        _copy(context, 'Open app settings', 'افتح إعدادات التطبيق'),
        const Color(0xffEF4444),
        Icons.settings_rounded,
      ),
      OperationalReadinessState.locationUnavailable => (
        _copy(context, 'Location unavailable', 'الموقع غير متوفر'),
        const Color(0xffEF4444),
        Icons.location_off_rounded,
      ),
      OperationalReadinessState.vpnActive => (
        _copy(context, 'VPN detected', 'تم اكتشاف VPN'),
        const Color(0xffEF4444),
        Icons.vpn_lock_rounded,
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DriverWorkSessionCard extends StatelessWidget {
  const _DriverWorkSessionCard();

  @override
  Widget build(BuildContext context) {
    return Consumer<DriverWorkSessionProvider>(
      builder: (context, work, _) {
        final isArabic = Localizations.localeOf(context).languageCode == 'ar';
        final (title, message, color, icon, action) = switch (work.state) {
          DriverWorkSessionState.active => (
            isArabic ? 'العمل الآمن نشط' : 'Secure work is active',
            isArabic
                ? 'تتم مشاركة الموقع بقراءة GPS موثقة.'
                : 'Location sharing uses a verified GPS session.',
            const Color(0xff16A06D),
            Icons.verified_user_rounded,
            isArabic ? 'إنهاء العمل' : 'End Work',
          ),
          DriverWorkSessionState.legacyTracking => (
            isArabic ? 'تتبع الموقع التقليدي نشط' : 'Legacy location tracking',
            isArabic
                ? 'خدمة الجلسات غير متاحة؛ لم يتم تفعيل جلسة عمل آمنة.'
                : 'The session service is unavailable; no secure work session is active.',
            const Color(0xffB45309),
            Icons.location_on_outlined,
            isArabic ? 'إيقاف مشاركة الموقع' : 'Stop location sharing',
          ),
          DriverWorkSessionState.pendingEnd => (
            isArabic ? 'إنهاء العمل قيد الانتظار' : 'End Work pending',
            isArabic
                ? 'توقفت مشاركة الموقع على هذا الجهاز. ستتم إعادة محاولة الإنهاء عند الاتصال.'
                : 'Location sharing stopped on this device. End Work will retry when connected.',
            const Color(0xffB45309),
            Icons.cloud_off_rounded,
            isArabic ? 'إعادة المحاولة' : 'Retry',
          ),
          DriverWorkSessionState.expired => (
            isArabic ? 'انتهت جلسة العمل' : 'Work session ended',
            isArabic
                ? 'ابدأ العمل مرة أخرى لمشاركة الموقع.'
                : 'Start Work again before sharing live location.',
            const Color(0xffDC2626),
            Icons.timer_off_rounded,
            isArabic ? 'بدء العمل' : 'Start Work',
          ),
          DriverWorkSessionState.disabled => (
            isArabic
                ? 'الجلسات الآمنة غير مفعلة'
                : 'Secure sessions are disabled',
            isArabic
                ? 'يمكنك استخدام سير العمل الحالي، لكن لم تبدأ جلسة عمل آمنة.'
                : 'The existing workflow remains available, but no secure work session started.',
            const Color(0xff0B63CE),
            Icons.info_outline_rounded,
            isArabic ? 'المحاولة مرة أخرى' : 'Try again',
          ),
          DriverWorkSessionState.unavailable ||
          DriverWorkSessionState.locationUnavailable => (
            isArabic ? 'تعذر بدء العمل الآمن' : 'Secure work is unavailable',
            isArabic
                ? 'تحقق من الاتصال والموقع ثم أعد المحاولة.'
                : 'Check connectivity and location, then try again.',
            const Color(0xffB45309),
            Icons.cloud_off_rounded,
            isArabic ? 'المحاولة مرة أخرى' : 'Try again',
          ),
          DriverWorkSessionState.starting => (
            isArabic ? 'جارٍ بدء العمل...' : 'Starting Work…',
            isArabic
                ? 'يتم التحقق من جلسة الموقع الآمنة.'
                : 'Verifying the secure location session.',
            const Color(0xff0B63CE),
            Icons.sync_rounded,
            '',
          ),
          DriverWorkSessionState.ending => (
            isArabic ? 'جارٍ إنهاء العمل...' : 'Ending Work…',
            isArabic
                ? 'توقفت مشاركة الموقع على هذا الجهاز.'
                : 'Location sharing stopped on this device.',
            const Color(0xff0B63CE),
            Icons.sync_rounded,
            '',
          ),
          DriverWorkSessionState.inactive => (
            isArabic ? 'لست في العمل' : 'Not working',
            isArabic
                ? 'ابدأ العمل لإنشاء جلسة مشاركة موقع آمنة.'
                : 'Start Work to create a secure location-sharing session.',
            const Color(0xff475569),
            Icons.play_circle_outline_rounded,
            isArabic ? 'بدء العمل' : 'Start Work',
          ),
        };

        final endsLocalSharing =
            work.state == DriverWorkSessionState.active ||
            work.state == DriverWorkSessionState.legacyTracking;
        return Container(
          key: const Key('driverWorkSessionCard'),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: color.withValues(alpha: 0.24)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 25),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: color,
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      message,
                      style: const TextStyle(
                        color: Color(0xff475569),
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      key: const Key('driverWorkSessionAction'),
                      onPressed:
                          work.isBusy
                              ? null
                              : () => unawaited(
                                endsLocalSharing ||
                                        work.state ==
                                            DriverWorkSessionState.pendingEnd
                                    ? work.endWork()
                                    : work.startWork(),
                              ),
                      style: FilledButton.styleFrom(
                        backgroundColor: color,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(0, 38),
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon:
                          work.isBusy
                              ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                              : Icon(
                                endsLocalSharing
                                    ? Icons.stop_circle_outlined
                                    : Icons.play_arrow_rounded,
                                size: 18,
                              ),
                      label: Text(action),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _LocationRequiredNotice extends StatelessWidget {
  const _LocationRequiredNotice({required this.readiness, required this.onFix});

  final OperationalReadinessState readiness;
  final VoidCallback onFix;

  @override
  Widget build(BuildContext context) {
    final isDisabled =
        readiness == OperationalReadinessState.locationServiceOff;
    final isUnavailable =
        readiness == OperationalReadinessState.locationUnavailable;
    final Color color =
        isUnavailable
            ? const Color(0xffDC2626)
            : isDisabled
            ? const Color(0xffEA580C)
            : const Color(0xff0B63CE);
    final IconData icon =
        isDisabled
            ? Icons.location_disabled_rounded
            : Icons.location_searching_rounded;
    final String title =
        isDisabled
            ? _copy(context, 'Location service is off', 'خدمة الموقع متوقفة')
            : _copy(context, 'Allow location access', 'اسمح بالوصول للموقع');
    final String message =
        isDisabled
            ? _copy(
              context,
              'Location must be enabled to receive orders and update your position correctly.',
              'يجب تشغيل الموقع لاستقبال الطلبات وتحديث موقعك بشكل صحيح.',
            )
            : _copy(
              context,
              'Drivers must keep location active while working so dispatch can track deliveries safely.',
              'يجب أن يبقى موقع السائق مفعلاً أثناء العمل حتى يتم تتبع عمليات التوصيل بأمان.',
            );

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: color,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  message,
                  style: const TextStyle(
                    color: Color(0xff475569),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: FilledButton.icon(
                    onPressed: onFix,
                    style: FilledButton.styleFrom(
                      backgroundColor: color,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(0, 38),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: const Icon(Icons.my_location_rounded, size: 17),
                    label: Text(
                      isDisabled
                          ? _copy(context, 'Turn on location', 'تشغيل الموقع')
                          : _copy(context, 'Enable now', 'تفعيل الآن'),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
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

class _HeroMetric extends StatelessWidget {
  const _HeroMetric({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              value,
              maxLines: 1,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            // "Earnings due" says what the number is; in Arabic it needs a
            // second line at this width rather than an ellipsis.
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.72),
              fontSize: 11,
              fontWeight: FontWeight.w600,
              height: 1.25,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({required this.stats});

  final DriverStatisticsData stats;

  @override
  Widget build(BuildContext context) {
    final cards = [
      _DashboardStat(
        title: _copy(context, 'Assigned shipments', 'الشحنات المسندة'),
        value: stats.shipments.toString(),
        icon: Icons.inventory_2_outlined,
        color: const Color(0xff0B63CE),
      ),
      _DashboardStat(
        title: _copy(context, 'In progress', 'قيد التنفيذ'),
        value: stats.shipmentsInProgress.toString(),
        icon: Icons.local_shipping_outlined,
        color: AppColors.primary,
      ),
      _DashboardStat(
        title: _copy(context, 'Delivered', 'تم التسليم'),
        value: stats.shipmentsDelivered.toString(),
        icon: Icons.check_circle_outline_rounded,
        color: const Color(0xff16A06D),
      ),
      _DashboardStat(
        title: _copy(context, 'Cancelled / Failed', 'ملغاة / فاشلة'),
        value: stats.cancelledShipments.toString(),
        icon: Icons.cancel_outlined,
        color: const Color(0xffEF4444),
      ),
      _DashboardStat(
        title: _copy(context, 'Earnings due', 'الأرباح المستحقة'),
        value: formatMoney(context, stats.totalDriverDue),
        icon: Icons.payments_outlined,
        color: const Color(0xff7755D6),
      ),
      // `total_ships_cost_all_of_them` is the gross COD value of every
      // unsettled shipment, not the driver's money. The Wallet calls it the
      // same thing, and explains it there.
      _DashboardStat(
        title: _copy(context, 'COD value', 'قيمة التحصيل'),
        value: formatMoney(context, stats.totalShipCost),
        icon: Icons.receipt_long_outlined,
        color: const Color(0xffF59E0B),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final count =
            constraints.maxWidth > 620
                ? 3
                : constraints.maxWidth < 330
                ? 1
                : 2;
        const gap = 12.0;
        final width = (constraints.maxWidth - gap * (count - 1)) / count;

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children:
              cards.map((card) => SizedBox(width: width, child: card)).toList(),
        );
      },
    );
  }
}

class _DashboardStat extends StatelessWidget {
  const _DashboardStat({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String title;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 118),
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon, color: color, size: 21),
          ),
          const SizedBox(height: 14),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              value,
              maxLines: 1,
              style: const TextStyle(
                color: Color(0xff0F172A),
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xff64748B),
              fontSize: 12,
              fontWeight: FontWeight.w700,
              height: 1.25,
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickActionsGrid extends StatelessWidget {
  const _QuickActionsGrid({required this.actions});

  final List<_DashboardAction> actions;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final count =
            constraints.maxWidth > 620
                ? 3
                : constraints.maxWidth < 330
                ? 1
                : 2;
        const gap = 12.0;
        final width = (constraints.maxWidth - gap * (count - 1)) / count;

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children:
              actions
                  .map(
                    (action) => SizedBox(
                      width: width,
                      child: _QuickActionTile(action: action),
                    ),
                  )
                  .toList(),
        );
      },
    );
  }
}

class _QuickActionTile extends StatelessWidget {
  const _QuickActionTile({required this.action});

  final _DashboardAction action;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: action.onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 96),
          child: Ink(
            padding: const EdgeInsets.all(14),
            decoration: _cardDecoration(),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: action.color.withValues(alpha: 0.11),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(action.icon, color: action.color, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        action.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xff0F172A),
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        action.subtitle,
                        maxLines: 1,
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ActiveShipmentPreview extends StatelessWidget {
  const _ActiveShipmentPreview({
    required this.isLoading,
    required this.shipments,
    required this.statusLabel,
    required this.onOpen,
  });

  final bool isLoading;
  final List<Shipment> shipments;
  final String Function(Shipment shipment) statusLabel;
  final ValueChanged<Shipment> onOpen;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return _InlineInfoCard(
        icon: Icons.sync_rounded,
        title: _copy(context, 'Loading shipments', 'جارٍ تحميل الشحنات'),
        message: _copy(
          context,
          'Please wait while we refresh your active work.',
          'يرجى الانتظار أثناء تحديث الشحنات النشطة.',
        ),
      );
    }

    if (shipments.isEmpty) {
      return _InlineInfoCard(
        icon: Icons.local_shipping_outlined,
        title: _copy(
          context,
          'No active shipment right now',
          'لا توجد شحنة نشطة حالياً',
        ),
        message: _copy(
          context,
          'Pull to refresh or check assigned shipments.',
          'اسحب للتحديث أو افتح الشحنات المسندة.',
        ),
      );
    }

    return Column(
      children:
          shipments
              .map(
                (shipment) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _ActiveShipmentCard(
                    shipment: shipment,
                    status: statusLabel(shipment),
                    onOpen: () => onOpen(shipment),
                  ),
                ),
              )
              .toList(),
    );
  }
}

class _ActiveShipmentCard extends StatelessWidget {
  const _ActiveShipmentCard({
    required this.shipment,
    required this.status,
    required this.onOpen,
  });

  final Shipment shipment;
  final String status;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final isStoreStage = driverShipmentIsPrePickup(shipment);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  shipment.policyNum.isEmpty
                      ? _copy(context, 'Shipment', 'شحنة')
                      : shipment.policyNum,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xff0F172A),
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: _statusColor(shipment).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  status.isEmpty ? _copy(context, 'Active', 'نشطة') : status,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _statusColor(shipment),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _ShipmentInfoLine(
            icon:
                isStoreStage
                    ? Icons.storefront_outlined
                    : Icons.person_outline_rounded,
            text:
                (isStoreStage ? shipment.nstore : shipment.recipientName)
                        .isEmpty
                    ? _copy(
                      context,
                      isStoreStage
                          ? 'Store not available'
                          : 'Recipient not available',
                      isStoreStage
                          ? 'اسم المتجر غير متوفر'
                          : 'اسم المستلم غير متوفر',
                    )
                    : isStoreStage
                    ? shipment.nstore
                    : shipment.recipientName,
          ),
          const SizedBox(height: 8),
          _ShipmentInfoLine(
            icon: Icons.place_outlined,
            text:
                (isStoreStage ? shipment.lclient : shipment.deliveryAddress)
                        .isEmpty
                    ? _copy(
                      context,
                      isStoreStage
                          ? 'Store address not available'
                          : 'Address not available',
                      isStoreStage
                          ? 'عنوان المتجر غير متوفر'
                          : 'العنوان غير متوفر',
                    )
                    : isStoreStage
                    ? shipment.lclient
                    : shipment.deliveryAddress,
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onOpen,
              icon: const Icon(Icons.open_in_new_rounded, size: 18),
              label: Text(_copy(context, 'View details', 'عرض التفاصيل')),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: BorderSide(
                  color: AppColors.primary.withValues(alpha: 0.3),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ShipmentInfoLine extends StatelessWidget {
  const _ShipmentInfoLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 17, color: const Color(0xff64748B)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xff475569),
              fontSize: 13,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }
}

class _DashboardErrorCard extends StatelessWidget {
  const _DashboardErrorCard({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xffFFF7ED),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xffFDBA74)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xffEA580C).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(
              Icons.wifi_off_rounded,
              color: Color(0xffEA580C),
              size: 21,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xff9A3412),
                fontSize: 13,
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: onRetry,
            child: Text(_copy(context, 'Retry', 'حاول مرة أخرى')),
          ),
        ],
      ),
    );
  }
}

class _InlineInfoCard extends StatelessWidget {
  const _InlineInfoCard({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: _cardDecoration(),
      child: Column(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: AppColors.primary, size: 24),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xff0F172A),
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xff64748B),
              fontSize: 12,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _DashboardLoadingGrid extends StatelessWidget {
  const _DashboardLoadingGrid();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final count = constraints.maxWidth < 330 ? 1 : 2;
        const gap = 12.0;
        final width = (constraints.maxWidth - gap * (count - 1)) / count;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: List.generate(
            count * 2,
            (index) => SizedBox(width: width, child: const _LoadingCard()),
          ),
        );
      },
    );
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 118,
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(
            width: 30,
            height: 30,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
          const Spacer(),
          _LoadingBar(width: 80),
          const SizedBox(height: 8),
          _LoadingBar(width: 120, opacity: 0.08),
        ],
      ),
    );
  }
}

class _LoadingBar extends StatelessWidget {
  const _LoadingBar({required this.width, this.opacity = 0.12});

  final double width;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 10,
      width: width,
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: opacity),
        borderRadius: BorderRadius.circular(999),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Color(0xff0F172A),
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: const TextStyle(
            color: Color(0xff64748B),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _SoftCircle extends StatelessWidget {
  const _SoftCircle({required this.size, required this.opacity});

  final double size;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withValues(alpha: opacity)),
      ),
    );
  }
}

class _DashboardAction {
  const _DashboardAction({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
}

BoxDecoration _cardDecoration() {
  return BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(18),
    border: Border.all(color: const Color(0xffE6EDF5)),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.045),
        blurRadius: 18,
        offset: const Offset(0, 8),
      ),
    ],
  );
}

Color _statusColor(Shipment shipment) {
  final normalized = shipment.statusNameEn.toLowerCase();
  if (normalized.contains('deliver') || normalized.contains('complete')) {
    return const Color(0xff16A06D);
  }
  if (normalized.contains('cancel') || normalized.contains('fail')) {
    return const Color(0xffEF4444);
  }
  if (normalized.contains('progress') ||
      normalized.contains('transit') ||
      normalized.contains('dispatch')) {
    return AppColors.primary;
  }
  return AppColors.primary;
}

/// `Localizations.localeOf`, not EasyLocalization's `context.locale`: the two
/// are separate states, and the provider notifies before syncing the second,
/// so these cards used to render one frame of the old language inside the new
/// direction.
String _copy(BuildContext context, String en, String ar) {
  return isArabicLocale(context) ? ar : en;
}
