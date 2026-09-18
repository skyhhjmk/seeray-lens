import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seeray_lens_admin/core/network/seeray_api.dart';
import 'package:seeray_lens_admin/features/auth/application/auth_controller.dart';
import 'package:seeray_lens_admin/features/workspaces/presentation/workspace_rollup_page.dart';

void main() {
  testWidgets('shows a usable multi-site comparison and honest visitor scope', (
    tester,
  ) async {
    final api = _RollupApi();
    final container = ProviderContainer(
      overrides: [apiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: WorkspaceRollupPage(workspaceId: 'workspace-1'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Workspace roll-up'), findsOneWidget);
    expect(find.text('Traffic trend'), findsOneWidget);
    expect(find.text('Site comparison'), findsOneWidget);
    expect(find.text('Acquisition channels'), findsOneWidget);
    expect(find.text('Alpha site'), findsOneWidget);
    expect(find.textContaining('not global people counts'), findsOneWidget);
    expect(api.reportRequests, hasLength(1));
    expect(api.reportRequests.single['siteIds'], ['site-a']);

    await tester.tap(find.text('Sites'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear selection'));
    await tester.pumpAndSettle();
    expect(
      find.text('Select at least one site to view its roll-up.'),
      findsOneWidget,
    );
    expect(api.reportRequests, hasLength(1));
  });
}

class _RollupApi extends SeeRayApi {
  _RollupApi() : super(baseUrl: 'https://lens.example.test');

  final reportRequests = <Map<String, dynamic>>[];

  @override
  Future<dynamic> request(
    String method,
    String path, {
    Object? body,
    bool retried = false,
  }) async {
    if (path.endsWith('/sites')) {
      return [
        {
          'id': 'site-a',
          'workspaceId': 'workspace-1',
          'name': 'Alpha site',
          'trackingId': 'srl_alpha',
          'timezone': 'UTC',
          'defaultLanguage': 'en',
          'trackingEnabled': true,
          'requireConsent': false,
          'rawRetentionDays': 30,
          'aggregateRetentionDays': 730,
        },
      ];
    }
    if (path.endsWith('/analytics/rollup')) {
      final payload = Map<String, dynamic>.from(body! as Map);
      reportRequests.add(payload);
      return {
        'from': payload['from'],
        'to': payload['to'],
        'siteCount': 1,
        'pageViews': 24,
        'siteVisitors': 12,
        'sessions': 18,
        'bounceRate': 0.2,
        'daily': [
          {
            'date': payload['from'],
            'pageViews': 24,
            'sessions': 18,
            'siteVisitors': 12,
          },
        ],
        'sites': [
          {
            'siteId': 'site-a',
            'name': 'Alpha site',
            'timezone': 'UTC',
            'trackingEnabled': true,
            'pageViews': 24,
            'siteVisitors': 12,
            'sessions': 18,
            'bounceRate': 0.2,
          },
        ],
        'channels': [
          {'channel': 'direct', 'sessions': 18},
        ],
      };
    }
    throw StateError('Unexpected request $method $path');
  }
}
