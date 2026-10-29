import 'package:blockatie/utils/localization.dart';
import 'package:blockatie/views/pages/connectivity/connectivity_controller.dart';
import 'package:blockatie/views/pages/connectivity/no_internet_screen.dart';
import 'package:flutter/material.dart';

class ConnectionAlert extends StatefulWidget {
  const ConnectionAlert({super.key});

  @override
  State<ConnectionAlert> createState() => _ConnectionAlertState();
}

class _ConnectionAlertState extends State<ConnectionAlert> {
  ConnectivityController connectivityController = ConnectivityController();

  @override
  void initState() {
    connectivityController.init();
    super.initState();
  }

  @override
  void dispose() {
    connectivityController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // This overlay sits above MaterialApp, so it has no Directionality of its
    // own to inherit and must state one. It used to state `rtl` unconditionally
    // — an English driver's message was laid out right-to-left, which moved its
    // trailing punctuation to the wrong end of the line.
    //
    // AppLocalizations is the same source the offline screen reads for its
    // wording, and main() rebuilds this subtree on a language change.
    return Directionality(
      textDirection:
          AppLocalizations.isRTL ? TextDirection.rtl : TextDirection.ltr,
      child: ValueListenableBuilder(
        valueListenable: connectivityController.isConnected,
        builder: (context, value, child) {
          if (value) {
            return const SizedBox();
          } else {
            return const NoInternetScreen();
          }
        },
      ),
    );
  }
}
