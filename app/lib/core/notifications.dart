import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../llm/mentor_agent.dart';

class LocalNotifications {
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
}