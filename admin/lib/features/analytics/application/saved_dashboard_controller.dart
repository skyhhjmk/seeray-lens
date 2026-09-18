import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import 'custom_report_formula.dart';

class SavedDashboardWidget {
  const SavedDashboardWidget({
    required this.id,
    required this.type,
    required this.title,
    this.metric,
    this.limit,
    this.chartType,
    this.dimension,
    this.secondaryDimension,
    this.tertiaryDimension,
    this.quaternaryDimension,
    this.formula,
    this.locationLevel,
    this.matchMode,
    this.filters,
  });

  final String id;
  final String type;
  final String title;
  final String? metric;
  final int? limit;
  final String? chartType;
  final String? dimension;
  final String? secondaryDimension;
  final String? tertiaryDimension;
  final String? quaternaryDimension;
  final CustomReportFormula? formula;
  final String? locationLevel;
  final String? matchMode;
  final List<SavedDashboardFilter>? filters;

  factory SavedDashboardWidget.fromJson(Map<String, dynamic> json) =>
      SavedDashboardWidget(
        id: json['id'] as String,
        type: json['type'] as String,
        title: json['title'] as String,
        metric: json['metric'] as String?,
        limit: (json['limit'] as num?)?.toInt(),
        chartType: json['chartType'] as String?,
        dimension: json['dimension'] as String?,
        secondaryDimension: json['secondaryDimension'] as String?,
        tertiaryDimension: json['tertiaryDimension'] as String?,
        quaternaryDimension: json['quaternaryDimension'] as String?,
        formula: json['formula'] is Map
            ? CustomReportFormula.fromJson(
                Map<String, dynamic>.from(json['formula'] as Map),
              )
            : null,
        locationLevel: json['locationLevel'] as String?,
        matchMode: json['matchMode'] as String?,
        filters: (json['filters'] as List?)
            ?.whereType<Map>()
            .map(
              (item) => SavedDashboardFilter.fromJson(
                Map<String, dynamic>.from(item),
              ),
            )
            .toList(growable: false),
      );

  factory SavedDashboardWidget.create(String type) {
    final id =
        '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
        '${Random().nextInt(1 << 24).toRadixString(36)}';
    return switch (type) {
      'summary' => SavedDashboardWidget(
        id: id,
        type: type,
        title: 'Key metrics',
      ),
      'trend' => SavedDashboardWidget(
        id: id,
        type: type,
        title: 'Visits over time',
        metric: 'sessions',
        chartType: 'line',
      ),
      'top_pages' => SavedDashboardWidget(
        id: id,
        type: type,
        title: 'Top pages',
        limit: 5,
      ),
      'traffic_channels' => SavedDashboardWidget(
        id: id,
        type: type,
        title: 'Traffic channels',
        limit: 5,
      ),
      'visitor_types' => SavedDashboardWidget(
        id: id,
        type: type,
        title: 'New and returning visitors',
      ),
      'events' => SavedDashboardWidget(
        id: id,
        type: type,
        title: 'Events',
        limit: 5,
      ),
      'goals' => SavedDashboardWidget(
        id: id,
        type: type,
        title: 'Goal conversions',
        limit: 5,
      ),
      'technology' => SavedDashboardWidget(
        id: id,
        type: type,
        title: 'Browser technology',
        dimension: 'Browser',
        limit: 5,
      ),
      'locations' => SavedDashboardWidget(
        id: id,
        type: type,
        title: 'Visitor locations',
        locationLevel: 'country',
        limit: 5,
      ),
      'page_behaviour' => SavedDashboardWidget(
        id: id,
        type: type,
        title: 'Page titles',
      ),
      'live_visitors' => SavedDashboardWidget(
        id: id,
        type: type,
        title: 'Live visitors',
        limit: 5,
      ),
      'custom_report' => SavedDashboardWidget(
        id: id,
        type: type,
        title: 'Custom report',
        metric: 'sessions',
        limit: 10,
        chartType: 'table',
        dimension: 'browser',
        matchMode: 'all',
        filters: const [],
      ),
      _ => throw ArgumentError.value(type, 'type', 'Unsupported widget type'),
    };
  }

  SavedDashboardWidget copyWith({
    String? title,
    String? metric,
    int? limit,
    String? chartType,
    String? dimension,
    String? secondaryDimension,
    bool clearSecondaryDimension = false,
    String? tertiaryDimension,
    bool clearTertiaryDimension = false,
    String? quaternaryDimension,
    bool clearQuaternaryDimension = false,
    CustomReportFormula? formula,
    bool clearFormula = false,
    String? locationLevel,
    String? matchMode,
    List<SavedDashboardFilter>? filters,
  }) => SavedDashboardWidget(
    id: id,
    type: type,
    title: title ?? this.title,
    metric: metric ?? this.metric,
    limit: limit ?? this.limit,
    chartType: chartType ?? this.chartType,
    dimension: dimension ?? this.dimension,
    secondaryDimension: clearSecondaryDimension
        ? null
        : secondaryDimension ?? this.secondaryDimension,
    tertiaryDimension: clearTertiaryDimension
        ? null
        : tertiaryDimension ?? this.tertiaryDimension,
    quaternaryDimension: clearQuaternaryDimension
        ? null
        : quaternaryDimension ?? this.quaternaryDimension,
    formula: clearFormula ? null : formula ?? this.formula,
    locationLevel: locationLevel ?? this.locationLevel,
    matchMode: matchMode ?? this.matchMode,
    filters: filters ?? this.filters,
  );

  Map<String, Object> toJson() {
    final result = <String, Object>{'id': id, 'type': type, 'title': title};
    if (metric != null) result['metric'] = metric!;
    if (limit != null) result['limit'] = limit!;
    if (chartType != null) result['chartType'] = chartType!;
    if (dimension != null) result['dimension'] = dimension!;
    if (secondaryDimension != null) {
      result['secondaryDimension'] = secondaryDimension!;
    }
    if (tertiaryDimension != null) {
      result['tertiaryDimension'] = tertiaryDimension!;
    }
    if (quaternaryDimension != null) {
      result['quaternaryDimension'] = quaternaryDimension!;
    }
    if (formula != null) result['formula'] = formula!.toJson();
    if (locationLevel != null) result['locationLevel'] = locationLevel!;
    if (matchMode != null) result['matchMode'] = matchMode!;
    if (filters != null) {
      result['filters'] = filters!.map((item) => item.toJson()).toList();
    }
    return result;
  }
}

class SavedDashboardFilter {
  const SavedDashboardFilter({
    required this.field,
    required this.operator,
    required this.value,
    this.dimensionKey,
  });

  final String field;
  final String operator;
  final String value;
  final String? dimensionKey;

  factory SavedDashboardFilter.fromJson(Map<String, dynamic> json) =>
      SavedDashboardFilter(
        field: json['field'] as String? ?? 'visitor_type',
        operator: json['operator'] as String? ?? 'equals',
        value: json['value'] as String? ?? '',
        dimensionKey: json['dimensionKey'] as String?,
      );

  Map<String, Object> toJson() {
    final result = <String, Object>{
      'field': field,
      'operator': operator,
      'value': value,
    };
    if (dimensionKey != null) result['dimensionKey'] = dimensionKey!;
    return result;
  }
}

class SavedAnalyticsDashboard {
  const SavedAnalyticsDashboard({
    required this.id,
    required this.name,
    required this.widgets,
    required this.isDefault,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final List<SavedDashboardWidget> widgets;
  final bool isDefault;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory SavedAnalyticsDashboard.fromJson(Map<String, dynamic> json) =>
      SavedAnalyticsDashboard(
        id: json['id'] as String,
        name: json['name'] as String,
        widgets: (json['widgets'] as List? ?? const [])
            .whereType<Map>()
            .map(
              (item) => SavedDashboardWidget.fromJson(
                Map<String, dynamic>.from(item),
              ),
            )
            .toList(growable: false),
        isDefault: json['isDefault'] as bool? ?? false,
        createdAt: DateTime.parse(json['createdAt'] as String),
        updatedAt: DateTime.parse(json['updatedAt'] as String),
      );
}

final savedAnalyticsDashboardsProvider =
    FutureProvider.family<List<SavedAnalyticsDashboard>, String>((
      ref,
      siteId,
    ) async {
      final result =
          await ref
                  .read(apiProvider)
                  .request('GET', '/api/v1/sites/$siteId/dashboards')
              as List;
      return result
          .whereType<Map>()
          .map(
            (item) => SavedAnalyticsDashboard.fromJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .toList(growable: false);
    });

List<SavedDashboardWidget> get starterDashboardWidgets => [
  SavedDashboardWidget.create('summary'),
  SavedDashboardWidget.create('trend'),
  SavedDashboardWidget.create('top_pages'),
  SavedDashboardWidget.create('traffic_channels'),
];
