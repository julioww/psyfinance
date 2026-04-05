import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'auth_state.dart';
import 'auth_repository.dart';

const _kTokenKey = 'psyfinance_token';
const _kExpiresAtKey = 'psyfinance_expires_at';

// ---------------------------------------------------------------------------
// Internal ChangeNotifier used only as GoRouter's refreshListenable.
// ---------------------------------------------------------------------------

class _RouterRefreshNotifier extends ChangeNotifier {
  void refresh() => notifyListeners();
}

// ---------------------------------------------------------------------------
// AuthNotifier
// ---------------------------------------------------------------------------

class AuthNotifier extends StateNotifier<AuthState> {
  final AuthRepository _repo;
  final _routerRefresh = _RouterRefreshNotifier();

  AuthNotifier(this._repo) : super(const AuthState.unauthenticated()) {
    _restoreSession();
  }

  /// Listenable for GoRouter's refreshListenable.
  Listenable get routerListenable => _routerRefresh;

  /// Callback invoked when a forced logout happens (e.g. 401 from API).
  /// Wired up in routerProvider so the router navigates to /login.
  VoidCallback? onForceLogout;

  Future<void> _restoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_kTokenKey);
    final expiresAtStr = prefs.getString(_kExpiresAtKey);

    if (token == null || expiresAtStr == null) return;

    final expiresAt = DateTime.tryParse(expiresAtStr);
    if (expiresAt == null || DateTime.now().isAfter(expiresAt)) {
      await _clearStorage();
      return;
    }

    state = AuthState(
      isAuthenticated: true,
      token: token,
      expiresAt: expiresAt,
    );
    _routerRefresh.refresh();
  }

  Future<void> login({
    required String usuario,
    required String senha,
    bool lembrar = false,
  }) async {
    final data = await _repo.login(
      usuario: usuario,
      senha: senha,
      lembrar: lembrar,
    );
    final token = data['token'] as String;
    final expiresAt = DateTime.parse(data['expiresAt'] as String);

    await _saveStorage(token, expiresAt);

    state = AuthState(
      isAuthenticated: true,
      token: token,
      expiresAt: expiresAt,
    );
    _routerRefresh.refresh();
  }

  Future<void> logout() async {
    final token = state.token;
    state = const AuthState.unauthenticated();
    _routerRefresh.refresh();
    await _clearStorage();
    if (token != null) {
      await _repo.logout(token);
    }
  }

  /// Called by ApiClient interceptor on 401.
  void forceLogout() {
    if (!state.isAuthenticated) return;
    state = const AuthState.unauthenticated();
    _clearStorage();
    _routerRefresh.refresh();
    onForceLogout?.call();
  }

  Future<void> _saveStorage(String token, DateTime expiresAt) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kTokenKey, token);
    await prefs.setString(_kExpiresAtKey, expiresAt.toIso8601String());
  }

  Future<void> _clearStorage() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kTokenKey);
    await prefs.remove(_kExpiresAtKey);
  }

  @override
  void dispose() {
    _routerRefresh.dispose();
    super.dispose();
  }
}

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

final authRepositoryProvider = Provider<AuthRepository>(
  (_) => AuthRepository(),
);

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>(
  (ref) => AuthNotifier(ref.watch(authRepositoryProvider)),
);
