import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shimmer/shimmer.dart';

import 'package:psyfinance_app/core/formatters.dart';
import 'package:psyfinance_app/features/patients/patient_model.dart';
import 'package:psyfinance_app/features/payments/payments_provider.dart';
import 'package:psyfinance_app/features/sessions/quick_add_session_sheet.dart';
import 'package:psyfinance_app/features/sessions/session_entry_sheet.dart';

import 'monthly_provider.dart';
import 'monthly_view_model.dart';

// ---------------------------------------------------------------------------
// Country color palette — deterministic by name hash
// ---------------------------------------------------------------------------

const _countryPalette = [
  Color(0xFF1565C0), // blue
  Color(0xFF2E7D32), // green
  Color(0xFFC62828), // red
  Color(0xFF6A1B9A), // purple
  Color(0xFFE65100), // orange
  Color(0xFF00695C), // teal
  Color(0xFF4527A0), // deep purple
  Color(0xFF283593), // indigo
];

Color _countryColor(String country) {
  final hash = country.codeUnits.fold(0, (acc, c) => acc + c);
  return _countryPalette[hash % _countryPalette.length];
}

// ---------------------------------------------------------------------------
// MonthlyBulkScreen
// ---------------------------------------------------------------------------

class MonthlyBulkScreen extends ConsumerStatefulWidget {
  const MonthlyBulkScreen({super.key});

  @override
  ConsumerState<MonthlyBulkScreen> createState() => _MonthlyBulkScreenState();
}

class _MonthlyBulkScreenState extends ConsumerState<MonthlyBulkScreen> {
  late int _year;
  late int _month;
  String? _countryFilter; // null = "Todos"
  bool _showRepasse = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _year = now.year;
    _month = now.month;
  }

  MonthlyArgs get _args => (year: _year, month: _month);

  void _prevMonth() => setState(() {
        if (_month == 1) {
          _month = 12;
          _year--;
        } else {
          _month--;
        }
      });

  void _nextMonth() => setState(() {
        if (_month == 12) {
          _month = 1;
          _year++;
        } else {
          _month++;
        }
      });

  @override
  Widget build(BuildContext context) {
    final asyncView = ref.watch(monthlyViewProvider(_args));

    void onRegisterSession() => showQuickAddSessionSheet(
          context,
          prefilterCountry: _countryFilter,
          args: _args,
          onSaved: (_, __) => ref
              .read(monthlyViewProvider(_args).notifier)
              .refreshAfterSessionSave(),
        );

    return Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _MonthlyAppBar(
              year: _year,
              month: _month,
              countryFilter: _countryFilter,
              allRows: asyncView.value?.patients ?? [],
              showRepasse: _showRepasse,
              onPrev: _prevMonth,
              onNext: _nextMonth,
              onCountryChanged: (c) => setState(() => _countryFilter = c),
              onToggleRepasse: () =>
                  setState(() => _showRepasse = !_showRepasse),
            ),
            asyncView.when(
              loading: () => Expanded(child: _ShimmerSkeleton()),
              error: (e, _) => Expanded(
                child: Center(
                  child: Text(
                    e.toString(),
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
              ),
              data: (view) => _MonthlyBody(
                view: view,
                year: _year,
                month: _month,
                countryFilter: _countryFilter,
                showRepasse: _showRepasse,
                args: _args,
                onSessionSaved: () => ref
                    .read(monthlyViewProvider(_args).notifier)
                    .refreshAfterSessionSave(),
                onRegisterSession: onRegisterSession,
              ),
            ),
          ],
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton.extended(
            heroTag: 'quick-add-session-fab',
            onPressed: onRegisterSession,
            icon: const Icon(Icons.add),
            label: const Text('Registrar sessão'),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// App bar — month navigator + filters
// ---------------------------------------------------------------------------

class _MonthlyAppBar extends StatelessWidget {
  final int year;
  final int month;
  final String? countryFilter;
  final List<MonthlyPatientRow> allRows;
  final bool showRepasse;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final ValueChanged<String?> onCountryChanged;
  final VoidCallback onToggleRepasse;

  const _MonthlyAppBar({
    required this.year,
    required this.month,
    required this.countryFilter,
    required this.allRows,
    required this.showRepasse,
    required this.onPrev,
    required this.onNext,
    required this.onCountryChanged,
    required this.onToggleRepasse,
  });

  List<String> get _countries {
    final set = <String>{};
    for (final r in allRows) {
      set.add(r.patient.location);
    }
    return set.toList()..sort();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final countries = _countries;
    final hasFilter = countryFilter != null;

    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(bottom: BorderSide(color: cs.outlineVariant, width: 1)),
      ),
      child: Row(
        children: [
          // Month navigator
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: onPrev,
            visualDensity: VisualDensity.compact,
          ),
          Text(
            '${monthName(month)} $year',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: onNext,
            visualDensity: VisualDensity.compact,
          ),
          const Spacer(),
          // Toggle repasse column
          Tooltip(
            message:
                showRepasse ? 'Ocultar repasses' : 'Mostrar repasses',
            child: IconButton(
              icon: Icon(
                Icons.receipt_long_outlined,
                color: showRepasse ? cs.primary : null,
              ),
              onPressed: onToggleRepasse,
              visualDensity: VisualDensity.compact,
            ),
          ),
          const SizedBox(width: 4),
          // "Todos" chip
          _FilterChip(
            label: 'Todos',
            active: !hasFilter,
            onTap: () => onCountryChanged(null),
          ),
          const SizedBox(width: 8),
          // Country dropdown
          _CountryDropdown(
            countries: countries,
            selected: countryFilter,
            onChanged: onCountryChanged,
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? cs.secondaryContainer : Colors.transparent,
          border: Border.all(
            color: active ? cs.secondary : cs.outline,
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: active ? cs.onSecondaryContainer : cs.onSurface,
            fontWeight: active ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

class _CountryDropdown extends StatelessWidget {
  final List<String> countries;
  final String? selected;
  final ValueChanged<String?> onChanged;

  const _CountryDropdown({
    required this.countries,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasSelection = selected != null;

    return PopupMenuButton<String?>(
      onSelected: onChanged,
      itemBuilder: (ctx) => countries
          .map(
            (c) => PopupMenuItem<String?>(
              value: c,
              child: Row(
                children: [
                  _CountryDot(country: c, size: 10),
                  const SizedBox(width: 8),
                  Text(c),
                ],
              ),
            ),
          )
          .toList(),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: hasSelection ? cs.secondaryContainer : Colors.transparent,
          border: Border.all(
            color: hasSelection ? cs.primary : cs.outline,
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hasSelection) ...[
              _CountryDot(country: selected!, size: 10),
              const SizedBox(width: 6),
              Text(
                selected!,
                style: TextStyle(
                  fontSize: 13,
                  color: cs.onSecondaryContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ] else
              Text(
                'Localização',
                style: TextStyle(fontSize: 13, color: cs.onSurface),
              ),
            const SizedBox(width: 4),
            Icon(Icons.arrow_drop_down, size: 18, color: cs.onSurface),
          ],
        ),
      ),
    );
  }
}

class _CountryDot extends StatelessWidget {
  final String country;
  final double size;

  const _CountryDot({required this.country, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: _countryColor(country),
        shape: BoxShape.circle,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Body — summary strip + patient table
// ---------------------------------------------------------------------------

class _MonthlyBody extends ConsumerWidget {
  final MonthlyView view;
  final int year;
  final int month;
  final String? countryFilter;
  final bool showRepasse;
  final MonthlyArgs args;
  final VoidCallback onSessionSaved;
  final VoidCallback onRegisterSession;

  const _MonthlyBody({
    required this.view,
    required this.year,
    required this.month,
    required this.countryFilter,
    required this.showRepasse,
    required this.args,
    required this.onSessionSaved,
    required this.onRegisterSession,
  });

  List<MonthlyPatientRow> get _filtered {
    if (countryFilter == null) return view.patients;
    return view.patients
        .where((r) => r.patient.location == countryFilter)
        .toList();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filtered = _filtered;
    final allEmpty = filtered.every((r) => r.sessionRecord == null);

    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SummaryStrip(
            view: view,
            countryFilter: countryFilter,
          ),
          Expanded(
            child: allEmpty && filtered.isNotEmpty
                ? _EmptyState(
                    month: month,
                    year: year,
                    onRegisterSession: onRegisterSession,
                  )
                : filtered.isEmpty
                    ? _EmptyState(month: month, year: year)
                    : _PatientTable(
                        rows: filtered,
                        year: year,
                        month: month,
                        showRepasse: showRepasse,
                        args: args,
                        onSessionSaved: onSessionSaved,
                      ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Summary strip
// ---------------------------------------------------------------------------

class _SummaryStrip extends StatelessWidget {
  final MonthlyView view;
  final String? countryFilter;

  const _SummaryStrip({required this.view, required this.countryFilter});

  // All countries for each currency (from the full patient list)
  List<String> _countriesForCurrency(String currency) {
    final locations = <String>{};
    for (final row in view.patients) {
      if (row.patient.currency.apiValue == currency) {
        if (countryFilter == null ||
            row.patient.location == countryFilter) {
          locations.add(row.patient.location);
        }
      }
    }
    return locations.toList()..sort();
  }

  @override
  Widget build(BuildContext context) {
    final brl = view.summary['BRL'] ??
        const CurrencySummary(totalExpected: 0, totalReceived: 0);
    final eur = view.summary['EUR'] ??
        const CurrencySummary(totalExpected: 0, totalReceived: 0);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: _CurrencyCard(
              currency: 'BRL',
              currencyName: 'Real brasileiro',
              countries: _countriesForCurrency('BRL'),
              summary: brl,
              accentColor: const Color(0xFF2E7D32),
              barColor: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _CurrencyCard(
              currency: 'EUR',
              currencyName: 'Euro',
              countries: _countriesForCurrency('EUR'),
              summary: eur,
              accentColor: const Color(0xFF1565C0),
              barColor: const Color(0xFF1565C0),
            ),
          ),
        ],
      ),
    );
  }
}

class _CurrencyCard extends StatelessWidget {
  final String currency;
  final String currencyName;
  final List<String> countries;
  final CurrencySummary summary;
  final Color accentColor;
  final Color barColor;

  const _CurrencyCard({
    required this.currency,
    required this.currencyName,
    required this.countries,
    required this.summary,
    required this.accentColor,
    required this.barColor,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final symbol = currency == 'EUR' ? '€' : 'R\$';
    final received = formatCurrency(summary.totalReceived, currency);
    final expected = formatCurrency(summary.totalExpected, currency);
    final progress = summary.totalExpected > 0
        ? (summary.totalReceived / summary.totalExpected).clamp(0.0, 1.0)
        : 0.0;
    final countrySubtitle = countries.isEmpty
        ? '—'
        : countries.join(' · ');

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: cs.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _CurrencyBadge(symbol: symbol, color: accentColor),
                const SizedBox(width: 8),
                Text(
                  currencyName,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w500),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              countrySubtitle,
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            Text(
              '$received / $expected',
              style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 4,
                backgroundColor: barColor.withValues(alpha: 0.15),
                valueColor: AlwaysStoppedAnimation<Color>(barColor),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CurrencyBadge extends StatelessWidget {
  final String symbol;
  final Color color;

  const _CurrencyBadge({required this.symbol, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        symbol,
        style: TextStyle(
            fontSize: 12, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Patient table — grouped by country with sticky section headers
// ---------------------------------------------------------------------------

class _PatientTable extends StatelessWidget {
  final List<MonthlyPatientRow> rows;
  final int year;
  final int month;
  final bool showRepasse;
  final MonthlyArgs args;
  final VoidCallback onSessionSaved;

  const _PatientTable({
    required this.rows,
    required this.year,
    required this.month,
    required this.showRepasse,
    required this.args,
    required this.onSessionSaved,
  });

  Map<String, List<MonthlyPatientRow>> _groupByCountry() {
    final map = <String, List<MonthlyPatientRow>>{};
    for (final row in rows) {
      (map[row.patient.location] ??= []).add(row);
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final groups = _groupByCountry();
    final countries = groups.keys.toList()..sort();

    return CustomScrollView(
      slivers: [
        // Table header
        SliverToBoxAdapter(child: _TableHeader(showRepasse: showRepasse)),
        // Country groups
        for (final country in countries)
          ..._buildCountryGroup(context, country, groups[country]!),
      ],
    );
  }

  List<Widget> _buildCountryGroup(
    BuildContext context,
    String country,
    List<MonthlyPatientRow> groupRows,
  ) {
    final currency = groupRows.first.patient.currency.apiValue;
    final symbol = currency == 'EUR' ? '€' : 'R\$';

    // Compute subtotals
    double totalExpected = 0;
    double totalPaid = 0;
    for (final r in groupRows) {
      totalExpected += r.sessionRecord?.expectedAmount ?? 0;
      totalPaid += r.payment?.amountPaid ?? 0;
    }

    return [
      // Sticky section header
      SliverPersistentHeader(
        pinned: true,
        delegate: _SectionHeaderDelegate(
          country: country,
          symbol: '($symbol)',
        ),
      ),
      // Rows
      SliverList(
        delegate: SliverChildBuilderDelegate(
          (ctx, i) => _PatientRow(
            row: groupRows[i],
            year: year,
            month: month,
            showRepasse: showRepasse,
            args: args,
            onSessionSaved: onSessionSaved,
          ),
          childCount: groupRows.length,
        ),
      ),
      // Subtotal row
      SliverToBoxAdapter(
        child: _SubtotalRow(
          country: country,
          currency: currency,
          totalExpected: totalExpected,
          totalPaid: totalPaid,
        ),
      ),
    ];
  }
}

// ---------------------------------------------------------------------------
// Table header row
// ---------------------------------------------------------------------------

class _TableHeader extends StatelessWidget {
  final bool showRepasse;

  const _TableHeader({required this.showRepasse});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      color: cs.surfaceContainerLow,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const _HeaderCell('Nome', flex: 3),
          const _HeaderCell('Sessões', flex: 2),
          const _HeaderCell('Esperado', flex: 2),
          const _HeaderCell('Pago', flex: 2),
          const _HeaderCell('Saldo', flex: 2),
          const _HeaderCell('Status', flex: 2),
          if (showRepasse) const _HeaderCell('Repasse', flex: 2),
          const _HeaderCell('Obs', flex: 2),
          const SizedBox(width: 40),
        ],
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  final String label;
  final int flex;

  const _HeaderCell(this.label, {required this.flex});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Section header delegate (sticky)
// ---------------------------------------------------------------------------

class _SectionHeaderDelegate extends SliverPersistentHeaderDelegate {
  final String country;
  final String symbol;

  _SectionHeaderDelegate({required this.country, required this.symbol});

  @override
  double get minExtent => 36;
  @override
  double get maxExtent => 36;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      color: cs.surfaceContainerLowest,
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: _countryColor(country),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$country $symbol',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(_SectionHeaderDelegate old) =>
      country != old.country || symbol != old.symbol;
}

// ---------------------------------------------------------------------------
// Subtotal row
// ---------------------------------------------------------------------------

class _SubtotalRow extends StatelessWidget {
  final String country;
  final String currency;
  final double totalExpected;
  final double totalPaid;

  const _SubtotalRow({
    required this.country,
    required this.currency,
    required this.totalExpected,
    required this.totalPaid,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      color: cs.surfaceContainer,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Total $country: ${formatCurrency(totalPaid, currency)} / ${formatCurrency(totalExpected, currency)}',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Patient row — manages its own inline payment edit state
// ---------------------------------------------------------------------------

class _PatientRow extends ConsumerStatefulWidget {
  final MonthlyPatientRow row;
  final int year;
  final int month;
  final bool showRepasse;
  final MonthlyArgs args;
  final VoidCallback onSessionSaved;

  const _PatientRow({
    required this.row,
    required this.year,
    required this.month,
    required this.showRepasse,
    required this.args,
    required this.onSessionSaved,
  });

  @override
  ConsumerState<_PatientRow> createState() => _PatientRowState();
}

class _PatientRowState extends ConsumerState<_PatientRow> {
  bool _editingPayment = false;
  late TextEditingController _payCtrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _payCtrl = TextEditingController(text: _initialPayText);
  }

  @override
  void didUpdateWidget(_PatientRow old) {
    super.didUpdateWidget(old);
    if (old.row.payment?.amountPaid != widget.row.payment?.amountPaid &&
        !_editingPayment) {
      _payCtrl.text = _initialPayText;
    }
  }

  @override
  void dispose() {
    _payCtrl.dispose();
    super.dispose();
  }

  String get _initialPayText {
    final paid = widget.row.payment?.amountPaid ?? 0.0;
    return paid == 0 ? '0' : paid.toStringAsFixed(2);
  }

  double get _parsedAmount =>
      double.tryParse(_payCtrl.text.replaceAll(',', '.')) ?? 0.0;

  Future<void> _confirmPayment() async {
    final sessionRecordId = widget.row.sessionRecord?.id;
    if (sessionRecordId == null) return;
    setState(() => _saving = true);
    try {
      final payment = await ref
          .read(paymentsRepositoryProvider)
          .updatePayment(sessionRecordId, _parsedAmount);
      ref
          .read(monthlyViewProvider(widget.args).notifier)
          .updateRowPayment(
              widget.row.patient.id, payment.amountPaid, payment.status);
      if (mounted) setState(() { _editingPayment = false; _saving = false; });
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e is Exception
                ? e.toString().replaceAll('Exception: ', '')
                : 'Erro ao salvar pagamento'),
          ),
        );
      }
    }
  }

  void _openSessionSheet() {
    final mp = widget.row.patient;
    final patient = Patient(
      id: mp.id,
      name: mp.name,
      email: '',
      location: mp.location,
      status: PatientStatus.ativo,
      paymentModel: mp.paymentModel,
      currency: mp.currency,
      currentRate: mp.currentRate,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    showSessionEntrySheet(
      context,
      patient: patient,
      year: widget.year,
      month: widget.month,
      onSaved: widget.onSessionSaved,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final row = widget.row;
    final hasSession = row.sessionRecord != null;
    final isAtrasado = row.payment?.status == 'ATRASADO';
    final currency = row.patient.currency.apiValue;

    Color? rowBg;
    if (isAtrasado) rowBg = cs.errorContainer.withValues(alpha: 0.3);

    return Container(
      color: rowBg,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: cs.outlineVariant, width: 0.5)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Nome
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.patient.name,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: hasSession ? null : cs.onSurfaceVariant,
                    fontStyle:
                        hasSession ? FontStyle.normal : FontStyle.italic,
                  ),
                ),
                Text(
                  '${row.patient.location} · ${row.patient.paymentModel.label}',
                  style: TextStyle(
                    fontSize: 11,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          // Sessões
          Expanded(
            flex: 2,
            child: hasSession
                ? Row(
                    children: [
                      Text(
                        '${row.sessionRecord!.sessionCount}',
                        style: TextStyle(
                          fontSize: 13,
                          color:
                              hasSession ? null : cs.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        icon: const Icon(Icons.calendar_today_outlined,
                            size: 16),
                        onPressed: _openSessionSheet,
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        tooltip: 'Editar sessões',
                      ),
                    ],
                  )
                : Row(
                    children: [
                      Text('—',
                          style: TextStyle(
                              fontSize: 13, color: cs.onSurfaceVariant)),
                      const SizedBox(width: 4),
                      TextButton(
                        onPressed: _openSessionSheet,
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          minimumSize: Size.zero,
                          tapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          textStyle: const TextStyle(fontSize: 11),
                        ),
                        child: const Text('Adicionar'),
                      ),
                    ],
                  ),
          ),
          // Esperado
          Expanded(
            flex: 2,
            child: Text(
              hasSession
                  ? formatCurrency(
                      row.sessionRecord!.expectedAmount, currency)
                  : '—',
              style: TextStyle(
                fontSize: 13,
                color: hasSession ? null : cs.onSurfaceVariant,
              ),
            ),
          ),
          // Pago
          Expanded(
            flex: 2,
            child: hasSession
                ? _editingPayment
                    ? Row(
                        children: [
                          Flexible(
                            child: SizedBox(
                              height: 30,
                              child: TextField(
                                controller: _payCtrl,
                                autofocus: true,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true),
                                textAlign: TextAlign.right,
                                style: const TextStyle(fontSize: 12),
                                decoration: const InputDecoration(
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 6),
                                  border: OutlineInputBorder(),
                                ),
                                onSubmitted: (_) => _confirmPayment(),
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(
                                      RegExp(r'[\d.,]')),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 2),
                          _saving
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2),
                                )
                              : IconButton(
                                  icon: const Icon(Icons.check,
                                      size: 16,
                                      color: Color(0xFF2E7D32)),
                                  onPressed: _confirmPayment,
                                  visualDensity: VisualDensity.compact,
                                  padding: EdgeInsets.zero,
                                ),
                        ],
                      )
                    : GestureDetector(
                        onTap: () => setState(() {
                          _editingPayment = true;
                          _payCtrl.text = _initialPayText;
                        }),
                        child: Text(
                          formatCurrency(
                              row.payment?.amountPaid ?? 0.0, currency),
                          style: const TextStyle(
                            fontSize: 13,
                            decoration: TextDecoration.underline,
                            decorationStyle: TextDecorationStyle.dotted,
                          ),
                        ),
                      )
                : Text('—',
                    style: TextStyle(
                        fontSize: 13, color: cs.onSurfaceVariant)),
          ),
          // Saldo
          Expanded(
            flex: 2,
            child: Builder(builder: (ctx) {
              if (!hasSession) {
                return Text('—',
                    style: TextStyle(
                        fontSize: 13, color: cs.onSurfaceVariant));
              }
              final saldo = row.sessionRecord!.expectedAmount -
                  (row.payment?.amountPaid ?? 0.0);
              return Text(
                formatCurrency(saldo, currency),
                style: TextStyle(
                  fontSize: 13,
                  color: saldo > 0.005 ? cs.error : const Color(0xFF2E7D32),
                  fontWeight: FontWeight.w500,
                ),
              );
            }),
          ),
          // Status
          Expanded(
            flex: 2,
            child: hasSession && row.payment != null
                ? _StatusChip(status: row.payment!.status)
                : const SizedBox.shrink(),
          ),
          // Repasse (hidden by default)
          if (widget.showRepasse)
            Expanded(
              flex: 2,
              child: Text(
                hasSession && (row.payment?.revenueShareAmount ?? 0) > 0
                    ? formatCurrency(
                        row.payment!.revenueShareAmount!, currency)
                    : '—',
                style: TextStyle(
                  fontSize: 13,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
          // Obs
          Expanded(
            flex: 2,
            child: hasSession &&
                    row.sessionRecord!.observations != null &&
                    row.sessionRecord!.observations!.isNotEmpty
                ? Tooltip(
                    message: row.sessionRecord!.observations!,
                    child: Text(
                      row.sessionRecord!.observations!.length > 30
                          ? '${row.sessionRecord!.observations!.substring(0, 30)}…'
                          : row.sessionRecord!.observations!,
                      style: TextStyle(
                          fontSize: 12, color: cs.onSurfaceVariant),
                      overflow: TextOverflow.ellipsis,
                    ),
                  )
                : Text('—',
                    style: TextStyle(
                        fontSize: 12, color: cs.onSurfaceVariant)),
          ),
          // Navigate to patient detail
          SizedBox(
            width: 40,
            child: IconButton(
              icon: const Icon(Icons.chevron_right, size: 18),
              onPressed: () =>
                  GoRouter.of(context).push('/pacientes/${row.patient.id}'),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Status chip
// ---------------------------------------------------------------------------

class _StatusChip extends StatelessWidget {
  final String status;

  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final (label, bg, fg) = switch (status) {
      'PAGO' => ('Pago', const Color(0xFFE8F5E9), const Color(0xFF1B5E20)),
      'PARCIAL' => (
          'Parcial',
          const Color(0xFFFFF8E1),
          const Color(0xFFE65100)
        ),
      'ATRASADO' => ('Atrasado', cs.errorContainer, cs.onErrorContainer),
      _ => ('Pendente', cs.surfaceVariant, cs.onSurfaceVariant),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: fg,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Empty state
// ---------------------------------------------------------------------------

class _EmptyState extends StatelessWidget {
  final int month;
  final int year;
  final VoidCallback? onRegisterSession;

  const _EmptyState({
    required this.month,
    required this.year,
    this.onRegisterSession,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.calendar_month_outlined,
            size: 48,
            color: cs.onSurfaceVariant.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            'Nenhuma sessão em ${monthName(month)} $year',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Toque no ícone de calendário ao lado de um paciente para registrar sessões.',
            style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          if (onRegisterSession != null) ...[
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: onRegisterSession,
              icon: const Icon(Icons.add),
              label: const Text('Registrar sessão'),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shimmer loading skeleton
// ---------------------------------------------------------------------------

class _ShimmerSkeleton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      child: Column(
        children: [
          // Summary strip skeleton
          Container(
            height: 100,
            margin: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          // Row skeletons
          for (int i = 0; i < 8; i++)
            Container(
              height: 52,
              margin:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(6),
              ),
            ),
        ],
      ),
    );
  }
}

