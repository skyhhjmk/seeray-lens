import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import 'analytics_controller.dart';

class AnalyticsInsightsQuery {
  const AnalyticsInsightsQuery(this.siteId, this.range, {this.segmentId});

  final String siteId;
  final AnalyticsDateRange range;
  final String? segmentId;

  @override
  bool operator ==(Object other) =>
      other is AnalyticsInsightsQuery &&
      other.siteId == siteId &&
      other.segmentId == segmentId &&
      other.range.fromQuery == range.fromQuery &&
      other.range.toQuery == range.toQuery;

  @override
  int get hashCode =>
      Object.hash(siteId, segmentId, range.fromQuery, range.toQuery);
}

class AnalyticsInsightMetric {
  const AnalyticsInsightMetric({
    required this.key,
    required this.label,
    required this.current,
    required this.previous,
    required this.delta,
    required this.percentChange,
  });

  final String key;
  final String label;
  final int current;
  final int previous;
  final int delta;
  final double? percentChange;

  factory AnalyticsInsightMetric.fromJson(Map<String, dynamic> json) =>
      AnalyticsInsightMetric(
        key: json['key'] as String? ?? '',
        label: json['label'] as String? ?? '',
        current: (json['current'] as num?)?.toInt() ?? 0,
        previous: (json['previous'] as num?)?.toInt() ?? 0,
        delta: (json['delta'] as num?)?.toInt() ?? 0,
        percentChange: (json['percentChange'] as num?)?.toDouble(),
      );
}

class AnalyticsInsightChange {
  const AnalyticsInsightChange({
    required this.category,
    required this.label,
    required this.detail,
    required this.metric,
    required this.current,
    required this.previous,
    required this.delta,
    required this.percentChange,
    required this.direction,
  });

  final String category;
  final String label;
  final String? detail;
  final String metric;
  final int current;
  final int previous;
  final int delta;
  final double? percentChange;
  final String direction;

  factory AnalyticsInsightChange.fromJson(Map<String, dynamic> json) =>
      AnalyticsInsightChange(
        category: json['category'] as String? ?? '',
        label: json['label'] as String? ?? '',
        detail: json['detail'] as String?,
        metric: json['metric'] as String? ?? '',
        current: (json['current'] as num?)?.toInt() ?? 0,
        previous: (json['previous'] as num?)?.toInt() ?? 0,
        delta: (json['delta'] as num?)?.toInt() ?? 0,
        percentChange: (json['percentChange'] as num?)?.toDouble(),
        direction: json['direction'] as String? ?? 'increase',
      );
}

class AnalyticsInsightsReport {
  const AnalyticsInsightsReport({
    required this.from,
    required this.to,
    required this.previousFrom,
    required this.previousTo,
    required this.metrics,
    required this.changes,
  });

  final String from;
  final String to;
  final String previousFrom;
  final String previousTo;
  final List<AnalyticsInsightMetric> metrics;
  final List<AnalyticsInsightChange> changes;

  factory AnalyticsInsightsReport.fromJson(
    Map<String, dynamic> json,
  ) => AnalyticsInsightsReport(
    from: json['from'] as String? ?? '',
    to: json['to'] as String? ?? '',
    previousFrom: json['previousFrom'] as String? ?? '',
    previousTo: json['previousTo'] as String? ?? '',
    metrics: (json['metrics'] as List? ?? const [])
        .whereType<Map>()
        .map(
          (item) =>
              AnalyticsInsightMetric.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList(growable: false),
    changes: (json['changes'] as List? ?? const [])
        .whereType<Map>()
        .map(
          (item) =>
              AnalyticsInsightChange.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList(growable: false),
  );
}

final analyticsInsightsProvider =
    FutureProvider.family<AnalyticsInsightsReport, AnalyticsInsightsQuery>((
      ref,
      query,
    ) async {
      final parameters = <String, String>{
        'from': query.range.fromQuery,
        'to': query.range.toQuery,
        if (query.segmentId != null) 'segmentId': query.segmentId!,
      };
      final path = Uri(
        path: '/api/v1/sites/${query.siteId}/analytics/insights',
        queryParameters: parameters,
      );
      final result = await ref
          .read(apiProvider)
          .request('GET', path.toString());
      if (result is! Map) {
        throw const FormatException('Invalid analytics insights response');
      }
      return AnalyticsInsightsReport.fromJson(
        Map<String, dynamic>.from(result),
      );
    });
