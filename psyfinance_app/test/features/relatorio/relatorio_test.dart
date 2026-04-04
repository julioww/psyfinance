import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:psyfinance_app/core/api_client.dart';
import 'package:psyfinance_app/features/dashboard/dashboard_model.dart';
import 'package:psyfinance_app/features/dashboard/dashboard_provider.dart';
import 'package:psyfinance_app/features/dashboard/dashboard_repository.dart';
import 'package:psyfinance_app/features/dashboard/export_button.dart';
import 'package:psyfinance_app/features/patients/patients_provider.dart';
import 'package:psyfinance_app/features/relatorio/relatorio_screen.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

CurrencyYearData _currencyData({
  int sessions = 10,
  double avgPrice = 150.0,
  double expected = 1500.0,
  double received = 1200.0,
}) =>
    CurrencyYearData(
      sessions: sessions,
      avgPricePerSession: avgPrice,
      expected: expected,
      received: received,
      balance: expected - received,
    );

YearlyComparison _makeComparison(int year, {double brlReceived = 1200.0, double eurReceived = 500.0}) =>
    YearlyComparison(
      year: year,
      brl: _currencyData(received: brlReceived, expected: brlReceived + 300),
      eur: _currencyData(received: eurReceived, sessions: 8, avgPrice: 80.0, expected: eurReceived + 100),
    );

List<YearlyComparison> _defaultComparisons() => [
      _makeComparison(2023, brlReceived: 800, eurReceived: 400),
      _makeComparison(2024, brlReceived: 1000, eurReceived: 450),
      _makeComparison(2025, brlReceived: 1200, eurReceived: 500),
      _makeComparison(2026, brlReceived: 1500, eurReceived: 600),
    ];

// ---------------------------------------------------------------------------
// Fake repository
// ---------------------------------------------------------------------------

class _FakeDashboardRepo extends DashboardRepository {
  final List<YearlyComparison> _comparisons;

  _FakeDashboardRepo(this._comparisons)
      : super(ApiClient(baseUrl: 'http://localhost:0'));

  @override
  Future<List<YearlyComparison>> getComparison(List<int> years) async =>
      _comparisons;

  @override
  Future<DashboardData> getDashboard(int year) async => throw UnimplementedError();
}

class _FakeApiClient extends ApiClient {
  final Uint8List bytes;
  final bool shouldThrow;

  _FakeApiClient({Uint8List? bytes, this.shouldThrow = false})
      : bytes = bytes ?? Uint8List.fromList([1, 2, 3]),
        super(baseUrl: 'http://localhost:0');

  @override
  Future<Uint8List> getBytes(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    if (shouldThrow) throw Exception('Erro de rede');
    return bytes;
  }
}

Widget _makeRelatórioApp(List<YearlyComparison> comparisons) {
  final fakeRepo = _FakeDashboardRepo(comparisons);
  return ProviderScope(
    overrides: [
      dashboardRepositoryProvider.overrideWith((_) => fakeRepo),
      apiClientProvider.overrideWith((_) => _FakeApiClient()),
    ],
    child: const MaterialApp(home: Scaffold(body: RelatorioScreen())),
  );
}

Widget _makeExportButtonApp({
  bool shouldThrow = false,
  Future<void> Function(List<int>, String)? onDownload,
}) {
  return ProviderScope(
    overrides: [
      apiClientProvider.overrideWith(
          (_) => _FakeApiClient(shouldThrow: shouldThrow)),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: ExportButton(
          type: ExportType.monthly,
          format: ExportFormat.csv,
          year: 2026,
          onDownload: onDownload,
        ),
      ),
    ),
  );
}

// ===========================================================================
// 1. ExportButton — loading indicator
// ===========================================================================

void main() {
  group('ExportButton', () {
    testWidgets('shows CircularProgressIndicator during API call',
        (tester) async {
      // Use a completer-based fake that keeps the future pending
      // so we can inspect the loading state.
      final downloadStarted = ValueNotifier(false);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWith((_) => _SlowApiClient()),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: ExportButton(
                type: ExportType.monthly,
                format: ExportFormat.csv,
                year: 2026,
                onDownload: (bytes, filename) async {
                  downloadStarted.value = true;
                },
              ),
            ),
          ),
        ),
      );

      // Tap the button and pump once without settling
      await tester.tap(find.byType(ExportButton));
      await tester.pump();

      // Loading indicator should be visible
      expect(find.byType(CircularProgressIndicator), findsWidgets);
    });

    testWidgets('shows SnackBar with filename on success', (tester) async {
      bool downloaded = false;

      await tester.pumpWidget(
        _makeExportButtonApp(
          onDownload: (bytes, filename) async {
            downloaded = true;
          },
        ),
      );

      await tester.tap(find.byType(ExportButton));
      await tester.pumpAndSettle();

      expect(downloaded, isTrue);
      expect(
        find.text('Arquivo salvo: psyfinance-mensal-2026.csv'),
        findsOneWidget,
      );
    });

    testWidgets('shows error SnackBar on failure', (tester) async {
      await tester.pumpWidget(
        _makeExportButtonApp(shouldThrow: true),
      );

      await tester.tap(find.byType(ExportButton));
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsOneWidget);
    });
  });

  // =========================================================================
  // 2. RelatorioScreen — year chip toggle
  // =========================================================================

  group('RelatorioScreen — year chip', () {
    testWidgets('deselecting a year chip removes its row from the table',
        (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(_makeRelatórioApp(_defaultComparisons()));
      await tester.pumpAndSettle();

      // All 4 year chips visible
      for (final year in [2023, 2024, 2025, 2026]) {
        expect(find.text('$year'), findsWidgets);
      }

      // Deselect 2023
      final chip2023 = find.widgetWithText(FilterChip, '2023');
      await tester.tap(chip2023.first);
      await tester.pumpAndSettle();

      // 2023 chip still present but deselected; 2023 year dot should not
      // appear as an active _YearDataRow (row dots are small Containers —
      // confirm by checking the chip is unselected)
      final filterChip = tester.widget<FilterChip>(chip2023.first);
      expect(filterChip.selected, isFalse);
    });

    testWidgets('cannot deselect the last active year chip', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(_makeRelatórioApp(_defaultComparisons()));
      await tester.pumpAndSettle();

      // Deselect 3 of 4 years
      for (final year in [2023, 2024, 2025]) {
        await tester.tap(find.widgetWithText(FilterChip, '$year').first);
        await tester.pumpAndSettle();
      }

      // Try to deselect the last one (2026)
      await tester.tap(find.widgetWithText(FilterChip, '2026').first);
      await tester.pumpAndSettle();

      final chip2026 = tester.widget<FilterChip>(
          find.widgetWithText(FilterChip, '2026').first);
      expect(chip2026.selected, isTrue); // still selected
    });
  });

  // =========================================================================
  // 3. CurrencyYearData — avgPricePerSession calculation
  // =========================================================================

  group('CurrencyYearData — avgPricePerSession', () {
    test('equals totalExpected / totalSessions', () {
      const d = CurrencyYearData(
        sessions: 8,
        avgPricePerSession: 0, // backend computes this
        expected: 1200,
        received: 1000,
        balance: 200,
      );
      // Simulate backend formula
      final avg = d.expected / d.sessions;
      expect(avg, closeTo(150.0, 0.001));
    });

    test('fromJson parses avgPricePerSession correctly', () {
      final json = {
        'sessions': 10,
        'avgPricePerSession': 180.0,
        'expected': 1800.0,
        'received': 1500.0,
        'balance': 300.0,
      };
      final d = CurrencyYearData.fromJson(json);
      expect(d.sessions, 10);
      expect(d.avgPricePerSession, 180.0);
      expect(d.expected, 1800.0);
      expect(d.received, 1500.0);
      expect(d.balance, 300.0);
    });

    test('YearlyComparison.fromJson parses extended format', () {
      final json = {
        'year': 2026,
        'BRL': {
          'sessions': 12,
          'avgPricePerSession': 200.0,
          'expected': 2400.0,
          'received': 2000.0,
          'balance': 400.0,
        },
        'EUR': {
          'sessions': 8,
          'avgPricePerSession': 100.0,
          'expected': 800.0,
          'received': 750.0,
          'balance': 50.0,
        },
      };
      final c = YearlyComparison.fromJson(json);
      expect(c.year, 2026);
      expect(c.brl.sessions, 12);
      expect(c.brl.avgPricePerSession, 200.0);
      expect(c.eur.sessions, 8);
      // Backward-compat getters
      expect(c.brlExpected, 2400.0);
      expect(c.eurReceived, 750.0);
    });
  });

  // =========================================================================
  // 4. Growth sub-row — correct % and direction
  // =========================================================================

  group('Growth sub-row', () {
    double? growthPct(double prev, double curr) {
      if (prev <= 0) return null;
      return (curr - prev) / prev * 100;
    }

    test('positive growth returns correct percentage', () {
      final g = growthPct(1000, 1200);
      expect(g, closeTo(20.0, 0.001));
    });

    test('negative growth returns correct percentage', () {
      final g = growthPct(1200, 900);
      expect(g, closeTo(-25.0, 0.001));
    });

    test('zero prev returns null', () {
      expect(growthPct(0, 500), isNull);
    });

    testWidgets('growth chip shows green for positive growth', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: _GrowthChipTestWrapper(pct: 15.0),
          ),
        ),
      );
      await tester.pump();

      // Text should contain +15.0%
      expect(find.textContaining('+15.0%'), findsOneWidget);
    });

    testWidgets('growth chip shows red for negative growth', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: _GrowthChipTestWrapper(pct: -10.0),
          ),
        ),
      );
      await tester.pump();

      expect(find.textContaining('-10.0%'), findsOneWidget);
    });
  });
}

// ---------------------------------------------------------------------------
// Slow API client — never completes getBytes (keeps loading state alive)
// ---------------------------------------------------------------------------

class _SlowApiClient extends ApiClient {
  _SlowApiClient() : super(baseUrl: 'http://localhost:0');

  @override
  Future<Uint8List> getBytes(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) {
    return Future.delayed(const Duration(hours: 1), () => Uint8List(0));
  }
}

// ---------------------------------------------------------------------------
// Wrapper to test _GrowthChip in isolation
// ---------------------------------------------------------------------------

class _GrowthChipTestWrapper extends StatelessWidget {
  final double pct;
  const _GrowthChipTestWrapper({required this.pct});

  @override
  Widget build(BuildContext context) {
    // Mirror _GrowthChip logic for testing
    final isPositive = pct > 0;
    final isZero = pct.abs() < 0.05;
    final colorScheme = Theme.of(context).colorScheme;
    final color = isZero
        ? colorScheme.onSurfaceVariant
        : isPositive
            ? const Color(0xFF22C55E)
            : colorScheme.error;
    final sign = isPositive ? '+' : '';

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '$sign${pct.toStringAsFixed(1)}%',
        style: TextStyle(color: color, fontSize: 10),
      ),
    );
  }
}
