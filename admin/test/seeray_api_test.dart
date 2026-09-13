import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:seeray_lens_admin/core/network/seeray_api.dart';

void main() {
  test('retries an expired access token exactly once after refresh', () async {
    final client = _QueueClient([
      _response(
        401,
        '{"code":"AUTH_INVALID_TOKEN","message":"Authentication failed"}',
      ),
      _response(200, '{"ok":true}'),
    ]);
    final api = SeeRayApi(client: client);
    api.accessToken = 'expired';
    var refreshes = 0;
    api.refresh = () async {
      refreshes++;
      return 'fresh';
    };

    final result = await api.request('GET', '/api/v1/workspaces');

    expect(result, {'ok': true});
    expect(refreshes, 1);
    expect(client.requests, hasLength(2));
    expect(client.requests.last.headers['authorization'], 'Bearer fresh');
  });

  test('does not retry a second unauthorized response', () async {
    final client = _QueueClient([_response(401, '{}'), _response(401, '{}')]);
    final api = SeeRayApi(client: client);
    api.accessToken = 'expired';
    api.refresh = () async => 'fresh';

    await expectLater(
      api.request('GET', '/api/v1/workspaces'),
      throwsA(isA<ApiFailure>()),
    );
    expect(client.requests, hasLength(2));
  });
}

http.StreamedResponse _response(int status, String body) =>
    http.StreamedResponse(
      Stream<List<int>>.value(body.codeUnits),
      status,
      headers: const {'content-type': 'application/json'},
    );

class _QueueClient extends http.BaseClient {
  _QueueClient(this.responses);
  final List<http.StreamedResponse> responses;
  final List<http.BaseRequest> requests = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    return responses.removeAt(0);
  }
}
