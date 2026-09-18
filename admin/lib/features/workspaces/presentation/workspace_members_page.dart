import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_i18n.dart';
import '../../../shared/presentation/app_back_button.dart';
import '../../../shared/presentation/page_help_button.dart';
import '../application/workspace_members_controller.dart';

class WorkspaceMembersPage extends ConsumerWidget {
  const WorkspaceMembersPage({required this.workspaceId, super.key});

  final String workspaceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final directory = ref.watch(workspaceMemberDirectoryProvider(workspaceId));
    final data = directory.asData?.value;
    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(fallback: '/workspaces'),
        title: Text(context.tr('Workspace members', '工作区成员')),
        actions: [
          const PageHelpButton(
            englishTitle: 'Workspace membership',
            chineseTitle: '工作区成员与角色',
            englishBody:
                'Owners can add existing accounts or email time-limited invitations, assign admin or viewer access, remove non-owners, and transfer ownership. Admins can view members and invitation status.',
            chineseBody:
                '所有者可直接添加已有账号或发送限时邮件邀请，分配管理员或只读角色、移除非所有者成员并移交所有权。管理员可查看成员和邀请状态。',
          ),
          const LanguageMenu(),
          if (data?.canManageInvitations == true)
            IconButton(
              tooltip: context.tr('Invite member', '邀请成员'),
              onPressed: () => _inviteMember(context, ref),
              icon: const Icon(Icons.mail_outline),
            ),
          IconButton(
            tooltip: context.tr('Refresh', '刷新'),
            onPressed: () =>
                ref.invalidate(workspaceMemberDirectoryProvider(workspaceId)),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: data?.canManage == true
          ? FloatingActionButton.extended(
              onPressed: () => _addMember(context, ref),
              icon: const Icon(Icons.person_add_alt_1),
              label: Text(context.tr('Add member', '添加成员')),
            )
          : null,
      body: directory.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(
          child: FilledButton.tonalIcon(
            onPressed: () =>
                ref.invalidate(workspaceMemberDirectoryProvider(workspaceId)),
            icon: const Icon(Icons.refresh),
            label: Text(context.tr('Retry loading members', '重试加载成员')),
          ),
        ),
        data: (value) => value.canView
            ? _MemberDirectory(workspaceId: workspaceId, directory: value)
            : _NoPermission(role: value.currentRole),
      ),
    );
  }

  Future<void> _addMember(BuildContext context, WidgetRef ref) async {
    final input = await showDialog<_MemberInput>(
      context: context,
      builder: (_) => const _AddMemberDialog(),
    );
    if (input == null) return;
    try {
      await WorkspaceMemberActions.add(
        ref,
        workspaceId,
        input.email,
        input.role,
      );
      if (context.mounted) {
        _message(context, context.tr('Member added.', '成员已添加。'));
      }
    } on Exception catch (error) {
      if (context.mounted) _message(context, '$error');
    }
  }

  Future<void> _inviteMember(BuildContext context, WidgetRef ref) async {
    final input = await showDialog<_MemberInput>(
      context: context,
      builder: (_) => const _AddMemberDialog(invite: true),
    );
    if (input == null) return;
    try {
      await WorkspaceMemberActions.invite(
        ref,
        workspaceId,
        input.email,
        input.role,
      );
      if (context.mounted) {
        _message(context, context.tr('Invitation email sent.', '邀请邮件已发送。'));
      }
    } on Exception catch (error) {
      if (context.mounted) _message(context, '$error');
    }
  }
}

class _MemberDirectory extends ConsumerWidget {
  const _MemberDirectory({required this.workspaceId, required this.directory});

  final String workspaceId;
  final WorkspaceMemberDirectory directory;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ListView(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
    children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                directory.workspaceName,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                context.tr(
                  '${directory.members.length} members · You are ${_roleName(context, directory.currentRole)}',
                  '${directory.members.length} 位成员 · 你的角色：${_roleName(context, directory.currentRole)}',
                ),
              ),
              const SizedBox(height: 8),
              Text(
                context.tr(
                  'Owner manages membership and workspace settings. Admins configure sites. Viewers can read reports.',
                  '所有者管理成员与工作区设置；管理员可配置站点；只读成员可查看报表。',
                ),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 8),
      for (final member in directory.members)
        Card(
          child: ListTile(
            leading: CircleAvatar(
              child: Text(
                (member.displayName.isNotEmpty
                        ? member.displayName
                        : member.email)
                    .characters
                    .first
                    .toUpperCase(),
              ),
            ),
            title: Text(
              member.displayName.isEmpty ? member.email : member.displayName,
            ),
            subtitle: Text(
              '${member.email}\n${context.tr('Joined', '加入于')} ${_date(member.createdAt)}',
            ),
            isThreeLine: true,
            trailing: directory.canManage && !member.currentUser
                ? _MemberActions(member: member, workspaceId: workspaceId)
                : Chip(
                    label: Text(
                      member.currentUser
                          ? context.tr(
                              '${_roleName(context, member.role)} · You',
                              '${_roleName(context, member.role)} · 你',
                            )
                          : _roleName(context, member.role),
                    ),
                  ),
          ),
        ),
      const SizedBox(height: 16),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      context.tr('Invitations', '邀请记录'),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  if (directory.canManageInvitations)
                    TextButton.icon(
                      onPressed: () =>
                          _inviteMemberFromDirectory(context, ref, workspaceId),
                      icon: const Icon(Icons.person_add_alt_1),
                      label: Text(context.tr('Invite', '邀请')),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                context.tr(
                  'Email links expire after ${directory.invitationLifetimeDays} days and can be used once.',
                  '邮件邀请链接 ${directory.invitationLifetimeDays} 天后过期，且只能接受一次。',
                ),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (directory.invitations.isEmpty) ...[
                const SizedBox(height: 14),
                Text(context.tr('No invitations yet.', '暂无邀请记录。')),
              ] else ...[
                const SizedBox(height: 8),
                for (final invitation in directory.invitations)
                  _InvitationTile(
                    invitation: invitation,
                    workspaceId: workspaceId,
                    canManage: directory.canManageInvitations,
                  ),
              ],
            ],
          ),
        ),
      ),
    ],
  );
}

Future<void> _inviteMemberFromDirectory(
  BuildContext context,
  WidgetRef ref,
  String workspaceId,
) async {
  final input = await showDialog<_MemberInput>(
    context: context,
    builder: (_) => const _AddMemberDialog(invite: true),
  );
  if (input == null) return;
  try {
    await WorkspaceMemberActions.invite(
      ref,
      workspaceId,
      input.email,
      input.role,
    );
    if (context.mounted) {
      _message(context, context.tr('Invitation email sent.', '邀请邮件已发送。'));
    }
  } on Exception catch (error) {
    if (context.mounted) _message(context, '$error');
  }
}

class _InvitationTile extends ConsumerWidget {
  const _InvitationTile({
    required this.invitation,
    required this.workspaceId,
    required this.canManage,
  });

  final WorkspaceInvitation invitation;
  final String workspaceId;
  final bool canManage;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: const Icon(Icons.mail_outline),
    title: Text(invitation.email),
    subtitle: Text(
      '${_roleName(context, invitation.role)} · ${_invitationStatus(context, invitation.status)}'
      '${invitation.status == 'pending' ? ' · ${context.tr('Expires', '过期时间')} ${_date(invitation.expiresAt)}' : ''}',
    ),
    trailing: canManage && invitation.canRevoke
        ? IconButton(
            tooltip: context.tr('Revoke invitation', '撤销邀请'),
            onPressed: () async {
              final confirmed = await _confirm(
                context,
                context.tr('Revoke invitation?', '撤销这条邀请？'),
                context.tr(
                  'The invitation link will stop working immediately.',
                  '该邀请链接将立即失效。',
                ),
              );
              if (!confirmed) return;
              try {
                await WorkspaceMemberActions.revokeInvitation(
                  ref,
                  workspaceId,
                  invitation.id,
                );
              } on Exception catch (error) {
                if (context.mounted) _message(context, '$error');
              }
            },
            icon: const Icon(Icons.delete_outline),
          )
        : Chip(label: Text(_invitationStatus(context, invitation.status))),
  );
}

class _MemberActions extends ConsumerWidget {
  const _MemberActions({required this.member, required this.workspaceId});

  final WorkspaceMember member;
  final String workspaceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => PopupMenuButton<String>(
    tooltip: context.tr('Member actions', '成员操作'),
    onSelected: (action) => _perform(context, ref, action),
    itemBuilder: (context) => [
      PopupMenuItem(
        value: 'role',
        child: Text(context.tr('Change role', '更改角色')),
      ),
      PopupMenuItem(
        value: 'transfer',
        child: Text(context.tr('Transfer ownership', '移交所有权')),
      ),
      PopupMenuItem(
        value: 'remove',
        child: Text(context.tr('Remove member', '移除成员')),
      ),
    ],
  );

  Future<void> _perform(
    BuildContext context,
    WidgetRef ref,
    String action,
  ) async {
    try {
      if (action == 'role') {
        final role = await showDialog<String>(
          context: context,
          builder: (_) => _ChangeRoleDialog(currentRole: member.role),
        );
        if (role == null) return;
        await WorkspaceMemberActions.changeRole(
          ref,
          workspaceId,
          member.userId,
          role,
        );
        if (context.mounted) {
          _message(context, context.tr('Role updated.', '角色已更新。'));
        }
      } else {
        final title = action == 'transfer'
            ? context.tr('Transfer ownership?', '移交所有权？')
            : context.tr('Remove this member?', '移除此成员？');
        final body = action == 'transfer'
            ? context.tr(
                '${member.email} becomes the owner and your account becomes an admin.',
                '${member.email} 将成为所有者，你的账号将降为管理员。',
              )
            : context.tr(
                '${member.email} will lose access to this workspace and its sites.',
                '${member.email} 将失去此工作区及其站点的访问权限。',
              );
        final confirmed = await _confirm(context, title, body);
        if (!confirmed) return;
        if (action == 'transfer') {
          await WorkspaceMemberActions.transferOwnership(
            ref,
            workspaceId,
            member.userId,
          );
          if (context.mounted) {
            _message(context, context.tr('Ownership transferred.', '所有权已移交。'));
          }
        } else {
          await WorkspaceMemberActions.remove(ref, workspaceId, member.userId);
          if (context.mounted) {
            _message(context, context.tr('Member removed.', '成员已移除。'));
          }
        }
      }
    } on Exception catch (error) {
      if (context.mounted) _message(context, '$error');
    }
  }
}

class _NoPermission extends StatelessWidget {
  const _NoPermission({required this.role});
  final String role;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.admin_panel_settings_outlined, size: 44),
                const SizedBox(height: 12),
                Text(
                  context.tr('Member directory restricted', '成员目录仅限管理角色查看'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  context.tr(
                    'Your ${_roleName(context, role)} role does not have permission to view workspace membership.',
                    '你的“${_roleName(context, role)}”角色没有查看工作区成员的权限。',
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _MemberInput {
  const _MemberInput(this.email, this.role);
  final String email;
  final String role;
}

class _AddMemberDialog extends StatefulWidget {
  const _AddMemberDialog({this.invite = false});

  final bool invite;

  @override
  State<_AddMemberDialog> createState() => _AddMemberDialogState();
}

class _AddMemberDialogState extends State<_AddMemberDialog> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  String _role = 'viewer';

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      context.tr(
        widget.invite ? 'Invite workspace member' : 'Add workspace member',
        widget.invite ? '邀请工作区成员' : '添加工作区成员',
      ),
    ),
    content: SizedBox(
      width: 420,
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _email,
              autofocus: true,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                labelText: context.tr(
                  widget.invite ? 'Email address' : 'Account email',
                  widget.invite ? '邮箱地址' : '账号邮箱',
                ),
              ),
              validator: (value) {
                final email = value?.trim() ?? '';
                return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)
                    ? null
                    : context.tr('Enter a valid email address', '请输入有效的邮箱地址');
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _role,
              decoration: InputDecoration(
                labelText: context.tr('Workspace role', '工作区角色'),
              ),
              items: [
                DropdownMenuItem(
                  value: 'viewer',
                  child: Text(
                    context.tr('Viewer · read reports', '只读成员 · 查看报表'),
                  ),
                ),
                DropdownMenuItem(
                  value: 'admin',
                  child: Text(
                    context.tr('Admin · configure sites', '管理员 · 配置站点'),
                  ),
                ),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _role = value);
              },
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                context.tr(
                  widget.invite
                      ? 'We will email a one-time link. The person can sign in or create an account to join this workspace.'
                      : 'The account must already exist. Ownership can only be assigned through an explicit transfer.',
                  widget.invite
                      ? '我们会发送一次性链接。对方登录或创建账号后即可加入此工作区。'
                      : '该邮箱必须已注册账号。所有权只能通过单独的移交操作授予。',
                ),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.tr('Cancel', '取消')),
      ),
      FilledButton(
        onPressed: () {
          if (!_form.currentState!.validate()) return;
          Navigator.pop(context, _MemberInput(_email.text.trim(), _role));
        },
        child: Text(
          context.tr(
            widget.invite ? 'Send invitation' : 'Add member',
            widget.invite ? '发送邀请' : '添加成员',
          ),
        ),
      ),
    ],
  );
}

class _ChangeRoleDialog extends StatefulWidget {
  const _ChangeRoleDialog({required this.currentRole});
  final String currentRole;

  @override
  State<_ChangeRoleDialog> createState() => _ChangeRoleDialogState();
}

class _ChangeRoleDialogState extends State<_ChangeRoleDialog> {
  late String _role = widget.currentRole;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(context.tr('Change member role', '更改成员角色')),
    content: DropdownButtonFormField<String>(
      initialValue: _role,
      items: [
        DropdownMenuItem(
          value: 'viewer',
          child: Text(context.tr('Viewer · read reports', '只读成员 · 查看报表')),
        ),
        DropdownMenuItem(
          value: 'admin',
          child: Text(context.tr('Admin · configure sites', '管理员 · 配置站点')),
        ),
      ],
      onChanged: (value) {
        if (value != null) setState(() => _role = value);
      },
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.tr('Cancel', '取消')),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _role),
        child: Text(context.tr('Save role', '保存角色')),
      ),
    ],
  );
}

Future<bool> _confirm(BuildContext context, String title, String body) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.tr('Cancel', '取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.tr('Confirm', '确认')),
          ),
        ],
      ),
    ) ??
    false;

String _roleName(BuildContext context, String role) => switch (role) {
  'owner' => context.tr('Owner', '所有者'),
  'admin' => context.tr('Admin', '管理员'),
  _ => context.tr('Viewer', '只读成员'),
};

String _invitationStatus(BuildContext context, String status) =>
    switch (status) {
      'accepted' => context.tr('Accepted', '已接受'),
      'revoked' => context.tr('Revoked', '已撤销'),
      'expired' => context.tr('Expired', '已过期'),
      _ => context.tr('Pending', '待接受'),
    };

String _date(DateTime value) =>
    '${value.toLocal().year.toString().padLeft(4, '0')}-'
    '${value.toLocal().month.toString().padLeft(2, '0')}-'
    '${value.toLocal().day.toString().padLeft(2, '0')}';

void _message(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
