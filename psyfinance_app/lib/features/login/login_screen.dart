import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:psyfinance_app/core/auth/auth_provider.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _usuarioCtrl = TextEditingController();
  final _senhaCtrl = TextEditingController();

  bool _obscureSenha = true;
  bool _lembrar = false;
  bool _loading = false;
  bool _showError = false;

  @override
  void dispose() {
    _usuarioCtrl.dispose();
    _senhaCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _showError = false;
    });

    try {
      await ref.read(authProvider.notifier).login(
            usuario: _usuarioCtrl.text.trim(),
            senha: _senhaCtrl.text,
            lembrar: _lembrar,
          );
      if (mounted) context.go('/mensal');
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        setState(() => _showError = true);
      } else {
        setState(() => _showError = true);
      }
    } catch (_) {
      setState(() => _showError = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final size = MediaQuery.sizeOf(context);

    return Scaffold(
      backgroundColor: cs.surfaceContainer,
      body: Column(
        children: [
          // ----------------------------------------------------------------
          // Top band — primaryContainer, ~25% height
          // ----------------------------------------------------------------
          Container(
            width: double.infinity,
            height: size.height * 0.25,
            color: cs.primaryContainer,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Logo mark
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: cs.primary,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(
                    Icons.water_drop_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'PsyFinance',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w500,
                    color: cs.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Gestão financeira · Psicologia',
                  style: TextStyle(
                    fontSize: 13,
                    color: cs.onPrimaryContainer.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),

          // ----------------------------------------------------------------
          // Form area — centered, scrollable
          // ----------------------------------------------------------------
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: Card(
                    color: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: cs.outlineVariant, width: 0.5),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Error banner
                          if (_showError) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: cs.errorContainer,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.error_outline,
                                      size: 18, color: cs.onErrorContainer),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Usuário ou senha incorretos.',
                                      style: TextStyle(
                                        color: cs.onErrorContainer,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],

                          // Usuário field
                          SizedBox(
                            height: 52,
                            child: TextField(
                              controller: _usuarioCtrl,
                              enabled: !_loading,
                              textInputAction: TextInputAction.next,
                              decoration: InputDecoration(
                                labelText: 'Usuário',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                suffixIcon: const Icon(Icons.person_outline),
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 0),
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),

                          // Senha field
                          SizedBox(
                            height: 52,
                            child: TextField(
                              controller: _senhaCtrl,
                              enabled: !_loading,
                              obscureText: _obscureSenha,
                              onSubmitted: (_) => _submit(),
                              decoration: InputDecoration(
                                labelText: 'Senha',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscureSenha
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                  ),
                                  onPressed: () => setState(
                                      () => _obscureSenha = !_obscureSenha),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 0),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),

                          // Lembrar de mim
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Lembrar de mim',
                                style: TextStyle(fontSize: 14)),
                            value: _lembrar,
                            onChanged: _loading
                                ? null
                                : (v) => setState(() => _lembrar = v ?? false),
                            visualDensity: VisualDensity.compact,
                            controlAffinity: ListTileControlAffinity.leading,
                          ),
                          const SizedBox(height: 12),

                          // Entrar button
                          Opacity(
                            opacity: _loading ? 0.8 : 1.0,
                            child: FilledButton.icon(
                              onPressed: _loading ? null : _submit,
                              style: FilledButton.styleFrom(
                                minimumSize: const Size.fromHeight(48),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(26),
                                ),
                              ),
                              icon: _loading
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.arrow_forward_rounded),
                              label: const Text('Entrar'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
