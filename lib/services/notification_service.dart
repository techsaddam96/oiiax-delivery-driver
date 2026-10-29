// import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// class LocalNotificationService {
//   static final _plugin = FlutterLocalNotificationsPlugin();

//   static Future<void> initialize() async {
//     const AndroidInitializationSettings androidInit =
//         AndroidInitializationSettings('@mipmap/ic_launcher');

//     const InitializationSettings settings =
//         InitializationSettings(android: androidInit);

//     await _plugin.initialize(settings);
//   }

//   static Future<void> showNotification(String title, String body) async {
//     const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
//       'default_channel_id',
//       'Default Channel',
//       channelDescription: 'Used for default notifications',
//       importance: Importance.max,
//       priority: Priority.high,
//       playSound: true,
//     );

//     const NotificationDetails platformDetails =
//         NotificationDetails(android: androidDetails);

//     await _plugin.show(
//       0, // Notification ID
//       title,
//       body,
//       platformDetails,
//     );
//   }
// }
