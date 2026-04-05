import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:psyfinance_app/core/auth/auth_provider.dart';
import 'package:psyfinance_app/features/patients/patients_provider.dart';

// ===========================================================================
// Enums & models
// ===========================================================================

enum _SettingsPanel { conta, importar, backup, seguranca, sobre }

enum _LogLevel { info, ok, warn, err }

class _LogLine {
  final _LogLevel level;
  final String message;

  const _LogLine(this.level, this.message);

  factory _LogLine.fromJson(Map<String, dynamic> json) {
    final lvl = switch (json['level'] as String? ?? 'info') {
      'ok' => _LogLevel.ok,
      'warn' => _LogLevel.warn,
      'err' => _LogLevel.err,
      _ => _LogLevel.info,
    };
    return _LogLine(lvl, json['message'] as String? ?? '');
  }
}

class _BackupEntry {
  final String filename;
  final DateTime date;
  final bool isNew;

  const _BackupEntry({
    required this.filename,
    required this.date,
    this.isNew = false,
  });
}

// ===========================================================================
// ConfiguracoesScreen
// ===========================================================================

class ConfiguracoesScreen extends ConsumerStatefulWidget {
  const ConfiguracoesScreen({super.key});

  @override
  ConsumerState<ConfiguracoesScreen> createState() =>
      _ConfiguracoesScreenState();
}

class _ConfiguracoesScreenState extends ConsumerState<ConfiguracoesScreen> {
  _SettingsPanel _activePanel = _SettingsPanel.conta;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Configurações'),
        leading: const BackButton(),
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ----------------------------------------------------------------
          // Settings sidebar — 200px
          // ----------------------------------------------------------------
          _SettingsSidebar(
            activePanel: _activePanel,
            onSelect: (p) => setState(() => _activePanel = p),
          ),
          Container(width: 0.5, color: cs.outlineVariant),
          // ----------------------------------------------------------------
          // Content panel
          // ----------------------------------------------------------------
          Expanded(
            child: _buildPanel(context),
          ),
        ],
      ),
    );
  }

  Widget _buildPanel(BuildContext context) {
    return switch (_activePanel) {
      _SettingsPanel.conta => _ContaPanel(
          onLogout: _handleLogout,
        ),
      _SettingsPanel.importar => const _ImportarPanel(),
      _SettingsPanel.backup => const _BackupPanel(),
      _SettingsPanel.seguranca => const _SegurancaPanel(),
      _SettingsPanel.sobre => const _SobrePanel(),
    };
  }

  Future<void> _handleLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Deseja sair?'),
        content: const Text('Sua sessão será encerrada.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sair'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await ref.read(authProvider.notifier).logout();
      if (mounted) context.go('/login');
    }
  }
}

// ===========================================================================
// Sidebar
// ===========================================================================

class _SettingsSidebar extends StatelessWidget {
  final _SettingsPanel activePanel;
  final ValueChanged<_SettingsPanel> onSelect;

  const _SettingsSidebar({
    required this.activePanel,
    required this.onSelect,
  });

  static const _items = [
    (panel: _SettingsPanel.conta, icon: Icons.person_outline, label: 'Conta'),
    (
      panel: _SettingsPanel.importar,
      icon: Icons.download_outlined,
      label: 'Importar dados'
    ),
    (
      panel: _SettingsPanel.backup,
      icon: Icons.insert_drive_file_outlined,
      label: 'Backup'
    ),
    (
      panel: _SettingsPanel.seguranca,
      icon: Icons.shield_outlined,
      label: 'Segurança'
    ),
    (panel: _SettingsPanel.sobre, icon: Icons.info_outline, label: 'Sobre'),
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return SizedBox(
      width: 200,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: _items.map((item) {
          final isActive = activePanel == item.panel;
          return Material(
            color: isActive ? cs.secondaryContainer : Colors.transparent,
            child: InkWell(
              onTap: () => onSelect(item.panel),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Icon(
                      item.icon,
                      size: 18,
                      color: isActive
                          ? cs.onSecondaryContainer
                          : cs.onSurfaceVariant,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      item.label,
                      style: TextStyle(
                        color: isActive
                            ? cs.onSecondaryContainer
                            : cs.onSurfaceVariant,
                        fontWeight: isActive
                            ? FontWeight.w600
                            : FontWeight.normal,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ===========================================================================
// CONTA panel
// ===========================================================================

class _ContaPanel extends ConsumerWidget {
  final VoidCallback onLogout;

  const _ContaPanel({required this.onLogout});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Profile card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cs.surfaceContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  // Avatar
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: cs.primary,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Center(
                      child: Text(
                        'P',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Psicóloga',
                          style: TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 15),
                        ),
                        Text(
                          'Administrador · sessão ativa',
                          style: TextStyle(
                              color: cs.onSurfaceVariant, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  // Conectado badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.green.shade100,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'Conectado',
                      style: TextStyle(
                        color: Colors.green.shade800,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),

            // PREFERÊNCIAS section
            Text('PREFERÊNCIAS',
                style: textTheme.labelSmall?.copyWith(
                    letterSpacing: 1.2, color: cs.onSurfaceVariant)),
            const SizedBox(height: 8),

            // Idioma
            _SettingRow(
              label: 'Idioma',
              subtitle: 'Idioma da interface',
              trailing: DropdownButton<String>(
                value: 'pt',
                underline: const SizedBox(),
                items: const [
                  DropdownMenuItem(value: 'pt', child: Text('Português Brasil')),
                  DropdownMenuItem(value: 'en', child: Text('English')),
                  DropdownMenuItem(value: 'de', child: Text('Deutsch')),
                ],
                onChanged: (_) {},
              ),
            ),

            // Tema
            _SettingRow(
              label: 'Tema',
              subtitle: 'Aparência do aplicativo',
              trailing: DropdownButton<String>(
                value: 'auto',
                underline: const SizedBox(),
                items: const [
                  DropdownMenuItem(value: 'auto', child: Text('Automático')),
                  DropdownMenuItem(value: 'light', child: Text('Claro')),
                  DropdownMenuItem(value: 'dark', child: Text('Escuro')),
                ],
                onChanged: (_) {},
              ),
            ),

            // Notificação de saldo em aberto
            _SwitchRow(
              label: 'Notificação de saldo em aberto',
              subtitle: 'Alertas de pagamentos pendentes',
              value: false,
              onChanged: (_) {},
            ),

            // Banner de fim de ano
            _SwitchRow(
              label: 'Banner de fim de ano',
              subtitle: 'Exibir resumo anual em dezembro',
              value: true,
              onChanged: (_) {},
            ),

            const SizedBox(height: 32),

            // Sair da sessão
            OutlinedButton.icon(
              onPressed: onLogout,
              style: OutlinedButton.styleFrom(
                foregroundColor: cs.error,
                side: BorderSide(color: cs.error),
              ),
              icon: const Icon(Icons.logout),
              label: const Text('Sair da sessão'),
            ),
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// IMPORTAR DADOS panel — embeds the existing import UI
// ===========================================================================

class _ImportarPanel extends ConsumerStatefulWidget {
  const _ImportarPanel();

  @override
  ConsumerState<_ImportarPanel> createState() => _ImportarPanelState();
}

class _ImportarPanelState extends ConsumerState<_ImportarPanel> {
  int _selectedYear = DateTime.now().year;
  bool _dryRun = true;
  bool _isHovering = false;
  bool _isImporting = false;

  String? _selectedFileName;
  Uint8List? _selectedFileBytes;

  final List<_LogLine> _logs = [];
  final ScrollController _logScrollController = ScrollController();

  static const _years = [2023, 2024, 2025, 2026];

  @override
  void dispose() {
    _logScrollController.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    setState(() {
      _selectedFileName = file.name;
      _selectedFileBytes = file.bytes;
      _logs.clear();
    });
  }

  Future<void> _runImport() async {
    if (_selectedFileBytes == null) return;

    setState(() {
      _isImporting = true;
      _logs.clear();
    });

    final apiClient = ref.read(apiClientProvider);
    final dio = apiClient.dio;

    try {
      final response = await dio.post<ResponseBody>(
        '/api/import',
        queryParameters: {
          'year': _selectedYear,
          'dryRun': _dryRun,
        },
        data: Stream.fromIterable([_selectedFileBytes!]),
        options: Options(
          contentType: 'text/csv',
          responseType: ResponseType.stream,
          headers: {'Content-Length': _selectedFileBytes!.length},
        ),
      );

      final stream = response.data!.stream;
      String buffer = '';

      await for (final chunk in stream) {
        buffer += utf8.decode(chunk);
        final lines = buffer.split('\n');
        buffer = lines.removeLast();

        for (final line in lines) {
          final trimmed = line.trim();
          if (trimmed.isEmpty) continue;
          try {
            final json = jsonDecode(trimmed) as Map<String, dynamic>;
            if (mounted) {
              setState(() => _logs.add(_LogLine.fromJson(json)));
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (_logScrollController.hasClients) {
                  _logScrollController.animateTo(
                    _logScrollController.position.maxScrollExtent,
                    duration: const Duration(milliseconds: 150),
                    curve: Curves.easeOut,
                  );
                }
              });
            }
          } catch (_) {}
        }
      }

      if (buffer.trim().isNotEmpty) {
        try {
          final json = jsonDecode(buffer.trim()) as Map<String, dynamic>;
          if (mounted) setState(() => _logs.add(_LogLine.fromJson(json)));
        } catch (_) {}
      }
    } on DioException catch (e) {
      final msg =
          e.response?.data?.toString() ?? e.message ?? 'Erro de conexão';
      if (mounted) {
        setState(
            () => _logs.add(_LogLine(_LogLevel.err, 'Erro: $msg')));
      }
    } catch (e) {
      if (mounted) {
        setState(() =>
            _logs.add(_LogLine(_LogLevel.err, 'Erro inesperado: $e')));
      }
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  Color _logColor(BuildContext context, _LogLevel level) {
    final cs = Theme.of(context).colorScheme;
    return switch (level) {
      _LogLevel.ok => Colors.green.shade400,
      _LogLevel.warn => Colors.amber.shade600,
      _LogLevel.err => cs.error,
      _LogLevel.info => cs.secondary,
    };
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Importar dados', style: textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'Migração única de dados históricos exportados do Google Sheets '
              '("Financeiro Psicologia").',
              style: textTheme.bodyMedium
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 24),

            // Year selector
            Row(
              children: [
                Text('Ano de referência', style: textTheme.bodyLarge),
                const SizedBox(width: 16),
                DropdownButton<int>(
                  value: _selectedYear,
                  items: _years
                      .map((y) =>
                          DropdownMenuItem(value: y, child: Text('$y')))
                      .toList(),
                  onChanged: _isImporting
                      ? null
                      : (v) => setState(() => _selectedYear = v!),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Dry-run toggle
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Modo simulação'),
              subtitle: const Text('Validar sem gravar dados no banco'),
              value: _dryRun,
              onChanged:
                  _isImporting ? null : (v) => setState(() => _dryRun = v),
            ),
            const SizedBox(height: 16),

            // Drop zone
            _DropZone(
              isHovering: _isHovering,
              selectedFileName: _selectedFileName,
              isImporting: _isImporting,
              onTap: _isImporting ? null : _pickFile,
              onHoverChanged: (v) => setState(() => _isHovering = v),
            ),
            const SizedBox(height: 16),

            // Import button
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: (_selectedFileBytes != null && !_isImporting)
                    ? _runImport
                    : null,
                icon: _isImporting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.upload_rounded),
                label: Text(_isImporting
                    ? 'Importando...'
                    : _dryRun
                        ? 'Simular importação'
                        : 'Importar dados'),
              ),
            ),

            // Log output
            if (_logs.isNotEmpty) ...[
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                height: 320,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.surfaceContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: ListView.builder(
                  controller: _logScrollController,
                  itemCount: _logs.length,
                  itemBuilder: (context, i) {
                    final line = _logs[i];
                    return Text(
                      line.message,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        color: _logColor(context, line.level),
                        height: 1.6,
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// BACKUP panel
// ===========================================================================

class _BackupPanel extends ConsumerStatefulWidget {
  const _BackupPanel();

  @override
  ConsumerState<_BackupPanel> createState() => _BackupPanelState();
}

class _BackupPanelState extends ConsumerState<_BackupPanel> {
  bool _loading = false;
  final List<_BackupEntry> _entries = [];

  Future<void> _generateBackup() async {
    setState(() => _loading = true);
    try {
      final apiClient = ref.read(apiClientProvider);
      final data = await apiClient.post('/api/backup') as Map<String, dynamic>;
      final filename = data['filename'] as String? ?? 'backup.dump';
      setState(() {
        _entries.insert(
          0,
          _BackupEntry(
            filename: filename,
            date: DateTime.now(),
            isNew: true,
          ),
        );
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Backup gerado com sucesso.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao gerar backup: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Backup', style: textTheme.titleLarge),
            const SizedBox(height: 16),

            FilledButton.icon(
              onPressed: _loading ? null : _generateBackup,
              icon: _loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.backup_outlined),
              label:
                  Text(_loading ? 'Gerando...' : 'Gerar backup agora'),
            ),

            if (_entries.isNotEmpty) ...[
              const SizedBox(height: 28),
              Text('BACKUPS ANTERIORES',
                  style: textTheme.labelSmall?.copyWith(
                      letterSpacing: 1.2, color: cs.onSurfaceVariant)),
              const SizedBox(height: 8),
              ..._entries.map((e) => _BackupEntryRow(entry: e)),
            ],
          ],
        ),
      ),
    );
  }
}

class _BackupEntryRow extends StatelessWidget {
  final _BackupEntry entry;

  const _BackupEntryRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dateStr =
        '${entry.date.day.toString().padLeft(2, '0')}/'
        '${entry.date.month.toString().padLeft(2, '0')}/'
        '${entry.date.year} '
        '${entry.date.hour.toString().padLeft(2, '0')}:'
        '${entry.date.minute.toString().padLeft(2, '0')}';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(Icons.insert_drive_file_outlined,
              size: 18, color: cs.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.filename,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w500)),
                Text(dateStr,
                    style: TextStyle(
                        fontSize: 11, color: cs.onSurfaceVariant)),
              ],
            ),
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: entry.isNew
                  ? cs.primaryContainer
                  : cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              entry.isNew ? 'Novo' : 'OK',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: entry.isNew
                    ? cs.onPrimaryContainer
                    : cs.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// SEGURANÇA panel
// ===========================================================================

class _SegurancaPanel extends ConsumerStatefulWidget {
  const _SegurancaPanel();

  @override
  ConsumerState<_SegurancaPanel> createState() => _SegurancaPanelState();
}

class _SegurancaPanelState extends ConsumerState<_SegurancaPanel> {
  final _senhaAtualCtrl = TextEditingController();
  final _novaSenhaCtrl = TextEditingController();
  final _confirmarCtrl = TextEditingController();
  bool _savingPassword = false;
  String? _passwordError;
  String? _passwordSuccess;

  String _sessionTimeout = '8h';

  @override
  void dispose() {
    _senhaAtualCtrl.dispose();
    _novaSenhaCtrl.dispose();
    _confirmarCtrl.dispose();
    super.dispose();
  }

  Future<void> _changePassword() async {
    setState(() {
      _passwordError = null;
      _passwordSuccess = null;
    });

    if (_novaSenhaCtrl.text != _confirmarCtrl.text) {
      setState(() => _passwordError = 'As senhas não coincidem.');
      return;
    }
    if (_novaSenhaCtrl.text.length < 8) {
      setState(() =>
          _passwordError = 'A nova senha deve ter pelo menos 8 caracteres.');
      return;
    }

    setState(() => _savingPassword = true);
    try {
      final apiClient = ref.read(apiClientProvider);
      await apiClient.post('/auth/change-password', data: {
        'senhaAtual': _senhaAtualCtrl.text,
        'novaSenha': _novaSenhaCtrl.text,
      });
      setState(() {
        _passwordSuccess =
            'Hash gerado. Atualize PSYFINANCE_PASSWORD_HASH e reinicie.';
        _senhaAtualCtrl.clear();
        _novaSenhaCtrl.clear();
        _confirmarCtrl.clear();
      });
    } catch (e) {
      setState(() => _passwordError = e.toString());
    } finally {
      if (mounted) setState(() => _savingPassword = false);
    }
  }

  Future<void> _deleteAllData() async {
    final cs = Theme.of(context).colorScheme;
    final confirmed = await _showConfirmDeleteDialog(context, cs);
    if (confirmed == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text('Operação ainda não implementada no servidor.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ALTERAR SENHA
            Text('ALTERAR SENHA',
                style: textTheme.labelSmall?.copyWith(
                    letterSpacing: 1.2, color: cs.onSurfaceVariant)),
            const SizedBox(height: 12),

            if (_passwordError != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: cs.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(_passwordError!,
                      style: TextStyle(color: cs.onErrorContainer)),
                ),
              ),
            if (_passwordSuccess != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.green.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(_passwordSuccess!,
                      style: TextStyle(color: Colors.green.shade900)),
                ),
              ),

            TextField(
              controller: _senhaAtualCtrl,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Senha atual'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _novaSenhaCtrl,
              obscureText: true,
              decoration:
                  const InputDecoration(labelText: 'Nova senha'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _confirmarCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                  labelText: 'Confirmar nova senha'),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _savingPassword ? null : _changePassword,
              child: Text(_savingPassword
                  ? 'Salvando...'
                  : 'Salvar nova senha'),
            ),

            const SizedBox(height: 32),

            // SESSÃO
            Text('SESSÃO',
                style: textTheme.labelSmall?.copyWith(
                    letterSpacing: 1.2, color: cs.onSurfaceVariant)),
            const SizedBox(height: 8),

            _SettingRow(
              label: 'Tempo limite de sessão',
              subtitle: 'Expiração automática do token',
              trailing: DropdownButton<String>(
                value: _sessionTimeout,
                underline: const SizedBox(),
                items: const [
                  DropdownMenuItem(value: '8h', child: Text('8 horas')),
                  DropdownMenuItem(value: '24h', child: Text('24 horas')),
                  DropdownMenuItem(
                      value: '30d', child: Text('30 dias')),
                  DropdownMenuItem(
                      value: 'never', child: Text('Nunca')),
                ],
                onChanged: (v) =>
                    setState(() => _sessionTimeout = v!),
              ),
            ),

            // LGPD — disabled, always on
            _SwitchRow(
              label: 'Proteção de dados (LGPD)',
              subtitle:
                  'Nunca registrar nome, e-mail ou CPF em logs',
              value: true,
              onChanged: null,
            ),

            const SizedBox(height: 32),

            // ZONA DE PERIGO
            Text('ZONA DE PERIGO',
                style: textTheme.labelSmall?.copyWith(
                    letterSpacing: 1.2, color: cs.error)),
            const SizedBox(height: 12),

            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Apagar todos os dados',
                          style: TextStyle(
                              color: cs.error,
                              fontWeight: FontWeight.w600)),
                      Text(
                        'Remove permanentemente todos os pacientes, sessões e '
                        'pagamentos. Esta ação é irreversível.',
                        style: TextStyle(
                            color: cs.onSurfaceVariant,
                            fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                OutlinedButton(
                  onPressed: _deleteAllData,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: cs.error,
                    side: BorderSide(color: cs.error),
                  ),
                  child: const Text('Apagar tudo'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

Future<bool?> _showConfirmDeleteDialog(
    BuildContext context, ColorScheme cs) {
  final ctrl = TextEditingController();
  return showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        title:
            Text('Apagar todos os dados', style: TextStyle(color: cs.error)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Esta ação é irreversível. Digite CONFIRMAR para prosseguir.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              onChanged: (_) => setS(() {}),
              decoration: const InputDecoration(
                  hintText: 'CONFIRMAR', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: ctrl.text == 'CONFIRMAR'
                ? () => Navigator.pop(ctx, true)
                : null,
            style:
                FilledButton.styleFrom(backgroundColor: cs.error),
            child: const Text('Apagar tudo'),
          ),
        ],
      ),
    ),
  );
}

// ===========================================================================
// SOBRE panel
// ===========================================================================

class _SobrePanel extends ConsumerStatefulWidget {
  const _SobrePanel();

  @override
  ConsumerState<_SobrePanel> createState() => _SobrePanelState();
}

class _SobrePanelState extends ConsumerState<_SobrePanel> {
  bool _dbConnected = false;
  Timer? _healthTimer;

  @override
  void initState() {
    super.initState();
    _checkHealth();
    _healthTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) _checkHealth();
    });
  }

  @override
  void dispose() {
    _healthTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkHealth() async {
    try {
      final apiClient = ref.read(apiClientProvider);
      await apiClient.get('/health');
      if (mounted) setState(() => _dbConnected = true);
    } catch (_) {
      if (mounted) setState(() => _dbConnected = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Logo mark
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: cs.primary,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.water_drop_rounded,
                  color: Colors.white, size: 30),
            ),
            const SizedBox(height: 16),
            const Text('PsyFinance',
                style:
                    TextStyle(fontSize: 20, fontWeight: FontWeight.w500)),
            const SizedBox(height: 4),
            Text(
              'Versão 1.0.0 · Flutter + Node.js',
              style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 28),

            // Info rows
            _InfoRow(label: 'Plataforma', value: 'Web (Chrome)'),
            _InfoRow(
                label: 'API',
                value: 'localhost:3000 (Node.js backend on Windows)'),
            _InfoRow(label: 'Banco de dados', value: 'PostgreSQL 16'),
            _InfoRow(
              label: 'Última sincronização',
              value: _dbConnected ? 'Agora' : 'Sem conexão',
              valueColor: _dbConnected
                  ? Colors.green.shade600
                  : cs.error,
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _InfoRow({required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 180,
            child: Text(label,
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
          ),
          Text(value,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: valueColor)),
        ],
      ),
    );
  }
}

// ===========================================================================
// Shared widgets
// ===========================================================================

class _SettingRow extends StatelessWidget {
  final String label;
  final String subtitle;
  final Widget trailing;

  const _SettingRow({
    required this.label,
    required this.subtitle,
    required this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w500)),
                Text(subtitle,
                    style: TextStyle(
                        fontSize: 12, color: cs.onSurfaceVariant)),
              ],
            ),
          ),
          trailing,
        ],
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  final String label;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  const _SwitchRow({
    required this.label,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w500)),
                Text(subtitle,
                    style: TextStyle(
                        fontSize: 12, color: cs.onSurfaceVariant)),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

// ===========================================================================
// Drop zone (reused from original import UI)
// ===========================================================================

class _DropZone extends StatelessWidget {
  final bool isHovering;
  final String? selectedFileName;
  final bool isImporting;
  final VoidCallback? onTap;
  final ValueChanged<bool> onHoverChanged;

  const _DropZone({
    required this.isHovering,
    required this.selectedFileName,
    required this.isImporting,
    required this.onTap,
    required this.onHoverChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final borderColor =
        isHovering ? cs.primary : cs.outlineVariant;
    final fillColor = isHovering
        ? cs.primaryContainer
        : cs.surfaceContainerLow;

    return MouseRegion(
      cursor: isImporting
          ? SystemMouseCursors.forbidden
          : SystemMouseCursors.click,
      onEnter: (_) => onHoverChanged(true),
      onExit: (_) => onHoverChanged(false),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: double.infinity,
          height: 130,
          decoration: BoxDecoration(
            color: fillColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: borderColor,
              width: 1.5,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.arrow_downward_rounded,
                size: 32,
                color: isHovering
                    ? cs.primary
                    : cs.onSurfaceVariant,
              ),
              const SizedBox(height: 8),
              if (selectedFileName != null) ...[
                Text(
                  selectedFileName!,
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface),
                ),
                const SizedBox(height: 4),
                Text(
                  'Toque para trocar o arquivo',
                  style: TextStyle(
                      fontSize: 12, color: cs.onSurfaceVariant),
                ),
              ] else ...[
                const Text(
                  'Arraste o arquivo CSV aqui',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 4),
                Text(
                  'ou toque para selecionar',
                  style: TextStyle(
                      fontSize: 12, color: cs.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
