import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_i18n.dart';
import '../../../core/network/seeray_api.dart';
import '../../../shared/presentation/page_help_button.dart';
import '../../../shared/presentation/site_top_bar.dart';
import '../../auth/application/auth_controller.dart';
import '../application/analytics_range.dart';
import '../application/analytics_segment.dart';

class CustomDimensionsPage extends ConsumerStatefulWidget {
  const CustomDimensionsPage({
    required this.siteId,
    this.embedded = false,
    super.key,
  });

  final String siteId;
  final bool embedded;

  @override
  ConsumerState<CustomDimensionsPage> createState() =>
      _CustomDimensionsPageState();
}

class _CustomDimensionsPageState extends ConsumerState<CustomDimensionsPage> {
  List<Map<String, dynamic>> _dimensions = const [];
  List<Map<String, dynamic>> _values = const [];
  String? _selectedId;
  bool _loading = true;
  bool _reportLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_loadDimensions);
  }

  @override
  Widget build(BuildContext context) {
    final range = ref.watch(analyticsRangeProvider(widget.siteId));
    ref.listen(analyticsRangeProvider(widget.siteId), (previous, next) {
      if (previous?.range != next.range && _selectedId != null) {
        _loadReport(_selectedId!);
      }
    });
    ref.listen(analyticsSegmentSelectionProvider(widget.siteId), (
      previous,
      next,
    ) {
      if (previous != next && _selectedId != null) _loadReport(_selectedId!);
    });
    return Scaffold(
      backgroundColor: const Color(0xfff3f5f8),
      appBar: widget.embedded
          ? null
          : SiteTopBar(
              siteId: widget.siteId,
              selected: SiteTopTab.dimensions,
              help: PageHelpButton(
                englishTitle: 'Custom dimensions',
                chineseTitle: '自定义维度',
                englishBody:
                    'Give useful event properties a name and review their values as a report. Configure a dimension here, then send the matching property from your tracker.',
                chineseBody:
                    '为有分析价值的事件属性建立可读名称，并查看该属性的取值报告。在此配置维度后，通过追踪器发送相同名称的属性。',
              ),
              rangeState: range,
              onSelectRange: () => _selectRange(range),
              onRefresh: _loading || _reportLoading ? null : _loadDimensions,
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(onRefresh: _loadDimensions, child: _body(range)),
    );
  }

  Widget _body(AnalyticsRangeState range) {
    final selected = _dimensions
        .where((dimension) => dimension['id'] == _selectedId)
        .firstOrNull;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.tr('Custom dimensions', '自定义维度'),
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    context.tr(
                      'Turn event properties into clear, reusable report dimensions.',
                      '将事件属性整理成清晰、可重复使用的报表维度。',
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: context.tr('Refresh report', '刷新报告'),
              onPressed: _reportLoading ? null : _loadDimensions,
              icon: const Icon(Icons.refresh),
            ),
            FilledButton.icon(
              onPressed: _dimensions.length >= 20 ? null : () => _edit(),
              icon: const Icon(Icons.add),
              label: Text(context.tr('Add dimension', '添加维度')),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_error != null) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(_error!),
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (_dimensions.isEmpty)
          _EmptyDimensions(onAdd: () => _edit())
        else
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 820) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _DimensionList(
                      dimensions: _dimensions,
                      selectedId: _selectedId,
                      onSelect: _selectDimension,
                      onAdd: () => _edit(),
                      onEdit: _edit,
                      onDelete: _delete,
                      onToggle: _toggle,
                    ),
                    const SizedBox(height: 16),
                    _DimensionReport(
                      dimension: selected,
                      values: _values,
                      rangeLabel: analyticsRangeLabel(context, range),
                      loading: _reportLoading,
                      onCopy: selected == null
                          ? null
                          : () => _copySnippet(selected),
                    ),
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 320,
                    child: _DimensionList(
                      dimensions: _dimensions,
                      selectedId: _selectedId,
                      onSelect: _selectDimension,
                      onAdd: () => _edit(),
                      onEdit: _edit,
                      onDelete: _delete,
                      onToggle: _toggle,
                    ),
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: _DimensionReport(
                      dimension: selected,
                      values: _values,
                      rangeLabel: analyticsRangeLabel(context, range),
                      loading: _reportLoading,
                      onCopy: selected == null
                          ? null
                          : () => _copySnippet(selected),
                    ),
                  ),
                ],
              );
            },
          ),
      ],
    );
  }

  Future<void> _selectRange(AnalyticsRangeState current) async {
    final selection = await showAnalyticsRangePicker(context, current);
    if (selection == null || !mounted) return;
    ref
        .read(analyticsRangeProvider(widget.siteId).notifier)
        .setRange(selection);
  }

  Future<void> _loadDimensions() async {
    if (mounted) {
      setState(() {
        _loading = _dimensions.isEmpty;
        _error = null;
      });
    }
    try {
      final response = await ref.read(apiProvider).request('GET', _basePath);
      final dimensions = (response as List)
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList(growable: false);
      final selectedId = dimensions.any((item) => item['id'] == _selectedId)
          ? _selectedId
          : dimensions
                        .where((item) => item['enabled'] == true)
                        .firstOrNull?['id']
                    as String? ??
                dimensions.firstOrNull?['id'] as String?;
      if (!mounted) return;
      setState(() {
        _dimensions = dimensions;
        _selectedId = selectedId;
        _loading = false;
      });
      if (selectedId == null) {
        setState(() => _values = const []);
      } else {
        await _loadReport(selectedId);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _message(error);
      });
    }
  }

  Future<void> _loadReport(String id) async {
    final range = ref.read(analyticsRangeProvider(widget.siteId)).range;
    final segmentId = ref.read(
      analyticsSegmentSelectionProvider(widget.siteId),
    );
    final segmentQuery = segmentId == null ? '' : '&segmentId=$segmentId';
    setState(() {
      _reportLoading = true;
    });
    try {
      final response = await ref
          .read(apiProvider)
          .request(
            'GET',
            '$_basePath/$id/report?from=${_date(range.from)}&to=${_date(range.to)}$segmentQuery',
          );
      if (!mounted || id != _selectedId) return;
      setState(() {
        _values = (response as List)
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList(growable: false);
        _reportLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _reportLoading = false;
        _error = _message(error);
      });
    }
  }

  Future<void> _selectDimension(String id) async {
    if (_selectedId == id) return;
    setState(() {
      _selectedId = id;
      _values = const [];
      _error = null;
    });
    await _loadReport(id);
  }

  Future<void> _edit([Map<String, dynamic>? initial]) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _DimensionEditor(initial: initial),
    );
    if (result == null) return;
    final id = initial?['id'];
    try {
      final saved =
          await ref
                  .read(apiProvider)
                  .request(
                    id == null ? 'POST' : 'PUT',
                    id == null ? _basePath : '$_basePath/$id',
                    body: result,
                  )
              as Map;
      if (!mounted) return;
      setState(() {
        _selectedId = saved['id'] as String?;
      });
      await _loadDimensions();
    } catch (error) {
      if (!mounted) return;
      _showError(error);
    }
  }

  Future<void> _toggle(Map<String, dynamic> dimension, bool enabled) async {
    final body = <String, dynamic>{
      'key': dimension['key'],
      'name': dimension['name'],
      'description': dimension['description'] ?? '',
      'enabled': enabled,
    };
    try {
      await ref
          .read(apiProvider)
          .request('PUT', '$_basePath/${dimension['id']}', body: body);
      await _loadDimensions();
    } catch (error) {
      if (mounted) _showError(error);
    }
  }

  Future<void> _delete(Map<String, dynamic> dimension) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.tr('Delete this dimension?', '删除这个维度？')),
        content: Text(
          context.tr(
            'Existing events are kept. The dimension definition and its report entry will be removed.',
            '已采集的事件会保留；维度定义和对应的报表入口将被删除。',
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
    try {
      await ref
          .read(apiProvider)
          .request('DELETE', '$_basePath/${dimension['id']}');
      if (_selectedId == dimension['id']) _selectedId = null;
      await _loadDimensions();
    } catch (error) {
      if (mounted) _showError(error);
    }
  }

  Future<void> _copySnippet(Map<String, dynamic> dimension) async {
    final key = dimension['key'] as String? ?? '';
    final snippet =
        "SeeRay.track('product_interaction', {\n  properties: { $key: 'example' }\n});";
    await Clipboard.setData(ClipboardData(text: snippet));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.tr('Tracking example copied', '埋点示例已复制'))),
    );
  }

  void _showError(Object error) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(_message(error))));
  }

  String _message(Object error) =>
      error is ApiFailure ? error.message : '$error';
  String get _basePath => '/api/v1/sites/${widget.siteId}/custom-dimensions';
  String _date(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

class _DimensionList extends StatelessWidget {
  const _DimensionList({
    required this.dimensions,
    required this.selectedId,
    required this.onSelect,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
    required this.onToggle,
  });

  final List<Map<String, dynamic>> dimensions;
  final String? selectedId;
  final ValueChanged<String> onSelect;
  final VoidCallback onAdd;
  final ValueChanged<Map<String, dynamic>> onEdit;
  final ValueChanged<Map<String, dynamic>> onDelete;
  final void Function(Map<String, dynamic>, bool) onToggle;

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  context.tr('Dimensions', '维度'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Text(
                '${dimensions.length}/20',
                style: Theme.of(context).textTheme.labelMedium,
              ),
              IconButton(
                tooltip: context.tr('Add dimension', '添加维度'),
                onPressed: dimensions.length >= 20 ? null : onAdd,
                icon: const Icon(Icons.add),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        ...dimensions.map((dimension) {
          final selected = dimension['id'] == selectedId;
          return Material(
            color: selected
                ? Theme.of(
                    context,
                  ).colorScheme.primaryContainer.withValues(alpha: 0.55)
                : null,
            child: ListTile(
              selected: selected,
              onTap: () => onSelect(dimension['id'] as String),
              leading: Icon(selected ? Icons.tune : Icons.data_object_outlined),
              title: Text(
                dimension['name'] as String? ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(dimension['key'] as String? ?? ''),
              trailing: PopupMenuButton<String>(
                tooltip: context.tr('Dimension actions', '维度操作'),
                onSelected: (value) {
                  if (value == 'edit') onEdit(dimension);
                  if (value == 'delete') onDelete(dimension);
                  if (value == 'toggle') {
                    onToggle(dimension, dimension['enabled'] != true);
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'toggle',
                    child: Text(
                      dimension['enabled'] == true
                          ? context.tr('Pause', '停用')
                          : context.tr('Enable', '启用'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'edit',
                    child: Text(context.tr('Edit', '编辑')),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Text(context.tr('Delete', '删除')),
                  ),
                ],
              ),
            ),
          );
        }),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Text(
            context.tr(
              'A dimension reads one top-level property from each tracked event.',
              '维度会读取每个追踪事件中的一个顶层属性。',
            ),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    ),
  );
}

class _DimensionReport extends StatelessWidget {
  const _DimensionReport({
    required this.dimension,
    required this.values,
    required this.rangeLabel,
    required this.loading,
    required this.onCopy,
  });

  final Map<String, dynamic>? dimension;
  final List<Map<String, dynamic>> values;
  final String rangeLabel;
  final bool loading;
  final VoidCallback? onCopy;

  @override
  Widget build(BuildContext context) {
    if (dimension == null) return const SizedBox.shrink();
    final enabled = dimension!['enabled'] == true;
    final key = dimension!['key'] as String? ?? '';
    final snippet =
        "SeeRay.track('product_interaction', {\n  properties: { $key: 'example' }\n});";
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        dimension!['name'] as String? ?? '',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    if (!enabled)
                      Chip(label: Text(context.tr('Paused', '已停用'))),
                  ],
                ),
                const SizedBox(height: 4),
                Text('${context.tr('Property', '属性')} · $key'),
                if ((dimension!['description'] as String? ?? '')
                    .isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(dimension!['description'] as String),
                ],
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        context.tr(
                          'Send this property with an event',
                          '在事件中发送这个属性',
                        ),
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: onCopy,
                      icon: const Icon(Icons.copy_outlined, size: 18),
                      label: Text(context.tr('Copy example', '复制示例')),
                    ),
                  ],
                ),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xff172334),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SelectableText(
                    snippet,
                    style: const TextStyle(
                      color: Color(0xffe0e9f4),
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        context.tr('Value report', '取值报告'),
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    Text(
                      rangeLabel,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (!enabled)
                  Text(
                    context.tr(
                      'Enable this dimension to collect new report values.',
                      '启用该维度后才会展示新采集的报表取值。',
                    ),
                  )
                else if (loading)
                  const Padding(
                    padding: EdgeInsets.all(20),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (values.isEmpty)
                  Text(
                    context.tr(
                      'No values for this period. Confirm the event includes this property, then try again.',
                      '此时间段没有取值。请确认事件已发送该属性后刷新报告。',
                    ),
                  )
                else
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columns: [
                        DataColumn(label: Text(context.tr('Value', '取值'))),
                        DataColumn(
                          numeric: true,
                          label: Text(context.tr('Events', '事件')),
                        ),
                        DataColumn(
                          numeric: true,
                          label: Text(context.tr('Visits', '访问')),
                        ),
                        DataColumn(
                          numeric: true,
                          label: Text(context.tr('Visitors', '访客')),
                        ),
                      ],
                      rows: values
                          .map(
                            (item) => DataRow(
                              cells: [
                                DataCell(
                                  ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxWidth: 280,
                                    ),
                                    child: Text(
                                      item['value'] as String? ?? '',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                                DataCell(Text('${item['events'] ?? 0}')),
                                DataCell(Text('${item['sessions'] ?? 0}')),
                                DataCell(Text('${item['visitors'] ?? 0}')),
                              ],
                            ),
                          )
                          .toList(growable: false),
                    ),
                  ),
                if (values.length >= 100) ...[
                  const SizedBox(height: 8),
                  Text(
                    context.tr('Showing the top 100 values.', '当前显示前 100 个取值。'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _EmptyDimensions extends StatelessWidget {
  const _EmptyDimensions({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.tune, size: 34),
          const SizedBox(height: 12),
          Text(
            context.tr(
              'Make important product context reportable',
              '把产品业务信息变成可分析的报表维度',
            ),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            context.tr(
              'Create a dimension such as plan, account_type, or experiment_group. Then add that property to the events you already send.',
              '例如创建 plan、account_type 或 experiment_group 维度，再把对应属性加到已有事件中。',
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: Text(context.tr('Create your first dimension', '创建第一个维度')),
          ),
        ],
      ),
    ),
  );
}

class _DimensionEditor extends StatefulWidget {
  const _DimensionEditor({this.initial});
  final Map<String, dynamic>? initial;

  @override
  State<_DimensionEditor> createState() => _DimensionEditorState();
}

class _DimensionEditorState extends State<_DimensionEditor> {
  late final TextEditingController _name;
  late final TextEditingController _key;
  late final TextEditingController _description;
  late bool _enabled;
  String? _error;

  bool get _editing => widget.initial != null;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(
      text: widget.initial?['name'] as String? ?? '',
    );
    _key = TextEditingController(text: widget.initial?['key'] as String? ?? '');
    _description = TextEditingController(
      text: widget.initial?['description'] as String? ?? '',
    );
    _enabled = widget.initial?['enabled'] as bool? ?? true;
  }

  @override
  void dispose() {
    _name.dispose();
    _key.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      context.tr(
        _editing ? 'Edit dimension' : 'Create dimension',
        _editing ? '编辑维度' : '创建维度',
      ),
    ),
    content: SizedBox(
      width: 520,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              autofocus: !_editing,
              decoration: InputDecoration(
                labelText: context.tr('Display name', '显示名称'),
                hintText: context.tr('Subscription plan', '订阅方案'),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _key,
              enabled: !_editing,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: context.tr('Event property key', '事件属性名称'),
                hintText: 'subscription_plan',
                helperText: context.tr(
                  'Use lowercase letters, numbers, and underscores. This key is added to event properties.',
                  '使用小写字母、数字和下划线。采集时将此名称作为事件属性发送。',
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _description,
              minLines: 2,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: context.tr('Description (optional)', '说明（可选）'),
              ),
            ),
            if (_editing)
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: Text(context.tr('Available in reports', '在报表中显示')),
                value: _enabled,
                onChanged: (value) => setState(() => _enabled = value),
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
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.tr('Cancel', '取消')),
      ),
      FilledButton(onPressed: _save, child: Text(context.tr('Save', '保存'))),
    ],
  );

  void _save() {
    final key = _key.text.trim();
    if (_name.text.trim().isEmpty ||
        !RegExp(r'^[a-z][a-z0-9_]{0,63}$').hasMatch(key)) {
      setState(
        () => _error = context.tr(
          'Enter a name and a valid lowercase property key.',
          '请填写名称和有效的小写属性名称。',
        ),
      );
      return;
    }
    Navigator.pop(context, <String, dynamic>{
      'name': _name.text.trim(),
      'key': key,
      'description': _description.text.trim(),
      'enabled': _enabled,
    });
  }
}
