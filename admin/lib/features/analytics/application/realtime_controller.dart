import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';

typedef AnalyticsRealtimeQuery = ({String siteId, int windowMinutes});

class AnalyticsLiveAction {
  const AnalyticsLiveAction({
    required this.at,
    required this.eventType,
    required this.path,
    required this.title,
  });

  final DateTime at;
  final String eventType;
  final String? path;
  final String? title;

  factory AnalyticsLiveAction.fromJson(Map<String, dynamic> json) =>
      AnalyticsLiveAction(
        at: DateTime.parse(json['at'] as String).toLocal(),
        eventType: json['eventType'] as String? ?? 'event',
        path: json['path'] as String?,
        title: json['title'] as String?,
      );
}

class AnalyticsLiveVisitor {
  const AnalyticsLiveVisitor({
    required this.visitorId,
    required this.sessionId,
    required this.startedAt,
    required this.lastActivityAt,
    required this.events,
    required this.pageViews,
    required this.entryPage,
    required this.lastEventType,
    required this.currentPage,
    required this.currentTitle,
    required this.countryCode,
    required this.region,
    required this.city,
    required this.browser,
    required this.operatingSystem,
    required this.deviceType,
    required this.language,
    required this.durationMs,
    required this.actions,
    required this.uniqueIdentity,
  });

  final String visitorId;
  final String sessionId;
  final DateTime startedAt;
  final DateTime lastActivityAt;
  final int events;
  final int pageViews;
  final String? entryPage;
  final String lastEventType;
  final String? currentPage;
  final String? currentTitle;
  final String? countryCode;
  final String? region;
  final String? city;
  final String? browser;
  final String? operatingSystem;
  final String? deviceType;
  final String? language;
  final int durationMs;
  final List<AnalyticsLiveAction> actions;
  final bool uniqueIdentity;

  factory AnalyticsLiveVisitor.fromJson(Map<String, dynamic> json) =>
      AnalyticsLiveVisitor(
        visitorId: json['visitorId'] as String? ?? '',
        sessionId: json['sessionId'] as String? ?? '',
        startedAt: DateTime.parse(json['startedAt'] as String).toLocal(),
        lastActivityAt: DateTime.parse(
          json['lastActivityAt'] as String,
        ).toLocal(),
        events: (json['events'] as num?)?.toInt() ?? 0,
        pageViews: (json['pageViews'] as num?)?.toInt() ?? 0,
        entryPage: json['entryPage'] as String?,
        lastEventType: json['lastEventType'] as String? ?? 'event',
        currentPage: json['currentPage'] as String?,
        currentTitle: json['currentTitle'] as String?,
        countryCode: json['countryCode'] as String?,
        region: json['region'] as String?,
        city: json['city'] as String?,
        browser: json['browser'] as String?,
        operatingSystem: json['operatingSystem'] as String?,
        deviceType: json['deviceType'] as String?,
        language: json['language'] as String?,
        durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
        uniqueIdentity: json['uniqueIdentity'] as bool? ?? true,
        actions: (json['actions'] as List? ?? const [])
            .whereType<Map>()
            .map(
              (item) =>
                  AnalyticsLiveAction.fromJson(Map<String, dynamic>.from(item)),
            )
            .toList(growable: false),
      );
}

final analyticsRealtimeProvider =
    FutureProvider.family<List<AnalyticsLiveVisitor>, AnalyticsRealtimeQuery>((
      ref,
      query,
    ) async {
      final path = Uri(
        path: '/api/v1/sites/${query.siteId}/analytics/realtime',
        queryParameters: {
          'windowMinutes': '${query.windowMinutes}',
          'limit': '100',
        },
      );
      final response =
          await ref.read(apiProvider).request('GET', path.toString()) as List;
      return response
          .whereType<Map>()
          .map(
            (item) =>
                AnalyticsLiveVisitor.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList(growable: false);
    });
