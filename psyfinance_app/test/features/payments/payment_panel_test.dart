import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:psyfinance_app/core/api_client.dart';
import 'package:psyfinance_app/features/payments/pagamentos_screen.dart';
import 'package:psyfinance_app/features/payments/payment_model.dart';
import 'package:psyfinance_app/features/payments/payment_panel_model.dart';
import 'package:psyfinance_app/features/payments/payment_panel_provider.dart';
import 'package:psyfinance_app/features/payments/payments_panel_repository.dart';
import 'package:psyfinance_app/features/payments/payments_provider.dart';
import 'package:psyfinance_app/features/payments/payments_repository.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

Map<String, dynamic> _patientJson(String id, String name,
        {String currency = 'BRL', String location = 'Brasil'}) =>
    {'id': id, 'name': name, 'location': location, 'currency': currency};

Map<String, dynamic> _srJson(String id,
        {int sessionCount = 4, double expectedAmount = 400.0}) =>
    {
      'id': id,
      'month': 3,
      'year': 2026,
      'sessionCount': sessionCount,
      'expectedAmount': expectedAmount,
    };

Map<String, dynamic> _payJson(String id,
        {double amountPaid = 0.0, String status = 'PENDENTE'}) =>
    {
      'id': id,
      'amountPaid': amountPaid,
      'status': status,
      'revenueShareAmount': null,
    };

PaymentPanel _makePanel({
  List<Map<String, dynamic>>? rows,
  Map<String, dynamic>? summaryOverride,
}) {
  final defaultRows = rows ??
      [
        {
          'patient': _patientJson('p1', 'Carlos Alves'),
          'sessionRecord': _srJson('sr1', expectedAmount: 800.0),
          'payment': _payJson('pay1', status: 'ATRASADO'),
        },
        {
          'patient': _patientJson('p2', 'Ana Borges'),
          'sessionRecord': _srJson('sr2', expectedAmount: 400.0),
          'payment': _payJson('pay2', amountPaid: 200.0, status: 'PARCIAL'),
        },
        {
          'patient': _patientJson('p3', 'Bia Costa'),
          'sessionRecord': _srJson('sr3', expectedAmount: 600.0),
          'payment': _payJson('pay3', status: 'PENDENTE'),
        },
        {
          'patient': _patientJson(
              'p4', 'Diego Faria',
              currency: 'EUR', location: 'Portugal'),
          'sessionRecord': _srJson('sr4', expectedAmount: 80.0),
          'payment': _payJson('pay4', amountPaid: 80.0, status: 'PAGO'),
        },
      ];

  final summary = summaryOverride ??
      {
        'BRL': {
          'totalExpected': 1800.0,
          'totalReceived': 200.0,
          'totalOutstanding': 1600.0,
          'countPaid': 0,
          'countPending': 3,
          'countOverdue': 1,
        },
        'EUR': {
          'totalExpected': 80.0,
          'totalReceived': 80.0,
          'totalOutstanding': 0.0,
          'countPaid': 1,
          'countPending': 0,
          'countOverdue': 0,
        },
      };

  return PaymentPanel.fromJson({'summary': summary, 'payments': defaultRows});
}

// ---------------------------------------------------------------------------
// Fake repositories
// ---------------------------------------------------------------------------

class _FakePanelRepo extends PaymentsPanelRepository {
  final PaymentPanel _panel;
  _FakePanelRepo(this._panel)
      : super(ApiClient(baseUrl: 'http://localhost:0'));

  @override
  Future<PaymentPanel> getPaymentPanel(int year, int month,
          {String status = 'all'}) async =>
      _panel;
}

class _FakePaymentsRepo extends PaymentsRepository {
  final Map<String, Payment> _responses;

  _FakePaymentsRepo(this._responses)
      : super(ApiClient(baseUrl: 'http://localhost:0'));

  @override
  Future<Payment> updatePayment(
      String sessionRecordId, double amountPaid) async {
    final data = _responses[sessionRecordId];
    if (data == null) throw Exception('Not found');
    return data;
  }
}

// ---------------------------------------------------------------------------
// Widget helper
// ---------------------------------------------------------------------------

Widget _makeApp(
  PaymentPanel panel, {
  PaymentsRepository? paymentsRepo,
}) {
  return ProviderScope(
    overrides: [
      paymentsPanelRepositoryProvider.overrideWith(
        (ref) => _FakePanelRepo(panel),
      ),
      if (paymentsRepo != null)
        paymentsRepositoryProvider.overrideWith((ref) => paymentsRepo),
    ],
    child: const MaterialApp(
      home: Scaffold(body: PagamentosScreen()),
    ),
  );
}

// ---------------------------------------------------------------------------
// Helper: create a container and await async _load() completion
// ---------------------------------------------------------------------------

Future<ProviderContainer> _makeContainer(PaymentPanel panel) async {
  final container = ProviderContainer(overrides: [
    paymentsPanelRepositoryProvider.overrideWith(
      (ref) => _FakePanelRepo(panel),
    ),
  ]);
  // Trigger provider creation
  container.read(paymentPanelProvider((year: 2026, month: 3)));
  // Allow async _load() microtask to complete
  await Future.delayed(Duration.zero);
  return container;
}

// ---------------------------------------------------------------------------
// 1. PaymentPanel.fromJson — unit tests
// ---------------------------------------------------------------------------

void main() {
  group('PaymentPanel.fromJson', () {
    test('parses summary for BRL and EUR', () {
      final panel = _makePanel();

      expect(panel.summary.containsKey('BRL'), isTrue);
      expect(panel.summary.containsKey('EUR'), isTrue);
      expect(panel.summary['BRL']!.totalExpected, 1800.0);
      expect(panel.summary['BRL']!.totalReceived, 200.0);
      expect(panel.summary['BRL']!.totalOutstanding, 1600.0);
      expect(panel.summary['BRL']!.countOverdue, 1);
      expect(panel.summary['EUR']!.countPaid, 1);
    });

    test('parses payments array correctly', () {
      final panel = _makePanel();

      expect(panel.payments.length, 4);
      expect(panel.payments[0].patient.name, 'Carlos Alves');
      expect(panel.payments[0].payment.status, 'ATRASADO');
      expect(panel.payments[1].payment.amountPaid, 200.0);
      expect(panel.payments[3].patient.currency, 'EUR');
    });

    test('PanelCurrencySummary.zero returns all zeroes', () {
      final z = PanelCurrencySummary.zero();
      expect(z.totalExpected, 0);
      expect(z.countPaid, 0);
      expect(z.countOverdue, 0);
    });

    test('PanelCurrencySummary addition works', () {
      const a = PanelCurrencySummary(
        totalExpected: 100,
        totalReceived: 50,
        totalOutstanding: 50,
        countPaid: 1,
        countPending: 0,
        countOverdue: 0,
      );
      const b = PanelCurrencySummary(
        totalExpected: 200,
        totalReceived: 0,
        totalOutstanding: 200,
        countPaid: 0,
        countPending: 1,
        countOverdue: 1,
      );
      final sum = a + b;
      expect(sum.totalExpected, 300);
      expect(sum.countPaid, 1);
      expect(sum.countOverdue, 1);
    });
  });

  // ---------------------------------------------------------------------------
  // 2. Sort order
  // ---------------------------------------------------------------------------

  group('Sort order', () {
    test('ATRASADO rows appear before PENDENTE before PARCIAL before PAGO',
        () async {
      // Panel with rows in reverse sort order
      final panel = _makePanel(rows: [
        {
          'patient': _patientJson('p4', 'Zara'),
          'sessionRecord': _srJson('sr4'),
          'payment': _payJson('pay4', amountPaid: 400.0, status: 'PAGO'),
        },
        {
          'patient': _patientJson('p3', 'Mia'),
          'sessionRecord': _srJson('sr3'),
          'payment': _payJson('pay3', amountPaid: 200.0, status: 'PARCIAL'),
        },
        {
          'patient': _patientJson('p1', 'Ana'),
          'sessionRecord': _srJson('sr1'),
          'payment': _payJson('pay1', status: 'PENDENTE'),
        },
        {
          'patient': _patientJson('p2', 'Bruno'),
          'sessionRecord': _srJson('sr2'),
          'payment': _payJson('pay2', status: 'ATRASADO'),
        },
      ]);

      final container = await _makeContainer(panel);
      addTearDown(container.dispose);

      // Mark Bruno (ATRASADO) as PAGO — should move to last group
      container
          .read(paymentPanelProvider((year: 2026, month: 3)).notifier)
          .updateRow('sr2', 400.0, 'PAGO');

      final rows = container
          .read(paymentPanelProvider((year: 2026, month: 3)))
          .value!
          .payments;

      // Sort order: PARCIAL(Mia) → PENDENTE(Ana) → PAGO(Bruno, Zara by alpha)
      expect(rows[0].payment.status, 'PARCIAL'); // Mia
      expect(rows[1].payment.status, 'PENDENTE'); // Ana
      expect(rows[2].patient.name, 'Bruno'); // PAGO, B < Z
      expect(rows[3].patient.name, 'Zara'); // PAGO
    });
  });

  // ---------------------------------------------------------------------------
  // 3. Status filter chips — widget tests
  // ---------------------------------------------------------------------------

  group('Status filter chips', () {
    testWidgets('shows all rows by default (Todos active)', (tester) async {
      await tester.pumpWidget(_makeApp(_makePanel()));
      await tester.pumpAndSettle();

      expect(find.text('Carlos Alves'), findsOneWidget);
      expect(find.text('Ana Borges'), findsOneWidget);
      expect(find.text('Bia Costa'), findsOneWidget);
      expect(find.text('Diego Faria'), findsOneWidget);
    });

    testWidgets('tapping Atrasado chip filters to only ATRASADO rows',
        (tester) async {
      await tester.pumpWidget(_makeApp(_makePanel()));
      await tester.pumpAndSettle();

      await tester.tap(find.textContaining('Atrasado ('));
      await tester.pumpAndSettle();

      expect(find.text('Carlos Alves'), findsOneWidget);
      expect(find.text('Ana Borges'), findsNothing);
      expect(find.text('Bia Costa'), findsNothing);
      expect(find.text('Diego Faria'), findsNothing);
    });

    testWidgets('chip count labels show counts from all rows', (tester) async {
      await tester.pumpWidget(_makeApp(_makePanel()));
      await tester.pumpAndSettle();

      expect(find.textContaining('Atrasado (1)'), findsOneWidget);
      expect(find.textContaining('Pendente (1)'), findsOneWidget);
      expect(find.textContaining('Parcial (1)'), findsOneWidget);
      expect(find.textContaining('Pago (1)'), findsOneWidget);
    });

    testWidgets('"Ver todos" button clears status filter', (tester) async {
      await tester.pumpWidget(_makeApp(_makePanel()));
      await tester.pumpAndSettle();

      // Apply Atrasado filter (on-screen chip) — only Carlos visible
      await tester.tap(find.textContaining('Atrasado ('));
      await tester.pumpAndSettle();

      expect(find.text('Carlos Alves'), findsOneWidget);
      expect(find.text('Ana Borges'), findsNothing);

      await tester.tap(find.textContaining('Todos ('));
      await tester.pumpAndSettle();

      expect(find.text('Carlos Alves'), findsOneWidget);
      expect(find.text('Ana Borges'), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // 4. Summary strip — widget tests
  // ---------------------------------------------------------------------------

  group('Summary strip', () {
    testWidgets('shows BRL and EUR cards', (tester) async {
      await tester.pumpWidget(_makeApp(_makePanel()));
      await tester.pumpAndSettle();

      expect(find.text('Real brasileiro'), findsOneWidget);
      expect(find.text('Euro'), findsOneWidget);
    });

    test('summary totals update after inline payment edit without full refetch',
        () async {
      final panel = _makePanel(rows: [
        {
          'patient': _patientJson('p1', 'Ana'),
          'sessionRecord': _srJson('sr1', expectedAmount: 400.0),
          'payment': _payJson('pay1', amountPaid: 0.0, status: 'PENDENTE'),
        },
      ], summaryOverride: {
        'BRL': {
          'totalExpected': 400.0,
          'totalReceived': 0.0,
          'totalOutstanding': 400.0,
          'countPaid': 0,
          'countPending': 1,
          'countOverdue': 0,
        },
        'EUR': {
          'totalExpected': 0.0,
          'totalReceived': 0.0,
          'totalOutstanding': 0.0,
          'countPaid': 0,
          'countPending': 0,
          'countOverdue': 0,
        },
      });

      final container = await _makeContainer(panel);
      addTearDown(container.dispose);

      container
          .read(paymentPanelProvider((year: 2026, month: 3)).notifier)
          .updateRow('sr1', 400.0, 'PAGO');

      final brl = container
          .read(paymentPanelProvider((year: 2026, month: 3)))
          .value!
          .summary['BRL']!;

      expect(brl.totalReceived, 400.0);
      expect(brl.totalOutstanding, 0.0);
      expect(brl.countPaid, 1);
      expect(brl.countPending, 0);
    });
  });

  // ---------------------------------------------------------------------------
  // 5. "Marcar como pago" and "Desfazer" — notifier unit tests
  // ---------------------------------------------------------------------------

  group('PaymentPanelNotifier.updateRow', () {
    test('"Marcar como pago" sets amountPaid = expectedAmount and status = PAGO',
        () async {
      final panel = _makePanel(rows: [
        {
          'patient': _patientJson('p1', 'Ana'),
          'sessionRecord': _srJson('sr1', expectedAmount: 400.0),
          'payment': _payJson('pay1', status: 'PENDENTE'),
        },
      ]);

      final container = await _makeContainer(panel);
      addTearDown(container.dispose);

      container
          .read(paymentPanelProvider((year: 2026, month: 3)).notifier)
          .updateRow('sr1', 400.0, 'PAGO');

      final row = container
          .read(paymentPanelProvider((year: 2026, month: 3)))
          .value!
          .payments
          .first;

      expect(row.payment.amountPaid, 400.0);
      expect(row.payment.status, 'PAGO');
    });

    test('"Desfazer" sets amountPaid = 0 and status = PENDENTE', () async {
      final panel = _makePanel(rows: [
        {
          'patient': _patientJson('p1', 'Ana'),
          'sessionRecord': _srJson('sr1', expectedAmount: 400.0),
          'payment': _payJson('pay1', amountPaid: 400.0, status: 'PAGO'),
        },
      ]);

      final container = await _makeContainer(panel);
      addTearDown(container.dispose);

      container
          .read(paymentPanelProvider((year: 2026, month: 3)).notifier)
          .updateRow('sr1', 0.0, 'PENDENTE');

      final row = container
          .read(paymentPanelProvider((year: 2026, month: 3)))
          .value!
          .payments
          .first;

      expect(row.payment.amountPaid, 0.0);
      expect(row.payment.status, 'PENDENTE');
    });

    test('updateRow does not affect other rows', () async {
      final container = await _makeContainer(_makePanel());
      addTearDown(container.dispose);

      container
          .read(paymentPanelProvider((year: 2026, month: 3)).notifier)
          .updateRow('sr1', 800.0, 'PAGO');

      final rows = container
          .read(paymentPanelProvider((year: 2026, month: 3)))
          .value!
          .payments;

      final updated = rows.firstWhere((r) => r.sessionRecord.id == 'sr1');
      expect(updated.payment.status, 'PAGO');

      final unchanged = rows.firstWhere((r) => r.sessionRecord.id == 'sr2');
      expect(unchanged.payment.status, 'PARCIAL');
    });
  });

  // ---------------------------------------------------------------------------
  // 6. computePanelSummaryFromRows — unit tests
  // ---------------------------------------------------------------------------

  group('computePanelSummaryFromRows', () {
    test('correctly aggregates totals by currency', () {
      final summary = computePanelSummaryFromRows(_makePanel().payments);

      expect(summary['BRL']!.totalExpected, 1800.0);
      expect(summary['BRL']!.totalReceived, 200.0);
      expect(summary['BRL']!.totalOutstanding, 1600.0);
      expect(summary['EUR']!.totalExpected, 80.0);
      expect(summary['EUR']!.totalReceived, 80.0);
      expect(summary['EUR']!.totalOutstanding, 0.0);
    });

    test('counts paid, pending (PARCIAL+PENDENTE), and overdue correctly', () {
      final summary = computePanelSummaryFromRows(_makePanel().payments);

      // BRL: ATRASADO(Carlos)=overdue, PARCIAL(Ana)=pending, PENDENTE(Bia)=pending
      expect(summary['BRL']!.countOverdue, 1);
      expect(summary['BRL']!.countPending, 2); // PARCIAL + PENDENTE
      expect(summary['BRL']!.countPaid, 0);

      // EUR: PAGO(Diego)
      expect(summary['EUR']!.countPaid, 1);
      expect(summary['EUR']!.countOverdue, 0);
    });
  });
}
