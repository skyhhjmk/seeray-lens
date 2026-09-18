import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seeray_lens_admin/features/sites/application/site_controller.dart';
import 'package:seeray_lens_admin/features/sites/presentation/sites_page.dart';
import 'package:seeray_lens_admin/features/workspaces/application/workspace_controller.dart';

void main() {
  testWidgets('renders the current workspace site list', (tester) async {
    final container = ProviderContainer(
      overrides: [
        currentWorkspaceProvider.overrideWith(CurrentWorkspaceController.new),
        sitesProvider.overrideWith(_FakeSitesController.new),
      ],
    );
    addTearDown(container.dispose);
    container
        .read(currentWorkspaceProvider.notifier)
        .select(const Workspace(id: 'w1', name: 'Demo', role: 'owner'));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SitesPage()),
      ),
    );
    await tester.pump();
    expect(find.text('Demo sites'), findsOneWidget);
    expect(find.text('No sites yet. Create your first site.'), findsOneWidget);
  });

  testWidgets('create site dialog presents retention defaults', (tester) async {
    final container = ProviderContainer(
      overrides: [
        currentWorkspaceProvider.overrideWith(CurrentWorkspaceController.new),
        sitesProvider.overrideWith(_FakeSitesController.new),
      ],
    );
    addTearDown(container.dispose);
    container
        .read(currentWorkspaceProvider.notifier)
        .select(const Workspace(id: 'w1', name: 'Demo', role: 'owner'));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SitesPage()),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Create site'));
    await tester.pumpAndSettle();
    expect(find.text('Raw retention days'), findsOneWidget);
    expect(find.text('Aggregate retention days'), findsOneWidget);
    expect(find.text('30'), findsOneWidget);
    expect(find.text('730'), findsOneWidget);
    expect(
      find.textContaining('Raw events are automatically deleted'),
      findsOneWidget,
    );
  });
}

class _FakeSitesController extends SitesController {
  @override
  Future<List<Site>> build() async => const [];
}
