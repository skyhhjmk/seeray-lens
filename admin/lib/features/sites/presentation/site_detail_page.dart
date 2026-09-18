import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../application/site_controller.dart';
import '../../../shared/presentation/timezone_picker.dart';
import '../../../core/i18n/app_i18n.dart';
import '../../../shared/presentation/app_back_button.dart';
import '../../../shared/presentation/page_help_button.dart';
import 'heatmap_settings_section.dart';

class SiteDetailPage extends ConsumerStatefulWidget {
  const SiteDetailPage({
    required this.siteId,
    this.embedded = false,
    super.key,
  });

  final String siteId;
  final bool embedded;

  @override
  ConsumerState<SiteDetailPage> createState() => _SiteDetailPageState();
}

class _SiteDetailPageState extends ConsumerState<SiteDetailPage> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _timezone = TextEditingController();
  final _language = TextEditingController();
  final _raw = TextEditingController();
  final _aggregate = TextEditingController();
  bool _enabled = true;
  bool _requireConsent = false;
  String? _loadedId;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _timezone.dispose();
    _language.dispose();
    _raw.dispose();
    _aggregate.dispose();
    super.dispose();
  }

  void _load(Site site) {
    if (_loadedId == site.id) return;
    _loadedId = site.id;
    _name.text = site.name;
    _timezone.text = site.timezone;
    _language.text = site.defaultLanguage ?? '';
    _raw.text = '${site.rawRetentionDays}';
    _aggregate.text = '${site.aggregateRetentionDays}';
    _enabled = site.trackingEnabled;
    _requireConsent = site.requireConsent;
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref.read(sitesProvider.notifier).updateSite(widget.siteId, {
        'name': _name.text.trim(),
        'timezone': _timezone.text.trim(),
        'defaultLanguage': _language.text.trim().isEmpty
            ? null
            : _language.text.trim(),
        'trackingEnabled': _enabled,
        'requireConsent': _requireConsent,
        'rawRetentionDays': int.parse(_raw.text),
        'aggregateRetentionDays': int.parse(_aggregate.text),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('Site saved', '站点已保存'))),
        );
      }
    } on Exception catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final sites = ref.watch(sitesProvider).value ?? const <Site>[];
    final site = sites.where((item) => item.id == widget.siteId).firstOrNull;
    if (site == null) {
      return Scaffold(
        body: Center(child: Text(context.tr('Site not found', '未找到站点'))),
      );
    }
    _load(site);
    return Scaffold(
      appBar: widget.embedded
          ? null
          : AppBar(
              backgroundColor: const Color(0xff202b3b),
              foregroundColor: Colors.white,
              leading: AppBackButton(fallback: '/sites/${site.id}/dashboard'),
              title: Text(site.name),
              actions: const [
                PageHelpButton(
                  englishTitle: 'Site settings',
                  chineseTitle: '站点设置',
                  englishBody:
                      'The site time zone determines reporting dates. Keep the tracking ID private to your integration, and allow only domains that are permitted to send events.',
                  chineseBody: '站点时区决定统计日期。请仅在集成中使用追踪 ID，并只允许获准发送事件的域名。',
                ),
                LanguageMenu(),
              ],
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(48),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.only(left: 12, bottom: 8),
                  child: Row(
                    children: [
                      _SiteTab(
                        context.tr('Dashboard', '仪表盘'),
                        '/sites/${site.id}/dashboard',
                      ),
                      _SiteTab(
                        context.tr('Visitors', '访客'),
                        '/sites/${site.id}/visitors',
                      ),
                      _SiteTab(
                        context.tr('Acquisition', '流量获取'),
                        '/sites/${site.id}/acquisition',
                      ),
                      _SiteTab(
                        context.tr('Behaviour', '用户行为'),
                        '/sites/${site.id}/behaviour',
                      ),
                      _SiteTab(
                        context.tr('Goals', '目标'),
                        '/sites/${site.id}/goals',
                      ),
                      _SiteTab(
                        context.tr('Integration', '集成'),
                        '/sites/${site.id}/integration',
                      ),
                      _SiteTab(
                        context.tr('Settings', '站点设置'),
                        '/sites/${site.id}',
                        selected: true,
                      ),
                    ],
                  ),
                ),
              ),
            ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: _name,
                      decoration: InputDecoration(
                        labelText: context.tr('Site name', '站点名称'),
                      ),
                      validator: _required,
                    ),
                    TimezonePicker(controller: _timezone),
                    TextField(
                      controller: _language,
                      decoration: InputDecoration(
                        labelText: context.tr('Default language', '默认语言'),
                      ),
                    ),
                    SwitchListTile(
                      value: _enabled,
                      onChanged: (value) => setState(() => _enabled = value),
                      title: Text(context.tr('Tracking enabled', '启用追踪')),
                    ),
                    SwitchListTile(
                      value: _requireConsent,
                      onChanged: (value) =>
                          setState(() => _requireConsent = value),
                      title: Text(
                        context.tr('Require visitor consent', '需要访客同意'),
                      ),
                      subtitle: Text(
                        context.tr(
                          'New tracker snippets wait for an explicit choice. After changing this policy, replace previously copied snippets. Visitors can reject or withdraw later.',
                          '新生成的追踪代码会等待访客明确选择。修改策略后请替换之前复制的代码；访客可以拒绝或之后撤回同意。',
                        ),
                      ),
                    ),
                    TextFormField(
                      controller: _raw,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: context.tr('Raw retention days', '原始事件保留天数'),
                      ),
                      validator: _positive,
                    ),
                    TextFormField(
                      controller: _aggregate,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: context.tr(
                          'Aggregate retention days',
                          '聚合数据保留天数',
                        ),
                      ),
                      validator: _positive,
                    ),
                    const SizedBox(height: 12),
                    Text(context.tr('Tracking ID', '追踪 ID')),
                    SelectableText(site.trackingId),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _saving ? null : _save,
                      child: Text(
                        _saving
                            ? context.tr('Saving…', '正在保存…')
                            : context.tr('Save changes', '保存修改'),
                      ),
                    ),
                    HeatmapSettingsSection(siteId: site.id),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => context.go('/sites/${site.id}/domains'),
                icon: const Icon(Icons.language),
                label: Text(context.tr('Allowed domains', '允许的域名')),
              ),
              OutlinedButton.icon(
                onPressed: () => context.go('/sites/${site.id}/integration'),
                icon: const Icon(Icons.integration_instructions_outlined),
                label: Text(context.tr('Tracking integration', '追踪集成')),
              ),
              TextButton(
                onPressed: () async {
                  await ref.read(sitesProvider.notifier).delete(site.id);
                  if (context.mounted) context.go('/sites');
                },
                child: Text(context.tr('Delete site', '删除站点')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SiteTab extends StatelessWidget {
  const _SiteTab(this.label, this.route, {this.selected = false});
  final String label;
  final String route;
  final bool selected;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 6),
    child: TextButton(
      onPressed: selected ? null : () => context.go(route, extra: -1),
      style: TextButton.styleFrom(
        foregroundColor: selected ? Colors.white : const Color(0xffc7d1df),
        backgroundColor: selected
            ? const Color(0xff385172)
            : Colors.transparent,
      ),
      child: Text(label),
    ),
  );
}

String? _required(String? value) =>
    value == null || value.trim().isEmpty ? 'Required' : null;

String? _positive(String? value) =>
    int.tryParse(value ?? '') == null || int.parse(value!) < 1
    ? 'Enter a positive number'
    : null;

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
