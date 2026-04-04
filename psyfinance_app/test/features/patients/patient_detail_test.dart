import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:psyfinance_app/features/patients/patient_detail_screen.dart';
import 'package:psyfinance_app/features/patients/patient_model.dart';
import 'package:psyfinance_app/features/patients/patient_summary_model.dart';
import 'package:psyfinance_app/features/patients/patients_provider.dart';
import 'package:psyfinance_app/features/patients/rate_history_model.dart';
import 'package:psyfinance_app/features/patients/rate_history_provider.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

final _testPatient = Patient(
  id: 'patient-1',
  name: 'Ana Santos',
  email: 'ana@example.com',
  location: 'Brasil',
  status: PatientStatus.ativo,
  paymentModel: PaymentModel.sessao,
  currency: PatientCurrency.brl,
  currentRate: 150.0,
  createdAt: DateTime(2025, 1, 15),
  updatedAt: DateTime(2025, 1, 15),
);

final _testRates = [
  RateHistory(
    id: 'r1',
    patientId: 'patient-1',
    rate: 150.0,
    effectiveFrom: DateTime(2025, 1, 1),
  ),
];

List<MonthSummary> _makeMonths({List<int> withData = const [1, 2, 3]}) {
  return List.generate(12, (i) {
    final month = i + 1;
    if (withData.contains(month)) {
      return MonthSummary(
        month: month,
        sessionCount: 4,
        expectedAmount: 600.0,
        amountPaid: 400.0,
        balance: 200.0,
        status: month == 1
            ? MonthPaymentStatus.pago
            : MonthPaymentStatus.pendente,
      );
    }
    return MonthSummary(month: month);
  });
}

PatientSummary _makeSummary({List<MonthSummary>? months}) => PatientSummary(
      patient: _testPatient,
      rates: _testRates,
      months: months ?? _makeMonths(),
    );

// ---------------------------------------------------------------------------
// Mock notifiers
// ---------------------------------------------------------------------------

class _MockSummaryNotifier
    extends FamilyAsyncNotifier<PatientSummary, PatientSummaryArgs> {
  final List<PatientSummaryArgs> calls;
  final PatientSummary summary;

  _MockSummaryNotifier(this.calls, this.summary);

  @override
  Future<PatientSummary> build(PatientSummaryArgs arg) async {
    calls.add(arg);
    return summary;
  }
}

class _MockRateHistoryNotifier
    extends FamilyAsyncNotifier<List<RateHistory>, String> {
  @override
  Future<List<RateHistory>> build(String patientId) async => [];
}

// ---------------------------------------------------------------------------
// Wrap helper
// ---------------------------------------------------------------------------

Widget _wrap(
  Widget widget, {
  List<Override> overrides = const [],
}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(home: widget),
  );
}

// ---------------------------------------------------------------------------
// Test 1 & 2 — PatientSummary model (pure unit tests)
// ---------------------------------------------------------------------------

void main() {
  group('PatientSummary.fromJson', () {
    final json = {
      'patient': {
        'id': 'p1',
        'name': 'Maria',
        'email': 'm@example.com',
        'location': 'Brasil',
        'status': 'ATIVO',
        'paymentModel': 'SESSAO',
        'currency': 'BRL',
        'currentRate': 100.0,
        'createdAt': '2024-01-01T00:00:00.000Z',
        'updatedAt': '2024-01-01T00:00:00.000Z',
      },
      'rates': [
        {
          'id': 'r1',
          'patientId': 'p1',
          'rate': 100.0,
          'effectiveFrom': '2024-01-01',
          'effectiveTo': null,
        }
      ],
      'months': List.generate(12, (i) {
        final month = i + 1;
        return month <= 3
            ? {
                'month': month,
                'sessionCount': 4,
                'expectedAmount': 400.0,
                'amountPaid': 400.0,
                'balance': 0.0,
                'status': 'PAGO',
                'observations': null,
              }
            : {
                'month': month,
                'sessionCount': null,
                'expectedAmount': null,
                'amountPaid': null,
                'balance': null,
                'status': null,
                'observations': null,
              };
      }),
    };

    test('parses all 12 monthly entries', () {
      final summary = PatientSummary.fromJson(json);
      expect(summary.months.length, 12);
    });

    test('month numbers are 1..12 in order', () {
      final summary = PatientSummary.fromJson(json);
      for (var i = 0; i < 12; i++) {
        expect(summary.months[i].month, i + 1);
      }
    });

    test('months with data are parsed correctly', () {
      final summary = PatientSummary.fromJson(json);
      final jan = summary.months.first;
      expect(jan.sessionCount, 4);
      expect(jan.expectedAmount, 400.0);
      expect(jan.amountPaid, 400.0);
      expect(jan.balance, 0.0);
      expect(jan.status, MonthPaymentStatus.pago);
      expect(jan.hasData, isTrue);
    });

    test('null rows are parsed as empty MonthSummary', () {
      final summary = PatientSummary.fromJson(json);
      final apr = summary.months[3]; // month 4
      expect(apr.month, 4);
      expect(apr.sessionCount, isNull);
      expect(apr.expectedAmount, isNull);
      expect(apr.hasData, isFalse);
    });

    test('all 12 statuses parse correctly', () {
      for (final pair in [
        ['PAGO', MonthPaymentStatus.pago],
        ['PARCIAL', MonthPaymentStatus.parcial],
        ['PENDENTE', MonthPaymentStatus.pendente],
        ['ATRASADO', MonthPaymentStatus.atrasado],
      ]) {
        expect(
          MonthPaymentStatusX.fromString(pair[0] as String),
          pair[1],
        );
      }
      expect(MonthPaymentStatusX.fromString(null), isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // Test 2 — Annual summary strip aggregates
  // ---------------------------------------------------------------------------

  group('PatientSummary annual aggregates (only non-null months)', () {
    test('totalSessions sums only non-null months', () {
      // 3 months with 4 sessions each
      expect(_makeSummary().totalSessions, 12);
    });

    test('totalExpected sums only non-null months', () {
      expect(_makeSummary().totalExpected, 1800.0);
    });

    test('totalPaid sums only non-null months', () {
      expect(_makeSummary().totalPaid, 1200.0);
    });

    test('totalBalance sums only non-null months', () {
      expect(_makeSummary().totalBalance, 600.0);
    });

    test('all-null months produce zero aggregates', () {
      final empty = _makeSummary(
          months: List.generate(12, (i) => MonthSummary(month: i + 1)));
      expect(empty.totalSessions, 0);
      expect(empty.totalExpected, 0.0);
      expect(empty.totalPaid, 0.0);
      expect(empty.totalBalance, 0.0);
    });
  });

  // ---------------------------------------------------------------------------
  // Test 3 — Year navigator refetches with the correct year on tap
  // ---------------------------------------------------------------------------

  testWidgets('year navigator refetches with correct year on tap',
      (tester) async {
    final calls = <PatientSummaryArgs>[];
    final summary = _makeSummary(); // rates start in 2025

    await tester.pumpWidget(_wrap(
      PatientDetailScreen(patientId: 'patient-1'),
      overrides: [
        patientSummaryProvider
            .overrideWith(() => _MockSummaryNotifier(calls, summary)),
        rateHistoryProvider
            .overrideWith(() => _MockRateHistoryNotifier()),
      ],
    ));

    await tester.pumpAndSettle();

    // Initial call should be for the current year
    expect(calls.any((c) => c.year == DateTime.now().year), isTrue);

    final callsBefore = calls.length;

    // Tap the 2025 chip (firstYear from _testRates is 2025)
    await tester.tap(find.text('2025'));
    await tester.pumpAndSettle();

    // A new call should have been made for 2025
    expect(calls.length, greaterThan(callsBefore));
    expect(calls.any((c) => c.year == 2025), isTrue);
  });

  // ---------------------------------------------------------------------------
  // Test 4 — Tapping a month row calls onMonthTap with the correct month
  // ---------------------------------------------------------------------------

  testWidgets('tapping a month row opens session entry sheet for that month',
      (tester) async {
    MonthSummary? tappedMonth;
    final summary = _makeSummary();

    await tester.pumpWidget(_wrap(
      PatientDetailScreen(
        patientId: 'patient-1',
        onMonthTap: (_, month) => tappedMonth = month,
      ),
      overrides: [
        patientSummaryProvider
            .overrideWith(() => _MockSummaryNotifier([], summary)),
        rateHistoryProvider
            .overrideWith(() => _MockRateHistoryNotifier()),
      ],
    ));

    await tester.pumpAndSettle();

    // Tap the January row (first occurrence of 'Jan')
    await tester.tap(find.text('Jan').first);
    await tester.pumpAndSettle();

    expect(tappedMonth, isNotNull);
    expect(tappedMonth!.month, 1);
  });
}
