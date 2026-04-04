import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:psyfinance_app/core/api_client.dart';
import 'package:psyfinance_app/core/formatters.dart';
import 'patient_model.dart';
import 'patients_provider.dart';
import 'rate_history_model.dart';
import 'rate_history_provider.dart';

// ---------------------------------------------------------------------------
// RateHistoryWidget
// ---------------------------------------------------------------------------

class RateHistoryWidget extends ConsumerWidget {
  final String patientId;
  final PatientCurrency currency;

  const RateHistoryWidget({
    super.key,
    required this.patientId,
    required this.currency,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ratesAsync = ref.watch(rateHistoryProvider(patientId));

    return ratesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Text('Erro ao carregar taxas: $e'),
      data: (rates) => _buildContent(context, ref, rates),
    );
  }

  Widget _buildContent(BuildContext context, WidgetRef ref, List<RateHistory> rates) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...rates.map((r) => _RateEntry(rate: r, currency: currency)),
        TextButton.icon(
          onPressed: () => _showUpdateDialog(context, ref),
          icon: const Icon(Icons.add),
          label: const Text('Atualizar taxa'),
        ),
      ],
    );
  }

  void _showUpdateDialog(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (_) => RateUpdateDialog(
        patientId: patientId,
        currency: currency,
        onSuccess: () {
          ref.invalidate(rateHistoryProvider(patientId));
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Taxa atualizada')),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _RateEntry
// ---------------------------------------------------------------------------

class _RateEntry extends StatelessWidget {
  final RateHistory rate;
  final PatientCurrency currency;

  const _RateEntry({required this.rate, required this.currency});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isCurrent = rate.isCurrent;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 5.0, right: 12.0),
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isCurrent
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurface.withOpacity(0.35),
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      formatCurrency(rate.rate, currency.apiValue),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (isCurrent) ...[
                      const SizedBox(width: 8),
                      Chip(
                        label: const Text('atual'),
                        backgroundColor: theme.colorScheme.primaryContainer,
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        labelStyle: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                        side: BorderSide.none,
                        padding: EdgeInsets.zero,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  _dateRangeText(),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _dateRangeText() {
    if (rate.isCurrent) {
      return 'a partir de ${formatDate(rate.effectiveFrom)}';
    }
    return '${formatDate(rate.effectiveFrom)} – ${formatDate(rate.effectiveTo!)}';
  }
}

// ---------------------------------------------------------------------------
// RateUpdateDialog
// ---------------------------------------------------------------------------

class RateUpdateDialog extends ConsumerStatefulWidget {
  final String patientId;
  final PatientCurrency currency;
  final VoidCallback onSuccess;
  // Optional: pre-set the effective date (useful in tests to bypass the picker).
  final DateTime? initialEffectiveFrom;

  const RateUpdateDialog({
    super.key,
    required this.patientId,
    required this.currency,
    required this.onSuccess,
    this.initialEffectiveFrom,
  });

  @override
  ConsumerState<RateUpdateDialog> createState() => _RateUpdateDialogState();
}

class _RateUpdateDialogState extends ConsumerState<RateUpdateDialog> {
  final _formKey = GlobalKey<FormState>();
  final _rateController = TextEditingController();
  late DateTime? _effectiveFrom;
  String? _dateError;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _effectiveFrom = widget.initialEffectiveFrom;
  }

  @override
  void dispose() {
    _rateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Text('Atualizar taxa'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _rateController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Nova taxa'),
              validator: (v) {
                if (v == null || v.isEmpty) return 'Taxa é obrigatória';
                final n = double.tryParse(v.replaceAll(',', '.'));
                if (n == null || n <= 0) return 'Taxa deve ser maior que zero';
                return null;
              },
            ),
            const SizedBox(height: 16),
            InkWell(
              onTap: _pickDate,
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: 'Vigente a partir de',
                  errorText: _dateError,
                  suffixIcon: const Icon(Icons.calendar_today),
                ),
                child: Text(
                  _effectiveFrom != null ? formatDate(_effectiveFrom!) : '',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _isSubmitting ? null : _submit,
          child: const Text('Confirmar'),
        ),
      ],
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _effectiveFrom ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        _effectiveFrom = picked;
        _dateError = null;
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_effectiveFrom == null) {
      setState(() => _dateError = 'Selecione a data de vigência');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _dateError = null;
    });

    try {
      final rate = double.parse(_rateController.text.replaceAll(',', '.'));
      final repo = ref.read(patientsRepositoryProvider);
      await repo.addRate(widget.patientId, rate, _effectiveFrom!);

      if (mounted) {
        Navigator.of(context).pop();
        widget.onSuccess();
      }
    } on ApiException catch (e) {
      if (e.statusCode == 409) {
        setState(() {
          _dateError = e.message;
          _isSubmitting = false;
        });
      } else {
        setState(() => _isSubmitting = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.message)),
          );
        }
      }
    } catch (_) {
      setState(() => _isSubmitting = false);
    }
  }
}
