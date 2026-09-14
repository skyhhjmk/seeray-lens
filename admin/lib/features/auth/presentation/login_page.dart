import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_state.dart';
import '../../../core/i18n/app_i18n.dart';
import '../../../shared/presentation/app_back_button.dart';
import '../../../shared/presentation/page_help_button.dart';
import '../application/auth_controller.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _rememberPassword = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (!_form.currentState!.validate()) return;
    await ref
        .read(authProvider.notifier)
        .login(_email.text.trim(), _password.text);
    if (mounted && ref.read(authProvider).isAuthenticated) {
      TextInput.finishAutofillContext(shouldSave: _rememberPassword);
      context.go('/workspaces');
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    if (auth.isAuthenticated) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => context.go('/workspaces'),
      );
    }
    final busy = auth.phase == AuthPhase.authenticating;
    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(fallback: '/'),
        actions: const [
          PageHelpButton(
            englishTitle: 'Signing in',
            chineseTitle: '登录说明',
            englishBody:
                'Use the email and password for your SeeRay Lens account. Your workspace and the sites you can access are shown after signing in.',
            chineseBody: '使用 SeeRay Lens 账号的邮箱和密码登录。登录后会显示你有权限访问的工作区和站点。',
          ),
          LanguageMenu(),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: AutofillGroup(
              child: Form(
                key: _form,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'SeeRay Lens',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [
                        AutofillHints.username,
                        AutofillHints.email,
                      ],
                      decoration: InputDecoration(
                        labelText: context.tr('Email', '邮箱'),
                      ),
                      validator: (value) =>
                          value == null || !value.contains('@')
                          ? context.tr('Enter a valid email', '请输入有效邮箱')
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _password,
                      obscureText: true,
                      autofillHints: const [AutofillHints.password],
                      decoration: InputDecoration(
                        labelText: context.tr('Password', '密码'),
                      ),
                      validator: (value) => value == null || value.length < 12
                          ? context.tr(
                              'Password must be at least 12 characters',
                              '密码至少需要 12 个字符',
                            )
                          : null,
                    ),
                    const SizedBox(height: 20),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _rememberPassword,
                      onChanged: busy
                          ? null
                          : (value) => setState(
                              () => _rememberPassword = value ?? false,
                            ),
                      title: Text(context.tr('Remember password', '记住密码')),
                      subtitle: Text(
                        context.tr(
                          'Saved by your browser or device password manager.',
                          '由浏览器或设备的密码管理器保存。',
                        ),
                      ),
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                    FilledButton(
                      onPressed: busy ? null : _signIn,
                      child: Text(
                        busy
                            ? context.tr('Signing in…', '正在登录…')
                            : context.tr('Sign in', '登录'),
                      ),
                    ),
                    if (auth.message != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        auth.message!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
