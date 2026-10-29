import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

class ConnectivityController {
  final ValueNotifier<bool> isConnected = ValueNotifier(false);
  StreamSubscription<List<ConnectivityResult>>? _subscription;

  Future<void> init() async {
    List<ConnectivityResult> result = await Connectivity().checkConnectivity();
    isInternetConnected(result.first);
    await _subscription?.cancel();
    _subscription = Connectivity().onConnectivityChanged.listen((
      List<ConnectivityResult> result,
    ) {
      isInternetConnected(result.first);
    });
  }

  bool isInternetConnected(ConnectivityResult? result) {
    if (result == ConnectivityResult.none) {
      isConnected.value = false;
      return false;
    } else if (result == ConnectivityResult.mobile ||
        result == ConnectivityResult.wifi) {
      isConnected.value = true;
      return true;
    }
    return false;
  }

  void dispose() {
    unawaited(_subscription?.cancel());
    isConnected.dispose();
  }
}
