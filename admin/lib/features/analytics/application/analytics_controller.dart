import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import 'custom_report_formula.dart';

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

class AnalyticsPageTitle {
  const AnalyticsPageTitle(this.path, this.title, this.pageViews);

  final String path;
  final String? title;
  final int pageViews;

  factory AnalyticsPageTitle.fromJson(Map<String, dynamic> json) =>
      AnalyticsPageTitle(
        json['path'] as String? ?? '/',
        json['title'] as String?,
        (json['pageViews'] as num?)?.toInt() ?? 0,
      );
}

class AnalyticsPageFlow {
  const AnalyticsPageFlow(this.flow, this.path, this.title, this.sessions);

  final String flow;
  final String path;
  final String? title;
  final int sessions;

  factory AnalyticsPageFlow.fromJson(Map<String, dynamic> json) =>
      AnalyticsPageFlow(
        json['flow'] as String? ?? '',
        json['path'] as String? ?? '/',
        json['title'] as String?,
        (json['sessions'] as num?)?.toInt() ?? 0,
      );
}

class AnalyticsUserFlowEdge {
  const AnalyticsUserFlowEdge({
    required this.step,
    required this.sourcePath,
    required this.targetPath,
    required this.sessions,
    this.sourceTitle,
    this.targetTitle,
  });

  final int step;
  final String sourcePath;
  final String? sourceTitle;
  final String? targetPath;
  final String? targetTitle;
  final int sessions;

  factory AnalyticsUserFlowEdge.fromJson(Map<String, dynamic> json) =>
      AnalyticsUserFlowEdge(
        step: (json['step'] as num?)?.toInt() ?? 1,
        sourcePath: json['sourcePath'] as String? ?? '/',
        sourceTitle: json['sourceTitle'] as String?,
        targetPath: json['targetPath'] as String?,
        targetTitle: json['targetTitle'] as String?,
        sessions: (json['sessions'] as num?)?.toInt() ?? 0,
      );
}

class AnalyticsCohortCell {
  const AnalyticsCohortCell({
    required this.cohortWeek,
    required this.weekIndex,
    required this.cohortSize,
    required this.retainedVisitors,
    required this.retentionRate,
    required this.complete,
  });

  final String cohortWeek;
  final int weekIndex;
  final int cohortSize;
  final int retainedVisitors;
  final double retentionRate;
  final bool complete;

  factory AnalyticsCohortCell.fromJson(Map<String, dynamic> json) =>
      AnalyticsCohortCell(
        cohortWeek: json['cohortWeek'] as String? ?? '',
        weekIndex: (json['weekIndex'] as num?)?.toInt() ?? 0,
        cohortSize: (json['cohortSize'] as num?)?.toInt() ?? 0,
        retainedVisitors: (json['retainedVisitors'] as num?)?.toInt() ?? 0,
        retentionRate: (json['retentionRate'] as num?)?.toDouble() ?? 0,
        complete: json['complete'] as bool? ?? false,
      );
}

class AnalyticsCohortQuery {
  const AnalyticsCohortQuery({
    required this.siteId,
    required this.range,
    required this.weeks,
    this.segmentId,
  });

  final String siteId;
  final AnalyticsDateRange range;
  final String? segmentId;
  final int weeks;

  @override
  bool operator ==(Object other) =>
      other is AnalyticsCohortQuery &&
      other.siteId == siteId &&
      other.segmentId == segmentId &&
      other.weeks == weeks &&
      other.range.fromQuery == range.fromQuery &&
      other.range.toQuery == range.toQuery;

  @override
  int get hashCode =>
      Object.hash(siteId, segmentId, weeks, range.fromQuery, range.toQuery);
}

class AnalyticsSiteSearchTerm {
  const AnalyticsSiteSearchTerm({
    required this.keyword,
    required this.searches,
    required this.uniqueVisitors,
    required this.sessions,
    required this.zeroResultSearches,
    required this.measuredResultSearches,
    this.category,
    this.averageResultsCount,
  });

  final String keyword;
  final String? category;
  final int searches;
  final int uniqueVisitors;
  final int sessions;
  final int zeroResultSearches;
  final int measuredResultSearches;
  final double? averageResultsCount;

  factory AnalyticsSiteSearchTerm.fromJson(Map<String, dynamic> json) =>
      AnalyticsSiteSearchTerm(
        keyword: json['keyword'] as String? ?? '',
        category: json['category'] as String?,
        searches: (json['searches'] as num?)?.toInt() ?? 0,
        uniqueVisitors: (json['uniqueVisitors'] as num?)?.toInt() ?? 0,
        sessions: (json['sessions'] as num?)?.toInt() ?? 0,
        zeroResultSearches: (json['zeroResultSearches'] as num?)?.toInt() ?? 0,
        measuredResultSearches:
            (json['measuredResultSearches'] as num?)?.toInt() ?? 0,
        averageResultsCount: (json['averageResultsCount'] as num?)?.toDouble(),
      );
}

class AnalyticsSiteSearchReport {
  const AnalyticsSiteSearchReport({
    required this.searches,
    required this.uniqueVisitors,
    required this.sessions,
    required this.zeroResultSearches,
    required this.measuredResultSearches,
    required this.terms,
    this.averageResultsCount,
  });

  final int searches;
  final int uniqueVisitors;
  final int sessions;
  final int zeroResultSearches;
  final int measuredResultSearches;
  final double? averageResultsCount;
  final List<AnalyticsSiteSearchTerm> terms;

  factory AnalyticsSiteSearchReport.fromJson(
    Map<String, dynamic> json,
  ) => AnalyticsSiteSearchReport(
    searches: (json['searches'] as num?)?.toInt() ?? 0,
    uniqueVisitors: (json['uniqueVisitors'] as num?)?.toInt() ?? 0,
    sessions: (json['sessions'] as num?)?.toInt() ?? 0,
    zeroResultSearches: (json['zeroResultSearches'] as num?)?.toInt() ?? 0,
    measuredResultSearches:
        (json['measuredResultSearches'] as num?)?.toInt() ?? 0,
    averageResultsCount: (json['averageResultsCount'] as num?)?.toDouble(),
    terms: (json['terms'] as List? ?? const [])
        .whereType<Map>()
        .map(
          (item) =>
              AnalyticsSiteSearchTerm.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList(growable: false),
  );
}

class AnalyticsContentEntry {
  const AnalyticsContentEntry({
    required this.name,
    required this.impressions,
    required this.interactions,
    required this.uniqueVisitors,
    required this.sessions,
    required this.interactionRate,
    this.piece,
    this.target,
  });

  final String name;
  final String? piece;
  final String? target;
  final int impressions;
  final int interactions;
  final int uniqueVisitors;
  final int sessions;
  final double interactionRate;

  factory AnalyticsContentEntry.fromJson(Map<String, dynamic> json) =>
      AnalyticsContentEntry(
        name: json['name'] as String? ?? '',
        piece: json['piece'] as String?,
        target: json['target'] as String?,
        impressions: (json['impressions'] as num?)?.toInt() ?? 0,
        interactions: (json['interactions'] as num?)?.toInt() ?? 0,
        uniqueVisitors: (json['uniqueVisitors'] as num?)?.toInt() ?? 0,
        sessions: (json['sessions'] as num?)?.toInt() ?? 0,
        interactionRate: (json['interactionRate'] as num?)?.toDouble() ?? 0,
      );
}

class AnalyticsContentReport {
  const AnalyticsContentReport({
    required this.impressions,
    required this.interactions,
    required this.uniqueVisitors,
    required this.sessions,
    required this.interactionRate,
    required this.entries,
  });

  final int impressions;
  final int interactions;
  final int uniqueVisitors;
  final int sessions;
  final double interactionRate;
  final List<AnalyticsContentEntry> entries;

  factory AnalyticsContentReport.fromJson(
    Map<String, dynamic> json,
  ) => AnalyticsContentReport(
    impressions: (json['impressions'] as num?)?.toInt() ?? 0,
    interactions: (json['interactions'] as num?)?.toInt() ?? 0,
    uniqueVisitors: (json['uniqueVisitors'] as num?)?.toInt() ?? 0,
    sessions: (json['sessions'] as num?)?.toInt() ?? 0,
    interactionRate: (json['interactionRate'] as num?)?.toDouble() ?? 0,
    entries: (json['entries'] as List? ?? const [])
        .whereType<Map>()
        .map(
          (item) =>
              AnalyticsContentEntry.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList(growable: false),
  );
}

class AnalyticsWebVitalSummary {
  const AnalyticsWebVitalSummary({
    required this.metric,
    required this.samples,
    required this.uniqueVisitors,
    required this.sessions,
    required this.p75,
    required this.good,
    required this.needsImprovement,
    required this.poor,
  });

  final String metric;
  final int samples;
  final int uniqueVisitors;
  final int sessions;
  final double p75;
  final int good;
  final int needsImprovement;
  final int poor;

  factory AnalyticsWebVitalSummary.fromJson(Map<String, dynamic> json) =>
      AnalyticsWebVitalSummary(
        metric: json['metric'] as String? ?? '',
        samples: (json['samples'] as num?)?.toInt() ?? 0,
        uniqueVisitors: (json['uniqueVisitors'] as num?)?.toInt() ?? 0,
        sessions: (json['sessions'] as num?)?.toInt() ?? 0,
        p75: (json['p75'] as num?)?.toDouble() ?? 0,
        good: (json['good'] as num?)?.toInt() ?? 0,
        needsImprovement: (json['needsImprovement'] as num?)?.toInt() ?? 0,
        poor: (json['poor'] as num?)?.toInt() ?? 0,
      );
}

class AnalyticsWebVitalPage {
  const AnalyticsWebVitalPage({
    required this.metric,
    required this.pagePath,
    required this.samples,
    required this.uniqueVisitors,
    required this.sessions,
    required this.p75,
    required this.good,
    required this.needsImprovement,
    required this.poor,
  });

  final String metric;
  final String? pagePath;
  final int samples;
  final int uniqueVisitors;
  final int sessions;
  final double p75;
  final int good;
  final int needsImprovement;
  final int poor;

  factory AnalyticsWebVitalPage.fromJson(Map<String, dynamic> json) =>
      AnalyticsWebVitalPage(
        metric: json['metric'] as String? ?? '',
        pagePath: json['pagePath'] as String?,
        samples: (json['samples'] as num?)?.toInt() ?? 0,
        uniqueVisitors: (json['uniqueVisitors'] as num?)?.toInt() ?? 0,
        sessions: (json['sessions'] as num?)?.toInt() ?? 0,
        p75: (json['p75'] as num?)?.toDouble() ?? 0,
        good: (json['good'] as num?)?.toInt() ?? 0,
        needsImprovement: (json['needsImprovement'] as num?)?.toInt() ?? 0,
        poor: (json['poor'] as num?)?.toInt() ?? 0,
      );
}

class AnalyticsWebVitalsReport {
  const AnalyticsWebVitalsReport({required this.metrics, required this.pages});

  final List<AnalyticsWebVitalSummary> metrics;
  final List<AnalyticsWebVitalPage> pages;

  factory AnalyticsWebVitalsReport.fromJson(
    Map<String, dynamic> json,
  ) => AnalyticsWebVitalsReport(
    metrics: (json['metrics'] as List? ?? const [])
        .whereType<Map>()
        .map(
          (item) => AnalyticsWebVitalSummary.fromJson(
            Map<String, dynamic>.from(item),
          ),
        )
        .toList(growable: false),
    pages: (json['pages'] as List? ?? const [])
        .whereType<Map>()
        .map(
          (item) =>
              AnalyticsWebVitalPage.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList(growable: false),
  );
}

final analyticsCohortProvider =
    FutureProvider.family<List<AnalyticsCohortCell>, AnalyticsCohortQuery>((
      ref,
      query,
    ) async {
      final parameters = <String, String>{
        'from': query.range.fromQuery,
        'to': query.range.toQuery,
        'weeks': '${query.weeks}',
        if (query.segmentId != null) 'segmentId': query.segmentId!,
      };
      final path = Uri(
        path: '/api/v1/sites/${query.siteId}/analytics/cohorts',
        queryParameters: parameters,
      );
      final response =
          await ref.read(apiProvider).request('GET', path.toString()) as List;
      return response
          .whereType<Map>()
          .map(
            (item) =>
                AnalyticsCohortCell.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList(growable: false);
    });

class AnalyticsBehaviourData {
  const AnalyticsBehaviourData(
    this.pages,
    this.flows,
    this.events,
    this.userFlow,
    this.siteSearch,
    this.content,
    this.webVitals,
  );

  final List<AnalyticsPageTitle> pages;
  final List<AnalyticsPageFlow> flows;
  final List<AnalyticsEvent> events;
  final List<AnalyticsUserFlowEdge> userFlow;
  final AnalyticsSiteSearchReport siteSearch;
  final AnalyticsContentReport content;
  final AnalyticsWebVitalsReport webVitals;
}

final analyticsBehaviourProvider =
    FutureProvider.family<AnalyticsBehaviourData, AnalyticsDashboardQuery>((
      ref,
      query,
    ) async {
      final parameters = <String, String>{
        'from': query.range.fromQuery,
        'to': query.range.toQuery,
        if (query.segmentId != null) 'segmentId': query.segmentId!,
      };
      final suffix = '?${Uri(queryParameters: parameters).query}';
      final base = '/api/v1/sites/${query.siteId}/analytics';
      final responses = await Future.wait<dynamic>([
        ref.read(apiProvider).request('GET', '$base/page-titles$suffix'),
        ref.read(apiProvider).request('GET', '$base/entry-exit$suffix'),
        ref.read(apiProvider).request('GET', '$base/events$suffix'),
        ref.read(apiProvider).request('GET', '$base/user-flow$suffix'),
        ref.read(apiProvider).request('GET', '$base/site-search$suffix'),
        ref.read(apiProvider).request('GET', '$base/content$suffix'),
        ref.read(apiProvider).request('GET', '$base/web-vitals$suffix'),
      ]);
      return AnalyticsBehaviourData(
        (responses[0] as List)
            .map(
              (item) =>
                  AnalyticsPageTitle.fromJson(item as Map<String, dynamic>),
            )
            .toList(growable: false),
        (responses[1] as List)
            .map(
              (item) =>
                  AnalyticsPageFlow.fromJson(item as Map<String, dynamic>),
            )
            .toList(growable: false),
        (responses[2] as List)
            .map(
              (item) => AnalyticsEvent.fromJson(item as Map<String, dynamic>),
            )
            .toList(growable: false),
        (responses[3] as List)
            .map(
              (item) => AnalyticsUserFlowEdge.fromJson(
                Map<String, dynamic>.from(item as Map),
              ),
            )
            .toList(growable: false),
        AnalyticsSiteSearchReport.fromJson(
          Map<String, dynamic>.from(responses[4] as Map),
        ),
        AnalyticsContentReport.fromJson(
          Map<String, dynamic>.from(responses[5] as Map),
        ),
        AnalyticsWebVitalsReport.fromJson(
          Map<String, dynamic>.from(responses[6] as Map),
        ),
      );
    });

class AnalyticsTraffic {
  const AnalyticsTraffic(
    this.channel,
    this.sessions, {
    this.source,
    this.medium,
    this.campaign,
    this.term,
    this.content,
  });
  final String channel;
  final int sessions;
  final String? source;
  final String? medium;
  final String? campaign;
  final String? term;
  final String? content;
  factory AnalyticsTraffic.fromJson(Map<String, dynamic> json) =>
      AnalyticsTraffic(
        json['channel'] as String? ?? 'direct',
        (json['sessions'] as num?)?.toInt() ?? 0,
        source: json['source'] as String?,
        medium: json['medium'] as String?,
        campaign: json['campaign'] as String?,
        term: json['term'] as String?,
        content: json['content'] as String?,
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
  const AnalyticsGoal(
    this.name,
    this.count, {
    this.convertedSessions = 0,
    this.value = 0,
    this.conversionRate = 0,
  });

  final String name;
  final int count;
  final int convertedSessions;
  final double value;
  final double conversionRate;

  factory AnalyticsGoal.fromJson(Map<String, dynamic> json) => AnalyticsGoal(
    json['name'] as String? ?? 'Unnamed goal',
    (json['count'] as num?)?.toInt() ?? 0,
    convertedSessions: (json['convertedSessions'] as num?)?.toInt() ?? 0,
    value: (json['value'] as num?)?.toDouble() ?? 0,
    conversionRate: (json['conversionRate'] as num?)?.toDouble() ?? 0,
  );
}

class AnalyticsTechnology {
  const AnalyticsTechnology({
    required this.dimension,
    required this.value,
    required this.sessions,
    required this.visitors,
  });

  final String dimension;
  final String value;
  final int sessions;
  final int visitors;

  factory AnalyticsTechnology.fromJson(Map<String, dynamic> json) =>
      AnalyticsTechnology(
        dimension: json['dimension'] as String? ?? '',
        value: json['value'] as String? ?? 'Unknown',
        sessions: (json['sessions'] as num?)?.toInt() ?? 0,
        visitors: (json['visitors'] as num?)?.toInt() ?? 0,
      );
}

final analyticsTechnologyProvider =
    FutureProvider.family<List<AnalyticsTechnology>, AnalyticsDashboardQuery>((
      ref,
      query,
    ) async {
      final parameters = <String, String>{
        'from': query.range.fromQuery,
        'to': query.range.toQuery,
        if (query.segmentId != null) 'segmentId': query.segmentId!,
      };
      final path = Uri(
        path: '/api/v1/sites/${query.siteId}/analytics/technology',
        queryParameters: parameters,
      );
      final result =
          await ref.read(apiProvider).request('GET', path.toString()) as List;
      return result
          .whereType<Map>()
          .map(
            (item) =>
                AnalyticsTechnology.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList(growable: false);
    });

class AnalyticsLocation {
  const AnalyticsLocation({
    required this.level,
    required this.label,
    required this.countryCode,
    required this.continentCode,
    required this.regionCode,
    required this.region,
    required this.city,
    required this.timezone,
    required this.sessions,
    required this.visitors,
  });

  final String level;
  final String label;
  final String? countryCode;
  final String? continentCode;
  final String? regionCode;
  final String? region;
  final String? city;
  final String? timezone;
  final int sessions;
  final int visitors;

  factory AnalyticsLocation.fromJson(Map<String, dynamic> json) =>
      AnalyticsLocation(
        level: json['level'] as String? ?? '',
        label: json['label'] as String? ?? 'Unknown',
        countryCode: json['countryCode'] as String?,
        continentCode: json['continentCode'] as String?,
        regionCode: json['regionCode'] as String?,
        region: json['region'] as String?,
        city: json['city'] as String?,
        timezone: json['timezone'] as String?,
        sessions: (json['sessions'] as num?)?.toInt() ?? 0,
        visitors: (json['visitors'] as num?)?.toInt() ?? 0,
      );
}

class AnalyticsLocationReport {
  const AnalyticsLocationReport({
    required this.sourceConfigured,
    required this.rows,
  });

  final bool sourceConfigured;
  final List<AnalyticsLocation> rows;

  factory AnalyticsLocationReport.fromJson(Map<String, dynamic> json) =>
      AnalyticsLocationReport(
        sourceConfigured: json['sourceConfigured'] as bool? ?? false,
        rows: (json['rows'] as List? ?? const [])
            .whereType<Map>()
            .map(
              (item) =>
                  AnalyticsLocation.fromJson(Map<String, dynamic>.from(item)),
            )
            .toList(growable: false),
      );
}

final analyticsLocationProvider =
    FutureProvider.family<AnalyticsLocationReport, AnalyticsDashboardQuery>((
      ref,
      query,
    ) async {
      final parameters = <String, String>{
        'from': query.range.fromQuery,
        'to': query.range.toQuery,
        if (query.segmentId != null) 'segmentId': query.segmentId!,
      };
      final path = Uri(
        path: '/api/v1/sites/${query.siteId}/analytics/locations',
        queryParameters: parameters,
      );
      final result =
          await ref.read(apiProvider).request('GET', path.toString())
              as Map<String, dynamic>;
      return AnalyticsLocationReport.fromJson(result);
    });

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
  const AnalyticsDashboardQuery(this.siteId, this.range, {this.segmentId});

  final String siteId;
  final AnalyticsDateRange range;
  final String? segmentId;

  @override
  bool operator ==(Object other) =>
      other is AnalyticsDashboardQuery &&
      other.siteId == siteId &&
      other.segmentId == segmentId &&
      other.range.fromQuery == range.fromQuery &&
      other.range.toQuery == range.toQuery;

  @override
  int get hashCode =>
      Object.hash(siteId, segmentId, range.fromQuery, range.toQuery);
}

final analyticsGoalsProvider =
    FutureProvider.family<List<AnalyticsGoal>, AnalyticsDashboardQuery>((
      ref,
      query,
    ) async {
      final parameters = <String, String>{
        'from': query.range.fromQuery,
        'to': query.range.toQuery,
        if (query.segmentId != null) 'segmentId': query.segmentId!,
      };
      final path = Uri(
        path: '/api/v1/sites/${query.siteId}/analytics/goals',
        queryParameters: parameters,
      );
      final result =
          await ref.read(apiProvider).request('GET', path.toString()) as List;
      return result
          .whereType<Map>()
          .map(
            (item) => AnalyticsGoal.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList(growable: false);
    });

class AnalyticsGoalsComparisonQuery {
  const AnalyticsGoalsComparisonQuery({
    required this.first,
    required this.second,
  });

  final AnalyticsDashboardQuery first;
  final AnalyticsDashboardQuery second;

  @override
  bool operator ==(Object other) =>
      other is AnalyticsGoalsComparisonQuery &&
      other.first == first &&
      other.second == second;

  @override
  int get hashCode => Object.hash(first, second);
}

class AnalyticsGoalsComparison {
  const AnalyticsGoalsComparison({required this.first, required this.second});

  final List<AnalyticsGoal> first;
  final List<AnalyticsGoal> second;
}

final analyticsGoalsComparisonProvider =
    FutureProvider.family<
      AnalyticsGoalsComparison,
      AnalyticsGoalsComparisonQuery
    >((ref, query) async {
      final reports = await Future.wait([
        ref.watch(analyticsGoalsProvider(query.first).future),
        ref.watch(analyticsGoalsProvider(query.second).future),
      ]);
      return AnalyticsGoalsComparison(first: reports[0], second: reports[1]);
    });

class CustomReportRow {
  const CustomReportRow(
    this.dimensionValue,
    this.metricValue, {
    this.secondaryDimensionValue,
    this.tertiaryDimensionValue,
  });
  final String dimensionValue;
  final double metricValue;
  final String? secondaryDimensionValue;
  final String? tertiaryDimensionValue;

  factory CustomReportRow.fromJson(Map<String, dynamic> json) =>
      CustomReportRow(
        json['dimensionValue'] as String? ?? 'Unknown',
        (json['metricValue'] as num?)?.toDouble() ?? 0,
        secondaryDimensionValue: json['secondaryDimensionValue'] as String?,
        tertiaryDimensionValue: json['tertiaryDimensionValue'] as String?,
      );
}

class CustomReportData {
  const CustomReportData(
    this.rows, {
    this.customDimensionName,
    this.secondaryDimension,
    this.tertiaryDimension,
    this.secondaryCustomDimensionName,
    this.tertiaryCustomDimensionName,
    this.formulaName,
  });
  final List<CustomReportRow> rows;
  final String? customDimensionName;
  final String? secondaryDimension;
  final String? tertiaryDimension;
  final String? secondaryCustomDimensionName;
  final String? tertiaryCustomDimensionName;
  final String? formulaName;
}

class AnalyticsCustomDimensionDefinition {
  const AnalyticsCustomDimensionDefinition({
    required this.id,
    required this.key,
    required this.name,
    required this.enabled,
  });

  final String id;
  final String key;
  final String name;
  final bool enabled;

  factory AnalyticsCustomDimensionDefinition.fromJson(
    Map<String, dynamic> json,
  ) => AnalyticsCustomDimensionDefinition(
    id: json['id'] as String? ?? '',
    key: json['key'] as String? ?? '',
    name: json['name'] as String? ?? '',
    enabled: json['enabled'] as bool? ?? false,
  );
}

final analyticsCustomDimensionDefinitionsProvider =
    FutureProvider.family<List<AnalyticsCustomDimensionDefinition>, String>((
      ref,
      siteId,
    ) async {
      final response =
          await ref
                  .read(apiProvider)
                  .request('GET', '/api/v1/sites/$siteId/custom-dimensions')
              as List;
      return response
          .whereType<Map>()
          .map(
            (item) => AnalyticsCustomDimensionDefinition.fromJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .where(
            (item) => item.enabled && item.id.isNotEmpty && item.key.isNotEmpty,
          )
          .toList(growable: false);
    });

class CustomReportQuery {
  const CustomReportQuery({
    required this.siteId,
    required this.range,
    required this.dimension,
    this.secondaryDimension,
    this.tertiaryDimension,
    required this.metric,
    required this.limit,
    required this.matchMode,
    required this.filters,
    this.segmentId,
    this.formula,
  });

  final String siteId;
  final AnalyticsDateRange range;
  final String dimension;
  final String? secondaryDimension;
  final String? tertiaryDimension;
  final String metric;
  final int limit;
  final String matchMode;
  final List<Map<String, Object?>> filters;
  final String? segmentId;
  final CustomReportFormula? formula;

  String get _filterKey => jsonEncode(filters);
  String get _formulaKey => jsonEncode(formula?.toJson());

  @override
  bool operator ==(Object other) =>
      other is CustomReportQuery &&
      other.siteId == siteId &&
      other.range.fromQuery == range.fromQuery &&
      other.range.toQuery == range.toQuery &&
      other.dimension == dimension &&
      other.secondaryDimension == secondaryDimension &&
      other.tertiaryDimension == tertiaryDimension &&
      other.metric == metric &&
      other._formulaKey == _formulaKey &&
      other.limit == limit &&
      other.matchMode == matchMode &&
      other.segmentId == segmentId &&
      other._filterKey == _filterKey;

  @override
  int get hashCode => Object.hash(
    siteId,
    range.fromQuery,
    range.toQuery,
    dimension,
    secondaryDimension,
    tertiaryDimension,
    metric,
    _formulaKey,
    limit,
    matchMode,
    segmentId,
    _filterKey,
  );
}

final customReportProvider =
    FutureProvider.family<CustomReportData, CustomReportQuery>((
      ref,
      query,
    ) async {
      final parameters = <String, String>{
        'from': query.range.fromQuery,
        'to': query.range.toQuery,
        if (query.segmentId != null) 'segmentId': query.segmentId!,
      };
      final path = Uri(
        path: '/api/v1/sites/${query.siteId}/analytics/custom-report/query',
        queryParameters: parameters,
      );
      final result =
          await ref
                  .read(apiProvider)
                  .request(
                    'POST',
                    path.toString(),
                    body: {
                      'dimension': query.dimension,
                      if (query.secondaryDimension != null)
                        'secondaryDimension': query.secondaryDimension,
                      if (query.tertiaryDimension != null)
                        'tertiaryDimension': query.tertiaryDimension,
                      'metric': query.metric,
                      if (query.formula != null)
                        'formula': query.formula!.toJson(),
                      'limit': query.limit,
                      'matchMode': query.matchMode,
                      'filters': query.filters,
                    },
                  )
              as Map<String, dynamic>;
      return CustomReportData(
        (result['rows'] as List? ?? const [])
            .whereType<Map>()
            .map(
              (item) =>
                  CustomReportRow.fromJson(Map<String, dynamic>.from(item)),
            )
            .toList(growable: false),
        customDimensionName: result['customDimensionName'] as String?,
        secondaryDimension: result['secondaryDimension'] as String?,
        tertiaryDimension: result['tertiaryDimension'] as String?,
        secondaryCustomDimensionName:
            result['secondaryCustomDimensionName'] as String?,
        tertiaryCustomDimensionName:
            result['tertiaryCustomDimensionName'] as String?,
        formulaName: result['formulaName'] as String?,
      );
    });

final analyticsDashboardRangeProvider =
    FutureProvider.family<AnalyticsDashboard, AnalyticsDashboardQuery>(
      (ref, query) => _loadDashboard(
        ref,
        query.siteId,
        range: query.range,
        segmentId: query.segmentId,
      ),
    );

Future<AnalyticsDashboard> _loadDashboard(
  Ref ref,
  String siteId, {
  AnalyticsDateRange? range,
  String? segmentId,
}) async {
  final api = ref.read(apiProvider);
  final base = '/api/v1/sites/$siteId/analytics';
  final parameters = <String, String>{
    if (range case final dateRange?) 'from': dateRange.fromQuery,
    if (range case final dateRange?) 'to': dateRange.toQuery,
    ...?(segmentId == null ? null : {'segmentId': segmentId}),
  };
  final period = parameters.isEmpty
      ? ''
      : '?${Uri(queryParameters: parameters).query}';
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
