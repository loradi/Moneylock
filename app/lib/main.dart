import 'package:flutter/material.dart';

import 'core/notifications.dart';
import 'core/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LocalNotifications().init();
  runApp(const MoneylockApp());
}

class MoneylockApp extends StatelessWidget {
  const MoneylockApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Moneylock',
      theme: buildTheme(),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Moneylock')),
      body: const Center(child: Text('Home')),
    );
  }
}