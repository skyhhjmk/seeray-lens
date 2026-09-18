import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import 'analytics_controller.dart';

const bingWebmasterDimensions = <String>['query', 'page', 'date'];

class BingWebmasterProperty {
  const BingWebmasterProperty({
    required this.configured,
    required this.credentialConfigured,
    required this.canManage,
    this.siteUrl,
    this.updatedAt,
  });

  final bool configured;
  final bool credentialConfigured;
  final bool canManage;
  final String? siteUrl;
  final DateTime? updatedAt;

  factory BingWebmasterProperty.fromJson(Map<String, dynamic> json) =>
      BingWebmasterProperty(
        configured: json['configured'] as bool? ?? false,
        credentialConfigured: json['credentialConfigured'] as bool? ?? false,
        canManage: json['canManage'] as bool? ?? false,
        siteUrl: json['siteUrl'] as String?,
        updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? ''),
      );
}

class BingWebmasterValidation {
  const BingWebmasterValidation({
    required this.accessible,
    required this.verified,
    required this.siteUrl,
    required this.message,
  });

  final bool accessible;
  final bool verified;
  final String siteUrl;
  final String message;

  factory BingWebmasterValidation.fromJson(Map<String, dynamic> json) =>
      BingWebmasterValidation(
        accessible: json['accessible'] as bool? ?? false,
        verified: json['verified'] as bool? ?? false,
        siteUrl: json['siteUrl'] as String? ?? '',
        message: json['message'] as String? ?? '',
      );
}

class BingWebmasterReportRow {
  const BingWebmasterReportRow({
    required this.key,
    required this.clicks,
    required this.impressions,
    required this.ctr,
    required this.averagePosition,
  });

  final String key;
  final double clicks;
  final double impressions;
  final double ctr;
  final double averagePosition;

  factory BingWebmasterReportRow.fromJson(Map<String, dynamic> json) =>
      BingWebmasterReportRow(
        key: json['key'] as String? ?? '',
        clicks: (json['clicks'] as num?)?.toDouble() ?? 0,
        impressions: (json['impressions'] as num?)?.toDouble() ?? 0,
        ctr: (json['ctr'] as num?)?.toDouble() ?? 0,
        averagePosition: (json['averagePosition'] as num?)?.toDouble() ?? 0,
      );
}

class BingWebmasterReport {
  const BingWebmasterReport({
    required this.siteUrl,
    required this.from,
    required this.to,
    required this.dimension,
    required this.clicks,
    required this.impressions,
    required this.ctr,
    required this.rows,
    required this.mayBeTruncated,
    required this.dataLimitNote,
  });

  final String siteUrl;
  final String from;
  final String to;
  final String dimension;
  final double clicks;
  final double impressions;
  final double ctr;
  final List<BingWebmasterReportRow> rows;
  final bool mayBeTruncated;
  final String dataLimitNote;

  factory BingWebmasterReport.fromJson(Map<String, dynamic> json) =>
      BingWebmasterReport(
        siteUrl: json['siteUrl'] as String? ?? '',
        from: json['from'] as String? ?? '',
        to: json['to'] as String? ?? '',
        dimension: json['dimension'] as String? ?? 'query',
        clicks: (json['clicks'] as num?)?.toDouble() ?? 0,
        impressions: (json['impressions'] as num?)?.toDouble() ?? 0,
        ctr: (json['ctr'] as num?)?.toDouble() ?? 0,
        rows: (json['rows'] as List? ?? const [])
            .whereType<Map>()
            .map(
              (row) => BingWebmasterReportRow.fromJson(
                Map<String, dynamic>.from(row),
              ),
            )
            .toList(growable: false),
        mayBeTruncated: json['mayBeTruncated'] as bool? ?? false,
        dataLimitNote: json['dataLimitNote'] as String? ?? '',
      );
}

class BingWebmasterReportQuery {
  const BingWebmasterReportQuery({
    required this.siteId,
    required this.range,
    required this.dimension,
  });

  final String siteId;
  final AnalyticsDateRange range;
  final String dimension;

  @override
  bool operator ==(Object other) =>
      other is BingWebmasterReportQuery &&
      other.siteId == siteId &&
      other.dimension == dimension &&
      other.range.fromQuery == range.fromQuery &&
      other.range.toQuery == range.toQuery;

  @override
  int get hashCode =>
      Object.hash(siteId, dimension, range.fromQuery, range.toQuery);
}

final bingWebmasterPropertyProvider =
    FutureProvider.family<BingWebmasterProperty, String>((ref, siteId) async {
      final result = await ref
          .read(apiProvider)
          .request('GET', '/api/v1/sites/$siteId/bing-webmaster/property');
      if (result is! Map) {
        throw const FormatException('Invalid Bing Webmaster property response');
      }
      return BingWebmasterProperty.fromJson(Map<String, dynamic>.from(result));
    });

final bingWebmasterReportProvider =
    FutureProvider.family<BingWebmasterReport, BingWebmasterReportQuery>((
      ref,
      query,
    ) async {
      final path = Uri(
        path: '/api/v1/sites/${query.siteId}/bing-webmaster/report',
        queryParameters: {
          'from': query.range.fromQuery,
          'to': query.range.toQuery,
          'dimension': query.dimension,
        },
      ).toString();
      final result = await ref.read(apiProvider).request('GET', path);
      if (result is! Map) {
        throw const FormatException('Invalid Bing Webmaster report response');
      }
      return BingWebmasterReport.fromJson(Map<String, dynamic>.from(result));
    });

class BingWebmasterRepository {
  const BingWebmasterRepository(this.ref);

  final WidgetRef ref;

  Future<BingWebmasterProperty> saveProperty(
    String siteId,
    String siteUrl,
    String apiKey,
  ) async {
    final result = await ref
        .read(apiProvider)
        .request(
          'PUT',
          '/api/v1/sites/$siteId/bing-webmaster/property',
          body: {'siteUrl': siteUrl, 'apiKey': apiKey},
        );
    if (result is! Map) {
      throw const FormatException('Invalid Bing Webmaster property response');
    }
    return BingWebmasterProperty.fromJson(Map<String, dynamic>.from(result));
  }

  Future<BingWebmasterValidation> validate(String siteId) async {
    final result = await ref
        .read(apiProvider)
        .request('POST', '/api/v1/sites/$siteId/bing-webmaster/validate');
    if (result is! Map) {
      throw const FormatException('Invalid Bing Webmaster validation response');
    }
    return BingWebmasterValidation.fromJson(Map<String, dynamic>.from(result));
  }

  Future<void> deleteProperty(String siteId) async {
    await ref
        .read(apiProvider)
        .request('DELETE', '/api/v1/sites/$siteId/bing-webmaster/property');
  }
}
