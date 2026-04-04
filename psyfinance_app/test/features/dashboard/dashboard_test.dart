import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:psyfinance_app/core/api_client.dart';
import 'package:psyfinance_app/features/dashboard/dashboard_model.dart';
import 'package:psyfinance_app/features/dashboard/dashboard_provider.dart';
import 'package:psyfinance_app/features/dashboard/dashboard_repository.dart';
import 'package:psyfinance_app/features/dashboard/dashboard_screen.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

Map<String, dynamic> _makeMonthlyTotals({double expected = 0, double received = 0}) =>
    List.generate(
      12,
      (i) => {'month': i + 1, 'expected': expected, 'received': received},
    ).cast<Map<String, dynamic>>().asMap().values.toList() as dynamic;

Map<String, dynamic> _dashboardJson({
  double brlExpected = 1200.0,
  double brlReceived = 800.0,
  double eurExpected = 500.0,
  double eurReceived = 500.0,
  List<Map<String, dynamic>>? patients,
  List<Map<String, dynamic>>? repasses,
}) {
  final brlPerMonth = brlExpected / 12;
  final brlRecPerMonth = brlReceived / 12;
  final eurPerMonth = eurExpected / 12;
  final eurRecPerMonth = eurReceived / 12;

  return {
    'year': 2026,
    'BRL': {
      'monthlyTotals': List.generate(
        12,
        (i) => {'month': i + 1, 'expected': brlPerMonth, 'received': brlRecPerMonth},
      ),
      'yearToDate': {'expected': brlExpected, 'received': brlReceived},
      'countries': ['Brasil'],
    },
    'EUR': {
      'monthlyTotals': List.generate(
        12,
        (i) => {'month': i + 1, 'expected': eurPerMonth, 'received': eurRecPerMonth},
      ),
      'yearToDate': {'expected': eurExpected, 'received': eurReceived},
      'countries': ['Alemanha', 'Portugal'],
    },
    'patients': patients ??
        [
          {
            'id': 'p1',
            'name': 'Ana Silva',
            'location': 'Brasil',
            'currency': 'BRL',
            'totalSessions': 10,
            'totalExpected': 1200.0,
            'totalReceived': 800.0,
            'balance': 400.0,
            'hasOutstanding': true,
          },
          {
            'id': 'p2',
            'name': 'Klaus Müller',
            'location': 'Alemanha',
            'currency': 'EUR',
            'totalSessions': 8,
            'totalExpected': 500.0,
            'totalReceived': 500.0,
            'balance': 0.0,
            'hasOutstanding': false,
          },
        ],
    'repasses': repasses ?? [],
  };
}

// ---------------------------------------------------------------------------
// Fake repository
// ---------------------------------------------------------------------------

class _FakeDashboardRepo extends DashboardRepository {
  final DashboardData _data;

  _FakeDashboardRepo(this._data)
      : super(ApiClient(baseUrl: 'http://localhost:0'));

  @override
  Future<DashboardData> getDashboard(int year) async => _data;

  @override
  Future<List<YearlyComparison>> getComparison(List<int> years) async => [];
}

Widget _makeApp(DashboardData data) {
  return ProviderScope(
    overrides: [
      dashboardRepositoryProvider.overrideWith(
        (ref) => _FakeDashboardRepo(data),
      ),
    ],
    child: const MaterialApp(
      home: Scaffold(body: DashboardScreen()),
    ),
  );
}

// ===========================================================================
// 1. DashboardData.fromJson — unit tests
// ===========================================================================

void main() {
  group('DashboardData.fromJson', () {
    test('parses BRL and EUR sections with 12 monthly entries each', () {
      final data = DashboardData.fromJson(_dashboardJson());

      expect(data.year, 2026);
      expect(data.brl.monthlyTotals.length, 12);
      expect(data.eur.monthlyTotals.length, 12);
      expect(data.brl.yearToDateExpected, 1200.0);
      expect(data.brl.yearToDateReceived, 800.0);
      expect(data.eur.yearToDateExpected, 500.0);
      expect(data.eur.yearToDateReceived, 500.0);
    });

    test('monthlyTotals are indexed month 1–12', () {
      final data = DashboardData.fromJson(_dashboardJson());

      for (var i = 0; i < 12; i++) {
        expect(data.brl.monthlyTotals[i].month, i + 1);
        expect(data.eur.monthlyTotals[i].month, i + 1);
      }
    });

    test('parses patients list', () {
      final data = DashboardData.fromJson(_dashboardJson());

      expect(data.patients.length, 2);
      expect(data.patients[0].name, 'Ana Silva');
      expect(data.patients[0].hasOutstanding, isTrue);
      expect(data.patients[1].hasOutstanding, isFalse);
    });

    test('repasses defaults to empty list when absent', () {
      final json = _dashboardJson();
      json.remove('repasses');
      final data = DashboardData.fromJson(json);
      expect(data.repasses, isEmpty);
    });

    test('countries are parsed for both currencies', () {
      final data = DashboardData.fromJson(_dashboardJson());
      expect(data.brl.countries, ['Brasil']);
      expect(data.eur.countries, containsAll(['Alemanha', 'Portugal']));
    });
  });

  // =========================================================================
  // 2. Summary card progress bar — clamping
  // =========================================================================

  group('SummaryCard progress bar clamping', () {
    test('progress is clamped to 1.0 when received > expected', () {
      final data = DashboardData.fromJson(
        _dashboardJson(brlExpected: 100.0, brlReceived: 150.0),
      );
      final pct = (data.brl.yearToDateReceived / data.brl.yearToDateExpected)
          .clamp(0.0, 1.0);
      expect(pct, 1.0);
    });

    test('progress is 0.0 when expected is 0', () {
      final data = DashboardData.fromJson(
        _dashboardJson(brlExpected: 0, brlReceived: 0),
      );
      final pct =
          data.brl.yearToDateExpected > 0
              ? (data.brl.yearToDateReceived / data.brl.yearToDateExpected)
                  .clamp(0.0, 1.0)
              : 0.0;
      expect(pct, 0.0);
    });

    test('progress is clamped to 0.0 when received is negative', () {
      final data = DashboardData.fromJson(
        _dashboardJson(brlExpected: 100.0, brlReceived: -50.0),
      );
      final pct = (data.brl.yearToDateReceived / data.brl.yearToDateExpected)
          .clamp(0.0, 1.0);
      expect(pct, 0.0);
    });
  });

  // =========================================================================
  // 3. BarChart data — 12 groups × 2 bars
  // =========================================================================

  group('BarChart data', () {
    test('has 12 monthly groups for BRL', () {
      final data = DashboardData.fromJson(_dashboardJson());
      expect(data.brl.monthlyTotals.length, 12);
    });

    test('each monthly total has expected and received', () {
      final data = DashboardData.fromJson(
        _dashboardJson(brlExpected: 1200.0, brlReceived: 600.0),
      );
      for (final total in data.brl.monthlyTotals) {
        // Each month has both fields (even if zero).
        expect(total.expected, isA<double>());
        expect(total.received, isA<double>());
      }
    });

    test('monthly totals sum to yearToDate values', () {
      final data = DashboardData.fromJson(
        _dashboardJson(brlExpected: 1200.0, brlReceived: 600.0),
      );
      final sumExpected =
          data.brl.monthlyTotals.fold(0.0, (a, t) => a + t.expected);
      final sumReceived =
          data.brl.monthlyTotals.fold(0.0, (a, t) => a + t.received);

      expect(sumExpected, closeTo(data.brl.yearToDateExpected, 0.01));
      expect(sumReceived, closeTo(data.brl.yearToDateReceived, 0.01));
    });
  });

  // =========================================================================
  // 4. Outstanding rows — widget test
  // =========================================================================

  group('Outstanding row left border', () {
    testWidgets('outstanding patient row has error-color Container',
        (tester) async {
      // Dashboard is a desktop-first UI; set a realistic window size.
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final data = DashboardData.fromJson(_dashboardJson());
      await tester.pumpWidget(_makeApp(data));
      await tester.pumpAndSettle();

      // Ana Silva has hasOutstanding = true.
      // The _PatientRow widget renders a red Container(width:3) in a Stack.
      // We verify the outstanding patient's name is present.
      expect(find.text('Ana Silva'), findsOneWidget);

      // Find the error-colored Container(s) — there should be exactly one
      // for the outstanding patient.
      final colorScheme =
          Theme.of(tester.element(find.byType(DashboardScreen))).colorScheme;

      final redContainers = tester.widgetList<Container>(find.byType(Container)).where(
        (c) {
          final decoration = c.decoration;
          if (decoration is BoxDecoration) {
            return decoration.color == colorScheme.error;
          }
          return c.color == colorScheme.error;
        },
      ).toList();

      // At least one red container exists for the outstanding patient.
      expect(redContainers.length, greaterThan(0));
    });

    testWidgets('non-outstanding patient has no error-color left border',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final data = DashboardData.fromJson(
        _dashboardJson(
          patients: [
            {
              'id': 'p3',
              'name': 'Sem Dívida',
              'location': 'Brasil',
              'currency': 'BRL',
              'totalSessions': 4,
              'totalExpected': 400.0,
              'totalReceived': 400.0,
              'balance': 0.0,
              'hasOutstanding': false,
            },
          ],
        ),
      );
      await tester.pumpWidget(_makeApp(data));
      await tester.pumpAndSettle();

      expect(find.text('Sem Dívida'), findsOneWidget);

      final colorScheme =
          Theme.of(tester.element(find.byType(DashboardScreen))).colorScheme;

      // With no outstanding patients, no error-colored containers should exist
      // that are 3px wide (the left border accent).
      final redBorderContainers =
          tester.widgetList<Container>(find.byType(Container)).where((c) {
        return c.color == colorScheme.error && c.constraints?.maxWidth == 3.0;
      }).toList();

      expect(redBorderContainers, isEmpty);
    });
  });
}
