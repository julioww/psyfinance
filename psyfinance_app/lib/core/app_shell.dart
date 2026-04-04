import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class AppShell extends StatelessWidget {
  final Widget child;

  const AppShell({super.key, required this.child});

  static const _destinations = [
    _NavDestination(
      icon: Icons.analytics_outlined,
      selectedIcon: Icons.analytics,
      label: 'Dashboard',
      route: '/dashboard',
    ),
    _NavDestination(
      icon: Icons.dashboard_outlined,
      selectedIcon: Icons.dashboard,
      label: 'Mensal',
      route: '/mensal',
    ),
    _NavDestination(
      icon: Icons.people_outline,
      selectedIcon: Icons.people,
      label: 'Pacientes',
      route: '/pacientes',
    ),
    _NavDestination(
      icon: Icons.event_note_outlined,
      selectedIcon: Icons.event_note,
      label: 'Sessões',
      route: '/sessoes',
    ),
    _NavDestination(
      icon: Icons.payments_outlined,
      selectedIcon: Icons.payments,
      label: 'Pagamentos',
      route: '/pagamentos',
    ),
    _NavDestination(
      icon: Icons.bar_chart_outlined,
      selectedIcon: Icons.bar_chart,
      label: 'Relatórios',
      route: '/relatorio',
    ),
  ];

  int _selectedIndex(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    final idx = _destinations.indexWhere((d) => location.startsWith(d.route));
    return idx < 0 ? 0 : idx;
  }

  @override
  Widget build(BuildContext context) {
    final selectedIdx = _selectedIndex(context);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: selectedIdx,
            onDestinationSelected: (i) => context.go(_destinations[i].route),
            labelType: NavigationRailLabelType.all,
            backgroundColor: colorScheme.surfaceContainerLow,
            indicatorColor: colorScheme.primaryContainer,
            selectedIconTheme:
                IconThemeData(color: colorScheme.onPrimaryContainer),
            unselectedIconTheme:
                IconThemeData(color: colorScheme.onSurfaceVariant),
            destinations: _destinations
                .map(
                  (d) => NavigationRailDestination(
                    icon: Icon(d.icon),
                    selectedIcon: Icon(d.selectedIcon),
                    label: Text(d.label),
                  ),
                )
                .toList(),
          ),
          const VerticalDivider(thickness: 1, width: 1),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _NavDestination {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final String route;

  const _NavDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.route,
  });
}
