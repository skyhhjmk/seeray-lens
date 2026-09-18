import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seeray_lens_admin/core/network/seeray_api.dart';
import 'package:seeray_lens_admin/features/analytics/presentation/analytics_alerts_page.dart';
import 'package:seeray_lens_admin/features/auth/application/auth_controller.dart';

void main() {
  testWidgets('shows alert status and offers a visual editor without secrets', (
    tester,
  ) async {
    final api = _AlertsApi();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiProvider.overrideWithValue(api)],
        child: const MaterialApp(
          home: AnalyticsAlertsPage(siteId: 'site-1', embedded: true),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(api.lastPath, '/api/v1/sites/site-1/analytics-alerts');
    expect(find.text('Available delivery channels'), findsOneWidget);
    expect(find.text('Visitors dropped 25%'), findsOneWidget);
    expect(find.textContaining('Next check 2026-09-18 09:00'), findsOneWidget);

    await tester.tap(find.text('New alert'));
    await tester.pumpAndSettle();
    expect(find.text('New analytics alert'), findsOneWidget);
    expect(find.text('Metric'), findsOneWidget);
    expect(find.text('Compare with'), findsOneWidget);
    expect(find.text('Threshold (%)'), findsOneWidget);
    expect(find.text('Cron expression'), findsNothing);
    expect(find.textContaining('hooks.slack.com'), findsNothing);
  });

  testWidgets('saves configured channel selections through the typed editor', (
    tester,
  ) async {
    final api = _AlertsApi()..alerts = [];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiProvider.overrideWithValue(api)],
        child: const MaterialApp(
          home: AnalyticsAlertsPage(siteId: 'site-1', embedded: true),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('New alert'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'Traffic rise');
    await tester.ensureVisible(find.text('Save alert'));
    await tester.tap(find.text('Save alert'));
    await tester.pumpAndSettle();

    expect(api.savedValues?['name'], 'Traffic rise');
    expect(api.savedValues?['channels'], ['slack']);
    expect(api.savedValues?['enabled'], isTrue);
  });
}

class _AlertsApi extends SeeRayApi {
  _AlertsApi() : super(baseUrl: 'https://lens.example.test');

  String? lastPath;
  Map<String, Object?>? savedValues;
  List<Map<String, Object?>> alerts = [
    {
      'id': '00000000-0000-0000-0000-000000000001',
      'name': 'Visitors dropped 25%',
      'metric': 'visitors',
      'direction': 'decrease',
      'baseline': 'same_weekday_last_week',
      'thresholdPercent': 25,
      'localTime': '09:00:00',
      'timezone': 'Asia/Shanghai',
      'channels': ['slack'],
      'recipients': [],
      'enabled': true,
      'lastEvaluatedDate': '2026-09-16',
      'lastEvaluatedAt': '2026-09-17T01:00:00Z',
      'lastStatus': 'triggered',
      'lastMessage': 'Threshold crossed.',
      'lastValue': 75,
      'lastChangePercent': -25,
      'lastBaselineDate': '2026-09-09',
      'nextRunLocal': '2026-09-18 09:00',
      'nextRunAt': '2026-09-18T01:00:00Z',
    },
  ];

  @override
  Future<dynamic> request(
    String method,
    String path, {
    Object? body,
    bool retried = false,
  }) async {
    lastPath = path;
    if (method == 'GET') {
      return {
        'emailEnabled': false,
        'slackEnabled': true,
        'teamsEnabled': false,
        'canManage': true,
        'timezone': 'Asia/Shanghai',
        'alerts': alerts,
      };
    }
    if (method == 'POST') {
      savedValues = Map<String, Object?>.from(body! as Map);
      return {
        'id': '00000000-0000-0000-0000-000000000002',
        ...savedValues!,
        'timezone': 'Asia/Shanghai',
        'channels': savedValues!['channels'],
        'recipients': savedValues!['recipients'],
        'lastEvaluatedDate': null,
        'lastEvaluatedAt': null,
        'lastStatus': null,
        'lastMessage': null,
        'lastValue': null,
        'lastChangePercent': null,
        'lastBaselineDate': null,
        'nextRunLocal': '2026-09-18 09:00',
        'nextRunAt': '2026-09-18T01:00:00Z',
      };
    }
    throw StateError('Unexpected request: $method $path');
  }
}
