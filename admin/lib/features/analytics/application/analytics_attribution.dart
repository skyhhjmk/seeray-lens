import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import 'analytics_controller.dart';

class AttributionQuery {
  const AttributionQuery({
    required this.siteId,
    required this.range,
    required this.model,
    required this.lookbackDays,
    this.goalId,
    this.segmentId,
  });

  final String siteId;
  final AnalyticsDateRange range;
  final String model;
  final int lookbackDays;
  final String? goalId;
  final String? segmentId;

  @override
  bool operator ==(Object other) =>
      other is AttributionQuery &&
      other.siteId == siteId &&
      other.model == model &&
      other.lookbackDays == lookbackDays &&
      other.goalId == goalId &&
      other.segmentId == segmentId &&
      other.range.fromQuery == range.fromQuery &&
      other.range.toQuery == range.toQuery;

  @override
  int get hashCode => Object.hash(
    siteId,
    range.fromQuery,
    range.toQuery,
    model,
    lookbackDays,
    goalId,
    segmentId,
  );
}

class AttributionGoal {
  const AttributionGoal({
    required this.id,
    required this.name,
    required this.enabled,
    required this.fixedValue,
  });

  final String id;
  final String name;
  final bool enabled;
  final double fixedValue;

  factory AttributionGoal.fromJson(Map<String, dynamic> json) =>
      AttributionGoal(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? 'Goal',
        enabled: json['enabled'] as bool? ?? false,
        fixedValue: (json['fixedValue'] as num?)?.toDouble() ?? 0,
      );
}

final analyticsGoalDefinitionsProvider =
    FutureProvider.family<List<AttributionGoal>, String>((ref, siteId) async {
      final response = await ref
          .read(apiProvider)
          .request('GET', '/api/v1/sites/$siteId/goals');
      return (response as List)
          .whereType<Map>()
          .map(
            (item) => AttributionGoal.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList(growable: false);
    });

class AttributionRow {
  const AttributionRow({
    required this.goalId,
    required this.goalName,
    required this.channel,
    required this.attributedConversions,
    required this.attributedValue,
    this.source,
    this.medium,
    this.campaign,
  });

  final String goalId;
  final String goalName;
  final String channel;
  final String? source;
  final String? medium;
  final String? campaign;
  final double attributedConversions;
  final double attributedValue;

  factory AttributionRow.fromJson(Map<String, dynamic> json) => AttributionRow(
    goalId: json['goalId'] as String? ?? '',
    goalName: json['goalName'] as String? ?? 'Goal',
    channel: json['channel'] as String? ?? 'direct',
    source: json['source'] as String?,
    medium: json['medium'] as String?,
    campaign: json['campaign'] as String?,
    attributedConversions:
        (json['attributedConversions'] as num?)?.toDouble() ?? 0,
    attributedValue: (json['attributedValue'] as num?)?.toDouble() ?? 0,
  );
}

class AttributionReport {
  const AttributionReport({
    required this.model,
    required this.lookbackDays,
    required this.attributedConversions,
    required this.attributedValue,
    required this.rows,
  });

  final String model;
  final int lookbackDays;
  final double attributedConversions;
  final double attributedValue;
  final List<AttributionRow> rows;

  factory AttributionReport.fromJson(Map<String, dynamic> json) =>
      AttributionReport(
        model: json['model'] as String? ?? 'last_touch',
        lookbackDays: (json['lookbackDays'] as num?)?.toInt() ?? 30,
        attributedConversions:
            (json['attributedConversions'] as num?)?.toDouble() ?? 0,
        attributedValue: (json['attributedValue'] as num?)?.toDouble() ?? 0,
        rows: (json['rows'] as List? ?? const [])
            .whereType<Map>()
            .map(
              (item) =>
                  AttributionRow.fromJson(Map<String, dynamic>.from(item)),
            )
            .toList(growable: false),
      );
}

class AttributionData {
  const AttributionData({required this.goals, required this.report});

  final List<AttributionGoal> goals;
  final AttributionReport report;
}

final analyticsAttributionProvider =
    FutureProvider.family<AttributionData, AttributionQuery>((
      ref,
      query,
    ) async {
      final api = ref.read(apiProvider);
      final reportUri = Uri(
        path: '/api/v1/sites/${query.siteId}/analytics/attribution',
        queryParameters: {
          'from': query.range.fromQuery,
          'to': query.range.toQuery,
          'model': query.model,
          'lookbackDays': '${query.lookbackDays}',
          if (query.goalId != null) 'goalId': query.goalId!,
          if (query.segmentId != null) 'segmentId': query.segmentId!,
        },
      );
      final responses = await Future.wait<dynamic>([
        ref.watch(analyticsGoalDefinitionsProvider(query.siteId).future),
        api.request('GET', reportUri.toString()),
      ]);
      final goals = responses[0] as List<AttributionGoal>;
      return AttributionData(
        goals: goals,
        report: AttributionReport.fromJson(
          Map<String, dynamic>.from(responses[1] as Map),
        ),
      );
    });
