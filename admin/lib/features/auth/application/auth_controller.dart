import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/auth/auth_state.dart';
import '../../../core/auth/auth_token_store.dart';
import '../../../core/network/seeray_api.dart';

final apiProvider = Provider((_) => SeeRayApi());
final authTokenStoreProvider = Provider<AuthTokenStore>(
  (_) => PreferencesAuthTokenStore(),
);
final authProvider = NotifierProvider<AuthController, AuthState>(
  AuthController.new,
);

class AuthController extends Notifier<AuthState> {
  late SeeRayApi _api;
  late AuthTokenStore _tokens;
  Future<String?>? _inflight;
  int? _inflightGeneration;
  int _sessionGeneration = 0;
  @override
  AuthState build() {
    _api = ref.read(apiProvider);
    _tokens = ref.read(authTokenStoreProvider);
    _api.refresh = refresh;
    Future.microtask(_restore);
    return const AuthState(AuthPhase.restoring);
  }

  Future<void> _restore() async {
    final generation = _sessionGeneration;
    try {
      final token = await _tokens.readRefreshToken();
      if (generation != _sessionGeneration) return;
      if (token == null || token.isEmpty) {
        state = const AuthState(AuthPhase.unauthenticated);
        return;
      }
      state = AuthState(AuthPhase.refreshing, refreshToken: token);
      await _refresh(token, generation);
    } catch (_) {
      if (generation != _sessionGeneration) return;
      await _tokens.clear();
      state = const AuthState(AuthPhase.unauthenticated);
    }
  }

  Future<void> login(String email, String password) async {
    final generation = ++_sessionGeneration;
    // A login request must never carry an expired access token from the
    // previous session. Quarkus authenticates a supplied bearer token before
    // dispatching even public endpoints, so a stale header can block a valid
    // email/password login until the process is restarted.
    _api.accessToken = null;
    state = const AuthState(AuthPhase.authenticating);
    try {
      final d = await _api.request(
        'POST',
        '/api/v1/auth/login',
        body: {'email': email, 'password': password},
        retried: true,
      );
      if (generation != _sessionGeneration) return;
      await _set(d);
    } catch (e) {
      if (generation != _sessionGeneration) return;
      state = AuthState(AuthPhase.error, message: _loginError(e));
    }
  }

  Future<void> registerForInvitation({
    required String email,
    required String password,
    required String displayName,
    required String invitationToken,
  }) async {
    final generation = ++_sessionGeneration;
    _api.accessToken = null;
    state = const AuthState(AuthPhase.authenticating);
    try {
      final data = await _api.request(
        'POST',
        '/api/v1/auth/register-invitation',
        body: {
          'email': email,
          'password': password,
          'displayName': displayName,
          'invitationToken': invitationToken,
        },
        retried: true,
      );
      if (generation != _sessionGeneration) return;
      await _set(data);
    } catch (error) {
      if (generation != _sessionGeneration) return;
      _api.accessToken = null;
      state = AuthState(AuthPhase.error, message: _loginError(error));
    }
  }

  Future<String?> refresh() {
    final generation = _sessionGeneration;
    final token = state.refreshToken;
    final current = _inflight;
    if (current != null && _inflightGeneration == generation) return current;

    final future = _refresh(token, generation);
    _inflight = future;
    _inflightGeneration = generation;
    future.whenComplete(() {
      if (identical(_inflight, future)) {
        _inflight = null;
        _inflightGeneration = null;
      }
    });
    return future;
  }

  Future<String?> _refresh(String? token, int generation) async {
    if (token == null) {
      return null;
    }
    state = AuthState(AuthPhase.refreshing, refreshToken: token);
    try {
      final d = await _api.request(
        'POST',
        '/api/v1/auth/refresh',
        body: {'refreshToken': token},
        retried: true,
      );
      if (generation != _sessionGeneration) return null;
      await _set(d);
      return state.accessToken;
    } catch (_) {
      if (generation != _sessionGeneration) return null;
      _api.accessToken = null;
      await _tokens.clear();
      state = const AuthState(AuthPhase.expired);
      return null;
    }
  }

  Future<void> _set(dynamic d) async {
    state = AuthState(
      AuthPhase.authenticated,
      accessToken: d['accessToken'] as String,
      refreshToken: d['refreshToken'] as String,
    );
    _api.accessToken = state.accessToken;
    await _tokens.writeRefreshToken(state.refreshToken!);
  }

  String _loginError(Object error) {
    if (error is! ApiFailure) return 'Unable to sign in';
    return switch (error.status) {
      0 => error.message,
      401 => 'Email or password is incorrect',
      403 => 'This account is disabled',
      _ => error.message,
    };
  }

  Future<void> logout() async {
    ++_sessionGeneration;
    final token = state.refreshToken;
    _api.accessToken = null;
    await _tokens.clear();
    state = const AuthState(AuthPhase.unauthenticated);
    try {
      if (token != null) {
        await _api.request(
          'POST',
          '/api/v1/auth/logout',
          body: {'refreshToken': token},
          retried: true,
        );
      }
    } catch (_) {
      // Logout is already complete locally. A network failure must not leave
      // the UI stuck or prevent the user from signing in again.
    }
  }
}
