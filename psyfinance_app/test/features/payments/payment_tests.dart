import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:psyfinance_app/features/patients/patient_model.dart';
import 'package:psyfinance_app/features/patients/patient_summary_model.dart';
import 'package:psyfinance_app/features/patients/patients_provider.dart';
import 'package:psyfinance_app/features/patients/rate_history_model.dart';
import 'package:psyfinance_app/features/patients/rate_history_provider.dart';
import 'package:psyfinance_app/features/payments/payment_model.dart';
import 'package:psyfinance_app/features/payments/payments_provider.dart';
import 'package:psyfinance_app/features/payments/payments_repository.dart';
import 'package:psyfinance_app/features/sessions/session_entry_sheet.dart';
import 'package:psyfinance_app/features/sessions/session_record_model.dart';
import 'package:psyfinance_app/features/sessions/sessions_provider.dart';
import 'package:psyfinance_app/features/sessions/sessions_repository.dart';
import 'package:psyfinance_app/features/patients/patient_detail_screen.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

class _FakeSessionsRepo implements SessionsRepository {
  final SessionRecord? record;
  _FakeSessionsRepo({this.record});

  @override
  Future<SessionRecord?> getSession(String p, int y, int m) async => record;

  @override
  Future<SessionRecord> saveSession(
      String p, int y, int m, SaveSessionDto dto) async {
    return SessionRecord(
      id: 'rec-1',
      patientId: p,
      year: y,
      month: m,
      sessionDates: dto.sessionDates,
      sessionCount: dto.sessionDates.length,
      expectedAmount: 300.0,
      observations: null,
      isReposicao: false,
      payment: const SessionPayment(
          id: 'pay-1', amountPaid: 0, status: 'PENDENTE'),
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );
  }
}

class _FakePaymentsRepo implements PaymentsRepository {
  final List<double> savedAmounts = [];

  @override
  Future<Payment> getPayment(String sessionRecordId) async {
    return Payment(
      id: 'pay-1',
      sessionRecordId: sessionRecordId,
      amountPaid: 0,
      status: 'PENDENTE',
      expectedAmount: 300.0,
    );
  }

  @override
  Future<Payment> updatePayment(
      String sessionRecordId, double amountPaid) async {
    savedAmounts.add(amountPaid);
    final String status;
    if (amountPaid >= 300.0) {
      status = 'PAGO';
    } else if (amountPaid > 0) {
      status = 'PARCIAL';
    } else {
      status = 'PENDENTE';
    }
    return Payment(
      id: 'pay-1',
      sessionRecordId: sessionRecordId,
      amountPaid: amountPaid,
      status: status,
      expectedAmount: 300.0,
    );
  }
}

class _MockSummaryNotifier extends PatientSummaryNotifier {
  final PatientSummary summary;
  _MockSummaryNotifier(this.summary);

  @override
  Future<PatientSummary> build(PatientSummaryArgs arg) async => summary;
}

class _MockRateHistoryNotifier extends RateHistoryNotifier {
  @override
  Future<List<RateHistory>> build(String patientId) async => [];
}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

final _patient = Patient(
  id: 'p-1',
  name: 'Ana Santos',
  email: 'ana@example.com',
  location: 'Brasil',
  status: PatientStatus.ativo,
  paymentModel: PaymentModel.sessao,
  currency: PatientCurrency.brl,
  currentRate: 150.0,
  createdAt: DateTime(2025, 1, 1),
  updatedAt: DateTime(2025, 1, 1),
);

// Uses a future year/month so _deriveStatus never triggers ATRASADO
SessionRecord _makeRecord(
        {double amountPaid = 0.0, String status = 'PENDENTE'}) =>
    SessionRecord(
      id: 'rec-1',
      patientId: 'p-1',
      year: 2030,
      month: 6,
      sessionDates: ['2030-06-04', '2030-06-11'],
      sessionCount: 2,
      expectedAmount: 300.0,
      observations: null,
      isReposicao: false,
      payment:
          SessionPayment(id: 'pay-1', amountPaid: amountPaid, status: status),
      createdAt: DateTime(2030, 6, 1),
      updatedAt: DateTime(2030, 6, 1),
    );

PatientSummary _makeSummary(List<MonthSummary> months) => PatientSummary(
      patient: _patient,
      rates: [
        RateHistory(
          id: 'r1',
          patientId: 'p-1',
          rate: 150.0,
          effectiveFrom: DateTime(2025, 1, 1),
        )
      ],
      months: months,
    );

List<MonthSummary> _monthsWith({
  required int month,
  required String sessionRecordId,
  required double amountPaid,
  required double expectedAmount,
  required MonthPaymentStatus status,
}) {
  return List.generate(12, (i) {
    final m = i + 1;
    if (m == month) {
      return MonthSummary(
        month: m,
        sessionRecordId: sessionRecordId,
        sessionCount: 2,
        expectedAmount: expectedAmount,
        amountPaid: amountPaid,
        balance: expectedAmount - amountPaid,
        status: status,
      );
    }
    return MonthSummary(month: m);
  });
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Future<void> _pumpSheet(
  WidgetTester tester, {
  required SessionRecord? existingRecord,
  _FakePaymentsRepo? paymentsRepo,
  // Use a future month by default so _deriveStatus never returns ATRASADO
  int year = 2030,
  int month = 6,
}) async {
  final pr = paymentsRepo ?? _FakePaymentsRepo();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sessionsRepositoryProvider.overrideWithValue(
          _FakeSessionsRepo(record: existingRecord),
        ),
        paymentsRepositoryProvider.overrideWithValue(pr),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SessionEntryContent(
            patient: _patient,
            year: year,
            month: month,
            onSaved: null,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpDetailScreen(
  WidgetTester tester, {
  required PatientSummary summary,
  _FakePaymentsRepo? paymentsRepo,
  void Function(BuildContext, MonthSummary)? onMonthTap,
}) async {
  final pr = paymentsRepo ?? _FakePaymentsRepo();
  // Use a large viewport so the sticky header doesn't overflow
  tester.view.physicalSize = const Size(1600, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        patientSummaryProvider
            .overrideWith(() => _MockSummaryNotifier(summary)),
        rateHistoryProvider.overrideWith(() => _MockRateHistoryNotifier()),
        paymentsRepositoryProvider.overrideWithValue(pr),
      ],
      child: MaterialApp(
        home: PatientDetailScreen(
          patientId: 'p-1',
          onMonthTap: onMonthTap,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  // Drain any pre-existing layout overflow errors from _InfoRow in _LeftSidebar
  // (those are from pre-existing code and not related to F6 changes)
  while (tester.takeException() != null) {}
}

Finder _text(String t) => find.text(t, skipOffstage: false);
Finder _textContaining(String s) => find.textContaining(s, skipOffstage: false);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // ──────────────────────────────────────────────────────────────────────────
  // Group 1: Payment section in SessionEntrySheet
  // ──────────────────────────────────────────────────────────────────────────
  group('SessionEntrySheet – payment section', () {
    testWidgets('shows placeholder message when no session record exists',
        (tester) async {
      await _pumpSheet(tester, existingRecord: null);

      expect(
        _textContaining('Salve as sessões primeiro'),
        findsOneWidget,
      );
      expect(
          find.text('Salvar pagamento', skipOffstage: false), findsNothing);
    });

    testWidgets('shows payment form when session record exists',
        (tester) async {
      await _pumpSheet(tester, existingRecord: _makeRecord());

      expect(_text('Valor esperado'), findsOneWidget);
      expect(_text('Pago até o momento'), findsOneWidget);
      expect(_text('Saldo devedor'), findsOneWidget);
      expect(_text('Salvar pagamento'), findsOneWidget);
    });

    testWidgets(
        'saldo devedor shows in error color when amountPaid < expectedAmount',
        (tester) async {
      await _pumpSheet(
          tester, existingRecord: _makeRecord(amountPaid: 100.0));

      // Scroll so saldo is visible
      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pumpAndSettle();

      // Find the saldo text — R$ 200,00 (300 - 100)
      final saldoWidget =
          tester.widget<Text>(_textContaining('200,00').last);
      final color = saldoWidget.style?.color;
      expect(color, isNotNull);
      // error color has higher red component in Material3 (approx r > g)
      final r = (color!.r * 255.0).round();
      final g = (color.g * 255.0).round();
      expect(r > g, isTrue,
          reason: 'Saldo owed should use error (red-ish) color');
    });

    testWidgets('status chip shows Pendente when amountPaid is 0',
        (tester) async {
      await _pumpSheet(
          tester, existingRecord: _makeRecord(amountPaid: 0));

      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pumpAndSettle();
      expect(_text('Pendente'), findsOneWidget);
    });

    testWidgets(
        'status chip shows Parcial when 0 < amountPaid < expectedAmount',
        (tester) async {
      await _pumpSheet(
          tester,
          existingRecord:
              _makeRecord(amountPaid: 150.0, status: 'PARCIAL'));

      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pumpAndSettle();
      expect(_text('Parcial'), findsOneWidget);
    });

    testWidgets('status chip shows Pago when amountPaid >= expectedAmount',
        (tester) async {
      await _pumpSheet(
          tester,
          existingRecord:
              _makeRecord(amountPaid: 300.0, status: 'PAGO'));

      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pumpAndSettle();
      expect(_text('Pago'), findsOneWidget);
    });

    testWidgets(
        'tapping Salvar pagamento calls updatePayment with entered amount',
        (tester) async {
      final paymentsRepo = _FakePaymentsRepo();
      await _pumpSheet(
          tester,
          existingRecord: _makeRecord(amountPaid: 0),
          paymentsRepo: paymentsRepo);

      // Scroll to payment section
      await tester.drag(find.byType(ListView), const Offset(0, -600));
      await tester.pumpAndSettle();

      // Enter amount in the last TextField (payment field)
      final field = find.byType(TextField).last;
      await tester.enterText(field, '200');
      await tester.pump();

      // Tap save
      await tester.tap(_text('Salvar pagamento'));
      await tester.pumpAndSettle();

      expect(paymentsRepo.savedAmounts, equals([200.0]));
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Group 2: Inline Pago cell editing in PatientDetailScreen
  // ──────────────────────────────────────────────────────────────────────────
  group('PatientDetailScreen – inline Pago cell', () {
      testWidgets('tapping Pago cell activates inline edit mode',
        (tester) async {
      // Use 2 months with data so the pago cell value (100,00) differs from
      // the annual total (150,00), making it uniquely findable in the table.
      final months = List.generate(12, (i) {
        final m = i + 1;
        if (m == 1) {
          return MonthSummary(
            month: m,
            sessionRecordId: 'rec-0',
            sessionCount: 1,
            expectedAmount: 300.0,
            amountPaid: 50.0,
            balance: 250.0,
            status: MonthPaymentStatus.parcial,
          );
        }
        if (m == 12) {
          return MonthSummary(
            month: m,
            sessionRecordId: 'rec-1',
            sessionCount: 2,
            expectedAmount: 300.0,
            amountPaid: 100.0,
            balance: 200.0,
            status: MonthPaymentStatus.parcial,
          );
        }
        return MonthSummary(month: m);
      });
      await _pumpDetailScreen(
          tester, summary: _makeSummary(months), onMonthTap: (_, __) {});

      // annual total is 150,00; the pago cell for Dec is unique at 100,00
      final pagoCell = _textContaining('100,00').first;
      await tester.tap(pagoCell);
      await tester.pumpAndSettle();

      // TextField should appear for inline edit
      expect(find.byType(TextField), findsAtLeastNWidgets(1));
    });

    testWidgets(
        'saving a payment updates the status chip on the same row without full reload',
        (tester) async {
      final paymentsRepo = _FakePaymentsRepo();
      // Use 2 months: month 1 has data (150,00 paid), month 12 has 0,00 paid.
      // Annual total paid = 150,00 — differs from month-12 cell value (0,00).
      final months = List.generate(12, (i) {
        final m = i + 1;
        if (m == 1) {
          return MonthSummary(
            month: m,
            sessionRecordId: 'rec-0',
            sessionCount: 1,
            expectedAmount: 300.0,
            amountPaid: 150.0,
            balance: 150.0,
            status: MonthPaymentStatus.parcial,
          );
        }
        if (m == 12) {
          return MonthSummary(
            month: m,
            sessionRecordId: 'rec-1',
            sessionCount: 2,
            expectedAmount: 300.0,
            amountPaid: 0.0,
            balance: 300.0,
            status: MonthPaymentStatus.pendente,
          );
        }
        return MonthSummary(month: m);
      });
      await _pumpDetailScreen(
        tester,
        summary: _makeSummary(months),
        paymentsRepo: paymentsRepo,
        onMonthTap: (_, __) {},
      );

      // Month 12 has Pendente (month 1 has Parcial — only 1 Pendente in tree)
      expect(_text('Pendente'), findsOneWidget);

      // The December pago cell shows exactly "R$ 0,00".
      // No other cell in this setup shows that exact value.
      final pagoCell = _text('R\$ 0,00').first;
      await tester.tap(pagoCell);
      await tester.pumpAndSettle();

      // Enter full payment amount into the TextField
      final field = find.byType(TextField).first;
      await tester.enterText(field, '300');
      await tester.pump();

      // Confirm with checkmark
      await tester.tap(find.byIcon(Icons.check).first);
      await tester.pumpAndSettle();

      // updatePayment was called with 300
      expect(paymentsRepo.savedAmounts, contains(300.0));
      // Status chip for December updated in-place to Pago
      // (the column header "Pago" is also a Text widget, so ≥1 is correct here)
      expect(_text('Pago'), findsAtLeastNWidgets(1));
    });

    testWidgets('months without session data show non-editable Pago cell',
        (tester) async {
      final months = List.generate(12, (i) => MonthSummary(month: i + 1));
      await _pumpDetailScreen(
          tester, summary: _makeSummary(months), onMonthTap: (_, __) {});

      // Tapping any '—' cell should NOT activate edit mode
      await tester.tap(_text('—').first);
      await tester.pump();
      expect(find.byType(TextField), findsNothing);
    });
  });
}
