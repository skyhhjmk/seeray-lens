import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_i18n.dart';
import '../../../shared/presentation/app_back_button.dart';
import '../../../shared/presentation/page_help_button.dart';
import '../application/domain_controller.dart';

class DomainsPage extends ConsumerWidget {
  const DomainsPage({required this.siteId, super.key});

  final String siteId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final domains = ref.watch(domainsProvider(siteId));
    return Scaffold(
      appBar: AppBar(
        leading: AppBackButton(fallback: '/sites/$siteId'),
        title: Text(context.tr('Allowed domains', '允许的域名')),
        actions: const [
          PageHelpButton(
            englishTitle: 'Allowed domains',
            chineseTitle: '允许的域名',
            englishBody:
                'Only configured domains may send browser tracking events for this site. Enable subdomains only when they are part of the same tracked website.',
            chineseBody: '只有配置过的域名可以为本站点发送浏览器追踪事件。仅当子域名属于同一被追踪网站时，才启用子域名。',
          ),
          LanguageMenu(),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _add(context, ref),
        icon: const Icon(Icons.add),
        label: Text(context.tr('Add domain', '添加域名')),
      ),
      body: domains.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(
          child: FilledButton.tonal(
            onPressed: () => ref.invalidate(domainsProvider(siteId)),
            child: Text(context.tr('Retry loading domains', '重新加载域名')),
          ),
        ),
        data: (items) => items.isEmpty
            ? Center(
                child: Text(
                  context.tr('No allowed domains configured.', '尚未配置允许的域名。'),
                ),
              )
            : ListView(
                padding: const EdgeInsets.all(16),
                children: items
                    .map(
                      (domain) => Card(
                        child: ListTile(
                          title: Text(domain.host),
                          subtitle: Text(
                            domain.allowSubdomains
                                ? context.tr('Includes subdomains', '包含子域名')
                                : context.tr('Exact host only', '仅精确主机名'),
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
                            tooltip: context.tr('Delete domain', '删除域名'),
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
      widget.initial == null
          ? context.tr('Add allowed domain', '添加允许的域名')
          : context.tr('Edit allowed domain', '编辑允许的域名'),
    ),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _host,
          enabled: widget.initial == null,
          decoration: InputDecoration(
            labelText: context.tr('Host or URL', '主机名或 URL'),
            helperText: context.tr(
              'For example https://Example.com:443/path is saved as example.com.',
              '例如 https://Example.com:443/path 会保存为 example.com。',
            ),
          ),
        ),
        SwitchListTile(
          value: _subdomains,
          onChanged: (value) => setState(() => _subdomains = value),
          title: Text(context.tr('Allow subdomains', '允许子域名')),
        ),
        SwitchListTile(
          value: _enabled,
          onChanged: (value) => setState(() => _enabled = value),
          title: Text(context.tr('Enabled', '启用')),
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
          final host = _host.text.trim();
          if (host.isEmpty) return;
          Navigator.pop(context, _DomainInput(host, _subdomains, _enabled));
        },
        child: Text(context.tr('Save', '保存')),
      ),
    ],
  );
}
