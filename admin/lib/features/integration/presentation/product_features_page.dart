import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_i18n.dart';
import '../../../core/network/seeray_api.dart';
import '../../auth/application/auth_controller.dart';

enum ProductFeatureMode { funnels, experiments, tagManager }

class ProductFeaturesPage extends ConsumerStatefulWidget {
  const ProductFeaturesPage({
    required this.siteId,
    required this.trackingId,
    required this.trackerUrl,
    required this.mode,
    super.key,
  });

  final String siteId;
  final String trackingId;
  final String trackerUrl;
  final ProductFeatureMode mode;

  @override
  ConsumerState<ProductFeaturesPage> createState() =>
      _ProductFeaturesPageState();
}

class _ProductFeaturesPageState extends ConsumerState<ProductFeaturesPage> {
  List<Map<String, dynamic>> _items = const [];
  final Map<String, int> _draftVersions = {};
  bool _loading = true;
  String? _error;

  String get _path => switch (widget.mode) {
    ProductFeatureMode.funnels => '/api/v1/sites/${widget.siteId}/funnels',
    ProductFeatureMode.experiments =>
      '/api/v1/sites/${widget.siteId}/experiments',
    ProductFeatureMode.tagManager =>
      '/api/v1/sites/${widget.siteId}/tag-manager/containers',
  };

  String get _title => switch (widget.mode) {
    ProductFeatureMode.funnels => context.tr('Funnels', '漏斗'),
    ProductFeatureMode.experiments => context.tr('A/B tests', 'A/B 测试'),
    ProductFeatureMode.tagManager => context.tr('Tag Manager', 'Tag Manager'),
  };

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_load);
  }

  @override
  void didUpdateWidget(covariant ProductFeaturesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.siteId != widget.siteId || oldWidget.mode != widget.mode) {
      _draftVersions.clear();
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await ref.read(apiProvider).request('GET', _path) as List;
      if (!mounted) return;
      setState(() {
        _items = data
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList(growable: false);
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _message(error);
      });
    }
  }

  Future<void> _create() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _CreateDialog(mode: widget.mode),
    );
    if (result == null) return;
    await _run(() async {
      await ref.read(apiProvider).request('POST', _path, body: result);
      await _load();
    });
  }

  Future<void> _draft(String id) async {
    final result = await showDialog<List<dynamic>>(
      context: context,
      builder: (context) => const _TagDraftDialog(),
    );
    if (result == null) return;
    await _run(() async {
      final data =
          await ref
                  .read(apiProvider)
                  .request('POST', '$_path/$id/versions', body: result)
              as Map;
      _draftVersions[id] = (data['version'] as num).toInt();
      if (mounted) setState(() {});
    });
  }

  Future<void> _publish(String id) async {
    final version = _draftVersions[id];
    if (version == null) return;
    await _publishVersion(id, version);
  }

  Future<void> _publishVersion(String id, int version) async {
    await _run(() async {
      await ref
          .read(apiProvider)
          .request('POST', '$_path/$id/versions/$version/publish');
      _draftVersions.remove(id);
      await _load();
    });
  }

  Future<void> _versions(String id) async {
    await _run(() async {
      final data =
          await ref.read(apiProvider).request('GET', '$_path/$id/versions')
              as List;
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => _VersionsDialog(
          versions: data
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList(growable: false),
          onPublish: (version) async {
            Navigator.of(context).pop();
            await _publishVersion(id, version);
          },
        ),
      );
    });
  }

  Future<void> _report(String id) async {
    final now = DateTime.now();
    final from = _date(now.subtract(const Duration(days: 29)));
    final to = _date(now);
    final path = '$_path/$id/report?from=$from&to=$to';
    await _run(() async {
      final data = await ref.read(apiProvider).request('GET', path) as Map;
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => _ReportDialog(mode: widget.mode, report: data),
      );
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_message(error))));
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      Row(
        children: [
          Expanded(
            child: Text(_title, style: Theme.of(context).textTheme.titleLarge),
          ),
          IconButton(
            tooltip: context.tr('Refresh', '刷新'),
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
          FilledButton.icon(
            onPressed: _loading ? null : _create,
            icon: const Icon(Icons.add),
            label: Text(context.tr('Create', '新建')),
          ),
        ],
      ),
      const SizedBox(height: 12),
      if (_error != null)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(_error!),
          ),
        ),
      if (widget.mode == ProductFeatureMode.tagManager)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr('Install the published container', '安装已发布容器'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                SelectableText(
                  '<script src="${widget.trackerUrl}" data-site-id="${widget.trackingId}" data-tag-manager="true"></script>',
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
                const SizedBox(height: 8),
                Text(
                  context.tr(
                    'Only event and page-view tags are executed by the tracker. HTML and arbitrary scripts are ignored.',
                    '追踪器只执行 event 和 page_view 标签；HTML 与任意脚本会被忽略。',
                  ),
                ),
              ],
            ),
          ),
        ),
      if (_loading)
        const Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: CircularProgressIndicator()),
        )
      else if (_items.isEmpty)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Text(context.tr('Nothing configured yet.', '还没有配置。')),
          ),
        )
      else
        ..._items.map(_card),
    ],
  );

  Widget _card(Map<String, dynamic> item) {
    final id = item['id'] as String? ?? '';
    final name = item['name'] as String? ?? id;
    final enabled = item['enabled'] as bool? ?? true;
    final variants = (item['variants'] as List?)?.join(', ');
    final steps = (item['steps'] as List?)?.length;
    final published = item['publishedVersion'];
    final draft = _draftVersions[id];
    return Card(
      child: ListTile(
        leading: Icon(switch (widget.mode) {
          ProductFeatureMode.funnels => Icons.filter_alt_outlined,
          ProductFeatureMode.experiments => Icons.science_outlined,
          ProductFeatureMode.tagManager => Icons.sell_outlined,
        }),
        title: Text(name),
        subtitle: Text(switch (widget.mode) {
          ProductFeatureMode.funnels => context.tr(
            '$steps ordered steps',
            '$steps 个顺序步骤',
          ),
          ProductFeatureMode.experiments => variants ?? '',
          ProductFeatureMode.tagManager => context.tr(
            'Published version: ${published ?? "none"}',
            '已发布版本：${published ?? "无"}',
          ),
        }),
        trailing: Wrap(
          spacing: 4,
          children: [
            if (widget.mode != ProductFeatureMode.tagManager)
              IconButton(
                tooltip: context.tr('Report', '报告'),
                onPressed: () => _report(id),
                icon: const Icon(Icons.bar_chart_outlined),
              ),
            if (widget.mode == ProductFeatureMode.tagManager) ...[
              IconButton(
                tooltip: context.tr('Versions', '版本'),
                onPressed: () => _versions(id),
                icon: const Icon(Icons.history),
              ),
              IconButton(
                tooltip: context.tr('Draft JSON', '编辑 JSON 草稿'),
                onPressed: () => _draft(id),
                icon: const Icon(Icons.edit_note_outlined),
              ),
              if (draft != null)
                IconButton(
                  tooltip: context.tr('Publish v$draft', '发布 v$draft'),
                  onPressed: () => _publish(id),
                  icon: const Icon(Icons.publish_outlined),
                ),
            ],
            if (!enabled) const Icon(Icons.pause_circle_outline),
          ],
        ),
      ),
    );
  }

  String _message(Object error) =>
      error is ApiFailure ? error.message : '$error';

  String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
}

class _CreateDialog extends StatefulWidget {
  const _CreateDialog({required this.mode});

  final ProductFeatureMode mode;

  @override
  State<_CreateDialog> createState() => _CreateDialogState();
}

class _CreateDialogState extends State<_CreateDialog> {
  final _name = TextEditingController();
  final _variants = TextEditingController(text: 'control, new_copy');
  final _steps = TextEditingController(text: 'Page: /landing\nEvent: signup');

  @override
  void dispose() {
    _name.dispose();
    _variants.dispose();
    _steps.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      context.tr('Create ${_label(context)}', '新建${_label(context)}'),
    ),
    content: SizedBox(
      width: 480,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            decoration: InputDecoration(labelText: context.tr('Name', '名称')),
          ),
          if (widget.mode == ProductFeatureMode.experiments)
            TextField(
              controller: _variants,
              decoration: InputDecoration(
                labelText: context.tr('Variants (comma separated)', '变体（逗号分隔）'),
              ),
            ),
          if (widget.mode == ProductFeatureMode.funnels)
            TextField(
              controller: _steps,
              minLines: 2,
              maxLines: 5,
              decoration: InputDecoration(
                labelText: context.tr(
                  'Steps: Page: /path or Event: event_type',
                  '步骤：Page: /path 或 Event: event_type',
                ),
              ),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.tr('Cancel', '取消')),
      ),
      FilledButton(
        onPressed: () {
          final name = _name.text.trim();
          if (name.isEmpty) return;
          final body = switch (widget.mode) {
            ProductFeatureMode.funnels => {
              'name': name,
              'steps': _parseSteps(_steps.text),
            },
            ProductFeatureMode.experiments => {
              'name': name,
              'variants': _variants.text
                  .split(',')
                  .map((value) => value.trim())
                  .where((value) => value.isNotEmpty)
                  .toList(),
            },
            ProductFeatureMode.tagManager => {'name': name},
          };
          Navigator.pop(context, body);
        },
        child: Text(context.tr('Create', '新建')),
      ),
    ],
  );

  String _label(BuildContext context) => switch (widget.mode) {
    ProductFeatureMode.funnels => context.tr('funnel', '漏斗'),
    ProductFeatureMode.experiments => context.tr('A/B test', 'A/B 测试'),
    ProductFeatureMode.tagManager => context.tr('container', '容器'),
  };

  List<Map<String, String>> _parseSteps(String value) => value
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .map((line) {
        final separator = line.indexOf(':');
        final kind = separator < 0
            ? 'event'
            : line.substring(0, separator).trim().toLowerCase();
        final target = separator < 0
            ? line
            : line.substring(separator + 1).trim();
        return kind == 'page'
            ? {'name': target, 'type': 'page_view', 'path': target}
            : {'name': target, 'type': 'event', 'eventType': target};
      })
      .toList();
}

class _TagDraftDialog extends StatefulWidget {
  const _TagDraftDialog();

  @override
  State<_TagDraftDialog> createState() => _TagDraftDialogState();
}

class _TagDraftDialogState extends State<_TagDraftDialog> {
  final _json = TextEditingController(
    text:
        '[\n  {"type": "event", "trigger": "signup", "eventType": "tag_signup", "name": "signup_tag"}\n]',
  );
  String? _error;

  @override
  void dispose() {
    _json.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(context.tr('Draft container JSON', '编辑容器 JSON 草稿')),
    content: SizedBox(
      width: 560,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _json,
            minLines: 8,
            maxLines: 16,
            style: const TextStyle(fontFamily: 'monospace'),
            decoration: InputDecoration(
              labelText: context.tr('Tags array', '标签数组'),
              errorText: _error,
              border: const OutlineInputBorder(),
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.tr('Cancel', '取消')),
      ),
      FilledButton(
        onPressed: () {
          try {
            final value = jsonDecode(_json.text);
            if (value is! List) {
              throw const FormatException('Expected an array');
            }
            Navigator.pop(context, value);
          } on FormatException catch (error) {
            setState(() => _error = error.message);
          }
        },
        child: Text(context.tr('Save draft', '保存草稿')),
      ),
    ],
  );
}

class _ReportDialog extends StatelessWidget {
  const _ReportDialog({required this.mode, required this.report});

  final ProductFeatureMode mode;
  final Map report;

  @override
  Widget build(BuildContext context) {
    final rows = mode == ProductFeatureMode.funnels
        ? ((report['steps'] as List?) ?? const [])
        : ((report['variants'] as List?) ?? const []);
    return AlertDialog(
      title: Text(report['name'] as String? ?? context.tr('Report', '报告')),
      content: SizedBox(
        width: 520,
        child: rows.isEmpty
            ? Text(context.tr('No data yet.', '暂无数据。'))
            : ListView(
                shrinkWrap: true,
                children: [
                  for (final row in rows.whereType<Map>())
                    ListTile(
                      title: Text(
                        row['name'] as String? ??
                            row['variant'] as String? ??
                            '',
                      ),
                      subtitle: Text(
                        mode == ProductFeatureMode.funnels
                            ? '${row['sessions'] ?? 0} sessions · ${_percent(row['rate'])}'
                            : '${row['exposures'] ?? 0} exposures · ${row['conversions'] ?? 0} conversions · ${_percent(row['conversionRate'])}${_experimentComparison(row)}',
                      ),
                    ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.tr('Close', '关闭')),
        ),
      ],
    );
  }

  String _percent(dynamic value) =>
      '${(((value as num?)?.toDouble() ?? 0) * 100).toStringAsFixed(1)}%';

  String _experimentComparison(Map row) {
    if (mode != ProductFeatureMode.experiments || row['relativeLift'] == null) {
      return '';
    }
    final lift = (row['relativeLift'] as num).toDouble() * 100;
    final marker = row['statisticallySignificant'] == true
        ? ' · significant'
        : '';
    return ' · ${lift >= 0 ? '+' : ''}${lift.toStringAsFixed(1)}% lift$marker';
  }
}

class _VersionsDialog extends StatelessWidget {
  const _VersionsDialog({required this.versions, required this.onPublish});

  final List<Map<String, dynamic>> versions;
  final Future<void> Function(int version) onPublish;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(context.tr('Container versions', '容器版本')),
    content: SizedBox(
      width: 480,
      child: versions.isEmpty
          ? Text(context.tr('No versions yet.', '暂无版本。'))
          : ListView(
              shrinkWrap: true,
              children: [
                for (final version in versions)
                  ListTile(
                    title: Text('v${version['version'] ?? ''}'),
                    subtitle: Text(version['status'] as String? ?? 'draft'),
                    trailing: version['status'] == 'published'
                        ? const Icon(Icons.check_circle_outline)
                        : TextButton(
                            onPressed: () =>
                                onPublish((version['version'] as num).toInt()),
                            child: Text(context.tr('Publish', '发布')),
                          ),
                  ),
              ],
            ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.tr('Close', '关闭')),
      ),
    ],
  );
}
