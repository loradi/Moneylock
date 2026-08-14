import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/notifications.dart';
import 'core/router.dart';
import 'providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LocalNotifications().init();
  final container = ProviderContainer();
  unawaited(container.read(deepLinkHandlerProvider).startListening());
  runApp(UncontrolledProviderScope(
      container: container, child: const MoneylockApp()));
}

class MoneylockApp extends StatelessWidget {
  const MoneylockApp({super.key});

  @override
  Widget build(BuildContext context) {
    return CupertinoApp.router(
      title: 'Moneylock',
      theme: CupertinoThemeData(
        brightness: Brightness.light,
        primaryColor: CupertinoColors.activeBlue,
        scaffoldBackgroundColor: CupertinoColors.systemGroupedBackground,
        barBackgroundColor: CupertinoColors.systemBackground,
      ),
      routerConfig: appRouter,
      debugShowCheckedModeBanner: false,
    );
  }
}