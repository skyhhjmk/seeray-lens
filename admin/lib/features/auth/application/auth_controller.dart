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
  @override
  AuthState build() {
    _api = ref.read(apiProvider);
    _tokens = ref.read(authTokenStoreProvider);
    _api.refresh = refresh;
    Future.microtask(_restore);
    return const AuthState(AuthPhase.restoring);
  }

  Future<void> _restore() async {
    try {
      final token = await _tokens.readRefreshToken();
      if (token == null || token.isEmpty) {
        state = const AuthState(AuthPhase.unauthenticated);
        return;
      }
      state = AuthState(AuthPhase.refreshing, refreshToken: token);
      await refresh();
    } catch (_) {
      await _tokens.clear();
      state = const AuthState(AuthPhase.unauthenticated);
    }
  }

  Future<void> login(String email, String password) async {
    state = const AuthState(AuthPhase.authenticating);
    try {
      final d = await _api.request(
        'POST',
        '/api/v1/auth/login',
        body: {'email': email, 'password': password},
      );
      await _set(d);
    } catch (e) {
      state = AuthState(AuthPhase.error, message: 'Unable to sign in');
    }
  }

  Future<String?> refresh() {
    return _inflight ??= _refresh().whenComplete(() => _inflight = null);
  }

  Future<String?> _refresh() async {
    final token = state.refreshToken;
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
      await _set(d);
      return state.accessToken;
    } catch (_) {
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

  Future<void> logout() async {
    final token = state.refreshToken;
    try {
      if (token != null) {
        await _api.request(
          'POST',
          '/api/v1/auth/logout',
          body: {'refreshToken': token},
          retried: true,
        );
      }
    } finally {
      _api.accessToken = null;
      await _tokens.clear();
      state = const AuthState(AuthPhase.unauthenticated);
    }
  }
}
