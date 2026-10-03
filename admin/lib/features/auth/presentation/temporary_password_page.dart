import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_state.dart';
import '../../../core/i18n/app_i18n.dart';
import '../application/auth_controller.dart';

class TemporaryPasswordPage extends ConsumerStatefulWidget {
  const TemporaryPasswordPage({super.key});

  @override
  ConsumerState<TemporaryPasswordPage> createState() => _TemporaryPasswordPageState();
}

class _TemporaryPasswordPageState extends ConsumerState<TemporaryPasswordPage> {
  final _form = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    await ref.read(authProvider.notifier).changeTemporaryPassword(_password.text);
    if (!mounted) return;
    setState(() => _saving = false);
    final auth = ref.read(authProvider);
    if (auth.isAuthenticated && !auth.mustChangePassword) context.go('/workspaces');
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('Set a new password', '设置新密码'))),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(context.tr(
                    'Your administrator issued a temporary password. Choose a new password to continue.',
                    '管理员为你设置了临时密码。请先设置新密码后继续。',
                  )),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _password,
                    obscureText: true,
                    decoration: InputDecoration(labelText: context.tr('New password', '新密码')),
                    validator: (value) => (value?.length ?? 0) < 12
                        ? context.tr('Password must be at least 12 characters', '密码至少需要 12 个字符')
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _confirm,
                    obscureText: true,
                    decoration: InputDecoration(labelText: context.tr('Confirm password', '确认密码')),
                    validator: (value) => value != _password.text
                        ? context.tr('Passwords do not match', '两次输入的密码不一致')
                        : null,
                  ),
                  if (auth.message != null) ...[
                    const SizedBox(height: 12),
                    Text(auth.message!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _saving ? null : _submit,
                    child: Text(_saving
                        ? context.tr('Saving…', '正在保存…')
                        : context.tr('Save new password', '保存新密码')),
                  ),
                  TextButton(
                    onPressed: _saving ? null : () => ref.read(authProvider.notifier).logout(),
                    child: Text(context.tr('Log out', '退出登录')),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
