import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Configuration for a single SeeRay Lens site.
class SeeRayAnalyticsOptions {
  const SeeRayAnalyticsOptions({
    required this.siteId,
    required this.apiOrigin,
    this.requireConsent = false,
    this.allowInsecureLocalhost = false,
    this.batchSize = 10,
    this.flushInterval = const Duration(seconds: 10),
  });

  final String siteId;
  final String apiOrigin;
  final bool requireConsent;
  /// Allows `http://localhost`, loopback IPv4, or loopback IPv6 for local development only.
  final bool allowInsecureLocalhost;
  final int batchSize;
  final Duration flushInterval;
}

enum SeeRayConsentState { unknown, granted, denied }

/// Explicit, consent-aware analytics for Flutter apps.
///
/// The host application decides when a screen is visible and when an event or
/// conversion has succeeded. This SDK never installs a route observer.
class SeeRayAnalytics {
  SeeRayAnalytics._(this.options, this._preferences, this._client, this._endpoint)
      : _batchSize = options.batchSize.clamp(1, _maximumBatchSize),
        _flushInterval = _boundedInterval(options.flushInterval) {
    _timer = Timer.periodic(_flushInterval, (_) => unawaited(flush()));
  }

  static const _maximumBatchSize = 10;
  static const _maximumPendingEvents = 100;
  static const _sessionTimeout = Duration(minutes: 30);
  static const _maximumProperties = 64;

  final SeeRayAnalyticsOptions options;
  final SharedPreferences _preferences;
  final http.Client _client;
  final Uri _endpoint;
  final int _batchSize;
  final Duration _flushInterval;
  final List<Map<String, Object?>> _queue = [];
  bool _sending = false;
  bool _closed = false;
  int _droppedEventCount = 0;
  String? _userId;
  Timer? _timer;

  static Future<SeeRayAnalytics> create(
    SeeRayAnalyticsOptions options, {
    http.Client? client,
  }) async {
    _validateOptions(options);
    final origin = Uri.parse(options.apiOrigin);
    final preferences = await SharedPreferences.getInstance();
    return SeeRayAnalytics._(
      options,
      preferences,
      client ?? http.Client(),
      origin.resolve('/api/v1/collect'),
    );
  }

  SeeRayConsentState get consentState {
    switch (_preferences.getString(_key('consent'))) {
      case 'granted':
        return SeeRayConsentState.granted;
      case 'denied':
        return SeeRayConsentState.denied;
      default:
        return options.requireConsent
            ? SeeRayConsentState.unknown
            : SeeRayConsentState.granted;
    }
  }

  int get pendingEventCount => _queue.length;
  int get droppedEventCount => _droppedEventCount;

  /// Apply a real visitor choice. Denial clears SDK-owned identifiers and data.
  Future<void> setConsent({required bool granted}) async {
    if (_closed) return;
    await _preferences.setString(_key('consent'), granted ? 'granted' : 'denied');
    if (granted) return;
    _queue.clear();
    _userId = null;
    await Future.wait([
      _preferences.remove(_key('visitor')),
      _preferences.remove(_key('session')),
      _preferences.remove(_key('lastActivity')),
    ]);
  }

  Future<void> optOut() => setConsent(granted: false);

  /// Sets an opaque application-owned identity for subsequent consented events.
  void setUserId(String? value) {
    _userId = consentState == SeeRayConsentState.granted ? _bounded(value, 256) : null;
  }

  void trackPageView({required String url, String? title, String? referrer}) {
    _record(type: 'page_view', url: url, title: title, referrer: referrer);
  }

  void trackScreen({
    required String name,
    required String url,
    String? title,
    String? referrer,
  }) {
    final screen = _bounded(name, 120);
    if (screen == null) return;
    _record(
      type: 'page_view',
      url: url,
      title: title ?? screen,
      referrer: referrer,
      properties: {'screen': screen},
    );
  }

  void trackGoal({
    required String name,
    required String url,
    Map<String, Object?> properties = const {},
  }) => _record(type: 'goal', url: url, name: name, properties: properties);

  void trackEvent({
    required String type,
    required String url,
    String? category,
    String? action,
    String? name,
    String? title,
    String? referrer,
    Map<String, Object?> properties = const {},
  }) {
    final eventType = _bounded(type, 64);
    if (eventType == null) return;
    _record(
      type: eventType,
      url: url,
      category: category,
      action: action,
      name: name,
      title: title,
      referrer: referrer,
      properties: properties,
    );
  }

  Future<bool> flush() async {
    if (_closed || _sending || consentState != SeeRayConsentState.granted) return false;
    if (_queue.isEmpty) return true;
    _sending = true;
    final batch = List<Map<String, Object?>>.from(_queue.take(_batchSize));
    try {
      final response = await _client.post(
        _endpoint,
        headers: const {'Content-Type': 'application/json', 'Accept': 'application/json'},
        body: jsonEncode({
          'schemaVersion': 1,
          'siteId': options.siteId,
          'sentAt': DateTime.now().toUtc().toIso8601String(),
          'events': batch,
        }),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) return false;
      _queue.removeRange(0, batch.length);
      await _preferences.setInt(_key('lastActivity'), DateTime.now().millisecondsSinceEpoch);
      return true;
    } catch (_) {
      return false;
    } finally {
      _sending = false;
    }
  }

  /// Stops the flush loop and makes one best-effort non-blocking final delivery.
  void close() {
    if (_closed) return;
    _closed = true;
    _timer?.cancel();
    _timer = null;
    unawaited(_flushAfterClose());
  }

  Future<void> _flushAfterClose() async {
    _closed = false;
    await flush();
    _closed = true;
    _client.close();
  }

  void _record({
    required String type,
    required String url,
    String? title,
    String? referrer,
    String? category,
    String? action,
    String? name,
    Map<String, Object?> properties = const {},
  }) {
    if (_closed || consentState != SeeRayConsentState.granted) return;
    final pageUrl = _minimizeUrl(url);
    if (pageUrl == null || _queue.length >= _maximumPendingEvents) {
      if (_queue.length >= _maximumPendingEvents) _droppedEventCount++;
      return;
    }
    final now = DateTime.now();
    final ids = _identity(now);
    _queue.add({
      'eventId': _uuid(),
      'type': type,
      'occurredAt': now.toUtc().toIso8601String(),
      'url': pageUrl,
      if (_bounded(title, 512) case final value?) 'title': value,
      if (_minimizeUrl(referrer) case final value?) 'referrer': value,
      'visitorId': ids.$1,
      'sessionId': ids.$2,
      if (_userId != null) 'userId': _userId,
      if (_bounded(category, 120) case final value?) 'category': value,
      if (_bounded(action, 120) case final value?) 'action': value,
      if (_bounded(name, 256) case final value?) 'name': value,
      'properties': _cleanProperties(properties),
      'context': _context(),
    });
    if (_queue.length >= _batchSize) unawaited(flush());
  }

  (String, String) _identity(DateTime now) {
    var visitor = _preferences.getString(_key('visitor'));
    var session = _preferences.getString(_key('session'));
    final last = _preferences.getInt(_key('lastActivity'));
    if (visitor == null) {
      visitor = _uuid();
      unawaited(_preferences.setString(_key('visitor'), visitor));
    }
    if (session == null || last == null || now.difference(DateTime.fromMillisecondsSinceEpoch(last)) > _sessionTimeout) {
      session = _uuid();
      unawaited(_preferences.setString(_key('session'), session));
    }
    return (visitor, session);
  }

  String _key(String suffix) => 'seeray:${options.siteId}:$suffix';

  static void _validateOptions(SeeRayAnalyticsOptions options) {
    if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$').hasMatch(options.siteId)) {
      throw ArgumentError.value(options.siteId, 'siteId', 'must be a valid tracking ID');
    }
    final origin = Uri.tryParse(options.apiOrigin);
    final localDevelopment = origin != null &&
        origin.scheme == 'http' &&
        options.allowInsecureLocalhost &&
        _isLoopback(origin.host);
    if (origin == null || (origin.scheme != 'https' && !localDevelopment) || origin.host.isEmpty) {
      throw ArgumentError.value(options.apiOrigin, 'apiOrigin', 'must be an HTTPS origin');
    }
    if (options.flushInterval <= Duration.zero) {
      throw ArgumentError.value(options.flushInterval, 'flushInterval', 'must be positive');
    }
  }

  static bool _isLoopback(String host) =>
      host == 'localhost' || host == '127.0.0.1' || host == '::1';

  static Duration _boundedInterval(Duration value) => Duration(
    milliseconds: value.inMilliseconds.clamp(200, 60000),
  );

  static String? _minimizeUrl(String? raw) {
    if (raw == null) return null;
    final uri = Uri.tryParse(raw.trim());
    if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http') || uri.host.isEmpty) return null;
    return (uri.scheme == 'https'
            ? Uri.https(uri.authority, uri.path)
            : Uri.http(uri.authority, uri.path))
        .toString();
  }

  static String? _bounded(String? value, int maximum) {
    final clean = value?.trim();
    return clean == null || clean.isEmpty || clean.length > maximum ? null : clean;
  }

  static Map<String, Object?> _cleanProperties(Map<String, Object?> values) {
    final result = <String, Object?>{};
    for (final entry in values.entries.take(_maximumProperties)) {
      final key = _bounded(entry.key, 120);
      final value = entry.value;
      if (key == null || value is! String && value is! num && value is! bool) continue;
      if (value is String && _bounded(value, 1000) == null) continue;
      if (value is double && !value.isFinite) continue;
      result[key] = value;
    }
    return result;
  }

  static Map<String, Object> _context() {
    final dispatcher = PlatformDispatcher.instance;
    final operatingSystem = switch (defaultTargetPlatform) {
      TargetPlatform.android => 'Android',
      TargetPlatform.iOS => 'iOS',
      TargetPlatform.windows => 'Windows',
      TargetPlatform.macOS => 'macOS',
      TargetPlatform.linux => 'Linux',
      TargetPlatform.fuchsia => 'Other',
    };
    final deviceType = switch (defaultTargetPlatform) {
      TargetPlatform.android || TargetPlatform.iOS => 'mobile',
      TargetPlatform.windows || TargetPlatform.macOS || TargetPlatform.linux => 'desktop',
      _ => 'other',
    };
    final view = dispatcher.views.isEmpty ? null : dispatcher.views.first;
    final physical = view?.physicalSize;
    final ratio = view?.devicePixelRatio;
    return {
      'browser': 'Other',
      'operatingSystem': operatingSystem,
      'deviceType': deviceType,
      'language': dispatcher.locale.toLanguageTag(),
      if (physical != null && physical.width > 0 && physical.height > 0) ...{
        'screenWidth': physical.width.round(),
        'screenHeight': physical.height.round(),
        'viewportWidth': physical.width.round(),
        'viewportHeight': physical.height.round(),
      },
      if (ratio != null && ratio >= 0.25 && ratio <= 8) 'pixelRatio': ratio,
    };
  }

  static String _uuid() {
    final random = Random();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}
