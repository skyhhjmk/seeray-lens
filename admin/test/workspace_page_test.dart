import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seeray_lens_admin/features/workspaces/application/workspace_controller.dart';
import 'package:seeray_lens_admin/features/workspaces/presentation/workspace_page.dart';

void main() {
  testWidgets('workspace owners and admins can discover the member directory', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          workspaceProvider.overrideWith(_FakeWorkspaceController.new),
        ],
        child: const MaterialApp(home: WorkspacePage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Analytics team'), findsOneWidget);
    expect(find.text('owner'), findsNothing);
    expect(find.text('Owner'), findsOneWidget);
    expect(find.text('Admin'), findsOneWidget);
    expect(find.text('Viewer'), findsOneWidget);
    expect(find.byTooltip('Manage members'), findsOneWidget);
    expect(find.byTooltip('View members'), findsOneWidget);
    expect(find.byTooltip('Workspace activity'), findsNWidgets(2));
    expect(find.byTooltip('System diagnostics'), findsNWidgets(2));
  });
}

class _FakeWorkspaceController extends WorkspaceController {
  @override
  Future<List<Workspace>> build() async => const [
    Workspace(id: 'owner-space', name: 'Analytics team', role: 'owner'),
    Workspace(id: 'admin-space', name: 'Read team', role: 'admin'),
    Workspace(id: 'viewer-space', name: 'Quiet team', role: 'viewer'),
  ];
}
