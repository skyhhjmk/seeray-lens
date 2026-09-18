import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seeray_lens_admin/core/network/seeray_api.dart';
import 'package:seeray_lens_admin/features/analytics/presentation/site_audit_log_page.dart';
import 'package:seeray_lens_admin/features/auth/application/auth_controller.dart';

void main() {
  testWidgets('labels production approval audit actions clearly', (
    tester,
  ) async {
    final api = _AuditLogApi(productionApproval: true);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiProvider.overrideWithValue(api)],
        child: const MaterialApp(
          home: SiteAuditLogPage(siteId: 'site-1', embedded: true),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text(
        'release-admin@example.test Approved and published a production release tag manager item',
      ),
      findsOneWidget,
    );
  });

  testWidgets('shows actor and changes, then pages older audit entries', (
    tester,
  ) async {
    final api = _AuditLogApi();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiProvider.overrideWithValue(api)],
        child: const MaterialApp(
          home: SiteAuditLogPage(siteId: 'site-1', embedded: true),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('analyst@example.test Updated segment'), findsOneWidget);
    expect(
      find.textContaining('Record · 00000000-0000-0000-0000-000000000101'),
      findsOneWidget,
    );
    expect(find.text('Load older activity'), findsOneWidget);

    await tester.tap(find.text('Load older activity'));
    await tester.pumpAndSettle();
    expect(api.requestCount, 2);
    expect(find.text('admin@example.test Created dashboard'), findsOneWidget);
    expect(find.text('Load older activity'), findsNothing);
  });
}

class _AuditLogApi extends SeeRayApi {
  _AuditLogApi({this.productionApproval = false})
    : super(baseUrl: 'https://lens.example.test');

  final bool productionApproval;

  int requestCount = 0;

  @override
  Future<dynamic> request(
    String method,
    String path, {
    Object? body,
    bool retried = false,
  }) async {
    expect(method, 'GET');
    expect(path, contains('/api/v1/sites/site-1/audit-log'));
    requestCount++;
    if (productionApproval) {
      return {
        'entries': [
          {
            'id': '00000000-0000-0000-0000-000000000003',
            'actorEmail': 'release-admin@example.test',
            'action': 'APPROVE_PRODUCTION',
            'resource': 'tag-manager',
            'resourceId': '00000000-0000-0000-0000-000000000102',
            'createdAt': '2026-09-18T01:02:03Z',
          },
        ],
        'nextCursor': null,
      };
    }
    if (requestCount == 1) {
      return {
        'entries': [
          {
            'id': '00000000-0000-0000-0000-000000000001',
            'actorEmail': 'analyst@example.test',
            'action': 'UPDATE',
            'resource': 'segments',
            'resourceId': '00000000-0000-0000-0000-000000000101',
            'createdAt': '2026-09-17T01:02:03Z',
          },
        ],
        'nextCursor':
            '2026-09-17T01:02:03Z|00000000-0000-0000-0000-000000000001',
      };
    }
    expect(
      Uri.parse(
        'https://lens.example.test$path',
      ).queryParameters.containsKey('cursor'),
      isTrue,
    );
    return {
      'entries': [
        {
          'id': '00000000-0000-0000-0000-000000000002',
          'actorEmail': 'admin@example.test',
          'action': 'CREATE',
          'resource': 'dashboards',
          'resourceId': null,
          'createdAt': '2026-09-16T22:00:00Z',
        },
      ],
      'nextCursor': null,
    };
  }
}
