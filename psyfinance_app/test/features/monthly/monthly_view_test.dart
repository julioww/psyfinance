import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:psyfinance_app/core/api_client.dart';
import 'package:psyfinance_app/features/monthly/monthly_bulk_screen.dart';
import 'package:psyfinance_app/features/monthly/monthly_provider.dart';
import 'package:psyfinance_app/features/monthly/monthly_repository.dart';
import 'package:psyfinance_app/features/monthly/monthly_view_model.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const _patientBrl = {
  'id': 'p1',
  'name': 'Ana Silva',
  'location': 'Brasil',
  'currency': 'BRL',
  'paymentModel': 'SESSAO',
  'currentRate': 200.0,
};

const _patientEur = {
  'id': 'p2',
  'name': 'Max Müller',
  'location': 'Alemanha',
  'currency': 'EUR',
  'paymentModel': 'MENSAL',
  'currentRate': 80.0,
};

const _sessionRecord = {
  'id': 'sr1',
  'sessionDates': ['2026-03-05', '2026-03-12'],
  'sessionCount': 2,
  'expectedAmount': 400.0,
  'observations': null,
  'isReposicao': false,
};

const _payment = {
  'id': 'pay1',
  'amountPaid': 200.0,
  'status': 'PARCIAL',
  'revenueShareAmount': null,
};

MonthlyView _makeView({
  bool nullSession = false,
  bool includeEurPatient = true,
}) {
  return MonthlyView.fromJson({
    'patients': [
      {
        'patient': _patientBrl,
        'sessionRecord': nullSession ? null : _sessionRecord,
        'payment': nullSession ? null : _payment,
      },
      if (includeEurPatient)
        {
          'patient': _patientEur,
          'sessionRecord': nullSession
              ? null
              : {
                  ..._sessionRecord,
                  'id': 'sr2',
                  'expectedAmount': 80.0,
                },
          'payment': nullSession
              ? null
              : {
                  ..._payment,
                  'id': 'pay2',
                  'amountPaid': 80.0,
                  'status': 'PAGO',
                },
        },
    ],
    'summary': {
      'BRL': {
        'totalExpected': nullSession ? 0.0 : 400.0,
        'totalReceived': nullSession ? 0.0 : 200.0,
      },
      'EUR': {
        'totalExpected': (nullSession || !includeEurPatient) ? 0.0 : 80.0,
        'totalReceived': (nullSession || !includeEurPatient) ? 0.0 : 80.0,
      },
    },
  });
}

// ---------------------------------------------------------------------------
// Fake repository — returns a fixed MonthlyView without network I/O
// ---------------------------------------------------------------------------

class _FakeMonthlyRepo extends MonthlyRepository {
  final MonthlyView _view;

  _FakeMonthlyRepo(this._view)
      : super(ApiClient(baseUrl: 'http://localhost:0'));

  @override
  Future<MonthlyView> getMonthlyView(int year, int month) async => _view;
}

// ---------------------------------------------------------------------------
// Widget helper
// ---------------------------------------------------------------------------

Widget _makeApp(MonthlyView view) {
  return ProviderScope(
    overrides: [
      monthlyRepositoryProvider.overrideWith(
        (ref) => _FakeMonthlyRepo(view),
      ),
    ],
    child: const MaterialApp(
      home: Scaffold(body: MonthlyBulkScreen()),
    ),
  );
}

// ---------------------------------------------------------------------------
// 1. MonthlyView.fromJson — unit tests
// ---------------------------------------------------------------------------

void main() {
  group('MonthlyView.fromJson', () {
    test('parses patients with null sessionRecord and payment', () {
      final view = _makeView(nullSession: true);

      expect(view.patients.length, 2);
      expect(view.patients[0].sessionRecord, isNull);
      expect(view.patients[0].payment, isNull);
      expect(view.patients[1].sessionRecord, isNull);
      expect(view.patients[1].payment, isNull);
    });

    test('parses patients with sessions correctly', () {
      final view = _makeView();

      expect(view.patients[0].sessionRecord, isNotNull);
      expect(view.patients[0].sessionRecord!.sessionCount, 2);
      expect(view.patients[0].payment!.status, 'PARCIAL');
    });

    test('summary is always keyed by BRL and EUR', () {
      final view = _makeView();

      expect(view.summary.containsKey('BRL'), isTrue);
      expect(view.summary.containsKey('EUR'), isTrue);
      expect(view.summary['BRL']!.totalExpected, 400.0);
      expect(view.summary['EUR']!.totalReceived, 80.0);
    });

    test('patient currency parsed correctly', () {
      final view = _makeView();
      // First patient is BRL
      expect(view.patients[0].patient.location, 'Brasil');
      // Second patient is EUR
      expect(view.patients[1].patient.location, 'Alemanha');
    });
  });

  // ---------------------------------------------------------------------------
  // 2. Summary strip — widget tests
  // ---------------------------------------------------------------------------

  group('Summary strip', () {
    testWidgets('shows BRL and EUR cards regardless of patient data',
        (tester) async {
      await tester.pumpWidget(_makeApp(_makeView()));
      await tester.pumpAndSettle();

      expect(find.text('Real brasileiro'), findsOneWidget);
      expect(find.text('Euro'), findsOneWidget);
    });

    testWidgets('shows both currency cards even when EUR amounts are zero',
        (tester) async {
      final view = _makeView(includeEurPatient: false);
      await tester.pumpWidget(_makeApp(view));
      await tester.pumpAndSettle();

      expect(find.text('Real brasileiro'), findsOneWidget);
      expect(find.text('Euro'), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // 3. Country filter — widget tests
  // ---------------------------------------------------------------------------

  group('Country filter', () {
    testWidgets('shows only filtered country patients after selection',
        (tester) async {
      await tester.pumpWidget(_makeApp(_makeView()));
      await tester.pumpAndSettle();

      // Both patients initially visible
      expect(find.text('Ana Silva'), findsOneWidget);
      expect(find.text('Max Müller'), findsOneWidget);

      // Open country dropdown and select Brasil
      await tester.tap(find.text('Localização'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Brasil').last);
      await tester.pumpAndSettle();

      // Only Ana Silva should be visible in the table
      expect(find.text('Ana Silva'), findsOneWidget);
      expect(find.text('Max Müller'), findsNothing);
    });

    testWidgets('tapping Todos clears the country filter', (tester) async {
      await tester.pumpWidget(_makeApp(_makeView()));
      await tester.pumpAndSettle();

      // Apply Brasil filter
      await tester.tap(find.text('Localização'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Brasil').last);
      await tester.pumpAndSettle();

      expect(find.text('Max Müller'), findsNothing);

      // Clear filter via Todos
      await tester.tap(find.text('Todos'));
      await tester.pumpAndSettle();

      // Both patients visible again
      expect(find.text('Ana Silva'), findsOneWidget);
      expect(find.text('Max Müller'), findsOneWidget);
    });

    testWidgets(
        'summary strip shows only the filtered country in the currency subtitle',
        (tester) async {
      await tester.pumpWidget(_makeApp(_makeView()));
      await tester.pumpAndSettle();

      // Without filter, both Brasil and Alemanha appear
      expect(find.text('Brasil'), findsOneWidget);
      expect(find.text('Alemanha'), findsOneWidget);

      // Apply Brasil filter
      await tester.tap(find.text('Localização'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Brasil').last);
      await tester.pumpAndSettle();

      // Brasil appears at least once (BRL card + dropdown label); Alemanha disappears
      expect(find.text('Brasil'), findsAtLeastNWidgets(1));
      expect(find.text('Alemanha'), findsNothing);
    });
  });

  // ---------------------------------------------------------------------------
  // 4. computeSummaryFromRows — unit tests for in-place update logic
  // ---------------------------------------------------------------------------

  group('computeSummaryFromRows', () {
    test('recalculates BRL summary after payment update', () {
      final view = _makeView();

      final updatedRows = view.patients.map((row) {
        if (row.patient.id != 'p1') return row;
        return row.copyWith(
          payment: row.payment!.copyWith(amountPaid: 400.0, status: 'PAGO'),
        );
      }).toList();

      final newSummary = computeSummaryFromRows(updatedRows);
      expect(newSummary['BRL']!.totalReceived, 400.0);
      expect(newSummary['BRL']!.totalExpected, 400.0);
      // EUR unchanged
      expect(newSummary['EUR']!.totalReceived, 80.0);
    });

    test('returns zero totals when all sessions are null', () {
      final view = _makeView(nullSession: true);
      final summary = computeSummaryFromRows(view.patients);
      expect(summary['BRL']!.totalExpected, 0.0);
      expect(summary['BRL']!.totalReceived, 0.0);
      expect(summary['EUR']!.totalExpected, 0.0);
    });
  });

  // ---------------------------------------------------------------------------
  // 5. Empty state — widget tests
  // ---------------------------------------------------------------------------

  group('Empty state', () {
    testWidgets('shows empty state icon and message when all sessions are null',
        (tester) async {
      await tester.pumpWidget(_makeApp(_makeView(nullSession: true)));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.calendar_month_outlined), findsOneWidget);
      expect(find.textContaining('Nenhuma sessão em'), findsOneWidget);
      expect(
        find.textContaining(
            'Toque no ícone de calendário'),
        findsOneWidget,
      );
    });

    testWidgets('does not show empty state when sessions exist',
        (tester) async {
      await tester.pumpWidget(_makeApp(_makeView()));
      await tester.pumpAndSettle();

      expect(find.textContaining('Nenhuma sessão em'), findsNothing);
    });
  });
}
