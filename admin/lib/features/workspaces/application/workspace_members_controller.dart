import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import 'workspace_controller.dart';

class WorkspaceMember {
  const WorkspaceMember({
    required this.userId,
    required this.email,
    required this.displayName,
    required this.role,
    required this.createdAt,
    required this.currentUser,
  });

  final String userId;
  final String email;
  final String displayName;
  final String role;
  final DateTime createdAt;
  final bool currentUser;

  factory WorkspaceMember.fromJson(Map<String, dynamic> json) =>
      WorkspaceMember(
        userId: json['userId'] as String,
        email: json['email'] as String,
        displayName: json['displayName'] as String,
        role: json['role'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        currentUser: json['currentUser'] as bool,
      );
}

class WorkspaceMemberDirectory {
  const WorkspaceMemberDirectory({
    required this.workspaceName,
    required this.currentRole,
    required this.members,
  });

  final String workspaceName;
  final String currentRole;
  final List<WorkspaceMember> members;

  bool get canManage => currentRole == 'owner';
  bool get canView => currentRole == 'owner' || currentRole == 'admin';
}

final workspaceMemberDirectoryProvider =
    FutureProvider.family<WorkspaceMemberDirectory, String>((
      ref,
      workspaceId,
    ) async {
      final api = ref.read(apiProvider);
      final workspace =
          await api.request('GET', '/api/v1/workspaces/$workspaceId')
              as Map<String, dynamic>;
      final role = workspace['role'] as String;
      if (role != 'owner' && role != 'admin') {
        return WorkspaceMemberDirectory(
          workspaceName: workspace['name'] as String,
          currentRole: role,
          members: const [],
        );
      }
      final response =
          await api.request('GET', '/api/v1/workspaces/$workspaceId/members')
              as List;
      return WorkspaceMemberDirectory(
        workspaceName: workspace['name'] as String,
        currentRole: role,
        members: response
            .map(
              (item) => WorkspaceMember.fromJson(
                Map<String, dynamic>.from(item as Map),
              ),
            )
            .toList(growable: false),
      );
    });

class WorkspaceMemberActions {
  const WorkspaceMemberActions._();

  static Future<void> add(
    WidgetRef ref,
    String workspaceId,
    String email,
    String role,
  ) async {
    await ref
        .read(apiProvider)
        .request(
          'POST',
          '/api/v1/workspaces/$workspaceId/members',
          body: {'email': email, 'role': role},
        );
    ref.invalidate(workspaceMemberDirectoryProvider(workspaceId));
  }

  static Future<void> changeRole(
    WidgetRef ref,
    String workspaceId,
    String userId,
    String role,
  ) async {
    await ref
        .read(apiProvider)
        .request(
          'PATCH',
          '/api/v1/workspaces/$workspaceId/members/$userId',
          body: {'role': role},
        );
    ref.invalidate(workspaceMemberDirectoryProvider(workspaceId));
  }

  static Future<void> transferOwnership(
    WidgetRef ref,
    String workspaceId,
    String userId,
  ) async {
    await ref
        .read(apiProvider)
        .request(
          'POST',
          '/api/v1/workspaces/$workspaceId/members/$userId/transfer-ownership',
          body: const {},
        );
    ref.invalidate(workspaceMemberDirectoryProvider(workspaceId));
    final selected = ref.read(currentWorkspaceProvider);
    if (selected?.id == workspaceId) {
      ref
          .read(currentWorkspaceProvider.notifier)
          .select(
            Workspace(id: selected!.id, name: selected.name, role: 'admin'),
          );
    }
    ref.invalidate(workspaceProvider);
  }

  static Future<void> remove(
    WidgetRef ref,
    String workspaceId,
    String userId,
  ) async {
    await ref
        .read(apiProvider)
        .request('DELETE', '/api/v1/workspaces/$workspaceId/members/$userId');
    ref.invalidate(workspaceMemberDirectoryProvider(workspaceId));
    ref.invalidate(workspaceProvider);
  }
}
