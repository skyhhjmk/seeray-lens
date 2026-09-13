import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/domain_controller.dart';

class DomainsPage extends ConsumerWidget {
  const DomainsPage({required this.siteId, super.key});

  final String siteId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final domains = ref.watch(domainsProvider(siteId));
    return Scaffold(
      appBar: AppBar(title: const Text('Allowed domains')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _add(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Add domain'),
      ),
      body: domains.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(
          child: FilledButton.tonal(
            onPressed: () => ref.invalidate(domainsProvider(siteId)),
            child: const Text('Retry loading domains'),
          ),
        ),
        data: (items) => items.isEmpty
            ? const Center(child: Text('No allowed domains configured.'))
            : ListView(
                padding: const EdgeInsets.all(16),
                children: items
                    .map(
                      (domain) => Card(
                        child: ListTile(
                          title: Text(domain.host),
                          subtitle: Text(
                            domain.allowSubdomains
                                ? 'Includes subdomains'
                                : 'Exact host only',
                          ),
                          leading: Switch(
                            value: domain.enabled,
                            onChanged: (enabled) => ref
                                .read(domainsProvider(siteId).notifier)
                                .updateDomain(
                                  domain,
                                  allowSubdomains: domain.allowSubdomains,
                                  enabled: enabled,
                                ),
                          ),
                          trailing: IconButton(
                            tooltip: 'Delete domain',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => ref
                                .read(domainsProvider(siteId).notifier)
                                .deleteDomain(domain.id),
                          ),
                          onTap: () => _edit(context, ref, domain),
                        ),
                      ),
                    )
                    .toList(),
              ),
      ),
    );
  }

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final input = await showDialog<_DomainInput>(
      context: context,
      builder: (_) => const _DomainDialog(),
    );
    if (input == null) {
      return;
    }
    try {
      await ref
          .read(domainsProvider(siteId).notifier)
          .create(input.host, input.allowSubdomains, input.enabled);
    } on Exception catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    AllowedDomain domain,
  ) async {
    final input = await showDialog<_DomainInput>(
      context: context,
      builder: (_) => _DomainDialog(initial: domain),
    );
    if (input == null) return;
    await ref
        .read(domainsProvider(siteId).notifier)
        .updateDomain(
          domain,
          allowSubdomains: input.allowSubdomains,
          enabled: input.enabled,
        );
  }
}

class _DomainInput {
  const _DomainInput(this.host, this.allowSubdomains, this.enabled);
  final String host;
  final bool allowSubdomains;
  final bool enabled;
}

class _DomainDialog extends StatefulWidget {
  const _DomainDialog({this.initial});
  final AllowedDomain? initial;

  @override
  State<_DomainDialog> createState() => _DomainDialogState();
}

class _DomainDialogState extends State<_DomainDialog> {
  late final TextEditingController _host;
  late bool _subdomains;
  late bool _enabled;

  @override
  void initState() {
    super.initState();
    _host = TextEditingController(text: widget.initial?.host ?? '');
    _subdomains = widget.initial?.allowSubdomains ?? false;
    _enabled = widget.initial?.enabled ?? true;
  }

  @override
  void dispose() {
    _host.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.initial == null ? 'Add allowed domain' : 'Edit allowed domain',
    ),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _host,
          enabled: widget.initial == null,
          decoration: const InputDecoration(
            labelText: 'Host or URL',
            helperText:
                'For example https://Example.com:443/path is saved as example.com.',
          ),
        ),
        SwitchListTile(
          value: _subdomains,
          onChanged: (value) => setState(() => _subdomains = value),
          title: const Text('Allow subdomains'),
        ),
        SwitchListTile(
          value: _enabled,
          onChanged: (value) => setState(() => _enabled = value),
          title: const Text('Enabled'),
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
          final host = _host.text.trim();
          if (host.isEmpty) return;
          Navigator.pop(context, _DomainInput(host, _subdomains, _enabled));
        },
        child: const Text('Save'),
      ),
    ],
  );
}
