import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_i18n.dart';
import '../../../core/network/seeray_api.dart';
import '../../../shared/presentation/page_help_button.dart';
import '../../../shared/presentation/site_top_bar.dart';
import '../../auth/application/auth_controller.dart';
import '../application/analytics_range.dart';
import '../application/analytics_segment.dart';

class SegmentsPage extends ConsumerStatefulWidget {
  const SegmentsPage({required this.siteId, this.embedded = false, super.key});

  final String siteId;
  final bool embedded;

  @override
  ConsumerState<SegmentsPage> createState() => _SegmentsPageState();
}

class _SegmentsPageState extends ConsumerState<SegmentsPage> {
  List<Map<String, dynamic>> _segments = const [];
  List<Map<String, dynamic>> _dimensions = const [];
  Map<String, dynamic>? _preview;
  String? _selectedId;
  bool _loading = true;
  bool _working = false;
  String? _error;

  String get _basePath => '/api/v1/sites/${widget.siteId}/segments';

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_load);
  }

  @override
  Widget build(BuildContext context) {
    final range = ref.watch(analyticsRangeProvider(widget.siteId));
    ref.listen(analyticsRangeProvider(widget.siteId), (previous, next) {
      if (previous?.range != next.range && _selectedId != null) {
        _loadPreview(_selectedId!);
      }
    });
    return Scaffold(
      backgroundColor: const Color(0xfff3f5f8),
      appBar: widget.embedded
          ? null
          : SiteTopBar(
              siteId: widget.siteId,
              selected: SiteTopTab.segments,
              help: const PageHelpButton(
                englishTitle: 'Segments',
                chineseTitle: '用户分群',
                englishBody:
                    'Build reusable audiences from visit, acquisition, technology, location, event, and custom-property rules. Preview matching sessions, then save the rule set for reuse.',
                chineseBody:
                    '使用访问、流量来源、技术、地域、事件和自定义属性条件组合可复用的用户分群，预览命中情况后保存以便重复使用。',
              ),
              rangeState: range,
              onSelectRange: () => _selectRange(range),
              onRefresh: _working ? null : _load,
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(onRefresh: _load, child: _body(range)),
    );
  }

  Widget _body(AnalyticsRangeState range) {
    final selected = _segments
        .where((segment) => segment['id'] == _selectedId)
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
                    context.tr('Segments', '用户分群'),
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    context.tr(
                      'Create reusable audiences with clear rules and inspect who matches before using them.',
                      '用清晰条件创建可复用的用户群体，并查看命中情况。',
                    ),
                  ),
                ],
              ),
            ),
            FilledButton.icon(
              onPressed: _working || _segments.length >= 30
                  ? null
                  : () => _edit(),
              icon: const Icon(Icons.add),
              label: Text(context.tr('Create segment', '创建分群')),
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
        if (_segments.isEmpty)
          _EmptySegments(onCreate: () => _edit())
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final list = _SegmentList(
                segments: _segments,
                selectedId: _selectedId,
                working: _working,
                onSelect: _select,
                onEdit: _edit,
                onDelete: _delete,
                onToggle: _toggle,
                onAdd: () => _edit(),
              );
              final report = _SegmentPreview(
                segment: selected,
                preview: _preview,
                range: analyticsRangeLabel(context, range),
                loading: _working,
                onRefresh: selected == null
                    ? null
                    : () => _loadPreview(_selectedId!),
              );
              if (constraints.maxWidth < 850) {
                return Column(
                  children: [list, const SizedBox(height: 16), report],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 330, child: list),
                  const SizedBox(width: 18),
                  Expanded(child: report),
                ],
              );
            },
          ),
      ],
    );
  }

  Future<void> _selectRange(AnalyticsRangeState current) async {
    final selected = await showAnalyticsRangePicker(context, current);
    if (selected == null || !mounted) return;
    ref.read(analyticsRangeProvider(widget.siteId).notifier).setRange(selected);
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = _segments.isEmpty;
        _error = null;
      });
    }
    try {
      final results = await Future.wait([
        ref.read(apiProvider).request('GET', _basePath),
        ref
            .read(apiProvider)
            .request('GET', '/api/v1/sites/${widget.siteId}/custom-dimensions'),
      ]);
      final segments = (results[0] as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      final dimensions = (results[1] as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      final selectedId =
          segments.any((e) => e['id'] == _selectedId && e['enabled'] == true)
          ? _selectedId
          : segments.where((e) => e['enabled'] == true).firstOrNull?['id']
                    as String? ??
                segments.firstOrNull?['id'] as String?;
      if (!mounted) return;
      setState(() {
        _segments = segments;
        _dimensions = dimensions;
        _selectedId = selectedId;
        _loading = false;
      });
      if (selectedId == null) {
        setState(() => _preview = null);
      } else {
        await _loadPreview(selectedId);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _message(error);
      });
    }
  }

  Future<void> _loadPreview(String id) async {
    final range = ref.read(analyticsRangeProvider(widget.siteId)).range;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final result = await ref
          .read(apiProvider)
          .request(
            'GET',
            '$_basePath/$id/preview?from=${_date(range.from)}&to=${_date(range.to)}',
          );
      if (!mounted || id != _selectedId) return;
      setState(() {
        _preview = Map<String, dynamic>.from(result as Map);
        _working = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _working = false;
        _error = _message(error);
      });
    }
  }

  Future<void> _select(String id) async {
    if (id == _selectedId) return;
    setState(() {
      _selectedId = id;
      _preview = null;
    });
    await _loadPreview(id);
  }

  Future<Map<String, dynamic>> _previewDraft(Map<String, dynamic> draft) async {
    final range = ref.read(analyticsRangeProvider(widget.siteId)).range;
    final result = await ref
        .read(apiProvider)
        .request(
          'POST',
          '$_basePath/preview?from=${_date(range.from)}&to=${_date(range.to)}',
          body: draft,
        );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<void> _edit([Map<String, dynamic>? initial]) async {
    final draft = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _SegmentEditor(
        initial: initial,
        dimensions: _dimensions,
        onPreview: _previewDraft,
      ),
    );
    if (draft == null) return;
    final id = initial?['id'];
    try {
      setState(() {
        _working = true;
        _error = null;
      });
      final saved = Map<String, dynamic>.from(
        await ref
                .read(apiProvider)
                .request(
                  id == null ? 'POST' : 'PUT',
                  id == null ? _basePath : '$_basePath/$id',
                  body: draft,
                )
            as Map,
      );
      if (!mounted) return;
      ref.invalidate(analyticsSegmentOptionsProvider(widget.siteId));
      setState(() {
        _selectedId = saved['id'] as String?;
        _working = false;
      });
      await _load();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _working = false;
        _error = _message(error);
      });
    }
  }

  Future<void> _toggle(Map<String, dynamic> segment) async {
    final next = Map<String, dynamic>.from(segment)
      ..['enabled'] = !(segment['enabled'] == true);
    await _save(segment, next);
  }

  Future<void> _save(
    Map<String, dynamic> previous,
    Map<String, dynamic> next,
  ) async {
    try {
      setState(() {
        _working = true;
        _error = null;
      });
      await ref
          .read(apiProvider)
          .request('PUT', '$_basePath/${previous['id']}', body: next);
      if (!mounted) return;
      ref.invalidate(analyticsSegmentOptionsProvider(widget.siteId));
      setState(() => _working = false);
      await _load();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _working = false;
        _error = _message(error);
      });
    }
  }

  Future<void> _delete(Map<String, dynamic> segment) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.tr('Delete segment?', '删除分群？')),
        content: Text(
          context.tr('This removes the saved rule set.', '这会删除已保存的规则。'),
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
          .request('DELETE', '$_basePath/${segment['id']}');
      if (!mounted) return;
      ref.invalidate(analyticsSegmentOptionsProvider(widget.siteId));
      setState(() {
        if (_selectedId == segment['id']) {
          _selectedId = null;
          _preview = null;
        }
      });
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    }
  }

  String _date(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  String _message(Object error) => error is ApiFailure
      ? error.message
      : context.tr('Could not load segments.', '无法加载用户分群。');
}

class _SegmentList extends StatelessWidget {
  const _SegmentList({
    required this.segments,
    required this.selectedId,
    required this.working,
    required this.onSelect,
    required this.onEdit,
    required this.onDelete,
    required this.onToggle,
    required this.onAdd,
  });
  final List<Map<String, dynamic>> segments;
  final String? selectedId;
  final bool working;
  final ValueChanged<String> onSelect;
  final ValueChanged<Map<String, dynamic>> onEdit, onDelete, onToggle;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) => Card(
    child: Column(
      children: [
        for (final segment in segments)
          ListTile(
            selected: segment['id'] == selectedId,
            leading: Icon(
              segment['enabled'] == true
                  ? Icons.groups_outlined
                  : Icons.pause_circle_outline,
            ),
            title: Text(segment['name'] as String? ?? ''),
            subtitle: Text(
              '${segment['matchMode'] == 'all' ? 'Match all' : 'Match any'} · ${(segment['rules'] as List? ?? const []).length} rules',
            ),
            onTap: working ? null : () => onSelect(segment['id'] as String),
            trailing: PopupMenuButton<String>(
              enabled: !working,
              onSelected: (value) {
                if (value == 'edit') onEdit(segment);
                if (value == 'toggle') onToggle(segment);
                if (value == 'delete') onDelete(segment);
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'edit',
                  child: Text(context.tr('Edit rules', '编辑规则')),
                ),
                PopupMenuItem(
                  value: 'toggle',
                  child: Text(
                    segment['enabled'] == true
                        ? context.tr('Disable', '停用')
                        : context.tr('Enable', '启用'),
                  ),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: Text(context.tr('Delete', '删除')),
                ),
              ],
            ),
          ),
        if (segments.length < 30)
          Padding(
            padding: const EdgeInsets.all(12),
            child: OutlinedButton.icon(
              onPressed: working ? null : onAdd,
              icon: const Icon(Icons.add),
              label: Text(context.tr('Add another segment', '添加分群')),
            ),
          ),
      ],
    ),
  );
}

class _SegmentPreview extends StatelessWidget {
  const _SegmentPreview({
    required this.segment,
    required this.preview,
    required this.range,
    required this.loading,
    required this.onRefresh,
  });
  final Map<String, dynamic>? segment, preview;
  final String range;
  final bool loading;
  final VoidCallback? onRefresh;
  @override
  Widget build(BuildContext context) {
    if (segment == null) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text('Choose or create a segment to preview its audience.'),
        ),
      );
    }
    final pages = (preview?['topPages'] as List? ?? const [])
        .whereType<Map>()
        .toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        segment!['name'] as String? ?? '',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      Text(range, style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: context.tr('Refresh preview', '刷新预览'),
                  onPressed: loading ? null : onRefresh,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            if (segment!['description'] is String &&
                (segment!['description'] as String).isNotEmpty)
              Text(segment!['description'] as String),
            const SizedBox(height: 16),
            if (loading) const LinearProgressIndicator(),
            if (preview != null)
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _Metric(
                    label: context.tr('Sessions', '会话'),
                    value: '${preview!['sessions'] ?? 0}',
                  ),
                  _Metric(
                    label: context.tr('Visitors', '访客'),
                    value: '${preview!['visitors'] ?? 0}',
                  ),
                  _Metric(
                    label: context.tr('Page views', '浏览量'),
                    value: '${preview!['pageViews'] ?? 0}',
                  ),
                  _Metric(
                    label: context.tr('Bounce rate', '跳出率'),
                    value:
                        '${(((preview!['bounceRate'] as num?) ?? 0) * 100).toStringAsFixed(1)}%',
                  ),
                ],
              ),
            const SizedBox(height: 18),
            Text(
              context.tr('Top pages in matching sessions', '命中会话中的热门页面'),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            if (pages.isEmpty && !loading)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  context.tr(
                    'No matching visits in this period.',
                    '此时间范围内没有命中访问。',
                  ),
                ),
              ),
            for (final page in pages)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(
                  page['path'] as String? ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Text('${page['pageViews'] ?? 0}'),
              ),
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});
  final String label, value;
  @override
  Widget build(BuildContext context) => Container(
    width: 145,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xfff3f5f8),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 6),
        Text(value, style: Theme.of(context).textTheme.titleLarge),
      ],
    ),
  );
}

class _EmptySegments extends StatelessWidget {
  const _EmptySegments({required this.onCreate});
  final VoidCallback onCreate;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          const Icon(Icons.filter_alt_outlined, size: 42),
          const SizedBox(height: 12),
          Text(
            context.tr('Build your first audience', '创建第一个用户群体'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            context.tr(
              'Combine visit and event conditions, then preview matching sessions.',
              '组合访问和事件条件，预览命中的会话。',
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onCreate,
            icon: const Icon(Icons.add),
            label: Text(context.tr('Create a segment', '创建分群')),
          ),
        ],
      ),
    ),
  );
}

class _SegmentEditor extends StatefulWidget {
  const _SegmentEditor({
    required this.initial,
    required this.dimensions,
    required this.onPreview,
  });
  final Map<String, dynamic>? initial;
  final List<Map<String, dynamic>> dimensions;
  final Future<Map<String, dynamic>> Function(Map<String, dynamic>) onPreview;
  @override
  State<_SegmentEditor> createState() => _SegmentEditorState();
}

class _SegmentEditorState extends State<_SegmentEditor> {
  late final TextEditingController _name;
  late final TextEditingController _description;
  late String _mode;
  late bool _enabled;
  bool _triedSave = false;
  bool _previewing = false;
  Map<String, dynamic>? _draftPreview;
  String? _previewError;
  late List<Map<String, dynamic>> _rules;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(
      text: widget.initial?['name'] as String? ?? '',
    );
    _description = TextEditingController(
      text: widget.initial?['description'] as String? ?? '',
    );
    _mode = widget.initial?['matchMode'] as String? ?? 'all';
    _enabled = widget.initial?['enabled'] as bool? ?? true;
    _rules =
        ((widget.initial?['rules'] as List?) ??
                const [
                  {
                    'field': 'visitor_type',
                    'operator': 'equals',
                    'value': 'new',
                  },
                ])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      context.tr(
        widget.initial == null ? 'Create segment' : 'Edit segment',
        widget.initial == null ? '创建分群' : '编辑分群',
      ),
    ),
    content: SizedBox(
      width: 650,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _name,
              maxLength: 128,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: context.tr('Segment name', '分群名称'),
                errorText: _triedSave && _name.text.trim().isEmpty
                    ? context.tr('Enter a segment name', '请输入分群名称')
                    : null,
                hintText: context.tr(
                  'e.g. Returning visitors from campaigns',
                  '例如：来自广告活动的回访访客',
                ),
              ),
            ),
            TextField(
              controller: _description,
              maxLength: 512,
              decoration: InputDecoration(
                labelText: context.tr('Description (optional)', '描述（可选）'),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Text(context.tr('Match', '匹配方式')),
                const SizedBox(width: 12),
                DropdownButton<String>(
                  value: _mode,
                  items: [
                    DropdownMenuItem(
                      value: 'all',
                      child: Text(context.tr('all rules', '全部规则')),
                    ),
                    DropdownMenuItem(
                      value: 'any',
                      child: Text(context.tr('any rule', '任一规则')),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _mode = value);
                  },
                ),
              ],
            ),
            const SizedBox(height: 6),
            for (var i = 0; i < _rules.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _RuleEditor(
                  key: ValueKey('rule-$i'),
                  rule: _rules[i],
                  dimensions: widget.dimensions,
                  onChanged: (rule) => setState(() => _rules[i] = rule),
                  onRemove: _rules.length == 1
                      ? null
                      : () => setState(() => _rules.removeAt(i)),
                ),
              ),
            if (_rules.length < 10)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => setState(
                    () => _rules.add({
                      'field': 'visitor_type',
                      'operator': 'equals',
                      'value': 'new',
                    }),
                  ),
                  icon: const Icon(Icons.add),
                  label: Text(context.tr('Add condition', '添加条件')),
                ),
              ),
            if (_previewError != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _previewError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (_draftPreview != null) ...[
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Wrap(
                    spacing: 16,
                    runSpacing: 8,
                    children: [
                      Text(
                        '${context.tr('Preview', '预览')}: ${_draftPreview!['sessions']} ${context.tr('sessions', '个会话')}',
                      ),
                      Text(
                        '${_draftPreview!['visitors']} ${context.tr('visitors', '位访客')}',
                      ),
                      Text(
                        '${_draftPreview!['pageViews']} ${context.tr('page views', '次浏览')}',
                      ),
                    ],
                  ),
                ),
              ),
            ],
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(context.tr('Enabled', '启用分群')),
              value: _enabled,
              onChanged: (value) => setState(() => _enabled = value),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.tr('Cancel', '取消')),
      ),
      TextButton.icon(
        onPressed: _previewing ? null : _preview,
        icon: _previewing
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.visibility_outlined),
        label: Text(context.tr('Preview matches', '预览命中情况')),
      ),
      FilledButton(
        onPressed: () {
          if (_name.text.trim().isEmpty) {
            setState(() => _triedSave = true);
            return;
          }
          Navigator.pop(context, {
            'name': _name.text.trim(),
            'description': _description.text.trim(),
            'matchMode': _mode,
            'rules': _rules,
            'enabled': _enabled,
          });
        },
        child: Text(context.tr('Save', '保存')),
      ),
    ],
  );

  Future<void> _preview() async {
    setState(() {
      _previewing = true;
      _previewError = null;
    });
    try {
      final result = await widget.onPreview({
        'name': _name.text.trim().isEmpty ? 'Draft preview' : _name.text.trim(),
        'description': _description.text.trim(),
        'matchMode': _mode,
        'rules': _rules,
        'enabled': true,
      });
      if (!mounted) return;
      setState(() {
        _draftPreview = result;
        _previewing = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _previewError = error is ApiFailure ? error.message : error.toString();
        _previewing = false;
      });
    }
  }
}

class _RuleEditor extends StatelessWidget {
  const _RuleEditor({
    super.key,
    required this.rule,
    required this.dimensions,
    required this.onChanged,
    required this.onRemove,
  });
  final Map<String, dynamic> rule;
  final List<Map<String, dynamic>> dimensions;
  final ValueChanged<Map<String, dynamic>> onChanged;
  final VoidCallback? onRemove;

  static const _fields = <String, String>{
    'visitor_type': 'Visitor type',
    'entry_page': 'Entry page',
    'exit_page': 'Exit page',
    'source': 'Campaign source',
    'medium': 'Campaign medium',
    'campaign': 'Campaign name',
    'campaign_term': 'Campaign term',
    'campaign_content': 'Campaign content',
    'referrer': 'Referrer',
    'browser': 'Browser',
    'operating_system': 'Operating system',
    'device_type': 'Device type',
    'language': 'Language',
    'country': 'Country',
    'region': 'Region',
    'city': 'City',
    'bounce': 'Bounced visit',
    'page_views': 'Page views',
    'event_count': 'Events per visit',
    'visit_duration': 'Visit duration (seconds)',
    'event_type': 'Event type',
    'page_path': 'Event page',
  };
  List<String> get _availableFields => [
    ..._fields.keys,
    if (dimensions.where((e) => e['enabled'] == true).isNotEmpty ||
        rule['field'] == 'custom_property')
      'custom_property',
  ];
  bool get _numeric => const {
    'page_views',
    'event_count',
    'visit_duration',
  }.contains(rule['field']);
  bool get _boolean => rule['field'] == 'bounce';
  List<String> get _operators => _numeric
      ? ['equals', 'greater_than', 'at_least', 'less_than', 'at_most']
      : _boolean || rule['field'] == 'visitor_type'
      ? ['equals', 'does_not_equal']
      : [
          'equals',
          'does_not_equal',
          'contains',
          'starts_with',
          'is_set',
          'is_not_set',
        ];
  String _fieldLabel(String field, BuildContext context) =>
      field == 'custom_property'
      ? context.tr('Custom property', '自定义属性')
      : context.tr(_fields[field] ?? field, switch (field) {
          'visitor_type' => '访客类型',
          'entry_page' => '入口页面',
          'exit_page' => '退出页面',
          'source' => '广告来源',
          'medium' => '广告媒介',
          'campaign' => '活动名称',
          'campaign_term' => '活动关键词',
          'campaign_content' => '活动内容',
          'referrer' => '引荐来源',
          'browser' => '浏览器',
          'operating_system' => '操作系统',
          'device_type' => '设备类型',
          'language' => '语言',
          'country' => '国家/地区',
          'region' => '省/州',
          'city' => '城市',
          'bounce' => '跳出访问',
          'page_views' => '浏览量',
          'event_count' => '每次访问事件数',
          'visit_duration' => '访问时长（秒）',
          'event_type' => '事件类型',
          'page_path' => '事件页面',
          _ => '自定义属性',
        });

  @override
  Widget build(BuildContext context) {
    final field = rule['field'] as String? ?? 'visitor_type';
    final operator = rule['operator'] as String? ?? 'equals';
    final unset = operator == 'is_set' || operator == 'is_not_set';
    final customDims = dimensions
        .where((e) => e['enabled'] == true || e['key'] == rule['dimensionKey'])
        .toList();
    return Card(
      color: const Color(0xfff8f9fb),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    key: ValueKey('field-$field'),
                    initialValue: field,
                    decoration: InputDecoration(
                      labelText: context.tr('Dimension', '维度'),
                    ),
                    items: _availableFields
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(_fieldLabel(value, context)),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        onChanged({
                          'field': value,
                          'operator': 'equals',
                          'value': _defaultValue(value),
                          if (value == 'custom_property')
                            'dimensionKey': customDims.first['key'],
                        });
                      }
                    },
                  ),
                ),
                IconButton(
                  tooltip: context.tr('Remove condition', '移除条件'),
                  onPressed: onRemove,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            if (field == 'custom_property' && customDims.isNotEmpty)
              DropdownButtonFormField<String>(
                key: ValueKey('custom-${rule['dimensionKey']}'),
                initialValue:
                    customDims.any((e) => e['key'] == rule['dimensionKey'])
                    ? rule['dimensionKey'] as String
                    : customDims.first['key'] as String,
                decoration: InputDecoration(
                  labelText: context.tr('Property', '属性'),
                ),
                items: customDims
                    .map(
                      (d) => DropdownMenuItem(
                        value: d['key'] as String,
                        child: Text('${d['name']} (${d['key']})'),
                      ),
                    )
                    .toList(),
                onChanged: (key) {
                  if (key != null) onChanged({...rule, 'dimensionKey': key});
                },
              ),
            if (field == 'custom_property' && customDims.isEmpty)
              InputDecorator(
                decoration: InputDecoration(
                  labelText: context.tr('Property key', '属性标识'),
                ),
                child: Text(
                  rule['dimensionKey'] as String? ??
                      context.tr('Unavailable dimension', '维度不可用'),
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    key: ValueKey('operator-$field-$operator'),
                    initialValue: _operators.contains(operator)
                        ? operator
                        : _operators.first,
                    decoration: InputDecoration(
                      labelText: context.tr('Condition', '条件'),
                    ),
                    items: _operators
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(_operatorLabel(value, context)),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        onChanged({
                          ...rule,
                          'operator': value,
                          if (value == 'is_set' || value == 'is_not_set')
                            'value': '',
                        });
                      }
                    },
                  ),
                ),
                if (!unset) const SizedBox(width: 10),
                if (!unset)
                  Expanded(
                    child: _valueControl(
                      context,
                      field,
                      rule['value'] as String? ?? 'new',
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _valueControl(BuildContext context, String field, String value) {
    if (field == 'visitor_type' || field == 'bounce') {
      final options = field == 'visitor_type'
          ? ['new', 'returning']
          : ['true', 'false'];
      return DropdownButtonFormField<String>(
        key: ValueKey('choice-${rule['field']}-${rule['operator']}-$value'),
        initialValue: options.contains(value) ? value : options.first,
        decoration: InputDecoration(labelText: context.tr('Value', '值')),
        items: options.map((option) {
          final label = field == 'bounce'
              ? (option == 'true'
                    ? context.tr('Yes', '是')
                    : context.tr('No', '否'))
              : context.tr(
                  option == 'new' ? 'New' : 'Returning',
                  option == 'new' ? '新访客' : '回访访客',
                );
          return DropdownMenuItem(value: option, child: Text(label));
        }).toList(),
        onChanged: (next) {
          if (next != null) onChanged({...rule, 'value': next});
        },
      );
    }
    return TextFormField(
      key: ValueKey('value-${rule['field']}-${rule['operator']}'),
      initialValue: value,
      keyboardType: _numeric ? TextInputType.number : TextInputType.text,
      decoration: InputDecoration(
        labelText: context.tr('Value', '值'),
        hintText: _numeric ? '0' : null,
      ),
      onChanged: (next) => onChanged({...rule, 'value': next}),
    );
  }

  String _operatorLabel(String value, BuildContext context) => context.tr(
    switch (value) {
      'equals' => 'equals',
      'does_not_equal' => 'does not equal',
      'contains' => 'contains',
      'starts_with' => 'starts with',
      'is_set' => 'is set',
      'is_not_set' => 'is not set',
      'greater_than' => 'greater than',
      'at_least' => 'at least',
      'less_than' => 'less than',
      _ => 'at most',
    },
    switch (value) {
      'equals' => '等于',
      'does_not_equal' => '不等于',
      'contains' => '包含',
      'starts_with' => '开头为',
      'is_set' => '已设置',
      'is_not_set' => '未设置',
      'greater_than' => '大于',
      'at_least' => '至少',
      'less_than' => '小于',
      _ => '至多',
    },
  );
  String _defaultValue(String field) => field == 'bounce'
      ? 'true'
      : field == 'page_views'
      ? '1'
      : field == 'event_count'
      ? '1'
      : field == 'visit_duration'
      ? '30'
      : field == 'visitor_type'
      ? 'new'
      : '';
}
