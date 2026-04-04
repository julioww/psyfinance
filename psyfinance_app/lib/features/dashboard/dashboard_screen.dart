import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:psyfinance_app/core/formatters.dart';
import 'dashboard_model.dart';
import 'dashboard_provider.dart';
import 'export_button.dart';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const _kEurBlue = Color(0xFF3B82F6);
const _kSuccessGreen = Color(0xFF22C55E);
const _kAvailableYears = [2023, 2024, 2025, 2026];

// ---------------------------------------------------------------------------
// DashboardScreen
// ---------------------------------------------------------------------------

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  int _year = DateTime.now().year.clamp(2023, 2026);

  @override
  Widget build(BuildContext context) {
    final asyncData = ref.watch(dashboardProvider(_year));

    return asyncData.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text(e.toString())),
      data: (data) => _DashboardBody(
        year: _year,
        data: data,
        onYearChanged: (y) => setState(() => _year = y),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _DashboardBody — scrollable content
// ---------------------------------------------------------------------------

class _DashboardBody extends StatelessWidget {
  final int year;
  final DashboardData data;
  final ValueChanged<int> onYearChanged;

  const _DashboardBody({
    required this.year,
    required this.data,
    required this.onYearChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PageHeader(
            year: year,
            onYearChanged: onYearChanged,
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _SummaryCard(
                  currency: 'BRL',
                  dashboard: data.brl,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _SummaryCard(
                  currency: 'EUR',
                  dashboard: data.eur,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _BarChartCard(currency: 'BRL', dashboard: data.brl),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _BarChartCard(currency: 'EUR', dashboard: data.eur),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _PatientTable(patients: data.patients),
          const SizedBox(height: 16),
          _RepassesSection(repasses: data.repasses),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _PageHeader
// ---------------------------------------------------------------------------

class _PageHeader extends StatelessWidget {
  final int year;
  final ValueChanged<int> onYearChanged;

  const _PageHeader({
    required this.year,
    required this.onYearChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        Text(
          'Dashboard',
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w500),
        ),
        const Spacer(),
        SegmentedButton<int>(
          segments: _kAvailableYears
              .map((y) => ButtonSegment<int>(value: y, label: Text('$y')))
              .toList(),
          selected: {year},
          onSelectionChanged: (s) => onYearChanged(s.first),
          style: ButtonStyle(
            backgroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return colorScheme.secondaryContainer;
              }
              return null;
            }),
          ),
        ),
        const SizedBox(width: 12),
        _ExportMenuButton(year: year),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// _ExportMenuButton — popup with ExportButton items for each format
// ---------------------------------------------------------------------------

class _ExportMenuButton extends StatelessWidget {
  final int year;

  const _ExportMenuButton({required this.year});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_ExportOption>(
      onSelected: (_) {},
      itemBuilder: (context) => [
        for (final opt in _ExportOption.values)
          PopupMenuItem<_ExportOption>(
            value: opt,
            padding: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: ExportButton(
                type: opt.type,
                format: opt.format,
                year: year,
              ),
            ),
          ),
      ],
      child: OutlinedButton.icon(
        onPressed: null,
        icon: const Icon(Icons.file_download_outlined, size: 16),
        label: const Text('Exportar'),
      ),
    );
  }
}

enum _ExportOption {
  monthlyCsv,
  monthlyPdf,
  annualCsv,
  annualPdf,
  summaryCsv,
  summaryPdf,
}

extension _ExportOptionX on _ExportOption {
  ExportType get type {
    switch (this) {
      case _ExportOption.monthlyCsv:
      case _ExportOption.monthlyPdf:
        return ExportType.monthly;
      case _ExportOption.annualCsv:
      case _ExportOption.annualPdf:
        return ExportType.annual;
      case _ExportOption.summaryCsv:
      case _ExportOption.summaryPdf:
        return ExportType.summary;
    }
  }

  ExportFormat get format {
    switch (this) {
      case _ExportOption.monthlyCsv:
      case _ExportOption.annualCsv:
      case _ExportOption.summaryCsv:
        return ExportFormat.csv;
      case _ExportOption.monthlyPdf:
      case _ExportOption.annualPdf:
      case _ExportOption.summaryPdf:
        return ExportFormat.pdf;
    }
  }
}

// ---------------------------------------------------------------------------
// _SummaryCard
// ---------------------------------------------------------------------------

class _SummaryCard extends StatelessWidget {
  final String currency; // 'BRL' | 'EUR'
  final CurrencyDashboard dashboard;

  const _SummaryCard({required this.currency, required this.dashboard});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isBrl = currency == 'BRL';
    final accentColor = isBrl ? colorScheme.primary : _kEurBlue;
    final currencyName = isBrl ? 'Real brasileiro' : 'Euro';
    final symbol = isBrl ? 'R\$' : '€';

    final received = dashboard.yearToDateReceived;
    final expected = dashboard.yearToDateExpected;
    final balance = expected - received;
    final pct = expected > 0 ? (received / expected).clamp(0.0, 1.0) : 0.0;
    final pctLabel = '${(pct * 100).toStringAsFixed(0)}%';
    final balanceColor = balance > 0 ? colorScheme.error : _kSuccessGreen;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: accentColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Text(
                  symbol,
                  style: TextStyle(
                    color: accentColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    currencyName,
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                  if (dashboard.countries.isNotEmpty)
                    Text(
                      dashboard.countries.join(', '),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(
                child: Text(
                  formatCurrency(received, currency),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  '/ ${formatCurrency(expected, currency)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 5,
              color: accentColor,
              backgroundColor: colorScheme.surfaceContainerHighest,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Flexible(
                child: Text(
                  '$pctLabel recebido · saldo ',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                formatCurrency(balance, currency),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: balanceColor,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _BarChartCard
// ---------------------------------------------------------------------------

class _BarChartCard extends StatelessWidget {
  final String currency;
  final CurrencyDashboard dashboard;

  const _BarChartCard({required this.currency, required this.dashboard});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isBrl = currency == 'BRL';
    final barColor = isBrl ? colorScheme.primary : _kEurBlue;
    final currencyLabel = isBrl ? 'BRL' : 'EUR';

    // Find max Y for chart scaling.
    double maxY = 10;
    for (final t in dashboard.monthlyTotals) {
      if (t.expected > maxY) maxY = t.expected;
      if (t.received > maxY) maxY = t.received;
    }
    maxY = (maxY * 1.2).ceilToDouble();

    final barGroups = List.generate(12, (i) {
      final total = dashboard.monthlyTotals[i];
      return BarChartGroupData(
        x: i,
        barRods: [
          // Faded: expected
          BarChartRodData(
            toY: total.expected,
            color: barColor.withOpacity(0.25),
            width: 9,
            borderRadius: BorderRadius.circular(2),
          ),
          // Solid: received
          BarChartRodData(
            toY: total.received,
            color: barColor,
            width: 9,
            borderRadius: BorderRadius.circular(2),
          ),
        ],
      );
    });

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: barColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                currencyLabel,
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 160,
            child: BarChart(
              BarChartData(
                maxY: maxY,
                barGroups: barGroups,
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  leftTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 20,
                      getTitlesWidget: (value, meta) {
                        final idx = value.toInt();
                        if (idx < 0 || idx > 11) return const SizedBox();
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            monthAbbr(idx + 1),
                            style: TextStyle(
                              fontSize: 9,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                barTouchData: BarTouchData(
                  enabled: true,
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (_) => colorScheme.surfaceContainerHighest,
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      final label = rodIndex == 0 ? 'Esperado' : 'Recebido';
                      return BarTooltipItem(
                        '$label\n${formatCurrency(rod.toY, currency)}',
                        TextStyle(
                          color: colorScheme.onSurface,
                          fontSize: 11,
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              _LegendDot(color: barColor, label: 'Recebido'),
              const SizedBox(width: 12),
              _LegendDot(color: barColor.withOpacity(0.25), label: 'Esperado'),
            ],
          ),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// _PatientTable
// ---------------------------------------------------------------------------

class _PatientTable extends StatelessWidget {
  final List<DashboardPatient> patients;

  const _PatientTable({required this.patients});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'RESUMO POR PACIENTE',
          style: textTheme.labelSmall?.copyWith(
            fontSize: 11,
            letterSpacing: 0.5,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        // Header
        _TableRow(
          isHeader: true,
          cells: const ['Nome', '', 'Sessões', 'Esperado', 'Recebido', 'Saldo', ''],
          hasOutstanding: false,
        ),
        const Divider(height: 1),
        ...patients.map(
          (p) => Column(
            children: [
              _PatientRow(patient: p),
              const Divider(height: 1),
            ],
          ),
        ),
      ],
    );
  }
}

class _TableRow extends StatelessWidget {
  final bool isHeader;
  final List<String> cells;
  final bool hasOutstanding;

  const _TableRow({
    required this.isHeader,
    required this.cells,
    required this.hasOutstanding,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final style = isHeader
        ? textTheme.labelSmall?.copyWith(color: colorScheme.onSurfaceVariant)
        : textTheme.bodySmall;

    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Row(
            children: [
              // Left padding for border
              const SizedBox(width: 4),
              // Nome
              Expanded(
                flex: 3,
                child: Text(cells[0], style: style),
              ),
              // Currency badge placeholder
              SizedBox(
                width: 36,
                child: cells[1].isEmpty
                    ? const SizedBox()
                    : _CurrencyBadge(currency: cells[1]),
              ),
              // Sessões
              SizedBox(
                width: 60,
                child: Text(cells[2], style: style, textAlign: TextAlign.right),
              ),
              // Esperado
              Expanded(
                flex: 2,
                child: Text(cells[3], style: style, textAlign: TextAlign.right),
              ),
              // Recebido
              Expanded(
                flex: 2,
                child: Text(cells[4], style: style, textAlign: TextAlign.right),
              ),
              // Saldo
              Expanded(
                flex: 2,
                child: Text(cells[5], style: style, textAlign: TextAlign.right),
              ),
              // Arrow
              const SizedBox(width: 24),
            ],
          ),
        ),
        if (hasOutstanding)
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: Container(
              width: 3,
              color: colorScheme.error,
            ),
          ),
      ],
    );
  }
}

class _PatientRow extends StatelessWidget {
  final DashboardPatient patient;

  const _PatientRow({required this.patient});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final balanceColor = patient.hasOutstanding ? colorScheme.error : _kSuccessGreen;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => context.push('/pacientes/${patient.id}'),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: Row(
              children: [
                const SizedBox(width: 4),
                Expanded(
                  flex: 3,
                  child: Text(
                    patient.name,
                    style: Theme.of(context).textTheme.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                SizedBox(
                  width: 36,
                  child: _CurrencyBadge(currency: patient.currency),
                ),
                SizedBox(
                  width: 60,
                  child: Text(
                    '${patient.totalSessions}',
                    style: Theme.of(context).textTheme.bodySmall,
                    textAlign: TextAlign.right,
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    formatCurrency(patient.totalExpected, patient.currency),
                    style: Theme.of(context).textTheme.bodySmall,
                    textAlign: TextAlign.right,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    formatCurrency(patient.totalReceived, patient.currency),
                    style: Theme.of(context).textTheme.bodySmall,
                    textAlign: TextAlign.right,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    formatCurrency(patient.balance, patient.currency),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: balanceColor,
                          fontWeight: FontWeight.w600,
                        ),
                    textAlign: TextAlign.right,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(
                  width: 24,
                  child: Icon(Icons.arrow_forward_ios, size: 12),
                ),
              ],
            ),
          ),
          if (patient.hasOutstanding)
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: Container(
                width: 3,
                color: colorScheme.error,
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _CurrencyBadge
// ---------------------------------------------------------------------------

class _CurrencyBadge extends StatelessWidget {
  final String currency;

  const _CurrencyBadge({required this.currency});

  @override
  Widget build(BuildContext context) {
    final isBrl = currency == 'BRL';
    final color = isBrl ? Theme.of(context).colorScheme.primary : _kEurBlue;
    final label = isBrl ? 'R\$' : '€';

    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 9,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _RepassesSection
// ---------------------------------------------------------------------------

class _RepassesSection extends StatelessWidget {
  final List<RepasseEntry> repasses;

  const _RepassesSection({required this.repasses});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ExpansionTile(
        title: Text(
          'REPASSES DO ANO',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontSize: 11,
                letterSpacing: 0.5,
                color: colorScheme.onSurfaceVariant,
              ),
        ),
        initiallyExpanded: false,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        collapsedShape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        children: [
          if (repasses.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Nenhum repasse no período.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
              ),
            )
          else
            _RepassesTable(repasses: repasses),
        ],
      ),
    );
  }
}

class _RepassesTable extends StatelessWidget {
  final List<RepasseEntry> repasses;

  const _RepassesTable({required this.repasses});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    // Group by beneficiaryName.
    final grouped = <String, List<RepasseEntry>>{};
    for (final r in repasses) {
      grouped.putIfAbsent(r.beneficiaryName, () => []).add(r);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Text(
                    'Paciente',
                    style: textTheme.labelSmall
                        ?.copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                ),
                const SizedBox(width: 36),
                Expanded(
                  flex: 2,
                  child: Text(
                    'Beneficiário',
                    style: textTheme.labelSmall
                        ?.copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                ),
                SizedBox(
                  width: 60,
                  child: Text(
                    'Sessões',
                    style: textTheme.labelSmall
                        ?.copyWith(color: colorScheme.onSurfaceVariant),
                    textAlign: TextAlign.right,
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'A repassar',
                    style: textTheme.labelSmall
                        ?.copyWith(color: colorScheme.onSurfaceVariant),
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          ...grouped.entries.expand((entry) {
            final beneficiary = entry.key;
            final items = entry.value;
            final subtotal = items.fold(0.0, (a, r) => a + r.totalRepass);
            final currency = items.first.currency;

            return [
              ...items.map(
                (r) => Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          vertical: 6, horizontal: 4),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: Text(
                              r.patientName,
                              style: textTheme.bodySmall,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          SizedBox(
                            width: 36,
                            child: _CurrencyBadge(currency: r.currency),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              beneficiary,
                              style: textTheme.bodySmall,
                            ),
                          ),
                          SizedBox(
                            width: 60,
                            child: Text(
                              '${r.totalSessions}',
                              style: textTheme.bodySmall,
                              textAlign: TextAlign.right,
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              formatCurrency(r.totalRepass, r.currency),
                              style: textTheme.bodySmall,
                              textAlign: TextAlign.right,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                  ],
                ),
              ),
              // Subtotal row
              Container(
                color: colorScheme.surfaceContainerHighest,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Text(
                          'Subtotal — $beneficiary',
                          style: textTheme.bodySmall
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(width: 36),
                      const Expanded(flex: 2, child: SizedBox()),
                      const SizedBox(width: 60),
                      Expanded(
                        flex: 2,
                        child: Text(
                          formatCurrency(subtotal, currency),
                          style: textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                          textAlign: TextAlign.right,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1),
            ];
          }),
        ],
      ),
    );
  }
}
