import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:psyfinance_app/core/app_router.dart';
import 'package:psyfinance_app/core/theme.dart';

void main() {
  runApp(const ProviderScope(child: PsyFinanceApp()));
}

class PsyFinanceApp extends StatelessWidget {
  const PsyFinanceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'PsyFinance',
      theme: buildAppTheme(),
      routerConfig: appRouter,
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
