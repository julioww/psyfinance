import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:psyfinance_app/features/dashboard/dashboard_model.dart';
import 'package:psyfinance_app/features/dashboard/dashboard_provider.dart';
import 'package:psyfinance_app/features/dashboard/export_button.dart';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const _kAvailableYears = [2023, 2024, 2025, 2026];

const _kYearColors = {
  2023: Color(0xFF6B8F71),
  2024: Color(0xFF4A7B9D),
  2025: Color(0xFF9B6B9B),
  2026: Color(0xFF1A6B5A),
};

// ---------------------------------------------------------------------------
// RelatorioScreen
// ---------------------------------------------------------------------------

class RelatorioScreen extends ConsumerStatefulWidget {
  const RelatorioScreen({super.key});

  @override
  ConsumerState<RelatorioScreen> createState() => _RelatorioState();
}

class _RelatorioState extends ConsumerState<RelatorioScreen> {
  final Set<int> _selectedYears = Set.from(_kAvailableYears);

  void _toggleYear(int year) {
    if (_selectedYears.contains(year) && _selectedYears.length == 1) return;
    setState(() {
      if (_selectedYears.contains(year)) {
        _selectedYears.remove(year);
      } else {
        _selectedYears.add(year);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(comparisonProvider);

    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text(e.toString())),
      data: (data) => _RelatorioBody(
        data: data,
        selectedYears: _selectedYears,
        onToggleYear: _toggleYear,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _RelatorioBody
// ---------------------------------------------------------------------------

class _RelatorioBody extends StatelessWidget {
  final List<YearlyComparison> data;
  final Set<int> selectedYears;
  final ValueChanged<int> onToggleYear;

  const _RelatorioBody({
    required this.data,
    required this.selectedYears,
    required this.onToggleYear,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Page header
          Row(
            children: [
              Text(
                'Relatório histórico',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                      fontSize: 16,
                    ),
              ),
              const Spacer(),
              ExportButton(
                type: ExportType.summary,
                format: ExportFormat.csv,
                year: DateTime.now().year.clamp(2023, 2026),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Year filter chips
          Row(
            children: [
              Text(
                'ANOS',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontSize: 11,
                      color: colorScheme.onSurfaceVariant,
                      letterSpacing: 0.8,
                    ),
              ),
              const SizedBox(width: 8),
              for (final year in _kAvailableYears) ...[
                FilterChip(
                  label: Text('$year'),
                  selected: selectedYears.contains(year),
                  onSelected: (_) => onToggleYear(year),
                  selectedColor:
                      (_kYearColors[year] ?? colorScheme.primary).withOpacity(0.2),
                  checkmarkColor: _kYearColors[year] ?? colorScheme.primary,
                  labelStyle: TextStyle(
                    color: selectedYears.contains(year)
                        ? (_kYearColors[year] ?? colorScheme.primary)
                        : colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(width: 6),
              ],
            ],
          ),
          const SizedBox(height: 16),

          // Sparkline cards
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _SparklineCard(
                  currency: 'BRL',
                  data: data,
                  selectedYears: selectedYears,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _SparklineCard(
                  currency: 'EUR',
                  data: data,
                  selectedYears: selectedYears,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Comparison tables
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _ComparisonTable(
                  currency: 'BRL',
                  data: data,
                  selectedYears: selectedYears,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ComparisonTable(
                  currency: 'EUR',
                  data: data,
                  selectedYears: selectedYears,
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
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
    final colorScheme = Theme.of(context).colorScheme;
    final isBrl = currency == 'BRL';
    final color = isBrl ? colorScheme.primary : const Color(0xFF3B82F6);
    final symbol = isBrl ? 'R\$' : '€';

    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      child: Text(
        symbol,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _SparklineCard
// ---------------------------------------------------------------------------

class _SparklineCard extends StatefulWidget {
  final String currency;
  final List<YearlyComparison> data;
  final Set<int> selectedYears;

  const _SparklineCard({
    required this.currency,
    required this.data,
    required this.selectedYears,
  });

  @override
  State<_SparklineCard> createState() => _SparklineCardState();
}

class _SparklineCardState extends State<_SparklineCard> {
  int? _touchedIndex;

  CurrencyYearData _forYear(int year) {
    final entry = widget.data.firstWhere(
      (e) => e.year == year,
      orElse: () => YearlyComparison(
        year: year,
        brl: const CurrencyYearData(
            sessions: 0, avgPricePerSession: 0, expected: 0, received: 0, balance: 0),
        eur: const CurrencyYearData(
            sessions: 0, avgPricePerSession: 0, expected: 0, received: 0, balance: 0),
      ),
    );
    return widget.currency == 'BRL' ? entry.brl : entry.eur;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isBrl = widget.currency == 'BRL';
    final currencyName = isBrl ? 'Real brasileiro' : 'Euro';
    final fmt = NumberFormat.currency(
      locale: isBrl ? 'pt_BR' : 'de_DE',
      symbol: isBrl ? 'R\$ ' : '€ ',
      decimalDigits: 0,
    );

    // Compute aggregates for selected years
    final selectedData = widget.selectedYears
        .map((y) => (year: y, d: _forYear(y)))
        .toList()
      ..sort((a, b) => a.year.compareTo(b.year));

    final totalReceived = selectedData.fold(0.0, (s, e) => s + e.d.received);
    final totalSessions = selectedData.fold(0, (s, e) => s + e.d.sessions);
    final avgPrice = totalSessions > 0 ? selectedData.fold(0.0, (s, e) => s + e.d.expected) / totalSessions : 0.0;

    double growth = 0;
    bool hasGrowth = false;
    if (selectedData.length >= 2) {
      final first = selectedData.first.d.received;
      final last = selectedData.last.d.received;
      if (first > 0) {
        growth = (last - first) / first * 100;
        hasGrowth = true;
      }
    }

    // Max value for bar height
    final maxVal = _kAvailableYears.fold(0.0, (m, y) {
      final d = _forYear(y);
      return d.received > m ? d.received : m;
    });

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
              _CurrencyBadge(currency: widget.currency),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.currency,
                    style: Theme.of(context)
                        .textTheme
                        .labelLarge
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    currencyName,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 11,
                        ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Sparkline bar chart
          SizedBox(
            height: 64,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: maxVal > 0 ? maxVal * 1.2 : 1,
                barTouchData: BarTouchData(
                  enabled: true,
                  touchCallback: (event, response) {
                    setState(() {
                      if (response?.spot != null &&
                          event is! FlPointerExitEvent) {
                        _touchedIndex = response!.spot!.touchedBarGroupIndex;
                      } else {
                        _touchedIndex = null;
                      }
                    });
                  },
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      final year = _kAvailableYears[groupIndex];
                      final val = _forYear(year).received;
                      return BarTooltipItem(
                        '$year\n${fmt.format(val)}',
                        const TextStyle(fontSize: 11),
                      );
                    },
                  ),
                ),
                titlesData: FlTitlesData(
                  show: true,
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (val, meta) {
                        final year = _kAvailableYears[val.toInt()];
                        return Text(
                          '${year % 100}',
                          style: const TextStyle(fontSize: 9),
                        );
                      },
                    ),
                  ),
                  leftTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                ),
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                barGroups: List.generate(_kAvailableYears.length, (i) {
                  final year = _kAvailableYears[i];
                  final color = _kYearColors[year] ?? colorScheme.primary;
                  final isActive = widget.selectedYears.contains(year);
                  return BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: _forYear(year).received,
                        color: color.withOpacity(isActive ? 1.0 : 0.15),
                        width: 16,
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(4)),
                      ),
                    ],
                    showingTooltipIndicators:
                        _touchedIndex == i ? [0] : [],
                  );
                }),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Stat chips
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              _StatChip(
                label: 'Total recebido',
                value: fmt.format(totalReceived),
              ),
              _StatChip(
                label: 'Preço médio/sessão',
                value: fmt.format(avgPrice),
                accent: colorScheme.primary,
              ),
              if (hasGrowth)
                _StatChip(
                  label: 'Crescimento',
                  value:
                      '${growth >= 0 ? '+' : ''}${growth.toStringAsFixed(1)}%',
                  accent: growth >= 0 ? const Color(0xFF22C55E) : colorScheme.error,
                )
              else
                const _StatChip(label: 'Crescimento', value: 'N/A'),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color? accent;

  const _StatChip({required this.label, required this.value, this.accent});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontSize: 10,
                ),
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: accent,
                  fontSize: 12,
                ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _ComparisonTable
// ---------------------------------------------------------------------------

class _ComparisonTable extends StatelessWidget {
  final String currency;
  final List<YearlyComparison> data;
  final Set<int> selectedYears;

  const _ComparisonTable({
    required this.currency,
    required this.data,
    required this.selectedYears,
  });

  CurrencyYearData _forYear(int year) {
    final entry = data.firstWhere(
      (e) => e.year == year,
      orElse: () => YearlyComparison(
        year: year,
        brl: const CurrencyYearData(
            sessions: 0, avgPricePerSession: 0, expected: 0, received: 0, balance: 0),
        eur: const CurrencyYearData(
            sessions: 0, avgPricePerSession: 0, expected: 0, received: 0, balance: 0),
      ),
    );
    return currency == 'BRL' ? entry.brl : entry.eur;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isBrl = currency == 'BRL';
    final fmt = NumberFormat.currency(
      locale: isBrl ? 'pt_BR' : 'de_DE',
      symbol: '',
      decimalDigits: 0,
    );

    final visibleYears = _kAvailableYears
        .where((y) => selectedYears.contains(y))
        .toList();

    // Total aggregates
    int totalSessions = 0;
    double totalExpected = 0, totalReceived = 0, totalBalance = 0;
    for (final y in visibleYears) {
      final d = _forYear(y);
      totalSessions += d.sessions;
      totalExpected += d.expected;
      totalReceived += d.received;
      totalBalance += d.balance;
    }
    final totalAvg = totalSessions > 0 ? totalExpected / totalSessions : 0.0;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.hardEdge,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Card header
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                _CurrencyBadge(currency: currency),
                const SizedBox(width: 8),
                Text(
                  currency,
                  style: Theme.of(context)
                      .textTheme
                      .labelLarge
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),

          // Column headers
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                _colHeader(context, 'Ano', flex: 2),
                _colHeader(context, 'Sess.', flex: 1),
                _colHeader(context, 'Preço médio', flex: 2,
                    color: colorScheme.primary),
                _colHeader(context, 'Esperado', flex: 2),
                _colHeader(context, 'Recebido', flex: 2),
                _colHeader(context, 'Saldo', flex: 2),
              ],
            ),
          ),
          const Divider(height: 1),

          // Data rows + vs sub-rows
          for (var i = 0; i < visibleYears.length; i++) ...[
            if (i > 0)
              _VsSubRow(
                prevYear: visibleYears[i - 1],
                currYear: visibleYears[i],
                prevData: _forYear(visibleYears[i - 1]),
                currData: _forYear(visibleYears[i]),
              ),
            _YearDataRow(
              year: visibleYears[i],
              d: _forYear(visibleYears[i]),
              fmt: fmt,
              primaryColor: colorScheme.primary,
            ),
          ],

          // Total row
          if (visibleYears.length > 1) ...[
            const Divider(height: 1),
            Container(
              color: colorScheme.surfaceContainerHigh,
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: Text(
                      'Total',
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 12),
                    ),
                  ),
                  Expanded(
                    flex: 1,
                    child: Text(
                      '$totalSessions',
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 12),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      fmt.format(totalAvg),
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                        color: colorScheme.primary,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      fmt.format(totalExpected),
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 12),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      fmt.format(totalReceived),
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 12),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      fmt.format(totalBalance),
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _colHeader(BuildContext context, String label,
      {required int flex, Color? color}) {
    return Expanded(
      flex: flex,
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w600,
              fontSize: 11,
              color: color ??
                  Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _YearDataRow
// ---------------------------------------------------------------------------

class _YearDataRow extends StatelessWidget {
  final int year;
  final CurrencyYearData d;
  final NumberFormat fmt;
  final Color primaryColor;

  const _YearDataRow({
    required this.year,
    required this.d,
    required this.fmt,
    required this.primaryColor,
  });

  @override
  Widget build(BuildContext context) {
    final yearColor = _kYearColors[year] ?? primaryColor;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: yearColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text('$year', style: const TextStyle(fontSize: 12)),
              ],
            ),
          ),
          Expanded(
            flex: 1,
            child: Text('${d.sessions}',
                style: const TextStyle(fontSize: 12)),
          ),
          Expanded(
            flex: 2,
            child: Text(
              fmt.format(d.avgPricePerSession),
              style: TextStyle(
                fontSize: 12,
                color: primaryColor,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(fmt.format(d.expected),
                style: const TextStyle(fontSize: 12)),
          ),
          Expanded(
            flex: 2,
            child: Text(fmt.format(d.received),
                style: const TextStyle(fontSize: 12)),
          ),
          Expanded(
            flex: 2,
            child: Text(fmt.format(d.balance),
                style: const TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _VsSubRow
// ---------------------------------------------------------------------------

class _VsSubRow extends StatelessWidget {
  final int prevYear;
  final int currYear;
  final CurrencyYearData prevData;
  final CurrencyYearData currData;

  const _VsSubRow({
    required this.prevYear,
    required this.currYear,
    required this.prevData,
    required this.currData,
  });

  double? _growth(double prev, double curr) {
    if (prev <= 0) return null;
    return (curr - prev) / prev * 100;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final avgGrowth =
        _growth(prevData.avgPricePerSession, currData.avgPricePerSession);
    final revGrowth = _growth(prevData.received, currData.received);

    return Container(
      color: colorScheme.surfaceContainerLow,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      child: Row(
        children: [
          Text(
            'vs $prevYear',
            style: TextStyle(
              fontSize: 10,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 8),
          if (avgGrowth != null)
            _GrowthChip(label: 'preço', pct: avgGrowth)
          else
            const SizedBox.shrink(),
          const SizedBox(width: 4),
          if (revGrowth != null)
            _GrowthChip(label: 'receita', pct: revGrowth)
          else
            const SizedBox.shrink(),
        ],
      ),
    );
  }
}

class _GrowthChip extends StatelessWidget {
  final String label;
  final double pct;

  const _GrowthChip({required this.label, required this.pct});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isPositive = pct > 0;
    final isZero = pct.abs() < 0.05;
    final color = isZero
        ? colorScheme.onSurfaceVariant
        : isPositive
            ? const Color(0xFF22C55E)
            : colorScheme.error;
    final sign = isPositive ? '+' : '';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '$label $sign${pct.toStringAsFixed(1)}%',
        style: TextStyle(
          fontSize: 10,
          color: color,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
