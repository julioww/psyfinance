import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:psyfinance_app/core/app_shell.dart';
import 'package:psyfinance_app/features/dashboard/dashboard_screen.dart';
import 'package:psyfinance_app/features/monthly/monthly_bulk_screen.dart';
import 'package:psyfinance_app/features/patients/patient_detail_screen.dart';
import 'package:psyfinance_app/features/patients/patient_list_screen.dart';
import 'package:psyfinance_app/features/relatorio/relatorio_screen.dart';
import 'package:psyfinance_app/screens/home_screen.dart';

final appRouter = GoRouter(
  initialLocation: '/mensal',
  routes: [
    ShellRoute(
      builder: (context, state, child) => AppShell(child: child),
      routes: [
        GoRoute(
          path: '/dashboard',
          builder: (context, state) => const DashboardScreen(),
        ),
        GoRoute(
          path: '/mensal',
          builder: (context, state) => const MonthlyBulkScreen(),
        ),
        GoRoute(
          path: '/pacientes',
          builder: (context, state) => const PatientListScreen(),
        ),
        GoRoute(
          path: '/pacientes/:id',
          builder: (context, state) => PatientDetailScreen(
            patientId: state.pathParameters['id']!,
          ),
        ),
        GoRoute(
          path: '/sessoes',
          builder: (context, state) =>
              const _PlaceholderScreen(label: 'Sessões'),
        ),
        GoRoute(
          path: '/pagamentos',
          builder: (context, state) =>
              const _PlaceholderScreen(label: 'Pagamentos'),
        ),
        GoRoute(
          path: '/relatorio',
          builder: (context, state) => const RelatorioScreen(),
        ),
      ],
    ),
    GoRoute(
      path: '/',
      builder: (context, state) => const HomeScreen(),
    ),
  ],
);

class _PlaceholderScreen extends StatelessWidget {
  final String label;
  const _PlaceholderScreen({required this.label});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Text(label, style: Theme.of(context).textTheme.headlineMedium),
      ),
    );
  }
}
