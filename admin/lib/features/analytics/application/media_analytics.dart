import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import 'analytics_controller.dart';

class MediaAnalyticsQuery {
  const MediaAnalyticsQuery({
    required this.siteId,
    required this.range,
    this.segmentId,
  });

  final String siteId;
  final AnalyticsDateRange range;
  final String? segmentId;

  @override
  bool operator ==(Object other) =>
      other is MediaAnalyticsQuery &&
      other.siteId == siteId &&
      other.segmentId == segmentId &&
      other.range.fromQuery == range.fromQuery &&
      other.range.toQuery == range.toQuery;

  @override
  int get hashCode =>
      Object.hash(siteId, segmentId, range.fromQuery, range.toQuery);
}

class MediaAnalyticsRow {
  const MediaAnalyticsRow({
    required this.mediaId,
    required this.mediaType,
    required this.pagePath,
    required this.starts,
    required this.reached25,
    required this.reached50,
    required this.reached75,
    required this.reached90,
    required this.completions,
    required this.incompleteSessions,
    required this.uniqueVisitors,
    required this.averageDurationSeconds,
    required this.completionRate,
  });

  final String mediaId;
  final String mediaType;
  final String pagePath;
  final int starts;
  final int reached25;
  final int reached50;
  final int reached75;
  final int reached90;
  final int completions;
  final int incompleteSessions;
  final int uniqueVisitors;
  final int averageDurationSeconds;
  final double completionRate;

  factory MediaAnalyticsRow.fromJson(Map<String, dynamic> json) =>
      MediaAnalyticsRow(
        mediaId: json['mediaId'] as String? ?? '',
        mediaType: json['mediaType'] as String? ?? 'video',
        pagePath: json['pagePath'] as String? ?? '/',
        starts: (json['starts'] as num?)?.toInt() ?? 0,
        reached25: (json['reached25'] as num?)?.toInt() ?? 0,
        reached50: (json['reached50'] as num?)?.toInt() ?? 0,
        reached75: (json['reached75'] as num?)?.toInt() ?? 0,
        reached90: (json['reached90'] as num?)?.toInt() ?? 0,
        completions: (json['completions'] as num?)?.toInt() ?? 0,
        incompleteSessions: (json['incompleteSessions'] as num?)?.toInt() ?? 0,
        uniqueVisitors: (json['uniqueVisitors'] as num?)?.toInt() ?? 0,
        averageDurationSeconds:
            (json['averageDurationSeconds'] as num?)?.toInt() ?? 0,
        completionRate: (json['completionRate'] as num?)?.toDouble() ?? 0,
      );
}

class MediaAnalyticsReport {
  const MediaAnalyticsReport({
    required this.from,
    required this.to,
    required this.rows,
    required this.hasMore,
  });

  final String from;
  final String to;
  final List<MediaAnalyticsRow> rows;
  final bool hasMore;

  factory MediaAnalyticsReport.fromJson(Map<String, dynamic> json) =>
      MediaAnalyticsReport(
        from: json['from'] as String? ?? '',
        to: json['to'] as String? ?? '',
        rows: (json['rows'] as List? ?? const [])
            .whereType<Map>()
            .map(
              (item) =>
                  MediaAnalyticsRow.fromJson(Map<String, dynamic>.from(item)),
            )
            .toList(growable: false),
        hasMore: json['hasMore'] as bool? ?? false,
      );
}

final mediaAnalyticsProvider =
    FutureProvider.family<MediaAnalyticsReport, MediaAnalyticsQuery>((
      ref,
      query,
    ) async {
      final uri = Uri(
        path: '/api/v1/sites/${query.siteId}/analytics/media',
        queryParameters: {
          'from': query.range.fromQuery,
          'to': query.range.toQuery,
          if (query.segmentId != null) 'segmentId': query.segmentId!,
        },
      );
      final response =
          await ref.read(apiProvider).request('GET', uri.toString()) as Map;
      return MediaAnalyticsReport.fromJson(Map<String, dynamic>.from(response));
    });
