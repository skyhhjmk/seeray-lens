import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import 'analytics_controller.dart';

class AnalyticsUserFlowSamplesQuery {
  const AnalyticsUserFlowSamplesQuery({
    required this.dashboard,
    required this.edge,
    this.cursor,
  });

  final AnalyticsDashboardQuery dashboard;
  final AnalyticsUserFlowEdge edge;
  final String? cursor;

  AnalyticsUserFlowSamplesQuery withCursor(String cursor) =>
      AnalyticsUserFlowSamplesQuery(
        dashboard: dashboard,
        edge: edge,
        cursor: cursor,
      );

  @override
  bool operator ==(Object other) =>
      other is AnalyticsUserFlowSamplesQuery &&
      other.dashboard == dashboard &&
      other.edge.step == edge.step &&
      other.edge.sourcePath == edge.sourcePath &&
      other.edge.sourceTitle == edge.sourceTitle &&
      other.edge.targetPath == edge.targetPath &&
      other.edge.targetTitle == edge.targetTitle &&
      other.cursor == cursor;

  @override
  int get hashCode => Object.hash(
    dashboard,
    edge.step,
    edge.sourcePath,
    edge.sourceTitle,
    edge.targetPath,
    edge.targetTitle,
    cursor,
  );
}

class AnalyticsUserFlowSamplePage {
  const AnalyticsUserFlowSamplePage({
    required this.step,
    required this.at,
    required this.path,
    this.title,
  });

  final int step;
  final DateTime at;
  final String path;
  final String? title;

  factory AnalyticsUserFlowSamplePage.fromJson(Map<String, dynamic> json) =>
      AnalyticsUserFlowSamplePage(
        step: (json['step'] as num?)?.toInt() ?? 0,
        at: DateTime.parse(json['at'] as String).toLocal(),
        path: json['path'] as String? ?? '/',
        title: json['title'] as String?,
      );
}

class AnalyticsUserFlowSampleSession {
  const AnalyticsUserFlowSampleSession({
    required this.startedAt,
    required this.lastActivityAt,
    required this.pages,
  });

  final DateTime startedAt;
  final DateTime lastActivityAt;
  final List<AnalyticsUserFlowSamplePage> pages;

  factory AnalyticsUserFlowSampleSession.fromJson(Map<String, dynamic> json) =>
      AnalyticsUserFlowSampleSession(
        startedAt: DateTime.parse(json['startedAt'] as String).toLocal(),
        lastActivityAt: DateTime.parse(
          json['lastActivityAt'] as String,
        ).toLocal(),
        pages: (json['pages'] as List? ?? const [])
            .whereType<Map>()
            .map(
              (page) => AnalyticsUserFlowSamplePage.fromJson(
                Map<String, dynamic>.from(page),
              ),
            )
            .toList(growable: false),
      );
}

class AnalyticsUserFlowSamples {
  const AnalyticsUserFlowSamples({
    required this.totalSessions,
    required this.hasMore,
    required this.nextCursor,
    required this.sessions,
  });

  final int totalSessions;
  final bool hasMore;
  final String? nextCursor;
  final List<AnalyticsUserFlowSampleSession> sessions;

  factory AnalyticsUserFlowSamples.fromJson(Map<String, dynamic> json) =>
      AnalyticsUserFlowSamples(
        totalSessions: (json['totalSessions'] as num?)?.toInt() ?? 0,
        hasMore: json['hasMore'] as bool? ?? false,
        nextCursor: json['nextCursor'] as String?,
        sessions: (json['sessions'] as List? ?? const [])
            .whereType<Map>()
            .map(
              (session) => AnalyticsUserFlowSampleSession.fromJson(
                Map<String, dynamic>.from(session),
              ),
            )
            .toList(growable: false),
      );
}

final analyticsUserFlowSamplesProvider =
    FutureProvider.family<
      AnalyticsUserFlowSamples,
      AnalyticsUserFlowSamplesQuery
    >((ref, query) async {
      final edge = query.edge;
      final parameters = <String, String>{
        'from': query.dashboard.range.fromQuery,
        'to': query.dashboard.range.toQuery,
        'step': '${edge.step}',
        'sourcePath': edge.sourcePath,
        'exit': '${edge.targetPath == null}',
        if (query.cursor != null) 'cursor': query.cursor!,
        if (query.dashboard.segmentId != null)
          'segmentId': query.dashboard.segmentId!,
        if (edge.sourceTitle != null) 'sourceTitle': edge.sourceTitle!,
        if (edge.targetPath != null) 'targetPath': edge.targetPath!,
        if (edge.targetTitle != null) 'targetTitle': edge.targetTitle!,
      };
      final path = Uri(
        path:
            '/api/v1/sites/${query.dashboard.siteId}/analytics/user-flow/samples',
        queryParameters: parameters,
      );
      final result = await ref
          .read(apiProvider)
          .request('GET', path.toString());
      return AnalyticsUserFlowSamples.fromJson(
        Map<String, dynamic>.from(result as Map),
      );
    });
