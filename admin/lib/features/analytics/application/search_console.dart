import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import 'analytics_controller.dart';

const searchConsoleDimensions = <String>[
  'query',
  'page',
  'country',
  'device',
  'date',
];

class SearchConsoleProperty {
  const SearchConsoleProperty({
    required this.configured,
    required this.canManage,
    required this.credentialMode,
    this.propertyUrl,
    this.updatedAt,
  });

  final bool configured;
  final bool canManage;
  final String credentialMode;
  final String? propertyUrl;
  final DateTime? updatedAt;

  factory SearchConsoleProperty.fromJson(Map<String, dynamic> json) =>
      SearchConsoleProperty(
        configured: json['configured'] as bool? ?? false,
        canManage: json['canManage'] as bool? ?? false,
        credentialMode: json['credentialMode'] as String? ?? '',
        propertyUrl: json['propertyUrl'] as String?,
        updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? ''),
      );
}

class SearchConsoleValidation {
  const SearchConsoleValidation({
    required this.accessible,
    required this.message,
    this.propertyUrl,
    this.permissionLevel,
  });

  final bool accessible;
  final String message;
  final String? propertyUrl;
  final String? permissionLevel;

  factory SearchConsoleValidation.fromJson(Map<String, dynamic> json) =>
      SearchConsoleValidation(
        accessible: json['accessible'] as bool? ?? false,
        message: json['message'] as String? ?? '',
        propertyUrl: json['propertyUrl'] as String?,
        permissionLevel: json['permissionLevel'] as String?,
      );
}

class SearchConsoleReportRow {
  const SearchConsoleReportRow({
    required this.key,
    required this.clicks,
    required this.impressions,
    required this.ctr,
    required this.position,
  });

  final String key;
  final double clicks;
  final double impressions;
  final double ctr;
  final double position;

  factory SearchConsoleReportRow.fromJson(Map<String, dynamic> json) =>
      SearchConsoleReportRow(
        key: json['key'] as String? ?? '',
        clicks: (json['clicks'] as num?)?.toDouble() ?? 0,
        impressions: (json['impressions'] as num?)?.toDouble() ?? 0,
        ctr: (json['ctr'] as num?)?.toDouble() ?? 0,
        position: (json['position'] as num?)?.toDouble() ?? 0,
      );
}

class SearchConsoleReport {
  const SearchConsoleReport({
    required this.propertyUrl,
    required this.from,
    required this.to,
    required this.dimension,
    required this.clicks,
    required this.impressions,
    required this.ctr,
    required this.averagePosition,
    required this.aggregationType,
    required this.rows,
    required this.mayBeTruncated,
    required this.dataLimitNote,
  });

  final String propertyUrl;
  final String from;
  final String to;
  final String dimension;
  final double clicks;
  final double impressions;
  final double ctr;
  final double averagePosition;
  final String aggregationType;
  final List<SearchConsoleReportRow> rows;
  final bool mayBeTruncated;
  final String dataLimitNote;

  factory SearchConsoleReport.fromJson(Map<String, dynamic> json) =>
      SearchConsoleReport(
        propertyUrl: json['propertyUrl'] as String? ?? '',
        from: json['from'] as String? ?? '',
        to: json['to'] as String? ?? '',
        dimension: json['dimension'] as String? ?? 'query',
        clicks: (json['clicks'] as num?)?.toDouble() ?? 0,
        impressions: (json['impressions'] as num?)?.toDouble() ?? 0,
        ctr: (json['ctr'] as num?)?.toDouble() ?? 0,
        averagePosition: (json['averagePosition'] as num?)?.toDouble() ?? 0,
        aggregationType: json['aggregationType'] as String? ?? 'auto',
        rows: (json['rows'] as List? ?? const [])
            .whereType<Map>()
            .map(
              (row) => SearchConsoleReportRow.fromJson(
                Map<String, dynamic>.from(row),
              ),
            )
            .toList(growable: false),
        mayBeTruncated: json['mayBeTruncated'] as bool? ?? false,
        dataLimitNote: json['dataLimitNote'] as String? ?? '',
      );
}

class SearchConsoleReportQuery {
  const SearchConsoleReportQuery({
    required this.siteId,
    required this.range,
    required this.dimension,
  });

  final String siteId;
  final AnalyticsDateRange range;
  final String dimension;

  @override
  bool operator ==(Object other) =>
      other is SearchConsoleReportQuery &&
      other.siteId == siteId &&
      other.dimension == dimension &&
      other.range.fromQuery == range.fromQuery &&
      other.range.toQuery == range.toQuery;

  @override
  int get hashCode =>
      Object.hash(siteId, dimension, range.fromQuery, range.toQuery);
}

final searchConsolePropertyProvider =
    FutureProvider.family<SearchConsoleProperty, String>((ref, siteId) async {
      final result = await ref
          .read(apiProvider)
          .request('GET', '/api/v1/sites/$siteId/search-console/property');
      if (result is! Map) {
        throw const FormatException('Invalid Search Console property response');
      }
      return SearchConsoleProperty.fromJson(Map<String, dynamic>.from(result));
    });

final searchConsoleReportProvider =
    FutureProvider.family<SearchConsoleReport, SearchConsoleReportQuery>((
      ref,
      query,
    ) async {
      final parameters = <String, String>{
        'from': query.range.fromQuery,
        'to': query.range.toQuery,
        'dimension': query.dimension,
      };
      final path = Uri(
        path: '/api/v1/sites/${query.siteId}/search-console/report',
        queryParameters: parameters,
      ).toString();
      final result = await ref.read(apiProvider).request('GET', path);
      if (result is! Map) {
        throw const FormatException('Invalid Search Console report response');
      }
      return SearchConsoleReport.fromJson(Map<String, dynamic>.from(result));
    });

class SearchConsoleRepository {
  const SearchConsoleRepository(this.ref);

  final WidgetRef ref;

  Future<SearchConsoleProperty> saveProperty(
    String siteId,
    String propertyUrl,
  ) async {
    final result = await ref
        .read(apiProvider)
        .request(
          'PUT',
          '/api/v1/sites/$siteId/search-console/property',
          body: {'propertyUrl': propertyUrl},
        );
    if (result is! Map) {
      throw const FormatException('Invalid Search Console property response');
    }
    return SearchConsoleProperty.fromJson(Map<String, dynamic>.from(result));
  }

  Future<SearchConsoleValidation> validate(String siteId) async {
    final result = await ref
        .read(apiProvider)
        .request('POST', '/api/v1/sites/$siteId/search-console/validate');
    if (result is! Map) {
      throw const FormatException('Invalid Search Console validation response');
    }
    return SearchConsoleValidation.fromJson(Map<String, dynamic>.from(result));
  }

  Future<void> deleteProperty(String siteId) async {
    await ref
        .read(apiProvider)
        .request('DELETE', '/api/v1/sites/$siteId/search-console/property');
  }
}
