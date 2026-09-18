import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import 'analytics_controller.dart';

class FormAnalyticsQuery {
  const FormAnalyticsQuery({
    required this.siteId,
    required this.range,
    this.segmentId,
  });

  final String siteId;
  final AnalyticsDateRange range;
  final String? segmentId;

  @override
  bool operator ==(Object other) =>
      other is FormAnalyticsQuery &&
      other.siteId == siteId &&
      other.segmentId == segmentId &&
      other.range.fromQuery == range.fromQuery &&
      other.range.toQuery == range.toQuery;

  @override
  int get hashCode =>
      Object.hash(siteId, segmentId, range.fromQuery, range.toQuery);
}

class FormAnalyticsRow {
  const FormAnalyticsRow({
    required this.formId,
    required this.pagePath,
    required this.views,
    required this.starts,
    required this.fieldInteractions,
    required this.validationErrors,
    required this.submits,
    required this.successes,
    required this.failures,
    required this.abandonments,
    required this.uniqueVisitors,
    required this.averageFieldTimeMs,
    required this.conversionRate,
  });

  final String formId;
  final String pagePath;
  final int views;
  final int starts;
  final int fieldInteractions;
  final int validationErrors;
  final int submits;
  final int successes;
  final int failures;
  final int abandonments;
  final int uniqueVisitors;
  final int averageFieldTimeMs;
  final double conversionRate;

  factory FormAnalyticsRow.fromJson(Map<String, dynamic> json) =>
      FormAnalyticsRow(
        formId: json['formId'] as String? ?? '',
        pagePath: json['pagePath'] as String? ?? '/',
        views: (json['views'] as num?)?.toInt() ?? 0,
        starts: (json['starts'] as num?)?.toInt() ?? 0,
        fieldInteractions: (json['fieldInteractions'] as num?)?.toInt() ?? 0,
        validationErrors: (json['validationErrors'] as num?)?.toInt() ?? 0,
        submits: (json['submits'] as num?)?.toInt() ?? 0,
        successes: (json['successes'] as num?)?.toInt() ?? 0,
        failures: (json['failures'] as num?)?.toInt() ?? 0,
        abandonments: (json['abandonments'] as num?)?.toInt() ?? 0,
        uniqueVisitors: (json['uniqueVisitors'] as num?)?.toInt() ?? 0,
        averageFieldTimeMs: (json['averageFieldTimeMs'] as num?)?.toInt() ?? 0,
        conversionRate: (json['conversionRate'] as num?)?.toDouble() ?? 0,
      );
}

class FormAnalyticsReport {
  const FormAnalyticsReport({
    required this.from,
    required this.to,
    required this.rows,
    required this.hasMore,
  });

  final String from;
  final String to;
  final List<FormAnalyticsRow> rows;
  final bool hasMore;

  factory FormAnalyticsReport.fromJson(Map<String, dynamic> json) =>
      FormAnalyticsReport(
        from: json['from'] as String? ?? '',
        to: json['to'] as String? ?? '',
        rows: (json['rows'] as List? ?? const [])
            .whereType<Map>()
            .map(
              (item) =>
                  FormAnalyticsRow.fromJson(Map<String, dynamic>.from(item)),
            )
            .toList(growable: false),
        hasMore: json['hasMore'] as bool? ?? false,
      );
}

final formAnalyticsProvider =
    FutureProvider.family<FormAnalyticsReport, FormAnalyticsQuery>((
      ref,
      query,
    ) async {
      final uri = Uri(
        path: '/api/v1/sites/${query.siteId}/analytics/forms',
        queryParameters: {
          'from': query.range.fromQuery,
          'to': query.range.toQuery,
          if (query.segmentId != null) 'segmentId': query.segmentId!,
        },
      );
      final response =
          await ref.read(apiProvider).request('GET', uri.toString()) as Map;
      return FormAnalyticsReport.fromJson(Map<String, dynamic>.from(response));
    });
