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
      builder: (context) => widget.mode == ProductFeatureMode.tagManager
          ? const _ContainerEditorDialog()
          : _FeatureEditorDialog(mode: widget.mode),
    );
    if (result == null) return;
    await _run(() async {
      await ref.read(apiProvider).request('POST', _path, body: result);
      await _load();
    });
  }

  Future<void> _edit(Map<String, dynamic> item) async {
    final id = item['id'] as String?;
    if (id == null) return;
    if (widget.mode == ProductFeatureMode.tagManager) {
      final result = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => _ContainerEditorDialog(initial: item),
      );
      if (result == null) return;
      await _run(() async {
        await ref.read(apiProvider).request('PUT', '$_path/$id', body: result);
        await _load();
      });
      return;
    }
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) =>
          _FeatureEditorDialog(mode: widget.mode, initial: item),
    );
    if (result == null) return;
    await _run(() async {
      await ref.read(apiProvider).request('PUT', '$_path/$id', body: result);
      await _load();
    });
  }

  Future<void> _delete(Map<String, dynamic> item) async {
    final id = item['id'] as String?;
    if (id == null) return;
    final name = item['name'] as String? ?? id;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.tr('Delete $name?', '删除“$name”？')),
        content: Text(
          context.tr(
            'Reports and future tracking for this definition will no longer be available.',
            '删除后将无法继续查看该定义的报告，也不会再用于后续追踪。',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.tr('Cancel', '取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.tr('Delete', '删除')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _run(() async {
      await ref.read(apiProvider).request('DELETE', '$_path/$id');
      await _load();
    });
  }

  Future<void> _draft(String id) async {
    List<dynamic>? initialTags;
    try {
      final versions =
          await ref.read(apiProvider).request('GET', '$_path/$id/versions')
              as List;
      if (versions.isNotEmpty) {
        final latest = versions.whereType<Map>().first;
        if (latest['tags'] is List) initialTags = latest['tags'] as List;
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_message(error))));
      return;
    }
    if (!mounted) return;
    final result = await showDialog<List<dynamic>>(
      context: context,
      builder: (context) => _TagDraftDialog(initialTags: initialTags),
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
            IconButton(
              tooltip: context.tr('Edit', '编辑'),
              onPressed: () => _edit(item),
              icon: const Icon(Icons.edit_outlined),
            ),
            if (widget.mode == ProductFeatureMode.experiments)
              IconButton(
                tooltip: context.tr('Install snippet', '安装代码'),
                onPressed: () => _showExperimentSnippet(item),
                icon: const Icon(Icons.integration_instructions_outlined),
              ),
            IconButton(
              tooltip: context.tr('Delete', '删除'),
              onPressed: () => _delete(item),
              icon: const Icon(Icons.delete_outline),
            ),
            if (widget.mode == ProductFeatureMode.tagManager) ...[
              IconButton(
                tooltip: context.tr('Versions', '版本'),
                onPressed: () => _versions(id),
                icon: const Icon(Icons.history),
              ),
              IconButton(
                tooltip: context.tr('Edit tags', '编辑标签'),
                onPressed: () => _draft(id),
                icon: const Icon(Icons.edit_outlined),
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

  Future<void> _showExperimentSnippet(Map<String, dynamic> item) async {
    final name = item['name'] as String? ?? '';
    final snippet =
        '<script src="${widget.trackerUrl}" data-site-id="${widget.trackingId}" data-experiments="true"></script>\n'
        '<script>\n'
        '  SeeRay.ready().then(() => {\n'
        "    const variant = SeeRay.assignExperiment('$name');\n"
        '    // Render the matching experience here.\n'
        '  });\n'
        '</script>';
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.tr('Install A/B test', '安装 A/B 测试')),
        content: SizedBox(
          width: 620,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                context.tr(
                  'This snippet reads the enabled variants from this site. You do not need to keep a second variant list in your page code.',
                  '这段代码会读取该站点已启用的变体，页面代码不需要再维护另一份变体列表。',
                ),
              ),
              const SizedBox(height: 12),
              SelectableText(
                snippet,
                style: const TextStyle(fontFamily: 'monospace'),
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
      ),
    );
  }

  String _message(Object error) =>
      error is ApiFailure ? error.message : '$error';

  String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
}

class _FeatureEditorDialog extends StatefulWidget {
  const _FeatureEditorDialog({required this.mode, this.initial});

  final ProductFeatureMode mode;
  final Map<String, dynamic>? initial;

  @override
  State<_FeatureEditorDialog> createState() => _FeatureEditorDialogState();
}

class _FeatureEditorDialogState extends State<_FeatureEditorDialog> {
  late final TextEditingController _name;
  late bool _enabled;
  final _steps = <_FunnelStepForm>[];
  final _variants = <TextEditingController>[];
  String? _error;

  bool get _editing => widget.initial != null;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _name = TextEditingController(text: initial?['name'] as String? ?? '');
    _enabled = initial?['enabled'] as bool? ?? true;
    if (widget.mode == ProductFeatureMode.funnels) {
      final rawSteps = initial?['steps'];
      if (rawSteps is List) {
        _steps.addAll(rawSteps.whereType<Map>().map(_FunnelStepForm.fromJson));
      }
      if (_steps.isEmpty) _steps.add(_FunnelStepForm());
    } else {
      final rawVariants = initial?['variants'];
      if (rawVariants is List) {
        for (final variant in rawVariants.whereType<String>()) {
          _variants.add(TextEditingController(text: variant));
        }
      }
      if (_variants.isEmpty) {
        _variants.add(TextEditingController(text: 'control'));
        _variants.add(TextEditingController(text: 'new_copy'));
      }
    }
  }

  @override
  void dispose() {
    _name.dispose();
    for (final step in _steps) {
      step.dispose();
    }
    for (final variant in _variants) {
      variant.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      context.tr(
        '${_editing ? 'Edit' : 'Create'} ${_label(context)}',
        '${_editing ? '编辑' : '新建'}${_label(context)}',
      ),
    ),
    content: SizedBox(
      width: 620,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 620),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _name,
                autofocus: !_editing,
                decoration: InputDecoration(
                  labelText: context.tr('Name', '名称'),
                ),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: Text(context.tr('Enabled', '启用')),
                subtitle: Text(
                  context.tr(
                    'Disabled definitions remain available for reporting but are not used for new tracking.',
                    '停用后仍保留历史报告，但不会用于新的追踪。',
                  ),
                ),
                value: _enabled,
                onChanged: (value) => setState(() => _enabled = value),
              ),
              const Divider(),
              if (widget.mode == ProductFeatureMode.funnels)
                _buildFunnelEditor(context)
              else
                _buildExperimentEditor(context),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.tr('Cancel', '取消')),
      ),
      FilledButton(onPressed: _save, child: Text(context.tr('Save', '保存'))),
    ],
  );

  Widget _buildFunnelEditor(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        context.tr('Ordered steps', '顺序步骤'),
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 4),
      Text(
        context.tr(
          'A session advances only when it matches the next step. Reorder steps to change the journey.',
          '会话只有匹配下一个步骤才会前进。调整顺序即可改变用户路径。',
        ),
      ),
      const SizedBox(height: 12),
      for (var index = 0; index < _steps.length; index++) ...[
        _FunnelStepCard(
          index: index,
          form: _steps[index],
          canRemove: _steps.length > 2,
          onChanged: () => setState(() => _error = null),
          onRemove: () {
            setState(() {
              final removed = _steps.removeAt(index);
              removed.dispose();
            });
          },
          onMoveUp: index == 0
              ? null
              : () => setState(() {
                  final step = _steps.removeAt(index);
                  _steps.insert(index - 1, step);
                }),
          onMoveDown: index == _steps.length - 1
              ? null
              : () => setState(() {
                  final step = _steps.removeAt(index);
                  _steps.insert(index + 1, step);
                }),
        ),
        if (index != _steps.length - 1) const SizedBox(height: 10),
      ],
      const SizedBox(height: 10),
      OutlinedButton.icon(
        onPressed: () => setState(() {
          _steps.add(_FunnelStepForm());
          _error = null;
        }),
        icon: const Icon(Icons.add),
        label: Text(context.tr('Add step', '添加步骤')),
      ),
    ],
  );

  Widget _buildExperimentEditor(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        context.tr('Variants', '变体'),
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 4),
      Text(
        context.tr(
          'The first variant is the control used for lift and significance comparisons.',
          '第一个变体是对照组，用于提升比例和显著性比较。',
        ),
      ),
      const SizedBox(height: 12),
      for (var index = 0; index < _variants.length; index++)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              CircleAvatar(radius: 14, child: Text('${index + 1}')),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _variants[index],
                  onChanged: (_) => setState(() => _error = null),
                  decoration: InputDecoration(
                    labelText: index == 0
                        ? context.tr('Control variant', '对照变体')
                        : context.tr('Variant ${index + 1}', '变体 ${index + 1}'),
                  ),
                ),
              ),
              IconButton(
                tooltip: context.tr('Remove variant', '删除变体'),
                onPressed: _variants.length <= 2
                    ? null
                    : () => setState(() {
                        final removed = _variants.removeAt(index);
                        removed.dispose();
                      }),
                icon: const Icon(Icons.remove_circle_outline),
              ),
            ],
          ),
        ),
      OutlinedButton.icon(
        onPressed: () => setState(() {
          _variants.add(
            TextEditingController(text: 'variant_${_variants.length + 1}'),
          );
          _error = null;
        }),
        icon: const Icon(Icons.add),
        label: Text(context.tr('Add variant', '添加变体')),
      ),
    ],
  );

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = context.tr('Name is required.', '名称不能为空。'));
      return;
    }
    final body = <String, dynamic>{'name': name, 'enabled': _enabled};
    if (widget.mode == ProductFeatureMode.funnels) {
      if (_steps.length < 2) {
        setState(
          () => _error = context.tr(
            'A funnel needs at least two steps.',
            '漏斗至少需要两个步骤。',
          ),
        );
        return;
      }
      final steps = <Map<String, dynamic>>[];
      for (var index = 0; index < _steps.length; index++) {
        final step = _steps[index].toJson();
        if (step == null) {
          setState(
            () => _error = context.tr(
              'Step ${index + 1} is incomplete.',
              '第 ${index + 1} 个步骤未填写完整。',
            ),
          );
          return;
        }
        steps.add(step);
      }
      body['steps'] = steps;
    } else {
      final variants = _variants
          .map((controller) => controller.text.trim())
          .where((value) => value.isNotEmpty)
          .toList();
      if (variants.length < 2 || variants.toSet().length != variants.length) {
        setState(
          () => _error = context.tr(
            'Add at least two unique variants.',
            '请添加至少两个不重复的变体。',
          ),
        );
        return;
      }
      body['variants'] = variants;
    }
    Navigator.pop(context, body);
  }

  String _label(BuildContext context) =>
      widget.mode == ProductFeatureMode.funnels
      ? context.tr('funnel', '漏斗')
      : context.tr('A/B test', 'A/B 测试');
}

class _FunnelStepCard extends StatelessWidget {
  const _FunnelStepCard({
    required this.index,
    required this.form,
    required this.canRemove,
    required this.onChanged,
    required this.onRemove,
    required this.onMoveUp,
    required this.onMoveDown,
  });

  final int index;
  final _FunnelStepForm form;
  final bool canRemove;
  final VoidCallback onChanged;
  final VoidCallback onRemove;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                context.tr('Step ${index + 1}', '步骤 ${index + 1}'),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const Spacer(),
              IconButton(
                tooltip: context.tr('Move up', '上移'),
                onPressed: onMoveUp,
                icon: const Icon(Icons.arrow_upward, size: 18),
              ),
              IconButton(
                tooltip: context.tr('Move down', '下移'),
                onPressed: onMoveDown,
                icon: const Icon(Icons.arrow_downward, size: 18),
              ),
              IconButton(
                tooltip: context.tr('Remove step', '删除步骤'),
                onPressed: canRemove ? onRemove : null,
                icon: const Icon(Icons.delete_outline, size: 18),
              ),
            ],
          ),
          DropdownButtonFormField<String>(
            initialValue: form.type,
            decoration: InputDecoration(
              labelText: context.tr('Step type', '步骤类型'),
            ),
            items: [
              DropdownMenuItem(
                value: 'page_view',
                child: Text(context.tr('Page view', '页面浏览')),
              ),
              DropdownMenuItem(
                value: 'event',
                child: Text(context.tr('Event', '事件')),
              ),
            ],
            onChanged: (value) {
              if (value == null) return;
              form.type = value;
              onChanged();
            },
          ),
          const SizedBox(height: 8),
          TextField(
            controller: form.name,
            onChanged: (_) => onChanged(),
            decoration: InputDecoration(
              labelText: context.tr('Step name', '步骤名称'),
            ),
          ),
          if (form.type == 'page_view') ...[
            const SizedBox(height: 8),
            TextField(
              controller: form.path,
              onChanged: (_) => onChanged(),
              decoration: InputDecoration(
                labelText: context.tr('Page path', '页面路径'),
                hintText: '/checkout',
              ),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: form.matchMode,
              decoration: InputDecoration(
                labelText: context.tr('Path matching', '路径匹配'),
              ),
              items: [
                DropdownMenuItem(
                  value: 'exact',
                  child: Text(context.tr('Exact path', '完整匹配')),
                ),
                DropdownMenuItem(
                  value: 'contains',
                  child: Text(context.tr('Contains path', '包含匹配')),
                ),
              ],
              onChanged: (value) {
                if (value == null) return;
                form.matchMode = value;
                onChanged();
              },
            ),
          ] else ...[
            const SizedBox(height: 8),
            TextField(
              controller: form.eventType,
              onChanged: (_) => onChanged(),
              decoration: InputDecoration(
                labelText: context.tr('Event type', '事件类型'),
                hintText: 'signup',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: form.eventName,
              onChanged: (_) => onChanged(),
              decoration: InputDecoration(
                labelText: context.tr('Event name (optional)', '事件名称（可选）'),
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

class _FunnelStepForm {
  _FunnelStepForm();

  factory _FunnelStepForm.fromJson(Map value) {
    final form = _FunnelStepForm();
    form.type = value['type'] == 'event' ? 'event' : 'page_view';
    form.name.text = '${value['name'] ?? ''}';
    form.eventType.text = '${value['eventType'] ?? ''}';
    form.eventName.text = '${value['eventName'] ?? ''}';
    form.path.text = '${value['path'] ?? ''}';
    form.matchMode = value['matchMode'] == 'contains' ? 'contains' : 'exact';
    return form;
  }

  String type = 'page_view';
  String matchMode = 'exact';
  final name = TextEditingController();
  final eventType = TextEditingController();
  final eventName = TextEditingController();
  final path = TextEditingController();

  Map<String, dynamic>? toJson() {
    final stepName = name.text.trim();
    if (stepName.isEmpty) return null;
    if (type == 'page_view') {
      final value = path.text.trim();
      if (!value.startsWith('/')) return null;
      return {
        'name': stepName,
        'type': type,
        'path': value,
        'matchMode': matchMode,
      };
    }
    final event = eventType.text.trim();
    if (event.isEmpty) return null;
    final result = <String, dynamic>{
      'name': stepName,
      'type': type,
      'eventType': event,
    };
    final eventNameValue = eventName.text.trim();
    if (eventNameValue.isNotEmpty) result['eventName'] = eventNameValue;
    return result;
  }

  void dispose() {
    name.dispose();
    eventType.dispose();
    eventName.dispose();
    path.dispose();
  }
}

class _ContainerEditorDialog extends StatefulWidget {
  const _ContainerEditorDialog({this.initial});

  final Map<String, dynamic>? initial;

  @override
  State<_ContainerEditorDialog> createState() => _ContainerEditorDialogState();
}

class _ContainerEditorDialogState extends State<_ContainerEditorDialog> {
  late final TextEditingController _name;
  late bool _enabled;

  bool get _editing => widget.initial != null;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(
      text: widget.initial?['name'] as String? ?? '',
    );
    _enabled = widget.initial?['enabled'] as bool? ?? true;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      context.tr(
        '${_editing ? 'Edit' : 'Create'} container',
        '${_editing ? '编辑' : '新建'}容器',
      ),
    ),
    content: SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            autofocus: !_editing,
            decoration: InputDecoration(labelText: context.tr('Name', '名称')),
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: Text(context.tr('Enabled', '启用')),
            value: _enabled,
            onChanged: (value) => setState(() => _enabled = value),
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
          Navigator.pop(context, {'name': name, 'enabled': _enabled});
        },
        child: Text(
          context.tr(_editing ? 'Save' : 'Create', _editing ? '保存' : '新建'),
        ),
      ),
    ],
  );
}

class _TagDraftDialog extends StatefulWidget {
  const _TagDraftDialog({this.initialTags});

  final List<dynamic>? initialTags;

  @override
  State<_TagDraftDialog> createState() => _TagDraftDialogState();
}

class _TagDraftDialogState extends State<_TagDraftDialog> {
  final _tags = <_TagFormEntry>[];
  String? _error;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialTags ?? const [];
    _tags.addAll(initial.whereType<Map>().map(_TagFormEntry.fromJson));
    if (_tags.isEmpty) _tags.add(_TagFormEntry());
  }

  @override
  void dispose() {
    for (final tag in _tags) {
      tag.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(context.tr('Edit container tags', '编辑容器标签')),
    content: SizedBox(
      width: 620,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 600),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                context.tr(
                  'Choose what the tracker should send when a trigger fires.',
                  '选择触发条件以及追踪器要发送的事件。',
                ),
              ),
              const SizedBox(height: 16),
              for (var index = 0; index < _tags.length; index++) ...[
                _TagFormCard(
                  index: index,
                  entry: _tags[index],
                  canRemove: _tags.length > 1,
                  onChanged: () => setState(() => _error = null),
                  onRemove: () {
                    setState(() {
                      final removed = _tags.removeAt(index);
                      removed.dispose();
                    });
                  },
                ),
                if (index != _tags.length - 1) const SizedBox(height: 12),
              ],
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => setState(() {
                  _tags.add(_TagFormEntry());
                  _error = null;
                }),
                icon: const Icon(Icons.add),
                label: Text(context.tr('Add tag', '添加标签')),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.tr('Cancel', '取消')),
      ),
      FilledButton(
        onPressed: _save,
        child: Text(context.tr('Save draft', '保存草稿')),
      ),
    ],
  );

  void _save() {
    final tags = <Map<String, dynamic>>[];
    for (var index = 0; index < _tags.length; index++) {
      final tag = _tags[index].toJson();
      if (tag == null) {
        setState(() {
          _error = context.tr(
            'Tag ${index + 1} needs a type, a name or event type, and an event trigger.',
            '第 ${index + 1} 个标签需要类型、名称或事件类型，以及事件触发器。',
          );
        });
        return;
      }
      tags.add(tag);
    }
    Navigator.pop(context, tags);
  }
}

class _TagFormCard extends StatelessWidget {
  const _TagFormCard({
    required this.index,
    required this.entry,
    required this.canRemove,
    required this.onChanged,
    required this.onRemove,
  });

  final int index;
  final _TagFormEntry entry;
  final bool canRemove;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  context.tr('Tag ${index + 1}', '标签 ${index + 1}'),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              if (canRemove)
                IconButton(
                  tooltip: context.tr('Remove tag', '删除标签'),
                  onPressed: onRemove,
                  icon: const Icon(Icons.delete_outline),
                ),
            ],
          ),
          DropdownButtonFormField<String>(
            initialValue: entry.type,
            decoration: InputDecoration(
              labelText: context.tr('Tag type', '标签类型'),
            ),
            items: [
              DropdownMenuItem(
                value: 'event',
                child: Text(context.tr('Custom event', '自定义事件')),
              ),
              DropdownMenuItem(
                value: 'page_view',
                child: Text(context.tr('Page view', '页面浏览')),
              ),
            ],
            onChanged: (value) {
              if (value == null) return;
              entry.type = value;
              onChanged();
            },
          ),
          if (entry.type == 'event') ...[
            const SizedBox(height: 8),
            TextField(
              controller: entry.trigger,
              onChanged: (_) => onChanged(),
              decoration: InputDecoration(
                labelText: context.tr('Trigger event', '触发事件'),
                hintText: 'signup',
              ),
            ),
          ],
          const SizedBox(height: 8),
          TextField(
            controller: entry.eventType,
            onChanged: (_) => onChanged(),
            decoration: InputDecoration(
              labelText: context.tr('Sent event type', '发送的事件类型'),
              hintText: 'tag_signup',
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: entry.name,
            onChanged: (_) => onChanged(),
            decoration: InputDecoration(
              labelText: context.tr('Display name (optional)', '显示名称（可选）'),
              hintText: 'signup_tag',
            ),
          ),
          const SizedBox(height: 12),
          Text(
            context.tr('Event properties (optional)', '事件属性（可选）'),
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 4),
          for (
            var propertyIndex = 0;
            propertyIndex < entry.properties.length;
            propertyIndex++
          )
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: entry.properties[propertyIndex].key,
                      onChanged: (_) => onChanged(),
                      decoration: InputDecoration(
                        labelText: context.tr('Key', '键'),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: entry.properties[propertyIndex].value,
                      onChanged: (_) => onChanged(),
                      decoration: InputDecoration(
                        labelText: context.tr('Value', '值'),
                        isDense: true,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: context.tr('Remove property', '删除属性'),
                    onPressed: () {
                      final removed = entry.properties.removeAt(propertyIndex);
                      removed.dispose();
                      onChanged();
                    },
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                ],
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () {
                entry.properties.add(_TagPropertyEntry());
                onChanged();
              },
              icon: const Icon(Icons.add, size: 18),
              label: Text(context.tr('Add property', '添加属性')),
            ),
          ),
        ],
      ),
    ),
  );
}

class _TagFormEntry {
  _TagFormEntry();

  String type = 'event';
  final trigger = TextEditingController();
  final eventType = TextEditingController();
  final name = TextEditingController();
  final properties = <_TagPropertyEntry>[];

  factory _TagFormEntry.fromJson(Map value) {
    final entry = _TagFormEntry();
    entry.type = value['type'] == 'page_view' ? 'page_view' : 'event';
    final triggerValue = value['trigger'];
    entry.trigger.text = triggerValue is String
        ? triggerValue
        : triggerValue is Map
        ? '${triggerValue['event'] ?? ''}'
        : '';
    entry.eventType.text = '${value['eventType'] ?? ''}';
    entry.name.text = '${value['name'] ?? ''}';
    final rawProperties = value['properties'];
    if (rawProperties is Map) {
      for (final property in rawProperties.entries) {
        entry.properties.add(
          _TagPropertyEntry(
            keyValue: '${property.key}',
            valueValue: '${property.value}',
          ),
        );
      }
    }
    return entry;
  }

  Map<String, dynamic>? toJson() {
    final triggerValue = trigger.text.trim();
    final eventTypeValue = eventType.text.trim();
    final nameValue = name.text.trim();
    if ((eventTypeValue.isEmpty && nameValue.isEmpty) ||
        (type == 'event' && triggerValue.isEmpty)) {
      return null;
    }
    final result = <String, dynamic>{'type': type};
    if (triggerValue.isNotEmpty) result['trigger'] = triggerValue;
    if (eventTypeValue.isNotEmpty) result['eventType'] = eventTypeValue;
    if (nameValue.isNotEmpty) result['name'] = nameValue;
    final values = <String, String>{};
    for (final property in properties) {
      final key = property.key.text.trim();
      final value = property.value.text.trim();
      if (key.isNotEmpty) values[key] = value;
    }
    if (values.isNotEmpty) result['properties'] = values;
    return result;
  }

  void dispose() {
    trigger.dispose();
    eventType.dispose();
    name.dispose();
    for (final property in properties) {
      property.dispose();
    }
  }
}

class _TagPropertyEntry {
  _TagPropertyEntry({String keyValue = '', String valueValue = ''})
    : key = TextEditingController(text: keyValue),
      value = TextEditingController(text: valueValue);

  final TextEditingController key;
  final TextEditingController value;

  void dispose() {
    key.dispose();
    value.dispose();
  }
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
                            ? '${row['sessions'] ?? 0} sessions · ${_percent(row['rate'])}${_funnelDropOff(row)}'
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

  String _funnelDropOff(Map row) {
    final dropOff = row['dropOff'] as num?;
    if (dropOff == null || dropOff == 0) return '';
    return ' · ${dropOff.toInt()} drop-off (${_percent(row['dropOffRate'])})';
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
