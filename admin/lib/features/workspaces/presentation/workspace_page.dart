import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../auth/application/auth_controller.dart';
import '../application/workspace_controller.dart';

class WorkspacePage extends ConsumerWidget {
  const WorkspacePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(workspaceProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Workspaces'),
        actions: [
          TextButton(
            onPressed: () async {
              await ref.read(authProvider.notifier).logout();
              if (context.mounted) context.go('/login');
            },
            child: const Text('Log out'),
          ),
        ],
      ),
      body: state.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(
          child: FilledButton.tonal(
            onPressed: () => ref.read(workspaceProvider.notifier).load(),
            child: const Text('Retry loading workspaces'),
          ),
        ),
        data: (items) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('Choose a workspace'),
            const SizedBox(height: 8),
            ...items.map(
              (workspace) => Card(
                child: ListTile(
                  title: Text(workspace.name),
                  subtitle: Text(workspace.role),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    ref.read(workspaceProvider.notifier).select(workspace);
                    context.go('/sites');
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
