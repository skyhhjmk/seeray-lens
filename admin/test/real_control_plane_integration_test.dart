import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

const _runReal = bool.fromEnvironment('SEERAY_RUN_REAL_API_TESTS');
const _baseUrl = String.fromEnvironment(
  'SEERAY_API_BASE_URL',
  defaultValue: 'http://localhost:8080',
);

void main() {
  test(
    'real control-plane loop: login, workspace, create and fetch site',
    () async {
      final client = http.Client();
      addTearDown(client.close);
      final email =
          'flutter-${DateTime.now().microsecondsSinceEpoch}@example.test';
      final registered = await _json(client, 'POST', '/api/v1/auth/register', {
        'email': email,
        'password': 'correct-horse-battery',
      });
      final access = registered['accessToken'] as String;
      expect(registered['refreshToken'], isA<String>());

      final workspaces =
          await _json(client, 'GET', '/api/v1/workspaces', null, access: access)
              as List;
      expect(workspaces, hasLength(1));
      final workspaceId =
          (workspaces.single as Map<String, dynamic>)['id'] as String;

      final created =
          await _json(client, 'POST', '/api/v1/workspaces/$workspaceId/sites', {
                'name': 'Flutter integration site',
                'timezone': 'UTC',
                'defaultLanguage': 'en',
                'rawRetentionDays': 30,
                'aggregateRetentionDays': 730,
              }, access: access)
              as Map<String, dynamic>;
      final siteId = created['id'] as String;
      expect(created['trackingId'], isNotEmpty);

      final fetched = await _json(
        client,
        'GET',
        '/api/v1/sites/$siteId',
        null,
        access: access,
      );
      expect((fetched as Map<String, dynamic>)['id'], siteId);

      final domain =
          await _json(client, 'POST', '/api/v1/sites/$siteId/domains', {
                'host': 'https://Example.com:443/path',
                'allowSubdomains': true,
                'enabled': true,
              }, access: access)
              as Map<String, dynamic>;
      expect(domain['host'], 'example.com');

      final token =
          await _json(
                client,
                'POST',
                '/api/v1/workspaces/$workspaceId/api-tokens',
                {
                  'name': 'Flutter integration token',
                  'scopes': ['sites:read'],
                },
                access: access,
              )
              as Map<String, dynamic>;
      expect(token['plainToken'], isA<String>());
      final tokenId = (token['token'] as Map<String, dynamic>)['id'] as String;
      final listed =
          await _json(
                client,
                'GET',
                '/api/v1/workspaces/$workspaceId/api-tokens',
                null,
                access: access,
              )
              as List;
      expect((listed.single as Map<String, dynamic>)['plainToken'], isNull);
      await _json(
        client,
        'POST',
        '/api/v1/workspaces/$workspaceId/api-tokens/$tokenId/revoke',
        null,
        access: access,
      );
      await _json(client, 'POST', '/api/v1/auth/logout', {
        'refreshToken': registered['refreshToken'],
      }, access: access);
    },
    skip: !_runReal
        ? 'Set SEERAY_RUN_REAL_API_TESTS=true against a running local control plane.'
        : false,
  );
}

Future<dynamic> _json(
  http.Client client,
  String method,
  String path,
  Object? body, {
  String? access,
}) async {
  final response = await client
      .send(
        http.Request(method, Uri.parse('$_baseUrl$path'))
          ..headers.addAll({
            'Content-Type': 'application/json',
            if (access != null) 'Authorization': 'Bearer $access',
          })
          ..body = body == null ? '' : jsonEncode(body),
      )
      .timeout(const Duration(seconds: 15));
  final text = await response.stream.bytesToString();
  expect(
    response.statusCode,
    inInclusiveRange(200, 299),
    reason: '$method $path: $text',
  );
  return text.isEmpty ? null : jsonDecode(text);
}
