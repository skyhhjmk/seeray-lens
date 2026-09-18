import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seeray_lens_admin/core/network/seeray_api.dart';
import 'package:seeray_lens_admin/features/auth/application/auth_controller.dart';
import 'package:seeray_lens_admin/features/workspaces/presentation/workspace_audit_log_page.dart';

void main() {
  testWidgets('renders actor, action, resource, and safe metadata only', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = _WorkspaceAuditApi();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiProvider.overrideWithValue(api)],
        child: const MaterialApp(
          locale: Locale('en'),
          supportedLocales: [Locale('en')],
          home: WorkspaceAuditLogPage(workspaceId: 'workspace-1'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Administrative history'), findsOneWidget);
    expect(
      find.text('owner@example.test sent a workspace invitation'),
      findsOneWidget,
    );
    expect(find.textContaining('Invitation'), findsOneWidget);
    expect(find.textContaining('invite-1'), findsOneWidget);
    expect(find.textContaining('invite-token'), findsNothing);
    expect(api.lastPath, contains('/api/v1/workspaces/workspace-1/audit-log'));
  });
}

class _WorkspaceAuditApi extends SeeRayApi {
  _WorkspaceAuditApi() : super(baseUrl: 'https://lens.example.test');

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
      'entries': [
        {
          'id': 'event-1',
          'actorEmail': 'owner@example.test',
          'action': 'CREATE_INVITATION',
          'resource': 'invitation',
          'resourceId': 'invite-1',
          'createdAt': '2026-09-19T08:30:00Z',
        },
      ],
      'nextCursor': null,
    };
  }
}
