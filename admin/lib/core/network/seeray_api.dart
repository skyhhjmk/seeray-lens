import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class ApiFailure implements Exception {
  const ApiFailure(this.status, this.message);

  final int status;
  final String message;

  @override
  String toString() => message;
}

class SeeRayApi {
  SeeRayApi({http.Client? client, this.baseUrl = 'http://localhost:8080'})
    : _client = client ?? http.Client();

  final http.Client _client;
  final String baseUrl;
  String? accessToken;
  Future<String?> Function()? refresh;

  Future<dynamic> request(
    String method,
    String path, {
    Object? body,
    bool retried = false,
  }) => _request(method, path, body: body, retried: retried);

  /// Sends a public authentication request without forwarding a stale bearer.
  /// Refresh endpoints must not receive the access token that just expired.
  Future<dynamic> requestUnauthenticated(
    String method,
    String path, {
    Object? body,
  }) => _request(method, path, body: body, retried: true, includeAuth: false);

  Future<dynamic> _request(
    String method,
    String path, {
    Object? body,
    bool retried = false,
    bool includeAuth = true,
  }) async {
    try {
      final outgoing = http.Request(method, Uri.parse('$baseUrl$path'))
        ..headers.addAll({
          'Content-Type': 'application/json',
          if (includeAuth && accessToken != null)
            'Authorization': 'Bearer $accessToken',
        })
        ..body = body == null ? '' : jsonEncode(body);
      final response = await _client
          .send(outgoing)
          .timeout(const Duration(seconds: 15));
      final text = await response.stream.bytesToString();
      final data = text.isEmpty ? null : _decode(text);

      if (response.statusCode == 401 && !retried && refresh != null) {
        final token = await refresh!();
        if (token != null) {
          accessToken = token;
          return await _request(
            method,
            path,
            body: body,
            retried: true,
            includeAuth: includeAuth,
          );
        }
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ApiFailure(
          response.statusCode,
          data is Map
              ? (data['message'] as String? ?? 'Request failed')
              : 'Request failed',
        );
      }
      return data;
    } on TimeoutException {
      throw const ApiFailure(0, 'The server did not respond in time');
    } on http.ClientException {
      throw const ApiFailure(0, 'Unable to reach the server');
    }
  }

  Future<dynamic> requestBytes(
    String method,
    String path,
    List<int> bytes, {
    required String contentType,
  }) async {
    try {
      final outgoing = http.Request(method, Uri.parse('$baseUrl$path'))
        ..headers.addAll({
          'Content-Type': contentType,
          if (accessToken != null) 'Authorization': 'Bearer $accessToken',
        })
        ..bodyBytes = bytes;
      final response = await _client
          .send(outgoing)
          .timeout(const Duration(seconds: 30));
      final text = await response.stream.bytesToString();
      final data = text.isEmpty ? null : _decode(text);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ApiFailure(
          response.statusCode,
          data is Map
              ? (data['message'] as String? ?? 'Request failed')
              : 'Request failed',
        );
      }
      return data;
    } on TimeoutException {
      throw const ApiFailure(0, 'The server did not respond in time');
    } on http.ClientException {
      throw const ApiFailure(0, 'Unable to reach the server');
    }
  }

  dynamic _decode(String value) {
    try {
      return jsonDecode(value);
    } on FormatException {
      return null;
    }
  }
}
