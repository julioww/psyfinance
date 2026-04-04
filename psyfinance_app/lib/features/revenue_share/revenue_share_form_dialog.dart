import 'package:flutter/material.dart';
import 'revenue_share_model.dart';

// ---------------------------------------------------------------------------
// RevenueShareFormDialog
// ---------------------------------------------------------------------------

/// Shows an AlertDialog to create or edit a RevenueShareConfig.
/// Returns [RevenueShareDto] if saved, null if cancelled.
Future<RevenueShareDto?> showRevenueShareFormDialog(
  BuildContext context, {
  RevenueShareConfig? existing,
}) {
  return showDialog<RevenueShareDto>(
    context: context,
    builder: (_) => RevenueShareFormDialog(existing: existing),
  );
}

class RevenueShareFormDialog extends StatefulWidget {
  final RevenueShareConfig? existing;

  const RevenueShareFormDialog({super.key, this.existing});

  @override
  State<RevenueShareFormDialog> createState() => _RevenueShareFormDialogState();
}

class _RevenueShareFormDialogState extends State<RevenueShareFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late ShareType _shareType;
  late TextEditingController _valueCtrl;
  late TextEditingController _nameCtrl;

  @override
  void initState() {
    super.initState();
    _shareType = widget.existing?.shareType ?? ShareType.percentage;
    _valueCtrl = TextEditingController(
      text: widget.existing != null
          ? widget.existing!.shareValue.toStringAsFixed(
              widget.existing!.shareType == ShareType.percentage ? 0 : 2)
          : '',
    );
    _nameCtrl =
        TextEditingController(text: widget.existing?.beneficiaryName ?? '');
  }

  @override
  void dispose() {
    _valueCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;

    final value = double.tryParse(_valueCtrl.text.replaceAll(',', '.'));
    if (value == null || value <= 0) return;

    Navigator.of(context).pop(
      RevenueShareDto(
        shareType: _shareType,
        shareValue: value,
        beneficiaryName: _nameCtrl.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isPercent = _shareType == ShareType.percentage;

    return AlertDialog(
      title: Text(
        widget.existing == null ? 'Configurar repasse' : 'Editar repasse',
      ),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Type selector
            SegmentedButton<ShareType>(
              segments: const [
                ButtonSegment(
                  value: ShareType.percentage,
                  label: Text('Percentual'),
                  icon: Icon(Icons.percent, size: 16),
                ),
                ButtonSegment(
                  value: ShareType.fixedPerSession,
                  label: Text('Fixo/sessão'),
                  icon: Icon(Icons.attach_money, size: 16),
                ),
              ],
              selected: {_shareType},
              onSelectionChanged: (s) => setState(() {
                _shareType = s.first;
                _valueCtrl.clear();
              }),
              style: ButtonStyle(
                visualDensity: VisualDensity.compact,
                textStyle: WidgetStatePropertyAll(
                  Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Value field
            TextFormField(
              controller: _valueCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: isPercent ? 'Percentual (%)' : 'Valor por sessão',
                prefixText: isPercent ? null : 'R\$ ',
                suffixText: isPercent ? '%' : null,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              validator: (v) {
                final parsed = double.tryParse((v ?? '').replaceAll(',', '.'));
                if (parsed == null || parsed <= 0) {
                  return 'Informe um valor positivo';
                }
                if (isPercent && parsed > 100) {
                  return 'Percentual não pode ser maior que 100';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            // Beneficiary name
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Nome do beneficiário',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Nome obrigatório' : null,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            'Cancelar',
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text('Salvar'),
        ),
      ],
    );
  }
}
