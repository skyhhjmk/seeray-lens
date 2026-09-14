import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';

class Workspace {
  const Workspace({required this.id, required this.name, required this.role});

  final String id;
  final String name;
  final String role;

  factory Workspace.fromJson(Map<String, dynamic> json) => Workspace(
    id: json['id'] as String,
    name: json['name'] as String,
    role: json['role'] as String,
  );
}

final workspaceProvider =
    AsyncNotifierProvider<WorkspaceController, List<Workspace>>(
      WorkspaceController.new,
    );

final currentWorkspaceProvider =
    NotifierProvider<CurrentWorkspaceController, Workspace?>(
      CurrentWorkspaceController.new,
    );

class CurrentWorkspaceController extends Notifier<Workspace?> {
  @override
  Workspace? build() => null;

  void select(Workspace workspace) => state = workspace;

  void clear() => state = null;
}

class WorkspaceController extends AsyncNotifier<List<Workspace>> {
  @override
  Future<List<Workspace>> build() {
    final auth = ref.watch(authProvider);
    if (!auth.isAuthenticated) {
      ref.read(currentWorkspaceProvider.notifier).clear();
      return Future.value(const []);
    }
    return load();
  }

  Future<List<Workspace>> load() async {
    final data =
        await ref.read(apiProvider).request('GET', '/api/v1/workspaces')
            as List;
    final items = data
        .map((item) => Workspace.fromJson(item as Map<String, dynamic>))
        .toList(growable: false);
    if (items.length == 1) {
      ref.read(currentWorkspaceProvider.notifier).select(items.single);
    }
    return items;
  }

  Future<Workspace> create(String name) async {
    final data = await ref
        .read(apiProvider)
        .request('POST', '/api/v1/workspaces', body: {'name': name});
    final workspace = Workspace.fromJson(data as Map<String, dynamic>);
    state = AsyncData([...(state.value ?? const <Workspace>[]), workspace]);
    ref.read(currentWorkspaceProvider.notifier).select(workspace);
    return workspace;
  }

  void select(Workspace workspace) {
    ref.read(currentWorkspaceProvider.notifier).select(workspace);
  }
}
