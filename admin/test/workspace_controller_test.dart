import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seeray_lens_admin/features/workspaces/application/workspace_controller.dart';

void main() {
  test('selecting and clearing a workspace updates the shared context', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    const workspace = Workspace(id: 'workspace-a', name: 'A', role: 'owner');

    container.read(currentWorkspaceProvider.notifier).select(workspace);
    expect(container.read(currentWorkspaceProvider), workspace);
    container.read(currentWorkspaceProvider.notifier).clear();
    expect(container.read(currentWorkspaceProvider), isNull);
  });
}
