import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';

class ScheduledAnalyticsReport {
  const ScheduledAnalyticsReport({
    required this.id,
    required this.name,
    required this.frequency,
    required this.weekday,
    required this.monthDay,
    required this.localTime,
    required this.timezone,
    required this.recipients,
    required this.sections,
    required this.enabled,
    required this.lastRunAt,
    required this.lastRunLocal,
    required this.lastRunStatus,
    required this.lastRunPeriod,
    required this.lastRunMessage,
    required this.nextRunLocal,
    required this.nextRunAt,
  });

  final String id;
  final String name;
  final String frequency;
  final String? weekday;
  final int? monthDay;
  final String localTime;
  final String timezone;
  final List<String> recipients;
  final List<String> sections;
  final bool enabled;
  final DateTime? lastRunAt;
  final String? lastRunLocal;
  final String? lastRunStatus;
  final String? lastRunPeriod;
  final String? lastRunMessage;
  final String? nextRunLocal;
  final DateTime? nextRunAt;

  factory ScheduledAnalyticsReport.fromJson(Map<String, dynamic> json) =>
      ScheduledAnalyticsReport(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        frequency: json['frequency'] as String? ?? 'weekly',
        weekday: json['weekday'] as String?,
        monthDay: (json['monthDay'] as num?)?.toInt(),
        localTime: json['localTime'] as String? ?? '09:00:00',
        timezone: json['timezone'] as String? ?? 'UTC',
        recipients: (json['recipients'] as List? ?? const []).cast<String>(),
        sections: (json['sections'] as List? ?? const []).cast<String>(),
        enabled: json['enabled'] as bool? ?? false,
        lastRunAt: _date(json['lastRunAt']),
        lastRunLocal: json['lastRunLocal'] as String?,
        lastRunStatus: json['lastRunStatus'] as String?,
        lastRunPeriod: json['lastRunPeriod'] as String?,
        lastRunMessage: json['lastRunMessage'] as String?,
        nextRunLocal: json['nextRunLocal'] as String?,
        nextRunAt: _date(json['nextRunAt']),
      );

  static DateTime? _date(Object? value) =>
      value is String ? DateTime.tryParse(value)?.toLocal() : null;
}

class ScheduledReportsState {
  const ScheduledReportsState({
    required this.emailEnabled,
    required this.canManage,
    required this.timezone,
    required this.reports,
  });

  final bool emailEnabled;
  final bool canManage;
  final String timezone;
  final List<ScheduledAnalyticsReport> reports;

  factory ScheduledReportsState.fromJson(Map<String, dynamic> json) =>
      ScheduledReportsState(
        emailEnabled: json['emailEnabled'] as bool? ?? false,
        canManage: json['canManage'] as bool? ?? false,
        timezone: json['timezone'] as String? ?? 'UTC',
        reports: (json['reports'] as List? ?? const [])
            .whereType<Map>()
            .map(
              (report) => ScheduledAnalyticsReport.fromJson(
                Map<String, dynamic>.from(report),
              ),
            )
            .toList(growable: false),
      );
}

final scheduledReportsRepositoryProvider = Provider(
  (ref) => ScheduledReportsRepository(ref),
);

final scheduledReportsProvider =
    FutureProvider.family<ScheduledReportsState, String>(
      (ref, siteId) =>
          ref.read(scheduledReportsRepositoryProvider).load(siteId),
    );

class ScheduledReportsRepository {
  ScheduledReportsRepository(this.ref);
  final Ref ref;

  Future<ScheduledReportsState> load(String siteId) async {
    final response = await ref.read(apiProvider).request('GET', _path(siteId));
    if (response is! Map) {
      throw const FormatException('Invalid scheduled reports response');
    }
    return ScheduledReportsState.fromJson(Map<String, dynamic>.from(response));
  }

  Future<ScheduledAnalyticsReport> save({
    required String siteId,
    String? reportId,
    required Map<String, Object?> values,
  }) async {
    final response = await ref
        .read(apiProvider)
        .request(
          reportId == null ? 'POST' : 'PUT',
          reportId == null ? _path(siteId) : '${_path(siteId)}/$reportId',
          body: values,
        );
    if (response is! Map) {
      throw const FormatException('Invalid scheduled report response');
    }
    return ScheduledAnalyticsReport.fromJson(
      Map<String, dynamic>.from(response),
    );
  }

  Future<void> delete(String siteId, String reportId) async {
    await ref.read(apiProvider).request('DELETE', '${_path(siteId)}/$reportId');
  }

  Future<ScheduledAnalyticsReport> sendNow(
    String siteId,
    String reportId,
  ) async {
    final response = await ref
        .read(apiProvider)
        .request('POST', '${_path(siteId)}/$reportId/send-now');
    if (response is! Map) {
      throw const FormatException('Invalid scheduled report response');
    }
    return ScheduledAnalyticsReport.fromJson(
      Map<String, dynamic>.from(response),
    );
  }

  String _path(String siteId) => '/api/v1/sites/$siteId/scheduled-reports';
}
