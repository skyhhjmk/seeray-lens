import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:seeray_lens_admin/core/auth/auth_state.dart';
import 'package:seeray_lens_admin/core/auth/auth_token_store.dart';
import 'package:seeray_lens_admin/core/network/seeray_api.dart';
import 'package:seeray_lens_admin/features/auth/application/auth_controller.dart';

void main() {
  test('login and logout update auth state', () async {
    final container = _container([
      '{"accessToken":"access","refreshToken":"refresh"}',
      '',
    ]);
    addTearDown(container.dispose);
    await container
        .read(authProvider.notifier)
        .login('person@example.com', 'password');
    expect(container.read(authProvider), isA<AuthState>());
    expect(container.read(authProvider).phase, AuthPhase.authenticated);
    await container.read(authProvider.notifier).logout();
    expect(container.read(authProvider).phase, AuthPhase.unauthenticated);
  });

  test('refresh is single-flight and updates the token pair', () async {
    final client = _Client([
      '{"accessToken":"access-a","refreshToken":"refresh-a"}',
      '{"accessToken":"access-b","refreshToken":"refresh-b"}',
    ]);
    final container = ProviderContainer(
      overrides: [
        apiProvider.overrideWithValue(SeeRayApi(client: client)),
        authTokenStoreProvider.overrideWithValue(_MemoryTokenStore()),
      ],
    );
    addTearDown(container.dispose);
    await container
        .read(authProvider.notifier)
        .login('person@example.com', 'password');

    final tokens = await Future.wait([
      container.read(authProvider.notifier).refresh(),
      container.read(authProvider.notifier).refresh(),
    ]);
    expect(tokens, ['access-b', 'access-b']);
    expect(client.requests, 2, reason: 'one login plus one refresh');
    expect(container.read(authProvider).refreshToken, 'refresh-b');
  });

  test('failed refresh expires the session', () async {
    final client = _Client(
      ['{"accessToken":"access-a","refreshToken":"refresh-a"}', '{}'],
      statuses: [200, 401],
    );
    final container = ProviderContainer(
      overrides: [
        apiProvider.overrideWithValue(SeeRayApi(client: client)),
        authTokenStoreProvider.overrideWithValue(_MemoryTokenStore()),
      ],
    );
    addTearDown(container.dispose);
    await container
        .read(authProvider.notifier)
        .login('person@example.com', 'password');
    await container.read(authProvider.notifier).refresh();
    expect(container.read(authProvider).phase, AuthPhase.expired);
  });

  test('restores a persisted refresh token after app restart', () async {
    final store = _MemoryTokenStore()..value = 'saved-refresh';
    final client = _Client([
      '{"accessToken":"new-access","refreshToken":"rotated-refresh"}',
    ]);
    final container = ProviderContainer(
      overrides: [
        apiProvider.overrideWithValue(SeeRayApi(client: client)),
        authTokenStoreProvider.overrideWithValue(store),
      ],
    );
    addTearDown(container.dispose);
    container.read(authProvider);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(container.read(authProvider).phase, AuthPhase.authenticated);
    expect(container.read(authProvider).accessToken, 'new-access');
    expect(store.value, 'rotated-refresh');
    expect(client.requests, 1);
  });

  test('a stale restore cannot overwrite a successful manual login', () async {
    final store = _MemoryTokenStore()..value = 'stale-refresh';
    final client = _DeferredRestoreClient();
    final container = ProviderContainer(
      overrides: [
        apiProvider.overrideWithValue(SeeRayApi(client: client)),
        authTokenStoreProvider.overrideWithValue(store),
      ],
    );
    addTearDown(container.dispose);

    container.read(authProvider);
    await client.restoreStarted.future;
    await container
        .read(authProvider.notifier)
        .login('person@example.com', 'correct-password');
    client.finishRestore();
    await Future<void>.delayed(Duration.zero);

    expect(container.read(authProvider).phase, AuthPhase.authenticated);
    expect(container.read(authProvider).accessToken, 'manual-access');
    expect(store.value, 'manual-refresh');
  });
}

ProviderContainer _container(List<String> bodies) => ProviderContainer(
  overrides: [
    apiProvider.overrideWithValue(SeeRayApi(client: _Client(bodies))),
    authTokenStoreProvider.overrideWithValue(_MemoryTokenStore()),
  ],
);

class _MemoryTokenStore implements AuthTokenStore {
  String? value;
  @override
  Future<void> clear() async => value = null;
  @override
  Future<String?> readRefreshToken() async => value;
  @override
  Future<void> writeRefreshToken(String token) async => value = token;
}

class _Client extends http.BaseClient {
  _Client(List<String> bodies, {List<int>? statuses})
    : bodies = List.of(bodies),
      statuses = List.of(statuses ?? List.filled(bodies.length, 200));
  final List<String> bodies;
  final List<int> statuses;
  var requests = 0;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests++;
    return http.StreamedResponse(
      Stream<List<int>>.value(bodies.removeAt(0).codeUnits),
      statuses.removeAt(0),
      headers: const {'content-type': 'application/json'},
    );
  }
}

class _DeferredRestoreClient extends http.BaseClient {
  final restoreStarted = Completer<void>();
  final _restoreResponse = Completer<http.StreamedResponse>();

  void finishRestore() {
    _restoreResponse.complete(
      http.StreamedResponse(
        Stream<List<int>>.value('{}'.codeUnits),
        401,
        headers: const {'content-type': 'application/json'},
      ),
    );
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (request.url.path.endsWith('/auth/refresh')) {
      restoreStarted.complete();
      return _restoreResponse.future;
    }
    return Future.value(
      http.StreamedResponse(
        Stream<List<int>>.value(
          '{"accessToken":"manual-access","refreshToken":"manual-refresh"}'
              .codeUnits,
        ),
        200,
        headers: const {'content-type': 'application/json'},
      ),
    );
  }
}
