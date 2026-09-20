import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import 'analytics_controller.dart';

class AnalyticsVisitorLogEntry {
  const AnalyticsVisitorLogEntry({
    required this.visitorId,
    required this.startedAt,
    required this.lastActivityAt,
    required this.entryPage,
    required this.exitPage,
    required this.pageViews,
    required this.events,
    required this.durationMs,
    required this.bounce,
    required this.visitorType,
    required this.fingerprintRiskLevel,
    required this.fingerprintRelatedVisitorCount,
    required this.fingerprintRelatedAccountCount,
    required this.fingerprintConfidence,
  });

  final String visitorId;
  final DateTime startedAt;
  final DateTime lastActivityAt;
  final String? entryPage;
  final String? exitPage;
  final int pageViews;
  final int events;
  final int durationMs;
  final bool bounce;
  final String visitorType;
  final String fingerprintRiskLevel;
  final int fingerprintRelatedVisitorCount;
  final int fingerprintRelatedAccountCount;
  final String fingerprintConfidence;

  factory AnalyticsVisitorLogEntry.fromJson(
    Map<String, dynamic> json,
  ) => AnalyticsVisitorLogEntry(
    visitorId: json['visitorId'] as String? ?? '',
    startedAt: DateTime.parse(json['startedAt'] as String).toLocal(),
    lastActivityAt: DateTime.parse(json['lastActivityAt'] as String).toLocal(),
    entryPage: json['entryPage'] as String?,
    exitPage: json['exitPage'] as String?,
    pageViews: (json['pageViews'] as num?)?.toInt() ?? 0,
    events: (json['events'] as num?)?.toInt() ?? 0,
    durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
    bounce: json['bounce'] as bool? ?? false,
    visitorType: json['visitorType'] as String? ?? 'unknown',
    fingerprintRiskLevel: json['fingerprintRiskLevel'] as String? ?? 'none',
    fingerprintRelatedVisitorCount:
        (json['fingerprintRelatedVisitorCount'] as num?)?.toInt() ?? 0,
    fingerprintRelatedAccountCount:
        (json['fingerprintRelatedAccountCount'] as num?)?.toInt() ?? 0,
    fingerprintConfidence: json['fingerprintConfidence'] as String? ?? 'none',
  );
}

final analyticsVisitorLogProvider =
    FutureProvider.family<
      List<AnalyticsVisitorLogEntry>,
      AnalyticsDashboardQuery
    >((ref, query) async {
      final path = Uri(
        path: '/api/v1/sites/${query.siteId}/analytics/visitor-log',
        queryParameters: {
          'from': query.range.fromQuery,
          'to': query.range.toQuery,
          'limit': '100',
          if (query.segmentId != null) 'segmentId': query.segmentId!,
        },
      );
      final result =
          await ref.read(apiProvider).request('GET', path.toString()) as List;
      return result
          .whereType<Map>()
          .map(
            (item) => AnalyticsVisitorLogEntry.fromJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .where((item) => item.visitorId.isNotEmpty)
          .toList(growable: false);
    });

class AnalyticsVisitorProfileQuery {
  const AnalyticsVisitorProfileQuery({
    required this.siteId,
    required this.visitorId,
    required this.range,
    this.segmentId,
  });

  final String siteId;
  final String visitorId;
  final AnalyticsDateRange range;
  final String? segmentId;

  @override
  bool operator ==(Object other) =>
      other is AnalyticsVisitorProfileQuery &&
      other.siteId == siteId &&
      other.visitorId == visitorId &&
      other.segmentId == segmentId &&
      other.range.fromQuery == range.fromQuery &&
      other.range.toQuery == range.toQuery;

  @override
  int get hashCode =>
      Object.hash(siteId, visitorId, segmentId, range.fromQuery, range.toQuery);
}

class AnalyticsVisitorProfile {
  const AnalyticsVisitorProfile({
    required this.visitorId,
    required this.firstSeenAt,
    required this.lastSeenAt,
    required this.lifetimeSessions,
    required this.identityLinkStatus,
    required this.linkedBrowserCount,
    required this.rangeSessions,
    required this.rangePageViews,
    required this.rangeEvents,
    required this.rangeBouncedSessions,
    required this.averageSessionDurationMs,
    required this.sessions,
    required this.hasMoreSessions,
    required this.nextSessionsCursor,
    required this.actions,
    required this.hasMoreActions,
    required this.nextActionsCursor,
    required this.fingerprintRiskLevel,
    required this.fingerprintRelatedVisitorCount,
    required this.fingerprintRelatedAccountCount,
    required this.fingerprintConfidence,
  });

  final String visitorId;
  final DateTime firstSeenAt;
  final DateTime lastSeenAt;
  final int lifetimeSessions;
  final String identityLinkStatus;
  final int linkedBrowserCount;
  final int rangeSessions;
  final int rangePageViews;
  final int rangeEvents;
  final int rangeBouncedSessions;
  final int averageSessionDurationMs;
  final List<AnalyticsVisitorProfileSession> sessions;
  final bool hasMoreSessions;
  final String? nextSessionsCursor;
  final List<AnalyticsVisitorProfileAction> actions;
  final bool hasMoreActions;
  final String? nextActionsCursor;
  final String fingerprintRiskLevel;
  final int fingerprintRelatedVisitorCount;
  final int fingerprintRelatedAccountCount;
  final String fingerprintConfidence;

  factory AnalyticsVisitorProfile.fromJson(
    Map<String, dynamic> json,
  ) => AnalyticsVisitorProfile(
    visitorId: json['visitorId'] as String? ?? '',
    firstSeenAt: DateTime.parse(json['firstSeenAt'] as String).toLocal(),
    lastSeenAt: DateTime.parse(json['lastSeenAt'] as String).toLocal(),
    lifetimeSessions: (json['lifetimeSessions'] as num?)?.toInt() ?? 0,
    identityLinkStatus: json['identityLinkStatus'] as String? ?? 'anonymous',
    linkedBrowserCount: (json['linkedBrowserCount'] as num?)?.toInt() ?? 1,
    rangeSessions: (json['rangeSessions'] as num?)?.toInt() ?? 0,
    rangePageViews: (json['rangePageViews'] as num?)?.toInt() ?? 0,
    rangeEvents: (json['rangeEvents'] as num?)?.toInt() ?? 0,
    rangeBouncedSessions: (json['rangeBouncedSessions'] as num?)?.toInt() ?? 0,
    averageSessionDurationMs:
        (json['averageSessionDurationMs'] as num?)?.toInt() ?? 0,
    sessions: (json['sessions'] as List? ?? const [])
        .whereType<Map>()
        .map(
          (item) => AnalyticsVisitorProfileSession.fromJson(
            Map<String, dynamic>.from(item),
          ),
        )
        .toList(growable: false),
    hasMoreSessions: json['hasMoreSessions'] as bool? ?? false,
    nextSessionsCursor: json['nextSessionsCursor'] as String?,
    actions: (json['actions'] as List? ?? const [])
        .whereType<Map>()
        .map(
          (item) => AnalyticsVisitorProfileAction.fromJson(
            Map<String, dynamic>.from(item),
          ),
        )
        .toList(growable: false),
    hasMoreActions: json['hasMoreActions'] as bool? ?? false,
    nextActionsCursor: json['nextActionsCursor'] as String?,
    fingerprintRiskLevel: json['fingerprintRiskLevel'] as String? ?? 'none',
    fingerprintRelatedVisitorCount:
        (json['fingerprintRelatedVisitorCount'] as num?)?.toInt() ?? 0,
    fingerprintRelatedAccountCount:
        (json['fingerprintRelatedAccountCount'] as num?)?.toInt() ?? 0,
    fingerprintConfidence: json['fingerprintConfidence'] as String? ?? 'none',
  );
}

class AnalyticsVisitorProfileHistoryQuery {
  const AnalyticsVisitorProfileHistoryQuery({
    required this.profileQuery,
    this.sessionsCursor,
    this.actionsCursor,
  });

  final AnalyticsVisitorProfileQuery profileQuery;
  final String? sessionsCursor;
  final String? actionsCursor;

  @override
  bool operator ==(Object other) =>
      other is AnalyticsVisitorProfileHistoryQuery &&
      other.profileQuery == profileQuery &&
      other.sessionsCursor == sessionsCursor &&
      other.actionsCursor == actionsCursor;

  @override
  int get hashCode => Object.hash(profileQuery, sessionsCursor, actionsCursor);
}

class AnalyticsVisitorProfileHistoryPage {
  const AnalyticsVisitorProfileHistoryPage({
    required this.sessions,
    required this.nextSessionsCursor,
    required this.actions,
    required this.nextActionsCursor,
  });

  final List<AnalyticsVisitorProfileSession> sessions;
  final String? nextSessionsCursor;
  final List<AnalyticsVisitorProfileAction> actions;
  final String? nextActionsCursor;

  factory AnalyticsVisitorProfileHistoryPage.fromJson(
    Map<String, dynamic> json,
  ) => AnalyticsVisitorProfileHistoryPage(
    sessions: (json['sessions'] as List? ?? const [])
        .whereType<Map>()
        .map(
          (item) => AnalyticsVisitorProfileSession.fromJson(
            Map<String, dynamic>.from(item),
          ),
        )
        .toList(growable: false),
    nextSessionsCursor: json['nextSessionsCursor'] as String?,
    actions: (json['actions'] as List? ?? const [])
        .whereType<Map>()
        .map(
          (item) => AnalyticsVisitorProfileAction.fromJson(
            Map<String, dynamic>.from(item),
          ),
        )
        .toList(growable: false),
    nextActionsCursor: json['nextActionsCursor'] as String?,
  );
}

class AnalyticsVisitorProfileSession {
  const AnalyticsVisitorProfileSession({
    required this.sessionId,
    required this.startedAt,
    required this.lastActivityAt,
    required this.entryPage,
    required this.exitPage,
    required this.pageViews,
    required this.events,
    required this.durationMs,
    required this.bounce,
    required this.visitorType,
    required this.browser,
    required this.operatingSystem,
    required this.deviceType,
    required this.language,
    required this.countryCode,
    required this.region,
    required this.city,
    required this.referrerHost,
    required this.campaignSource,
    required this.campaignMedium,
    required this.campaignName,
  });

  final String sessionId;
  final DateTime startedAt;
  final DateTime lastActivityAt;
  final String? entryPage;
  final String? exitPage;
  final int pageViews;
  final int events;
  final int durationMs;
  final bool bounce;
  final String visitorType;
  final String? browser;
  final String? operatingSystem;
  final String? deviceType;
  final String? language;
  final String? countryCode;
  final String? region;
  final String? city;
  final String? referrerHost;
  final String? campaignSource;
  final String? campaignMedium;
  final String? campaignName;

  factory AnalyticsVisitorProfileSession.fromJson(Map<String, dynamic> json) =>
      AnalyticsVisitorProfileSession(
        sessionId: json['sessionId'] as String? ?? '',
        startedAt: DateTime.parse(json['startedAt'] as String).toLocal(),
        lastActivityAt: DateTime.parse(
          json['lastActivityAt'] as String,
        ).toLocal(),
        entryPage: json['entryPage'] as String?,
        exitPage: json['exitPage'] as String?,
        pageViews: (json['pageViews'] as num?)?.toInt() ?? 0,
        events: (json['events'] as num?)?.toInt() ?? 0,
        durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
        bounce: json['bounce'] as bool? ?? false,
        visitorType: json['visitorType'] as String? ?? 'unknown',
        browser: json['browser'] as String?,
        operatingSystem: json['operatingSystem'] as String?,
        deviceType: json['deviceType'] as String?,
        language: json['language'] as String?,
        countryCode: json['countryCode'] as String?,
        region: json['region'] as String?,
        city: json['city'] as String?,
        referrerHost: json['referrerHost'] as String?,
        campaignSource: json['campaignSource'] as String?,
        campaignMedium: json['campaignMedium'] as String?,
        campaignName: json['campaignName'] as String?,
      );
}

class AnalyticsVisitorProfileAction {
  const AnalyticsVisitorProfileAction({
    required this.at,
    required this.eventType,
    required this.path,
    required this.title,
    required this.sessionId,
  });

  final DateTime at;
  final String eventType;
  final String? path;
  final String? title;
  final String sessionId;

  factory AnalyticsVisitorProfileAction.fromJson(Map<String, dynamic> json) =>
      AnalyticsVisitorProfileAction(
        at: DateTime.parse(json['at'] as String).toLocal(),
        eventType: json['eventType'] as String? ?? 'event',
        path: json['path'] as String?,
        title: json['title'] as String?,
        sessionId: json['sessionId'] as String? ?? '',
      );
}

final analyticsVisitorProfileProvider =
    FutureProvider.family<
      AnalyticsVisitorProfile,
      AnalyticsVisitorProfileQuery
    >((ref, query) async {
      final path = Uri(
        pathSegments: [
          '',
          'api',
          'v1',
          'sites',
          query.siteId,
          'analytics',
          'visitors',
          query.visitorId,
        ],
        queryParameters: {
          'from': query.range.fromQuery,
          'to': query.range.toQuery,
          if (query.segmentId != null) 'segmentId': query.segmentId!,
        },
      );
      final result =
          await ref.read(apiProvider).request('GET', path.toString())
              as Map<String, dynamic>;
      return AnalyticsVisitorProfile.fromJson(result);
    });

final analyticsVisitorProfileHistoryProvider =
    FutureProvider.family<
      AnalyticsVisitorProfileHistoryPage,
      AnalyticsVisitorProfileHistoryQuery
    >((ref, query) async {
      final profileQuery = query.profileQuery;
      final path = Uri(
        pathSegments: [
          '',
          'api',
          'v1',
          'sites',
          profileQuery.siteId,
          'analytics',
          'visitors',
          profileQuery.visitorId,
          'history',
        ],
        queryParameters: {
          'from': profileQuery.range.fromQuery,
          'to': profileQuery.range.toQuery,
          if (profileQuery.segmentId != null)
            'segmentId': profileQuery.segmentId!,
          if (query.sessionsCursor != null)
            'sessionsCursor': query.sessionsCursor!,
          if (query.actionsCursor != null)
            'actionsCursor': query.actionsCursor!,
        },
      );
      final result =
          await ref.read(apiProvider).request('GET', path.toString())
              as Map<String, dynamic>;
      return AnalyticsVisitorProfileHistoryPage.fromJson(result);
    });
