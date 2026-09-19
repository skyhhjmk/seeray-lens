import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seeray_lens_admin/core/network/seeray_api.dart';
import 'package:seeray_lens_admin/features/auth/application/auth_controller.dart';
import 'package:seeray_lens_admin/features/workspaces/presentation/workspace_diagnostics_page.dart';

void main() {
  testWidgets('renders actionable workspace diagnostics', (tester) async {
    final api = _DiagnosticsApi();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiProvider.overrideWithValue(api)],
        child: const MaterialApp(
          locale: Locale('en'),
          supportedLocales: [Locale('en')],
          home: WorkspaceDiagnosticsPage(workspaceId: 'workspace-1'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('All checks passed'), findsNothing);
    expect(find.text('Review recommended actions'), findsOneWidget);
    expect(find.text('Database connectivity'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Allowed tracker origins'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Allowed tracker origins'), findsOneWidget);
    expect(find.text('Healthy'), findsAtLeastNWidgets(3));
    expect(find.text('Review'), findsOneWidget);
    expect(find.textContaining('Recommended action:'), findsOneWidget);
    expect(api.lastPath, '/api/v1/workspaces/workspace-1/diagnostics');
  });
}

class _DiagnosticsApi extends SeeRayApi {
  _DiagnosticsApi() : super(baseUrl: 'https://lens.example.test');

  String? lastPath;

  @override
  Future<dynamic> request(
    String method,
    String path, {
    Object? body,
    bool retried = false,
  }) async {
    lastPath = path;
    return {
      'overallStatus': 'warning',
      'checkedAt': '2026-09-19T08:40:00Z',
      'checks': [
        {
          'key': 'database',
          'status': 'pass',
          'title': 'Database connectivity',
          'detail': 'Database query succeeded.',
          'remediation': null,
        },
        {
          'key': 'sites',
          'status': 'pass',
          'title': 'Workspace sites',
          'detail': '1 site is configured.',
          'remediation': null,
        },
        {
          'key': 'tracking',
          'status': 'pass',
          'title': 'Tracking availability',
          'detail': '1 of 1 sites have tracking enabled.',
          'remediation': null,
        },
        {
          'key': 'origins',
          'status': 'warning',
          'title': 'Allowed tracker origins',
          'detail': '1 site has no enabled tracker origin.',
          'remediation': 'Add an HTTPS host.',
        },
        {
          'key': 'retention',
          'status': 'pass',
          'title': 'Retention policy',
          'detail': 'Retention is consistent.',
          'remediation': null,
        },
        {
          'key': 'release',
          'status': 'pass',
          'title': 'Release and migrations',
          'detail': 'Release development is running.',
          'remediation': null,
        },
      ],
    };
  }
}
