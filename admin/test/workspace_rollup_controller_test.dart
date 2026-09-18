import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:seeray_lens_admin/core/network/seeray_api.dart';
import 'package:seeray_lens_admin/features/auth/application/auth_controller.dart';
import 'package:seeray_lens_admin/features/workspaces/application/workspace_rollup_controller.dart';

void main() {
  test('requests selected sites and parses roll-up report metrics', () async {
    http.Request? received;
    final api = SeeRayApi(
      baseUrl: 'https://lens.example.test',
      client: MockClient((request) async {
        received = request;
        return http.Response(
          jsonEncode({
            'from': '2026-09-01',
            'to': '2026-09-30',
            'siteCount': 2,
            'pageViews': 120,
            'siteVisitors': 42,
            'sessions': 60,
            'bounceRate': 0.25,
            'daily': [
              {
                'date': '2026-09-01',
                'pageViews': 12,
                'sessions': 6,
                'siteVisitors': 5,
              },
            ],
            'sites': [
              {
                'siteId': 'site-a',
                'name': 'Alpha',
                'timezone': 'UTC',
                'trackingEnabled': true,
                'pageViews': 70,
                'siteVisitors': 25,
                'sessions': 35,
                'bounceRate': 0.2,
              },
            ],
            'channels': [
              {'channel': 'campaign', 'sessions': 12},
            ],
          }),
          200,
        );
      }),
    );
    final container = ProviderContainer(
      overrides: [apiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);

    final query = WorkspaceRollupQuery(
      workspaceId: 'workspace-1',
      siteIds: ['site-b', 'site-a'],
      from: '2026-09-01',
      to: '2026-09-30',
    );
    final result = await container.read(workspaceRollupProvider(query).future);

    expect(received?.method, 'POST');
    expect(
      received?.url.path,
      '/api/v1/workspaces/workspace-1/analytics/rollup',
    );
    expect(jsonDecode(received!.body), {
      'siteIds': ['site-a', 'site-b'],
      'from': '2026-09-01',
      'to': '2026-09-30',
    });
    expect(result.siteVisitors, 42);
    expect(result.daily.single.pageViews, 12);
    expect(result.sites.single.timezone, 'UTC');
    expect(result.channels.single.sessions, 12);
  });
}
