import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';

class AnalyticsOverview {
  const AnalyticsOverview({
    required this.pageViews,
    required this.uniqueVisitors,
    required this.sessions,
    required this.bounceRate,
    required this.averageSessionDurationMs,
  });
  final int pageViews;
  final int uniqueVisitors;
  final int sessions;
  final double bounceRate;
  final int averageSessionDurationMs;
  factory AnalyticsOverview.fromJson(Map<String, dynamic> json) =>
      AnalyticsOverview(
        pageViews: (json['pageViews'] as num?)?.toInt() ?? 0,
        uniqueVisitors: (json['uniqueVisitors'] as num?)?.toInt() ?? 0,
        sessions: (json['sessions'] as num?)?.toInt() ?? 0,
        bounceRate: (json['bounceRate'] as num?)?.toDouble() ?? 0,
        averageSessionDurationMs:
            (json['averageSessionDurationMs'] as num?)?.toInt() ?? 0,
      );
}

class AnalyticsDay {
  const AnalyticsDay(
    this.date,
    this.pageViews,
    this.uniqueVisitors,
    this.sessions,
  );
  final String date;
  final int pageViews;
  final int uniqueVisitors;
  final int sessions;
  factory AnalyticsDay.fromJson(Map<String, dynamic> json) => AnalyticsDay(
    json['date'] as String,
    (json['pageViews'] as num?)?.toInt() ?? 0,
    (json['uniqueVisitors'] as num?)?.toInt() ?? 0,
    (json['sessions'] as num?)?.toInt() ?? 0,
  );
}

class AnalyticsPage {
  const AnalyticsPage(this.path, this.pageViews);
  final String path;
  final int pageViews;
  factory AnalyticsPage.fromJson(Map<String, dynamic> json) => AnalyticsPage(
    json['path'] as String? ?? '/',
    (json['pageViews'] as num?)?.toInt() ?? 0,
  );
}

class AnalyticsTraffic {
  const AnalyticsTraffic(
    this.channel,
    this.sessions, {
    this.source,
    this.medium,
    this.campaign,
  });
  final String channel;
  final int sessions;
  final String? source;
  final String? medium;
  final String? campaign;
  factory AnalyticsTraffic.fromJson(Map<String, dynamic> json) =>
      AnalyticsTraffic(
        json['channel'] as String? ?? 'direct',
        (json['sessions'] as num?)?.toInt() ?? 0,
        source: json['source'] as String?,
        medium: json['medium'] as String?,
        campaign: json['campaign'] as String?,
      );
}

class AnalyticsEvent {
  const AnalyticsEvent(this.type, this.count);
  final String type;
  final int count;
  factory AnalyticsEvent.fromJson(Map<String, dynamic> json) => AnalyticsEvent(
    json['eventType'] as String? ?? 'event',
    (json['count'] as num?)?.toInt() ?? 0,
  );
}

class AnalyticsGoal {
  const AnalyticsGoal(this.name, this.count);
  final String name;
  final int count;
  factory AnalyticsGoal.fromJson(Map<String, dynamic> json) => AnalyticsGoal(
    json['name'] as String? ?? 'Unnamed goal',
    (json['count'] as num?)?.toInt() ?? 0,
  );
}

class VisitorOverview {
  const VisitorOverview(
    this.uniqueVisitors,
    this.sessions,
    this.newSessions,
    this.returningSessions,
    this.bounceRate,
    this.averageSessionDurationMs,
  );
  final int uniqueVisitors,
      sessions,
      newSessions,
      returningSessions,
      averageSessionDurationMs;
  final double bounceRate;
  factory VisitorOverview.fromJson(Map<String, dynamic> json) =>
      VisitorOverview(
        (json['uniqueVisitors'] as num?)?.toInt() ?? 0,
        (json['sessions'] as num?)?.toInt() ?? 0,
        (json['newSessions'] as num?)?.toInt() ?? 0,
        (json['returningSessions'] as num?)?.toInt() ?? 0,
        (json['bounceRate'] as num?)?.toDouble() ?? 0,
        (json['averageSessionDurationMs'] as num?)?.toInt() ?? 0,
      );
}

class AnalyticsDashboard {
  const AnalyticsDashboard(
    this.overview,
    this.trend,
    this.pages,
    this.traffic,
    this.visitors,
    this.events,
    this.goals,
  );
  final AnalyticsOverview overview;
  final List<AnalyticsDay> trend;
  final List<AnalyticsPage> pages;
  final List<AnalyticsTraffic> traffic;
  final VisitorOverview visitors;
  final List<AnalyticsEvent> events;
  final List<AnalyticsGoal> goals;
}

final analyticsDashboardProvider =
    FutureProvider.family<AnalyticsDashboard, String>((ref, siteId) async {
      return _loadDashboard(ref, siteId);
    });

class AnalyticsDateRange {
  const AnalyticsDateRange(this.from, this.to);

  final DateTime from;
  final DateTime to;

  String get fromQuery => _dateQuery(from);
  String get toQuery => _dateQuery(to);
}

class AnalyticsDashboardQuery {
  const AnalyticsDashboardQuery(this.siteId, this.range);

  final String siteId;
  final AnalyticsDateRange range;

  @override
  bool operator ==(Object other) =>
      other is AnalyticsDashboardQuery &&
      other.siteId == siteId &&
      other.range.fromQuery == range.fromQuery &&
      other.range.toQuery == range.toQuery;

  @override
  int get hashCode => Object.hash(siteId, range.fromQuery, range.toQuery);
}

final analyticsDashboardRangeProvider =
    FutureProvider.family<AnalyticsDashboard, AnalyticsDashboardQuery>(
      (ref, query) => _loadDashboard(ref, query.siteId, range: query.range),
    );

Future<AnalyticsDashboard> _loadDashboard(
  Ref ref,
  String siteId, {
  AnalyticsDateRange? range,
}) async {
  final api = ref.read(apiProvider);
  final base = '/api/v1/sites/$siteId/analytics';
  final period = range == null
      ? ''
      : '?from=${range.fromQuery}&to=${range.toQuery}';
  final responses = await Future.wait<dynamic>([
    api.request('GET', '$base/overview$period'),
    api.request('GET', '$base/timeseries$period'),
    api.request('GET', '$base/pages$period'),
    api.request('GET', '$base/traffic$period'),
    api.request('GET', '$base/visitors$period'),
    api.request('GET', '$base/events$period'),
    api.request('GET', '$base/goals$period'),
  ]);
  return AnalyticsDashboard(
    AnalyticsOverview.fromJson(responses[0] as Map<String, dynamic>),
    (responses[1] as List)
        .map((item) => AnalyticsDay.fromJson(item as Map<String, dynamic>))
        .toList(),
    (responses[2] as List)
        .map((item) => AnalyticsPage.fromJson(item as Map<String, dynamic>))
        .toList(),
    (responses[3] as List)
        .map((item) => AnalyticsTraffic.fromJson(item as Map<String, dynamic>))
        .toList(),
    VisitorOverview.fromJson(responses[4] as Map<String, dynamic>),
    (responses[5] as List)
        .map((item) => AnalyticsEvent.fromJson(item as Map<String, dynamic>))
        .toList(),
    (responses[6] as List)
        .map((item) => AnalyticsGoal.fromJson(item as Map<String, dynamic>))
        .toList(),
  );
}

String _dateQuery(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
