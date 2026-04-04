import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:psyfinance_app/core/formatters.dart';
import 'package:psyfinance_app/features/patients/patient_model.dart';
import 'package:psyfinance_app/features/patients/patient_summary_model.dart';
import 'package:psyfinance_app/features/patients/patients_provider.dart';
import 'package:psyfinance_app/features/payments/payments_provider.dart';
import 'package:psyfinance_app/features/sessions/session_record_model.dart';
import 'package:psyfinance_app/features/sessions/sessions_provider.dart';

// ---------------------------------------------------------------------------
// Public entry point
// ---------------------------------------------------------------------------

/// Opens [SessionEntryContent] as a draggable modal bottom sheet.
void showSessionEntrySheet(
  BuildContext context, {
  required Patient patient,
  required int year,
  required int month,
  required VoidCallback onSaved,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scrollController) => SessionEntryContent(
        patient: patient,
        year: year,
        month: month,
        scrollController: scrollController,
        onSaved: onSaved,
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// SessionEntrySheet — thin wrapper for navigation / convenience
// ---------------------------------------------------------------------------

/// A self-contained DraggableScrollableSheet widget.
/// For tests, pump [SessionEntryContent] directly instead.
class SessionEntrySheet extends StatelessWidget {
  final Patient patient;
  final int year;
  final int month;
  final VoidCallback? onSaved;

  const SessionEntrySheet({
    super.key,
    required this.patient,
    required this.year,
    required this.month,
    this.onSaved,
  });

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scrollController) => SessionEntryContent(
        patient: patient,
        year: year,
        month: month,
        scrollController: scrollController,
        onSaved: onSaved,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// SessionEntryContent — the actual form widget (directly testable)
// ---------------------------------------------------------------------------

class SessionEntryContent extends ConsumerStatefulWidget {
  final Patient patient;
  final int year;
  final int month;
  final VoidCallback? onSaved;

  /// Provided by DraggableScrollableSheet in production; null in tests.
  final ScrollController? scrollController;

  const SessionEntryContent({
    super.key,
    required this.patient,
    required this.year,
    required this.month,
    this.scrollController,
    this.onSaved,
  });

  @override
  ConsumerState<SessionEntryContent> createState() =>
      _SessionEntryContentState();
}

class _SessionEntryContentState extends ConsumerState<SessionEntryContent> {
  final Set<int> _selectedDays = {};
  bool _isReposicao = false;
  final _obsController = TextEditingController();

  bool _saving = false;
  String? _saveError;

  SessionRecord? _currentRecord;

  @override
  void initState() {
    super.initState();
    _prefillFromExistingSession();
  }

  Future<void> _prefillFromExistingSession() async {
    try {
      final record = await ref.read(sessionsRepositoryProvider).getSession(
            widget.patient.id,
            widget.year,
            widget.month,
          );
      if (mounted && record != null) {
        setState(() {
          _currentRecord = record;
          _initFromRecord(record);
        });
      }
    } catch (_) {
      // Pre-fill is best-effort; form stays empty on error.
    }
  }

  @override
  void dispose() {
    _obsController.dispose();
    super.dispose();
  }

  SessionArgs get _sessionArgs => (
        patientId: widget.patient.id,
        year: widget.year,
        month: widget.month,
      );

  void _initFromRecord(SessionRecord? record) {
    if (record == null) return;
    _selectedDays
      ..clear()
      ..addAll(record.sessionDates.map((d) => DateTime.parse(d).day));
    _isReposicao = record.isReposicao;
    _obsController.text = record.observations ?? '';
  }

  void _toggleDay(int day) =>
      setState(() => _selectedDays.contains(day)
          ? _selectedDays.remove(day)
          : _selectedDays.add(day));

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _saveError = null;
    });

    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    final monthStr = widget.month.toString().padLeft(2, '0');
    final dates = _selectedDays.map((day) {
      return '${widget.year}-$monthStr-${day.toString().padLeft(2, '0')}';
    }).toList()
      ..sort();

    final dto = SaveSessionDto(
      sessionDates: dates,
      observations: _obsController.text.trim().isEmpty
          ? null
          : _obsController.text.trim(),
      isReposicao: _isReposicao,
    );

    try {
      final saved = await ref
          .read(sessionsRepositoryProvider)
          .saveSession(widget.patient.id, widget.year, widget.month, dto);

      if (mounted) setState(() => _currentRecord = saved);

      ref.invalidate(sessionProvider(_sessionArgs));
      ref.invalidate(patientSummaryProvider(
          (patientId: widget.patient.id, year: widget.year)));

      widget.onSaved?.call();

      if (mounted) {
        navigator.pop();
        messenger.showSnackBar(
            const SnackBar(content: Text('Sessões salvas')));
      }
    } catch (e) {
      setState(() {
        _saveError = e is Exception
            ? e.toString().replaceAll('Exception: ', '')
            : 'Erro ao salvar';
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final title = 'Sessões — ${monthName(widget.month)} ${widget.year}';

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        children: [
          // Drag handle
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: cs.onSurfaceVariant.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // Title
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                title,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const Divider(height: 1),
          // Scrollable content
          Expanded(
            child: ListView(
                    controller: widget.scrollController,
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                    children: [
                      _SessionsSection(
                        patient: widget.patient,
                        year: widget.year,
                        month: widget.month,
                        selectedDays: _selectedDays,
                        isReposicao: _isReposicao,
                        obsController: _obsController,
                        onDayToggle: _toggleDay,
                        onReposicaoChanged: (v) =>
                            setState(() => _isReposicao = v),
                      ),
                      const SizedBox(height: 24),
                      const Divider(height: 1),
                      const SizedBox(height: 24),
                      _PaymentSection(
                        record: _currentRecord,
                        patient: widget.patient,
                        year: widget.year,
                        month: widget.month,
                        onSaved: () => ref.invalidate(patientSummaryProvider(
                            (patientId: widget.patient.id, year: widget.year))),
                      ),
                      const SizedBox(height: 24),
                      if (_saveError != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            _saveError!,
                            style:
                                TextStyle(color: cs.error, fontSize: 13),
                          ),
                        ),
                      FilledButton(
                        onPressed: _saving ? null : _save,
                        child: _saving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Text('Salvar sessões'),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sessions section
// ---------------------------------------------------------------------------

class _SessionsSection extends StatelessWidget {
  final Patient patient;
  final int year;
  final int month;
  final Set<int> selectedDays;
  final bool isReposicao;
  final TextEditingController obsController;
  final void Function(int day) onDayToggle;
  final void Function(bool) onReposicaoChanged;

  const _SessionsSection({
    required this.patient,
    required this.year,
    required this.month,
    required this.selectedDays,
    required this.isReposicao,
    required this.obsController,
    required this.onDayToggle,
    required this.onReposicaoChanged,
  });

  @override
  Widget build(BuildContext context) {
    final sortedDays = selectedDays.toList()..sort();
    final monthStr = month.toString().padLeft(2, '0');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Sessões',
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        _MiniCalendar(
          year: year,
          month: month,
          selectedDays: selectedDays,
          onDayToggle: onDayToggle,
        ),
        const SizedBox(height: 12),
        if (sortedDays.isNotEmpty)
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: sortedDays.map((day) {
              final label =
                  '${day.toString().padLeft(2, '0')}/$monthStr';
              return Chip(
                label: Text(label, style: const TextStyle(fontSize: 12)),
                deleteIcon: const Icon(Icons.close, size: 16),
                onDeleted: () => onDayToggle(day),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              );
            }).toList(),
          ),
        const SizedBox(height: 8),
        _LiveTotal(patient: patient, sessionCount: selectedDays.length),
        const SizedBox(height: 8),
        SwitchListTile(
          value: isReposicao,
          onChanged: onReposicaoChanged,
          title: const Text('Reposição'),
          contentPadding: EdgeInsets.zero,
          dense: true,
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: obsController,
          minLines: 2,
          maxLines: null,
          decoration: const InputDecoration(
            labelText: 'Observações',
            alignLabelWithHint: true,
            border: OutlineInputBorder(),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Live total
// ---------------------------------------------------------------------------

class _LiveTotal extends StatelessWidget {
  final Patient patient;
  final int sessionCount;

  const _LiveTotal({required this.patient, required this.sessionCount});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rate = patient.currentRate ?? 0.0;
    final currencyStr = patient.currency.apiValue;

    final String text;
    if (patient.paymentModel == PaymentModel.mensal) {
      text = 'Mensal — ${formatCurrency(rate, currencyStr)} (fixo)';
    } else {
      final total = sessionCount * rate;
      text = '$sessionCount '
          '${sessionCount == 1 ? 'sessão' : 'sessões'} × '
          '${formatCurrency(rate, currencyStr)} = '
          '${formatCurrency(total, currencyStr)}';
    }

    return Text(
      text,
      style: TextStyle(
        fontSize: 13,
        color: cs.onSurfaceVariant,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Mini calendar
// ---------------------------------------------------------------------------

class _MiniCalendar extends StatelessWidget {
  final int year;
  final int month;
  final Set<int> selectedDays;
  final void Function(int day) onDayToggle;

  const _MiniCalendar({
    required this.year,
    required this.month,
    required this.selectedDays,
    required this.onDayToggle,
  });

  static const _headers = ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom'];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final firstDay = DateTime(year, month, 1);
    final startOffset = firstDay.weekday - 1; // Mon=0 … Sun=6
    final daysInMonth = DateUtils.getDaysInMonth(year, month);
    final rowCount = ((startOffset + daysInMonth) / 7).ceil();

    return Column(
      children: [
        Row(
          children: _headers
              .map(
                (h) => Expanded(
                  child: Center(
                    child: Text(
                      h,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 4),
        for (int row = 0; row < rowCount; row++)
          Row(
            children: [
              for (int col = 0; col < 7; col++)
                Expanded(
                  child: _DayCell(
                    cellIndex: row * 7 + col,
                    startOffset: startOffset,
                    daysInMonth: daysInMonth,
                    selectedDays: selectedDays,
                    onDayToggle: onDayToggle,
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  final int cellIndex;
  final int startOffset;
  final int daysInMonth;
  final Set<int> selectedDays;
  final void Function(int day) onDayToggle;

  const _DayCell({
    required this.cellIndex,
    required this.startOffset,
    required this.daysInMonth,
    required this.selectedDays,
    required this.onDayToggle,
  });

  @override
  Widget build(BuildContext context) {
    if (cellIndex < startOffset ||
        cellIndex >= startOffset + daysInMonth) {
      return const SizedBox(height: 36);
    }

    final day = cellIndex - startOffset + 1;
    final isSelected = selectedDays.contains(day);
    final cs = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: () => onDayToggle(day),
      child: Container(
        height: 36,
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: isSelected ? cs.primaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Center(
          child: Text(
            '$day',
            style: TextStyle(
              fontSize: 13,
              color: isSelected ? cs.onPrimaryContainer : cs.onSurface,
              fontWeight:
                  isSelected ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Payment section
// ---------------------------------------------------------------------------

MonthPaymentStatus _deriveStatus(
    double amountPaid, double expectedAmount, int year, int month) {
  if (amountPaid >= expectedAmount) return MonthPaymentStatus.pago;
  final now = DateTime.now();
  final isPast =
      year < now.year || (year == now.year && month < now.month);
  if (isPast && amountPaid < expectedAmount) return MonthPaymentStatus.atrasado;
  if (amountPaid > 0) return MonthPaymentStatus.parcial;
  return MonthPaymentStatus.pendente;
}

class _PaymentSection extends ConsumerStatefulWidget {
  final SessionRecord? record;
  final Patient patient;
  final int year;
  final int month;
  final VoidCallback? onSaved;

  const _PaymentSection({
    required this.record,
    required this.patient,
    required this.year,
    required this.month,
    this.onSaved,
  });

  @override
  ConsumerState<_PaymentSection> createState() => _PaymentSectionState();
}

class _PaymentSectionState extends ConsumerState<_PaymentSection> {
  late TextEditingController _controller;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: _initialText,
    );
  }

  String get _initialText {
    final paid = widget.record?.payment?.amountPaid ?? 0.0;
    return paid == 0 ? '0' : paid.toStringAsFixed(2);
  }

  @override
  void didUpdateWidget(_PaymentSection old) {
    super.didUpdateWidget(old);
    if (old.record?.id != widget.record?.id) {
      _controller.text = _initialText;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double get _parsedAmount =>
      double.tryParse(_controller.text.replaceAll(',', '.')) ?? 0.0;

  Future<void> _savePayment() async {
    final sessionRecordId = widget.record?.id;
    if (sessionRecordId == null) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await ref
          .read(paymentsRepositoryProvider)
          .updatePayment(sessionRecordId, _parsedAmount);
      widget.onSaved?.call();
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pagamento salvo')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e is Exception
              ? e.toString().replaceAll('Exception: ', '')
              : 'Erro ao salvar pagamento';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final record = widget.record;
    final currencyStr = widget.patient.currency.apiValue;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Pagamento',
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        if (record == null) ...[
          Text(
            'Salve as sessões primeiro para registrar o pagamento.',
            style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
          ),
        ] else ...[
          // Valor esperado
          _PaymentRow(
            label: 'Valor esperado',
            child: Text(
              formatCurrency(record.expectedAmount, currencyStr),
              style: const TextStyle(fontSize: 14),
              textAlign: TextAlign.right,
            ),
          ),
          const SizedBox(height: 8),
          // Pago até o momento
          _PaymentRow(
            label: 'Pago até o momento',
            child: SizedBox(
              width: 100,
              child: TextField(
                controller: _controller,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 14),
                decoration: const InputDecoration(
                  isDense: true,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Saldo devedor
          Builder(builder: (context) {
            final saldo = record.expectedAmount - _parsedAmount;
            final isOwed = saldo > 0;
            return _PaymentRow(
              label: 'Saldo devedor',
              child: Text(
                formatCurrency(saldo, currencyStr),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: isOwed ? cs.error : const Color(0xFF1B5E20),
                ),
                textAlign: TextAlign.right,
              ),
            );
          }),
          const SizedBox(height: 12),
          // Status chip
          _SheetStatusChip(
            status: _deriveStatus(
              _parsedAmount,
              record.expectedAmount,
              widget.year,
              widget.month,
            ),
          ),
          const SizedBox(height: 16),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(_error!,
                  style: TextStyle(color: cs.error, fontSize: 13)),
            ),
          OutlinedButton(
            onPressed: _saving ? null : _savePayment,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Salvar pagamento'),
          ),
        ],
      ],
    );
  }
}

class _PaymentRow extends StatelessWidget {
  final String label;
  final Widget child;

  const _PaymentRow({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(label, style: const TextStyle(fontSize: 14)),
        ),
        child,
      ],
    );
  }
}

class _SheetStatusChip extends StatelessWidget {
  final MonthPaymentStatus status;

  const _SheetStatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (bg, fg) = switch (status) {
      MonthPaymentStatus.pago => (
          const Color(0xFFE8F5E9),
          const Color(0xFF1B5E20)
        ),
      MonthPaymentStatus.parcial => (
          const Color(0xFFFFF8E1),
          const Color(0xFFE65100)
        ),
      MonthPaymentStatus.pendente => (
          cs.surfaceVariant,
          cs.onSurfaceVariant
        ),
      MonthPaymentStatus.atrasado => (
          cs.errorContainer,
          cs.onErrorContainer
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Text(
        status.label,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: fg),
      ),
    );
  }
}
