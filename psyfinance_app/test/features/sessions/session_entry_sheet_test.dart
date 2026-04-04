import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:psyfinance_app/core/api_client.dart';
import 'package:psyfinance_app/features/patients/patient_model.dart';
import 'package:psyfinance_app/features/sessions/session_entry_sheet.dart';
import 'package:psyfinance_app/features/sessions/session_record_model.dart';
import 'package:psyfinance_app/features/sessions/sessions_provider.dart';
import 'package:psyfinance_app/features/sessions/sessions_repository.dart';

// ---------------------------------------------------------------------------
// Fake repository
// ---------------------------------------------------------------------------

class _FakeRepository implements SessionsRepository {
  final SessionRecord? existing;
  final bool throwOn400;

  _FakeRepository({this.existing, this.throwOn400 = false});

  @override
  Future<SessionRecord?> getSession(
      String patientId, int year, int month) async {
    return existing;
  }

  @override
  Future<SessionRecord> saveSession(
    String patientId,
    int year,
    int month,
    SaveSessionDto dto,
  ) async {
    if (throwOn400) {
      throw const ApiException(
          statusCode: 400, message: 'Data fora do mês especificado');
    }
    return SessionRecord(
      id: 'rec-1',
      patientId: patientId,
      year: year,
      month: month,
      sessionDates: dto.sessionDates,
      sessionCount: dto.sessionDates.length,
      expectedAmount: dto.sessionDates.length * 150.0,
      observations: dto.observations,
      isReposicao: dto.isReposicao,
      payment: const SessionPayment(
          id: 'pay-1', amountPaid: 0, status: 'PENDENTE'),
      createdAt: DateTime(2026, 3, 1),
      updatedAt: DateTime(2026, 3, 1),
    );
  }
}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

final _sessaoPatient = Patient(
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

final _mensalPatient = Patient(
  id: 'p-2',
  name: 'Bruno Lima',
  email: 'bruno@example.com',
  location: 'Brasil',
  status: PatientStatus.ativo,
  paymentModel: PaymentModel.mensal,
  currency: PatientCurrency.brl,
  currentRate: 800.0,
  createdAt: DateTime(2025, 1, 1),
  updatedAt: DateTime(2025, 1, 1),
);

SessionRecord _makeRecord(List<String> dates) => SessionRecord(
      id: 'rec-0',
      patientId: 'p-1',
      year: 2026,
      month: 3,
      sessionDates: dates,
      sessionCount: dates.length,
      expectedAmount: dates.length * 150.0,
      observations: null,
      isReposicao: false,
      payment:
          const SessionPayment(id: 'pay-0', amountPaid: 0, status: 'PENDENTE'),
      createdAt: DateTime(2026, 3, 1),
      updatedAt: DateTime(2026, 3, 1),
    );

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Future<void> _pumpContent(
  WidgetTester tester,
  Patient patient, {
  SessionRecord? existingRecord,
  bool throwOn400 = false,
  VoidCallback? onSaved,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sessionsRepositoryProvider.overrideWithValue(
          _FakeRepository(
            existing: existingRecord,
            throwOn400: throwOn400,
          ),
        ),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SessionEntryContent(
            patient: patient,
            year: 2026,
            month: 3,
            onSaved: onSaved,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Finds text anywhere in the tree, including items scrolled outside the
/// visible viewport within a ListView.
Finder _text(String text) => find.text(text, skipOffstage: false);

/// Finds text containing [substring] anywhere in the tree.
Finder _textContaining(String substring) =>
    find.textContaining(substring, skipOffstage: false);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('SessionEntrySheet', () {
    testWidgets('mini calendar toggles dates and updates session count text',
        (tester) async {
      await _pumpContent(tester, _sessaoPatient);

      // Initially 0 sessions — live total reflects 0 × rate
      expect(_text('0 sessões × R\$ 150,00 = R\$ 0,00'), findsOneWidget);

      // Tap day 4 in the calendar grid (on-stage, first rows are visible)
      await tester.tap(find.text('4').first);
      await tester.pump();
      expect(_text('1 sessão × R\$ 150,00 = R\$ 150,00'), findsOneWidget);

      // Tap day 11
      await tester.tap(find.text('11').first);
      await tester.pump();
      expect(_text('2 sessões × R\$ 150,00 = R\$ 300,00'), findsOneWidget);

      // Deselect day 4
      await tester.tap(find.text('4').first);
      await tester.pump();
      expect(_text('1 sessão × R\$ 150,00 = R\$ 150,00'), findsOneWidget);
    });

    testWidgets(
        'MENSAL patient shows fixed amount regardless of days selected',
        (tester) async {
      await _pumpContent(tester, _mensalPatient);

      expect(_text('Mensal — R\$ 800,00 (fixo)'), findsOneWidget);

      // Select several days — text must remain unchanged
      await tester.tap(find.text('5').first);
      await tester.pump();
      await tester.tap(find.text('12').first);
      await tester.pump();
      await tester.tap(find.text('19').first);
      await tester.pump();

      expect(_text('Mensal — R\$ 800,00 (fixo)'), findsOneWidget);
    });

    testWidgets(
        'saving when API returns 400 shows error message without closing sheet',
        (tester) async {
      await _pumpContent(tester, _sessaoPatient, throwOn400: true);

      // Select a day so there is something to save
      await tester.tap(find.text('7').first);
      await tester.pump();

      // Drag the list up to reveal the save button, then tap it
      await tester.drag(find.byType(ListView), const Offset(0, -600));
      await tester.pumpAndSettle();
      await tester.tap(_text('Salvar sessões'));
      await tester.pumpAndSettle();

      // Error message shown
      expect(_textContaining('Data fora do mês especificado'), findsOneWidget);
      // Sheet still present
      expect(_text('Salvar sessões'), findsOneWidget);
    });

    testWidgets('existing session dates pre-populate the calendar on open',
        (tester) async {
      final record = _makeRecord(['2026-03-04', '2026-03-11']);
      await _pumpContent(tester, _sessaoPatient, existingRecord: record);

      // Live total reflects the 2 pre-loaded sessions
      expect(_text('2 sessões × R\$ 150,00 = R\$ 300,00'), findsOneWidget);

      // Chips for the pre-populated dates are visible (anywhere in tree)
      expect(_text('04/03'), findsOneWidget);
      expect(_text('11/03'), findsOneWidget);
    });
  });
}
