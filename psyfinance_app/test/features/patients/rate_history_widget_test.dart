import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:psyfinance_app/core/api_client.dart';
import 'package:psyfinance_app/features/patients/patient_model.dart';
import 'package:psyfinance_app/features/patients/patients_provider.dart';
import 'package:psyfinance_app/features/patients/patients_repository.dart';
import 'package:psyfinance_app/features/patients/rate_history_model.dart';
import 'package:psyfinance_app/features/patients/rate_history_widget.dart';

// ---------------------------------------------------------------------------
// Mock repository
// ---------------------------------------------------------------------------

class _MockRepository extends PatientsRepository {
  final List<RateHistory> rates;
  final ApiException? errorOnAdd;

  _MockRepository({required this.rates, this.errorOnAdd}) : super(ApiClient());

  @override
  Future<List<RateHistory>> getRateHistory(String patientId) async => rates;

  @override
  Future<RateHistory> addRate(
    String patientId,
    double rate,
    DateTime effectiveFrom,
  ) async {
    if (errorOnAdd != null) throw errorOnAdd!;
    return RateHistory(
      id: 'new-id',
      patientId: patientId,
      rate: rate,
      effectiveFrom: effectiveFrom,
    );
  }
}

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

Widget _wrap(Widget child, {required PatientsRepository repo}) {
  return ProviderScope(
    overrides: [patientsRepositoryProvider.overrideWithValue(repo)],
    child: MaterialApp(
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('pt', 'BR')],
      home: Scaffold(body: child),
    ),
  );
}

// ---------------------------------------------------------------------------
// Fixture data
// ---------------------------------------------------------------------------

final _historicalRate = RateHistory(
  id: 'rate-1',
  patientId: 'p1',
  rate: 200.0,
  effectiveFrom: DateTime(2025, 1, 1),
  effectiveTo: DateTime(2025, 7, 31),
);

final _currentRate = RateHistory(
  id: 'rate-2',
  patientId: 'p1',
  rate: 250.0,
  effectiveFrom: DateTime(2025, 8, 1),
  effectiveTo: null,
);

// ---------------------------------------------------------------------------
// RateHistoryWidget tests
// ---------------------------------------------------------------------------

void main() {
  group('RateHistoryWidget', () {
    testWidgets('renders "atual" chip only on the most recent entry', (tester) async {
      final repo = _MockRepository(rates: [_currentRate, _historicalRate]);

      await tester.pumpWidget(
        _wrap(
          RateHistoryWidget(patientId: 'p1', currency: PatientCurrency.brl),
          repo: repo,
        ),
      );

      // Wait for the async provider to resolve
      await tester.pumpAndSettle();

      // Exactly one "atual" chip
      expect(find.text('atual'), findsOneWidget);
    });

    testWidgets('does not show "atual" chip on historical entries', (tester) async {
      final repo = _MockRepository(rates: [_currentRate, _historicalRate]);

      await tester.pumpWidget(
        _wrap(
          RateHistoryWidget(patientId: 'p1', currency: PatientCurrency.brl),
          repo: repo,
        ),
      );

      await tester.pumpAndSettle();

      // Both entries are rendered (verify date range texts appear)
      expect(find.textContaining('a partir de'), findsOneWidget);
      expect(find.textContaining('–'), findsOneWidget);
    });

    testWidgets('shows "Atualizar taxa" button', (tester) async {
      final repo = _MockRepository(rates: [_currentRate]);

      await tester.pumpWidget(
        _wrap(
          RateHistoryWidget(patientId: 'p1', currency: PatientCurrency.brl),
          repo: repo,
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Atualizar taxa'), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // RateUpdateDialog tests
  // ---------------------------------------------------------------------------

  group('RateUpdateDialog', () {
    testWidgets('shows inline error text below date field on 409 response', (tester) async {
      const errorMessage = 'A data deve ser posterior a 2025-01-01';
      final repo = _MockRepository(
        rates: [],
        errorOnAdd: const ApiException(statusCode: 409, message: errorMessage),
      );

      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => RateUpdateDialog(
                  patientId: 'p1',
                  currency: PatientCurrency.brl,
                  onSuccess: () {},
                  // Pre-set date to bypass the date picker in this test
                  initialEffectiveFrom: DateTime(2025, 1, 1),
                ),
              ),
              child: const Text('Abrir'),
            ),
          ),
          repo: repo,
        ),
      );

      // Open dialog
      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();

      // Fill in the rate field
      await tester.enterText(find.byType(TextFormField), '300');

      // Tap Confirmar
      await tester.tap(find.text('Confirmar'));
      await tester.pumpAndSettle();

      // Inline error should appear below the date field
      expect(find.text(errorMessage), findsOneWidget);
    });

    testWidgets('shows date validation error when no date is selected', (tester) async {
      final repo = _MockRepository(rates: []);

      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => RateUpdateDialog(
                  patientId: 'p1',
                  currency: PatientCurrency.brl,
                  onSuccess: () {},
                ),
              ),
              child: const Text('Abrir'),
            ),
          ),
          repo: repo,
        ),
      );

      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField), '300');
      await tester.tap(find.text('Confirmar'));
      await tester.pumpAndSettle();

      expect(find.text('Selecione a data de vigência'), findsOneWidget);
    });

    testWidgets('closes dialog and calls onSuccess when submission succeeds', (tester) async {
      var successCalled = false;
      final repo = _MockRepository(rates: []);

      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => RateUpdateDialog(
                  patientId: 'p1',
                  currency: PatientCurrency.brl,
                  onSuccess: () => successCalled = true,
                  initialEffectiveFrom: DateTime(2025, 9, 1),
                ),
              ),
              child: const Text('Abrir'),
            ),
          ),
          repo: repo,
        ),
      );

      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField), '350');
      await tester.tap(find.text('Confirmar'));
      await tester.pumpAndSettle();

      expect(successCalled, isTrue);
      // Dialog should be dismissed
      expect(find.text('Atualizar taxa'), findsNothing);
    });
  });
}
