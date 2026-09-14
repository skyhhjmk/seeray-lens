import 'package:shared_preferences/shared_preferences.dart';

/// Stores only the rotating refresh token. Access tokens remain memory-only.
abstract class AuthTokenStore {
  Future<String?> readRefreshToken();
  Future<void> writeRefreshToken(String token);
  Future<void> clear();
}

class PreferencesAuthTokenStore implements AuthTokenStore {
  static const _key = 'seeray.auth.refresh_token';

  @override
  Future<String?> readRefreshToken() async =>
      (await SharedPreferences.getInstance()).getString(_key);

  @override
  Future<void> writeRefreshToken(String token) async =>
      (await SharedPreferences.getInstance()).setString(_key, token);

  @override
  Future<void> clear() async =>
      (await SharedPreferences.getInstance()).remove(_key);
}
