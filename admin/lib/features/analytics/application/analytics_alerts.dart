import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';

class AnalyticsAlert {
  const AnalyticsAlert({
    required this.id,
    required this.name,
    required this.metric,
    required this.direction,
    required this.baseline,
    required this.thresholdPercent,
    required this.localTime,
    required this.timezone,
    required this.channels,
    required this.recipients,
    required this.enabled,
    required this.lastEvaluatedDate,
    required this.lastEvaluatedAt,
    required this.lastStatus,
    required this.lastMessage,
    required this.lastValue,
    required this.lastChangePercent,
    required this.lastBaselineDate,
    required this.nextRunLocal,
    required this.nextRunAt,
  });

  final String id;
  final String name;
  final String metric;
  final String direction;
  final String baseline;
  final double thresholdPercent;
  final String localTime;
  final String timezone;
  final List<String> channels;
  final List<String> recipients;
  final bool enabled;
  final String? lastEvaluatedDate;
  final DateTime? lastEvaluatedAt;
  final String? lastStatus;
  final String? lastMessage;
  final double? lastValue;
  final double? lastChangePercent;
  final String? lastBaselineDate;
  final String? nextRunLocal;
  final DateTime? nextRunAt;

  factory AnalyticsAlert.fromJson(Map<String, dynamic> json) => AnalyticsAlert(
    id: json['id'] as String,
    name: json['name'] as String? ?? '',
    metric: json['metric'] as String? ?? 'visitors',
    direction: json['direction'] as String? ?? 'increase',
    baseline: json['baseline'] as String? ?? 'previous_day',
    thresholdPercent: (json['thresholdPercent'] as num? ?? 20).toDouble(),
    localTime: json['localTime'] as String? ?? '09:00:00',
    timezone: json['timezone'] as String? ?? 'UTC',
    channels: (json['channels'] as List? ?? const []).cast<String>(),
    recipients: (json['recipients'] as List? ?? const []).cast<String>(),
    enabled: json['enabled'] as bool? ?? false,
    lastEvaluatedDate: json['lastEvaluatedDate'] as String?,
    lastEvaluatedAt: _date(json['lastEvaluatedAt']),
    lastStatus: json['lastStatus'] as String?,
    lastMessage: json['lastMessage'] as String?,
    lastValue: (json['lastValue'] as num?)?.toDouble(),
    lastChangePercent: (json['lastChangePercent'] as num?)?.toDouble(),
    lastBaselineDate: json['lastBaselineDate'] as String?,
    nextRunLocal: json['nextRunLocal'] as String?,
    nextRunAt: _date(json['nextRunAt']),
  );

  static DateTime? _date(Object? value) =>
      value is String ? DateTime.tryParse(value)?.toLocal() : null;
}

class AnalyticsAlertsState {
  const AnalyticsAlertsState({
    required this.emailEnabled,
    required this.slackEnabled,
    required this.teamsEnabled,
    required this.canManage,
    required this.timezone,
    required this.alerts,
  });

  final bool emailEnabled;
  final bool slackEnabled;
  final bool teamsEnabled;
  final bool canManage;
  final String timezone;
  final List<AnalyticsAlert> alerts;

  factory AnalyticsAlertsState.fromJson(Map<String, dynamic> json) =>
      AnalyticsAlertsState(
        emailEnabled: json['emailEnabled'] as bool? ?? false,
        slackEnabled: json['slackEnabled'] as bool? ?? false,
        teamsEnabled: json['teamsEnabled'] as bool? ?? false,
        canManage: json['canManage'] as bool? ?? false,
        timezone: json['timezone'] as String? ?? 'UTC',
        alerts: (json['alerts'] as List? ?? const [])
            .whereType<Map>()
            .map(
              (item) =>
                  AnalyticsAlert.fromJson(Map<String, dynamic>.from(item)),
            )
            .toList(growable: false),
      );
}

final analyticsAlertsRepositoryProvider = Provider(
  (ref) => AnalyticsAlertsRepository(ref),
);

final analyticsAlertsProvider =
    FutureProvider.family<AnalyticsAlertsState, String>(
      (ref, siteId) => ref.read(analyticsAlertsRepositoryProvider).load(siteId),
    );

class AnalyticsAlertsRepository {
  AnalyticsAlertsRepository(this.ref);
  final Ref ref;

  Future<AnalyticsAlertsState> load(String siteId) async {
    final response = await ref.read(apiProvider).request('GET', _path(siteId));
    if (response is! Map) {
      throw const FormatException('Invalid analytics alerts response');
    }
    return AnalyticsAlertsState.fromJson(Map<String, dynamic>.from(response));
  }

  Future<AnalyticsAlert> save({
    required String siteId,
    String? alertId,
    required Map<String, Object?> values,
  }) async {
    final response = await ref
        .read(apiProvider)
        .request(
          alertId == null ? 'POST' : 'PUT',
          alertId == null ? _path(siteId) : '${_path(siteId)}/$alertId',
          body: values,
        );
    if (response is! Map) {
      throw const FormatException('Invalid analytics alert response');
    }
    return AnalyticsAlert.fromJson(Map<String, dynamic>.from(response));
  }

  Future<void> delete(String siteId, String alertId) async {
    await ref.read(apiProvider).request('DELETE', '${_path(siteId)}/$alertId');
  }

  String _path(String siteId) => '/api/v1/sites/$siteId/analytics-alerts';
}
