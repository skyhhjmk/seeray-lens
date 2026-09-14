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
  });
  final AuthPhase phase;
  final String? accessToken;
  final String? refreshToken;
  final String? message;
  bool get isAuthenticated =>
      phase == AuthPhase.authenticated && accessToken != null;
}
