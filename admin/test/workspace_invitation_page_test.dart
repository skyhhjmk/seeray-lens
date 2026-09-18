import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seeray_lens_admin/core/auth/auth_token_store.dart';
import 'package:seeray_lens_admin/features/auth/application/auth_controller.dart';
import 'package:seeray_lens_admin/features/workspaces/presentation/workspace_invitation_page.dart';

void main() {
  testWidgets(
    'shows invitation details and lets a new invitee choose sign-in',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authTokenStoreProvider.overrideWithValue(_MemoryTokenStore()),
            workspaceInvitationPreviewProvider('srlw_test-token').overrideWith(
              (ref) async => {
                'email': 'invitee@example.test',
                'workspaceName': 'Northwind Analytics',
                'role': 'viewer',
                'expiresAt': '2026-10-01T12:00:00Z',
                'accountExists': false,
              },
            ),
          ],
          child: const MaterialApp(
            locale: Locale('en'),
            supportedLocales: [Locale('en')],
            home: WorkspaceInvitationPage(token: 'srlw_test-token'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Northwind Analytics'), findsOneWidget);
      expect(find.textContaining('invitee@example.test'), findsWidgets);
      expect(find.text('Create account and join'), findsOneWidget);
      await tester.tap(find.text('Already have an account? Sign in'));
      await tester.pumpAndSettle();
      expect(find.text('Sign in and join'), findsOneWidget);
      expect(find.text('Password'), findsOneWidget);
    },
  );
}

class _MemoryTokenStore implements AuthTokenStore {
  @override
  Future<void> clear() async {}

  @override
  Future<String?> readRefreshToken() async => null;

  @override
  Future<void> writeRefreshToken(String token) async {}
}
