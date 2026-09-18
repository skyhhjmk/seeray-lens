import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import 'analytics_controller.dart';
import 'analytics_csv.dart';

const offlineConversionCsvHeaders = <String>[
  'conversion_id',
  'platform',
  'click_id',
  'converted_at',
];

const offlineConversionPlatforms = <String>{
  'google_ads',
  'microsoft_ads',
  'meta_ads',
  'tiktok_ads',
  'linkedin_ads',
  'x_ads',
};

class OfflineConversionImportRow {
  const OfflineConversionImportRow({
    required this.conversionId,
    required this.platform,
    required this.clickId,
    required this.convertedAt,
  });

  final String conversionId;
  final String platform;
  final String clickId;
  final String convertedAt;

  Map<String, String> toJson() => {
    'conversionId': conversionId,
    'platform': platform,
    'clickId': clickId,
    'convertedAt': convertedAt,
  };
}

class OfflineConversionImportPreview {
  const OfflineConversionImportPreview(this.rows);

  static const maximumRows = 5000;
  static const maximumBytes = 2 * 1024 * 1024;

  final List<OfflineConversionImportRow> rows;

  int get tooOldRows => rows.where((row) {
    final convertedAt = DateTime.parse(row.convertedAt).toUtc();
    return DateTime.now().toUtc().difference(convertedAt) >
        const Duration(days: 7);
  }).length;

  int get futureRows => rows.where((row) {
    final convertedAt = DateTime.parse(row.convertedAt).toUtc();
    return convertedAt.isAfter(
      DateTime.now().toUtc().add(const Duration(minutes: 5)),
    );
  }).length;

  int get eligibleRows => rows.length - tooOldRows - futureRows;

  int get linkedinTooOldRows => rows.where((row) {
    final convertedAt = DateTime.parse(row.convertedAt).toUtc();
    return DateTime.now().toUtc().difference(convertedAt) >
        const Duration(days: 90);
  }).length;

  int get linkedinFutureRows => rows.where((row) {
    final convertedAt = DateTime.parse(row.convertedAt).toUtc();
    return convertedAt.isAfter(DateTime.now().toUtc());
  }).length;

  DateTime get firstConversion => rows
      .map((row) => DateTime.parse(row.convertedAt).toUtc())
      .reduce((a, b) => a.isBefore(b) ? a : b);

  DateTime get lastConversion => rows
      .map((row) => DateTime.parse(row.convertedAt).toUtc())
      .reduce((a, b) => a.isAfter(b) ? a : b);

  factory OfflineConversionImportPreview.parse(String input) {
    final records = parseAnalyticsCsvRecords(input.replaceFirst('\uFEFF', ''));
    if (records.isEmpty) throw const FormatException('The CSV file is empty.');
    final headers = records.first
        .map((value) => value.trim().toLowerCase())
        .toList();
    if (headers.toSet().length != offlineConversionCsvHeaders.length ||
        headers
            .toSet()
            .difference(offlineConversionCsvHeaders.toSet())
            .isNotEmpty ||
        offlineConversionCsvHeaders
            .toSet()
            .difference(headers.toSet())
            .isNotEmpty) {
      throw const FormatException(
        'Use the supplied template with conversion_id, platform, click_id, and converted_at columns.',
      );
    }
    if (records.length < 2) {
      throw const FormatException(
        'Add at least one offline conversion row below the header.',
      );
    }
    if (records.length - 1 > maximumRows) {
      throw FormatException('A file can contain at most $maximumRows rows.');
    }
    final columns = {for (var i = 0; i < headers.length; i++) headers[i]: i};
    final result = <OfflineConversionImportRow>[];
    final conversionIds = <String>{};
    for (var recordIndex = 1; recordIndex < records.length; recordIndex++) {
      final line = recordIndex + 1;
      final cells = records[recordIndex];
      if (cells.length != headers.length) {
        throw FormatException(
          'Row $line must contain exactly ${headers.length} columns.',
        );
      }
      String cell(String name) => cells[columns[name]!].trim();
      final conversionId = _offlineRequiredCell(
        cells,
        columns['conversion_id']!,
        'conversion_id',
        line,
        256,
      );
      if (!conversionIds.add(conversionId)) {
        throw FormatException(
          'Row $line repeats a conversion_id from this file.',
        );
      }
      final platform = cell('platform').toLowerCase();
      if (!offlineConversionPlatforms.contains(platform)) {
        throw FormatException(
          'Row $line: use a supported platform key such as google_ads.',
        );
      }
      final clickId = _offlineRequiredCell(
        cells,
        columns['click_id']!,
        'click_id',
        line,
        2048,
      );
      final convertedAt = cell('converted_at');
      final hasOffset = RegExp(
        r'(?:Z|[+-]\d{2}:\d{2})$',
        caseSensitive: false,
      ).hasMatch(convertedAt);
      if (!hasOffset || DateTime.tryParse(convertedAt) == null) {
        throw FormatException(
          'Row $line: converted_at must be an ISO-8601 date-time with a timezone offset.',
        );
      }
      result.add(
        OfflineConversionImportRow(
          conversionId: conversionId,
          platform: platform,
          clickId: clickId,
          convertedAt: convertedAt,
        ),
      );
    }
    return OfflineConversionImportPreview(List.unmodifiable(result));
  }
}

String _offlineRequiredCell(
  List<String> cells,
  int index,
  String name,
  int row,
  int maximum,
) {
  final raw = cells[index];
  if (raw.contains(RegExp(r'[\x00-\x1f\x7f]'))) {
    throw FormatException(
      'Row $row: $name must not contain control characters.',
    );
  }
  final value = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (value.isEmpty || value.length > maximum) {
    throw FormatException(
      'Row $row: $name is required and must be at most $maximum characters.',
    );
  }
  return value;
}

class OfflineConversionQuery {
  const OfflineConversionQuery({
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
      other is OfflineConversionQuery &&
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

class OfflineConversionRow {
  const OfflineConversionRow({
    required this.goalId,
    required this.goalName,
    required this.platform,
    required this.channel,
    required this.attributedConversions,
    required this.attributedValue,
    this.source,
    this.medium,
    this.campaign,
  });

  final String goalId;
  final String goalName;
  final String platform;
  final String channel;
  final String? source;
  final String? medium;
  final String? campaign;
  final double attributedConversions;
  final double attributedValue;

  factory OfflineConversionRow.fromJson(Map<String, dynamic> json) =>
      OfflineConversionRow(
        goalId: json['goalId'] as String? ?? '',
        goalName: json['goalName'] as String? ?? 'Goal',
        platform: json['platform'] as String? ?? '',
        channel: json['channel'] as String? ?? 'direct',
        source: json['source'] as String?,
        medium: json['medium'] as String?,
        campaign: json['campaign'] as String?,
        attributedConversions:
            (json['attributedConversions'] as num?)?.toDouble() ?? 0,
        attributedValue: (json['attributedValue'] as num?)?.toDouble() ?? 0,
      );
}

class OfflineConversionReport {
  const OfflineConversionReport({
    required this.model,
    required this.lookbackDays,
    required this.totalImported,
    required this.matchedConversions,
    required this.unmatchedConversions,
    required this.attributedConversions,
    required this.attributedValue,
    required this.rows,
  });

  final String model;
  final int lookbackDays;
  final int totalImported;
  final int matchedConversions;
  final int unmatchedConversions;
  final double attributedConversions;
  final double attributedValue;
  final List<OfflineConversionRow> rows;

  factory OfflineConversionReport.fromJson(
    Map<String, dynamic> json,
  ) => OfflineConversionReport(
    model: json['model'] as String? ?? 'last_touch',
    lookbackDays: (json['lookbackDays'] as num?)?.toInt() ?? 30,
    totalImported: (json['totalImported'] as num?)?.toInt() ?? 0,
    matchedConversions: (json['matchedConversions'] as num?)?.toInt() ?? 0,
    unmatchedConversions: (json['unmatchedConversions'] as num?)?.toInt() ?? 0,
    attributedConversions:
        (json['attributedConversions'] as num?)?.toDouble() ?? 0,
    attributedValue: (json['attributedValue'] as num?)?.toDouble() ?? 0,
    rows: (json['rows'] as List? ?? const [])
        .whereType<Map>()
        .map(
          (item) =>
              OfflineConversionRow.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList(growable: false),
  );
}

class OfflineConversionImportBatch {
  const OfflineConversionImportBatch({
    required this.id,
    required this.goalName,
    required this.rowCount,
    required this.importedAt,
  });

  final String id;
  final String goalName;
  final int rowCount;
  final DateTime importedAt;

  factory OfflineConversionImportBatch.fromJson(Map<String, dynamic> json) =>
      OfflineConversionImportBatch(
        id: json['id'] as String? ?? '',
        goalName: json['goalName'] as String? ?? 'Goal',
        rowCount: (json['rowCount'] as num?)?.toInt() ?? 0,
        importedAt:
            DateTime.tryParse(json['importedAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );
}

class OfflineConversionHistory {
  const OfflineConversionHistory({
    required this.canManage,
    required this.timezone,
    required this.imports,
  });

  final bool canManage;
  final String timezone;
  final List<OfflineConversionImportBatch> imports;

  factory OfflineConversionHistory.fromJson(Map<String, dynamic> json) =>
      OfflineConversionHistory(
        canManage: json['canManage'] as bool? ?? false,
        timezone: json['timezone'] as String? ?? 'UTC',
        imports: (json['imports'] as List? ?? const [])
            .whereType<Map>()
            .map(
              (item) => OfflineConversionImportBatch.fromJson(
                Map<String, dynamic>.from(item),
              ),
            )
            .toList(growable: false),
      );
}

class OfflineConversionData {
  const OfflineConversionData({required this.report, required this.history});

  final OfflineConversionReport report;
  final OfflineConversionHistory history;
}

class GoogleAdsConversionConfig {
  const GoogleAdsConversionConfig({
    required this.canManage,
    required this.configured,
    this.customerId,
    this.loginCustomerId,
    this.conversionActionId,
    this.currencyCode,
  });

  final bool canManage;
  final bool configured;
  final String? customerId;
  final String? loginCustomerId;
  final String? conversionActionId;
  final String? currencyCode;

  factory GoogleAdsConversionConfig.fromJson(Map<String, dynamic> json) =>
      GoogleAdsConversionConfig(
        canManage: json['canManage'] as bool? ?? false,
        configured: json['configured'] as bool? ?? false,
        customerId: json['customerId'] as String?,
        loginCustomerId: json['loginCustomerId'] as String?,
        conversionActionId: json['conversionActionId'] as String?,
        currencyCode: json['currencyCode'] as String?,
      );
}

final googleAdsConversionConfigProvider =
    FutureProvider.family<GoogleAdsConversionConfig, String>((
      ref,
      siteId,
    ) async {
      final response = await ref
          .read(apiProvider)
          .request(
            'GET',
            '/api/v1/sites/$siteId/offline-conversions/google-ads/config',
          );
      return GoogleAdsConversionConfig.fromJson(
        Map<String, dynamic>.from(response as Map),
      );
    });

class MicrosoftAdsGoalMapping {
  const MicrosoftAdsGoalMapping({
    required this.goalId,
    required this.goalName,
    required this.eventName,
  });

  final String goalId;
  final String goalName;
  final String eventName;

  factory MicrosoftAdsGoalMapping.fromJson(Map<String, dynamic> json) =>
      MicrosoftAdsGoalMapping(
        goalId: json['goalId'] as String? ?? '',
        goalName: json['goalName'] as String? ?? 'Goal',
        eventName: json['eventName'] as String? ?? '',
      );
}

class MicrosoftAdsConversionConfig {
  const MicrosoftAdsConversionConfig({
    required this.canManage,
    required this.configured,
    required this.credentialConfigured,
    required this.goalMappings,
    this.tagId,
    this.currencyCode,
  });

  final bool canManage;
  final bool configured;
  final bool credentialConfigured;
  final String? tagId;
  final String? currencyCode;
  final List<MicrosoftAdsGoalMapping> goalMappings;

  MicrosoftAdsGoalMapping? mappingFor(String? goalId) =>
      goalMappings.where((mapping) => mapping.goalId == goalId).firstOrNull;

  factory MicrosoftAdsConversionConfig.fromJson(Map<String, dynamic> json) =>
      MicrosoftAdsConversionConfig(
        canManage: json['canManage'] as bool? ?? false,
        configured: json['configured'] as bool? ?? false,
        credentialConfigured: json['credentialConfigured'] as bool? ?? false,
        tagId: json['tagId'] as String?,
        currencyCode: json['currencyCode'] as String?,
        goalMappings: (json['goalMappings'] as List? ?? const [])
            .whereType<Map>()
            .map(
              (mapping) => MicrosoftAdsGoalMapping.fromJson(
                Map<String, dynamic>.from(mapping),
              ),
            )
            .toList(growable: false),
      );
}

class MicrosoftAdsTransferResult {
  const MicrosoftAdsTransferResult({
    required this.rowsProcessed,
    required this.eventsReceived,
    required this.validationWarnings,
  });

  final int rowsProcessed;
  final int eventsReceived;
  final List<Map<String, dynamic>> validationWarnings;

  factory MicrosoftAdsTransferResult.fromJson(Map<String, dynamic> json) =>
      MicrosoftAdsTransferResult(
        rowsProcessed: (json['rowsProcessed'] as num?)?.toInt() ?? 0,
        eventsReceived: (json['eventsReceived'] as num?)?.toInt() ?? 0,
        validationWarnings: (json['validationWarnings'] as List? ?? const [])
            .whereType<Map>()
            .map(Map<String, dynamic>.from)
            .toList(growable: false),
      );
}

final microsoftAdsConversionConfigProvider =
    FutureProvider.family<MicrosoftAdsConversionConfig, String>((
      ref,
      siteId,
    ) async {
      final response = await ref
          .read(apiProvider)
          .request(
            'GET',
            '/api/v1/sites/$siteId/offline-conversions/microsoft-ads/config',
          );
      return MicrosoftAdsConversionConfig.fromJson(
        Map<String, dynamic>.from(response as Map),
      );
    });

class MetaAdsGoalMapping {
  const MetaAdsGoalMapping({
    required this.goalId,
    required this.goalName,
    required this.eventName,
  });

  final String goalId;
  final String goalName;
  final String eventName;

  factory MetaAdsGoalMapping.fromJson(Map<String, dynamic> json) =>
      MetaAdsGoalMapping(
        goalId: json['goalId'] as String? ?? '',
        goalName: json['goalName'] as String? ?? 'Goal',
        eventName: json['eventName'] as String? ?? '',
      );
}

class MetaAdsConversionConfig {
  const MetaAdsConversionConfig({
    required this.canManage,
    required this.configured,
    required this.credentialConfigured,
    required this.goalMappings,
    this.datasetId,
    this.currencyCode,
  });

  final bool canManage;
  final bool configured;
  final bool credentialConfigured;
  final String? datasetId;
  final String? currencyCode;
  final List<MetaAdsGoalMapping> goalMappings;

  MetaAdsGoalMapping? mappingFor(String? goalId) =>
      goalMappings.where((mapping) => mapping.goalId == goalId).firstOrNull;

  factory MetaAdsConversionConfig.fromJson(
    Map<String, dynamic> json,
  ) => MetaAdsConversionConfig(
    canManage: json['canManage'] as bool? ?? false,
    configured: json['configured'] as bool? ?? false,
    credentialConfigured: json['credentialConfigured'] as bool? ?? false,
    datasetId: json['datasetId'] as String?,
    currencyCode: json['currencyCode'] as String?,
    goalMappings: (json['goalMappings'] as List? ?? const [])
        .whereType<Map>()
        .map(
          (mapping) =>
              MetaAdsGoalMapping.fromJson(Map<String, dynamic>.from(mapping)),
        )
        .toList(growable: false),
  );
}

class MetaAdsTransferResult {
  const MetaAdsTransferResult({
    required this.rowsProcessed,
    required this.eventsReceived,
  });

  final int rowsProcessed;
  final int eventsReceived;

  factory MetaAdsTransferResult.fromJson(Map<String, dynamic> json) =>
      MetaAdsTransferResult(
        rowsProcessed: (json['rowsProcessed'] as num?)?.toInt() ?? 0,
        eventsReceived: (json['eventsReceived'] as num?)?.toInt() ?? 0,
      );
}

final metaAdsConversionConfigProvider =
    FutureProvider.family<MetaAdsConversionConfig, String>((ref, siteId) async {
      final response = await ref
          .read(apiProvider)
          .request(
            'GET',
            '/api/v1/sites/$siteId/offline-conversions/meta-ads/config',
          );
      return MetaAdsConversionConfig.fromJson(
        Map<String, dynamic>.from(response as Map),
      );
    });

class LinkedInAdsGoalMapping {
  const LinkedInAdsGoalMapping({
    required this.goalId,
    required this.goalName,
    required this.conversionUrn,
  });

  final String goalId;
  final String goalName;
  final String conversionUrn;

  factory LinkedInAdsGoalMapping.fromJson(Map<String, dynamic> json) =>
      LinkedInAdsGoalMapping(
        goalId: json['goalId'] as String? ?? '',
        goalName: json['goalName'] as String? ?? 'Goal',
        conversionUrn: json['conversionUrn'] as String? ?? '',
      );
}

class LinkedInAdsConversionConfig {
  const LinkedInAdsConversionConfig({
    required this.canManage,
    required this.configured,
    required this.credentialConfigured,
    required this.goalMappings,
    this.currencyCode,
  });

  final bool canManage;
  final bool configured;
  final bool credentialConfigured;
  final String? currencyCode;
  final List<LinkedInAdsGoalMapping> goalMappings;

  LinkedInAdsGoalMapping? mappingFor(String? goalId) =>
      goalMappings.where((mapping) => mapping.goalId == goalId).firstOrNull;

  factory LinkedInAdsConversionConfig.fromJson(Map<String, dynamic> json) =>
      LinkedInAdsConversionConfig(
        canManage: json['canManage'] as bool? ?? false,
        configured: json['configured'] as bool? ?? false,
        credentialConfigured: json['credentialConfigured'] as bool? ?? false,
        currencyCode: json['currencyCode'] as String?,
        goalMappings: (json['goalMappings'] as List? ?? const [])
            .whereType<Map>()
            .map(
              (mapping) => LinkedInAdsGoalMapping.fromJson(
                Map<String, dynamic>.from(mapping),
              ),
            )
            .toList(growable: false),
      );
}

class LinkedInAdsTransferResult {
  const LinkedInAdsTransferResult({
    required this.rowsProcessed,
    required this.eventsReceived,
  });

  final int rowsProcessed;
  final int eventsReceived;

  factory LinkedInAdsTransferResult.fromJson(Map<String, dynamic> json) =>
      LinkedInAdsTransferResult(
        rowsProcessed: (json['rowsProcessed'] as num?)?.toInt() ?? 0,
        eventsReceived: (json['eventsReceived'] as num?)?.toInt() ?? 0,
      );
}

final linkedInAdsConversionConfigProvider =
    FutureProvider.family<LinkedInAdsConversionConfig, String>((
      ref,
      siteId,
    ) async {
      final response = await ref
          .read(apiProvider)
          .request(
            'GET',
            '/api/v1/sites/$siteId/offline-conversions/linkedin-ads/config',
          );
      return LinkedInAdsConversionConfig.fromJson(
        Map<String, dynamic>.from(response as Map),
      );
    });

final offlineConversionAnalyticsProvider =
    FutureProvider.family<OfflineConversionData, OfflineConversionQuery>((
      ref,
      query,
    ) async {
      final api = ref.read(apiProvider);
      final reportUri = Uri(
        path: '/api/v1/sites/${query.siteId}/analytics/offline-conversions',
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
        api.request('GET', reportUri.toString()),
        api.request(
          'GET',
          '/api/v1/sites/${query.siteId}/offline-conversions/imports',
        ),
      ]);
      return OfflineConversionData(
        report: OfflineConversionReport.fromJson(
          Map<String, dynamic>.from(responses[0] as Map),
        ),
        history: OfflineConversionHistory.fromJson(
          Map<String, dynamic>.from(responses[1] as Map),
        ),
      );
    });
