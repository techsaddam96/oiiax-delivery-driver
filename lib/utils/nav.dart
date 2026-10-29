// import 'package:blockatie/provider/bottom_nav.dart';
// import 'package:blockatie/views/widgets/bottom_nav.dart';
// import 'package:flutter/material.dart';
// import 'package:provider/provider.dart';

// class Nav {
//   Nav._();

//   static final GlobalKey<NavigatorState> key = GlobalKey<NavigatorState>();

//   static BuildContext get context => key.currentState!.context;

//   /// ➡️ Push a new screen
//   // static void to(Widget page, {bool withNav = false, int? navIndex}) {
//   //   Navigator.push(
//   //     context,
//   //     MaterialPageRoute(
//   //       builder: (_) => withNav
//   //   ? _WithBottomNavWrapper(
//   //       navIndex: navIndex ?? 0,
//   //       overlayPage: page, // Pass your ProfilePage here
//   //     )
//   //   : page,

//   //       // builder: (_) => withNav
//   //       //     ? _WithBottomNavWrapper(navIndex: navIndex ?? 0)
//   //       //     : page,
//   //     ),
//   //   );
//   // }
//   static void to(Widget page, {bool withNav = false, int? navIndex}) {
//     if (withNav) {
//       final navProvider = Provider.of<BottomNavProvider>(
//         key.currentState!.context,
//         listen: false,
//       );

//       if (navIndex != null) {
//         navProvider.setIndex(navIndex);
//       }

//       navProvider.showOverlay(page);
//     } else {
//       Navigator.push(
//         key.currentState!.context,
//         MaterialPageRoute(builder: (_) => page),
//       );
//     }
//   }

//   /// 🔁 Replace current screen
//   static void off(Widget page, {bool withNav = false, int? navIndex}) {
//     Navigator.pushReplacement(
//       context,
//       MaterialPageRoute(
//         builder:
//             (_) =>
//                 withNav ? _WithBottomNavWrapper(navIndex: navIndex ?? 0) : page,
//       ),
//     );
//   }

//   /// 🔄 Clear all and push new screen
//   static void offAll(Widget page, {bool withNav = false, int? navIndex}) {
//     final effectiveContext = key.currentState?.context;

//     if (effectiveContext != null && Navigator.canPop(effectiveContext)) {
//       Navigator.pushAndRemoveUntil(
//         effectiveContext,
//         MaterialPageRoute(
//           builder:
//               (_) =>
//                   withNav
//                       ? _WithBottomNavWrapper(navIndex: navIndex ?? 0)
//                       : page,
//         ),
//         (route) => false,
//       );
//     } else {
//       off(page, withNav: withNav, navIndex: navIndex);
//     }
//   }

//   // /// ⬅️ Go back
//   // static void back([dynamic result]) =>
//   //     Navigator.pop(context, result);

//   static void back([dynamic result]) {
//     final navProvider = Provider.of<BottomNavProvider>(
//       key.currentState!.context,
//       listen: false,
//     );

//     if (navProvider.overlayPage != null) {
//       navProvider.clearOverlay();
//     } else {
//       Navigator.pop(key.currentState!.context, result);
//     }
//   }
// }

// class _WithBottomNavWrapper extends StatelessWidget {
//   final int navIndex;
//   final Widget? overlayPage;

//   const _WithBottomNavWrapper({required this.navIndex, this.overlayPage});

//   @override
//   Widget build(BuildContext context) {
//     WidgetsBinding.instance.addPostFrameCallback((_) {
//       final navProvider = Provider.of<BottomNavProvider>(
//         context,
//         listen: false,
//       );

//       navProvider.setIndex(navIndex);

//       if (overlayPage != null) {
//         navProvider.showOverlay(overlayPage!);
//       }
//     });

//     return CustomBottomNavBar();
//   }
// }

// import 'package:flutter/material.dart';

// class Nav {
//   Nav._();
//   static final GlobalKey<NavigatorState> key = GlobalKey<NavigatorState>();

//   static BuildContext get context => key.currentState!.context;

//   static to(Widget page) => Navigator.push(
//       key.currentState!.context,
//       MaterialPageRoute(
//         builder: (context) => page,
//       ));

//   static off(Widget page) => Navigator.pushReplacement(
//       key.currentState!.context,
//       MaterialPageRoute(
//         builder: (context) => page,
//       ));

//   static offAll(Widget page, [BuildContext? context]) {
//     final effectiveContext = context ?? key.currentState?.context;
//     if (effectiveContext != null && Navigator.canPop(effectiveContext)) {
//       Navigator.pushAndRemoveUntil(
//         effectiveContext,
//         MaterialPageRoute(builder: (context) => page),
//         (Route<dynamic> route) => false,
//       );
//     } else {
//       off(page);
//       // debugLog("Navigation context is invalid or no routes in the stack.");
//     }
//   }

//   static back([result]) => Navigator.pop(key.currentState!.context, result);
// }

import 'package:blockatie/views/widgets/bottom_nav.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:blockatie/provider/bottom_nav.dart';

class Nav {
  Nav._();

  static final GlobalKey<NavigatorState> key = GlobalKey<NavigatorState>();

  static BuildContext get context => key.currentState!.context;

  static void to(Widget page, {bool withNav = false, int? navIndex}) {
    if (withNav) {
      final navProvider = Provider.of<BottomNavProvider>(
        key.currentState!.context,
        listen: false,
      );

      if (navIndex != null) {
        navProvider.setIndex(navIndex);
      }

      navProvider.showOverlay(page);
    } else {
      Navigator.push(
        key.currentState!.context,
        MaterialPageRoute(builder: (_) => page),
      );
    }
  }

  /// 🔁 Replace current screen
  static void off(Widget page, {bool withNav = false, int? navIndex}) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder:
            (_) =>
                withNav ? _WithBottomNavWrapper(navIndex: navIndex ?? 0) : page,
      ),
    );
  }

  /// 🔄 Clear all and push new screen
  static void offAll(Widget page, {bool withNav = false, int? navIndex}) {
    final effectiveContext = key.currentState?.context;

    if (effectiveContext != null && Navigator.canPop(effectiveContext)) {
      Navigator.pushAndRemoveUntil(
        effectiveContext,
        MaterialPageRoute(
          builder:
              (_) =>
                  withNav
                      ? _WithBottomNavWrapper(navIndex: navIndex ?? 0)
                      : page,
        ),
        (route) => false,
      );
    } else {
      off(page, withNav: withNav, navIndex: navIndex);
    }
  }

  // /// ⬅️ Go back
  // static void back([dynamic result]) =>
  //     Navigator.pop(context, result);

  static void back([dynamic result]) {
    final navProvider = Provider.of<BottomNavProvider>(
      key.currentState!.context,
      listen: false,
    );

    if (navProvider.overlayPage != null) {
      navProvider.clearOverlay();
    } else {
      Navigator.pop(key.currentState!.context, result);
    }
  }
}

class _WithBottomNavWrapper extends StatelessWidget {
  final int navIndex;

  const _WithBottomNavWrapper({required this.navIndex});

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final navProvider = Provider.of<BottomNavProvider>(
        context,
        listen: false,
      );

      navProvider.setIndex(navIndex);
    });

    return CustomBottomNavBar();
  }
}

// class _WithBottomNavWrapper extends StatelessWidget {
//   final int navIndex;

//   const _WithBottomNavWrapper({super.key, required this.navIndex});

//   @override
//   Widget build(BuildContext context) {
//     WidgetsBinding.instance.addPostFrameCallback((_) {
//       Provider.of<BottomNavProvider>(context, listen: false)
//           .setIndex(navIndex);
//     });

//     return const CustomBottomNavBar(); // This manages the IndexedStack
//   }
// }
