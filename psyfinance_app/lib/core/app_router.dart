import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:psyfinance_app/core/app_shell.dart';
import 'package:psyfinance_app/core/auth/auth_provider.dart';
import 'package:psyfinance_app/features/configuracoes/configuracoes_screen.dart';
import 'package:psyfinance_app/features/dashboard/dashboard_screen.dart';
import 'package:psyfinance_app/features/login/login_screen.dart';
import 'package:psyfinance_app/features/monthly/monthly_bulk_screen.dart';
import 'package:psyfinance_app/features/patients/patient_detail_screen.dart';
import 'package:psyfinance_app/features/patients/patient_list_screen.dart';
import 'package:psyfinance_app/features/agenda/sessoes_screen.dart';
import 'package:psyfinance_app/features/payments/pagamentos_screen.dart';
import 'package:psyfinance_app/features/relatorio/relatorio_screen.dart';
import 'package:psyfinance_app/screens/home_screen.dart';

// ---------------------------------------------------------------------------
// routerProvider
// Creates the GoRouter once; uses AuthNotifier as refreshListenable so that
// route guards are re-evaluated whenever auth state changes.
// ---------------------------------------------------------------------------

final routerProvider = Provider<GoRouter>((ref) {
  final authNotifier = ref.read(authProvider.notifier);

  final router = GoRouter(
    initialLocation: '/mensal',
    refreshListenable: authNotifier.routerListenable,
    redirect: (context, state) {
      final isAuthenticated = ref.read(authProvider).isAuthenticated;
      final goingToLogin = state.matchedLocation == '/login';

      if (!isAuthenticated && !goingToLogin) return '/login';
      if (isAuthenticated && goingToLogin) return '/mensal';
      return null;
    },
    routes: [
      // ---------------------------------------------------------------
      // Public
      // ---------------------------------------------------------------
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),

      // ---------------------------------------------------------------
      // Configurações — own full-screen layout, no NavigationRail
      // ---------------------------------------------------------------
      GoRoute(
        path: '/configuracoes',
        builder: (context, state) => const ConfiguracoesScreen(),
      ),

      // ---------------------------------------------------------------
      // Main shell (NavigationRail)
      // ---------------------------------------------------------------
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
            builder: (context, state) => const SessoesScreen(),
          ),
          GoRoute(
            path: '/pagamentos',
            builder: (context, state) => const PagamentosScreen(),
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

  // Wire up forced logout → router navigates to /login
  authNotifier.onForceLogout = () => router.go('/login');

  return router;
});

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
