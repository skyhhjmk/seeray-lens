import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import 'analytics_controller.dart';

const yandexWebmasterDeviceTypes = <String>[
  'ALL',
  'DESKTOP',
  'MOBILE_AND_TABLET',
  'MOBILE',
  'TABLET',
];

class YandexWebmasterProperty {
  const YandexWebmasterProperty({
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

  factory YandexWebmasterProperty.fromJson(Map<String, dynamic> json) =>
      YandexWebmasterProperty(
        configured: json['configured'] as bool? ?? false,
        credentialConfigured: json['credentialConfigured'] as bool? ?? false,
        canManage: json['canManage'] as bool? ?? false,
        siteUrl: json['siteUrl'] as String?,
        updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? ''),
      );
}

class YandexWebmasterValidation {
  const YandexWebmasterValidation({
    required this.accessible,
    required this.verified,
    required this.siteUrl,
    required this.message,
  });

  final bool accessible;
  final bool verified;
  final String siteUrl;
  final String message;

  factory YandexWebmasterValidation.fromJson(Map<String, dynamic> json) =>
      YandexWebmasterValidation(
        accessible: json['accessible'] as bool? ?? false,
        verified: json['verified'] as bool? ?? false,
        siteUrl: json['siteUrl'] as String? ?? '',
        message: json['message'] as String? ?? '',
      );
}

class YandexWebmasterReportRow {
  const YandexWebmasterReportRow({
    required this.query,
    required this.clicks,
    required this.impressions,
    required this.ctr,
    required this.averagePosition,
  });

  final String query;
  final double clicks;
  final double impressions;
  final double ctr;
  final double averagePosition;

  factory YandexWebmasterReportRow.fromJson(Map<String, dynamic> json) =>
      YandexWebmasterReportRow(
        query: json['query'] as String? ?? '',
        clicks: (json['clicks'] as num?)?.toDouble() ?? 0,
        impressions: (json['impressions'] as num?)?.toDouble() ?? 0,
        ctr: (json['ctr'] as num?)?.toDouble() ?? 0,
        averagePosition: (json['averagePosition'] as num?)?.toDouble() ?? 0,
      );
}

class YandexWebmasterReport {
  const YandexWebmasterReport({
    required this.siteUrl,
    required this.from,
    required this.to,
    required this.deviceType,
    required this.clicks,
    required this.impressions,
    required this.ctr,
    required this.averagePosition,
    required this.totalQueries,
    required this.rows,
    required this.mayBeTruncated,
    required this.dataLimitNote,
  });

  final String siteUrl;
  final String from;
  final String to;
  final String deviceType;
  final double clicks;
  final double impressions;
  final double ctr;
  final double averagePosition;
  final int totalQueries;
  final List<YandexWebmasterReportRow> rows;
  final bool mayBeTruncated;
  final String dataLimitNote;

  factory YandexWebmasterReport.fromJson(
    Map<String, dynamic> json,
  ) => YandexWebmasterReport(
    siteUrl: json['siteUrl'] as String? ?? '',
    from: json['from'] as String? ?? '',
    to: json['to'] as String? ?? '',
    deviceType: json['deviceType'] as String? ?? 'ALL',
    clicks: (json['clicks'] as num?)?.toDouble() ?? 0,
    impressions: (json['impressions'] as num?)?.toDouble() ?? 0,
    ctr: (json['ctr'] as num?)?.toDouble() ?? 0,
    averagePosition: (json['averagePosition'] as num?)?.toDouble() ?? 0,
    totalQueries: (json['totalQueries'] as num?)?.toInt() ?? 0,
    rows: (json['rows'] as List? ?? const [])
        .whereType<Map>()
        .map(
          (row) =>
              YandexWebmasterReportRow.fromJson(Map<String, dynamic>.from(row)),
        )
        .toList(growable: false),
    mayBeTruncated: json['mayBeTruncated'] as bool? ?? false,
    dataLimitNote: json['dataLimitNote'] as String? ?? '',
  );
}

class YandexWebmasterReportQuery {
  const YandexWebmasterReportQuery({
    required this.siteId,
    required this.range,
    required this.deviceType,
  });

  final String siteId;
  final AnalyticsDateRange range;
  final String deviceType;

  @override
  bool operator ==(Object other) =>
      other is YandexWebmasterReportQuery &&
      other.siteId == siteId &&
      other.deviceType == deviceType &&
      other.range.fromQuery == range.fromQuery &&
      other.range.toQuery == range.toQuery;

  @override
  int get hashCode =>
      Object.hash(siteId, deviceType, range.fromQuery, range.toQuery);
}

final yandexWebmasterPropertyProvider =
    FutureProvider.family<YandexWebmasterProperty, String>((ref, siteId) async {
      final result = await ref
          .read(apiProvider)
          .request('GET', '/api/v1/sites/$siteId/yandex-webmaster/property');
      if (result is! Map) {
        throw const FormatException(
          'Invalid Yandex Webmaster property response',
        );
      }
      return YandexWebmasterProperty.fromJson(
        Map<String, dynamic>.from(result),
      );
    });

final yandexWebmasterReportProvider =
    FutureProvider.family<YandexWebmasterReport, YandexWebmasterReportQuery>((
      ref,
      query,
    ) async {
      final path = Uri(
        path: '/api/v1/sites/${query.siteId}/yandex-webmaster/report',
        queryParameters: {
          'from': query.range.fromQuery,
          'to': query.range.toQuery,
          'deviceType': query.deviceType,
        },
      ).toString();
      final result = await ref.read(apiProvider).request('GET', path);
      if (result is! Map) {
        throw const FormatException('Invalid Yandex Webmaster report response');
      }
      return YandexWebmasterReport.fromJson(Map<String, dynamic>.from(result));
    });

class YandexWebmasterRepository {
  const YandexWebmasterRepository(this.ref);

  final WidgetRef ref;

  Future<YandexWebmasterProperty> saveProperty(
    String siteId,
    String siteUrl,
    String oauthToken,
  ) async {
    final result = await ref
        .read(apiProvider)
        .request(
          'PUT',
          '/api/v1/sites/$siteId/yandex-webmaster/property',
          body: {'siteUrl': siteUrl, 'oauthToken': oauthToken},
        );
    if (result is! Map) {
      throw const FormatException('Invalid Yandex Webmaster property response');
    }
    return YandexWebmasterProperty.fromJson(Map<String, dynamic>.from(result));
  }

  Future<YandexWebmasterValidation> validate(String siteId) async {
    final result = await ref
        .read(apiProvider)
        .request('POST', '/api/v1/sites/$siteId/yandex-webmaster/validate');
    if (result is! Map) {
      throw const FormatException(
        'Invalid Yandex Webmaster validation response',
      );
    }
    return YandexWebmasterValidation.fromJson(
      Map<String, dynamic>.from(result),
    );
  }

  Future<void> deleteProperty(String siteId) async {
    await ref
        .read(apiProvider)
        .request('DELETE', '/api/v1/sites/$siteId/yandex-webmaster/property');
  }
}
