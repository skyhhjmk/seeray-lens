enum AuthPhase {
  restoring,
  unauthenticated,
  authenticating,
  authenticated,
  refreshing,
  expired,
  error,
}

class AuthState {
  const AuthState(
    this.phase, {
    this.accessToken,
    this.refreshToken,
    this.message,
    this.isSystemAdmin = false,
    this.mustChangePassword = false,
  });
  final AuthPhase phase;
  final String? accessToken;
  final String? refreshToken;
  final String? message;
  final bool isSystemAdmin;
  final bool mustChangePassword;
  bool get isAuthenticated =>
      phase == AuthPhase.authenticated && accessToken != null;
}
