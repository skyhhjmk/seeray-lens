import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seeray_lens_admin/core/network/seeray_api.dart';
import 'package:seeray_lens_admin/features/analytics/presentation/scheduled_reports_page.dart';
import 'package:seeray_lens_admin/features/auth/application/auth_controller.dart';

void main() {
  testWidgets('shows delivery configuration and saved report state', (
    tester,
  ) async {
    final api = _ScheduledReportsApi();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiProvider.overrideWithValue(api)],
        child: const MaterialApp(
          home: ScheduledReportsPage(siteId: 'site-1', embedded: true),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(api.lastPath, '/api/v1/sites/site-1/scheduled-reports');
    expect(find.text('Email delivery is not configured'), findsOneWidget);
    expect(find.textContaining('SEERAY_SMTP_HOST'), findsOneWidget);
    expect(find.textContaining('Every Monday at 09:30'), findsOneWidget);
    expect(find.textContaining('analyst@example.test'), findsOneWidget);
    expect(find.textContaining('Delivery failed.'), findsOneWidget);

    await tester.tap(find.byTooltip('Report actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pause'));
    await tester.pumpAndSettle();

    expect(api.updatedEnabled, isFalse);
    expect(find.text('Paused'), findsOneWidget);
  });

  testWidgets('opens a visual report editor without exposing cron input', (
    tester,
  ) async {
    final api = _ScheduledReportsApi()..reports = [];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiProvider.overrideWithValue(api)],
        child: const MaterialApp(
          home: ScheduledReportsPage(siteId: 'site-1', embedded: true),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('New report'));
    await tester.pumpAndSettle();

    expect(find.text('Create scheduled report'), findsOneWidget);
    expect(find.text('Frequency'), findsOneWidget);
    expect(find.text('Include report sections'), findsOneWidget);
    expect(find.text('Schedule active'), findsOneWidget);
    expect(find.text('Cron expression'), findsNothing);
  });
}

class _ScheduledReportsApi extends SeeRayApi {
  _ScheduledReportsApi() : super(baseUrl: 'https://lens.example.test');

  String? lastPath;
  bool? updatedEnabled;
  List<Map<String, Object?>> reports = [
    {
      'id': '00000000-0000-0000-0000-000000000001',
      'name': 'Monday summary',
      'frequency': 'weekly',
      'weekday': 'MON',
      'monthDay': null,
      'localTime': '09:30:00',
      'timezone': 'Asia/Shanghai',
      'recipients': ['analyst@example.test'],
      'sections': ['overview', 'pages'],
      'enabled': true,
      'lastRunAt': '2026-09-17T01:02:03Z',
      'lastRunLocal': '2026-09-17 09:02',
      'lastRunStatus': 'failed',
      'lastRunPeriod': null,
      'lastRunMessage':
          'Delivery failed. Verify server SMTP connectivity and sender settings.',
      'nextRunLocal': '2026-09-21 09:30',
      'nextRunAt': '2026-09-21T01:30:00Z',
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
        'canManage': true,
        'timezone': 'Asia/Shanghai',
        'reports': reports,
      };
    }
    if (method == 'PUT') {
      updatedEnabled = (body! as Map<String, Object?>)['enabled'] as bool;
      reports = [
        {...reports.single, 'enabled': updatedEnabled, 'nextRunAt': null},
      ];
      return reports.single;
    }
    throw StateError('Unexpected request: $method $path');
  }
}
