import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:psyfinance_app/features/patients/patients_provider.dart';

import 'export_download_stub.dart'
    if (dart.library.html) 'export_download_web.dart';

// ---------------------------------------------------------------------------
// Enums
// ---------------------------------------------------------------------------

enum ExportType { monthly, annual, summary }

enum ExportFormat { csv, pdf }

extension _ExportTypeX on ExportType {
  String get apiName => name; // 'monthly' | 'annual' | 'summary'

  String get fileLabel {
    switch (this) {
      case ExportType.monthly:
        return 'mensal';
      case ExportType.annual:
        return 'anual';
      case ExportType.summary:
        return 'resumo';
    }
  }
}

// ---------------------------------------------------------------------------
// ExportButton
// ---------------------------------------------------------------------------

/// Reusable export button. Calls /api/export/{type}?year=...&format=...
/// On success triggers a browser file-save dialog (web) or saves to Downloads
/// (desktop) and shows a SnackBar. Shows a CircularProgressIndicator while
/// the request is in-flight.
class ExportButton extends ConsumerStatefulWidget {
  final ExportType type;
  final ExportFormat format;
  final int year;

  /// Override for testing: if provided, called instead of [triggerBrowserDownload].
  final Future<void> Function(List<int> bytes, String filename)? onDownload;

  const ExportButton({
    super.key,
    required this.type,
    required this.format,
    required this.year,
    this.onDownload,
  });

  @override
  ConsumerState<ExportButton> createState() => _ExportButtonState();
}

class _ExportButtonState extends ConsumerState<ExportButton> {
  bool _loading = false;

  String get _filename =>
      'psyfinance-${widget.type.fileLabel}-${widget.year}.${widget.format.name}';

  Future<void> _handleTap() async {
    if (_loading) return;
    setState(() => _loading = true);

    try {
      final client = ref.read(apiClientProvider);
      final bytes = await client.getBytes(
        '/api/export/${widget.type.apiName}',
        queryParameters: {
          'year': widget.year,
          'format': widget.format.name,
        },
      );

      final downloader = widget.onDownload ?? triggerBrowserDownload;
      await downloader(bytes, _filename);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Arquivo salvo: $_filename')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: _loading ? null : _handleTap,
      icon: _loading
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.file_download_outlined, size: 16),
      label: Text(
        widget.format == ExportFormat.csv ? 'Exportar CSV' : 'Exportar PDF',
      ),
    );
  }
}
