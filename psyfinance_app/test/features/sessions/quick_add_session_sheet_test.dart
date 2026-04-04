import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:psyfinance_app/core/api_client.dart';
import 'package:psyfinance_app/features/monthly/monthly_provider.dart';
import 'package:psyfinance_app/features/monthly/monthly_repository.dart';
import 'package:psyfinance_app/features/monthly/monthly_view_model.dart';
import 'package:psyfinance_app/features/patients/patient_model.dart';
import 'package:psyfinance_app/features/patients/patients_provider.dart';
import 'package:psyfinance_app/features/sessions/quick_add_session_sheet.dart';
import 'package:psyfinance_app/features/sessions/session_record_model.dart';
import 'package:psyfinance_app/features/sessions/sessions_provider.dart';
import 'package:psyfinance_app/features/sessions/sessions_repository.dart';

// ---------------------------------------------------------------------------
// Fake patients
// ---------------------------------------------------------------------------

final _ana = Patient(
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

final _bruno = Patient(
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

final _inactivePatient = Patient(
  id: 'p-3',
  name: 'Carlos Dias',
  email: 'carlos@example.com',
  location: 'Brasil',
  status: PatientStatus.inativo,
  paymentModel: PaymentModel.sessao,
  currency: PatientCurrency.brl,
  currentRate: 100.0,
  createdAt: DateTime(2025, 1, 1),
  updatedAt: DateTime(2025, 1, 1),
);

// ---------------------------------------------------------------------------
// Fake sessions repository
// ---------------------------------------------------------------------------

class _FakeSessionsRepository implements SessionsRepository {
  int quickAddCallCount = 0;
  String? lastPatientId;
  DateTime? lastDate;
  final bool throwDuplicate;
  final bool throwGenericError;

  _FakeSessionsRepository({
    this.throwDuplicate = false,
    this.throwGenericError = false,
  });

  @override
  Future<SessionRecord?> getSession(
      String patientId, int year, int month) async => null;

  @override
  Future<SessionRecord> saveSession(
    String patientId,
    int year,
    int month,
    SaveSessionDto dto,
  ) async =>
      throw UnimplementedError();

  @override
  Future<SessionRecord> quickAddSession(
    String patientId,
    DateTime date, {
    String? observations,
  }) async {
    if (throwDuplicate) {
      throw const ApiException(
          statusCode: 409,
          message:
              'Já existe uma sessão registrada nesta data para este paciente.');
    }
    if (throwGenericError) {
      throw const ApiException(statusCode: 500, message: 'Erro interno');
    }
    quickAddCallCount++;
    lastPatientId = patientId;
    lastDate = date;
    return SessionRecord(
      id: 'rec-1',
      patientId: patientId,
      year: date.year,
      month: date.month,
      sessionDates: [
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}'
      ],
      sessionCount: 1,
      expectedAmount: 150.0,
      observations: observations,
      isReposicao: false,
      payment: const SessionPayment(
          id: 'pay-1', amountPaid: 0, status: 'PENDENTE'),
      createdAt: DateTime(2026, 4, 1),
      updatedAt: DateTime(2026, 4, 1),
    );
  }
}

// ---------------------------------------------------------------------------
// Fake patients notifier
// ---------------------------------------------------------------------------

class _FakePatientsNotifier extends AsyncNotifier<List<Patient>> {
  final List<Patient> patients;
  _FakePatientsNotifier(this.patients);

  @override
  Future<List<Patient>> build() async => patients;
}

// ---------------------------------------------------------------------------
// Fake monthly repository (for refresh-after-save test)
// ---------------------------------------------------------------------------

class _FakeMonthlyRepository implements MonthlyRepository {
  int loadCount = 0;

  @override
  Future<MonthlyView> getMonthlyView(int year, int month) async {
    loadCount++;
    return MonthlyView(patients: const [], summary: const {});
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const _testArgs = (year: 2026, month: 4);

Future<void> _pump(
  WidgetTester tester,
  List<Patient> patients, {
  bool throwDuplicate = false,
  bool throwGenericError = false,
  _FakeMonthlyRepository? monthlyRepo,
}) async {
  final fakeRepo = _FakeSessionsRepository(
    throwDuplicate: throwDuplicate,
    throwGenericError: throwGenericError,
  );
  final fakeMonthly = monthlyRepo ?? _FakeMonthlyRepository();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sessionsRepositoryProvider.overrideWithValue(fakeRepo),
        patientsProvider.overrideWith(() => _FakePatientsNotifier(patients)),
        monthlyRepositoryProvider.overrideWithValue(fakeMonthly),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => TextButton(
              onPressed: () => showQuickAddSessionSheet(
                ctx,
                args: _testArgs,
                onSaved: (_, __) {},
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _openSheet(WidgetTester tester) async {
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

/// Selects a patient from the DropdownMenu by tapping the field and then
/// tapping the entry with [name].
Future<void> _selectPatient(WidgetTester tester, String name) async {
  // Tap the DropdownMenu field to open the dropdown
  final dropdown = find.byType(DropdownMenu<Patient>);
  await tester.tap(dropdown);
  await tester.pumpAndSettle();
  // Tap the entry in the list
  await tester.tap(find.text(name).last);
  await tester.pumpAndSettle();
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('QuickAddSessionSheet', () {
    testWidgets('shows today\'s date pre-filled on open', (tester) async {
      await _pump(tester, [_ana]);
      await _openSheet(tester);

      final today = DateTime.now();
      final padDay = today.day.toString().padLeft(2, '0');
      final padMonth = today.month.toString().padLeft(2, '0');
      final dateStr = '$padDay/$padMonth/${today.year}';

      expect(find.text(dateStr), findsOneWidget);
    });

    testWidgets('patient list shows only active patients sorted alphabetically',
        (tester) async {
      await _pump(tester, [_bruno, _ana, _inactivePatient]);
      await _openSheet(tester);

      // Open the dropdown
      await tester.tap(find.byType(DropdownMenu<Patient>));
      await tester.pumpAndSettle();

      // Active patients are present
      expect(find.text('Ana Santos'), findsWidgets);
      expect(find.text('Bruno Lima'), findsWidgets);
      // Inactive patient must not appear
      expect(find.text('Carlos Dias'), findsNothing);

      // Alphabetical order: Ana before Bruno
      final anaPos = tester.getTopLeft(find.text('Ana Santos').last).dy;
      final brunoPos = tester.getTopLeft(find.text('Bruno Lima').last).dy;
      expect(anaPos, lessThan(brunoPos));
    });

    testWidgets('saving calls quickAddSession with correct patientId and date',
        (tester) async {
      final fakeRepo = _FakeSessionsRepository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionsRepositoryProvider.overrideWithValue(fakeRepo),
            patientsProvider
                .overrideWith(() => _FakePatientsNotifier([_ana])),
            monthlyRepositoryProvider
                .overrideWithValue(_FakeMonthlyRepository()),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (ctx) => TextButton(
                  onPressed: () => showQuickAddSessionSheet(
                    ctx,
                    args: _testArgs,
                    onSaved: (_, __) {},
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await _openSheet(tester);
      await _selectPatient(tester, 'Ana Santos');

      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();

      expect(fakeRepo.quickAddCallCount, 1);
      expect(fakeRepo.lastPatientId, 'p-1');
      final today = DateTime.now();
      expect(fakeRepo.lastDate!.year, today.year);
      expect(fakeRepo.lastDate!.month, today.month);
      expect(fakeRepo.lastDate!.day, today.day);
    });

    testWidgets(
        'on success monthlyViewProvider is refreshed and sheet closes',
        (tester) async {
      final fakeMonthly = _FakeMonthlyRepository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionsRepositoryProvider
                .overrideWithValue(_FakeSessionsRepository()),
            patientsProvider
                .overrideWith(() => _FakePatientsNotifier([_ana])),
            monthlyRepositoryProvider.overrideWithValue(fakeMonthly),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (ctx) => TextButton(
                  onPressed: () => showQuickAddSessionSheet(
                    ctx,
                    args: _testArgs,
                    onSaved: (_, __) {},
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await _openSheet(tester);
      // Monthly view loads once on open (via the notifier)
      final loadsBefore = fakeMonthly.loadCount;

      await _selectPatient(tester, 'Ana Santos');
      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();

      // Sheet should be dismissed
      expect(find.text('Salvar'), findsNothing);
      // Monthly repo should have been called again for the refresh
      expect(fakeMonthly.loadCount, greaterThan(loadsBefore));
    });

    testWidgets(
        'duplicate date error shows inline message and keeps sheet open',
        (tester) async {
      await _pump(tester, [_ana], throwDuplicate: true);
      await _openSheet(tester);
      await _selectPatient(tester, 'Ana Santos');

      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();

      // Inline error below date field
      expect(
        find.text(
            'Já existe uma sessão registrada nesta data para este paciente.'),
        findsOneWidget,
      );
      // Sheet still open
      expect(find.text('Salvar'), findsOneWidget);
    });

    testWidgets('live preview updates when patient changes', (tester) async {
      await _pump(tester, [_ana, _bruno]);
      await _openSheet(tester);

      // Before patient selection: preview shows "—"
      expect(find.text('—'), findsOneWidget);

      // Select SESSAO patient
      await _selectPatient(tester, 'Ana Santos');
      expect(find.textContaining('Ana Santos'), findsWidgets);
      expect(find.textContaining('por sessão'), findsOneWidget);
    });

    testWidgets(
        'MENSAL patient preview shows "Mensal (não altera valor)"',
        (tester) async {
      await _pump(tester, [_bruno]);
      await _openSheet(tester);
      await _selectPatient(tester, 'Bruno Lima');

      expect(find.textContaining('Mensal (não altera valor)'), findsOneWidget);
    });
  });
}
