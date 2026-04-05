import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shimmer/shimmer.dart';

import 'package:psyfinance_app/core/formatters.dart';
import 'payment_panel_model.dart';
import 'payment_panel_provider.dart';
import 'payments_provider.dart';
import 'payments_repository.dart';

// ---------------------------------------------------------------------------
// PagamentosScreen
// ---------------------------------------------------------------------------

class PagamentosScreen extends ConsumerStatefulWidget {
  const PagamentosScreen({super.key});

  @override
  ConsumerState<PagamentosScreen> createState() => _PagamentosScreenState();
}

class _PagamentosScreenState extends ConsumerState<PagamentosScreen> {
  late int _year;
  late int _month;

  // null = "Todos"
  String? _statusFilter;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _year = now.year;
    _month = now.month;
  }

  PaymentPanelArgs get _args => (year: _year, month: _month);

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

  Future<void> _exportCsv(List<PaymentPanelRow> rows) async {
    final buffer = StringBuffer();
    buffer.writeln(
        '"Paciente","Localização","Moeda","Sessões","Esperado","Pago","Saldo","Status"');
    for (final row in rows) {
      final expected = row.sessionRecord.expectedAmount;
      final paid = row.payment.amountPaid;
      final saldo = expected - paid;
      buffer.writeln([
        '"${row.patient.name.replaceAll('"', '""')}"',
        '"${row.patient.location.replaceAll('"', '""')}"',
        '"${row.patient.currency}"',
        row.sessionRecord.sessionCount,
        expected.toStringAsFixed(2),
        paid.toStringAsFixed(2),
        saldo.toStringAsFixed(2),
        '"${row.payment.status}"',
      ].join(','));
    }

    final fileName =
        'pagamentos_${monthName(_month).toLowerCase()}_$_year.csv';

    try {
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Salvar CSV de pagamentos',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );
      if (path == null) return;
      await File(path).writeAsString(buffer.toString());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Exportado para $path')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erro ao exportar CSV')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final asyncPanel = ref.watch(paymentPanelProvider(_args));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PagamentosAppBar(
          year: _year,
          month: _month,
          onPrev: _prevMonth,
          onNext: _nextMonth,
          onExport: asyncPanel.value == null
              ? null
              : () {
                  final rows = asyncPanel.value!.payments;
                  final filtered = _statusFilter == null
                      ? rows
                      : rows
                          .where((r) => r.payment.status == _statusFilter)
                          .toList();
                  _exportCsv(filtered);
                },
        ),
        asyncPanel.when(
          loading: () => const Expanded(child: _ShimmerSkeleton()),
          error: (e, _) => Expanded(
            child: Center(
              child: Text(
                e.toString(),
                style: TextStyle(
                    color: Theme.of(context).colorScheme.error),
              ),
            ),
          ),
          data: (panel) => _PagamentosBody(
            panel: panel,
            statusFilter: _statusFilter,
            args: _args,
            onStatusFilterChanged: (s) => setState(() => _statusFilter = s),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// App bar — title, month navigator, export button
// ---------------------------------------------------------------------------

class _PagamentosAppBar extends StatelessWidget {
  final int year;
  final int month;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback? onExport;

  const _PagamentosAppBar({
    required this.year,
    required this.month,
    required this.onPrev,
    required this.onNext,
    required this.onExport,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: cs.surface,
        border:
            Border(bottom: BorderSide(color: cs.outlineVariant, width: 1)),
      ),
      child: Row(
        children: [
          Text(
            'Pagamentos',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 24),
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
          OutlinedButton.icon(
            onPressed: onExport,
            icon: const Icon(Icons.download_outlined, size: 16),
            label: const Text('Exportar'),
            style: OutlinedButton.styleFrom(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              visualDensity: VisualDensity.compact,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Body — summary strip + filter chips + table
// ---------------------------------------------------------------------------

class _PagamentosBody extends StatelessWidget {
  final PaymentPanel panel;
  final String? statusFilter; // null = "Todos"
  final PaymentPanelArgs args;
  final ValueChanged<String?> onStatusFilterChanged;

  const _PagamentosBody({
    required this.panel,
    required this.statusFilter,
    required this.args,
    required this.onStatusFilterChanged,
  });

  List<PaymentPanelRow> get _filtered {
    if (statusFilter == null) return panel.payments;
    return panel.payments
        .where((r) => r.payment.status == statusFilter)
        .toList();
  }

  int _countForStatus(String status) =>
      panel.payments.where((r) => r.payment.status == status).length;

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;

    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SummaryStrip(panel: panel),
          _StatusFilterRow(
            allRows: panel.payments,
            statusFilter: statusFilter,
            countAtrasado: _countForStatus('ATRASADO'),
            countPendente: _countForStatus('PENDENTE'),
            countParcial: _countForStatus('PARCIAL'),
            countPago: _countForStatus('PAGO'),
            onChanged: onStatusFilterChanged,
          ),
          Expanded(
            child: filtered.isEmpty
                ? _EmptyState(
                    onClearFilter: statusFilter != null
                        ? () => onStatusFilterChanged(null)
                        : null,
                  )
                : _PaymentTable(
                    rows: filtered,
                    args: args,
                  ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Summary strip — two currency cards
// ---------------------------------------------------------------------------

class _SummaryStrip extends StatelessWidget {
  final PaymentPanel panel;

  const _SummaryStrip({required this.panel});

  @override
  Widget build(BuildContext context) {
    final brl = panel.summary['BRL'] ?? PanelCurrencySummary.zero();
    final eur = panel.summary['EUR'] ?? PanelCurrencySummary.zero();

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
            child: _PanelCurrencyCard(
              currency: 'BRL',
              currencyName: 'Real brasileiro',
              summary: brl,
              accentColor: const Color(0xFF2E7D32),
              barColor: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _PanelCurrencyCard(
              currency: 'EUR',
              currencyName: 'Euro',
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

class _PanelCurrencyCard extends StatelessWidget {
  final String currency;
  final String currencyName;
  final PanelCurrencySummary summary;
  final Color accentColor;
  final Color barColor;

  const _PanelCurrencyCard({
    required this.currency,
    required this.currencyName,
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
    final outstanding = formatCurrency(summary.totalOutstanding, currency);
    final progress = summary.totalExpected > 0
        ? (summary.totalReceived / summary.totalExpected).clamp(0.0, 1.0)
        : 0.0;

    final hasOutstanding = summary.totalOutstanding > 0.005;
    final hasOverdue = summary.countOverdue > 0;

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
                value: progress.toDouble(),
                minHeight: 4,
                backgroundColor: barColor.withValues(alpha: 0.15),
                valueColor: AlwaysStoppedAnimation<Color>(barColor),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Flexible(
                  child: Text(
                    '$outstanding em aberto'
                    '${summary.countOverdue > 0 ? '  ·  ${summary.countOverdue} atrasado${summary.countOverdue == 1 ? '' : 's'}' : ''}',
                    style: TextStyle(
                      fontSize: 12,
                      color: (hasOutstanding || hasOverdue)
                          ? cs.error
                          : cs.onSurfaceVariant,
                      fontWeight: (hasOutstanding || hasOverdue)
                          ? FontWeight.w500
                          : null,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
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
// Status filter chips
// ---------------------------------------------------------------------------

class _StatusFilterRow extends StatelessWidget {
  final List<PaymentPanelRow> allRows;
  final String? statusFilter;
  final int countAtrasado;
  final int countPendente;
  final int countParcial;
  final int countPago;
  final ValueChanged<String?> onChanged;

  const _StatusFilterRow({
    required this.allRows,
    required this.statusFilter,
    required this.countAtrasado,
    required this.countPendente,
    required this.countParcial,
    required this.countPago,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        border: Border(
            bottom: BorderSide(color: cs.outlineVariant, width: 0.5)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _StatusChipFilter(
              label: 'Todos',
              count: allRows.length,
              active: statusFilter == null,
              bg: cs.secondaryContainer,
              fg: cs.onSecondaryContainer,
              onTap: () => onChanged(null),
            ),
            const SizedBox(width: 8),
            _StatusChipFilter(
              label: 'Atrasado',
              count: countAtrasado,
              active: statusFilter == 'ATRASADO',
              bg: cs.errorContainer,
              fg: cs.onErrorContainer,
              onTap: () =>
                  onChanged(statusFilter == 'ATRASADO' ? null : 'ATRASADO'),
            ),
            const SizedBox(width: 8),
            _StatusChipFilter(
              label: 'Pendente',
              count: countPendente,
              active: statusFilter == 'PENDENTE',
              bg: cs.surfaceVariant,
              fg: cs.onSurfaceVariant,
              onTap: () =>
                  onChanged(statusFilter == 'PENDENTE' ? null : 'PENDENTE'),
            ),
            const SizedBox(width: 8),
            _StatusChipFilter(
              label: 'Parcial',
              count: countParcial,
              active: statusFilter == 'PARCIAL',
              bg: const Color(0xFFFFF8E1),
              fg: const Color(0xFFE65100),
              onTap: () =>
                  onChanged(statusFilter == 'PARCIAL' ? null : 'PARCIAL'),
            ),
            const SizedBox(width: 8),
            _StatusChipFilter(
              label: 'Pago',
              count: countPago,
              active: statusFilter == 'PAGO',
              bg: const Color(0xFFE8F5E9),
              fg: const Color(0xFF1B5E20),
              onTap: () =>
                  onChanged(statusFilter == 'PAGO' ? null : 'PAGO'),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChipFilter extends StatelessWidget {
  final String label;
  final int count;
  final bool active;
  final Color bg;
  final Color fg;
  final VoidCallback onTap;

  const _StatusChipFilter({
    required this.label,
    required this.count,
    required this.active,
    required this.bg,
    required this.fg,
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
          color: active ? bg : Colors.transparent,
          border: Border.all(
            color: active ? fg : cs.outline,
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          '$label ($count)',
          style: TextStyle(
            fontSize: 13,
            color: active ? fg : cs.onSurface,
            fontWeight: active ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Payment table
// ---------------------------------------------------------------------------

class _PaymentTable extends StatelessWidget {
  final List<PaymentPanelRow> rows;
  final PaymentPanelArgs args;

  const _PaymentTable({required this.rows, required this.args});

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _TableHeader()),
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (ctx, i) => _PaymentRow(row: rows[i], args: args),
            childCount: rows.length,
          ),
        ),
      ],
    );
  }
}

class _TableHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      color: cs.surfaceContainerLow,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: const Row(
        children: [
          _HeaderCell('Paciente', flex: 4),
          _HeaderCell('Moeda', flex: 2),
          _HeaderCell('Sessões', flex: 2),
          _HeaderCell('Esperado', flex: 3),
          _HeaderCell('Pago', flex: 3),
          _HeaderCell('Saldo', flex: 3),
          _HeaderCell('Status', flex: 3),
          _HeaderCell('Ação', flex: 2),
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
// Payment row — manages its own inline payment edit state
// ---------------------------------------------------------------------------

class _PaymentRow extends ConsumerStatefulWidget {
  final PaymentPanelRow row;
  final PaymentPanelArgs args;

  const _PaymentRow({required this.row, required this.args});

  @override
  ConsumerState<_PaymentRow> createState() => _PaymentRowState();
}

class _PaymentRowState extends ConsumerState<_PaymentRow> {
  bool _editingPayment = false;
  late TextEditingController _payCtrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _payCtrl = TextEditingController(text: _initialPayText);
  }

  @override
  void didUpdateWidget(_PaymentRow old) {
    super.didUpdateWidget(old);
    if (old.row.payment.amountPaid != widget.row.payment.amountPaid &&
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
    final paid = widget.row.payment.amountPaid;
    return paid == 0 ? '0' : paid.toStringAsFixed(2);
  }

  double get _parsedAmount =>
      double.tryParse(_payCtrl.text.replaceAll(',', '.')) ?? 0.0;

  Future<void> _savePayment(double amount) async {
    final sessionRecordId = widget.row.sessionRecord.id;
    setState(() => _saving = true);
    try {
      final payment = await ref
          .read(paymentsRepositoryProvider)
          .updatePayment(sessionRecordId, amount);
      ref.read(paymentPanelProvider(widget.args).notifier).updateRow(
            sessionRecordId,
            payment.amountPaid,
            payment.status,
          );
      if (mounted) {
        setState(() {
          _editingPayment = false;
          _saving = false;
        });
      }
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

  Future<void> _confirmPayment() => _savePayment(_parsedAmount);

  Future<void> _markAsPago() async {
    final expected = widget.row.sessionRecord.expectedAmount;
    await _savePayment(expected);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('${widget.row.patient.name} marcado como pago.')),
      );
    }
  }

  Future<void> _undoPayment() async {
    await _savePayment(0);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                'Pagamento de ${widget.row.patient.name} revertido.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final row = widget.row;
    final currency = row.patient.currency;
    final isAtrasado = row.payment.status == 'ATRASADO';
    final isPago = row.payment.status == 'PAGO';

    Color? rowBg;
    if (isAtrasado) rowBg = cs.errorContainer.withValues(alpha: 0.3);

    final saldo =
        row.sessionRecord.expectedAmount - row.payment.amountPaid;

    return Container(
      decoration: BoxDecoration(
        color: rowBg,
        border: Border(
            bottom: BorderSide(color: cs.outlineVariant, width: 0.5)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Paciente
          Expanded(
            flex: 4,
            child: Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: cs.primaryContainer,
                  child: Text(
                    row.patient.name.isNotEmpty
                        ? row.patient.name[0].toUpperCase()
                        : '?',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: cs.onPrimaryContainer),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        row.patient.name,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w500),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        row.patient.location,
                        style: TextStyle(
                            fontSize: 11, color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Moeda
          Expanded(
            flex: 2,
            child: _CurrencyBadge(
              symbol: currency == 'EUR' ? '€' : 'R\$',
              color: currency == 'EUR'
                  ? const Color(0xFF1565C0)
                  : const Color(0xFF2E7D32),
            ),
          ),
          // Sessões
          Expanded(
            flex: 2,
            child: Text(
              '${row.sessionRecord.sessionCount}',
              style: const TextStyle(fontSize: 13),
            ),
          ),
          // Esperado
          Expanded(
            flex: 3,
            child: Text(
              formatCurrency(row.sessionRecord.expectedAmount, currency),
              style: const TextStyle(fontSize: 13),
            ),
          ),
          // Pago — inline edit
          Expanded(
            flex: 3,
            child: _editingPayment
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
                                  size: 16, color: Color(0xFF2E7D32)),
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
                      formatCurrency(row.payment.amountPaid, currency),
                      style: const TextStyle(
                        fontSize: 13,
                        decoration: TextDecoration.underline,
                        decorationStyle: TextDecorationStyle.dotted,
                      ),
                    ),
                  ),
          ),
          // Saldo
          Expanded(
            flex: 3,
            child: Text(
              formatCurrency(saldo, currency),
              style: TextStyle(
                fontSize: 13,
                color: saldo > 0.005 ? cs.error : const Color(0xFF2E7D32),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          // Status
          Expanded(
            flex: 3,
            child: _StatusChip(status: row.payment.status),
          ),
          // Ação
          Expanded(
            flex: 2,
            child: _saving
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child:
                        CircularProgressIndicator(strokeWidth: 2),
                  )
                : isPago
                    ? Tooltip(
                        message: 'Desfazer pagamento',
                        child: IconButton(
                          icon: Icon(Icons.undo,
                              size: 20, color: cs.onSurfaceVariant),
                          onPressed: _undoPayment,
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                        ),
                      )
                    : Tooltip(
                        message: 'Marcar como pago',
                        child: IconButton(
                          icon: const Icon(Icons.check_circle_outline,
                              size: 20, color: Color(0xFF2E7D32)),
                          onPressed: _markAsPago,
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                        ),
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
          const Color(0xFFE65100),
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
  final VoidCallback? onClearFilter;

  const _EmptyState({this.onClearFilter});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.payments_outlined,
            size: 48,
            color: cs.onSurfaceVariant.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            'Nenhum pagamento encontrado para este filtro.',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
            textAlign: TextAlign.center,
          ),
          if (onClearFilter != null) ...[
            const SizedBox(height: 12),
            TextButton(
              onPressed: onClearFilter,
              child: const Text('Ver todos'),
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
  const _ShimmerSkeleton();

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      child: ListView(
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
          // Filter chips skeleton
          Container(
            height: 40,
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
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
