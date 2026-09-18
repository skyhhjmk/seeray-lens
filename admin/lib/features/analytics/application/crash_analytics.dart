import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import 'analytics_controller.dart';

class CrashAnalyticsQuery {
  const CrashAnalyticsQuery({required this.siteId, required this.range});

  final String siteId;
  final AnalyticsDateRange range;

  @override
  bool operator ==(Object other) =>
      other is CrashAnalyticsQuery &&
      other.siteId == siteId &&
      other.range.fromQuery == range.fromQuery &&
      other.range.toQuery == range.toQuery;

  @override
  int get hashCode => Object.hash(siteId, range.fromQuery, range.toQuery);
}

class CrashIssue {
  const CrashIssue({
    required this.fingerprint,
    required this.errorName,
    required this.message,
    required this.sourcePath,
    required this.line,
    required this.column,
    required this.functionName,
    required this.occurrences,
    required this.affectedPages,
    required this.browsers,
    required this.firstSeen,
    required this.lastSeen,
  });

  final String fingerprint;
  final String errorName;
  final String message;
  final String sourcePath;
  final int? line;
  final int? column;
  final String? functionName;
  final int occurrences;
  final int affectedPages;
  final String browsers;
  final DateTime? firstSeen;
  final DateTime? lastSeen;

  factory CrashIssue.fromJson(Map<String, dynamic> json) => CrashIssue(
    fingerprint: json['fingerprint'] as String? ?? '',
    errorName: json['errorName'] as String? ?? 'Error',
    message: json['message'] as String? ?? '',
    sourcePath: json['sourcePath'] as String? ?? '/',
    line: (json['line'] as num?)?.toInt(),
    column: (json['column'] as num?)?.toInt(),
    functionName: json['functionName'] as String?,
    occurrences: (json['occurrences'] as num?)?.toInt() ?? 0,
    affectedPages: (json['affectedPages'] as num?)?.toInt() ?? 0,
    browsers: json['browsers'] as String? ?? 'Other',
    firstSeen: DateTime.tryParse(json['firstSeen'] as String? ?? ''),
    lastSeen: DateTime.tryParse(json['lastSeen'] as String? ?? ''),
  );
}

class CrashAnalyticsReport {
  const CrashAnalyticsReport({
    required this.from,
    required this.to,
    required this.occurrences,
    required this.issueCount,
    required this.rows,
    required this.hasMore,
  });

  final String from;
  final String to;
  final int occurrences;
  final int issueCount;
  final List<CrashIssue> rows;
  final bool hasMore;

  factory CrashAnalyticsReport.fromJson(Map<String, dynamic> json) =>
      CrashAnalyticsReport(
        from: json['from'] as String? ?? '',
        to: json['to'] as String? ?? '',
        occurrences: (json['occurrences'] as num?)?.toInt() ?? 0,
        issueCount: (json['issueCount'] as num?)?.toInt() ?? 0,
        rows: (json['rows'] as List? ?? const [])
            .whereType<Map>()
            .map((item) => CrashIssue.fromJson(Map<String, dynamic>.from(item)))
            .toList(growable: false),
        hasMore: json['hasMore'] as bool? ?? false,
      );
}

final crashAnalyticsProvider =
    FutureProvider.family<CrashAnalyticsReport, CrashAnalyticsQuery>((
      ref,
      query,
    ) async {
      final uri = Uri(
        path: '/api/v1/sites/${query.siteId}/analytics/crashes',
        queryParameters: {
          'from': query.range.fromQuery,
          'to': query.range.toQuery,
        },
      );
      final response =
          await ref.read(apiProvider).request('GET', uri.toString()) as Map;
      return CrashAnalyticsReport.fromJson(Map<String, dynamic>.from(response));
    });
