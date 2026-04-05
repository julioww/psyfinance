import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:psyfinance_app/core/app_router.dart';
import 'package:psyfinance_app/core/auth/auth_provider.dart';
import 'package:psyfinance_app/core/theme.dart';
import 'package:psyfinance_app/features/patients/patients_provider.dart';

void main() {
  runApp(const ProviderScope(child: PsyFinanceApp()));
}

class PsyFinanceApp extends ConsumerWidget {
  const PsyFinanceApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Wire the ApiClient to auth state:
    // - Set token on login, clear on logout
    final authState = ref.watch(authProvider);
    final apiClient = ref.read(apiClientProvider);

    if (authState.isAuthenticated && authState.token != null) {
      apiClient.setAuthToken(authState.token!);
    } else {
      apiClient.clearAuthToken();
    }

    // Connect ApiClient's 401 handler to AuthNotifier
    apiClient.onUnauthorized = ref.read(authProvider.notifier).forceLogout;

    return MaterialApp.router(
      title: 'PsyFinance',
      theme: buildAppTheme(),
      routerConfig: ref.watch(routerProvider),
      locale: const Locale('pt', 'BR'),
      supportedLocales: const [
        Locale('pt', 'BR'),
        Locale('en', 'US'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      debugShowCheckedModeBanner: false,
    );
  }
}
