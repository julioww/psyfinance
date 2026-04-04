import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:psyfinance_app/core/formatters.dart';
import 'package:psyfinance_app/features/patients/patient_model.dart';
import 'package:psyfinance_app/features/patients/patient_summary_model.dart';
import 'package:psyfinance_app/features/patients/patients_provider.dart';
import 'package:psyfinance_app/features/patients/rate_history_widget.dart';
import 'package:psyfinance_app/features/payments/payments_provider.dart';
import 'package:psyfinance_app/features/revenue_share/revenue_share_form_dialog.dart';
import 'package:psyfinance_app/features/revenue_share/revenue_share_model.dart';
import 'package:psyfinance_app/features/revenue_share/revenue_share_provider.dart';
import 'package:psyfinance_app/features/sessions/session_entry_sheet.dart';

// ---------------------------------------------------------------------------
// Deterministic avatar color (same algorithm as patient_list_screen.dart)
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

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class PatientDetailScreen extends ConsumerStatefulWidget {
  final String patientId;

  /// Injected for testing — if provided, called instead of showing the real
  /// SessionEntrySheet (built in F5).
  final void Function(BuildContext, MonthSummary)? onMonthTap;

  const PatientDetailScreen({
    super.key,
    required this.patientId,
    this.onMonthTap,
  });

  @override
  ConsumerState<PatientDetailScreen> createState() =>
      _PatientDetailScreenState();
}

class _PatientDetailScreenState extends ConsumerState<PatientDetailScreen> {
  late int _selectedYear;

  @override
  void initState() {
    super.initState();
    _selectedYear = DateTime.now().year;
  }

  void _handleMonthTap(
      BuildContext context, MonthSummary month, PatientSummary summary) {
    if (widget.onMonthTap != null) {
      widget.onMonthTap!(context, month);
      return;
    }
    showSessionEntrySheet(
      context,
      patient: summary.patient,
      year: _selectedYear,
      month: month.month,
      onSaved: () => ref.invalidate(
        patientSummaryProvider(
          (patientId: widget.patientId, year: _selectedYear),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final summaryAsync = ref.watch(
      patientSummaryProvider(
          (patientId: widget.patientId, year: _selectedYear)),
    );

    return summaryAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(
          leading: BackButton(onPressed: () => context.go('/pacientes')),
          title: const Text('Paciente'),
        ),
        body: Center(child: Text('Erro ao carregar: $e')),
      ),
      data: (summary) => _buildScreen(context, summary),
    );
  }

  Widget _buildScreen(BuildContext context, PatientSummary summary) {
    // Height: breadcrumb(40) + divider(1) + profile(107) + divider(1) = 149 → 160
    const headerHeight = 160.0;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 80,
            title: Text(summary.patient.name),
            flexibleSpace: const FlexibleSpaceBar(),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => context.go('/pacientes'),
            ),
          ),
          SliverPersistentHeader(
            pinned: true,
            delegate: _PinnedHeaderDelegate(
              height: headerHeight,
              child: _StickyHeader(
                summary: summary,
                onEdit: () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Edição disponível em breve')),
                ),
                onArchiveToggle: () async {
                  final patient = summary.patient;
                  if (patient.status == PatientStatus.ativo) {
                    await ref
                        .read(patientsProvider.notifier)
                        .archivePatient(patient.id);
                  } else {
                    await ref
                        .read(patientsProvider.notifier)
                        .updatePatient(patient.id,
                            const UpdatePatientDto(status: PatientStatus.ativo));
                  }
                  ref.invalidate(patientSummaryProvider);
                  if (mounted) context.go('/pacientes');
                },
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 260,
                    child: _LeftSidebar(summary: summary),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _RightPanel(
                      summary: summary,
                      selectedYear: _selectedYear,
                      onYearChanged: (year) =>
                          setState(() => _selectedYear = year),
                      onMonthTap: (month) =>
                          _handleMonthTap(context, month, summary),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Pinned header delegate
// ---------------------------------------------------------------------------

class _PinnedHeaderDelegate extends SliverPersistentHeaderDelegate {
  final double height;
  final Widget child;

  const _PinnedHeaderDelegate({required this.height, required this.child});

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Material(
      elevation: overlapsContent ? 1 : 0,
      color: Theme.of(context).colorScheme.surface,
      child: SizedBox.expand(child: child),
    );
  }

  @override
  double get maxExtent => height;

  @override
  double get minExtent => height;

  @override
  bool shouldRebuild(covariant _PinnedHeaderDelegate old) =>
      old.height != height || old.child != child;
}

// ---------------------------------------------------------------------------
// Sticky header: breadcrumb + profile
// ---------------------------------------------------------------------------

class _StickyHeader extends StatelessWidget {
  final PatientSummary summary;
  final VoidCallback onEdit;
  final VoidCallback onArchiveToggle;

  const _StickyHeader({
    required this.summary,
    required this.onEdit,
    required this.onArchiveToggle,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final patient = summary.patient;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Breadcrumb
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () => context.go('/pacientes'),
                  child: Text(
                    'Pacientes',
                    style: TextStyle(color: colorScheme.primary, fontSize: 13),
                  ),
                ),
              ),
              Text(' › ',
                  style: TextStyle(
                      color: colorScheme.onSurfaceVariant, fontSize: 13)),
              Flexible(
                child: Text(
                  patient.name,
                  style:
                      TextStyle(color: colorScheme.onSurface, fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        // Profile
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _Avatar(patientId: patient.id, name: patient.name),
              const SizedBox(width: 12),
              Expanded(
                child: _ProfileInfo(
                    summary: summary, colorScheme: colorScheme),
              ),
              const SizedBox(width: 12),
              _ActionButtons(
                isAtivo: patient.status == PatientStatus.ativo,
                onEdit: onEdit,
                onArchiveToggle: onArchiveToggle,
              ),
            ],
          ),
        ),
        const Divider(height: 1),
      ],
    );
  }
}

class _Avatar extends StatelessWidget {
  final String patientId;
  final String name;

  const _Avatar({required this.patientId, required this.name});

  @override
  Widget build(BuildContext context) {
    final color = _avatarColor(patientId);
    final initials = name
        .split(' ')
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w[0].toUpperCase())
        .join();

    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: const TextStyle(
            color: Colors.white, fontWeight: FontWeight.w600, fontSize: 18),
      ),
    );
  }
}

class _ProfileInfo extends StatelessWidget {
  final PatientSummary summary;
  final ColorScheme colorScheme;

  const _ProfileInfo({required this.summary, required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    final patient = summary.patient;

    // Compute current rate from rates list
    double? currentRate;
    if (summary.rates.isNotEmpty) {
      final now = DateTime.now();
      final active = summary.rates.where((r) =>
          !r.effectiveFrom.isAfter(now) &&
          (r.effectiveTo == null || r.effectiveTo!.isAfter(now)));
      if (active.isNotEmpty) {
        currentRate = active
            .reduce((a, b) =>
                a.effectiveFrom.isAfter(b.effectiveFrom) ? a : b)
            .rate;
      } else {
        currentRate = summary.rates.first.rate;
      }
    }

    final currencyStr = patient.currency.apiValue;
    final rateText = currentRate != null
        ? 'Taxa atual: ${formatCurrency(currentRate, currencyStr)}/sessão'
        : 'Sem taxa configurada';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(patient.name,
            style: const TextStyle(
                fontSize: 18, fontWeight: FontWeight.w500)),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            _Badge(
              label: patient.status.label,
              bg: patient.status == PatientStatus.ativo
                  ? colorScheme.secondaryContainer
                  : colorScheme.surfaceVariant,
              fg: patient.status == PatientStatus.ativo
                  ? colorScheme.onSecondaryContainer
                  : colorScheme.onSurfaceVariant,
            ),
            _Badge(
              label: patient.currency.symbol,
              bg: patient.currency == PatientCurrency.brl
                  ? const Color(0xFFE8F5E9)
                  : const Color(0xFFE3F2FD),
              fg: patient.currency == PatientCurrency.brl
                  ? const Color(0xFF1B5E20)
                  : const Color(0xFF0D47A1),
            ),
            _Badge(
              label: patient.paymentModel.label,
              bg: colorScheme.primaryContainer,
              fg: colorScheme.onPrimaryContainer,
            ),
            _Badge(
              label: patient.location,
              bg: colorScheme.surfaceVariant,
              fg: colorScheme.onSurfaceVariant,
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(children: [
          Text(patient.email,
              style:
                  TextStyle(color: colorScheme.secondary, fontSize: 13)),
          Text(' · ',
              style: TextStyle(
                  color: colorScheme.onSurfaceVariant, fontSize: 13)),
          Text(rateText,
              style: TextStyle(
                  color: colorScheme.onSurface, fontSize: 13)),
        ]),
      ],
    );
  }
}

class _ActionButtons extends StatelessWidget {
  final bool isAtivo;
  final VoidCallback onEdit;
  final VoidCallback onArchiveToggle;

  const _ActionButtons({
    required this.isAtivo,
    required this.onEdit,
    required this.onArchiveToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        OutlinedButton.icon(
          icon: const Icon(Icons.edit_outlined, size: 16),
          label: const Text('Editar'),
          onPressed: onEdit,
        ),
        const SizedBox(height: 6),
        _ArchiveButton(isAtivo: isAtivo, onPressed: onArchiveToggle),
      ],
    );
  }
}

class _ArchiveButton extends StatefulWidget {
  final bool isAtivo;
  final VoidCallback onPressed;

  const _ArchiveButton({required this.isAtivo, required this.onPressed});

  @override
  State<_ArchiveButton> createState() => _ArchiveButtonState();
}

class _ArchiveButtonState extends State<_ArchiveButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: OutlinedButton.icon(
        style: _hovered && widget.isAtivo
            ? OutlinedButton.styleFrom(
                foregroundColor: cs.error,
                side: BorderSide(color: cs.error),
              )
            : null,
        icon: Icon(
          widget.isAtivo ? Icons.archive_outlined : Icons.unarchive_outlined,
          size: 16,
        ),
        label: Text(widget.isAtivo ? 'Arquivar' : 'Reativar'),
        onPressed: widget.onPressed,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared badge widget
// ---------------------------------------------------------------------------

class _Badge extends StatelessWidget {
  final String label;
  final Color bg;
  final Color fg;

  const _Badge({required this.label, required this.bg, required this.fg});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Text(label,
          style: TextStyle(
              color: fg, fontSize: 11, fontWeight: FontWeight.w500)),
    );
  }
}

// ---------------------------------------------------------------------------
// Left sidebar
// ---------------------------------------------------------------------------

class _LeftSidebar extends ConsumerWidget {
  final PatientSummary summary;

  const _LeftSidebar({required this.summary});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final patient = summary.patient;
    final firstRate =
        summary.rates.isNotEmpty ? summary.rates.last : null;
    final since = firstRate != null
        ? '${monthName(firstRate.effectiveFrom.month)}/${firstRate.effectiveFrom.year}'
        : '—';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SidebarSection(
          title: 'INFORMAÇÕES',
          initiallyExpanded: true,
          children: [
            _InfoRow('Email', patient.email),
            _InfoRow('CPF', patient.cpf ?? '—'),
            _InfoRow('Localização', patient.location),
            _InfoRow('Forma de pagamento', patient.paymentModel.label),
            _InfoRow('Moeda', patient.currency.symbol),
            _InfoRow('Paciente desde', since),
          ],
        ),
        const SizedBox(height: 8),
        _SidebarSection(
          title: 'HISTÓRICO DE TAXA',
          initiallyExpanded: true,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: RateHistoryWidget(patientId: patient.id, currency: patient.currency),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _SidebarSection(
          title: 'REPASSE',
          initiallyExpanded: false,
          children: [
            _RepasseSection(patient: patient),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// REPASSE section — ConsumerStatefulWidget to handle loading + actions
// ---------------------------------------------------------------------------

class _RepasseSection extends ConsumerStatefulWidget {
  final Patient patient;

  const _RepasseSection({required this.patient});

  @override
  ConsumerState<_RepasseSection> createState() => _RepasseSectionState();
}

class _RepasseSectionState extends ConsumerState<_RepasseSection> {
  bool _saving = false;

  String _configLabel(RevenueShareConfig config) {
    final currency = widget.patient.currency.apiValue;
    if (config.shareType == ShareType.percentage) {
      final pct = config.shareValue % 1 == 0
          ? config.shareValue.toInt().toString()
          : config.shareValue.toStringAsFixed(1);
      return '$pct% para ${config.beneficiaryName}';
    } else {
      return '${formatCurrency(config.shareValue, currency)}/sessão para ${config.beneficiaryName}';
    }
  }

  Future<void> _openForm(RevenueShareConfig? existing) async {
    final dto = await showRevenueShareFormDialog(
      context,
      existing: existing,
    );
    if (dto == null || !mounted) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(revenueShareProvider(widget.patient.id).notifier)
          .save(widget.patient.id, dto);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deactivate() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remover repasse'),
        content: const Text('Deseja desativar o repasse configurado?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Desativar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(revenueShareProvider(widget.patient.id).notifier)
          .deactivate(widget.patient.id);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final asyncConfig = ref.watch(revenueShareProvider(widget.patient.id));

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: asyncConfig.when(
        loading: () => const SizedBox(
          height: 36,
          child: Center(
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
        error: (_, __) => Text(
          'Erro ao carregar repasse.',
          style: TextStyle(color: cs.error, fontSize: 13),
        ),
        data: (config) {
          if (_saving) {
            return const SizedBox(
              height: 36,
              child: Center(
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          }

          if (config == null) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Sem repasse configurado.',
                  style: TextStyle(
                      color: cs.onSurfaceVariant, fontSize: 13),
                ),
                TextButton.icon(
                  onPressed: () => _openForm(null),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Configurar repasse'),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                  ),
                ),
              ],
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _configLabel(config),
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w500),
              ),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    onPressed: () => _openForm(config),
                    tooltip: 'Editar repasse',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                  ),
                  IconButton(
                    icon: Icon(Icons.cancel_outlined,
                        size: 16, color: cs.error),
                    onPressed: _deactivate,
                    tooltip: 'Desativar repasse',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SidebarSection extends StatelessWidget {
  final String title;
  final bool initiallyExpanded;
  final List<Widget> children;

  const _SidebarSection({
    required this.title,
    required this.initiallyExpanded,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: cs.surfaceContainerLow,
      child: ExpansionTile(
        title: Text(
          title,
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
              color: cs.onSurfaceVariant),
        ),
        initiallyExpanded: initiallyExpanded,
        children: children,
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label,
                  style: TextStyle(
                      color: cs.onSurfaceVariant, fontSize: 13)),
              Flexible(
                child: Text(value,
                    style: TextStyle(
                        color: cs.onSurface, fontSize: 13),
                    textAlign: TextAlign.end,
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
        ),
        Divider(
            height: 1,
            thickness: 0.5,
            color: cs.outlineVariant.withOpacity(0.5)),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Right panel
// ---------------------------------------------------------------------------

class _RightPanel extends StatelessWidget {
  final PatientSummary summary;
  final int selectedYear;
  final void Function(int) onYearChanged;
  final void Function(MonthSummary) onMonthTap;

  const _RightPanel({
    required this.summary,
    required this.selectedYear,
    required this.onYearChanged,
    required this.onMonthTap,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final currentYear = now.year;
    final firstYear = summary.rates.isNotEmpty
        ? summary.rates
            .map((r) => r.effectiveFrom.year)
            .reduce((a, b) => a < b ? a : b)
        : currentYear;
    final availableYears =
        List.generate(currentYear - firstYear + 1, (i) => firstYear + i);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Year navigator
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: availableYears.map((year) {
            return ChoiceChip(
              label: Text(year.toString()),
              selected: year == selectedYear,
              onSelected: (_) {
                if (year != selectedYear) onYearChanged(year);
              },
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
        _AnnualSummaryStrip(summary: summary),
        const SizedBox(height: 16),
        _MonthlyTable(
          summary: summary,
          selectedYear: selectedYear,
          onMonthTap: onMonthTap,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Annual summary strip
// ---------------------------------------------------------------------------

class _AnnualSummaryStrip extends StatelessWidget {
  final PatientSummary summary;

  const _AnnualSummaryStrip({required this.summary});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final cur = summary.patient.currency.apiValue;
    final balance = summary.totalBalance;

    return Row(
      children: [
        Expanded(
          child: _SummaryCard(
              title: 'SESSÕES',
              value: summary.totalSessions.toString(),
              valueColor: null),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _SummaryCard(
              title: 'ESPERADO',
              value: formatCurrency(summary.totalExpected, cur),
              valueColor: null),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _SummaryCard(
              title: 'RECEBIDO',
              value: formatCurrency(summary.totalPaid, cur),
              valueColor: const Color(0xFF2E7D32)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _SummaryCard(
              title: 'SALDO',
              value: formatCurrency(balance, cur),
              valueColor: balance > 0 ? cs.error : null),
        ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String title;
  final String value;
  final Color? valueColor;

  const _SummaryCard(
      {required this.title, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                  color: cs.onSurfaceVariant)),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: valueColor ?? cs.onSurface,
                  fontFeatures: const [FontFeature.tabularFigures()])),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Monthly table
// ---------------------------------------------------------------------------

class _MonthlyTable extends StatelessWidget {
  final PatientSummary summary;
  final int selectedYear;
  final void Function(MonthSummary) onMonthTap;

  const _MonthlyTable({
    required this.summary,
    required this.selectedYear,
    required this.onMonthTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final cur = summary.patient.currency.apiValue;

    final headerStyle = TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.4,
        color: cs.onSurfaceVariant);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header row
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(8)),
          ),
          child: Row(children: [
            SizedBox(
                width: 64,
                child: Text('Mês', style: headerStyle)),
            SizedBox(
                width: 48,
                child: Text('Sess.',
                    style: headerStyle,
                    textAlign: TextAlign.center)),
            Expanded(
                child: Text('Esperado',
                    style: headerStyle, textAlign: TextAlign.right)),
            Expanded(
                child: Text('Pago',
                    style: headerStyle, textAlign: TextAlign.right)),
            Expanded(
                child: Text('Saldo',
                    style: headerStyle, textAlign: TextAlign.right)),
            SizedBox(
                width: 88,
                child: Text('Status',
                    style: headerStyle,
                    textAlign: TextAlign.center)),
            SizedBox(
                width: 88,
                child: Text('Obs', style: headerStyle)),
          ]),
        ),
        // Month rows
        ...summary.months.map((m) => _MonthRow(
              month: m,
              isCurrentMonth: m.month == now.month &&
                  selectedYear == now.year,
              currencyStr: cur,
              patientId: summary.patient.id,
              year: selectedYear,
              onTap: () => onMonthTap(m),
            )),
        // Bottom border
        Container(
          height: 1,
          decoration: BoxDecoration(
            color: cs.outlineVariant,
            borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(8)),
          ),
        ),
      ],
    );
  }
}

class _MonthRow extends ConsumerStatefulWidget {
  final MonthSummary month;
  final bool isCurrentMonth;
  final String currencyStr;
  final String patientId;
  final int year;
  final VoidCallback onTap;

  const _MonthRow({
    required this.month,
    required this.isCurrentMonth,
    required this.currencyStr,
    required this.patientId,
    required this.year,
    required this.onTap,
  });

  @override
  ConsumerState<_MonthRow> createState() => _MonthRowState();
}

class _MonthRowState extends ConsumerState<_MonthRow> {
  bool _editingPago = false;
  late TextEditingController _controller;
  bool _saving = false;

  // Local optimistic overrides after a successful payment save
  double? _localAmountPaid;
  double? _localBalance;
  MonthPaymentStatus? _localStatus;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: _formatAmount(widget.month.amountPaid ?? 0.0),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _formatAmount(double v) =>
      v == 0 ? '0' : v.toStringAsFixed(2);

  double get _displayAmountPaid =>
      _localAmountPaid ?? widget.month.amountPaid ?? 0.0;
  double get _displayBalance =>
      _localBalance ??
      widget.month.balance ??
      (widget.month.expectedAmount ?? 0.0) - _displayAmountPaid;
  MonthPaymentStatus? get _displayStatus =>
      _localStatus ?? widget.month.status;

  void _startEdit() {
    if (widget.month.sessionRecordId == null) return;
    _controller.text = _formatAmount(_displayAmountPaid);
    setState(() => _editingPago = true);
  }

  void _cancelEdit() => setState(() => _editingPago = false);

  Future<void> _confirmEdit() async {
    final sessionRecordId = widget.month.sessionRecordId;
    if (sessionRecordId == null) return;

    final amount =
        double.tryParse(_controller.text.replaceAll(',', '.')) ?? 0.0;
    setState(() {
      _saving = true;
      _editingPago = false;
    });

    try {
      final payment = await ref
          .read(paymentsRepositoryProvider)
          .updatePayment(sessionRecordId, amount);

      final newBalance =
          (widget.month.expectedAmount ?? 0.0) - payment.amountPaid;
      setState(() {
        _localAmountPaid = payment.amountPaid;
        _localBalance = newBalance;
        _localStatus =
            MonthPaymentStatusX.fromString(payment.status);
        _saving = false;
      });

      // Refresh summary in background so totals update
      ref.invalidate(patientSummaryProvider(
          (patientId: widget.patientId, year: widget.year)));
    } catch (_) {
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isAtrasado = _displayStatus == MonthPaymentStatus.atrasado;
    final hasData = widget.month.sessionRecordId != null;

    return InkWell(
      onTap: widget.onTap,
      child: Container(
        color: isAtrasado ? cs.errorContainer.withOpacity(0.25) : null,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(children: [
          // Mês
          SizedBox(
            width: 64,
            child: Row(children: [
              if (widget.isCurrentMonth)
                Container(
                  width: 6,
                  height: 6,
                  margin: const EdgeInsets.only(right: 5),
                  decoration: const BoxDecoration(
                    color: Color(0xFF00897B),
                    shape: BoxShape.circle,
                  ),
                )
              else
                const SizedBox(width: 11),
              Text(monthAbbr(widget.month.month),
                  style: TextStyle(fontSize: 13, color: cs.onSurface)),
            ]),
          ),
          // Sess.
          SizedBox(
            width: 48,
            child: Text(
              widget.month.sessionCount?.toString() ?? '—',
              style: TextStyle(fontSize: 13, color: cs.onSurface),
              textAlign: TextAlign.center,
            ),
          ),
          // Esperado
          Expanded(
            child: Text(
              widget.month.expectedAmount != null
                  ? formatCurrency(
                      widget.month.expectedAmount!, widget.currencyStr)
                  : '—',
              style: TextStyle(fontSize: 13, color: cs.onSurface),
              textAlign: TextAlign.right,
            ),
          ),
          // Pago (tappable for inline edit when month has data)
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: hasData && !_saving ? _startEdit : null,
              child: _editingPago
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        SizedBox(
                          width: 80,
                          child: TextField(
                            controller: _controller,
                            autofocus: true,
                            keyboardType:
                                const TextInputType.numberWithOptions(
                                    decimal: true),
                            textAlign: TextAlign.right,
                            style: const TextStyle(fontSize: 13),
                            decoration: const InputDecoration(
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 4, vertical: 4),
                              border: OutlineInputBorder(),
                            ),
                            onSubmitted: (_) => _confirmEdit(),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.check, size: 16),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: _confirmEdit,
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 16),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: _cancelEdit,
                        ),
                      ],
                    )
                  : _saving
                      ? const Align(
                          alignment: Alignment.centerRight,
                          child: SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : Text(
                          hasData
                              ? formatCurrency(
                                  _displayAmountPaid, widget.currencyStr)
                              : '—',
                          style: TextStyle(
                              fontSize: 13,
                              color: hasData
                                  ? cs.primary
                                  : cs.onSurface,
                              decoration: hasData
                                  ? TextDecoration.underline
                                  : null),
                          textAlign: TextAlign.right,
                        ),
            ),
          ),
          // Saldo
          Expanded(
            child: Text(
              hasData
                  ? formatCurrency(_displayBalance, widget.currencyStr)
                  : '—',
              style: TextStyle(fontSize: 13, color: cs.onSurface),
              textAlign: TextAlign.right,
            ),
          ),
          // Status chip
          SizedBox(
            width: 88,
            child: Center(child: _StatusChip(status: _displayStatus)),
          ),
          // Obs
          SizedBox(
            width: 88,
            child: _ObsCell(text: widget.month.observations),
          ),
        ]),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final MonthPaymentStatus? status;

  const _StatusChip({this.status});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (status == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: cs.surfaceVariant.withOpacity(0.4),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text('—',
            style: TextStyle(
                fontSize: 10,
                color: cs.onSurfaceVariant.withOpacity(0.5))),
      );
    }

    final (bg, fg) = switch (status!) {
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
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Text(status!.label,
          style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.w500, color: fg),
          textAlign: TextAlign.center),
    );
  }
}

class _ObsCell extends StatelessWidget {
  final String? text;

  const _ObsCell({this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (text == null || text!.isEmpty) {
      return Text('—',
          style:
              TextStyle(fontSize: 12, color: cs.onSurfaceVariant));
    }
    return Tooltip(
      message: text!,
      child: Text(
        text!,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 12, color: cs.onSurface),
      ),
    );
  }
}

