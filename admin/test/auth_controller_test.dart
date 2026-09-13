import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:seeray_lens_admin/core/auth/auth_state.dart';
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
      overrides: [apiProvider.overrideWithValue(SeeRayApi(client: client))],
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
      overrides: [apiProvider.overrideWithValue(SeeRayApi(client: client))],
    );
    addTearDown(container.dispose);
    await container
        .read(authProvider.notifier)
        .login('person@example.com', 'password');
    await container.read(authProvider.notifier).refresh();
    expect(container.read(authProvider).phase, AuthPhase.expired);
  });
}

ProviderContainer _container(List<String> bodies) => ProviderContainer(
  overrides: [
    apiProvider.overrideWithValue(SeeRayApi(client: _Client(bodies))),
  ],
);

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
