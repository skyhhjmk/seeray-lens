import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/i18n/app_i18n.dart';
import '../../../core/network/seeray_api.dart';
import '../../../shared/presentation/app_back_button.dart';
import '../../../shared/presentation/page_help_button.dart';
import '../../../shared/presentation/site_top_bar.dart';
import '../../auth/application/auth_controller.dart';
import '../application/analytics_controller.dart';
import '../application/analytics_range.dart';

enum AnalyticsView { visitors, acquisition, behaviour, goals }

class AnalyticsDetailPage extends ConsumerWidget {
  const AnalyticsDetailPage({
    required this.siteId,
    required this.view,
    this.embedded = false,
    super.key,
  });
  final String siteId;
  final AnalyticsView view;
  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rangeState = ref.watch(analyticsRangeProvider(siteId));
    final query = AnalyticsDashboardQuery(siteId, rangeState.range);
    return Scaffold(
      backgroundColor: const Color(0xfff3f5f8),
      appBar: embedded
          ? null
          : SiteTopBar(
              siteId: siteId,
              selected: switch (view) {
                AnalyticsView.visitors => SiteTopTab.visitors,
                AnalyticsView.acquisition => SiteTopTab.acquisition,
                AnalyticsView.behaviour => SiteTopTab.behaviour,
                AnalyticsView.goals => SiteTopTab.goals,
              },
              help: const PageHelpButton(
                englishTitle: 'Analytics view',
                chineseTitle: '分析视图说明',
                englishBody:
                    'These reports use the selected site and the last 30 days. Empty panels mean no collected matching events yet.',
                chineseBody: '这些报表显示当前站点最近 30 天的数据。空白面板表示尚未采集到匹配事件。',
              ),
            ),
      body: ref
          .watch(analyticsDashboardRangeProvider(query))
          .when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Center(
              child: Text(context.tr('Could not load analytics', '无法加载分析数据')),
            ),
            data: (data) => view == AnalyticsView.goals
                ? _GoalsBody(siteId: siteId, data: data)
                : _Body(view: view, data: data),
          ),
    );
  }
}

// ignore: unused_element
class _AnalyticsBar extends StatelessWidget implements PreferredSizeWidget {
  const _AnalyticsBar({required this.siteId, required this.view});
  final String siteId;
  final AnalyticsView view;
  @override
  Size get preferredSize => const Size.fromHeight(104);
  @override
  Widget build(BuildContext context) => AppBar(
    backgroundColor: const Color(0xff202b3b),
    foregroundColor: Colors.white,
    leading: AppBackButton(fallback: '/sites'),
    title: const Text('SeeRay Lens'),
    actions: const [
      PageHelpButton(
        englishTitle: 'Analytics view',
        chineseTitle: '分析视图说明',
        englishBody:
            'These reports use the selected site and the last 30 days. Empty panels mean no collected matching events yet.',
        chineseBody: '这些报表显示当前站点最近 30 天的数据。空白面板表示尚未采集到匹配事件。',
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
            _Tab('Dashboard', '仪表盘', '/sites/$siteId/dashboard', false),
            _Tab(
              'Visitors',
              '访客',
              '/sites/$siteId/visitors',
              view == AnalyticsView.visitors,
            ),
            _Tab(
              'Acquisition',
              '流量获取',
              '/sites/$siteId/acquisition',
              view == AnalyticsView.acquisition,
            ),
            _Tab(
              'Behaviour',
              '用户行为',
              '/sites/$siteId/behaviour',
              view == AnalyticsView.behaviour,
            ),
            _Tab(
              'Goals',
              '目标',
              '/sites/$siteId/goals',
              view == AnalyticsView.goals,
            ),
            _Tab('Integration', '集成', '/sites/$siteId/integration', false),
            _Tab('Settings', '站点设置', '/sites/$siteId', false),
          ],
        ),
      ),
    ),
  );
}

class _Tab extends StatelessWidget {
  const _Tab(this.en, this.zh, this.route, this.selected);
  final String en, zh, route;
  final bool selected;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: TextButton(
      onPressed: selected ? null : () => context.go(route),
      style: TextButton.styleFrom(
        foregroundColor: selected ? Colors.white : const Color(0xffc7d1df),
        backgroundColor: selected
            ? const Color(0xff385172)
            : Colors.transparent,
      ),
      child: Text(context.tr(en, zh)),
    ),
  );
}

class _Body extends StatelessWidget {
  const _Body({required this.view, required this.data});
  final AnalyticsView view;
  final AnalyticsDashboard data;
  @override
  Widget build(BuildContext context) {
    final rows = switch (view) {
      AnalyticsView.visitors => [
        _Metric('Unique visitors', '独立访客', '${data.visitors.uniqueVisitors}'),
        _Metric('Visits', '访问次数', '${data.visitors.sessions}'),
        _Metric('New visits', '新访问', '${data.visitors.newSessions}'),
        _Metric('Returning visits', '回访', '${data.visitors.returningSessions}'),
        _Metric(
          'Bounce rate',
          '跳出率',
          '${(data.visitors.bounceRate * 100).toStringAsFixed(1)}%',
        ),
      ],
      AnalyticsView.acquisition =>
        data.traffic
            .map(
              (x) => _Metric(
                x.channel,
                x.source ?? 'direct',
                '${x.sessions} ${context.tr('visits', '次访问')}',
              ),
            )
            .toList(),
      AnalyticsView.behaviour => [
        ...data.pages.map(
          (x) => _Metric(x.path, 'Page views', '${x.pageViews}'),
        ),
        ...data.events.map((x) => _Metric(x.type, 'Events', '${x.count}')),
      ],
      AnalyticsView.goals =>
        data.goals
            .map((x) => _Metric(x.name, 'Conversions', '${x.count}'))
            .toList(),
    };
    final title = switch (view) {
      AnalyticsView.visitors => context.tr('Visitor overview', '访客概览'),
      AnalyticsView.acquisition => context.tr('Acquisition', '流量获取'),
      AnalyticsView.behaviour => context.tr('Behaviour', '用户行为'),
      AnalyticsView.goals => context.tr('Goals', '目标'),
    };
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(title, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 16),
        if (rows.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(context.tr('No data collected yet.', '尚未采集到数据。')),
            ),
          )
        else
          ...rows,
      ],
    );
  }
}

class _GoalsBody extends ConsumerStatefulWidget {
  const _GoalsBody({required this.siteId, required this.data});

  final String siteId;
  final AnalyticsDashboard data;

  @override
  ConsumerState<_GoalsBody> createState() => _GoalsBodyState();
}

class _GoalsBodyState extends ConsumerState<_GoalsBody> {
  List<Map<String, dynamic>> _definitions = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_load);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result =
          await ref
                  .read(apiProvider)
                  .request('GET', '/api/v1/sites/${widget.siteId}/goals')
              as List;
      if (!mounted) return;
      setState(() {
        _definitions = result
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

  Future<void> _edit([Map<String, dynamic>? initial]) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _GoalEditorDialog(initial: initial),
    );
    if (result == null) return;
    final id = initial?['id'];
    try {
      await ref
          .read(apiProvider)
          .request(
            id == null ? 'POST' : 'PUT',
            id == null
                ? '/api/v1/sites/${widget.siteId}/goals'
                : '/api/v1/sites/${widget.siteId}/goals/$id',
            body: result,
          );
      await _load();
      if (mounted) _invalidateReport();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_message(error))));
    }
  }

  Future<void> _delete(Map<String, dynamic> definition) async {
    final id = definition['id'];
    if (id == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          context.tr(
            'Delete ${definition['name'] ?? 'goal'}?',
            '删除“${definition['name'] ?? '目标'}”？',
          ),
        ),
        content: Text(
          context.tr(
            'Historical raw events remain, but this definition will no longer produce configured conversions.',
            '历史原始事件会保留，但该定义将不再产生配置目标转化。',
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
          .request('DELETE', '/api/v1/sites/${widget.siteId}/goals/$id');
      await _load();
      if (mounted) _invalidateReport();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_message(error))));
    }
  }

  void _invalidateReport() {
    final range = ref.read(analyticsRangeProvider(widget.siteId)).range;
    ref.invalidate(
      analyticsDashboardRangeProvider(
        AnalyticsDashboardQuery(widget.siteId, range),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              context.tr('Goals', '目标'),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ),
          IconButton(
            tooltip: context.tr('Refresh', '刷新'),
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
          FilledButton.icon(
            onPressed: _loading ? null : () => _edit(),
            icon: const Icon(Icons.add),
            label: Text(context.tr('Create goal', '新建目标')),
          ),
        ],
      ),
      const SizedBox(height: 16),
      if (_error != null)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(_error!),
          ),
        ),
      Text(
        context.tr('Conversion report', '转化报告'),
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: 8),
      if (widget.data.goals.isEmpty)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(context.tr('No goal conversions yet.', '暂无目标转化。')),
          ),
        )
      else
        ...widget.data.goals.map(
          (goal) => _Metric(goal.name, 'Conversions', '${goal.count}'),
        ),
      const SizedBox(height: 20),
      Row(
        children: [
          Expanded(
            child: Text(
              context.tr('Configured goals', '已配置目标'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          if (_loading)
            const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
        ],
      ),
      const SizedBox(height: 8),
      if (!_loading && _definitions.isEmpty)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(context.tr('No configured goals.', '还没有配置目标。')),
          ),
        )
      else
        ..._definitions.map(_definitionCard),
    ],
  );

  Widget _definitionCard(Map<String, dynamic> definition) {
    final event = definition['triggerType'] == 'event';
    final detail = event
        ? '${definition['eventType'] ?? ''}${definition['eventName'] == null ? '' : ' · ${definition['eventName']}'}'
        : '${definition['pathPattern'] ?? ''} · ${definition['pathMatchMode'] ?? 'exact'}';
    return Card(
      child: ListTile(
        leading: Icon(event ? Icons.bolt_outlined : Icons.route_outlined),
        title: Text(definition['name'] as String? ?? ''),
        subtitle: Text(
          '$detail · ${context.tr('Value', '价值')} ${definition['fixedValue'] ?? 0}',
        ),
        trailing: Wrap(
          spacing: 2,
          children: [
            if (definition['enabled'] != true)
              const Icon(Icons.pause_circle_outline),
            IconButton(
              tooltip: context.tr('Edit', '编辑'),
              onPressed: () => _edit(definition),
              icon: const Icon(Icons.edit_outlined),
            ),
            IconButton(
              tooltip: context.tr('Delete', '删除'),
              onPressed: () => _delete(definition),
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
      ),
    );
  }

  String _message(Object error) =>
      error is ApiFailure ? error.message : '$error';
}

class _GoalEditorDialog extends StatefulWidget {
  const _GoalEditorDialog({this.initial});

  final Map<String, dynamic>? initial;

  @override
  State<_GoalEditorDialog> createState() => _GoalEditorDialogState();
}

class _GoalEditorDialogState extends State<_GoalEditorDialog> {
  late final TextEditingController _name;
  late final TextEditingController _eventType;
  late final TextEditingController _eventName;
  late final TextEditingController _path;
  late final TextEditingController _fixedValue;
  late String _triggerType;
  late String _pathMatchMode;
  late bool _enabled;
  String? _error;

  bool get _editing => widget.initial != null;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _name = TextEditingController(text: initial?['name'] as String? ?? '');
    _eventType = TextEditingController(
      text: initial?['eventType'] as String? ?? '',
    );
    _eventName = TextEditingController(
      text: initial?['eventName'] as String? ?? '',
    );
    _path = TextEditingController(
      text: initial?['pathPattern'] as String? ?? '',
    );
    _fixedValue = TextEditingController(text: '${initial?['fixedValue'] ?? 0}');
    _triggerType = initial?['triggerType'] == 'page_view'
        ? 'page_view'
        : 'event';
    _pathMatchMode = initial?['pathMatchMode'] == 'contains'
        ? 'contains'
        : 'exact';
    _enabled = initial?['enabled'] as bool? ?? true;
  }

  @override
  void dispose() {
    _name.dispose();
    _eventType.dispose();
    _eventName.dispose();
    _path.dispose();
    _fixedValue.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      context.tr(
        '${_editing ? 'Edit' : 'Create'} goal',
        '${_editing ? '编辑' : '新建'}目标',
      ),
    ),
    content: SizedBox(
      width: 560,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 600),
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
                value: _enabled,
                onChanged: (value) => setState(() => _enabled = value),
              ),
              DropdownButtonFormField<String>(
                initialValue: _triggerType,
                decoration: InputDecoration(
                  labelText: context.tr('Goal trigger', '目标触发方式'),
                ),
                items: [
                  DropdownMenuItem(
                    value: 'event',
                    child: Text(context.tr('Event', '事件')),
                  ),
                  DropdownMenuItem(
                    value: 'page_view',
                    child: Text(context.tr('Page view', '页面浏览')),
                  ),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _triggerType = value;
                    _error = null;
                  });
                },
              ),
              const SizedBox(height: 8),
              if (_triggerType == 'event') ...[
                TextField(
                  controller: _eventType,
                  onChanged: (_) => setState(() => _error = null),
                  decoration: InputDecoration(
                    labelText: context.tr('Event type', '事件类型'),
                    hintText: 'signup',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _eventName,
                  decoration: InputDecoration(
                    labelText: context.tr('Event name (optional)', '事件名称（可选）'),
                  ),
                ),
              ] else ...[
                TextField(
                  controller: _path,
                  onChanged: (_) => setState(() => _error = null),
                  decoration: InputDecoration(
                    labelText: context.tr('Page path', '页面路径'),
                    hintText: '/thank-you',
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: _pathMatchMode,
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
                    if (value != null) setState(() => _pathMatchMode = value);
                  },
                ),
              ],
              const SizedBox(height: 8),
              TextField(
                controller: _fixedValue,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: context.tr('Conversion value', '转化价值'),
                  hintText: '0',
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
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

  void _save() {
    final name = _name.text.trim();
    final fixed = double.tryParse(_fixedValue.text.trim());
    if (name.isEmpty) {
      setState(() => _error = context.tr('Name is required.', '名称不能为空。'));
      return;
    }
    if (fixed == null || fixed < 0) {
      setState(
        () => _error = context.tr(
          'Value must be a non-negative number.',
          '价值必须是非负数字。',
        ),
      );
      return;
    }
    final body = <String, dynamic>{
      'name': name,
      'enabled': _enabled,
      'triggerType': _triggerType,
      'eventType': _triggerType == 'event' ? _eventType.text.trim() : null,
      'eventName': _triggerType == 'event' ? _eventName.text.trim() : null,
      'pathPattern': _triggerType == 'page_view' ? _path.text.trim() : null,
      'pathMatchMode': _pathMatchMode,
      'fixedValue': fixed,
    };
    if (_triggerType == 'event' && (body['eventType'] as String).isEmpty) {
      setState(
        () => _error = context.tr('Event type is required.', '事件类型不能为空。'),
      );
      return;
    }
    if (_triggerType == 'page_view' &&
        !(body['pathPattern'] as String).startsWith('/')) {
      setState(
        () => _error = context.tr('Path must start with /.', '路径必须以 / 开头。'),
      );
      return;
    }
    Navigator.pop(context, body);
  }
}

class _Metric extends StatelessWidget {
  const _Metric(this.title, this.subtitle, this.value);
  final String title, subtitle, value;
  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: Text(value, style: Theme.of(context).textTheme.titleLarge),
    ),
  );
}
