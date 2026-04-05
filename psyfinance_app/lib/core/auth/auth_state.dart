class AuthState {
  final bool isAuthenticated;
  final String? token;
  final DateTime? expiresAt;

  const AuthState({
    required this.isAuthenticated,
    this.token,
    this.expiresAt,
  });

  const AuthState.unauthenticated()
      : isAuthenticated = false,
        token = null,
        expiresAt = null;

  AuthState copyWith({
    bool? isAuthenticated,
    String? token,
    DateTime? expiresAt,
  }) =>
      AuthState(
        isAuthenticated: isAuthenticated ?? this.isAuthenticated,
        token: token ?? this.token,
        expiresAt: expiresAt ?? this.expiresAt,
      );
}
