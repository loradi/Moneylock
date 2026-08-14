import 'package:flutter/cupertino.dart';
import 'package:go_router/go_router.dart';

import '../features/chat/chat_screen.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/insights/insights_screen.dart';
import '../features/settings/settings_screen.dart';

/// Router: shell con 4 tabs estilo Cupertino. StatefulShellRoute preserva
/// el estado de cada tab (scroll del chat/dashboard) al alternar.
final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) =>
          AppShell(navigationShell: navigationShell),
      branches: [
        StatefulShellBranch(routes: [
          GoRoute(path: '/', builder: (_, _) => const DashboardScreen()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(path: '/chat', builder: (_, _) => const ChatScreen()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(path: '/insights', builder: (_, _) => const InsightsScreen()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
        ]),
      ],
    ),
  ],
);

class AppShell extends StatelessWidget {
  final StatefulNavigationShell navigationShell;
  const AppShell({super.key, required this.navigationShell});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(child: navigationShell),
        CupertinoTabBar(
          currentIndex: navigationShell.currentIndex,
          onTap: (index) => navigationShell.goBranch(
            index,
            initialLocation: index == navigationShell.currentIndex,
          ),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(CupertinoIcons.home),
              label: 'Dashboard',
            ),
            BottomNavigationBarItem(
              icon: Icon(CupertinoIcons.chat_bubble_2),
              label: 'Chat',
            ),
            BottomNavigationBarItem(
              icon: Icon(CupertinoIcons.chart_bar_square),
              label: 'Insights',
            ),
            BottomNavigationBarItem(
              icon: Icon(CupertinoIcons.gear_solid),
              label: 'Settings',
            ),
          ],
        ),
      ],
    );
  }
}