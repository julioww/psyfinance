import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:psyfinance_app/core/formatters.dart';
import 'patient_model.dart';
import 'patients_provider.dart';

// ---------------------------------------------------------------------------
// Avatar palette  (8 tones — teal/blue/amber/purple)
// ---------------------------------------------------------------------------

const _avatarPalette = [
  Color(0xFF00695C), // teal 800
  Color(0xFF00838F), // cyan 800
  Color(0xFF1565C0), // blue 800
  Color(0xFF283593), // indigo 800
  Color(0xFF6A1B9A), // purple 800
  Color(0xFF558B2F), // light-green 800
  Color(0xFFE65100), // deep-orange 900
  Color(0xFF827717), // lime 900
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
// Country flag dots (simple color mapping)
// ---------------------------------------------------------------------------

Color _countryColor(String location) {
  final lower = location.toLowerCase();
  if (lower.contains('brasil') || lower.contains('brazil')) return const Color(0xFF2E7D32);
  if (lower.contains('aleman') || lower.contains('germany') || lower.contains('deutsch')) {
    return const Color(0xFFB71C1C);
  }
  if (lower.contains('fran') || lower.contains('france')) return const Color(0xFF1565C0);
  if (lower.contains('portugal')) return const Color(0xFFAD1457);
  if (lower.contains('eua') || lower.contains('usa') || lower.contains('estados')) {
    return const Color(0xFF1A237E);
  }
  return const Color(0xFF546E7A); // default grey-blue
}

// ---------------------------------------------------------------------------
// Sort state
// ---------------------------------------------------------------------------

enum _SortCol { name, location, currency, paymentModel, rate, status }

// ---------------------------------------------------------------------------
// PatientListScreen
// ---------------------------------------------------------------------------

class PatientListScreen extends ConsumerStatefulWidget {
  const PatientListScreen({super.key});

  @override
  ConsumerState<PatientListScreen> createState() => _PatientListScreenState();
}

class _PatientListScreenState extends ConsumerState<PatientListScreen> {
  final _searchCtrl = TextEditingController();
  _SortCol _sortCol = _SortCol.name;
  bool _sortAsc = true;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  PatientsFilter get _filter => ref.read(patientsProvider.notifier).filter;

  void _updateFilter(PatientsFilter filter) {
    ref.read(patientsProvider.notifier).applyFilter(filter);
  }

  void _clearFilters() {
    _searchCtrl.clear();
    _updateFilter(const PatientsFilter());
  }

  void _toggleSort(_SortCol col) {
    setState(() {
      if (_sortCol == col) {
        _sortAsc = !_sortAsc;
      } else {
        _sortCol = col;
        _sortAsc = true;
      }
    });
  }

  List<Patient> _sorted(List<Patient> list) {
    final sorted = [...list];
    sorted.sort((a, b) {
      int cmp;
      switch (_sortCol) {
        case _SortCol.name:
          cmp = a.name.compareTo(b.name);
        case _SortCol.location:
          cmp = a.location.compareTo(b.location);
        case _SortCol.currency:
          cmp = a.currency.apiValue.compareTo(b.currency.apiValue);
        case _SortCol.paymentModel:
          cmp = a.paymentModel.apiValue.compareTo(b.paymentModel.apiValue);
        case _SortCol.rate:
          cmp = (a.currentRate ?? 0).compareTo(b.currentRate ?? 0);
        case _SortCol.status:
          cmp = a.status.apiValue.compareTo(b.status.apiValue);
      }
      return _sortAsc ? cmp : -cmp;
    });
    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    final patientsAsync = ref.watch(patientsProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final filter = ref.watch(patientsProvider.notifier).filter;

    // Collect distinct locations from loaded patients for the dropdown.
    // Always include the currently-selected location so the DropdownButton
    // never holds a value that has no matching item.
    final allPatients = patientsAsync.valueOrNull ?? [];
    final distinctLocations = {
      ...allPatients.map((p) => p.location),
      if (filter.location != null) filter.location!,
    }.toList()..sort();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pacientes'),
        backgroundColor: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showPatientFormSheet(context),
        icon: const Icon(Icons.add),
        label: const Text('Novo paciente'),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _FilterBar(
            searchCtrl: _searchCtrl,
            filter: filter,
            distinctLocations: distinctLocations,
            onFilterChanged: _updateFilter,
            onClearFilters: _clearFilters,
          ),
          _CountBar(
            count: allPatients.length,
            hasFilters: filter.hasActiveNonDefaultFilters,
            onClear: _clearFilters,
          ),
          Expanded(
            child: patientsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Erro: $e')),
              data: (patients) => patients.isEmpty
                  ? const _EmptyState()
                  : _PatientTable(
                      patients: _sorted(patients),
                      sortCol: _sortCol,
                      sortAsc: _sortAsc,
                      onSortChanged: _toggleSort,
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showPatientFormSheet(BuildContext context) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => PatientFormSheet(
        onSaved: (dto) async {
          await ref.read(patientsProvider.notifier).createPatient(dto);
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Filter bar
// ---------------------------------------------------------------------------

class _FilterBar extends StatelessWidget {
  final TextEditingController searchCtrl;
  final PatientsFilter filter;
  final List<String> distinctLocations;
  final ValueChanged<PatientsFilter> onFilterChanged;
  final VoidCallback onClearFilters;

  const _FilterBar({
    required this.searchCtrl,
    required this.filter,
    required this.distinctLocations,
    required this.onFilterChanged,
    required this.onClearFilters,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          // Search
          SizedBox(
            width: 260,
            height: 40,
            child: TextField(
              controller: searchCtrl,
              decoration: InputDecoration(
                hintText: 'Buscar paciente…',
                prefixIcon: const Icon(Icons.search, size: 18),
                contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                isDense: true,
              ),
              onChanged: (q) => onFilterChanged(filter.copyWith(query: q)),
            ),
          ),

          // Status segmented button
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'ATIVO', label: Text('Ativos')),
              ButtonSegment(value: 'INATIVO', label: Text('Inativos')),
              ButtonSegment(value: 'all', label: Text('Todos')),
            ],
            selected: {filter.statusFilter},
            onSelectionChanged: (s) => onFilterChanged(filter.copyWith(statusFilter: s.first)),
            style: ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),

          // País dropdown
          _FilterDropdown<String>(
            label: 'País',
            value: filter.location,
            items: distinctLocations,
            itemLabel: (l) => l,
            itemLeading: (l) => Container(
              width: 10,
              height: 10,
              margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(
                color: _countryColor(l),
                shape: BoxShape.circle,
              ),
            ),
            onChanged: (v) => onFilterChanged(filter.copyWith(location: v)),
          ),

          // Moeda dropdown
          _FilterDropdown<String>(
            label: 'Moeda',
            value: filter.currency,
            items: const ['BRL', 'EUR'],
            itemLabel: (c) => c == 'BRL' ? 'R\$ (BRL)' : '€ (EUR)',
            onChanged: (v) => onFilterChanged(filter.copyWith(currency: v)),
          ),

          // Pagamento dropdown
          _FilterDropdown<String>(
            label: 'Pagamento',
            value: filter.paymentModel,
            items: const ['SESSAO', 'MENSAL'],
            itemLabel: (m) => m == 'SESSAO' ? 'Sessão' : 'Mensal',
            onChanged: (v) => onFilterChanged(filter.copyWith(paymentModel: v)),
          ),
        ],
      ),
    );
  }
}

class _FilterDropdown<T> extends StatelessWidget {
  final String label;
  final T? value;
  final List<T> items;
  final String Function(T) itemLabel;
  final Widget Function(T)? itemLeading;
  final ValueChanged<T?> onChanged;

  const _FilterDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.itemLabel,
    this.itemLeading,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButton<T>(
      value: value,
      hint: Text(label),
      isDense: true,
      underline: const SizedBox(),
      items: [
        DropdownMenuItem<T>(
          value: null,
          child: Text('$label (todos)', style: const TextStyle(color: Colors.grey)),
        ),
        ...items.map(
          (item) => DropdownMenuItem<T>(
            value: item,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (itemLeading != null) itemLeading!(item),
                Text(itemLabel(item)),
              ],
            ),
          ),
        ),
      ],
      onChanged: onChanged,
    );
  }
}

// ---------------------------------------------------------------------------
// Count bar
// ---------------------------------------------------------------------------

class _CountBar extends StatelessWidget {
  final int count;
  final bool hasFilters;
  final VoidCallback onClear;

  const _CountBar({required this.count, required this.hasFilters, required this.onClear});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      child: Row(
        children: [
          Text(
            '$count ${count == 1 ? 'paciente' : 'pacientes'}',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: colorScheme.onSurfaceVariant),
          ),
          if (hasFilters) ...[
            const SizedBox(width: 4),
            TextButton.icon(
              onPressed: onClear,
              icon: const Icon(Icons.close, size: 14),
              label: const Text('Limpar filtros'),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                textStyle: const TextStyle(fontSize: 12),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Patient table
// ---------------------------------------------------------------------------

class _PatientTable extends StatelessWidget {
  final List<Patient> patients;
  final _SortCol sortCol;
  final bool sortAsc;
  final ValueChanged<_SortCol> onSortChanged;

  const _PatientTable({
    required this.patients,
    required this.sortCol,
    required this.sortAsc,
    required this.onSortChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.vertical,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          sortColumnIndex: _SortCol.values.indexOf(sortCol),
          sortAscending: sortAsc,
          columnSpacing: 20,
          horizontalMargin: 16,
          headingRowHeight: 42,
          dataRowMinHeight: 60,
          dataRowMaxHeight: 72,
          columns: [
            _sortableCol('Paciente', _SortCol.name, sortCol, sortAsc, onSortChanged, context),
            _sortableCol('País', _SortCol.location, sortCol, sortAsc, onSortChanged, context),
            _sortableCol('Moeda', _SortCol.currency, sortCol, sortAsc, onSortChanged, context),
            _sortableCol('Pagamento', _SortCol.paymentModel, sortCol, sortAsc, onSortChanged, context),
            _sortableCol('Taxa atual', _SortCol.rate, sortCol, sortAsc, onSortChanged, context),
            _sortableCol('Status', _SortCol.status, sortCol, sortAsc, onSortChanged, context),
            const DataColumn(label: SizedBox.shrink()), // link icon column
          ],
          rows: patients.map((p) => _PatientRow(patient: p).build(context)).toList(),
        ),
      ),
    );
  }

  static DataColumn _sortableCol(
    String label,
    _SortCol col,
    _SortCol currentCol,
    bool asc,
    ValueChanged<_SortCol> onSort,
    BuildContext context,
  ) {
    final isActive = col == currentCol;
    final color = isActive ? Theme.of(context).colorScheme.primary : null;
    return DataColumn(
      label: GestureDetector(
        onTap: () => onSort(col),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
            if (isActive)
              Icon(
                asc ? Icons.arrow_upward : Icons.arrow_downward,
                size: 14,
                color: color,
              ),
          ],
        ),
      ),
      onSort: (_, __) => onSort(col),
    );
  }
}

class _PatientRow {
  final Patient patient;
  const _PatientRow({required this.patient});

  DataRow build(BuildContext context) {
    final inactive = patient.status == PatientStatus.inativo;
    final opacity = inactive ? 0.5 : 1.0;

    return DataRow(
      onSelectChanged: (_) => context.go('/pacientes/${patient.id}'),
      cells: [
        // Paciente cell
        DataCell(
          Opacity(
            opacity: opacity,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: _avatarColor(patient.id),
                  child: Text(
                    _initials(patient.name),
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(patient.name, style: const TextStyle(fontWeight: FontWeight.w500)),
                    Text(
                      patient.location,
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        // País
        DataCell(
          Opacity(
            opacity: opacity,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(right: 6),
                  decoration: BoxDecoration(
                    color: _countryColor(patient.location),
                    shape: BoxShape.circle,
                  ),
                ),
                Text(patient.location),
              ],
            ),
          ),
        ),

        // Moeda
        DataCell(Opacity(opacity: opacity, child: _CurrencyBadge(currency: patient.currency))),

        // Pagamento
        DataCell(Opacity(opacity: opacity, child: _PaymentBadge(model: patient.paymentModel))),

        // Taxa atual
        DataCell(
          Opacity(
            opacity: opacity,
            child: Text(
              patient.currentRate != null
                  ? formatCurrency(patient.currentRate!, patient.currency.apiValue)
                  : '—',
              style: const TextStyle(fontFamily: 'monospace'),
            ),
          ),
        ),

        // Status
        DataCell(Opacity(opacity: opacity, child: _StatusBadge(status: patient.status))),

        // Link
        DataCell(
          IconButton(
            icon: const Icon(Icons.open_in_new_outlined, size: 16),
            onPressed: () => context.go('/pacientes/${patient.id}'),
            visualDensity: VisualDensity.compact,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Colored badges
// ---------------------------------------------------------------------------

class _CurrencyBadge extends StatelessWidget {
  final PatientCurrency currency;
  const _CurrencyBadge({required this.currency});

  @override
  Widget build(BuildContext context) {
    final isBrl = currency == PatientCurrency.brl;
    final bg = isBrl ? const Color(0xFFE8F5E9) : const Color(0xFFE3F2FD);
    final fg = isBrl ? const Color(0xFF2E7D32) : const Color(0xFF1565C0);
    final label = isBrl ? 'R\$' : '€';
    return _Badge(label: label, bg: bg, fg: fg);
  }
}

class _PaymentBadge extends StatelessWidget {
  final PaymentModel model;
  const _PaymentBadge({required this.model});

  @override
  Widget build(BuildContext context) {
    final isSessao = model == PaymentModel.sessao;
    final bg = isSessao ? const Color(0xFFE0F2F1) : Theme.of(context).colorScheme.primaryContainer;
    final fg = isSessao ? const Color(0xFF00695C) : Theme.of(context).colorScheme.onPrimaryContainer;
    return _Badge(label: model.label, bg: bg, fg: fg);
  }
}

class _StatusBadge extends StatelessWidget {
  final PatientStatus status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isAtivo = status == PatientStatus.ativo;
    final bg = isAtivo ? colorScheme.secondaryContainer : colorScheme.surfaceContainerHighest;
    final fg = isAtivo ? colorScheme.onSecondaryContainer : colorScheme.onSurfaceVariant;
    return _Badge(label: status.label, bg: bg, fg: fg);
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color bg;
  final Color fg;

  const _Badge({required this.label, required this.bg, required this.fg});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Text(label, style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w500)),
    );
  }
}

// ---------------------------------------------------------------------------
// Empty state
// ---------------------------------------------------------------------------

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.person_outline, size: 72, color: colorScheme.onSurfaceVariant.withOpacity(0.3)),
          const SizedBox(height: 16),
          Text(
            'Nenhum paciente encontrado',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(color: colorScheme.onSurfaceVariant.withOpacity(0.6)),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// PatientFormSheet
// ---------------------------------------------------------------------------

class PatientFormSheet extends ConsumerStatefulWidget {
  final Future<void> Function(CreatePatientDto dto) onSaved;

  const PatientFormSheet({super.key, required this.onSaved});

  @override
  ConsumerState<PatientFormSheet> createState() => _PatientFormSheetState();
}

class _PatientFormSheetState extends ConsumerState<PatientFormSheet> {
  final _formKey = GlobalKey<FormState>();

  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _cpfCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _rateCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  PaymentModel _paymentModel = PaymentModel.sessao;
  PatientCurrency _currency = PatientCurrency.brl;
  DateTime _rateEffectiveFrom = DateTime.now();
  bool _saving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _cpfCtrl.dispose();
    _locationCtrl.dispose();
    _rateCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _rateEffectiveFrom,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      locale: const Locale('pt', 'BR'),
    );
    if (picked != null) setState(() => _rateEffectiveFrom = picked);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);
    try {
      final dto = CreatePatientDto(
        name: _nameCtrl.text.trim(),
        email: _emailCtrl.text.trim(),
        cpf: _cpfCtrl.text.trim().isEmpty ? null : _cpfCtrl.text.trim(),
        location: _locationCtrl.text.trim(),
        paymentModel: _paymentModel,
        currency: _currency,
        initialRate: double.parse(_rateCtrl.text.replaceAll(',', '.')),
        rateEffectiveFrom: _rateEffectiveFrom,
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      );
      await widget.onSaved(dto);
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Paciente adicionado')),
        );
      }
    } on Exception catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e'), backgroundColor: Theme.of(context).colorScheme.error),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.92,
      minChildSize: 0.5,
      maxChildSize: 0.97,
      builder: (context, scrollCtrl) => Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Drag handle
            Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 4),
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: colorScheme.onSurfaceVariant.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Title
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  Text('Novo paciente', style: Theme.of(context).textTheme.titleLarge),
                ],
              ),
            ),
            const Divider(height: 1),
            // Form
            Expanded(
              child: SingleChildScrollView(
                controller: scrollCtrl,
                padding: const EdgeInsets.all(20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Nome completo (full width)
                      _field(
                        controller: _nameCtrl,
                        label: 'Nome completo',
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Nome é obrigatório' : null,
                      ),
                      const SizedBox(height: 12),

                      // Email | CPF
                      Row(
                        children: [
                          Expanded(
                            child: _field(
                              controller: _emailCtrl,
                              label: 'Email',
                              keyboardType: TextInputType.emailAddress,
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) return 'Email é obrigatório';
                                final re = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
                                if (!re.hasMatch(v.trim())) return 'Email inválido';
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _field(
                              controller: _cpfCtrl,
                              label: 'CPF (opcional)',
                              keyboardType: TextInputType.number,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // País
                      _field(
                        controller: _locationCtrl,
                        label: 'País / Localização',
                        validator: (v) =>
                            (v == null || v.trim().isEmpty) ? 'Localização é obrigatória' : null,
                      ),
                      const SizedBox(height: 16),

                      // Forma de pagamento
                      Text('Forma de pagamento',
                          style: Theme.of(context).textTheme.labelMedium),
                      const SizedBox(height: 6),
                      SegmentedButton<PaymentModel>(
                        segments: const [
                          ButtonSegment(value: PaymentModel.sessao, label: Text('Sessão')),
                          ButtonSegment(value: PaymentModel.mensal, label: Text('Mensal')),
                        ],
                        selected: {_paymentModel},
                        onSelectionChanged: (s) => setState(() => _paymentModel = s.first),
                      ),
                      const SizedBox(height: 16),

                      // Moeda
                      Text('Moeda', style: Theme.of(context).textTheme.labelMedium),
                      const SizedBox(height: 6),
                      SegmentedButton<PatientCurrency>(
                        segments: const [
                          ButtonSegment(value: PatientCurrency.brl, label: Text('R\$ (BRL)')),
                          ButtonSegment(value: PatientCurrency.eur, label: Text('€ (EUR)')),
                        ],
                        selected: {_currency},
                        onSelectionChanged: (s) => setState(() => _currency = s.first),
                      ),
                      const SizedBox(height: 16),

                      // Taxa | Vigente a partir de
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _field(
                              controller: _rateCtrl,
                              label: 'Taxa inicial',
                              keyboardType:
                                  const TextInputType.numberWithOptions(decimal: true),
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) return 'Taxa obrigatória';
                                final n = double.tryParse(v.replaceAll(',', '.'));
                                if (n == null || n <= 0) return 'Taxa deve ser > 0';
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: InkWell(
                              onTap: _pickDate,
                              borderRadius: BorderRadius.circular(8),
                              child: InputDecorator(
                                decoration: InputDecoration(
                                  labelText: 'Vigente a partir de',
                                  border: const OutlineInputBorder(),
                                  suffixIcon: const Icon(Icons.calendar_today_outlined, size: 16),
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 14),
                                ),
                                child: Text(formatDate(_rateEffectiveFrom)),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Observações
                      _field(
                        controller: _notesCtrl,
                        label: 'Observações (opcional)',
                        maxLines: 3,
                      ),
                      const SizedBox(height: 24),

                      // Actions
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: _saving ? null : () => Navigator.of(context).pop(),
                            child: const Text('Cancelar'),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            onPressed: _saving ? null : _submit,
                            child: _saving
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Text('Salvar paciente'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
    int? maxLines,
  }) =>
      TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        maxLines: maxLines ?? 1,
        validator: validator,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        ),
      );
}
