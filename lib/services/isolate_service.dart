import 'dart:isolate';
import 'package:blockatie/utils/nav.dart';
import 'package:provider/provider.dart';

import '../provider/order_location.dart';

void startBackgroundIsolate() async {
  final receivePort = ReceivePort();
  await Isolate.spawn(backgroundTask, receivePort.sendPort);

  receivePort.listen((_) {});
}

void backgroundTask(SendPort sendPort) {
  final provider = Provider.of<OrderLocationProvider>(
    Nav.context,
    listen: false,
  );
  provider.startDriverLocationUpdates();
}
