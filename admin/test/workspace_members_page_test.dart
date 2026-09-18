import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seeray_lens_admin/features/workspaces/application/workspace_members_controller.dart';
import 'package:seeray_lens_admin/features/workspaces/presentation/workspace_members_page.dart';

void main() {
  testWidgets('owner sees member roles and practical management actions', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          workspaceMemberDirectoryProvider(
            'w1',
          ).overrideWith((ref) async => _directory(role: 'owner')),
        ],
        child: const MaterialApp(home: WorkspaceMembersPage(workspaceId: 'w1')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Northwind Analytics'), findsOneWidget);
    expect(find.text('Ada Admin'), findsOneWidget);
    expect(find.text('Lin Viewer'), findsOneWidget);
    expect(find.text('Add member'), findsOneWidget);
    expect(find.byTooltip('Member actions'), findsNWidgets(2));

    await tester.tap(find.text('Add member'));
    await tester.pumpAndSettle();
    expect(find.text('Account email'), findsOneWidget);
    expect(
      find.text(
        'The account must already exist. Ownership can only be assigned through an explicit transfer.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Viewer · read reports'));
    await tester.pumpAndSettle();
    expect(find.text('Viewer · read reports'), findsWidgets);
    expect(find.text('Admin · configure sites'), findsOneWidget);
  });

  testWidgets('owner can review invitations and open the invite form', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          workspaceMemberDirectoryProvider('w1').overrideWith(
            (ref) async =>
                _directory(role: 'owner', canManageInvitations: true),
          ),
        ],
        child: const MaterialApp(home: WorkspaceMembersPage(workspaceId: 'w1')),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Invitations'));
    expect(find.text('invitee@example.test'), findsOneWidget);
    expect(find.textContaining('Pending'), findsOneWidget);
    await tester.tap(find.text('Invite').last);
    await tester.pumpAndSettle();
    expect(find.text('Invite workspace member'), findsOneWidget);
    expect(
      find.text(
        'We will email a one-time link. The person can sign in or create an account to join this workspace.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('viewer gets a clear access explanation and no member actions', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          workspaceMemberDirectoryProvider('w1').overrideWith(
            (ref) async => _directory(role: 'viewer', members: const []),
          ),
        ],
        child: const MaterialApp(home: WorkspaceMembersPage(workspaceId: 'w1')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Member directory restricted'), findsOneWidget);
    expect(find.text('Add member'), findsNothing);
  });
}

WorkspaceMemberDirectory _directory({
  required String role,
  List<WorkspaceMember>? members,
  bool canManageInvitations = false,
}) => WorkspaceMemberDirectory(
  workspaceName: 'Northwind Analytics',
  currentRole: role,
  canManageInvitations: canManageInvitations,
  invitations: canManageInvitations
      ? [
          WorkspaceInvitation(
            id: 'invite-1',
            email: 'invitee@example.test',
            role: 'viewer',
            status: 'pending',
            createdAt: DateTime.utc(2026, 1, 3),
            expiresAt: DateTime.utc(2026, 1, 10),
            canRevoke: true,
          ),
        ]
      : const [],
  members:
      members ??
      [
        WorkspaceMember(
          userId: 'owner',
          email: 'ada@example.test',
          displayName: 'Ada Owner',
          role: 'owner',
          createdAt: DateTime.utc(2026, 1, 1),
          currentUser: true,
        ),
        WorkspaceMember(
          userId: 'admin',
          email: 'alix@example.test',
          displayName: 'Ada Admin',
          role: 'admin',
          createdAt: DateTime.utc(2026, 1, 2),
          currentUser: false,
        ),
        WorkspaceMember(
          userId: 'viewer',
          email: 'lin@example.test',
          displayName: 'Lin Viewer',
          role: 'viewer',
          createdAt: DateTime.utc(2026, 1, 3),
          currentUser: false,
        ),
      ],
);
