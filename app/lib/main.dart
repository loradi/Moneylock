import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'core/notification_scheduler.dart';
import 'core/notifications.dart';
import 'core/router.dart';
import 'providers.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tz_data.initializeTimeZones();
  try {
    tz.setLocalLocation(tz.getLocation(await FlutterTimezone.getLocalTimezone()));
  } catch (_) {
    tz.setLocalLocation(tz.UTC);
  }
  final localNotifications = LocalNotifications();
  await localNotifications.init();
  final container = ProviderContainer();
  unawaited(container.read(deepLinkHandlerProvider).startListening());
  unawaited(NotificationScheduler(
    container.read(appDatabaseProvider),
    localNotifications,
  ).refresh());
  runApp(UncontrolledProviderScope(
    container: container,
    child: MoneylockApp(notifications: localNotifications),
  ));
}

class MoneylockApp extends StatefulWidget {
  final LocalNotifications notifications;
  const MoneylockApp({super.key, required this.notifications});

  @override
  State<MoneylockApp> createState() => _MoneylockAppState();
}

class _MoneylockAppState extends State<MoneylockApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final container = ProviderScope.containerOf(context, listen: false);
      NotificationScheduler(
        container.read(appDatabaseProvider),
        widget.notifications,
      ).refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Moneylock',
      theme: buildAppTheme(),
      routerConfig: appRouter,
      debugShowCheckedModeBanner: false,
    );
  }
}
