import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import 'agenda_provider.dart';
import 'agenda_session_model.dart';

// ---------------------------------------------------------------------------
// Localisation helpers
// ---------------------------------------------------------------------------

const _monthPt = [
  'Janeiro', 'Fevereiro', 'Março', 'Abril', 'Maio', 'Junho',
  'Julho', 'Agosto', 'Setembro', 'Outubro', 'Novembro', 'Dezembro',
];

const _dayHeadersPt = ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom'];

const _weekdayFullPt = [
  'Segunda-feira', 'Terça-feira', 'Quarta-feira',
  'Quinta-feira', 'Sexta-feira', 'Sábado', 'Domingo',
];

// ---------------------------------------------------------------------------
// Avatar helpers (deterministic from patient id — matches patient_list_screen)
// ---------------------------------------------------------------------------

const _avatarPalette = [
  Color(0xFF00695C),
  Color(0xFF00838F),
  Color(0xFF1565C0),
  Color(0xFF283593),
  Color(0xFF6A1B9A),
  Color(0xFF558B2F),
  Color(0xFFE65100),
  Color(0xFF827717),
];

Color _avatarColor(String patientId) {
  int hash = 0;
  for (final c in patientId.codeUnits) {
    hash = (hash * 31 + c) & 0x7FFFFFFF;
  }
  return _avatarPalette[hash % _avatarPalette.length];
}

String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  if (parts[0].length >= 2) return parts[0].substring(0, 2).toUpperCase();
  return parts[0][0].toUpperCase();
}

// ---------------------------------------------------------------------------
// Date helpers
// ---------------------------------------------------------------------------

String _fmtDate(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String _fmtShortDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';

/// Returns the Monday on or before [date].
DateTime _mondayOf(DateTime date) =>
    date.subtract(Duration(days: date.weekday - 1));

// ---------------------------------------------------------------------------
// Google Calendar URL builder
// ---------------------------------------------------------------------------

String buildGCalUrl(AgendaSession session) {
  final date = session.date.replaceAll('-', '');
  final symbol = session.patient.currency == 'EUR' ? '€' : 'R\$';
  final rateStr = session.patient.currentRate != null
      ? '$symbol ${session.patient.currentRate!.toStringAsFixed(0)}'
      : 'Valor não definido';

  final text = Uri.encodeComponent('${session.patient.name} \u2014 Sess\u00e3o');
  final details = Uri.encodeComponent(
    'Sess\u00e3o com ${session.patient.name} \u00b7 $rateStr \u00b7 PsyFinance',
  );

  return 'https://calendar.google.com/calendar/render?action=TEMPLATE'
      '&text=$text'
      '&dates=${date}T090000/${date}T100000'
      '&details=$details'
      '&sf=true&output=xml';
}

// ---------------------------------------------------------------------------
// SessoesScreen
// ---------------------------------------------------------------------------

enum _ViewMode { month, week }

class SessoesScreen extends ConsumerStatefulWidget {
  const SessoesScreen({super.key});

  @override
  ConsumerState<SessoesScreen> createState() => _SessoesScreenState();
}

class _SessoesScreenState extends ConsumerState<SessoesScreen> {
  _ViewMode _view = _ViewMode.month;
  late int _year;
  late int _month;
  late DateTime _weekStart; // always a Monday

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _year = now.year;
    _month = now.month;
    _weekStart = _mondayOf(now);
  }

  // ---- Navigation -----------------------------------------------------------

  String _periodLabel() {
    if (_view == _ViewMode.month) {
      return '${_monthPt[_month - 1]} $_year';
    } else {
      final weekEnd = _weekStart.add(const Duration(days: 6));
      return 'Semana de ${_fmtShortDate(_weekStart)} \u2013 ${_fmtShortDate(weekEnd)}';
    }
  }

  void _prevPeriod() => setState(() {
        if (_view == _ViewMode.month) {
          _month--;
          if (_month < 1) {
            _month = 12;
            _year--;
          }
        } else {
          _weekStart = _weekStart.subtract(const Duration(days: 7));
        }
      });

  void _nextPeriod() => setState(() {
        if (_view == _ViewMode.month) {
          _month++;
          if (_month > 12) {
            _month = 1;
            _year++;
          }
        } else {
          _weekStart = _weekStart.add(const Duration(days: 7));
        }
      });

  void _onViewChanged(_ViewMode v) {
    if (v == _view) return;
    setState(() {
      if (v == _ViewMode.month) {
        // Sync to the month of the current week start
        _year = _weekStart.year;
        _month = _weekStart.month;
      } else {
        // Sync week to the first Monday visible in the current month view
        final now = DateTime.now();
        if (_year == now.year && _month == now.month) {
          _weekStart = _mondayOf(now);
        } else {
          _weekStart = _mondayOf(DateTime(_year, _month, 1));
        }
      }
      _view = v;
    });
  }

  // ---- Session data ---------------------------------------------------------

  /// Combines two async values, filters to [startStr..endStr], and returns
  /// a single AsyncValue. Used for week view that can span two months.
  AsyncValue<List<AgendaSession>> _mergeWeekAsync(
    AsyncValue<List<AgendaSession>> m1,
    AsyncValue<List<AgendaSession>>? m2,
    String startStr,
    String endStr,
  ) {
    if (m1.isLoading || (m2 != null && m2.isLoading)) {
      return const AsyncValue.loading();
    }
    if (m1.hasError) return AsyncValue.error(m1.error!, m1.stackTrace!);
    if (m2 != null && m2.hasError) {
      return AsyncValue.error(m2.error!, m2.stackTrace!);
    }
    final all = <AgendaSession>[
      ...(m1.valueOrNull ?? []),
      ...(m2?.valueOrNull ?? []),
    ];
    final filtered = all
        .where((s) =>
            s.date.compareTo(startStr) >= 0 && s.date.compareTo(endStr) <= 0)
        .toList();
    return AsyncValue.data(filtered);
  }

  // ---- Refresh --------------------------------------------------------------

  /// Invalidates the cached provider(s) for the current view so that the next
  /// build triggers a fresh API call.
  void _refresh() {
    if (_view == _ViewMode.month) {
      ref.invalidate(agendaProvider((year: _year, month: _month)));
    } else {
      final weekEnd = _weekStart.add(const Duration(days: 6));
      ref.invalidate(
          agendaProvider((year: _weekStart.year, month: _weekStart.month)));
      if (weekEnd.month != _weekStart.month ||
          weekEnd.year != _weekStart.year) {
        ref.invalidate(
            agendaProvider((year: weekEnd.year, month: weekEnd.month)));
      }
    }
  }

  // ---- Google Calendar export -----------------------------------------------

  Future<void> _exportBatch(
      List<AgendaSession> sessions, BuildContext context) async {
    if (sessions.isEmpty) return;

    if (sessions.length > 20) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Muitas sessões'),
          content: Text(
              'Serão abertas ${sessions.length} abas no navegador. Deseja continuar?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Exportar'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
          'Abrindo ${sessions.length} sess${sessions.length == 1 ? 'ão' : 'ões'} no Google Agenda…'),
    ));

    for (final s in sessions) {
      await launchUrl(Uri.parse(buildGCalUrl(s)),
          mode: LaunchMode.externalApplication);
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
  }

  // ---- Build ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<AgendaSession>> asyncSessions;

    if (_view == _ViewMode.month) {
      asyncSessions =
          ref.watch(agendaProvider((year: _year, month: _month)));
    } else {
      final weekEnd = _weekStart.add(const Duration(days: 6));
      final startStr = _fmtDate(_weekStart);
      final endStr = _fmtDate(weekEnd);
      final m1 = ref.watch(
          agendaProvider((year: _weekStart.year, month: _weekStart.month)));
      final spansMonth = weekEnd.month != _weekStart.month ||
          weekEnd.year != _weekStart.year;
      final m2 = spansMonth
          ? ref.watch(
              agendaProvider((year: weekEnd.year, month: weekEnd.month)))
          : null;
      asyncSessions = _mergeWeekAsync(m1, m2, startStr, endStr);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sessões'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Atualizar',
            onPressed: _refresh,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.calendar_today_outlined),
            tooltip: 'Exportar para Google Agenda',
            onSelected: (value) {
              if (value == 'week') {
                final weekEnd = _weekStart.add(const Duration(days: 6));
                final startStr = _fmtDate(_weekStart);
                final endStr = _fmtDate(weekEnd);
                final all = ref
                        .read(agendaProvider((
                          year: _weekStart.year,
                          month: _weekStart.month,
                        )))
                        .valueOrNull ??
                    [];
                final week = all
                    .where((s) =>
                        s.date.compareTo(startStr) >= 0 &&
                        s.date.compareTo(endStr) <= 0)
                    .toList();
                _exportBatch(week, context);
              } else {
                final (yr, mo) = _view == _ViewMode.week
                    ? (_weekStart.year, _weekStart.month)
                    : (_year, _month);
                final all =
                    ref.read(agendaProvider((year: yr, month: mo))).valueOrNull ??
                        [];
                _exportBatch(all, context);
              }
            },
            itemBuilder: (_) => [
              if (_view == _ViewMode.week)
                const PopupMenuItem(
                  value: 'week',
                  child: Text('Exportar esta semana'),
                ),
              const PopupMenuItem(
                value: 'month',
                child: Text('Exportar este mês'),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          _buildViewControls(context),
          const Divider(height: 1),
          Expanded(
            child: asyncSessions.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, size: 48),
                    const SizedBox(height: 12),
                    Text('Erro ao carregar sessões: $e'),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () => setState(() {}),
                      child: const Text('Tentar novamente'),
                    ),
                  ],
                ),
              ),
              data: (sessions) {
                if (sessions.isEmpty) return _buildEmptyState(context);
                return _view == _ViewMode.month
                    ? _buildMonthView(sessions, context)
                    : _buildWeekView(sessions, context);
              },
            ),
          ),
        ],
      ),
    );
  }

  // ---- View controls --------------------------------------------------------

  Widget _buildViewControls(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          SegmentedButton<_ViewMode>(
            segments: const [
              ButtonSegment(
                value: _ViewMode.week,
                label: Text('Semana'),
                icon: Icon(Icons.view_week_outlined),
              ),
              ButtonSegment(
                value: _ViewMode.month,
                label: Text('Mês'),
                icon: Icon(Icons.calendar_month_outlined),
              ),
            ],
            selected: {_view},
            onSelectionChanged: (s) => _onViewChanged(s.first),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.chevron_left),
            tooltip: 'Período anterior',
            onPressed: _prevPeriod,
          ),
          Text(
            _periodLabel(),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            tooltip: 'Próximo período',
            onPressed: _nextPeriod,
          ),
        ],
      ),
    );
  }

  // ---- Empty state ----------------------------------------------------------

  Widget _buildEmptyState(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.event_busy_outlined,
              size: 48, color: cs.onSurface.withOpacity(0.35)),
          const SizedBox(height: 16),
          Text(
            'Sem sessões em ${_periodLabel()}',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(color: cs.onSurface.withOpacity(0.6)),
          ),
          const SizedBox(height: 6),
          Text(
            'Registre sessões na tela Mensal ou use o botão Registrar sessão.',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: cs.onSurface.withOpacity(0.45)),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // ---- Month view -----------------------------------------------------------

  Widget _buildMonthView(
      List<AgendaSession> sessions, BuildContext context) {
    final byDate = _groupByDate(sessions);

    final firstDay = DateTime(_year, _month, 1);
    final lastDay = DateTime(_year, _month + 1, 0);
    final gridStart = _mondayOf(firstDay);
    // The Sunday on or after the last day of the month:
    final gridEnd = lastDay.weekday == 7
        ? lastDay
        : lastDay.add(Duration(days: 7 - lastDay.weekday));

    final weeks = <DateTime>[];
    DateTime w = gridStart;
    while (!w.isAfter(gridEnd)) {
      weeks.add(w);
      w = w.add(const Duration(days: 7));
    }

    return Column(
      children: [
        _buildDayHeaders(context),
        Expanded(
          child: Column(
            children: weeks
                .map((ws) => Expanded(
                      child: _buildWeekRow(ws, byDate, context),
                    ))
                .toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildDayHeaders(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      color: cs.surfaceContainerLow,
      child: Row(
        children: _dayHeadersPt
            .map((h) => Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text(
                      h,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: cs.onSurface.withOpacity(0.55),
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                ))
            .toList(),
      ),
    );
  }

  Widget _buildWeekRow(
    DateTime weekStart,
    Map<String, List<AgendaSession>> byDate,
    BuildContext context,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: List.generate(7, (i) {
        final date = weekStart.add(Duration(days: i));
        final dateStr = _fmtDate(date);
        final daySessions = byDate[dateStr] ?? [];
        return Expanded(
          child: _buildDayCell(date, daySessions, context),
        );
      }),
    );
  }

  Widget _buildDayCell(
    DateTime date,
    List<AgendaSession> sessions,
    BuildContext context,
  ) {
    final now = DateTime.now();
    final isToday = date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
    final isCurrentMonth = date.month == _month && date.year == _year;
    final cs = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: () => _showDaySheet(context, date, sessions),
      child: Container(
        margin: const EdgeInsets.all(1),
        decoration: BoxDecoration(
          color: isToday
              ? cs.primaryContainer.withOpacity(0.45)
              : null,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isToday ? cs.primary.withOpacity(0.3) : cs.outlineVariant.withOpacity(0.3),
            width: 0.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 3, 4, 1),
              child: Text(
                '${date.day}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight:
                      isToday ? FontWeight.bold : FontWeight.normal,
                  color: isCurrentMonth
                      ? (isToday ? cs.primary : cs.onSurface)
                      : cs.onSurface.withOpacity(0.28),
                ),
              ),
            ),
            if (isCurrentMonth) ..._buildMonthChips(sessions, context),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildMonthChips(
      List<AgendaSession> sessions, BuildContext context) {
    if (sessions.isEmpty) return [];
    final shown = sessions.take(3).toList();
    final overflow = sessions.length - shown.length;
    return [
      ...shown.map((s) => _buildPatientChip(s, context)),
      if (overflow > 0)
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 1),
          child: Text(
            '+$overflow mais',
            style: TextStyle(
              fontSize: 9,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
            ),
          ),
        ),
    ];
  }

  Widget _buildPatientChip(AgendaSession session, BuildContext context) {
    final color = _avatarColor(session.patient.id);
    final firstName = session.patient.name.split(' ').first;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 1),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 3),
          Expanded(
            child: Text(
              firstName,
              style: const TextStyle(fontSize: 9),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  // ---- Week view ------------------------------------------------------------

  Widget _buildWeekView(List<AgendaSession> sessions, BuildContext context) {
    final byDate = _groupByDate(sessions);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: List.generate(7, (i) {
        final date = _weekStart.add(Duration(days: i));
        final dateStr = _fmtDate(date);
        final daySessions = byDate[dateStr] ?? [];
        return Expanded(
          child: _buildWeekColumn(date, daySessions, context),
        );
      }),
    );
  }

  Widget _buildWeekColumn(
    DateTime date,
    List<AgendaSession> sessions,
    BuildContext context,
  ) {
    final now = DateTime.now();
    final isToday = date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
    final cs = Theme.of(context).colorScheme;

    return Column(
      children: [
        // Column header
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 8),
          color:
              isToday ? cs.primaryContainer.withOpacity(0.35) : null,
          child: Text(
            '${_dayHeadersPt[date.weekday - 1]} ${date.day.toString().padLeft(2, '0')}',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isToday ? FontWeight.bold : FontWeight.w500,
              color: isToday ? cs.primary : cs.onSurface,
            ),
          ),
        ),
        Divider(height: 1, color: cs.outlineVariant),
        // Sessions
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(4),
            children: [
              ...sessions
                  .map((s) => _buildWeekSessionCard(s, context, date)),
              if (sessions.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '—',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurface.withOpacity(0.3),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildWeekSessionCard(
      AgendaSession session, BuildContext context, DateTime date) {
    final color = _avatarColor(session.patient.id);
    final cs = Theme.of(context).colorScheme;
    final symbol = session.patient.currency == 'EUR' ? '€' : 'R\$';
    final rate = session.patient.currentRate != null
        ? '$symbol ${session.patient.currentRate!.toStringAsFixed(0)}'
        : '—';

    return GestureDetector(
      onTap: () => _showDaySheet(context, date, [session]),
      child: Card(
        margin: const EdgeInsets.only(bottom: 4),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 12,
                    backgroundColor: color,
                    child: Text(
                      _initials(session.patient.name),
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      session.patient.name,
                      style: const TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w500),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                rate,
                style: TextStyle(
                    fontSize: 10, color: cs.onSurface.withOpacity(0.65)),
              ),
              if (session.sessionRecord.isReposicao)
                Container(
                  margin: const EdgeInsets.only(top: 3),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade100,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: const Text(
                    'Reposição',
                    style: TextStyle(
                        fontSize: 9,
                        color: Color(0xFF7A5A00),
                        fontWeight: FontWeight.w600),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ---- Day detail sheet -----------------------------------------------------

  void _showDaySheet(
      BuildContext context, DateTime date, List<AgendaSession> sessions) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _DayDetailSheet(date: date, sessions: sessions),
    );
  }

  // ---- Utility --------------------------------------------------------------

  Map<String, List<AgendaSession>> _groupByDate(List<AgendaSession> sessions) {
    final map = <String, List<AgendaSession>>{};
    for (final s in sessions) {
      map.putIfAbsent(s.date, () => []).add(s);
    }
    return map;
  }
}

// ---------------------------------------------------------------------------
// Day detail bottom sheet
// ---------------------------------------------------------------------------

class _DayDetailSheet extends StatelessWidget {
  final DateTime date;
  final List<AgendaSession> sessions;

  const _DayDetailSheet({required this.date, required this.sessions});

  String _fullDateLabel() {
    final wd = _weekdayFullPt[date.weekday - 1];
    final m = _monthPt[date.month - 1].toLowerCase();
    return '$wd, ${date.day.toString().padLeft(2, '0')} de $m de ${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      maxChildSize: 0.92,
      minChildSize: 0.3,
      expand: false,
      builder: (ctx, controller) => Column(
        children: [
          // Drag handle
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(ctx).colorScheme.onSurface.withOpacity(0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // Title
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              _fullDateLabel(),
              style: Theme.of(ctx).textTheme.titleMedium,
            ),
          ),
          const Divider(height: 1),
          // List
          Expanded(
            child: sessions.isEmpty
                ? const Center(
                    child: Text(
                      'Sem sessões neste dia.',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    controller: controller,
                    itemCount: sessions.length,
                    itemBuilder: (c, i) =>
                        _buildSessionTile(sessions[i], c),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSessionTile(AgendaSession session, BuildContext context) {
    final color = _avatarColor(session.patient.id);
    final initials = _initials(session.patient.name);
    final symbol = session.patient.currency == 'EUR' ? '€' : 'R\$';
    final rate = session.patient.currentRate != null
        ? '$symbol ${session.patient.currentRate!.toStringAsFixed(0)}'
        : 'Valor não definido';

    return ListTile(
      leading: CircleAvatar(
        radius: 20,
        backgroundColor: color,
        child: Text(
          initials,
          style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600),
        ),
      ),
      title: Text(
        session.patient.name,
        style: const TextStyle(fontWeight: FontWeight.w500),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$rate · ${session.patient.location}'),
          if (session.sessionRecord.isReposicao)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.amber.shade100,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'Reposição',
                  style: TextStyle(
                      fontSize: 11,
                      color: Color(0xFF7A5A00),
                      fontWeight: FontWeight.w600),
                ),
              ),
            ),
        ],
      ),
      isThreeLine: session.sessionRecord.isReposicao,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Exportar para Google Agenda',
            icon: const Icon(Icons.calendar_today_outlined, size: 20),
            onPressed: () async {
              await launchUrl(
                Uri.parse(buildGCalUrl(session)),
                mode: LaunchMode.externalApplication,
              );
            },
          ),
          IconButton(
            tooltip: 'Ver paciente',
            icon: const Icon(Icons.arrow_forward_ios, size: 16),
            onPressed: () {
              Navigator.of(context).pop();
              context.go('/pacientes/${session.patient.id}');
            },
          ),
        ],
      ),
    );
  }
}
