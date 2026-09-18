import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import 'analytics_csv.dart';
import 'analytics_controller.dart';

const campaignCostCsvHeaders = <String>[
  'date',
  'platform',
  'source',
  'medium',
  'campaign',
  'currency',
  'cost',
  'clicks',
  'impressions',
];

const campaignCostPlatforms = <String>{
  'google_ads',
  'microsoft_ads',
  'meta_ads',
  'tiktok_ads',
  'linkedin_ads',
  'x_ads',
  'other',
};

class CampaignCostImportRow {
  const CampaignCostImportRow({
    required this.date,
    required this.platform,
    required this.source,
    required this.medium,
    required this.campaign,
    required this.currency,
    required this.cost,
    required this.clicks,
    required this.impressions,
  });

  final String date;
  final String platform;
  final String source;
  final String medium;
  final String campaign;
  final String currency;
  final String cost;
  final int clicks;
  final int impressions;

  Map<String, Object> toJson() => {
    'date': date,
    'platform': platform,
    'source': source,
    'medium': medium,
    'campaign': campaign,
    'currency': currency,
    'cost': cost,
    'clicks': clicks,
    'impressions': impressions,
  };
}

class CampaignCostImportPreview {
  const CampaignCostImportPreview(this.rows);

  static const maximumRows = 5000;
  static const maximumBytes = 2 * 1024 * 1024;

  final List<CampaignCostImportRow> rows;

  int get clicks => rows.fold(0, (sum, row) => sum + row.clicks);
  int get impressions => rows.fold(0, (sum, row) => sum + row.impressions);
  Set<String> get currencies => rows.map((row) => row.currency).toSet();
  String get firstDate =>
      rows.map((row) => row.date).reduce((a, b) => a.compareTo(b) < 0 ? a : b);
  String get lastDate =>
      rows.map((row) => row.date).reduce((a, b) => a.compareTo(b) > 0 ? a : b);

  factory CampaignCostImportPreview.parse(String input) {
    final records = parseAnalyticsCsvRecords(input.replaceFirst('\uFEFF', ''));
    if (records.isEmpty) throw const FormatException('The CSV file is empty.');
    final headers = records.first
        .map((value) => value.trim().toLowerCase())
        .toList();
    if (headers.toSet().length != campaignCostCsvHeaders.length ||
        headers.toSet().difference(campaignCostCsvHeaders.toSet()).isNotEmpty ||
        campaignCostCsvHeaders.toSet().difference(headers.toSet()).isNotEmpty) {
      throw const FormatException(
        'Use the supplied template with date, platform, source, medium, campaign, currency, cost, clicks, and impressions columns.',
      );
    }
    if (records.length < 2) {
      throw const FormatException(
        'Add at least one campaign row below the header.',
      );
    }
    if (records.length - 1 > maximumRows) {
      throw FormatException('A file can contain at most $maximumRows rows.');
    }
    final columns = {for (var i = 0; i < headers.length; i++) headers[i]: i};
    final result = <CampaignCostImportRow>[];
    final seen = <String>{};
    for (var recordIndex = 1; recordIndex < records.length; recordIndex++) {
      final line = recordIndex + 1;
      final cells = records[recordIndex];
      if (cells.length != headers.length) {
        throw FormatException(
          'Row $line must contain exactly ${headers.length} columns.',
        );
      }
      String cell(String name) => cells[columns[name]!].trim();
      final date = cell('date');
      final parsedDate = DateTime.tryParse(date);
      if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date) ||
          parsedDate == null ||
          _formatDate(parsedDate) != date) {
        throw FormatException(
          'Row $line: date must use a real YYYY-MM-DD date.',
        );
      }
      final platform = cell('platform').toLowerCase();
      if (!campaignCostPlatforms.contains(platform)) {
        throw FormatException(
          'Row $line: use a supported platform key such as google_ads.',
        );
      }
      final source = _requiredCell(
        cells,
        columns['source']!,
        'source',
        line,
        128,
      );
      final medium = _requiredCell(
        cells,
        columns['medium']!,
        'medium',
        line,
        128,
      );
      final campaign = _requiredCell(
        cells,
        columns['campaign']!,
        'campaign',
        line,
        256,
      );
      final currency = cell('currency').toUpperCase();
      if (!RegExp(r'^[A-Z]{3}$').hasMatch(currency)) {
        throw FormatException(
          'Row $line: currency must be a 3-letter ISO code such as USD.',
        );
      }
      final cost = cell('cost');
      if (!RegExp(r'^\d{1,12}(?:\.\d{1,6})?$').hasMatch(cost)) {
        throw FormatException(
          'Row $line: cost must be non-negative with up to 6 decimals.',
        );
      }
      final clicks = _nonNegativeInt(cell('clicks'), 'clicks', line);
      final impressions = _nonNegativeInt(
        cell('impressions'),
        'impressions',
        line,
      );
      final key =
          '$date\u001f$platform\u001f$source\u001f$medium\u001f$campaign\u001f$currency';
      if (!seen.add(key)) {
        throw FormatException(
          'Row $line repeats the same date and campaign dimensions.',
        );
      }
      result.add(
        CampaignCostImportRow(
          date: date,
          platform: platform,
          source: source,
          medium: medium,
          campaign: campaign,
          currency: currency,
          cost: cost,
          clicks: clicks,
          impressions: impressions,
        ),
      );
    }
    return CampaignCostImportPreview(List.unmodifiable(result));
  }
}

String _requiredCell(
  List<String> cells,
  int index,
  String name,
  int row,
  int maximum,
) {
  final value = cells[index].trim();
  if (value.isEmpty ||
      value.length > maximum ||
      value.contains(RegExp(r'[\x00-\x1f\x7f]'))) {
    throw FormatException(
      'Row $row: $name is required and must be at most $maximum characters.',
    );
  }
  return value;
}

int _nonNegativeInt(String value, String name, int row) {
  final parsed = int.tryParse(value);
  if (parsed == null || parsed < 0 || parsed > 1000000000000) {
    throw FormatException(
      'Row $row: $name must be a non-negative whole number.',
    );
  }
  return parsed;
}

String _formatDate(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

class CampaignCostQuery {
  const CampaignCostQuery({
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
      other is CampaignCostQuery &&
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

class CampaignCostRow {
  const CampaignCostRow({
    required this.platform,
    required this.source,
    required this.medium,
    required this.campaign,
    required this.currency,
    required this.impressions,
    required this.clicks,
    required this.cost,
    required this.sessions,
    required this.attributedConversions,
    required this.attributedGoalValue,
    this.costPerClick,
    this.costPerAttributedConversion,
    this.goalValuePerSpend,
  });

  final String platform;
  final String source;
  final String medium;
  final String campaign;
  final String currency;
  final int impressions;
  final int clicks;
  final double cost;
  final int sessions;
  final double attributedConversions;
  final double attributedGoalValue;
  final double? costPerClick;
  final double? costPerAttributedConversion;
  final double? goalValuePerSpend;

  factory CampaignCostRow.fromJson(Map<String, dynamic> json) =>
      CampaignCostRow(
        platform: json['platform'] as String? ?? 'other',
        source: json['source'] as String? ?? '',
        medium: json['medium'] as String? ?? '',
        campaign: json['campaign'] as String? ?? '',
        currency: json['currency'] as String? ?? 'USD',
        impressions: (json['impressions'] as num?)?.toInt() ?? 0,
        clicks: (json['clicks'] as num?)?.toInt() ?? 0,
        cost: (json['cost'] as num?)?.toDouble() ?? 0,
        sessions: (json['sessions'] as num?)?.toInt() ?? 0,
        attributedConversions:
            (json['attributedConversions'] as num?)?.toDouble() ?? 0,
        attributedGoalValue:
            (json['attributedGoalValue'] as num?)?.toDouble() ?? 0,
        costPerClick: (json['costPerClick'] as num?)?.toDouble(),
        costPerAttributedConversion:
            (json['costPerAttributedConversion'] as num?)?.toDouble(),
        goalValuePerSpend: (json['goalValuePerSpend'] as num?)?.toDouble(),
      );
}

class CampaignCostReport {
  const CampaignCostReport({
    required this.from,
    required this.to,
    required this.model,
    required this.lookbackDays,
    required this.rows,
  });

  final String from;
  final String to;
  final String model;
  final int lookbackDays;
  final List<CampaignCostRow> rows;

  factory CampaignCostReport.fromJson(Map<String, dynamic> json) =>
      CampaignCostReport(
        from: json['from'] as String? ?? '',
        to: json['to'] as String? ?? '',
        model: json['model'] as String? ?? 'last_touch',
        lookbackDays: (json['lookbackDays'] as num?)?.toInt() ?? 30,
        rows: (json['rows'] as List? ?? const [])
            .whereType<Map>()
            .map(
              (row) => CampaignCostRow.fromJson(Map<String, dynamic>.from(row)),
            )
            .toList(growable: false),
      );
}

class CampaignCostImportBatch {
  const CampaignCostImportBatch({
    required this.id,
    required this.fileName,
    required this.rowCount,
    required this.importedAt,
  });

  final String id;
  final String fileName;
  final int rowCount;
  final DateTime importedAt;

  factory CampaignCostImportBatch.fromJson(Map<String, dynamic> json) =>
      CampaignCostImportBatch(
        id: json['id'] as String? ?? '',
        fileName: json['fileName'] as String? ?? '',
        rowCount: (json['rowCount'] as num?)?.toInt() ?? 0,
        importedAt:
            DateTime.tryParse(json['importedAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );
}

class CampaignCostHistory {
  const CampaignCostHistory({
    required this.canManage,
    required this.timezone,
    required this.imports,
  });

  final bool canManage;
  final String timezone;
  final List<CampaignCostImportBatch> imports;

  factory CampaignCostHistory.fromJson(
    Map<String, dynamic> json,
  ) => CampaignCostHistory(
    canManage: json['canManage'] as bool? ?? false,
    timezone: json['timezone'] as String? ?? 'UTC',
    imports: (json['imports'] as List? ?? const [])
        .whereType<Map>()
        .map(
          (item) =>
              CampaignCostImportBatch.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList(growable: false),
  );
}

class CampaignCostData {
  const CampaignCostData({required this.report, required this.history});

  final CampaignCostReport report;
  final CampaignCostHistory history;
}

final campaignCostAnalyticsProvider =
    FutureProvider.family<CampaignCostData, CampaignCostQuery>((
      ref,
      query,
    ) async {
      final api = ref.read(apiProvider);
      final base = '/api/v1/sites/${query.siteId}/analytics/campaign-costs';
      final reportPath = Uri(
        path: base,
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
        api.request('GET', reportPath.toString()),
        api.request('GET', '$base/imports'),
      ]);
      return CampaignCostData(
        report: CampaignCostReport.fromJson(
          Map<String, dynamic>.from(responses[0] as Map),
        ),
        history: CampaignCostHistory.fromJson(
          Map<String, dynamic>.from(responses[1] as Map),
        ),
      );
    });
