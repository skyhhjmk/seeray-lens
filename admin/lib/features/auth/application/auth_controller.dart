import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/auth/auth_state.dart';
import '../../../core/network/seeray_api.dart';

final apiProvider = Provider((_) => SeeRayApi());
final authProvider = NotifierProvider<AuthController, AuthState>(
  AuthController.new,
);

class AuthController extends Notifier<AuthState> {
  late SeeRayApi _api;
  Future<String?>? _inflight;
  @override
  AuthState build() {
    _api = ref.read(apiProvider);
    _api.refresh = refresh;
    return const AuthState(AuthPhase.unauthenticated);
  }

  Future<void> login(String email, String password) async {
    state = const AuthState(AuthPhase.authenticating);
    try {
      final d = await _api.request(
        'POST',
        '/api/v1/auth/login',
        body: {'email': email, 'password': password},
      );
      _set(d);
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
      _set(d);
      return state.accessToken;
    } catch (_) {
      state = const AuthState(AuthPhase.expired);
      return null;
    }
  }

  void _set(dynamic d) {
    state = AuthState(
      AuthPhase.authenticated,
      accessToken: d['accessToken'] as String,
      refreshToken: d['refreshToken'] as String,
    );
    _api.accessToken = state.accessToken;
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
      state = const AuthState(AuthPhase.unauthenticated);
    }
  }
}
