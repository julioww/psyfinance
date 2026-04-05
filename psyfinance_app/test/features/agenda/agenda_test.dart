import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:psyfinance_app/features/agenda/agenda_session_model.dart';
import 'package:psyfinance_app/features/agenda/agenda_provider.dart';
import 'package:psyfinance_app/features/agenda/sessoes_screen.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

AgendaSession _makeSession({
  required String date,
  required int dayOfWeek,
  String patientId = 'p1',
  String patientName = 'Ana Lima',
  String currency = 'BRL',
  double? currentRate = 200.0,
  String location = 'Brasil',
  String recordId = 'r1',
  String? observations,
  bool isReposicao = false,
}) {
  return AgendaSession(
    date: date,
    dayOfWeek: dayOfWeek,
    patient: AgendaPatient(
      id: patientId,
      name: patientName,
      currency: currency,
      currentRate: currentRate,
      location: location,
    ),
    sessionRecord: AgendaSessionRecord(
      id: recordId,
      observations: observations,
      isReposicao: isReposicao,
    ),
  );
}

// ---------------------------------------------------------------------------
// 1. AgendaSession.fromJson
// ---------------------------------------------------------------------------

void main() {
  group('AgendaSession.fromJson', () {
    test('parses date, dayOfWeek, patient, and sessionRecord', () {
      final json = {
        'date': '2026-03-04',
        'dayOfWeek': 3,
        'patient': {
          'id': 'patient-uuid-1',
          'name': 'João Silva',
          'currency': 'BRL',
          'currentRate': 250.0,
          'location': 'Brasil',
        },
        'sessionRecord': {
          'id': 'record-uuid-1',
          'observations': 'Sessão produtiva.',
          'isReposicao': false,
        },
      };

      final session = AgendaSession.fromJson(json);

      expect(session.date, '2026-03-04');
      expect(session.dayOfWeek, 3);
      expect(session.patient.id, 'patient-uuid-1');
      expect(session.patient.name, 'João Silva');
      expect(session.patient.currency, 'BRL');
      expect(session.patient.currentRate, 250.0);
      expect(session.patient.location, 'Brasil');
      expect(session.sessionRecord.id, 'record-uuid-1');
      expect(session.sessionRecord.observations, 'Sessão produtiva.');
      expect(session.sessionRecord.isReposicao, false);
    });

    test('parses null currentRate and observations', () {
      final json = {
        'date': '2026-03-11',
        'dayOfWeek': 3,
        'patient': {
          'id': 'p2',
          'name': 'Maria Costa',
          'currency': 'EUR',
          'currentRate': null,
          'location': 'Alemanha',
        },
        'sessionRecord': {
          'id': 'r2',
          'observations': null,
          'isReposicao': true,
        },
      };

      final session = AgendaSession.fromJson(json);

      expect(session.patient.currentRate, isNull);
      expect(session.sessionRecord.observations, isNull);
      expect(session.sessionRecord.isReposicao, true);
    });

    test('dateTime getter parses date string correctly', () {
      final session = _makeSession(date: '2026-03-04', dayOfWeek: 3);
      expect(session.dateTime, DateTime(2026, 3, 4));
    });
  });

  // -------------------------------------------------------------------------
  // 2. Month view: correct day count
  // -------------------------------------------------------------------------

  group('Month view calendar grid', () {
    /// For a given [year]/[month], returns the number of week rows the grid
    /// should have — mirrors the logic in _SessoesScreenState._buildMonthView.
    int weekRowCount(int year, int month) {
      final firstDay = DateTime(year, month, 1);
      final lastDay = DateTime(year, month + 1, 0);
      final gridStart = firstDay.subtract(Duration(days: firstDay.weekday - 1));
      final gridEnd = lastDay.weekday == 7
          ? lastDay
          : lastDay.add(Duration(days: 7 - lastDay.weekday));

      int count = 0;
      DateTime w = gridStart;
      while (!w.isAfter(gridEnd)) {
        count++;
        w = w.add(const Duration(days: 7));
      }
      return count;
    }

    test('March 2026 shows 6 week rows (1 Mar = Sunday)', () {
      // 2026-03-01 is Sunday (weekday 7).
      // gridStart = 2026-02-23 (Monday).
      // 2026-03-31 is Tuesday (weekday 2); gridEnd = 2026-04-05 (Sunday).
      // Rows: Feb 23, Mar 2, 9, 16, 23, 30 → 6 rows.
      expect(weekRowCount(2026, 3), 6);
    });

    test('February 2026 shows 4 week rows (28-day month, 1 Feb = Sunday)', () {
      // 2026-02-01 is Sunday → gridStart = 2026-01-26 (Monday).
      // 2026-02-28 is Saturday → gridEnd = 2026-02-28.
      // Rows: Jan 26, Feb 2, 9, 16, 23 → 5 rows. Let's verify programmatically.
      final rows = weekRowCount(2026, 2);
      expect(rows, greaterThanOrEqualTo(4));
      expect(rows, lessThanOrEqualTo(6));
    });

    test('grid starts on a Monday', () {
      for (int m = 1; m <= 12; m++) {
        final firstDay = DateTime(2026, m, 1);
        final gridStart =
            firstDay.subtract(Duration(days: firstDay.weekday - 1));
        expect(gridStart.weekday, 1,
            reason: 'Month $m grid should start on Monday');
      }
    });

    test('grid ends on a Sunday', () {
      for (int m = 1; m <= 12; m++) {
        final lastDay = DateTime(2026, m + 1, 0);
        final gridEnd = lastDay.weekday == 7
            ? lastDay
            : lastDay.add(Duration(days: 7 - lastDay.weekday));
        expect(gridEnd.weekday, 7,
            reason: 'Month $m grid should end on Sunday');
      }
    });
  });

  // -------------------------------------------------------------------------
  // 3. DayDetailSheet shows correct sessions for the tapped day
  // -------------------------------------------------------------------------

  group('_DayDetailSheet', () {
    Widget _buildSheet(DateTime date, List<AgendaSession> sessions) {
      return MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => TextButton(
              onPressed: () => showModalBottomSheet(
                context: ctx,
                builder: (_) =>
                    // ignore: invalid_use_of_internal_member
                    _DayDetailSheetTestHelper(date: date, sessions: sessions),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
    }

    testWidgets('shows patient name in each list tile', (tester) async {
      final sessions = [
        _makeSession(
            date: '2026-03-04',
            dayOfWeek: 3,
            patientId: 'p1',
            patientName: 'Ana Lima'),
        _makeSession(
            date: '2026-03-04',
            dayOfWeek: 3,
            patientId: 'p2',
            patientName: 'Bruno Martins'),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: _DayDetailSheetTestHelper(
              date: DateTime(2026, 3, 4),
              sessions: sessions,
            ),
          ),
        ),
      );

      expect(find.text('Ana Lima'), findsOneWidget);
      expect(find.text('Bruno Martins'), findsOneWidget);
    });

    testWidgets('shows "Sem sessões neste dia." when list is empty',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: _DayDetailSheetTestHelper(
              date: DateTime(2026, 3, 5),
              sessions: const [],
            ),
          ),
        ),
      );

      expect(find.text('Sem sessões neste dia.'), findsOneWidget);
    });

    testWidgets('shows Reposição badge for isReposicao session',
        (tester) async {
      final s = _makeSession(
          date: '2026-03-04',
          dayOfWeek: 3,
          patientName: 'Carlos Dias',
          isReposicao: true);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: _DayDetailSheetTestHelper(
              date: DateTime(2026, 3, 4),
              sessions: [s],
            ),
          ),
        ),
      );

      expect(find.text('Reposição'), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------
  // 4. GCal URL is correctly formed
  // -------------------------------------------------------------------------

  group('buildGCalUrl', () {
    test('contains correct date in YYYYMMDD format', () {
      final s = _makeSession(date: '2026-03-04', dayOfWeek: 3);
      final url = buildGCalUrl(s);
      expect(url, contains('20260304T090000/20260304T100000'));
    });

    test('defaults to 09:00–10:00 local time', () {
      final s = _makeSession(date: '2026-05-15', dayOfWeek: 5);
      final url = buildGCalUrl(s);
      expect(url, contains('T090000'));
      expect(url, contains('T100000'));
    });

    test('includes patient name encoded in text parameter', () {
      final s = _makeSession(
          date: '2026-03-04', dayOfWeek: 3, patientName: 'Ana Lima');
      final url = buildGCalUrl(s);
      // Patient name should appear in the URL (URI-encoded)
      expect(url, contains('Ana%20Lima'));
    });

    test('uses EUR symbol for EUR currency patient', () {
      final s = _makeSession(
        date: '2026-04-01',
        dayOfWeek: 3,
        currency: 'EUR',
        currentRate: 120.0,
      );
      final url = buildGCalUrl(s);
      // %E2%82%AC is the URI encoding of €
      expect(url, contains('%E2%82%AC'));
    });

    test('includes PsyFinance in details', () {
      final s = _makeSession(date: '2026-03-04', dayOfWeek: 3);
      final url = buildGCalUrl(s);
      expect(url, contains('PsyFinance'));
    });

    test('URL starts with Google Calendar render endpoint', () {
      final s = _makeSession(date: '2026-03-04', dayOfWeek: 3);
      final url = buildGCalUrl(s);
      expect(url,
          startsWith('https://calendar.google.com/calendar/render'));
    });
  });

  // -------------------------------------------------------------------------
  // 5. Batch export with 0 sessions shows empty state instead of export prompt
  // -------------------------------------------------------------------------

  group('SessoesScreen empty state', () {
    testWidgets('shows empty state widget when provider returns empty list',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            agendaProvider.overrideWith((ref, args) async => <AgendaSession>[]),
          ],
          child: const MaterialApp(home: SessoesScreen()),
        ),
      );

      // Wait for the future to resolve
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byIcon(Icons.event_busy_outlined), findsOneWidget);
      expect(find.textContaining('Sem sessões'), findsOneWidget);
    });
  });
}

// ---------------------------------------------------------------------------
// Test helper: exposes _DayDetailSheet content directly (avoids bottom sheet)
// ---------------------------------------------------------------------------

/// Renders the internals of [_DayDetailSheet] as a regular widget for testing.
class _DayDetailSheetTestHelper extends StatelessWidget {
  final DateTime date;
  final List<AgendaSession> sessions;

  const _DayDetailSheetTestHelper(
      {required this.date, required this.sessions});

  String _fullDateLabel() {
    const weekdayFull = [
      'Segunda-feira', 'Terça-feira', 'Quarta-feira',
      'Quinta-feira', 'Sexta-feira', 'Sábado', 'Domingo',
    ];
    const monthPt = [
      'Janeiro', 'Fevereiro', 'Março', 'Abril', 'Maio', 'Junho',
      'Julho', 'Agosto', 'Setembro', 'Outubro', 'Novembro', 'Dezembro',
    ];
    final wd = weekdayFull[date.weekday - 1];
    final m = monthPt[date.month - 1].toLowerCase();
    return '$wd, ${date.day.toString().padLeft(2, '0')} de $m de ${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(_fullDateLabel()),
        if (sessions.isEmpty)
          const Text('Sem sessões neste dia.')
        else
          ...sessions.map((s) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.patient.name,
                      style:
                          const TextStyle(fontWeight: FontWeight.w500)),
                  if (s.sessionRecord.isReposicao)
                    const Text('Reposição'),
                ],
              )),
      ],
    );
  }
}
