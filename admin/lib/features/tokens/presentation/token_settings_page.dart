import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/token_controller.dart';

class TokenSettingsPage extends ConsumerWidget {
  const TokenSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(apiTokensProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Workspace API tokens')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _create(context, ref),
        icon: const Icon(Icons.key),
        label: const Text('Create token'),
      ),
      body: tokens.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(
          child: FilledButton.tonal(
            onPressed: () => ref.invalidate(apiTokensProvider),
            child: const Text('Retry loading tokens'),
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
                            child: const Text('Revoke'),
                          )
                        : const Chip(label: Text('Revoked')),
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
          title: const Text('Copy this token now'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Save this token now. You cannot view it again after closing this dialog.',
              ),
              const SizedBox(height: 12),
              SelectableText(created.plainToken),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
            TextButton(
              onPressed: () async {
                await Clipboard.setData(
                  ClipboardData(text: created.plainToken),
                );
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('Copy and close'),
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
    title: const Text('Create API token'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _name,
          decoration: const InputDecoration(labelText: 'Token name'),
        ),
        CheckboxListTile(
          value: _read,
          onChanged: (value) => setState(() => _read = value ?? false),
          title: const Text('Sites: read'),
        ),
        CheckboxListTile(
          value: _write,
          onChanged: (value) => setState(() => _write = value ?? false),
          title: const Text('Sites: write'),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
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
        child: const Text('Create'),
      ),
    ],
  );
}
