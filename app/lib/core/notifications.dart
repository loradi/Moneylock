import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../llm/mentor_agent.dart';

abstract class NotificationScheduling {
  Future<void> scheduleAt(int id, DateTime when, String title, String body);
  Future<void> cancel(int id);
}

class LocalNotifications implements NotificationScheduling {
  final _plugin = FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    const settings = InitializationSettings(
        iOS: DarwinInitializationSettings(requestAlertPermission: true,
            requestBadgePermission: true, requestSoundPermission: true));
    await _plugin.initialize(settings: settings);
  }

  Future<void> show(String title, String body, Severity severity) =>
      _plugin.show(
          id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          title: title,
          body: body,
          notificationDetails: const NotificationDetails(
              iOS: DarwinNotificationDetails(badgeNumber: 1)),
          payload: severity.name);

  @override
  Future<void> scheduleAt(
    int id,
    DateTime when,
    String title,
    String body,
  ) =>
      _plugin.zonedSchedule(
        id: id,
        title: title,
        body: body,
        scheduledDate: tz.TZDateTime.from(when, tz.local),
        notificationDetails: const NotificationDetails(
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      );

  @override
  Future<void> cancel(int id) => _plugin.cancel(id: id);
}
