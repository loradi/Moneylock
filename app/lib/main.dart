import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'core/notifications.dart';
import 'core/router.dart';
import 'providers.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tz_data.initializeTimeZones();
  tz.setLocalLocation(tz.getLocation(await FlutterTimezone.getLocalTimezone()));
  await LocalNotifications().init();
  final container = ProviderContainer();
  unawaited(container.read(deepLinkHandlerProvider).startListening());
  runApp(UncontrolledProviderScope(
    container: container,
    child: const MoneylockApp(),
  ));
}

class MoneylockApp extends StatelessWidget {
  const MoneylockApp({super.key});

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
