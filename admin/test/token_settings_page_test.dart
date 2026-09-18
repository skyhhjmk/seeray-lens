import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seeray_lens_admin/core/network/seeray_api.dart';
import 'package:seeray_lens_admin/features/auth/application/auth_controller.dart';
import 'package:seeray_lens_admin/features/tokens/application/token_controller.dart';
import 'package:seeray_lens_admin/features/tokens/presentation/token_settings_page.dart';
import 'package:seeray_lens_admin/features/workspaces/application/workspace_controller.dart';

void main() {
  testWidgets('shows a newly created token only in the one-time dialog', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        currentWorkspaceProvider.overrideWith(CurrentWorkspaceController.new),
        apiTokensProvider.overrideWith(_FakeTokensController.new),
        apiProvider.overrideWithValue(_TokenUsageApi()),
      ],
    );
    addTearDown(container.dispose);
    container
        .read(currentWorkspaceProvider.notifier)
        .select(const Workspace(id: 'w1', name: 'Demo', role: 'owner'));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: TokenSettingsPage()),
      ),
    );
    await tester.pump();
    expect(find.textContaining('Sites: read'), findsNWidgets(2));
    expect(find.textContaining('Never'), findsNWidgets(2));
    expect(find.text('Expired'), findsOneWidget);
    await tester.tap(find.text('Recent API activity').first);
    await tester.pumpAndSettle();
    expect(
      find.text('/api/v1/sites/{siteId}/analytics/overview'),
      findsOneWidget,
    );
    expect(find.textContaining('Status 200'), findsOneWidget);
    await tester.tap(find.text('Load older requests'));
    await tester.pumpAndSettle();
    expect(
      find.text('/api/v1/sites/{siteId}/analytics/events'),
      findsOneWidget,
    );
    expect(_TokenUsageApi.lastCursor, contains('usage-1'));
    await tester.tap(find.text('Create token'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'test token');
    await tester.tap(find.byTooltip('Choose expiration'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    expect(_FakeTokensController.createdExpiresAt, isNotNull);
    expect(
      find.text(
        'Save this token now. You cannot view it again after closing this dialog.',
      ),
      findsOneWidget,
    );
    expect(find.text('srl_secret_once'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text('srl_secret_once'), findsNothing);
  });
}

class _TokenUsageApi extends SeeRayApi {
  _TokenUsageApi() : super(baseUrl: 'https://lens.example.test');
  static String? lastCursor;

  @override
  Future<dynamic> request(
    String method,
    String path, {
    Object? body,
    bool retried = false,
  }) async {
    if (path.contains('/api-tokens/existing-token/usage')) {
      final cursor = Uri.parse(path).queryParameters['cursor'];
      lastCursor = cursor;
      if (cursor != null) {
        return {
          'entries': [
            {
              'id': 'usage-2',
              'method': 'GET',
              'routeTemplate': '/api/v1/sites/{siteId}/analytics/events',
              'statusCode': 200,
              'createdAt': '2026-09-18T01:00:00Z',
            },
          ],
          'nextCursor': null,
          'retentionDays': 30,
        };
      }
      return {
        'entries': [
          {
            'id': 'usage-1',
            'method': 'GET',
            'routeTemplate': '/api/v1/sites/{siteId}/analytics/overview',
            'statusCode': 200,
            'createdAt': '2026-09-19T01:00:00Z',
          },
        ],
        'nextCursor': '2026-09-19T01:00:00Z|usage-1',
        'retentionDays': 30,
      };
    }
    throw StateError('Unexpected request $method $path');
  }
}

class _FakeTokensController extends ApiTokensController {
  static DateTime? createdExpiresAt;

  @override
  Future<List<ApiTokenSummary>> build() async => const [
    ApiTokenSummary(
      id: 'existing-token',
      name: 'existing token',
      prefix: 'srl_existing',
      scopes: '["sites:read"]',
      createdAt: 'now',
      lastUsedAt: null,
      expiresAt: null,
      revokedAt: null,
    ),
    ApiTokenSummary(
      id: 'expired-token',
      name: 'expired token',
      prefix: 'srl_expired',
      scopes: '["sites:read"]',
      createdAt: 'then',
      lastUsedAt: null,
      expiresAt: '2000-01-01T00:00:00Z',
      revokedAt: null,
    ),
  ];

  @override
  Future<CreatedApiToken> create(
    String name,
    List<String> scopes, {
    DateTime? expiresAt,
  }) async {
    createdExpiresAt = expiresAt;
    return CreatedApiToken(
      const ApiTokenSummary(
        id: 'token-1',
        name: 'test token',
        prefix: 'srl_prefix',
        scopes: '["sites:read"]',
        createdAt: 'now',
        lastUsedAt: null,
        expiresAt: null,
        revokedAt: null,
      ),
      'srl_secret_once',
    );
  }
}
