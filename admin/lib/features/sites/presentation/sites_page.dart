import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../workspaces/application/workspace_controller.dart';
import '../../../shared/presentation/timezone_picker.dart';
import '../../../core/i18n/app_i18n.dart';
import '../../../shared/presentation/page_help_button.dart';
import '../application/site_controller.dart';

class SitesPage extends ConsumerWidget {
  const SitesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workspace = ref.watch(currentWorkspaceProvider);
    final sites = ref.watch(sitesProvider);
    if (workspace == null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => context.go('/workspaces'),
      );
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(
        title: Text('${workspace.name} ${context.tr('sites', '站点')}'),
        leading: IconButton(
          onPressed: () => context.go('/workspaces'),
          icon: const Icon(Icons.business),
        ),
        actions: [
          const PageHelpButton(
            englishTitle: 'Sites',
            chineseTitle: '站点管理',
            englishBody:
                'A site represents one tracked website. Open a site to see its analytics, then use settings to manage its time zone, tracker ID and allowed domains.',
            chineseBody: '一个站点对应一个被追踪的网站。打开站点可查看分析数据；在设置中管理时区、追踪 ID 和允许的域名。',
          ),
          const LanguageMenu(),
          IconButton(
            tooltip: context.tr('Workspace API tokens', '工作区 API 令牌'),
            onPressed: () => context.go('/settings'),
            icon: const Icon(Icons.key),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showSiteForm(context, ref),
        icon: const Icon(Icons.add),
        label: Text(context.tr('Create site', '创建站点')),
      ),
      body: sites.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(
          child: FilledButton.tonal(
            onPressed: () => ref.invalidate(sitesProvider),
            child: Text(context.tr('Retry loading sites', '重新加载站点')),
          ),
        ),
        data: (items) => items.isEmpty
            ? Center(
                child: Text(
                  context.tr(
                    'No sites yet. Create your first site.',
                    '暂无站点，创建你的第一个站点。',
                  ),
                ),
              )
            : ListView(
                padding: const EdgeInsets.all(16),
                children: items
                    .map(
                      (site) => Card(
                        child: ListTile(
                          title: Text(site.name),
                          subtitle: Text(site.trackingId),
                          trailing: Icon(
                            site.trackingEnabled
                                ? Icons.toggle_on
                                : Icons.toggle_off,
                            color: site.trackingEnabled
                                ? Theme.of(context).colorScheme.primary
                                : null,
                          ),
                          onTap: () =>
                              context.go('/sites/${site.id}/dashboard'),
                        ),
                      ),
                    )
                    .toList(),
              ),
      ),
    );
  }

  Future<void> _showSiteForm(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const _SiteFormDialog(),
    );
    if (result == null) return;
    try {
      final site = await ref.read(sitesProvider.notifier).create(result);
      if (context.mounted) {
        context.go('/sites/${site.id}/dashboard');
      }
    } on Exception catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }
}

class _SiteFormDialog extends StatefulWidget {
  const _SiteFormDialog();

  @override
  State<_SiteFormDialog> createState() => _SiteFormDialogState();
}

class _SiteFormDialogState extends State<_SiteFormDialog> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _timezone = TextEditingController(text: 'UTC');
  final _language = TextEditingController();
  final _raw = TextEditingController(text: '30');
  final _aggregate = TextEditingController(text: '730');

  @override
  void dispose() {
    _name.dispose();
    _timezone.dispose();
    _language.dispose();
    _raw.dispose();
    _aggregate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Create site'),
    content: SingleChildScrollView(
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Name'),
              validator: _required,
            ),
            TimezonePicker(controller: _timezone),
            TextField(
              controller: _language,
              decoration: const InputDecoration(
                labelText: 'Default language (optional)',
              ),
            ),
            TextFormField(
              controller: _raw,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Raw retention days',
              ),
              validator: _positive,
            ),
            TextFormField(
              controller: _aggregate,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Aggregate retention days',
              ),
              validator: _positive,
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (!_form.currentState!.validate()) return;
          Navigator.pop(context, {
            'name': _name.text.trim(),
            'timezone': _timezone.text.trim(),
            'defaultLanguage': _language.text.trim().isEmpty
                ? null
                : _language.text.trim(),
            'rawRetentionDays': int.parse(_raw.text),
            'aggregateRetentionDays': int.parse(_aggregate.text),
          });
        },
        child: const Text('Create'),
      ),
    ],
  );
}

String? _required(String? value) =>
    value == null || value.trim().isEmpty ? 'Required' : null;

String? _positive(String? value) =>
    int.tryParse(value ?? '') == null || int.parse(value!) < 1
    ? 'Enter a positive number'
    : null;
