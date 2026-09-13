import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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
    await tester.tap(find.text('Create token'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'test token');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
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

class _FakeTokensController extends ApiTokensController {
  @override
  Future<List<ApiTokenSummary>> build() async => const [];

  @override
  Future<CreatedApiToken> create(String name, List<String> scopes) async =>
      CreatedApiToken(
        const ApiTokenSummary(
          id: 'token-1',
          name: 'test token',
          prefix: 'srl_prefix',
          scopes: '["sites:read"]',
          createdAt: 'now',
          expiresAt: null,
          revokedAt: null,
        ),
        'srl_secret_once',
      );
}
