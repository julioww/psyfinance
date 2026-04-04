import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:psyfinance_app/core/api_client.dart';

final _healthProvider = FutureProvider<String>((ref) async {
  final client = ApiClient();
  try {
    final data = await client.get('/health') as Map<String, dynamic>;
    return data['status'] == 'ok' ? 'ok' : 'error';
  } catch (_) {
    return 'error';
  }
});

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final healthAsync = ref.watch(_healthProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: Center(
        child: healthAsync.when(
          loading: () => const CircularProgressIndicator(),
          error: (_, __) => _StatusCard(
            icon: Icons.cloud_off,
            label: 'Erro de conexão',
            color: colorScheme.error,
            textTheme: textTheme,
          ),
          data: (status) => _StatusCard(
            icon: status == 'ok' ? Icons.cloud_done : Icons.cloud_off,
            label: status == 'ok' ? 'API conectada ✓' : 'Erro de conexão',
            color: status == 'ok' ? colorScheme.primary : colorScheme.error,
            textTheme: textTheme,
          ),
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final TextTheme textTheme;

  const _StatusCard({
    required this.icon,
    required this.label,
    required this.color,
    required this.textTheme,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: color),
            const SizedBox(height: 12),
            Text(label, style: textTheme.titleMedium?.copyWith(color: color)),
          ],
        ),
      ),
    );
  }
}
