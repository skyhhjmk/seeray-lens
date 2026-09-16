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
                    'The tracker supports event tags, page-view tags, and custom HTML/JavaScript snippets. Published snippets run in the visitor\'s page, so only publish code you trust.',
                    '追踪器支持事件标签、页面浏览标签，以及自定义 HTML/JavaScript 代码段。已发布代码会在访客页面执行，请只发布可信代码。',
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
  final _savedTags = <_TagFormEntry>[];
  final _dirtyTags = <bool>[];
  var _selectedIndex = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialTags ?? const [];
    _tags.addAll(initial.whereType<Map>().map(_TagFormEntry.fromJson));
    if (_tags.isEmpty) _tags.add(_TagFormEntry());
    _savedTags.addAll(_tags.map((entry) => entry.clone()));
    _dirtyTags.addAll(List<bool>.filled(_tags.length, false));
  }

  @override
  void dispose() {
    for (final tag in _tags) {
      tag.dispose();
    }
    for (final tag in _savedTags) {
      tag.dispose();
    }
    super.dispose();
  }

  double _editorHeight(BuildContext context) =>
      (MediaQuery.sizeOf(context).height - 220).clamp(320.0, 540.0).toDouble();

  void _addTag() {
    setState(() {
      final tag = _TagFormEntry();
      _tags.add(tag);
      _savedTags.add(tag.clone());
      _dirtyTags.add(false);
      _selectedIndex = _tags.length - 1;
      _error = null;
    });
  }

  void _removeTag(int index) {
    if (_tags.length <= 1) return;
    setState(() {
      _tags.removeAt(index).dispose();
      _savedTags.removeAt(index).dispose();
      _dirtyTags.removeAt(index);
      if (_selectedIndex >= _tags.length) {
        _selectedIndex = _tags.length - 1;
      } else if (_selectedIndex > index) {
        _selectedIndex--;
      }
      _error = null;
    });
  }

  void _markTagChanged(int index) {
    if (!mounted) return;
    setState(() {
      _dirtyTags[index] = true;
      _error = null;
    });
  }

  void _saveTagChanges(int index) {
    final tag = _tags[index].toJson();
    if (tag == null) {
      setState(() {
        _selectedIndex = index;
        _error = _tagValidationMessage(index);
      });
      return;
    }
    setState(() {
      _savedTags[index].dispose();
      _savedTags[index] = _tags[index].clone();
      _dirtyTags[index] = false;
      _selectedIndex = index;
      _error = null;
    });
  }

  void _discardTagChanges(int index) {
    setState(() {
      _tags[index].copyFrom(_savedTags[index]);
      _dirtyTags[index] = false;
      _selectedIndex = index;
      _error = null;
    });
  }

  String _tagValidationMessage(int index) => context.tr(
    'Tag ${index + 1} needs a valid trigger and either an event definition or a code snippet.',
    '第 ${index + 1} 个标签需要有效触发器，以及事件定义或代码段。',
  );

  String _tagTitle(BuildContext context, int index) {
    final tag = _tags[index];
    final name = tag.name.text.trim();
    if (name.isNotEmpty) return name;
    final eventType = tag.eventType.text.trim();
    if (eventType.isNotEmpty) return eventType;
    return context.tr('Tag ${index + 1}', '标签 ${index + 1}');
  }

  String _tagSubtitle(BuildContext context, _TagFormEntry tag) =>
      switch (tag.type) {
        'custom_html' => context.tr(
          'Custom HTML / JavaScript',
          '自定义 HTML / JavaScript',
        ),
        'page_view' => context.tr('Page view', '页面浏览'),
        _ => context.tr('Event', '事件'),
      };

  Widget _tagListItem(BuildContext context, int index) {
    final selected = index == _selectedIndex;
    final dirty = _dirtyTags[index];
    final colors = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: selected ? colors.primaryContainer : null,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => setState(() {
          _selectedIndex = index;
          _error = null;
        }),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _tagTitle(context, index),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (_tags.length > 1)
                    IconButton(
                      tooltip: context.tr('Remove tag', '删除标签'),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _removeTag(index),
                      icon: const Icon(Icons.delete_outline, size: 18),
                    ),
                ],
              ),
              Text(
                _tagSubtitle(context, _tags[index]),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (dirty) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => _saveTagChanges(index),
                        child: Text(context.tr('Save', '保存')),
                      ),
                    ),
                    Expanded(
                      child: TextButton(
                        onPressed: () => _discardTagChanges(index),
                        child: Text(context.tr('Discard', '丢弃')),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _tagManagement(BuildContext context, double panelHeight) => SizedBox(
    width: 220,
    height: panelHeight,
    child: Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              context.tr('Tags', '标签管理'),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              context.tr('Select a tag to edit it.', '选择标签后在右侧编辑。'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _addTag,
              icon: const Icon(Icons.add),
              label: Text(context.tr('Add tag', '添加标签')),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  for (var index = 0; index < _tags.length; index++)
                    _tagListItem(context, index),
                ],
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final editorHeight = _editorHeight(context);
    final panelHeight = editorHeight + 88;
    const leftWidth = 220.0;
    const editorWidth = 1080.0;
    const contentWidth = leftWidth + 16 + editorWidth;
    return AlertDialog(
      title: Text(context.tr('Edit container tags', '编辑容器标签')),
      content: SizedBox(
        width: contentWidth,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 700),
          child: SingleChildScrollView(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: contentWidth,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _tagManagement(context, panelHeight),
                    const SizedBox(width: 16),
                    SizedBox(
                      width: editorWidth,
                      child: _ThreeColumnTagFormCard(
                        key: ValueKey('tag-editor-$_selectedIndex'),
                        entry: _tags[_selectedIndex],
                        onChanged: () => _markTagChanged(_selectedIndex),
                      ),
                    ),
                  ],
                ),
              ),
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
  }

  void _save() {
    final tags = <Map<String, dynamic>>[];
    for (var index = 0; index < _tags.length; index++) {
      final tag = _tags[index].toJson();
      if (tag == null) {
        setState(() {
          _selectedIndex = index;
          _error = _tagValidationMessage(index);
        });
        return;
      }
      tags.add(tag);
    }
    Navigator.pop(context, tags);
  }
}

// ignore: unused_element
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
            isExpanded: true,
            decoration: InputDecoration(
              labelText: context.tr('Tag type', '标签类型'),
            ),
            items: [
              DropdownMenuItem(
                value: 'custom_html',
                child: Text(
                  context.tr(
                    'Custom HTML / JavaScript',
                    '自定义 HTML / JavaScript',
                  ),
                ),
              ),
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
          if (entry.type == 'event' || entry.type == 'custom_html') ...[
            const SizedBox(height: 8),
            TextField(
              controller: entry.trigger,
              onChanged: (_) => onChanged(),
              decoration: InputDecoration(
                labelText: context.tr(
                  'Trigger event (use page_view for page load)',
                  '触发事件（页面加载请输入 page_view）',
                ),
                hintText: entry.type == 'custom_html' ? 'page_view' : 'signup',
              ),
            ),
          ],
          if (entry.type == 'custom_html') ...[
            const SizedBox(height: 8),
            TextField(
              controller: entry.name,
              onChanged: (_) => onChanged(),
              decoration: InputDecoration(
                labelText: context.tr('Display name', '显示名称'),
                hintText: 'marketing_pixel',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: entry.code,
              onChanged: (_) => onChanged(),
              minLines: 7,
              maxLines: 14,
              keyboardType: TextInputType.multiline,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              decoration: InputDecoration(
                alignLabelWithHint: true,
                labelText: context.tr(
                  'Code snippet (HTML / JavaScript)',
                  '代码段（HTML / JavaScript）',
                ),
                hintText: '<script>\n  // your code\n</script>',
                helperText: context.tr(
                  'HTML nodes are inserted into the page and script tags are executed when the trigger fires.',
                  'HTML 节点会插入页面，script 标签会在触发条件满足时执行。',
                ),
                border: const OutlineInputBorder(),
              ),
            ),
          ],
          if (entry.type != 'custom_html') ...[
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
                        final removed = entry.properties.removeAt(
                          propertyIndex,
                        );
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
        ],
      ),
    ),
  );
}

class _TagTriggerOption {
  const _TagTriggerOption(this.id, this.english, this.chinese);

  final String id;
  final String english;
  final String chinese;
}

const _tagTriggerOptions = [
  _TagTriggerOption('page_view', 'Page view', '页面浏览'),
  _TagTriggerOption('session_start', 'Session start', '会话开始'),
  _TagTriggerOption('goal', 'Goal', '目标完成'),
  _TagTriggerOption('download', 'Download', '下载'),
  _TagTriggerOption('outlink', 'Outbound link', '外链点击'),
  _TagTriggerOption('signup', 'Signup', '注册'),
  _TagTriggerOption('login', 'Login', '登录'),
  _TagTriggerOption('purchase', 'Purchase', '购买'),
  _TagTriggerOption('add_to_cart', 'Add to cart', '加入购物车'),
  _TagTriggerOption('form_submit', 'Form submit', '表单提交'),
  _TagTriggerOption('search', 'Search', '搜索'),
  _TagTriggerOption('experiment_exposure', 'Experiment exposure', '实验曝光'),
];

class _ThreeColumnTagFormCard extends StatefulWidget {
  const _ThreeColumnTagFormCard({
    super.key,
    required this.entry,
    required this.onChanged,
  });

  final _TagFormEntry entry;
  final VoidCallback onChanged;

  @override
  State<_ThreeColumnTagFormCard> createState() =>
      _ThreeColumnTagFormCardState();
}

class _ThreeColumnTagFormCardState extends State<_ThreeColumnTagFormCard> {
  final _settingsScrollController = ScrollController();
  final _triggersScrollController = ScrollController();
  final _codeScrollController = ScrollController();

  _TagFormEntry get entry => widget.entry;
  VoidCallback get onChanged => widget.onChanged;

  @override
  void dispose() {
    _settingsScrollController.dispose();
    _triggersScrollController.dispose();
    _codeScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final editorHeight = (MediaQuery.sizeOf(context).height - 220)
        .clamp(320.0, 540.0)
        .toDouble();
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: editorHeight,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: _scrollingColumn(
                      _settings(context),
                      _settingsScrollController,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 4,
                    child: _scrollingColumn(
                      _triggers(context),
                      _triggersScrollController,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 5,
                    child: _scrollingColumn(
                      _code(context),
                      _codeScrollController,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _scrollingColumn(Widget child, ScrollController controller) =>
      Scrollbar(
        controller: controller,
        thumbVisibility: true,
        child: SingleChildScrollView(
          controller: controller,
          primary: false,
          padding: const EdgeInsets.only(right: 8),
          child: child,
        ),
      );

  Widget _settings(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        context.tr('Settings', '基础设置'),
        style: Theme.of(context).textTheme.labelLarge,
      ),
      const SizedBox(height: 8),
      DropdownButtonFormField<String>(
        initialValue: entry.type,
        isExpanded: true,
        decoration: InputDecoration(labelText: context.tr('Tag type', '标签类型')),
        items: [
          DropdownMenuItem(
            value: 'custom_html',
            child: Text(
              context.tr('Custom HTML / JavaScript', '自定义 HTML / JavaScript'),
            ),
          ),
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
          if (value == 'page_view') {
            entry.predefinedTriggers.add('page_view');
          }
          onChanged();
        },
      ),
      const SizedBox(height: 8),
      TextField(
        controller: entry.name,
        onChanged: (_) => onChanged(),
        decoration: InputDecoration(
          labelText: context.tr(
            entry.type == 'custom_html'
                ? 'Display name'
                : 'Display name (optional)',
            entry.type == 'custom_html' ? '显示名称' : '显示名称（可选）',
          ),
          hintText: 'marketing_pixel',
        ),
      ),
      if (entry.type != 'custom_html') ...[
        const SizedBox(height: 8),
        TextField(
          controller: entry.eventType,
          onChanged: (_) => onChanged(),
          decoration: InputDecoration(
            labelText: context.tr('Sent event type', '发送的事件类型'),
            hintText: 'tag_signup',
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
    ],
  );

  Widget _triggers(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        context.tr('Triggers (match any)', '触发条件（满足任意一项即可）'),
        style: Theme.of(context).textTheme.labelLarge,
      ),
      const SizedBox(height: 4),
      Text(
        context.tr('Select one or more predefined events.', '可多选预定义事件。'),
        style: Theme.of(context).textTheme.bodySmall,
      ),
      const SizedBox(height: 4),
      Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          TextButton.icon(
            onPressed: () {
              entry.customEvents.add(_TagCustomEventEntry());
              onChanged();
            },
            icon: const Icon(Icons.add, size: 18),
            label: Text(context.tr('Add custom event', '添加自定义事件')),
          ),
          TextButton.icon(
            onPressed: () {
              entry.customJsTriggers.add(_TagCustomJsTriggerEntry());
              onChanged();
            },
            icon: const Icon(Icons.add, size: 18),
            label: Text(context.tr('Add custom JS trigger', '添加自定义 JS 触发器')),
          ),
        ],
      ),
      for (final option in _tagTriggerOptions)
        CheckboxListTile(
          value: entry.predefinedTriggers.contains(option.id),
          onChanged: (checked) {
            if (checked == true) {
              entry.predefinedTriggers.add(option.id);
            } else {
              entry.predefinedTriggers.remove(option.id);
            }
            onChanged();
          },
          title: Text(context.tr(option.english, option.chinese)),
          subtitle: Text(option.id),
          dense: true,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
        ),
      const Divider(),
      Text(
        context.tr('Custom event names', '自定义事件名称'),
        style: Theme.of(context).textTheme.labelLarge,
      ),
      for (var i = 0; i < entry.customEvents.length; i++)
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: entry.customEvents[i].name,
                onChanged: (_) => onChanged(),
                decoration: InputDecoration(
                  labelText: context.tr('Event name', '事件名称'),
                  hintText: 'checkout_started',
                  isDense: true,
                ),
              ),
            ),
            IconButton(
              tooltip: context.tr('Remove trigger', '删除触发条件'),
              onPressed: () {
                final removed = entry.customEvents.removeAt(i);
                removed.dispose();
                onChanged();
              },
              icon: const Icon(Icons.remove_circle_outline),
            ),
          ],
        ),
      const Divider(),
      Text(
        context.tr('Custom JavaScript triggers', '自定义 JavaScript 触发器'),
        style: Theme.of(context).textTheme.labelLarge,
      ),
      Text(
        context.tr(
          'The tracker calls window.functionName(event, context). Return true to fire this tag.',
          '追踪器会调用 window.functionName(event, context)，返回 true 才会触发标签。',
        ),
        style: Theme.of(context).textTheme.bodySmall,
      ),
      for (var i = 0; i < entry.customJsTriggers.length; i++)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Card(
            margin: EdgeInsets.zero,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: entry.customJsTriggers[i].functionName,
                          onChanged: (_) => onChanged(),
                          decoration: InputDecoration(
                            labelText: context.tr(
                              'window function name',
                              'window 函数名',
                            ),
                            hintText: 'shouldFireMarketingTag',
                            isDense: true,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: context.tr('Remove trigger', '删除触发条件'),
                        onPressed: () {
                          final removed = entry.customJsTriggers.removeAt(i);
                          removed.dispose();
                          onChanged();
                        },
                        icon: const Icon(Icons.remove_circle_outline),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: entry.customJsTriggers[i].code,
                    onChanged: (_) => onChanged(),
                    minLines: 2,
                    maxLines: 5,
                    keyboardType: TextInputType.multiline,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                    decoration: InputDecoration(
                      alignLabelWithHint: true,
                      labelText: context.tr(
                        'Function expression (optional)',
                        '函数表达式（可选）',
                      ),
                      hintText:
                          '(event, context) => event.event === \'purchase\'',
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
    ],
  );

  Widget _code(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        context.tr('Injected code', '注入代码段'),
        style: Theme.of(context).textTheme.labelLarge,
      ),
      const SizedBox(height: 4),
      if (entry.type == 'custom_html')
        TextField(
          controller: entry.code,
          onChanged: (_) => onChanged(),
          minLines: 18,
          maxLines: 28,
          keyboardType: TextInputType.multiline,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
          decoration: InputDecoration(
            alignLabelWithHint: true,
            labelText: context.tr(
              'HTML / JavaScript snippet',
              'HTML / JavaScript 代码段',
            ),
            hintText: '<script>\n  // code executed on trigger\n</script>',
            helperText: context.tr(
              'HTML is inserted into the page. Script tags and raw JavaScript are executed when a trigger matches.',
              'HTML 会插入页面；触发条件满足时会执行 script 标签和原始 JavaScript。',
            ),
            border: const OutlineInputBorder(),
          ),
        )
      else
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).colorScheme.outline),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            context.tr(
              'This tag emits an analytics event and does not inject code. Choose Custom HTML / JavaScript when you need a code snippet.',
              '此标签只发送分析事件，不注入代码。需要代码段时请选择“自定义 HTML / JavaScript”。',
            ),
          ),
        ),
    ],
  );
}

class _TagFormEntry {
  _TagFormEntry();

  String type = 'event';
  final trigger = TextEditingController();
  final eventType = TextEditingController();
  final name = TextEditingController();
  final code = TextEditingController();
  final predefinedTriggers = <String>{};
  final customEvents = <_TagCustomEventEntry>[];
  final customJsTriggers = <_TagCustomJsTriggerEntry>[];
  final properties = <_TagPropertyEntry>[];

  factory _TagFormEntry.fromJson(Map value) {
    final entry = _TagFormEntry();
    entry.type = value['type'] == 'page_view'
        ? 'page_view'
        : value['type'] == 'custom_html'
        ? 'custom_html'
        : 'event';
    final triggerValue = value['trigger'];
    entry.trigger.text = triggerValue is String
        ? triggerValue
        : triggerValue is Map
        ? '${triggerValue['event'] ?? ''}'
        : '';
    final rawTriggers = value['triggers'];
    if (rawTriggers is List) {
      for (final rawTrigger in rawTriggers) {
        entry._readTrigger(rawTrigger);
      }
    } else if (triggerValue != null) {
      entry._readTrigger(triggerValue);
    }
    if (entry.type == 'page_view' &&
        entry.predefinedTriggers.isEmpty &&
        entry.customEvents.isEmpty &&
        entry.customJsTriggers.isEmpty) {
      entry.predefinedTriggers.add('page_view');
    }
    entry.eventType.text = '${value['eventType'] ?? ''}';
    entry.name.text = '${value['name'] ?? ''}';
    entry.code.text = '${value['code'] ?? ''}';
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
    final eventTypeValue = eventType.text.trim();
    final nameValue = name.text.trim();
    final codeValue = code.text.trim();
    final triggers = <Map<String, dynamic>>[
      for (final value in predefinedTriggers)
        {'type': 'predefined', 'event': value},
      for (final custom in customEvents)
        if (custom.name.text.trim().isNotEmpty)
          {'type': 'event', 'event': custom.name.text.trim()},
      for (final custom in customJsTriggers)
        if (custom.functionName.text.trim().isNotEmpty)
          {
            'type': 'custom_js',
            'functionName': custom.functionName.text.trim(),
            if (custom.code.text.trim().isNotEmpty)
              'code': custom.code.text.trim(),
          },
    ];
    if (type == 'custom_html'
        ? (nameValue.isEmpty || triggers.isEmpty || codeValue.isEmpty)
        : ((eventTypeValue.isEmpty && nameValue.isEmpty) ||
              (type == 'event' && triggers.isEmpty))) {
      return null;
    }
    final result = <String, dynamic>{'type': type};
    if (triggers.isNotEmpty) result['triggers'] = triggers;
    if (eventTypeValue.isNotEmpty) result['eventType'] = eventTypeValue;
    if (nameValue.isNotEmpty) result['name'] = nameValue;
    if (codeValue.isNotEmpty) result['code'] = codeValue;
    final values = <String, String>{};
    for (final property in properties) {
      final key = property.key.text.trim();
      final value = property.value.text.trim();
      if (key.isNotEmpty) values[key] = value;
    }
    if (values.isNotEmpty) result['properties'] = values;
    return result;
  }

  _TagFormEntry clone() {
    final copy = _TagFormEntry()..type = type;
    copy.trigger.text = trigger.text;
    copy.eventType.text = eventType.text;
    copy.name.text = name.text;
    copy.code.text = code.text;
    copy.predefinedTriggers.addAll(predefinedTriggers);
    copy.customEvents.addAll(
      customEvents.map(
        (event) => _TagCustomEventEntry(nameValue: event.name.text),
      ),
    );
    copy.customJsTriggers.addAll(
      customJsTriggers.map(
        (trigger) => _TagCustomJsTriggerEntry(
          functionNameValue: trigger.functionName.text,
          codeValue: trigger.code.text,
        ),
      ),
    );
    copy.properties.addAll(
      properties.map(
        (property) => _TagPropertyEntry(
          keyValue: property.key.text,
          valueValue: property.value.text,
        ),
      ),
    );
    return copy;
  }

  void copyFrom(_TagFormEntry source) {
    type = source.type;
    trigger.text = source.trigger.text;
    eventType.text = source.eventType.text;
    name.text = source.name.text;
    code.text = source.code.text;
    predefinedTriggers
      ..clear()
      ..addAll(source.predefinedTriggers);
    for (final event in customEvents) {
      event.dispose();
    }
    customEvents
      ..clear()
      ..addAll(
        source.customEvents.map(
          (event) => _TagCustomEventEntry(nameValue: event.name.text),
        ),
      );
    for (final trigger in customJsTriggers) {
      trigger.dispose();
    }
    customJsTriggers
      ..clear()
      ..addAll(
        source.customJsTriggers.map(
          (trigger) => _TagCustomJsTriggerEntry(
            functionNameValue: trigger.functionName.text,
            codeValue: trigger.code.text,
          ),
        ),
      );
    for (final property in properties) {
      property.dispose();
    }
    properties
      ..clear()
      ..addAll(
        source.properties.map(
          (property) => _TagPropertyEntry(
            keyValue: property.key.text,
            valueValue: property.value.text,
          ),
        ),
      );
  }

  void _readTrigger(dynamic value) {
    if (value is String) {
      final id = value.trim();
      if (_tagTriggerOptions.any((option) => option.id == id)) {
        predefinedTriggers.add(id);
      } else if (id.isNotEmpty) {
        customEvents.add(_TagCustomEventEntry(nameValue: id));
      }
      return;
    }
    if (value is! Map) return;
    final kind = '${value['type'] ?? 'event'}';
    if (kind == 'custom_js') {
      customJsTriggers.add(
        _TagCustomJsTriggerEntry(
          functionNameValue: '${value['functionName'] ?? ''}',
          codeValue: '${value['code'] ?? ''}',
        ),
      );
      return;
    }
    _readTrigger('${value['event'] ?? ''}');
  }

  void dispose() {
    trigger.dispose();
    eventType.dispose();
    name.dispose();
    code.dispose();
    for (final property in properties) {
      property.dispose();
    }
    for (final event in customEvents) {
      event.dispose();
    }
    for (final customJsTrigger in customJsTriggers) {
      customJsTrigger.dispose();
    }
  }
}

class _TagCustomEventEntry {
  _TagCustomEventEntry({String nameValue = ''})
    : name = TextEditingController(text: nameValue);

  final TextEditingController name;

  void dispose() => name.dispose();
}

class _TagCustomJsTriggerEntry {
  _TagCustomJsTriggerEntry({
    String functionNameValue = '',
    String codeValue = '',
  }) : functionName = TextEditingController(text: functionNameValue),
       code = TextEditingController(text: codeValue);

  final TextEditingController functionName;
  final TextEditingController code;

  void dispose() {
    functionName.dispose();
    code.dispose();
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
