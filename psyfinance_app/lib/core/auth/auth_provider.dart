import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'auth_state.dart';
import 'auth_repository.dart';

// ---------------------------------------------------------------------------
// AuthNotifier — token lives in-memory ONLY (Riverpod state).
//
// Security rationale: storing the JWT in SharedPreferences (which maps to
// localStorage on Flutter web) exposes it to any JavaScript running on the
// page (XSS risk). In-memory storage means the token is lost on page refresh
// and the user must log in again — this is acceptable for a single-user
// internal tool and is far safer than localStorage persistence.
// ---------------------------------------------------------------------------

class _RouterRefreshNotifier extends ChangeNotifier {
  void refresh() => notifyListeners();
}

class AuthNotifier extends StateNotifier<AuthState> {
  final AuthRepository _repo;
  final _routerRefresh = _RouterRefreshNotifier();

  AuthNotifier(this._repo) : super(const AuthState.unauthenticated());

  /// Listenable for GoRouter's refreshListenable.
  Listenable get routerListenable => _routerRefresh;

  /// Callback invoked when a forced logout happens (e.g. 401 from API).
  VoidCallback? onForceLogout;

  Future<void> login({
    required String usuario,
    required String senha,
  }) async {
    final data = await _repo.login(usuario: usuario, senha: senha);
    final token = data['token'] as String;
    final expiresAt = DateTime.parse(data['expiresAt'] as String);

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
    if (token != null) {
      await _repo.logout(token);
    }
  }

  /// Called by ApiClient interceptor on 401.
  void forceLogout() {
    if (!state.isAuthenticated) return;
    state = const AuthState.unauthenticated();
    _routerRefresh.refresh();
    onForceLogout?.call();
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
