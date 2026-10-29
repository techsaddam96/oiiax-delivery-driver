import 'package:blockatie/services/driver_action_service.dart';
import 'dart:async';
import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../firebase_options.dart';
import 'package:provider/provider.dart';

import '../models/shipment.dart';
import '../provider/bottom_nav.dart';
import '../provider/chat/driver_chat_conversations_provider.dart';
import '../provider/shipment.dart';
import '../services/auth_services.dart';
import '../services/driver_fcm_token_service.dart';
import '../utils/localization.dart';
import '../utils/nav.dart';
import '../services/user_session_state.dart';
import '../views/pages/chat/driver_chat_navigation.dart';
import '../views/pages/orders/order_details.dart';
import '../views/pages/settlements/driver_settlement_details_page.dart';
import 'notification_routes.dart';

class NotificationSystem {
  int countNotificationNumber = 0;
  int idCategories = -1;
  late FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();
  static final FirebaseMessaging _firebaseMessaging =
      FirebaseMessaging.instance;
  static bool _messageOpenHandlerRegistered = false;
  static bool _foregroundHandlerRegistered = false;
  static bool _tokenRefreshHandlerRegistered = false;
  static bool _tokenRegistrationInProgress = false;
  static bool _topicSubscriptionInProgress = false;
  static String? _topicsSubscribedForUserId;
  static String? _lastRegisteredTokenKey;
  static final Set<String> _handledNavigationTargets = {};
  static const int _maxHandledNavigationTargets = 100;

  /// How long a tap will wait for the Navigator on a cold start before giving
  /// up. Bounded, so a launch straight to Login cannot hold a tap forever.
  static const int _navigatorReadyAttempts = 40;
  static const Duration _navigatorReadyInterval = Duration(milliseconds: 100);

  // Bottom-nav destinations. Indices mirror CustomBottomNavBar's page list.
  static const int _shipmentsTabIndex = 1;
  static const int _hubTabIndex = 4;
  static const int _assignedShipmentsSubTab = 0;
  static const int _availableShipmentsSubTab = 1;
  static Future<void> Function()? onForegroundNotificationReceived;
  static const List<String> _driverGlobalTopics = [
    'allheros',
    'driver_all',
    'announcements',
    'shipment_updates',
    'payment_notifications',
    'driver_updates',
    'maintenance',
  ];

  Future<void> setupInteractedMessage() async {
    RemoteMessage? initMessage =
        await FirebaseMessaging.instance.getInitialMessage();
    if (initMessage != null) {
      handleMessage(initMessage);
    }
    if (!_messageOpenHandlerRegistered) {
      FirebaseMessaging.onMessageOpenedApp.listen(handleMessage);
      _messageOpenHandlerRegistered = true;
    }
  }

  void handleMessage(RemoteMessage message) {
    unawaited(navigator(data: message.data));
  }

  /// The one way anything outside this class opens a notification.
  ///
  /// The Notifications page used to route its own rows by looking for the word
  /// "shipment" in the type and pushing a details screen with a fabricated
  /// phone number — no typed resolution, no ownership read, no session check
  /// and no de-duplication. An inbox tap and a push tap are the same act, so
  /// they now take the same path.
  static Future<void> openDriverNotificationPayload(Map<String, dynamic> data) {
    return NotificationSystem().navigator(data: data);
  }

  Future selectNotification(Map<String, dynamic>? payload) async {
    if (payload == null) return;
    await navigator(data: payload);
  }

  void showNotification({
    required String title,
    required String body,
    required idNotification,
    required Map<String, dynamic> data,
  }) async {
    var android = const AndroidNotificationDetails(
      'Hero',
      'Hero Notifications',
      icon: '@mipmap/notification_logo',
      colorized: true,
      color: Color(0xff0C63FF),
      playSound: true,
      importance: Importance.high,
      priority: Priority.high,
    );

    var ios = const DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    var platform = NotificationDetails(android: android, iOS: ios);

    flutterLocalNotificationsPlugin.show(
      idNotification,
      title,
      body,
      platform,
      payload: jsonEncode(data),
    );
  }

  Future<void> onBackgroundMessage(RemoteMessage message) async {
    await Firebase.initializeApp();
    await navigator(data: message.data);
  }

  // Subscribe to topic
  static Future<bool> subscribeToTopic(String topic) async {
    try {
      await _firebaseMessaging.subscribeToTopic(topic);
      debugPrint('Notification topic subscription completed.');
      return true;
    } catch (e) {
      debugPrint('Notification topic subscription failed: ${e.runtimeType}');
      return false;
    }
  }

  //
  // void onMessage() async {
  //   FirebaseMessaging.onMessage.listen((event) {
  //     log('EventData=> ${event.data}');
  //
  //     showNotification(
  //         title: event.notification!.title.toString(),
  //         body: event.notification!.body.toString(),
  //         data: event.data,
  //         idNotification: countNotificationNumber);
  //     countNotificationNumber++;
  //   });
  //   //FirebaseMessaging.onBackgroundMessage(onBackgroundMessage);
  // }

  void onMessage() async {
    if (_foregroundHandlerRegistered) return;
    _foregroundHandlerRegistered = true;
    FirebaseMessaging.onMessage.listen((event) {
      final notification = event.notification;
      final title =
          notification?.title ?? event.data['title']?.toString() ?? '';
      final body = notification?.body ?? event.data['body']?.toString() ?? '';

      showNotification(
        title: title,
        body: body,
        data: event.data,
        idNotification: countNotificationNumber,
      );

      countNotificationNumber++;
      final foregroundCallback = onForegroundNotificationReceived;
      if (foregroundCallback != null) {
        unawaited(foregroundCallback());
      }

      // A chat signal while the app is open never navigates on its own. It
      // only tells the chat state to re-read the server.
      final target = resolveDriverNotificationTarget(event.data);
      if (target != null &&
          target.destination ==
              DriverNotificationDestination.chatConversation) {
        unawaited(_handleForegroundChatSignal(target.conversationId!));
      }
    });
    //FirebaseMessaging.onBackgroundMessage(onBackgroundMessage);
  }

  Future<void> notificationReady() async {
    await permissionNotification();

    var android = const AndroidInitializationSettings('@mipmap/ic_launcher');
    var ios = const DarwinInitializationSettings(
      requestSoundPermission: true,
      defaultPresentAlert: true,
      defaultPresentBadge: true,
      defaultPresentSound: true,
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestCriticalPermission: true,
    );
    var initSetting = InitializationSettings(android: android, iOS: ios);
    flutterLocalNotificationsPlugin.initialize(
      initSetting,
      onDidReceiveNotificationResponse: (details) {
        //setupInteractedMessage();
        //onMessage();
        final payload = details.payload;
        if (payload == null || payload.isEmpty) return;
        final decodedPayload = jsonDecode(payload);
        if (decodedPayload is Map<String, dynamic>) {
          selectNotification(decodedPayload);
        }
      },
    );
    setupInteractedMessage();
    onMessage();
    await registerDriverFcmTokenAfterLogin(requestPermission: false);
  }

  /// Single entry point for every notification tap.
  ///
  /// Foreground (local-notification tap), background (`onMessageOpenedApp`) and
  /// terminated (`getInitialMessage`) all funnel here, so the three flows route
  /// identically. The payload only selects a destination; the screen then loads
  /// its own data from the backend.
  Future<void> navigator({required Map<String, dynamic> data}) async {
    final target = resolveDriverNotificationTarget(data);
    if (target == null) return; // unknown type or missing/invalid id

    final session = await AuthService.getSessionSnapshot();
    if (!session.isAuthenticated) return;

    // Capture the session that owns this tap. If the account changes while the
    // destination is being prepared, the navigation is abandoned so a
    // notification for Driver A can never open a screen for Driver B.
    final generation = UserSessionState.generation;
    final driverId = session.driverId;

    // Driven by its own bounded poll rather than a post-frame callback: one
    // registered from an async gap waits for the next frame, and an idle app
    // produces none, which would strand the tap.
    await _navigateWhenReady(target, generation, driverId);
  }

  /// Waits, briefly and boundedly, for the Navigator to exist.
  ///
  /// A terminated-app launch delivers its notification before the widget tree
  /// is built, so the first frame often has no Navigator. Dropping the tap
  /// there loses the notification entirely; polling for a few seconds lets the
  /// app finish starting. The de-duplication key is claimed only once the
  /// Navigator is real, so a tap that never navigated cannot suppress itself.
  Future<void> _navigateWhenReady(
    DriverNotificationTarget target,
    int generation,
    String? driverId,
  ) async {
    for (var attempt = 0; attempt < _navigatorReadyAttempts; attempt++) {
      // A logout or account switch while the app was starting ends this tap.
      if (!UserSessionState.isCurrent(generation)) return;
      if (Nav.key.currentState != null) break;
      await Future<void>.delayed(_navigatorReadyInterval);
    }

    if (Nav.key.currentState == null) return;
    if (!UserSessionState.isCurrent(generation)) return;
    if (!_registerNavigation('${target.dedupeKey}:$driverId')) return;

    await _openTarget(target, generation);
  }

  /// Foreground chat signal: re-read the badge, and let an open thread fetch
  /// newer messages through its own cursor. Nothing from the payload is
  /// written into provider state.
  Future<void> _handleForegroundChatSignal(int conversationId) async {
    try {
      final context = Nav.key.currentState?.context;
      if (context == null) return;
      final conversations = Provider.of<DriverChatConversationsProvider>(
        context,
        listen: false,
      );
      await conversations.handleChatSignal(conversationId);
    } catch (e) {
      debugPrint('Chat signal handling failed: ${e.runtimeType}');
    }
  }

  /// Opens the destination, loading current data from the backend first where
  /// the screen needs it.
  Future<void> _openTarget(
    DriverNotificationTarget target,
    int generation,
  ) async {
    try {
      switch (target.destination) {
        case DriverNotificationDestination.settlementDetails:
          // The page fetches the settlement itself from settlement_id.
          Nav.to(
            DriverSettlementDetailsPage(settlementId: target.settlementId!),
            withNav: true,
            navIndex: _hubTabIndex,
          );

        case DriverNotificationDestination.shipmentDetails:
          await _openShipmentDetails(target, generation);

        case DriverNotificationDestination.availableShipments:
          _openShipmentsTab(_availableShipmentsSubTab);

        case DriverNotificationDestination.chatConversation:
          await _openChatConversation(target, generation);
      }
    } catch (e) {
      debugPrint('Notification navigation failed: ${e.runtimeType}');
    }
  }

  /// Re-reads the driver's shipments from the backend, then opens the matching
  /// one. The payload is never rendered directly.
  Future<void> _openShipmentDetails(
    DriverNotificationTarget target,
    int generation,
  ) async {
    final shipmentId = target.shipmentId!;
    final context = Nav.key.currentState?.context;
    if (context == null) return;

    final shipmentProvider = Provider.of<ShipmentProvider>(
      context,
      listen: false,
    );

    try {
      await shipmentProvider.getAllShipments(force: true);
    } catch (e) {
      debugPrint('Notification shipment refresh failed: ${e.runtimeType}');
    }

    // The account may have changed while the refresh was in flight.
    if (!UserSessionState.isCurrent(generation)) return;
    if (Nav.key.currentState == null) return;

    Shipment? shipment = await DriverActionService.read(
      context,
    ).fetch(shipmentId);
    if (!UserSessionState.isCurrent(generation)) return;

    if (shipment == null) {
      // Reassigned, closed or not visible to this driver any more. Land on the
      // shipments list rather than an empty or stale detail screen.
      _openShipmentsTab(_assignedShipmentsSubTab);
      return;
    }

    if (!context.mounted) return;
    context.read<BottomNavProvider>().setShipmentsTab(
      shipment.deliveryTypeId == 1
          ? 0
          : shipment.deliveryTypeId == 2
          ? 1
          : 2,
    );
    Nav.to(
      OrderDetailPage(
        shipment: shipment,
        shipmentId: shipment.id,
        phoneCustomer: shipment.phclient,
        deliveryAdd: shipment.lclient,
        storeAdd: shipment.nstore,
        orderDate: shipment.createdAt,
      ),
      withNav: true,
      navIndex: _shipmentsTabIndex,
    );
  }

  /// Opens one chat thread, but only after the server confirms it is this
  /// driver's to open.
  ///
  /// Nothing in the payload is treated as proof: `conversation_id` names a
  /// resource, and the Chat API decides. A conversation belonging to another
  /// driver, or one that no longer exists, answers the same way and no
  /// navigation happens. `shipment_id` and `message_id` never take part.
  Future<void> _openChatConversation(
    DriverNotificationTarget target,
    int generation,
  ) async {
    final conversationId = target.conversationId!;
    final context = Nav.key.currentState?.context;
    if (context == null) return;

    final conversations = Provider.of<DriverChatConversationsProvider>(
      context,
      listen: false,
    );

    // That thread is already on screen. Pushing a second copy of it would be
    // the duplicate-route bug; refetching through its own cursor is what the
    // driver actually wants.
    if (conversations.openConversationId == conversationId) {
      await conversations.handleChatSignal(conversationId);
      return;
    }

    final allowed = await conversations.canOpenNotifiedConversation(
      conversationId,
    );
    // The account may have changed while the probe was in flight, so a late
    // answer for the previous driver cannot open anything here.
    if (!allowed || !UserSessionState.isCurrent(generation)) return;

    final navigator = Nav.key.currentState;
    if (navigator == null) return;

    // Taken before navigating, because a push Future only completes when the
    // route is popped — the badge must be right while the thread is open, not
    // only after the driver leaves it.
    await conversations.refreshUnreadCount();
    if (!UserSessionState.isCurrent(generation)) return;

    // Whatever the list already knows fills in the header; the page loads the
    // thread itself either way.
    final known =
        conversations.conversations
            .where((c) => c.conversationId == conversationId)
            .firstOrNull;

    await DriverChatNavigation.openConversationById(
      navigator,
      conversationId: conversationId,
      title: known?.title ?? '',
      shipmentId: known?.shipmentId,
      policyNum: known?.policyNum,
    );

    if (!UserSessionState.isCurrent(generation)) return;
    // Back from the thread, which marked what it showed as read.
    await conversations.refreshUnreadCount();
  }

  void _openShipmentsTab(int subTab) {
    final context = Nav.key.currentState?.context;
    if (context == null) return;

    final navProvider = Provider.of<BottomNavProvider>(context, listen: false);
    navProvider.setIndex(_shipmentsTabIndex);
    // Legacy offer notifications belong to Instant; assignment details resolve by id.
    navProvider.setShipmentsTab(0, offers: subTab == _availableShipmentsSubTab);
  }

  /// Records a tap and reports whether it is the first time this target was
  /// seen. FCM can deliver the same message more than once, and a tap can be
  /// replayed by `getInitialMessage` right after `onMessageOpenedApp`.
  static bool _registerNavigation(String key) {
    if (!_handledNavigationTargets.add(key)) return false;

    // Bounded so a long-lived session cannot grow this without limit.
    if (_handledNavigationTargets.length > _maxHandledNavigationTargets) {
      _handledNavigationTargets.remove(_handledNavigationTargets.first);
    }
    return true;
  }

  Future<bool> permissionNotification() async {
    // if (!await Permission.notification.status.isPermanentlyDenied) {
    //   NotificationSettings notificationSettings = await FirebaseMessaging
    //       .instance
    //       .requestPermission(alert: true, badge: true, sound: true);
    //   AuthorizationStatus authorizationStatus =
    //       notificationSettings.authorizationStatus;
    //   if (authorizationStatus == AuthorizationStatus.denied) {
    //     await ShApp().notificationActive(muteNotification: true);
    //     return false;
    //   } else {
    //     await ShApp().notificationActive(muteNotification: false);
    //     return true;
    //   }
    // } else {
    //   await ShApp().notificationActive(muteNotification: true);
    //   showSnackBar(
    //       context: navigatorKey.currentState!.context,
    //       message: 'فعل الاشعارات من أذونات التطبيق لتتمكن من استلام اشعاراتك',
    //       visibleMessage: false);
    //   return false;
    // }
    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    // One visible alert per push, on both platforms. iOS would otherwise show
    // the system banner *and* the local notification raised in `onMessage`;
    // Android never auto-presents a foreground message, so the local one is
    // the single path there. Badge and sound stay with the system.
    await FirebaseMessaging.instance
        .setForegroundNotificationPresentationOptions(
          sound: true,
          badge: true,
          alert: false,
        );
    return true;
  }

  Future<void> registerDriverFcmTokenAfterLogin({
    bool requestPermission = true,
  }) async {
    _registerTokenRefreshListener();

    if (_tokenRegistrationInProgress) return;
    _tokenRegistrationInProgress = true;

    try {
      final registrationGeneration = UserSessionState.generation;
      final session = await AuthService.getSessionSnapshot();
      if (!session.isAuthenticated) {
        debugPrint('FCM token registration skipped: missing session.');
        return;
      }

      if (requestPermission) {
        await permissionNotification();
      }

      final token = await _firebaseMessaging.getToken();
      if (token == null || token.trim().isEmpty) {
        debugPrint('FCM token registration skipped: token unavailable.');
        return;
      }

      // The app's own canonical locale, already normalised to 'ar' or 'en'.
      final language = AppLocalizations.currentLocale.languageCode;
      final tokenKey = _tokenKey(session.driverId!, token, language);
      if (_lastRegisteredTokenKey == tokenKey) {
        return;
      }

      final registration = await DriverFcmTokenService.updateDriverFcmToken(
        driverId: session.driverId!,
        apiKey: session.apiKey!,
        fcmToken: token,
        language: language,
      );
      if (registration != null &&
          !registration.isCached &&
          registration.binding != null) {
        final saved = await AuthService.saveFcmBinding(
          registration.binding!,
          expectedGeneration: registrationGeneration,
          apiKey: session.apiKey!,
          driverId: session.driverId!,
        );
        if (saved) {
          _lastRegisteredTokenKey = tokenKey;
        }
      } else if (registration?.isCached == true &&
          UserSessionState.isCurrent(registrationGeneration)) {
        _lastRegisteredTokenKey = tokenKey;
      }
    } catch (e) {
      debugPrint('FCM token registration failed: ${e.runtimeType}');
    } finally {
      _tokenRegistrationInProgress = false;
    }
  }

  /// Tells the server which language this driver now reads.
  ///
  /// Called when the language is switched in-app: waiting for the FCM token
  /// itself to change would leave every push in the old language until the
  /// next reinstall. Registration is the only endpoint that carries the
  /// preference, so the same authenticated call is reused — token ownership
  /// and its transactional transfer are untouched. With no session or no
  /// token yet, the preference is simply picked up by the next registration.
  static Future<void> updateDriverNotificationLanguage() async {
    try {
      final session = await AuthService.getSessionSnapshot();
      if (!session.isAuthenticated) return;
      await NotificationSystem().registerDriverFcmTokenAfterLogin(
        requestPermission: false,
      );
    } catch (e) {
      debugPrint(
        'Driver notification language update failed: ${e.runtimeType}',
      );
    }
  }

  static void _registerTokenRefreshListener() {
    if (_tokenRefreshHandlerRegistered) return;
    _tokenRefreshHandlerRegistered = true;

    _firebaseMessaging.onTokenRefresh.listen((token) async {
      if (token.trim().isEmpty) {
        debugPrint('FCM token refresh skipped: token unavailable.');
        return;
      }

      final session = await AuthService.getSessionSnapshot();
      if (!session.isAuthenticated) {
        debugPrint('FCM token refresh skipped: missing session.');
        return;
      }

      try {
        final registrationGeneration = UserSessionState.generation;
        final language = AppLocalizations.currentLocale.languageCode;
        final registration = await DriverFcmTokenService.updateDriverFcmToken(
          driverId: session.driverId!,
          apiKey: session.apiKey!,
          fcmToken: token,
          language: language,
        );
        if (registration != null &&
            !registration.isCached &&
            registration.binding != null &&
            await AuthService.saveFcmBinding(
              registration.binding!,
              expectedGeneration: registrationGeneration,
              apiKey: session.apiKey!,
              driverId: session.driverId!,
            )) {
          _lastRegisteredTokenKey = _tokenKey(
            session.driverId!,
            token,
            language,
          );
        }
      } catch (e) {
        debugPrint('FCM token refresh failed: ${e.runtimeType}');
      }
    });
  }

  Future<void> subscribeDriverTopics({
    bool ensureTokenRegistered = true,
  }) async {
    if (_topicSubscriptionInProgress) return;

    try {
      final subscriptionGeneration = UserSessionState.generation;
      final userId = await AuthService.getuserId();
      if (userId == null) {
        debugPrint('Cannot subscribe to notification topics: missing session.');
        return;
      }

      final userKey = userId.toString();
      if (_topicsSubscribedForUserId == userKey) return;

      _topicSubscriptionInProgress = true;
      debugPrint('Starting driver notification topic subscription.');

      if (ensureTokenRegistered) {
        await registerDriverFcmTokenAfterLogin(requestPermission: false);
      }

      if (!UserSessionState.isCurrent(subscriptionGeneration)) return;

      final topics = <String>{..._driverGlobalTopics, 'hero_$userId'};

      var successCount = 0;
      for (final topic in topics) {
        if (!UserSessionState.isCurrent(subscriptionGeneration)) return;
        final subscribed = await subscribeToTopic(topic);
        if (subscribed) successCount++;
      }

      if (successCount > 0) {
        _topicsSubscribedForUserId = userKey;
      }
      debugPrint('Driver notification topic subscription completed.');
    } catch (e) {
      debugPrint(
        'Notification topic subscription process failed: ${e.runtimeType}',
      );
    } finally {
      _topicSubscriptionInProgress = false;
    }
  }

  Future<void> subscribeToUserTopics() async {
    await subscribeDriverTopics();
  }

  /// Releases this device's FCM token from the driver, server-side.
  ///
  /// Starts token capture before local logout invalidates memory. The caller
  /// intentionally does not await this Future on the Login navigation path.
  static Future<String?> captureCurrentFcmToken() async {
    String? token;
    try {
      token = await _firebaseMessaging.getToken();
    } catch (e) {
      debugPrint('FCM token read failed during logout: ${e.runtimeType}');
    }
    return token;
  }

  Future<void> unsubscribeFromUserTopics() async {
    final userId = await AuthService.getuserId();
    if (userId == null) {
      debugPrint(
        'Cannot unsubscribe from notification topics: missing session.',
      );
      return;
    }
    await unsubscribeDriverTopics(
      userId,
      expectedGeneration: UserSessionState.generation,
    );
    _topicsSubscribedForUserId = null;
  }

  /// Removes this device from [driverId]'s topics.
  ///
  /// Used by the logout teardown after the credentials are already erased, so
  /// it takes the id instead of reading the session, and it leaves the
  /// subscription bookkeeping alone: by the time a slow FCM call returns, a new
  /// driver may have signed in and subscribed. FCM can wait indefinitely for
  /// connectivity, so callers bound it with a timeout and never await it on the
  /// way to Login. Topic operations are queued by FCM in request order, so a
  /// new driver's later subscription still wins over this cleanup.
  Future<void> unsubscribeDriverTopics(
    String driverId, {
    required int expectedGeneration,
  }) async {
    try {
      debugPrint('Starting driver notification topic unsubscription.');

      final topics = <String>{..._driverGlobalTopics, 'hero_$driverId'};

      for (final topic in topics) {
        // No new operation is started once another account boundary exists.
        // Calls already started before a rapid re-login are ordered by FCM
        // before that login's subscriptions, so they cannot remove the new
        // session's later subscription.
        if (!UserSessionState.isCurrent(expectedGeneration)) return;
        await _firebaseMessaging.unsubscribeFromTopic(topic);
      }
      debugPrint('Driver notification topic unsubscription completed.');
    } catch (e) {
      debugPrint(
        'Notification topic unsubscription process failed: ${e.runtimeType}',
      );
    }
  }

  static void resetDriverSessionState() {
    _topicsSubscribedForUserId = null;
    _lastRegisteredTokenKey = null;
    _tokenRegistrationInProgress = false;
    _topicSubscriptionInProgress = false;
    // Taps are de-duplicated per driver; a new session starts with a clean slate
    // so the next driver's notifications are never suppressed.
    _handledNavigationTargets.clear();
  }

  static String _tokenKey(String driverId, String token, String language) {
    return '$driverId:${token.hashCode}:$language';
  }
}

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  debugPrint('Handling a background notification message.');
}
