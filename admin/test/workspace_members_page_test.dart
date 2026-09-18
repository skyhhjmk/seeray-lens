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
}) => WorkspaceMemberDirectory(
  workspaceName: 'Northwind Analytics',
  currentRole: role,
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
