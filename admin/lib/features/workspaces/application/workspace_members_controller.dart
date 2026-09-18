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
    this.invitations = const [],
    this.canManageInvitations = false,
    this.invitationLifetimeDays = 7,
  });

  final String workspaceName;
  final String currentRole;
  final List<WorkspaceMember> members;
  final List<WorkspaceInvitation> invitations;
  final bool canManageInvitations;
  final int invitationLifetimeDays;

  bool get canManage => currentRole == 'owner';
  bool get canView => currentRole == 'owner' || currentRole == 'admin';
}

class WorkspaceInvitation {
  const WorkspaceInvitation({
    required this.id,
    required this.email,
    required this.role,
    required this.status,
    required this.createdAt,
    required this.expiresAt,
    required this.canRevoke,
  });

  final String id;
  final String email;
  final String role;
  final String status;
  final DateTime createdAt;
  final DateTime expiresAt;
  final bool canRevoke;

  factory WorkspaceInvitation.fromJson(Map<String, dynamic> json) =>
      WorkspaceInvitation(
        id: json['id'] as String,
        email: json['email'] as String,
        role: json['role'] as String,
        status: json['status'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        expiresAt: DateTime.parse(json['expiresAt'] as String),
        canRevoke: json['canRevoke'] as bool,
      );
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
      final invitationResponse =
          await api.request(
                'GET',
                '/api/v1/workspaces/$workspaceId/invitations',
              )
              as Map<String, dynamic>;
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
        canManageInvitations: invitationResponse['canManage'] as bool,
        invitationLifetimeDays: invitationResponse['lifetimeDays'] as int,
        invitations: (invitationResponse['invitations'] as List)
            .map(
              (item) => WorkspaceInvitation.fromJson(
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

  static Future<void> invite(
    WidgetRef ref,
    String workspaceId,
    String email,
    String role,
  ) async {
    await ref
        .read(apiProvider)
        .request(
          'POST',
          '/api/v1/workspaces/$workspaceId/invitations',
          body: {'email': email, 'role': role},
        );
    ref.invalidate(workspaceMemberDirectoryProvider(workspaceId));
  }

  static Future<void> revokeInvitation(
    WidgetRef ref,
    String workspaceId,
    String invitationId,
  ) async {
    await ref
        .read(apiProvider)
        .request(
          'DELETE',
          '/api/v1/workspaces/$workspaceId/invitations/$invitationId',
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
