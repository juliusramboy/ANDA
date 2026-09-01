import 'dart:convert';
import 'dart:io';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path_provider/path_provider.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static Future<void> init() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);

    await _notificationsPlugin.initialize(
      initializationSettings,
    );

    // Request permissions for Android (needed for API 33+)
    await _notificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  static Future<void> showNotificationIfDue(int dueCount) async {
    if (dueCount <= 0) return;

    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/last_notified_date.json');
      final todayStr = DateTime.now().toIso8601String().split('T').first; // yyyy-MM-dd

      if (await file.exists()) {
        final content = await file.readAsString();
        final Map<String, dynamic> data = jsonDecode(content);
        if (data['date'] == todayStr) {
          // Already notified today
          return;
        }
      }

      // Show native notification
      const AndroidNotificationDetails androidNotificationDetails =
          AndroidNotificationDetails(
        'due_dates',
        'Due Dates',
        channelDescription: 'Notifications for upcoming loan due dates',
        importance: Importance.max,
        priority: Priority.high,
        ticker: 'ticker',
      );
      const NotificationDetails notificationDetails =
          NotificationDetails(android: androidNotificationDetails);

      await _notificationsPlugin.show(
        0,
        'Due Date Alert',
        'You have $dueCount active loan${dueCount == 1 ? "" : "s"} due this month.',
        notificationDetails,
      );

      // Save today's date
      await file.writeAsString(jsonEncode({'date': todayStr}));
    } catch (e) {
      // debug log
    }
  }

  static Future<void> showNotification({
    required int id,
    required String title,
    required String body,
  }) async {
    try {
      const AndroidNotificationDetails androidNotificationDetails =
          AndroidNotificationDetails(
        'route_alerts',
        'Route & Location Alerts',
        channelDescription: 'Notifications for route arrivals and location tracking',
        importance: Importance.max,
        priority: Priority.high,
        ticker: 'ticker',
      );
      const NotificationDetails notificationDetails =
          NotificationDetails(android: androidNotificationDetails);

      await _notificationsPlugin.show(
        id,
        title,
        body,
        notificationDetails,
      );
    } catch (_) {}
  }
}

