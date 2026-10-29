// // import 'package:blockatie/provider/bottom_nav.dart';
// // import 'package:blockatie/provider/driver_location.dart';
// // import 'package:blockatie/provider/home.dart';
// // import 'package:blockatie/provider/localization.dart';
// // import 'package:blockatie/provider/login.dart';
// // import 'package:blockatie/utils/nav.dart';
// // import 'package:blockatie/utils/size_config.dart';
// // import 'package:flutter/material.dart';
// // import 'package:provider/provider.dart';
//
// // import 'provider/filter.dart';
// // import 'provider/header.dart';
// // import 'provider/notification.dart';
// // import 'provider/orders.dart';
// // import 'provider/profile.dart';
// // import 'provider/register.dart';
// // import 'provider/shipment.dart';
// // import 'provider/shipment_instsnt.dart';
// // import 'provider/support.dart';
// // import 'provider/time.dart';
// // import 'provider/wallet.dart';
// // import 'provider/withdrawal.dart';
// // import 'utils/theme.dart';
// // import 'views/pages/splash/splash.dart';
//
// // import 'package:flutter/material.dart';
// // import 'package:easy_localization/easy_localization.dart';
// // import 'package:provider/provider.dart';
//
// // void main() async {
// //   WidgetsFlutterBinding.ensureInitialized();
// //   await EasyLocalization.ensureInitialized();
//
// //   runApp(
// //     EasyLocalization(
// //       supportedLocales: [Locale('en'), Locale('ar')],
// //       path: 'assets/translation', // <- path to your JSON files
// //       fallbackLocale: Locale('en'),
// //       child: MultiProvider(
// //         providers: [
// //           ChangeNotifierProvider(create: (_) => LocaleProvider()),
// //         ],
// //         child: MyApp(),
// //       ),
// //     ),
// //   );
// // }
//
// // class MyApp extends StatelessWidget {
// //   const MyApp({super.key});
//
// //   // This widget is the root of your application.
// //   @override
// //   Widget build(BuildContext context) {
// //     return MultiProvider(
// //       providers: [
// //         ChangeNotifierProvider(create: (_) => LoginProvider()),
// //         ChangeNotifierProvider(create: (_) => BottomNavProvider()),
// //         ChangeNotifierProvider(create: (_) => HomeProvider()),
// //         ChangeNotifierProvider(create: (_) => OrderStatusProvider()),
// //         ChangeNotifierProvider(create: (_) => ShipmentProvider()),
// //         ChangeNotifierProvider(create: (_) => FilterProvider()),
// //         ChangeNotifierProvider(create: (_) => TimeProvider()),
// //         ChangeNotifierProvider(create: (_) => WithdrawalProvider()),
// //         ChangeNotifierProvider(create: (_) => ProfileProvider()),
// //         ChangeNotifierProvider(create: (_) => Headerprovider()),
// //         ChangeNotifierProvider(create: (_) => WalletProvider()),
// //         ChangeNotifierProvider(create: (_) => RegisterProvider()),
// //         ChangeNotifierProvider(create: (_) => NotificationProvider()),
// //         ChangeNotifierProvider(create: (_) => ShipmentInstantprovider()),
// //         ChangeNotifierProvider(create: (_) => SupportProvider()),
// //         ChangeNotifierProvider(create: (_) => DriverLocationProvider()),
// //         ChangeNotifierProvider(create: (_) => LocaleProvider()),
// //       ],
// //       child: LayoutBuilder(
// //         builder: (context, constraints) {
// //           return OrientationBuilder(
// //             builder: (context, orientation) {
// //               SizeConfig().init(constraints, orientation);
// //               return MaterialApp(
//
// //                 navigatorKey: Nav.key,
// //                 debugShowCheckedModeBanner: false,
// //                 theme: AppTheme.getPrimaryTheme(),
// //                 title: 'BLOCKATIE',
// //                 home: const SplashPage(),
// //               );
// //               // home: const TestMapPage());
// //             },
// //           );
// //         },
// //       ),
// //     );
// //   }
// // }
//
// import 'package:blockatie/provider/bottom_nav.dart';
// import 'package:blockatie/provider/driver_location.dart';
// import 'package:blockatie/provider/home.dart';
// import 'package:blockatie/provider/localization.dart';
// import 'package:blockatie/provider/login.dart';
// import 'package:blockatie/provider/filter.dart';
// import 'package:blockatie/provider/header.dart';
// import 'package:blockatie/provider/notification.dart';
// import 'package:blockatie/provider/orders.dart';
// import 'package:blockatie/provider/profile.dart';
// import 'package:blockatie/provider/register.dart';
// import 'package:blockatie/provider/shipment.dart';
// import 'package:blockatie/provider/shipment_instsnt.dart';
// import 'package:blockatie/provider/support.dart';
// import 'package:blockatie/provider/time.dart';
// import 'package:blockatie/provider/wallet.dart';
// import 'package:blockatie/provider/withdrawal.dart';
// import 'package:blockatie/utils/nav.dart';
// import 'package:blockatie/utils/size_config.dart';
// import 'package:blockatie/utils/theme.dart';
// import 'package:blockatie/views/pages/splash/splash.dart';
//
// import 'package:flutter/material.dart';
// import 'package:provider/provider.dart';
// import 'package:easy_localization/easy_localization.dart';
//
// void main() async {
//   WidgetsFlutterBinding.ensureInitialized();
//   await EasyLocalization.ensureInitialized();
//
//   runApp(
//     EasyLocalization(
//       supportedLocales: [Locale('ar'), Locale('en')],
//       path: 'assets/translation', // Your JSON path
//       fallbackLocale: Locale('en'),
//       child: MultiProvider(
//         providers: [
//           // All your providers here
//           ChangeNotifierProvider(create: (_) => LoginProvider()),
//           ChangeNotifierProvider(create: (_) => BottomNavProvider()),
//           ChangeNotifierProvider(create: (_) => HomeProvider()),
//           ChangeNotifierProvider(create: (_) => OrderStatusProvider()),
//           ChangeNotifierProvider(create: (_) => ShipmentProvider()),
//           ChangeNotifierProvider(create: (_) => FilterProvider()),
//           ChangeNotifierProvider(create: (_) => TimeProvider()),
//           ChangeNotifierProvider(create: (_) => WithdrawalProvider()),
//           ChangeNotifierProvider(create: (_) => ProfileProvider()),
//           ChangeNotifierProvider(create: (_) => Headerprovider()),
//           ChangeNotifierProvider(create: (_) => WalletProvider()),
//           ChangeNotifierProvider(create: (_) => RegisterProvider()),
//           ChangeNotifierProvider(create: (_) => NotificationProvider()),
//           ChangeNotifierProvider(create: (_) => ShipmentInstantprovider()),
//           ChangeNotifierProvider(create: (_) => SupportProvider()),
//           ChangeNotifierProvider(create: (_) => DriverLocationProvider()),
//           ChangeNotifierProvider(create: (_) => LocaleProvider()),
//         ],
//         child: const MyApp(),
//       ),
//     ),
//   );
// }
//
// class MyApp extends StatelessWidget {
//   const MyApp({super.key});
//
//   @override
//   Widget build(BuildContext context) {
//     return LayoutBuilder(
//       builder: (context, constraints) {
//         return OrientationBuilder(
//           builder: (context, orientation) {
//             SizeConfig().init(constraints, orientation);
//
//             return MaterialApp(
//               debugShowCheckedModeBanner: false,
//               title: 'BLOCKATIE',
//               theme: AppTheme.getPrimaryTheme(),
//               navigatorKey: Nav.key,
//
//               // ✅ Localization settings
//               locale: context.locale,
//               supportedLocales: context.supportedLocales,
//               localizationsDelegates: context.localizationDelegates,
//
//               home: const SplashPage(),
//             );
//           },
//         );
//       },
//     );
//   }
// }

import 'package:blockatie/provider/blockatie_pro.dart';
import 'package:blockatie/provider/bottom_nav.dart';
import 'package:blockatie/provider/chat/driver_chat_conversations_provider.dart';
import 'package:blockatie/provider/chat/driver_chat_launcher_provider.dart';
import 'package:blockatie/provider/driver_location.dart';
import 'package:blockatie/provider/driver_shipment_sections.dart';
import 'package:blockatie/provider/driver_work_session.dart';
import 'package:blockatie/provider/driver_tours.dart';
import 'package:blockatie/provider/filter.dart';
import 'package:blockatie/provider/header.dart';
import 'package:blockatie/provider/home.dart';
import 'package:blockatie/provider/localization.dart';
import 'package:blockatie/provider/login.dart';
import 'package:blockatie/provider/notification.dart';
import 'package:blockatie/provider/order_location.dart';
import 'package:blockatie/provider/operational_readiness.dart';
import 'package:blockatie/provider/orders.dart';
import 'package:blockatie/provider/profile.dart';
import 'package:blockatie/provider/register.dart';
import 'package:blockatie/provider/requests_provider.dart';
import 'package:blockatie/provider/shipment.dart';
import 'package:blockatie/provider/shipment_flow_config.dart';
import 'package:blockatie/services/auth_services.dart';
import 'package:blockatie/provider/shipment_instsnt.dart';
import 'package:blockatie/provider/support.dart';
import 'package:blockatie/provider/time.dart';
import 'package:blockatie/provider/wallet.dart';
import 'package:blockatie/provider/withdrawal.dart';
import 'package:blockatie/provider/settlements/driver_settlement_details_provider.dart';
import 'package:blockatie/provider/settlements/driver_settlements_provider.dart';
import 'package:blockatie/services/driver_chat_service.dart';
import 'package:blockatie/utils/driver_chat_launcher_observer.dart';
import 'package:blockatie/utils/localization.dart';
import 'package:blockatie/utils/nav.dart';
import 'package:blockatie/utils/size_config.dart';
import 'package:blockatie/utils/theme.dart';
import 'package:blockatie/views/pages/connectivity/connection_alert_screen.dart';
import 'package:blockatie/views/widgets/driver_chat_bubble.dart';
import 'package:blockatie/views/pages/splash/splash.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:overlay_support/overlay_support.dart';
import 'package:provider/provider.dart';
import 'dart:ui' as ui;

import 'constants/notification_system.dart';
import 'firebase_options.dart';

final GlobalKey<ScaffoldMessengerState> rootScaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // In this order: initialize() discards easy_localization's legacy saved
  // locale, which ensureInitialized() would otherwise read and let override
  // the startLocale below.
  await AppLocalizations.initialize();
  await EasyLocalization.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  runApp(
    EasyLocalization(
      supportedLocales: const [Locale('ar'), Locale('en')],
      path: 'assets/translation',
      fallbackLocale: const Locale('en'),
      // EasyLocalization starts from, and never independently persists, the
      // language LocaleProvider owns. Left to itself it keeps a second saved
      // locale of its own and falls back to the device locale, which is how
      // tr() strings could come out Arabic inside an English LTR layout.
      startLocale: AppLocalizations.currentLocale,
      saveLocale: false,
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => LoginProvider()),
          ChangeNotifierProvider(create: (_) => BottomNavProvider()),
          ChangeNotifierProvider(create: (_) => HomeProvider()),
          ChangeNotifierProvider(create: (_) => OrderStatusProvider()),
          ChangeNotifierProvider(create: (_) => ShipmentProvider()),
          ChangeNotifierProvider(
            create: (_) => DriverShipmentSectionsProvider(),
          ),
          ChangeNotifierProvider(create: (_) => FilterProvider()),
          ChangeNotifierProvider(create: (_) => TimeProvider()),
          ChangeNotifierProvider(create: (_) => WithdrawalProvider()),
          ChangeNotifierProvider(create: (_) => ProfileProvider()),
          ChangeNotifierProvider(create: (_) => Headerprovider()),
          ChangeNotifierProvider(create: (_) => WalletProvider()),
          ChangeNotifierProvider(create: (_) => RegisterProvider()),
          ChangeNotifierProvider(create: (_) => NotificationProvider()),
          ChangeNotifierProvider(create: (_) => ShipmentFlowConfigProvider()),
          ChangeNotifierProvider(create: (_) => ShipmentInstantprovider()),
          ChangeNotifierProvider(create: (_) => SupportProvider()),
          ChangeNotifierProvider(create: (_) => DriverLocationProvider()),
          ChangeNotifierProvider(create: (_) => DriverWorkSessionProvider()),
          // Driver-owned tour state is isolated from shipment status state.
          // The provider clears itself at the same session boundary as the
          // rest of the authenticated Driver App.
          ChangeNotifierProvider(create: (_) => DriverToursProvider()),
          ChangeNotifierProvider(create: (_) => OrderLocationProvider()),
          ChangeNotifierProvider(create: (_) => OperationalReadinessProvider()),
          ChangeNotifierProvider(create: (_) => LocaleProvider()),
          ChangeNotifierProvider(create: (_) => BlockatiePro()),
          ChangeNotifierProvider(create: (_) => RequestsProvider()),
          ChangeNotifierProvider(create: (_) => DriverSettlementsProvider()),
          ChangeNotifierProvider(
            create: (_) => DriverSettlementDetailsProvider(),
          ),
          // Registered once, app-wide: the conversation list and the global
          // unread badge have a single owner, so the chat screen and the
          // future floating bubble read the same numbers. Lazy, so nothing is
          // requested until chat is actually opened.
          ChangeNotifierProvider(
            create:
                (_) => DriverChatConversationsProvider(
                  repository: DriverChatService(),
                ),
          ),
          // Visibility state for the one floating chat launcher. Eager, because
          // the navigation observer needs it before any screen reads it.
          ChangeNotifierProvider(
            create: (_) => DriverChatLauncherProvider(),
            lazy: false,
          ),
        ],
        child: const MyApp(),
      ),
    ),
  );
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  /// One observer for the life of the app. It is built here rather than inline
  /// below because the MaterialApp sits inside layout, orientation and locale
  /// builders — a new observer on each of those rebuilds would forget the route
  /// stack it tracks, and the launcher would reappear over a chat screen.
  late final DriverChatLauncherObserver _launcherObserver =
      DriverChatLauncherObserver(context.read<DriverChatLauncherProvider>());

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshShipmentFlowConfig();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshShipmentFlowConfig();
    }
  }

  Future<void> _refreshShipmentFlowConfig() async {
    try {
      final session = await AuthService.getSessionSnapshot();
      if (!mounted ||
          (session.apiKey?.isEmpty ?? true) ||
          (session.driverId?.isEmpty ?? true)) {
        return;
      }
      final shipmentFlowConfig =
          context.read<ShipmentFlowConfigProvider>();
      await shipmentFlowConfig.restoreCachedScheduledPolicy(session.driverId!);
      if (!mounted) return;
      await shipmentFlowConfig.fetch(force: true);
    } catch (_) {
      // The provider exposes an explicit unavailable state. Startup and resume
      // must never turn a transient config read failure into a logout.
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return OrientationBuilder(
          builder: (context, orientation) {
            SizeConfig().init(constraints, orientation);
            return Consumer<LocaleProvider>(
              builder: (context, value, child) {
                return OverlaySupport.global(
                  child: Stack(
                    alignment: AlignmentDirectional.bottomStart,
                    textDirection: ui.TextDirection.ltr,
                    children: [
                      MaterialApp(
                        debugShowCheckedModeBanner: false,
                        title: 'OIIAX Driver',
                        theme: AppTheme.getPrimaryTheme(),
                        navigatorKey: Nav.key,
                        // App-wide messages that are emitted outside a page
                        // still have a stable messenger target.
                        scaffoldMessengerKey: rootScaffoldMessengerKey,
                        navigatorObservers: [_launcherObserver],

                        // ✅ Localization settings
                        supportedLocales: AppLocalizations.supportedLocales,
                        locale: value.getCurrentLocale(),
                        localizationsDelegates: context.localizationDelegates,
                        // The launcher lives above the Navigator, so it survives
                        // every push and pop instead of being rebuilt per screen.
                        builder:
                            (context, child) => Stack(
                              children: [
                                child ?? const SizedBox.shrink(),
                                const DriverChatBubble(),
                              ],
                            ),
                        home: const SplashPage(),
                        // home: BlockatieProPage(),
                      ),
                      const ConnectionAlert(),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}
