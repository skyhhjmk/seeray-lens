import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_i18n.dart';
import '../../../shared/presentation/app_back_button.dart';
import '../../../shared/presentation/page_help_button.dart';
import '../application/token_controller.dart';

class TokenSettingsPage extends ConsumerWidget {
  const TokenSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(apiTokensProvider);
    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(fallback: '/sites'),
        title: Text(context.tr('Workspace API tokens', '工作区 API 令牌')),
        actions: const [
          PageHelpButton(
            englishTitle: 'API tokens',
            chineseTitle: 'API 令牌',
            englishBody:
                'API tokens allow server-to-server access to this workspace. Choose the least privilege needed, copy a new token immediately, and revoke it if it is no longer needed.',
            chineseBody: 'API 令牌用于服务端访问当前工作区。请按最小权限创建、立即保存新令牌，并在不再需要时撤销。',
          ),
          LanguageMenu(),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _create(context, ref),
        icon: const Icon(Icons.key),
        label: Text(context.tr('Create token', '创建令牌')),
      ),
      body: tokens.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(
          child: FilledButton.tonal(
            onPressed: () => ref.invalidate(apiTokensProvider),
            child: Text(context.tr('Retry loading tokens', '重新加载令牌')),
          ),
        ),
        data: (items) => ListView(
          padding: const EdgeInsets.all(16),
          children: items
              .map(
                (token) => Card(
                  child: ListTile(
                    title: Text(token.name),
                    subtitle: Text(
                      '${token.prefix} • ${token.scopes}\nCreated ${token.createdAt}${token.expiresAt == null ? '' : '\nExpires ${token.expiresAt}'}',
                    ),
                    trailing: token.revokedAt == null
                        ? TextButton(
                            onPressed: () => ref
                                .read(apiTokensProvider.notifier)
                                .revoke(token.id),
                            child: Text(context.tr('Revoke', '撤销')),
                          )
                        : Chip(label: Text(context.tr('Revoked', '已撤销'))),
                  ),
                ),
              )
              .toList(),
        ),
      ),
    );
  }

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final input = await showDialog<_TokenInput>(
      context: context,
      builder: (_) => const _CreateTokenDialog(),
    );
    if (input == null) {
      return;
    }
    try {
      final created = await ref
          .read(apiTokensProvider.notifier)
          .create(input.name, input.scopes);
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(context.tr('Copy this token now', '立即复制此令牌')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.tr(
                  'Save this token now. You cannot view it again after closing this dialog.',
                  '请立即保存此令牌。关闭此对话框后将无法再次查看。',
                ),
              ),
              const SizedBox(height: 12),
              SelectableText(created.plainToken),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.tr('Close', '关闭')),
            ),
            TextButton(
              onPressed: () async {
                await Clipboard.setData(
                  ClipboardData(text: created.plainToken),
                );
                if (context.mounted) Navigator.pop(context);
              },
              child: Text(context.tr('Copy and close', '复制并关闭')),
            ),
          ],
        ),
      );
    } on Exception catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }
}

class _TokenInput {
  const _TokenInput(this.name, this.scopes);
  final String name;
  final List<String> scopes;
}

class _CreateTokenDialog extends StatefulWidget {
  const _CreateTokenDialog();

  @override
  State<_CreateTokenDialog> createState() => _CreateTokenDialogState();
}

class _CreateTokenDialogState extends State<_CreateTokenDialog> {
  final _name = TextEditingController();
  bool _read = true;
  bool _write = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(context.tr('Create API token', '创建 API 令牌')),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _name,
          decoration: InputDecoration(
            labelText: context.tr('Token name', '令牌名称'),
          ),
        ),
        CheckboxListTile(
          value: _read,
          onChanged: (value) => setState(() => _read = value ?? false),
          title: Text(context.tr('Sites: read', '站点：读取')),
        ),
        CheckboxListTile(
          value: _write,
          onChanged: (value) => setState(() => _write = value ?? false),
          title: Text(context.tr('Sites: write', '站点：写入')),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.tr('Cancel', '取消')),
      ),
      FilledButton(
        onPressed: () {
          if (_name.text.trim().isEmpty || (!_read && !_write)) return;
          Navigator.pop(
            context,
            _TokenInput(_name.text.trim(), [
              if (_read) 'sites:read',
              if (_write) 'sites:write',
            ]),
          );
        },
        child: Text(context.tr('Create', '创建')),
      ),
    ],
  );
}
