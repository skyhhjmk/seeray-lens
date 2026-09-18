import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_state.dart';
import '../../../core/i18n/app_i18n.dart';
import '../../auth/application/auth_controller.dart';

final workspaceInvitationPreviewProvider =
    FutureProvider.family<Map<String, dynamic>, String>((ref, token) async {
      return await ref
              .read(apiProvider)
              .request(
                'POST',
                '/api/v1/auth/invitations/preview',
                body: {'token': token},
              )
          as Map<String, dynamic>;
    });

class WorkspaceInvitationPage extends ConsumerStatefulWidget {
  const WorkspaceInvitationPage({required this.token, super.key});

  final String token;

  @override
  ConsumerState<WorkspaceInvitationPage> createState() =>
      _WorkspaceInvitationPageState();
}

class _WorkspaceInvitationPageState
    extends ConsumerState<WorkspaceInvitationPage> {
  final _form = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _displayName = TextEditingController();
  String? _error;
  bool _createAccount = true;
  bool _submitting = false;
  bool _accepted = false;

  @override
  void dispose() {
    _password.dispose();
    _displayName.dispose();
    super.dispose();
  }

  Future<void> _submit(Map<String, dynamic> preview, bool authenticated) async {
    if (_submitting) return;
    if (!authenticated && !_form.currentState!.validate()) return;
    final creatingAccount = _createAccount && preview['accountExists'] != true;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      if (authenticated) {
        await ref
            .read(apiProvider)
            .request(
              'POST',
              '/api/v1/workspace-invitations/accept',
              body: {'invitationToken': widget.token},
            );
      } else if (creatingAccount) {
        await ref
            .read(authProvider.notifier)
            .registerForInvitation(
              email: preview['email'] as String,
              password: _password.text,
              displayName: _displayName.text,
              invitationToken: widget.token,
            );
        final auth = ref.read(authProvider);
        if (!auth.isAuthenticated) {
          throw Exception(auth.message ?? 'Unable to create the account');
        }
      } else {
        await ref
            .read(authProvider.notifier)
            .login(preview['email'] as String, _password.text);
        if (!ref.read(authProvider).isAuthenticated) {
          throw Exception(
            ref.read(authProvider).message ?? 'Unable to sign in',
          );
        }
        await ref
            .read(apiProvider)
            .request(
              'POST',
              '/api/v1/workspace-invitations/accept',
              body: {'invitationToken': widget.token},
            );
      }
      if (mounted) setState(() => _accepted = true);
    } on Exception catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final invitation = widget.token.isEmpty
        ? null
        : ref.watch(workspaceInvitationPreviewProvider(widget.token));
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.go('/')),
        title: Text(context.tr('Workspace invitation', '工作区邀请')),
        actions: const [LanguageMenu()],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: invitation == null
                ? _InvitationError(
                    message: context.tr(
                      'This invitation link is incomplete.',
                      '邀请链接不完整。',
                    ),
                  )
                : invitation.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (error, stackTrace) =>
                        _InvitationError(message: error.toString()),
                    data: (preview) => _InvitationCard(
                      preview: preview,
                      authenticated: auth.isAuthenticated,
                      restoring:
                          auth.phase == AuthPhase.restoring ||
                          auth.phase == AuthPhase.refreshing,
                      accepted: _accepted,
                      createAccount:
                          _createAccount && preview['accountExists'] != true,
                      submitting: _submitting,
                      error: _error,
                      form: _form,
                      password: _password,
                      displayName: _displayName,
                      onModeChanged: (value) =>
                          setState(() => _createAccount = value),
                      onSignOut: () async {
                        await ref.read(authProvider.notifier).logout();
                      },
                      onSubmit: () => _submit(preview, auth.isAuthenticated),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _InvitationCard extends StatelessWidget {
  const _InvitationCard({
    required this.preview,
    required this.authenticated,
    required this.restoring,
    required this.accepted,
    required this.createAccount,
    required this.submitting,
    required this.error,
    required this.form,
    required this.password,
    required this.displayName,
    required this.onModeChanged,
    required this.onSignOut,
    required this.onSubmit,
  });

  final Map<String, dynamic> preview;
  final bool authenticated;
  final bool restoring;
  final bool accepted;
  final bool createAccount;
  final bool submitting;
  final String? error;
  final GlobalKey<FormState> form;
  final TextEditingController password;
  final TextEditingController displayName;
  final ValueChanged<bool> onModeChanged;
  final VoidCallback onSignOut;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final email = preview['email'] as String;
    final workspace = preview['workspaceName'] as String;
    final role = preview['role'] as String;
    final expiresAt = DateTime.parse(preview['expiresAt'] as String).toLocal();
    final accountExists = preview['accountExists'] as bool;
    final creatingAccount = createAccount && !accountExists;
    if (accepted) {
      return _InvitationMessage(
        icon: Icons.check_circle_outline,
        title: context.tr('You joined $workspace', '你已加入 $workspace'),
        body: context.tr(
          'Your ${_role(context, role)} access is ready.',
          '你的${_role(context, role)}权限已生效。',
        ),
        action: FilledButton.icon(
          onPressed: () => context.go('/workspaces'),
          icon: const Icon(Icons.workspaces_outline),
          label: Text(context.tr('Open workspaces', '打开工作区')),
        ),
      );
    }
    if (restoring) return const Center(child: CircularProgressIndicator());
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.group_add_outlined, size: 44),
            const SizedBox(height: 12),
            Text(
              context.tr('You are invited to join', '你受邀加入'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              workspace,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              '${context.tr('Role', '角色')}: ${_role(context, role)} · ${context.tr('For', '邀请对象')} $email',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              context.tr(
                'This one-time link expires ${_date(expiresAt)}.',
                '该一次性链接将于 ${_date(expiresAt)} 过期。',
              ),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (authenticated) ...[
              const SizedBox(height: 20),
              Text(
                context.tr(
                  'Accept while signed in with $email.',
                  '请确认当前登录账号是 $email。',
                ),
                textAlign: TextAlign.center,
              ),
              TextButton(
                onPressed: submitting ? null : onSignOut,
                child: Text(
                  context.tr(
                    'Sign out and use the invited email',
                    '退出当前账号，改用受邀邮箱登录',
                  ),
                ),
              ),
            ] else ...[
              const SizedBox(height: 20),
              Form(
                key: form,
                child: Column(
                  children: [
                    if (creatingAccount)
                      TextFormField(
                        controller: displayName,
                        decoration: InputDecoration(
                          labelText: context.tr('Display name', '显示名称'),
                        ),
                        validator: (value) => (value?.trim().length ?? 0) > 120
                            ? context.tr(
                                'Name must be at most 120 characters',
                                '名称不能超过 120 个字符',
                              )
                            : null,
                      ),
                    if (creatingAccount) const SizedBox(height: 12),
                    TextFormField(
                      initialValue: email,
                      readOnly: true,
                      decoration: InputDecoration(
                        labelText: context.tr('Invitation email', '受邀邮箱'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: password,
                      obscureText: true,
                      autofillHints: const [AutofillHints.password],
                      decoration: InputDecoration(
                        labelText: creatingAccount
                            ? context.tr('Create password', '设置密码')
                            : context.tr('Password', '密码'),
                      ),
                      validator: (value) => (value?.length ?? 0) < 12
                          ? context.tr(
                              'Password must be at least 12 characters',
                              '密码至少需要 12 个字符',
                            )
                          : null,
                    ),
                  ],
                ),
              ),
              if (!accountExists)
                TextButton(
                  onPressed: submitting
                      ? null
                      : () => onModeChanged(!creatingAccount),
                  child: Text(
                    creatingAccount
                        ? context.tr(
                            'Already have an account? Sign in',
                            '已有账号？登录接受邀请',
                          )
                        : context.tr(
                            'New to SeeRay Lens? Create an account',
                            '还没有账号？创建账号',
                          ),
                  ),
                ),
            ],
            if (error != null) ...[
              const SizedBox(height: 8),
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: submitting ? null : onSubmit,
              icon: submitting
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
              label: Text(
                submitting
                    ? context.tr('Please wait…', '请稍候…')
                    : authenticated
                    ? context.tr('Accept invitation', '接受邀请')
                    : creatingAccount
                    ? context.tr('Create account and join', '创建账号并加入')
                    : context.tr('Sign in and join', '登录并加入'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InvitationError extends StatelessWidget {
  const _InvitationError({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => _InvitationMessage(
    icon: Icons.link_off,
    title: context.tr('Invitation unavailable', '邀请链接不可用'),
    body: message,
  );
}

class _InvitationMessage extends StatelessWidget {
  const _InvitationMessage({
    required this.icon,
    required this.title,
    required this.body,
    this.action,
  });

  final IconData icon;
  final String title;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 44),
          const SizedBox(height: 12),
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(body, textAlign: TextAlign.center),
          if (action != null) ...[const SizedBox(height: 20), action!],
        ],
      ),
    ),
  );
}

String _role(BuildContext context, String role) => switch (role) {
  'admin' => context.tr('admin', '管理员'),
  _ => context.tr('viewer', '只读成员'),
};

String _date(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';
