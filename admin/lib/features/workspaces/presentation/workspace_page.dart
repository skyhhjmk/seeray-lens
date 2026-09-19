import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../auth/application/auth_controller.dart';
import '../../../core/i18n/app_i18n.dart';
import '../../../shared/presentation/page_help_button.dart';
import '../application/workspace_controller.dart';

class WorkspacePage extends ConsumerWidget {
  const WorkspacePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(workspaceProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('Workspaces', '工作区')),
        actions: [
          const PageHelpButton(
            englishTitle: 'About workspaces',
            chineseTitle: '工作区是什么？',
            englishBody:
                'A workspace is the boundary for a team or project. It owns its sites, members and API tokens. Create a separate workspace when data or access should be isolated.',
            chineseBody:
                '工作区是一个团队或项目的隔离边界，包含其站点、成员和 API 令牌。当数据或访问权限需要隔离时，请创建新的工作区。',
          ),
          const LanguageMenu(),
          TextButton(
            onPressed: () async {
              await ref.read(authProvider.notifier).logout();
              if (context.mounted) context.go('/');
            },
            child: Text(context.tr('Log out', '退出登录')),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _createWorkspace(context, ref),
        icon: const Icon(Icons.add),
        label: Text(context.tr('Create workspace', '创建工作区')),
      ),
      body: state.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(
          child: FilledButton.tonal(
            onPressed: () => ref.read(workspaceProvider.notifier).load(),
            child: Text(context.tr('Retry loading workspaces', '重新加载工作区')),
          ),
        ),
        data: (items) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(context.tr('Choose a workspace', '选择工作区')),
            const SizedBox(height: 8),
            ...items.map(
              (workspace) => Card(
                child: ListTile(
                  leading: _workspaceAvatar(workspace),
                  title: Text(workspace.name),
                  subtitle: Text(_workspaceRole(context, workspace.role)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (workspace.role == 'owner')
                        IconButton(
                          tooltip: context.tr('Branding', '品牌设置'),
                          onPressed: () => context.go(
                            '/workspaces/${workspace.id}/branding',
                          ),
                          icon: const Icon(Icons.palette_outlined),
                        ),
                      if (workspace.role == 'owner' ||
                          workspace.role == 'admin')
                        IconButton(
                          tooltip: context.tr('System diagnostics', '系统诊断'),
                          onPressed: () => context.go(
                            '/workspaces/${workspace.id}/diagnostics',
                          ),
                          icon: const Icon(Icons.health_and_safety_outlined),
                        ),
                      if (workspace.role == 'owner' ||
                          workspace.role == 'admin')
                        IconButton(
                          tooltip: context.tr('Workspace activity', '工作区活动记录'),
                          onPressed: () => context.go(
                            '/workspaces/${workspace.id}/activity',
                          ),
                          icon: const Icon(Icons.history),
                        ),
                      if (workspace.role == 'owner' ||
                          workspace.role == 'admin')
                        IconButton(
                          tooltip: context.tr(
                            workspace.role == 'owner'
                                ? 'Manage members'
                                : 'View members',
                            workspace.role == 'owner' ? '管理成员' : '查看成员',
                          ),
                          onPressed: () {
                            ref
                                .read(workspaceProvider.notifier)
                                .select(workspace);
                            context.go('/workspaces/${workspace.id}/members');
                          },
                          icon: const Icon(Icons.group_outlined),
                        ),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
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

  Future<void> _createWorkspace(BuildContext context, WidgetRef ref) async {
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => const _CreateWorkspaceDialog(),
    );
    if (name == null) return;
    try {
      await ref.read(workspaceProvider.notifier).create(name);
      if (context.mounted) context.go('/sites');
    } on Exception catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }
}

Widget _workspaceAvatar(Workspace workspace) {
  final logo = workspace.brandLogoUrl?.trim();
  if (logo != null && logo.isNotEmpty) {
    return CircleAvatar(
      backgroundColor: Colors.transparent,
      child: ClipOval(
        child: Image.network(
          logo,
          width: 40,
          height: 40,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) =>
              _workspaceInitial(workspace),
        ),
      ),
    );
  }
  return _workspaceInitial(workspace);
}

Widget _workspaceInitial(Workspace workspace) {
  final name = workspace.displayName.trim();
  return CircleAvatar(child: Text(name.isEmpty ? 'S' : name[0].toUpperCase()));
}

String _workspaceRole(BuildContext context, String role) => switch (role) {
  'owner' => context.tr('Owner', '所有者'),
  'admin' => context.tr('Admin', '管理员'),
  _ => context.tr('Viewer', '只读成员'),
};

class _CreateWorkspaceDialog extends StatefulWidget {
  const _CreateWorkspaceDialog();
  @override
  State<_CreateWorkspaceDialog> createState() => _CreateWorkspaceDialogState();
}

class _CreateWorkspaceDialogState extends State<_CreateWorkspaceDialog> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(context.tr('Create workspace', '创建工作区')),
    content: Form(
      key: _form,
      child: TextFormField(
        controller: _name,
        autofocus: true,
        maxLength: 120,
        decoration: InputDecoration(
          labelText: context.tr('Workspace name', '工作区名称'),
        ),
        validator: (value) => value == null || value.trim().isEmpty
            ? context.tr('Name is required', '请输入名称')
            : null,
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.tr('Cancel', '取消')),
      ),
      FilledButton(
        onPressed: () {
          if (_form.currentState!.validate()) {
            Navigator.pop(context, _name.text.trim());
          }
        },
        child: Text(context.tr('Create', '创建')),
      ),
    ],
  );
}
