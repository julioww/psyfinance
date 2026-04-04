import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:psyfinance_app/core/api_client.dart';
import 'package:psyfinance_app/core/formatters.dart';
import 'package:psyfinance_app/features/monthly/monthly_provider.dart';
import 'package:psyfinance_app/features/patients/patient_model.dart';
import 'package:psyfinance_app/features/patients/patients_provider.dart';
import 'package:psyfinance_app/features/sessions/sessions_provider.dart';

// ---------------------------------------------------------------------------
// Country color palette — same deterministic system as monthly_bulk_screen
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

Color _avatarColor(String location) {
  final hash = location.codeUnits.fold(0, (acc, c) => acc + c);
  return _countryPalette[hash % _countryPalette.length];
}

// ---------------------------------------------------------------------------
// Public entry point
// ---------------------------------------------------------------------------

/// Opens the quick-add session bottom sheet. Calls [onSaved] after a
/// successful save so the caller can refresh the table.
void showQuickAddSessionSheet(
  BuildContext context, {
  String? prefilterCountry,
  required MonthlyArgs args,
  required void Function(String patientName, DateTime date) onSaved,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => Padding(
      // Shift up when keyboard opens
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: _QuickAddSessionSheet(
        prefilterCountry: prefilterCountry,
        args: args,
        onSaved: onSaved,
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Sheet widget
// ---------------------------------------------------------------------------

class _QuickAddSessionSheet extends ConsumerStatefulWidget {
  final String? prefilterCountry;
  final MonthlyArgs args;
  final void Function(String patientName, DateTime date) onSaved;

  const _QuickAddSessionSheet({
    required this.prefilterCountry,
    required this.args,
    required this.onSaved,
  });

  @override
  ConsumerState<_QuickAddSessionSheet> createState() =>
      _QuickAddSessionSheetState();
}

class _QuickAddSessionSheetState
    extends ConsumerState<_QuickAddSessionSheet> {
  Patient? _selectedPatient;
  DateTime _date = DateTime.now();
  final _obsController = TextEditingController();
  bool _saving = false;
  bool _duplicateError = false;
  late String? _activeCountryFilter;

  // Controller for the DropdownMenu text field
  final _patientController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _activeCountryFilter = widget.prefilterCountry;
  }

  @override
  void dispose() {
    _obsController.dispose();
    _patientController.dispose();
    super.dispose();
  }

  List<Patient> _filtered(List<Patient> all) {
    final active = all.where((p) => p.status == PatientStatus.ativo);
    final byCountry = _activeCountryFilter != null
        ? active.where((p) => p.location == _activeCountryFilter)
        : active;
    return byCountry.toList()..sort((a, b) => a.name.compareTo(b.name));
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        _date = picked;
        // Changing date clears a previous duplicate error
        _duplicateError = false;
      });
    }
  }

  Future<void> _save() async {
    if (_selectedPatient == null) return;
    setState(() {
      _saving = true;
      _duplicateError = false;
    });

    final repo = ref.read(sessionsRepositoryProvider);
    final obs = _obsController.text.trim().isEmpty
        ? null
        : _obsController.text.trim();

    try {
      await repo.quickAddSession(
        _selectedPatient!.id,
        _date,
        observations: obs,
      );

      // Refresh the bulk table
      ref
          .read(monthlyViewProvider(widget.args).notifier)
          .refreshAfterSessionSave();

      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      widget.onSaved(_selectedPatient!.name, _date);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Sessão de ${_selectedPatient!.name} registrada em ${_formatDate(_date)}.',
          ),
        ),
      );
    } on ApiException catch (e) {
      if (e.statusCode == 409) {
        setState(() {
          _duplicateError = true;
          _saving = false;
        });
      } else {
        setState(() => _saving = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.message)),
          );
        }
      }
    } catch (_) {
      setState(() => _saving = false);
    }
  }

  String _formatDate(DateTime d) => formatDate(d);

  String _todayLabel() {
    final now = DateTime.now();
    final isToday = _date.year == now.year &&
        _date.month == now.month &&
        _date.day == now.day;
    if (isToday) return 'Hoje, ${_formatDate(_date)}';
    return _formatDate(_date);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final patientsAsync = ref.watch(patientsProvider);

    return patientsAsync.when(
      loading: () => const SizedBox(
        height: 200,
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => SizedBox(
        height: 200,
        child: Center(child: Text(e.toString())),
      ),
      data: (allPatients) {
        final patients = _filtered(allPatients);
        return _buildSheet(context, cs, patients);
      },
    );
  }

  Widget _buildSheet(
      BuildContext context, ColorScheme cs, List<Patient> patients) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Drag handle ────────────────────────────────────────────────────
        const SizedBox(height: 8),
        Center(
          child: Container(
            width: 32,
            height: 4,
            decoration: BoxDecoration(
              color: cs.onSurfaceVariant.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        const SizedBox(height: 12),
        // ── Header ─────────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Registrar sessão',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 2),
              Text(
                _todayLabel(),
                style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // ── Fields ─────────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Paciente
              Row(
                children: [
                  Expanded(
                    child: LayoutBuilder(
                      builder: (ctx, constraints) => DropdownMenu<Patient>(
                        controller: _patientController,
                        width: constraints.maxWidth,
                        requestFocusOnTap: true,
                        label: const Text('Paciente'),
                        dropdownMenuEntries: patients
                            .map(
                              (p) => DropdownMenuEntry<Patient>(
                                value: p,
                                label: p.name,
                                leadingIcon: _AvatarCircle(
                                  name: p.name,
                                  color: _avatarColor(p.location),
                                  size: 24,
                                ),
                              ),
                            )
                            .toList(),
                        onSelected: (p) => setState(() {
                          _selectedPatient = p;
                          _duplicateError = false;
                        }),
                      ),
                    ),
                  ),
                  if (_activeCountryFilter != null) ...[
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () => setState(
                          () => _activeCountryFilter = null),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text('Ver todos'),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              // 2. Data da sessão
              InkWell(
                onTap: _pickDate,
                borderRadius: BorderRadius.circular(4),
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: 'Data da sessão',
                    suffixIcon: const Icon(Icons.calendar_today_outlined,
                        size: 18),
                    errorText: _duplicateError
                        ? 'Já existe uma sessão registrada nesta data para este paciente.'
                        : null,
                    border: const OutlineInputBorder(),
                  ),
                  child: Text(_formatDate(_date)),
                ),
              ),
              const SizedBox(height: 12),
              // 3. Observações
              TextField(
                controller: _obsController,
                decoration: const InputDecoration(
                  labelText: 'Observações (opcional)',
                  border: OutlineInputBorder(),
                ),
                maxLines: 1,
                textInputAction: TextInputAction.done,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // ── Live preview ───────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: _LivePreview(
            patient: _selectedPatient,
            date: _date,
          ),
        ),
        const SizedBox(height: 8),
        // ── Actions ────────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed:
                    _saving ? null : () => Navigator.of(context).pop(),
                child: const Text('Cancelar'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed:
                    (_saving || _selectedPatient == null) ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Salvar'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Live preview row
// ---------------------------------------------------------------------------

class _LivePreview extends StatelessWidget {
  final Patient? patient;
  final DateTime date;

  const _LivePreview({required this.patient, required this.date});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (patient == null) {
      return Text(
        '—',
        style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
      );
    }

    final dateStr = formatDate(date);
    final String rateStr;
    if (patient!.paymentModel == PaymentModel.mensal) {
      rateStr = 'Mensal (não altera valor)';
    } else {
      final rate = patient!.currentRate ?? 0;
      rateStr =
          '${formatCurrency(rate, patient!.currency.apiValue)} por sessão';
    }

    return Text(
      '${patient!.name} · $dateStr · $rateStr',
      style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

// ---------------------------------------------------------------------------
// Patient avatar circle
// ---------------------------------------------------------------------------

class _AvatarCircle extends StatelessWidget {
  final String name;
  final Color color;
  final double size;

  const _AvatarCircle({
    required this.name,
    required this.color,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    final initial =
        name.isNotEmpty ? name[0].toUpperCase() : '?';
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
