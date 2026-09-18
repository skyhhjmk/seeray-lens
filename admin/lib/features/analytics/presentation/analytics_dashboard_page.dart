import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/i18n/app_i18n.dart';
import '../../../shared/presentation/app_back_button.dart';
import '../../../shared/presentation/page_help_button.dart';
import '../../../shared/presentation/site_top_bar.dart';
import '../../auth/application/auth_controller.dart';
import '../application/analytics_controller.dart';
import '../application/analytics_export.dart';
import '../application/analytics_range.dart';
import '../application/analytics_segment.dart';
import '../application/custom_report_formula.dart';
import '../application/realtime_controller.dart';
import '../application/saved_dashboard_controller.dart';

class AnalyticsDashboardPage extends ConsumerStatefulWidget {
  const AnalyticsDashboardPage({
    required this.siteId,
    this.embedded = false,
    super.key,
  });
  final String siteId;
  final bool embedded;

  @override
  ConsumerState<AnalyticsDashboardPage> createState() =>
      _AnalyticsDashboardPageState();
}

class _AnalyticsDashboardPageState
    extends ConsumerState<AnalyticsDashboardPage> {
  static const _starterId = 'starter-overview';
  late final List<SavedDashboardWidget> _starterWidgets =
      starterDashboardWidgets;
  String? _selectedDashboardId;
  bool _editing = false;
  bool _saving = false;
  String _draftName = '';
  bool _draftIsDefault = false;
  List<SavedDashboardWidget> _draftWidgets = [];

  @override
  void didUpdateWidget(covariant AnalyticsDashboardPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.siteId != widget.siteId) {
      _selectedDashboardId = null;
      _editing = false;
      _draftWidgets = [];
    }
  }

  @override
  Widget build(BuildContext context) {
    final rangeState = ref.watch(analyticsRangeProvider(widget.siteId));
    final segmentId = ref.watch(
      analyticsSegmentSelectionProvider(widget.siteId),
    );
    final query = AnalyticsDashboardQuery(
      widget.siteId,
      rangeState.range,
      segmentId: segmentId,
    );
    final savedDashboards = ref.watch(
      savedAnalyticsDashboardsProvider(widget.siteId),
    );
    final dashboard = ref.watch(analyticsDashboardRangeProvider(query));
    final combined = (savedDashboards, dashboard);
    return Scaffold(
      backgroundColor: const Color(0xfff3f5f8),
      appBar: widget.embedded
          ? null
          : SiteTopBar(
              siteId: widget.siteId,
              selected: SiteTopTab.dashboard,
              help: const PageHelpButton(
                englishTitle: 'Analytics dashboard',
                chineseTitle: '分析仪表盘',
                englishBody:
                    'This dashboard summarizes the selected site for the chosen reporting period. Visitors are exact across the whole range; bounce rate and average visit duration are calculated from sessions.',
                chineseBody:
                    '此仪表盘汇总所选站点在当前统计周期内的数据。独立访客会在整个范围内精确去重；跳出率和平均访问时长由会话数据计算。',
              ),
              rangeState: rangeState,
              onSelectRange: () => _selectRange(rangeState),
            ),
      body: combined.$1.when(
        loading: () => const _DashboardSkeleton(),
        error: (error, stack) => _DashboardError(
          onRetry: () =>
              ref.invalidate(savedAnalyticsDashboardsProvider(widget.siteId)),
        ),
        data: (definitions) => dashboard.when(
          loading: () => const _DashboardSkeleton(),
          error: (error, stack) => _DashboardError(
            onRetry: () =>
                ref.invalidate(analyticsDashboardRangeProvider(query)),
          ),
          data: (data) => _workspace(
            definitions: definitions,
            data: data,
            rangeState: rangeState,
            query: query,
          ),
        ),
      ),
    );
  }

  Widget _workspace({
    required List<SavedAnalyticsDashboard> definitions,
    required AnalyticsDashboard data,
    required AnalyticsRangeState rangeState,
    required AnalyticsDashboardQuery query,
  }) {
    final selected = _selected(definitions);
    final widgets = _editing
        ? _draftWidgets
        : selected?.widgets ?? _starterWidgets;
    return Column(
      children: [
        _DashboardToolbar(
          definitions: definitions,
          selectedId: selected?.id ?? _starterId,
          selectedName: selected?.name ?? context.tr('Overview', '总览'),
          isDefault: selected?.isDefault ?? definitions.isEmpty,
          canChangeDefault: selected != null && !selected.isDefault,
          editing: _editing,
          saving: _saving,
          draftName: _draftName,
          draftIsDefault: _draftIsDefault,
          onSelect: (id) => _selectDashboard(id, definitions),
          onNew: () => _createDashboard(definitions),
          onDuplicate: selected == null
              ? null
              : () => _duplicateDashboard(selected),
          onDelete: selected == null ? null : () => _deleteDashboard(selected),
          onMakeDefault: selected == null || selected.isDefault
              ? null
              : () => _makeDefault(selected),
          onEdit: () => _beginEdit(selected, definitions.isEmpty),
          onCancel: _cancelEdit,
          onSave: () => _saveDashboard(selected),
          onNameChanged: (value) => _draftName = value,
          onDefaultChanged: (value) => setState(() => _draftIsDefault = value),
          onAddWidget: _addWidget,
        ),
        Expanded(
          child: _DashboardBody(
            data: data,
            rangeState: rangeState,
            query: query,
            widgets: widgets,
            editing: _editing,
            onReorder: _reorderWidgets,
            onEditWidget: _editWidget,
            onRemoveWidget: _removeWidget,
          ),
        ),
      ],
    );
  }

  SavedAnalyticsDashboard? _selected(List<SavedAnalyticsDashboard> items) {
    if (items.isEmpty) return null;
    for (final item in items) {
      if (item.id == _selectedDashboardId) return item;
    }
    for (final item in items) {
      if (item.isDefault) return item;
    }
    return items.first;
  }

  void _selectDashboard(String id, List<SavedAnalyticsDashboard> items) {
    if (id == _starterId || !items.any((item) => item.id == id)) return;
    setState(() {
      _selectedDashboardId = id;
      _editing = false;
    });
  }

  void _beginEdit(SavedAnalyticsDashboard? selected, bool firstDashboard) {
    setState(() {
      _editing = true;
      _draftName = selected?.name ?? context.tr('Overview', '总览');
      _draftIsDefault = selected?.isDefault ?? firstDashboard;
      _draftWidgets = List.of(selected?.widgets ?? _starterWidgets);
    });
  }

  void _cancelEdit() => setState(() => _editing = false);

  Future<void> _createDashboard(
    List<SavedAnalyticsDashboard> definitions,
  ) async {
    final name = await _askForName(
      context.tr('New dashboard', '新建仪表盘'),
      context.tr('Create', '创建'),
    );
    if (name == null || !mounted) return;
    try {
      final response = await ref
          .read(apiProvider)
          .request(
            'POST',
            '/api/v1/sites/${widget.siteId}/dashboards',
            body: {
              'name': name,
              'widgets': <Object>[],
              'isDefault': definitions.isEmpty,
            },
          );
      final created = SavedAnalyticsDashboard.fromJson(
        Map<String, dynamic>.from(response as Map),
      );
      if (!mounted) return;
      ref.invalidate(savedAnalyticsDashboardsProvider(widget.siteId));
      setState(() {
        _selectedDashboardId = created.id;
        _editing = true;
        _draftName = created.name;
        _draftIsDefault = created.isDefault;
        _draftWidgets = List.of(created.widgets);
      });
    } catch (_) {
      if (!mounted) return;
      _message(context.tr('Could not create dashboard.', '无法创建仪表盘。'));
    }
  }

  Future<void> _duplicateDashboard(SavedAnalyticsDashboard source) async {
    try {
      final response = await ref
          .read(apiProvider)
          .request(
            'POST',
            '/api/v1/sites/${widget.siteId}/dashboards/${source.id}/duplicate',
          );
      final copy = SavedAnalyticsDashboard.fromJson(
        Map<String, dynamic>.from(response as Map),
      );
      if (!mounted) return;
      ref.invalidate(savedAnalyticsDashboardsProvider(widget.siteId));
      setState(() {
        _selectedDashboardId = copy.id;
        _editing = false;
      });
    } catch (_) {
      if (!mounted) return;
      _message(context.tr('Could not duplicate dashboard.', '无法复制仪表盘。'));
    }
  }

  Future<void> _deleteDashboard(SavedAnalyticsDashboard target) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.tr('Delete dashboard?', '删除此仪表盘？')),
        content: Text(
          context.tr(
            '“${target.name}” will be removed. Other dashboards are not affected.',
            '“${target.name}”将被删除，其他仪表盘不受影响。',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.tr('Cancel', '取消')),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.tr('Delete', '删除')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref
          .read(apiProvider)
          .request(
            'DELETE',
            '/api/v1/sites/${widget.siteId}/dashboards/${target.id}',
          );
      if (!mounted) return;
      setState(() {
        _selectedDashboardId = null;
        _editing = false;
      });
      ref.invalidate(savedAnalyticsDashboardsProvider(widget.siteId));
      _message(context.tr('Dashboard deleted.', '仪表盘已删除。'));
    } catch (_) {
      if (!mounted) return;
      _message(context.tr('Could not delete dashboard.', '无法删除仪表盘。'));
    }
  }

  Future<void> _makeDefault(SavedAnalyticsDashboard target) async {
    try {
      await ref
          .read(apiProvider)
          .request(
            'PUT',
            '/api/v1/sites/${widget.siteId}/dashboards/${target.id}',
            body: {
              'name': target.name,
              'widgets': target.widgets.map((item) => item.toJson()).toList(),
              'isDefault': true,
            },
          );
      if (!mounted) return;
      ref.invalidate(savedAnalyticsDashboardsProvider(widget.siteId));
      _message(context.tr('Default dashboard updated.', '默认仪表盘已更新。'));
    } catch (_) {
      if (!mounted) return;
      _message(context.tr('Could not update the default.', '无法更新默认仪表盘。'));
    }
  }

  Future<void> _saveDashboard(SavedAnalyticsDashboard? selected) async {
    final name = _draftName.trim();
    if (name.isEmpty || name.length > 80) {
      _message(
        context.tr(
          'Use a name between 1 and 80 characters.',
          '名称需为 1 到 80 个字符。',
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final body = {
        'name': name,
        'widgets': _draftWidgets.map((item) => item.toJson()).toList(),
        'isDefault': _draftIsDefault,
      };
      final response = await ref
          .read(apiProvider)
          .request(
            selected == null ? 'POST' : 'PUT',
            selected == null
                ? '/api/v1/sites/${widget.siteId}/dashboards'
                : '/api/v1/sites/${widget.siteId}/dashboards/${selected.id}',
            body: body,
          );
      final saved = SavedAnalyticsDashboard.fromJson(
        Map<String, dynamic>.from(response as Map),
      );
      if (!mounted) return;
      ref.invalidate(savedAnalyticsDashboardsProvider(widget.siteId));
      setState(() {
        _selectedDashboardId = saved.id;
        _editing = false;
      });
      _message(context.tr('Dashboard saved.', '仪表盘已保存。'));
    } catch (_) {
      if (!mounted) return;
      _message(
        context.tr(
          'Could not save dashboard. Check the name and try again.',
          '无法保存仪表盘，请检查名称后重试。',
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _addWidget() async {
    if (_draftWidgets.length >= 20) {
      _message(
        context.tr(
          'A dashboard can have up to 20 widgets.',
          '每个仪表盘最多可添加 20 个组件。',
        ),
      );
      return;
    }
    final type = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => const _WidgetGallery(),
    );
    if (type == null || !mounted) return;
    final index = _draftWidgets.length;
    setState(() => _draftWidgets.add(SavedDashboardWidget.create(type)));
    if (type == 'custom_report' && mounted) await _editWidget(index);
  }

  void _reorderWidgets(int oldIndex, int newIndex) {
    setState(() {
      final item = _draftWidgets.removeAt(oldIndex);
      _draftWidgets.insert(newIndex, item);
    });
  }

  Future<void> _editWidget(int index) async {
    final result = await showDialog<SavedDashboardWidget>(
      context: context,
      builder: (context) => _WidgetSettingsDialog(
        siteId: widget.siteId,
        widgetDefinition: _draftWidgets[index],
      ),
    );
    if (result == null || !mounted) return;
    setState(() => _draftWidgets[index] = result);
  }

  void _removeWidget(int index) =>
      setState(() => _draftWidgets.removeAt(index));

  Future<String?> _askForName(String title, String action) async {
    final controller = TextEditingController();
    try {
      return await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLength: 80,
            decoration: InputDecoration(
              labelText: context.tr('Dashboard name', '仪表盘名称'),
            ),
            onSubmitted: (value) {
              if (value.trim().isNotEmpty) Navigator.pop(context, value.trim());
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.tr('Cancel', '取消')),
            ),
            FilledButton(
              onPressed: () {
                final value = controller.text.trim();
                if (value.isNotEmpty) Navigator.pop(context, value);
              },
              child: Text(action),
            ),
          ],
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  void _message(String value) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(value)));
  }

  Future<void> _selectRange(AnalyticsRangeState current) async {
    final selection = await showAnalyticsRangePicker(context, current);
    if (selection == null || !mounted) return;
    ref
        .read(analyticsRangeProvider(widget.siteId).notifier)
        .setRange(selection);
  }
}

// Kept temporarily for source compatibility with older dashboard snapshots.
// ignore: unused_element
class _TopBar extends ConsumerWidget implements PreferredSizeWidget {
  const _TopBar({required this.siteId, required this.siteName});
  final String siteId;
  final String siteName;

  @override
  Size get preferredSize => const Size.fromHeight(104);

  @override
  Widget build(BuildContext context, WidgetRef ref) => AppBar(
    backgroundColor: const Color(0xff202b3b),
    foregroundColor: Colors.white,
    leading: AppBackButton(fallback: '/sites'),
    titleSpacing: 0,
    title: Text('SeeRay Lens · $siteName', overflow: TextOverflow.ellipsis),
    actions: [
      const PageHelpButton(
        englishTitle: 'Analytics dashboard',
        chineseTitle: '分析仪表盘',
        englishBody:
            'This dashboard summarizes the selected site for the chosen reporting period. Visitors are exact across the whole range; bounce rate and average visit duration are calculated from sessions.',
        chineseBody: '此仪表盘汇总所选站点在当前统计周期内的数据。独立访客会在整个范围内精确去重；跳出率和平均访问时长由会话数据计算。',
      ),
      IconButton(
        tooltip: context.tr('Site settings', '站点设置'),
        onPressed: () => context.go('/sites/$siteId'),
        icon: const Icon(Icons.settings_outlined),
      ),
      const LanguageMenu(),
    ],
    bottom: PreferredSize(
      preferredSize: const Size.fromHeight(48),
      child: Align(
        alignment: Alignment.centerLeft,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.only(left: 12, bottom: 8),
          child: Row(
            children: [
              _NavTab(
                label: context.tr('Dashboard', '仪表盘'),
                route: '/sites/$siteId/dashboard',
                selected: true,
              ),
              _NavTab(
                label: context.tr('Visitors', '访客'),
                route: '/sites/$siteId/visitors',
              ),
              _NavTab(
                label: context.tr('Acquisition', '流量获取'),
                route: '/sites/$siteId/acquisition',
              ),
              _NavTab(
                label: context.tr('Behaviour', '用户行为'),
                route: '/sites/$siteId/behaviour',
              ),
              _NavTab(
                label: context.tr('Goals', '目标'),
                route: '/sites/$siteId/goals',
              ),
              _NavTab(
                label: context.tr('Integration', '集成'),
                route: '/sites/$siteId/integration',
              ),
              _NavTab(
                label: context.tr('Settings', '站点设置'),
                route: '/sites/$siteId',
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _NavTab extends StatelessWidget {
  const _NavTab({
    required this.label,
    required this.route,
    this.selected = false,
  });
  final String label;
  final String route;
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
      child: Text(label),
    ),
  );
}

class _DashboardToolbar extends StatelessWidget {
  const _DashboardToolbar({
    required this.definitions,
    required this.selectedId,
    required this.selectedName,
    required this.isDefault,
    required this.canChangeDefault,
    required this.editing,
    required this.saving,
    required this.draftName,
    required this.draftIsDefault,
    required this.onSelect,
    required this.onNew,
    required this.onDuplicate,
    required this.onDelete,
    required this.onMakeDefault,
    required this.onEdit,
    required this.onCancel,
    required this.onSave,
    required this.onNameChanged,
    required this.onDefaultChanged,
    required this.onAddWidget,
  });

  final List<SavedAnalyticsDashboard> definitions;
  final String selectedId;
  final String selectedName;
  final bool isDefault;
  final bool canChangeDefault;
  final bool editing;
  final bool saving;
  final String draftName;
  final bool draftIsDefault;
  final ValueChanged<String> onSelect;
  final VoidCallback onNew;
  final VoidCallback? onDuplicate;
  final VoidCallback? onDelete;
  final VoidCallback? onMakeDefault;
  final VoidCallback onEdit;
  final VoidCallback onCancel;
  final VoidCallback onSave;
  final ValueChanged<String> onNameChanged;
  final ValueChanged<bool> onDefaultChanged;
  final VoidCallback onAddWidget;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: selectedId,
                  isDense: true,
                  icon: const Icon(Icons.expand_more),
                  style: Theme.of(context).textTheme.titleLarge,
                  items: [
                    if (definitions.isEmpty)
                      DropdownMenuItem(
                        value: _AnalyticsDashboardPageState._starterId,
                        child: Text(context.tr('Overview', '总览')),
                      ),
                    ...definitions.map(
                      (item) => DropdownMenuItem(
                        value: item.id,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 280),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Text(
                                  item.name,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (item.isDefault) ...[
                                const SizedBox(width: 8),
                                Icon(
                                  Icons.star_rounded,
                                  size: 16,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                  onChanged: editing
                      ? null
                      : (value) {
                          if (value != null) onSelect(value);
                        },
                ),
              ),
              if (isDefault && !editing)
                Chip(
                  avatar: const Icon(Icons.star_rounded, size: 16),
                  label: Text(context.tr('Default', '默认')),
                  visualDensity: VisualDensity.compact,
                ),
              if (!editing) ...[
                FilledButton.tonalIcon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.tune),
                  label: Text(context.tr('Customize', '自定义')),
                ),
                PopupMenuButton<String>(
                  tooltip: context.tr('Dashboard actions', '仪表盘操作'),
                  onSelected: (action) {
                    switch (action) {
                      case 'new':
                        onNew();
                        break;
                      case 'duplicate':
                        onDuplicate?.call();
                        break;
                      case 'default':
                        onMakeDefault?.call();
                        break;
                      case 'delete':
                        onDelete?.call();
                        break;
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'new',
                      child: ListTile(
                        leading: const Icon(Icons.add),
                        title: Text(context.tr('New dashboard', '新建仪表盘')),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    if (onDuplicate != null)
                      PopupMenuItem(
                        value: 'duplicate',
                        child: ListTile(
                          leading: const Icon(Icons.copy_outlined),
                          title: Text(context.tr('Duplicate', '复制')),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    if (onMakeDefault != null)
                      PopupMenuItem(
                        value: 'default',
                        child: ListTile(
                          leading: const Icon(Icons.star_outline),
                          title: Text(context.tr('Make default', '设为默认')),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    if (onDelete != null)
                      PopupMenuItem(
                        value: 'delete',
                        child: ListTile(
                          leading: const Icon(Icons.delete_outline),
                          title: Text(context.tr('Delete', '删除')),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                  ],
                  child: const Icon(Icons.more_horiz),
                ),
              ],
              if (editing) ...[
                SizedBox(
                  width: 240,
                  child: TextFormField(
                    key: const ValueKey('dashboard-name-field'),
                    initialValue: draftName,
                    maxLength: 80,
                    decoration: InputDecoration(
                      labelText: context.tr('Dashboard name', '仪表盘名称'),
                      counterText: '',
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: onNameChanged,
                  ),
                ),
                FilterChip(
                  selected: draftIsDefault,
                  avatar: Icon(
                    draftIsDefault ? Icons.star : Icons.star_outline,
                    size: 18,
                  ),
                  label: Text(context.tr('Default view', '默认视图')),
                  onSelected: canChangeDefault ? onDefaultChanged : null,
                ),
                FilledButton.tonalIcon(
                  onPressed: onAddWidget,
                  icon: const Icon(Icons.add),
                  label: Text(context.tr('Add widget', '添加组件')),
                ),
                TextButton(
                  onPressed: saving ? null : onCancel,
                  child: Text(context.tr('Discard', '放弃修改')),
                ),
                FilledButton.icon(
                  onPressed: saving ? null : onSave,
                  icon: saving
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check),
                  label: Text(context.tr('Save', '保存')),
                ),
              ],
            ],
          ),
          if (editing) ...[
            const SizedBox(height: 8),
            Text(
              context.tr(
                'Drag cards to reorder. Add reports from the widget library; each card can be configured or removed.',
                '拖动卡片调整顺序。可从组件库添加报表，并逐个设置或移除。',
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ] else if (definitions.length > 1) ...[
            const SizedBox(height: 4),
            Text(
              context.tr(
                'Personal dashboard · $selectedName',
                '个人仪表盘 · $selectedName',
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    ),
  );
}

class _WidgetGallery extends StatelessWidget {
  const _WidgetGallery();

  static const _items =
      <
        ({
          String type,
          String en,
          String zh,
          String descEn,
          String descZh,
          IconData icon,
        })
      >[
        (
          type: 'summary',
          en: 'Key metrics',
          zh: '关键指标',
          descEn: 'Visits, visitors, page views and engagement.',
          descZh: '访问、访客、浏览量和参与度。',
          icon: Icons.insights_outlined,
        ),
        (
          type: 'trend',
          en: 'Trend chart',
          zh: '趋势图',
          descEn: 'Track visits, page views or visitors over time.',
          descZh: '查看访问、浏览量或访客的时间趋势。',
          icon: Icons.show_chart,
        ),
        (
          type: 'top_pages',
          en: 'Top pages',
          zh: '热门页面',
          descEn: 'Pages with the most page views.',
          descZh: '按页面浏览量查看热门页面。',
          icon: Icons.article_outlined,
        ),
        (
          type: 'traffic_channels',
          en: 'Traffic channels',
          zh: '流量渠道',
          descEn: 'Compare visits from each acquisition channel.',
          descZh: '比较各获客渠道带来的访问。',
          icon: Icons.alt_route,
        ),
        (
          type: 'visitor_types',
          en: 'New and returning',
          zh: '新访客与回访访客',
          descEn: 'Compare new and returning visits.',
          descZh: '比较新访客和回访访问。',
          icon: Icons.people_outline,
        ),
        (
          type: 'events',
          en: 'Events',
          zh: '事件',
          descEn: 'See the most frequent tracked events.',
          descZh: '查看发生次数最多的追踪事件。',
          icon: Icons.bolt_outlined,
        ),
        (
          type: 'goals',
          en: 'Goal conversions',
          zh: '目标转化',
          descEn: 'Review conversion counts by configured goal.',
          descZh: '按已配置目标查看转化次数。',
          icon: Icons.flag_outlined,
        ),
        (
          type: 'technology',
          en: 'Technology',
          zh: '访客技术',
          descEn: 'Break down visits by a browser or device dimension.',
          descZh: '按浏览器或设备维度拆分访问。',
          icon: Icons.devices_outlined,
        ),
        (
          type: 'locations',
          en: 'Visitor locations',
          zh: '访客地域',
          descEn: 'Compare visits by country, region or city.',
          descZh: '按国家、地区或城市比较访问。',
          icon: Icons.public,
        ),
        (
          type: 'page_behaviour',
          en: 'Page titles',
          zh: '页面标题',
          descEn: 'Rank page titles and paths by views.',
          descZh: '按浏览量查看页面标题和路径。',
          icon: Icons.web_outlined,
        ),
        (
          type: 'live_visitors',
          en: 'Live visitors',
          zh: '实时访客',
          descEn: 'See current visits and their latest pages.',
          descZh: '查看近期活跃访问及其最新页面。',
          icon: Icons.sensors,
        ),
        (
          type: 'custom_report',
          en: 'Custom report',
          zh: '自定义报表',
          descEn: 'Choose a dimension, measure and audience filters.',
          descZh: '自由组合分析维度、指标与访客过滤条件。',
          icon: Icons.tune,
        ),
      ];

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr('Choose a report widget', '选择报表组件'),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 4),
          Text(
            context.tr(
              'These components use the current date range and selected segment where supported.',
              '组件会使用当前日期范围，并在支持的报表中应用所选分群。',
            ),
          ),
          const SizedBox(height: 14),
          Flexible(
            child: GridView.builder(
              shrinkWrap: true,
              itemCount: _items.length,
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 360,
                mainAxisExtent: 112,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemBuilder: (context, index) {
                final item = _items[index];
                return Card(
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => Navigator.pop(context, item.type),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: Theme.of(
                              context,
                            ).colorScheme.primaryContainer,
                            child: Icon(item.icon),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  context.tr(item.en, item.zh),
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  context.tr(item.descEn, item.descZh),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.add_circle_outline),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}

class _WidgetSettingsDialog extends ConsumerStatefulWidget {
  const _WidgetSettingsDialog({
    required this.siteId,
    required this.widgetDefinition,
  });
  final String siteId;
  final SavedDashboardWidget widgetDefinition;

  @override
  ConsumerState<_WidgetSettingsDialog> createState() =>
      _WidgetSettingsDialogState();
}

class _WidgetSettingsDialogState extends ConsumerState<_WidgetSettingsDialog> {
  late final TextEditingController _title = TextEditingController(
    text: widget.widgetDefinition.title,
  );
  late final TextEditingController _reportFormulaName = TextEditingController(
    text: widget.widgetDefinition.formula?.name ?? 'Events per visit',
  );
  late String _metric = widget.widgetDefinition.metric ?? 'sessions';
  late String _chartType = widget.widgetDefinition.chartType ?? 'line';
  late int _limit = widget.widgetDefinition.limit ?? 5;
  late String _dimension = widget.widgetDefinition.dimension ?? 'Browser';
  late String _locationLevel =
      widget.widgetDefinition.locationLevel ?? 'country';
  late String _reportDimension = widget.widgetDefinition.dimension ?? 'browser';
  late String? _reportSecondaryDimension =
      widget.widgetDefinition.secondaryDimension;
  late String _reportMetric = widget.widgetDefinition.metric ?? 'sessions';
  late String _formulaLeftMetric =
      widget.widgetDefinition.formula?.leftMetric ?? 'events';
  late String _formulaOperator =
      widget.widgetDefinition.formula?.operator ?? 'divide';
  late String _formulaRightMetric =
      widget.widgetDefinition.formula?.rightMetric ?? 'sessions';
  late String _formulaFormat =
      widget.widgetDefinition.formula?.format ?? 'number';
  late String _reportMatchMode = widget.widgetDefinition.matchMode ?? 'all';
  late String _reportChartType = widget.widgetDefinition.chartType ?? 'table';
  late final List<SavedDashboardFilter> _reportFilters = List.of(
    widget.widgetDefinition.filters ?? const [],
  );

  bool get _reportFiltersInvalid => _reportFilters.any((filter) {
    if (filter.operator == 'is_set' || filter.operator == 'is_not_set') {
      return false;
    }
    if (filter.field == 'page_views') {
      final value = int.tryParse(filter.value);
      return value == null || value < 0 || value > 1000000;
    }
    return filter.value.trim().isEmpty || filter.value.length > 512;
  });

  @override
  void dispose() {
    _title.dispose();
    _reportFormulaName.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final type = widget.widgetDefinition.type;
    final customDimensionState = type == 'custom_report'
        ? ref.watch(analyticsCustomDimensionDefinitionsProvider(widget.siteId))
        : null;
    final customDimensions =
        customDimensionState?.value ??
        const <AnalyticsCustomDimensionDefinition>[];
    const reportSessionDimensions = [
      'entry_page',
      'exit_page',
      'entry_page_title',
      'exit_page_title',
      'referrer',
      'source',
      'medium',
      'campaign',
      'campaign_term',
      'campaign_content',
      'visitor_type',
      'browser',
      'operating_system',
      'device_type',
      'language',
      'country',
      'region',
      'city',
    ];
    final reportDimensionOptions = <DropdownMenuItem<String>>[
      for (final value in const ['event_type', ...reportSessionDimensions])
        DropdownMenuItem(
          value: value,
          child: Text(_reportDimensionLabel(context, value)),
        ),
      for (final dimension in customDimensions)
        DropdownMenuItem(
          value: 'custom:${dimension.id}',
          child: Text('${dimension.name} (${dimension.key})'),
        ),
    ];
    final secondaryDimensionOptions = reportDimensionOptions
        .where((item) => item.value != _reportDimension)
        .toList();
    final canAddSecondaryDimension =
        reportDimensionOptions.any((item) => item.value == _reportDimension) &&
        secondaryDimensionOptions.isNotEmpty;
    final eventDimensionPair =
        _reportDimension == 'event_type' ||
        _reportDimension.startsWith('custom:') ||
        _reportSecondaryDimension == 'event_type' ||
        (_reportSecondaryDimension?.startsWith('custom:') ?? false);
    if (!reportDimensionOptions.any((item) => item.value == _reportDimension)) {
      reportDimensionOptions.add(
        DropdownMenuItem(
          value: _reportDimension,
          child: Text(
            context.tr(
              'Unavailable custom dimension — choose another',
              '自定义维度不可用，请重新选择',
            ),
          ),
        ),
      );
    }
    if (_reportSecondaryDimension != null &&
        !secondaryDimensionOptions.any(
          (item) => item.value == _reportSecondaryDimension,
        )) {
      secondaryDimensionOptions.add(
        DropdownMenuItem(
          value: _reportSecondaryDimension,
          child: Text(
            context.tr(
              'Unavailable dimension — remove or choose another',
              '维度不可用，请移除或重新选择',
            ),
          ),
        ),
      );
    }
    return AlertDialog(
      title: Text(context.tr('Widget settings', '组件设置')),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _title,
                autofocus: true,
                maxLength: 80,
                decoration: InputDecoration(
                  labelText: context.tr('Card title', '卡片标题'),
                ),
              ),
              if (type == 'trend') ...[
                DropdownButtonFormField<String>(
                  initialValue: _metric,
                  decoration: InputDecoration(
                    labelText: context.tr('Measure', '统计指标'),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: 'sessions',
                      child: Text(context.tr('Visits', '访问次数')),
                    ),
                    DropdownMenuItem(
                      value: 'pageViews',
                      child: Text(context.tr('Page views', '页面浏览')),
                    ),
                    DropdownMenuItem(
                      value: 'uniqueVisitors',
                      child: Text(context.tr('Unique visitors', '独立访客')),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _metric = value);
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _chartType,
                  decoration: InputDecoration(
                    labelText: context.tr('Chart style', '图表样式'),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: 'line',
                      child: Text(context.tr('Line', '折线')),
                    ),
                    DropdownMenuItem(
                      value: 'bar',
                      child: Text(context.tr('Bars', '柱状')),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _chartType = value);
                  },
                ),
              ],
              if ({
                'top_pages',
                'traffic_channels',
                'events',
                'goals',
                'live_visitors',
              }.contains(type))
                _limitField(context),
              if (type == 'technology') ...[
                DropdownButtonFormField<String>(
                  initialValue: _dimension,
                  decoration: InputDecoration(
                    labelText: context.tr('Technology dimension', '技术维度'),
                  ),
                  items:
                      const [
                            'Browser',
                            'Browser version',
                            'Operating system',
                            'OS version',
                            'Device type',
                            'Language',
                            'Screen size',
                            'Viewport size',
                            'Display scale',
                          ]
                          .map(
                            (value) => DropdownMenuItem(
                              value: value,
                              child: Text(_dimensionLabel(context, value)),
                            ),
                          )
                          .toList(),
                  onChanged: (value) {
                    if (value != null) setState(() => _dimension = value);
                  },
                ),
                _limitField(context),
              ],
              if (type == 'locations') ...[
                DropdownButtonFormField<String>(
                  initialValue: _locationLevel,
                  decoration: InputDecoration(
                    labelText: context.tr('Location level', '地域层级'),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: 'country',
                      child: Text(context.tr('Country', '国家')),
                    ),
                    DropdownMenuItem(
                      value: 'continent',
                      child: Text(context.tr('Continent', '洲')),
                    ),
                    DropdownMenuItem(
                      value: 'region',
                      child: Text(context.tr('Region', '地区')),
                    ),
                    DropdownMenuItem(
                      value: 'city',
                      child: Text(context.tr('City', '城市')),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _locationLevel = value);
                  },
                ),
                _limitField(context),
              ],
              if (type == 'custom_report') ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _reportDimension,
                  decoration: InputDecoration(
                    labelText: context.tr('Break down by', '分析维度'),
                  ),
                  items: reportDimensionOptions,
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _reportDimension = value;
                        if (value == _reportSecondaryDimension) {
                          _reportSecondaryDimension = null;
                        }
                      });
                    }
                  },
                ),
                if (canAddSecondaryDimension ||
                    _reportSecondaryDimension != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => setState(() {
                        if (_reportSecondaryDimension != null) {
                          _reportSecondaryDimension = null;
                        } else {
                          final suggested = _reportDimension == 'country'
                              ? 'region'
                              : 'country';
                          _reportSecondaryDimension = suggested;
                        }
                      }),
                      icon: Icon(
                        _reportSecondaryDimension == null
                            ? Icons.add
                            : Icons.remove,
                      ),
                      label: Text(
                        _reportSecondaryDimension == null
                            ? context.tr('Add a second breakdown', '添加第二分析维度')
                            : context.tr('Remove second breakdown', '移除第二分析维度'),
                      ),
                    ),
                  ),
                if (_reportSecondaryDimension != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: _reportSecondaryDimension,
                      decoration: InputDecoration(
                        labelText: context.tr('Then break down by', '再按以下维度细分'),
                      ),
                      items: secondaryDimensionOptions,
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _reportSecondaryDimension = value);
                        }
                      },
                    ),
                  ),
                if (_reportSecondaryDimension != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        context.tr(
                          eventDimensionPair
                              ? 'Rows show the intersection of both dimensions. Event and custom-property values are paired from the same event; visits and visitors can recur across combinations, so row totals are not additive.'
                              : 'Rows show the intersection of both dimensions. Visitors can recur across combinations, so do not add unique-visitor totals across rows.',
                          eventDimensionPair
                              ? '每行表示两个维度的交叉组合。事件类型与自定义属性按同一事件匹配；访问和访客可能出现在多个组合中，因此各行不可直接相加。'
                              : '每行表示两个维度的交叉组合。同一访客可能出现在多个组合中，请勿将各行独立访客数相加。',
                        ),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ),
                if (customDimensionState?.isLoading == true)
                  const LinearProgressIndicator(),
                if (customDimensionState?.hasError == true)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => ref.invalidate(
                        analyticsCustomDimensionDefinitionsProvider(
                          widget.siteId,
                        ),
                      ),
                      icon: const Icon(Icons.refresh),
                      label: Text(
                        context.tr(
                          'Could not load custom dimensions. Retry.',
                          '无法加载自定义维度，点击重试。',
                        ),
                      ),
                    ),
                  )
                else if (customDimensionState?.isLoading != true &&
                    customDimensions.isEmpty)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () =>
                          context.go('/sites/${widget.siteId}/dimensions'),
                      icon: const Icon(Icons.add),
                      label: Text(
                        context.tr('Create a custom dimension', '创建自定义维度'),
                      ),
                    ),
                  ),
                if (_reportDimension.startsWith('custom:'))
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.info_outline, size: 16),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            context.tr(
                              'Events count only matching values. Visit measures are grouped once per distinct value seen during a visit and are not additive.',
                              '事件数只统计包含该值的事件。访问类指标按每次访问中的不同取值分别归组，因此各值不一定可相加。',
                            ),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (_reportDimension == 'event_type')
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.info_outline, size: 16),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            context.tr(
                              'Event count is grouped by exact event type. Visit-level measures count each matching visit once under every event type it contains, so rows are not additive.',
                              '事件数按事件类型精确分组。访问类指标会把包含该事件类型的访问分别计入各类型，因此各行不能直接相加。',
                            ),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _reportMetric,
                  decoration: InputDecoration(
                    labelText: context.tr('Measure', '统计指标'),
                  ),
                  items:
                      const [
                            'sessions',
                            'unique_visitors',
                            'page_views',
                            'events',
                            'bounced_sessions',
                            'average_duration_ms',
                            'bounce_rate',
                            'formula',
                          ]
                          .map(
                            (value) => DropdownMenuItem(
                              value: value,
                              child: Text(_reportMetricLabel(context, value)),
                            ),
                          )
                          .toList(),
                  onChanged: (value) {
                    if (value != null) setState(() => _reportMetric = value);
                  },
                ),
                if (_reportMetric == 'formula') ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _reportFormulaName,
                    maxLength: 80,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: context.tr('Calculated metric name', '计算指标名称'),
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        flex: 5,
                        child: DropdownButtonFormField<String>(
                          isExpanded: true,
                          initialValue: _formulaLeftMetric,
                          decoration: InputDecoration(
                            labelText: context.tr('First measure', '第一个指标'),
                          ),
                          items: CustomReportFormula.metrics
                              .map(
                                (value) => DropdownMenuItem(
                                  value: value,
                                  child: Text(
                                    _reportMetricLabel(context, value),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            if (value != null) {
                              setState(() => _formulaLeftMetric = value);
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 3,
                        child: DropdownButtonFormField<String>(
                          isExpanded: true,
                          initialValue: _formulaOperator,
                          decoration: InputDecoration(
                            labelText: context.tr('Operation', '运算'),
                          ),
                          items: [
                            DropdownMenuItem(value: 'add', child: Text('+')),
                            DropdownMenuItem(
                              value: 'subtract',
                              child: Text('−'),
                            ),
                            DropdownMenuItem(
                              value: 'multiply',
                              child: Text('×'),
                            ),
                            DropdownMenuItem(value: 'divide', child: Text('÷')),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              setState(() => _formulaOperator = value);
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 5,
                        child: DropdownButtonFormField<String>(
                          isExpanded: true,
                          initialValue: _formulaRightMetric,
                          decoration: InputDecoration(
                            labelText: context.tr('Second measure', '第二个指标'),
                          ),
                          items: CustomReportFormula.metrics
                              .map(
                                (value) => DropdownMenuItem(
                                  value: value,
                                  child: Text(
                                    _reportMetricLabel(context, value),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            if (value != null) {
                              setState(() => _formulaRightMetric = value);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: _formulaFormat,
                    decoration: InputDecoration(
                      labelText: context.tr('Output format', '结果格式'),
                    ),
                    items: [
                      DropdownMenuItem(
                        value: 'number',
                        child: Text(context.tr('Number', '数值')),
                      ),
                      DropdownMenuItem(
                        value: 'percent',
                        child: Text(context.tr('Percentage', '百分比')),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => _formulaFormat = value);
                    },
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      '${_reportMetricLabel(context, _formulaLeftMetric)} '
                      '${switch (_formulaOperator) {
                        'add' => '+',
                        'subtract' => '−',
                        'multiply' => '×',
                        _ => '÷',
                      }} ${_reportMetricLabel(context, _formulaRightMetric)}'
                      '${_formulaFormat == 'percent' ? ' × 100%' : ''}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _reportChartType,
                  decoration: InputDecoration(
                    labelText: context.tr('Display', '显示方式'),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: 'table',
                      child: Text(context.tr('Table', '表格')),
                    ),
                    DropdownMenuItem(
                      value: 'bars',
                      child: Text(context.tr('Bars', '条形图')),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _reportChartType = value);
                  },
                ),
                _limitField(context),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    context.tr('Audience filters', '访客过滤条件'),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                const SizedBox(height: 8),
                if (_reportFilters.isNotEmpty)
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: _reportMatchMode,
                    decoration: InputDecoration(
                      labelText: context.tr('Combine conditions', '条件组合'),
                    ),
                    items: [
                      DropdownMenuItem(
                        value: 'all',
                        child: Text(context.tr('Match all', '全部满足')),
                      ),
                      DropdownMenuItem(
                        value: 'any',
                        child: Text(context.tr('Match any', '任一满足')),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _reportMatchMode = value);
                      }
                    },
                  ),
                for (var i = 0; i < _reportFilters.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: _ReportFilterEditor(
                      key: ValueKey('custom-report-filter-$i'),
                      filter: _reportFilters[i],
                      onChanged: (filter) =>
                          setState(() => _reportFilters[i] = filter),
                      onRemove: () =>
                          setState(() => _reportFilters.removeAt(i)),
                    ),
                  ),
                if (_reportFilters.length < 5)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => setState(
                        () => _reportFilters.add(
                          const SavedDashboardFilter(
                            field: 'source',
                            operator: 'contains',
                            value: 'newsletter',
                          ),
                        ),
                      ),
                      icon: const Icon(Icons.add),
                      label: Text(context.tr('Add filter', '添加过滤条件')),
                    ),
                  ),
                if (_reportFilters.isEmpty)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      context.tr(
                        'No additional filters. The dashboard audience segment still applies.',
                        '未添加额外过滤；仪表盘顶部选择的分群仍会生效。',
                      ),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                if (_reportFiltersInvalid)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        context.tr(
                          'Complete each filter with a valid value.',
                          '请为每个过滤条件填写有效值。',
                        ),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
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
        FilledButton(
          onPressed:
              _reportFiltersInvalid ||
                  (_reportMetric == 'formula' &&
                      _reportFormulaName.text.trim().isEmpty)
              ? null
              : () {
                  final title = _title.text.trim();
                  if (title.isEmpty) return;
                  Navigator.pop(
                    context,
                    widget.widgetDefinition.copyWith(
                      title: title,
                      metric: type == 'trend'
                          ? _metric
                          : type == 'custom_report'
                          ? _reportMetric
                          : null,
                      formula:
                          type == 'custom_report' && _reportMetric == 'formula'
                          ? CustomReportFormula(
                              name: _reportFormulaName.text.trim(),
                              leftMetric: _formulaLeftMetric,
                              operator: _formulaOperator,
                              rightMetric: _formulaRightMetric,
                              format: _formulaFormat,
                            )
                          : null,
                      clearFormula:
                          type == 'custom_report' && _reportMetric != 'formula',
                      chartType: type == 'trend'
                          ? _chartType
                          : type == 'custom_report'
                          ? _reportChartType
                          : null,
                      limit: _hasLimit(type) ? _limit : null,
                      dimension: type == 'technology'
                          ? _dimension
                          : type == 'custom_report'
                          ? _reportDimension
                          : null,
                      secondaryDimension: _reportSecondaryDimension,
                      clearSecondaryDimension:
                          type == 'custom_report' &&
                          _reportSecondaryDimension == null,
                      locationLevel: type == 'locations'
                          ? _locationLevel
                          : null,
                      matchMode: type == 'custom_report'
                          ? _reportMatchMode
                          : null,
                      filters: type == 'custom_report'
                          ? List.unmodifiable(_reportFilters)
                          : null,
                    ),
                  );
                },
          child: Text(context.tr('Apply', '应用')),
        ),
      ],
    );
  }

  Widget _limitField(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: DropdownButtonFormField<int>(
      initialValue: _limit,
      decoration: InputDecoration(
        labelText: context.tr('Rows to show', '显示行数'),
      ),
      items: const [5, 10, 20]
          .map((value) => DropdownMenuItem(value: value, child: Text('$value')))
          .toList(),
      onChanged: (value) {
        if (value != null) setState(() => _limit = value);
      },
    ),
  );
}

class _ReportFilterEditor extends StatelessWidget {
  const _ReportFilterEditor({
    super.key,
    required this.filter,
    required this.onChanged,
    required this.onRemove,
  });

  final SavedDashboardFilter filter;
  final ValueChanged<SavedDashboardFilter> onChanged;
  final VoidCallback onRemove;

  static const _fields = <String, String>{
    'visitor_type': 'Visitor type',
    'entry_page': 'Entry page',
    'exit_page': 'Exit page',
    'source': 'Campaign source',
    'medium': 'Campaign medium',
    'campaign': 'Campaign name',
    'campaign_term': 'Campaign term',
    'campaign_content': 'Campaign content',
    'referrer': 'Referrer host',
    'browser': 'Browser',
    'operating_system': 'Operating system',
    'device_type': 'Device type',
    'language': 'Language',
    'country': 'Country code',
    'region': 'Region',
    'city': 'City',
    'bounce': 'Bounced visit',
    'page_views': 'Page views',
    'event_type': 'Event type',
    'page_path': 'Event page',
  };

  List<String> get _operators => switch (filter.field) {
    'page_views' => [
      'equals',
      'greater_than',
      'at_least',
      'less_than',
      'at_most',
    ],
    'bounce' || 'visitor_type' => ['equals', 'does_not_equal'],
    _ => [
      'equals',
      'does_not_equal',
      'contains',
      'starts_with',
      'is_set',
      'is_not_set',
    ],
  };

  @override
  Widget build(BuildContext context) {
    final isUnset =
        filter.operator == 'is_set' || filter.operator == 'is_not_set';
    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    key: ValueKey('report-field-${filter.field}'),
                    initialValue: _fields.containsKey(filter.field)
                        ? filter.field
                        : 'source',
                    decoration: InputDecoration(
                      labelText: context.tr('Filter dimension', '过滤维度'),
                    ),
                    items: _fields.entries
                        .map(
                          (entry) => DropdownMenuItem(
                            value: entry.key,
                            child: Text(_reportFilterLabel(context, entry.key)),
                          ),
                        )
                        .toList(),
                    onChanged: (field) {
                      if (field == null) return;
                      onChanged(
                        SavedDashboardFilter(
                          field: field,
                          operator: 'equals',
                          value: switch (field) {
                            'visitor_type' => 'new',
                            'bounce' => 'true',
                            'page_views' => '1',
                            _ => '',
                          },
                        ),
                      );
                    },
                  ),
                ),
                IconButton(
                  tooltip: context.tr('Remove filter', '移除过滤条件'),
                  onPressed: onRemove,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    key: ValueKey(
                      'report-operator-${filter.field}-${filter.operator}',
                    ),
                    initialValue: _operators.contains(filter.operator)
                        ? filter.operator
                        : _operators.first,
                    decoration: InputDecoration(
                      labelText: context.tr('Condition', '条件'),
                    ),
                    items: _operators
                        .map(
                          (operator) => DropdownMenuItem(
                            value: operator,
                            child: Text(
                              context.tr(operator, switch (operator) {
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
                              }),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (operator) {
                      if (operator != null) {
                        onChanged(
                          SavedDashboardFilter(
                            field: filter.field,
                            operator: operator,
                            value:
                                operator == 'is_set' || operator == 'is_not_set'
                                ? ''
                                : isUnset
                                ? ''
                                : filter.value,
                          ),
                        );
                      }
                    },
                  ),
                ),
                if (!isUnset) const SizedBox(width: 10),
                if (!isUnset) Expanded(child: _valueField(context)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _valueField(BuildContext context) {
    if (filter.field == 'visitor_type' || filter.field == 'bounce') {
      final values = filter.field == 'visitor_type'
          ? const ['new', 'returning']
          : const ['true', 'false'];
      return DropdownButtonFormField<String>(
        isExpanded: true,
        key: ValueKey('report-value-${filter.field}-${filter.value}'),
        initialValue: values.contains(filter.value)
            ? filter.value
            : values.first,
        decoration: InputDecoration(labelText: context.tr('Value', '值')),
        items: values
            .map(
              (value) => DropdownMenuItem(
                value: value,
                child: Text(
                  filter.field == 'bounce'
                      ? (value == 'true'
                            ? context.tr('Yes', '是')
                            : context.tr('No', '否'))
                      : context.tr(
                          value == 'new' ? 'New' : 'Returning',
                          value == 'new' ? '新访客' : '回访访客',
                        ),
                ),
              ),
            )
            .toList(),
        onChanged: (value) {
          if (value != null) {
            onChanged(
              SavedDashboardFilter(
                field: filter.field,
                operator: filter.operator,
                value: value,
              ),
            );
          }
        },
      );
    }
    return TextFormField(
      key: ValueKey('report-value-${filter.field}-${filter.operator}'),
      initialValue: filter.value,
      keyboardType: filter.field == 'page_views'
          ? TextInputType.number
          : TextInputType.text,
      decoration: InputDecoration(
        labelText: context.tr('Value', '值'),
        hintText: filter.field == 'page_views' ? '0' : null,
      ),
      onChanged: (value) => onChanged(
        SavedDashboardFilter(
          field: filter.field,
          operator: filter.operator,
          value: value,
        ),
      ),
    );
  }
}

String _reportDimensionLabel(BuildContext context, String value) {
  if (value.startsWith('custom:')) {
    return context.tr('Custom dimension', '自定义维度');
  }
  return context.tr(
    switch (value) {
      'event_type' => 'Event type',
      'entry_page' => 'Entry page',
      'exit_page' => 'Exit page',
      'entry_page_title' => 'Entry page title',
      'exit_page_title' => 'Exit page title',
      'referrer' => 'Referrer host',
      'source' => 'Campaign source',
      'medium' => 'Campaign medium',
      'campaign' => 'Campaign name',
      'campaign_term' => 'Campaign term',
      'campaign_content' => 'Campaign content',
      'visitor_type' => 'Visitor type',
      'browser' => 'Browser',
      'operating_system' => 'Operating system',
      'device_type' => 'Device type',
      'language' => 'Language',
      'country' => 'Country code',
      'region' => 'Region',
      _ => 'City',
    },
    switch (value) {
      'event_type' => '事件类型',
      'entry_page' => '入口页面',
      'exit_page' => '退出页面',
      'entry_page_title' => '入口页面标题',
      'exit_page_title' => '退出页面标题',
      'referrer' => '引荐域名',
      'source' => '活动来源',
      'medium' => '活动媒介',
      'campaign' => '活动名称',
      'campaign_term' => '活动关键词',
      'campaign_content' => '活动内容',
      'visitor_type' => '访客类型',
      'browser' => '浏览器',
      'operating_system' => '操作系统',
      'device_type' => '设备类型',
      'language' => '语言',
      'country' => '国家代码',
      'region' => '地区',
      _ => '城市',
    },
  );
}

String _reportMetricLabel(BuildContext context, String value) => context.tr(
  switch (value) {
    'sessions' => 'Visits',
    'unique_visitors' => 'Unique visitors',
    'page_views' => 'Page views',
    'events' => 'Events',
    'formula' => 'Calculated metric',
    'bounced_sessions' => 'Bounced visits',
    'average_duration_ms' => 'Average visit duration',
    _ => 'Bounce rate',
  },
  switch (value) {
    'sessions' => '访问次数',
    'unique_visitors' => '独立访客',
    'page_views' => '页面浏览量',
    'events' => '事件次数',
    'formula' => '计算指标',
    'bounced_sessions' => '跳出访问',
    'average_duration_ms' => '平均访问时长',
    _ => '跳出率',
  },
);

String _reportFilterLabel(BuildContext context, String field) =>
    context.tr(_ReportFilterEditor._fields[field] ?? field, switch (field) {
      'visitor_type' => '访客类型',
      'entry_page' => '入口页面',
      'exit_page' => '退出页面',
      'source' => '活动来源',
      'medium' => '活动媒介',
      'campaign' => '活动名称',
      'campaign_term' => '活动关键词',
      'campaign_content' => '活动内容',
      'referrer' => '引荐域名',
      'browser' => '浏览器',
      'operating_system' => '操作系统',
      'device_type' => '设备类型',
      'language' => '语言',
      'country' => '国家代码',
      'region' => '地区',
      'city' => '城市',
      'bounce' => '跳出访问',
      'page_views' => '页面浏览量',
      'event_type' => '事件类型',
      _ => '事件页面',
    });

bool _hasLimit(String type) => {
  'top_pages',
  'traffic_channels',
  'events',
  'goals',
  'live_visitors',
  'technology',
  'locations',
  'custom_report',
}.contains(type);

String _dimensionLabel(BuildContext context, String value) => switch (value) {
  'Browser' => context.tr('Browser', '浏览器'),
  'Browser version' => context.tr('Browser version', '浏览器版本'),
  'Operating system' => context.tr('Operating system', '操作系统'),
  'OS version' => context.tr('OS version', '系统版本'),
  'Device type' => context.tr('Device type', '设备类型'),
  'Language' => context.tr('Language', '语言'),
  'Screen size' => context.tr('Screen size', '屏幕尺寸'),
  'Viewport size' => context.tr('Viewport size', '视口尺寸'),
  'Display scale' => context.tr('Display scale', '显示缩放'),
  _ => value,
};

class _DashboardBody extends StatelessWidget {
  const _DashboardBody({
    required this.data,
    required this.rangeState,
    required this.query,
    required this.widgets,
    required this.editing,
    required this.onReorder,
    required this.onEditWidget,
    required this.onRemoveWidget,
  });

  final AnalyticsDashboard data;
  final AnalyticsRangeState rangeState;
  final AnalyticsDashboardQuery query;
  final List<SavedDashboardWidget> widgets;
  final bool editing;
  final void Function(int oldIndex, int newIndex) onReorder;
  final ValueChanged<int> onEditWidget;
  final ValueChanged<int> onRemoveWidget;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
    children: [
      Text(
        analyticsRangeLabel(context, rangeState),
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 14),
      if (widgets.isEmpty)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              children: [
                const Icon(Icons.dashboard_customize_outlined, size: 42),
                const SizedBox(height: 10),
                Text(context.tr('This dashboard is empty.', '此仪表盘还没有组件。')),
                if (editing)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      context.tr(
                        'Use “Add widget” to choose the reports you need.',
                        '点击“添加组件”选择需要的报表。',
                      ),
                    ),
                  ),
              ],
            ),
          ),
        )
      else if (editing)
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          itemCount: widgets.length,
          onReorderItem: onReorder,
          itemBuilder: (context, index) => _EditableDashboardWidget(
            key: ValueKey(widgets[index].id),
            index: index,
            definition: widgets[index],
            data: data,
            query: query,
            onEdit: () => onEditWidget(index),
            onRemove: () => onRemoveWidget(index),
          ),
        )
      else
        for (final item in widgets)
          Padding(
            key: ValueKey(item.id),
            padding: const EdgeInsets.only(bottom: 16),
            child: _DashboardWidgetContent(
              definition: item,
              data: data,
              query: query,
            ),
          ),
    ],
  );
}

class _EditableDashboardWidget extends StatelessWidget {
  const _EditableDashboardWidget({
    required super.key,
    required this.index,
    required this.definition,
    required this.data,
    required this.query,
    required this.onEdit,
    required this.onRemove,
  });

  final int index;
  final SavedDashboardWidget definition;
  final AnalyticsDashboard data;
  final AnalyticsDashboardQuery query;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Card(
    elevation: 0,
    margin: const EdgeInsets.only(bottom: 16),
    shape: RoundedRectangleBorder(
      side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      children: [
        Row(
          children: [
            ReorderableDragStartListener(
              index: index,
              child: IconButton(
                tooltip: context.tr('Drag to reorder', '拖动排序'),
                onPressed: () {},
                icon: const Icon(Icons.drag_indicator),
              ),
            ),
            Expanded(
              child: Text(
                definition.title,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            IconButton(
              tooltip: context.tr('Configure widget', '设置组件'),
              onPressed: onEdit,
              icon: const Icon(Icons.tune),
            ),
            IconButton(
              tooltip: context.tr('Remove widget', '移除组件'),
              onPressed: onRemove,
              icon: const Icon(Icons.close),
            ),
            const SizedBox(width: 8),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: _DashboardWidgetContent(
            definition: definition,
            data: data,
            query: query,
          ),
        ),
      ],
    ),
  );
}

class _DashboardWidgetContent extends ConsumerWidget {
  const _DashboardWidgetContent({
    required this.definition,
    required this.data,
    required this.query,
  });

  final SavedDashboardWidget definition;
  final AnalyticsDashboard data;
  final AnalyticsDashboardQuery query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = definition;
    final limit = item.limit ?? 5;
    final exportMetadata = _dashboardWidgetExportMetadata(item, query);
    if (item.type == 'live_visitors') {
      return _LiveDashboardWidget(definition: item, query: query);
    }
    switch (item.type) {
      case 'summary':
        final overview = data.overview;
        return _Panel(
          title: item.title,
          exportColumns: const ['Metric', 'Value'],
          exportRows: [
            ['Page views', overview.pageViews],
            ['Unique visitors', overview.uniqueVisitors],
            ['Visits', overview.sessions],
            ['Bounce rate', overview.bounceRate],
            ['Average visit duration (ms)', overview.averageSessionDurationMs],
          ],
          exportMetadata: exportMetadata,
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _MetricCard(
                icon: Icons.visibility_outlined,
                label: context.tr('Page views', '页面浏览'),
                value: '${overview.pageViews}',
              ),
              _MetricCard(
                icon: Icons.people_outline,
                label: context.tr('Unique visitors', '独立访客'),
                value: '${overview.uniqueVisitors}',
              ),
              _MetricCard(
                icon: Icons.forum_outlined,
                label: context.tr('Visits', '访问次数'),
                value: '${overview.sessions}',
              ),
              _MetricCard(
                icon: Icons.trending_down,
                label: context.tr('Bounce rate', '跳出率'),
                value: '${(overview.bounceRate * 100).toStringAsFixed(1)}%',
              ),
              _MetricCard(
                icon: Icons.timer_outlined,
                label: context.tr('Avg. visit duration', '平均访问时长'),
                value: _duration(overview.averageSessionDurationMs),
              ),
            ],
          ),
        );
      case 'trend':
        final values = data.trend
            .map(
              (day) => switch (item.metric) {
                'pageViews' => day.pageViews.toDouble(),
                'uniqueVisitors' => day.uniqueVisitors.toDouble(),
                _ => day.sessions.toDouble(),
              },
            )
            .toList(growable: false);
        return _Panel(
          title: item.title,
          exportColumns: const [
            'Date',
            'Page views',
            'Unique visitors',
            'Visits',
          ],
          exportRows: data.trend
              .map(
                (day) => <Object?>[
                  day.date,
                  day.pageViews,
                  day.uniqueVisitors,
                  day.sessions,
                ],
              )
              .toList(growable: false),
          exportMetadata: exportMetadata,
          child: values.isEmpty
              ? const _EmptyChart()
              : SizedBox(
                  height: 230,
                  child: _TrendChart(
                    values: values,
                    chartType: item.chartType ?? 'line',
                  ),
                ),
        );
      case 'top_pages':
        return _Panel(
          title: item.title,
          exportColumns: const ['Page', 'Page views'],
          exportRows: data.pages
              .take(limit)
              .map((row) => <Object?>[row.path, row.pageViews])
              .toList(growable: false),
          exportMetadata: exportMetadata,
          child: data.pages.isEmpty
              ? _TablePlaceholder(
                  label: context.tr('No page views yet', '暂无页面浏览数据'),
                )
              : Column(
                  children: data.pages
                      .take(limit)
                      .map(
                        (row) => _TableRow(
                          label: row.path,
                          value: '${row.pageViews}',
                        ),
                      )
                      .toList(),
                ),
        );
      case 'traffic_channels':
        return _Panel(
          title: item.title,
          exportColumns: const [
            'Channel',
            'Source',
            'Medium',
            'Campaign',
            'Term',
            'Content',
            'Visits',
          ],
          exportRows: data.traffic
              .take(limit)
              .map(
                (row) => <Object?>[
                  row.channel,
                  row.source,
                  row.medium,
                  row.campaign,
                  row.term,
                  row.content,
                  row.sessions,
                ],
              )
              .toList(growable: false),
          exportMetadata: exportMetadata,
          child: data.traffic.isEmpty
              ? _TablePlaceholder(
                  label: context.tr('No traffic data yet', '暂无流量数据'),
                )
              : Column(
                  children: data.traffic
                      .take(limit)
                      .map((row) => _AcquisitionTableRow(row))
                      .toList(),
                ),
        );
      case 'visitor_types':
        final visitors = data.visitors;
        final total = visitors.newSessions + visitors.returningSessions;
        return _Panel(
          title: item.title,
          exportColumns: const ['Visitor type', 'Visits'],
          exportRows: <List<Object?>>[
            ['New', visitors.newSessions],
            ['Returning', visitors.returningSessions],
          ],
          exportMetadata: exportMetadata,
          child: total == 0
              ? _TablePlaceholder(
                  label: context.tr('No visitor data yet', '暂无访客数据'),
                )
              : Column(
                  children: [
                    _TableRow(
                      label: context.tr('New visits', '新访客访问'),
                      value: '${visitors.newSessions}',
                    ),
                    _TableRow(
                      label: context.tr('Returning visits', '回访访问'),
                      value: '${visitors.returningSessions}',
                    ),
                  ],
                ),
        );
      case 'events':
        return _Panel(
          title: item.title,
          exportColumns: const ['Event', 'Count'],
          exportRows: data.events
              .take(limit)
              .map((row) => <Object?>[row.type, row.count])
              .toList(growable: false),
          exportMetadata: exportMetadata,
          child: data.events.isEmpty
              ? _TablePlaceholder(label: context.tr('No events yet', '暂无事件数据'))
              : Column(
                  children: data.events
                      .take(limit)
                      .map(
                        (row) =>
                            _TableRow(label: row.type, value: '${row.count}'),
                      )
                      .toList(),
                ),
        );
      case 'goals':
        return _Panel(
          title: item.title,
          exportColumns: const ['Goal', 'Conversions'],
          exportRows: data.goals
              .take(limit)
              .map((row) => <Object?>[row.name, row.count])
              .toList(growable: false),
          exportMetadata: exportMetadata,
          child: data.goals.isEmpty
              ? _TablePlaceholder(
                  label: context.tr('No goal conversions yet', '暂无目标转化数据'),
                )
              : Column(
                  children: data.goals
                      .take(limit)
                      .map(
                        (row) =>
                            _TableRow(label: row.name, value: '${row.count}'),
                      )
                      .toList(),
                ),
        );
      case 'technology':
        final report = ref.watch(analyticsTechnologyProvider(query));
        return report.when(
          loading: () =>
              _Panel(title: item.title, child: const LinearProgressIndicator()),
          error: (error, stack) => _Panel(
            title: item.title,
            child: _TablePlaceholder(
              label: context.tr('Technology report unavailable', '技术报表暂不可用'),
            ),
          ),
          data: (rows) {
            final filtered = rows
                .where((row) => row.dimension == item.dimension)
                .take(limit)
                .toList(growable: false);
            return _Panel(
              title: item.title,
              exportColumns: const [
                'Dimension',
                'Value',
                'Visits',
                'Unique visitors',
              ],
              exportRows: filtered
                  .map(
                    (row) => <Object?>[
                      row.dimension,
                      row.value,
                      row.sessions,
                      row.visitors,
                    ],
                  )
                  .toList(growable: false),
              exportMetadata: exportMetadata,
              child: filtered.isEmpty
                  ? _TablePlaceholder(
                      label: context.tr('No technology data yet', '暂无技术数据'),
                    )
                  : Column(
                      children: filtered
                          .map(
                            (row) => _TableRow(
                              label: row.value,
                              value: '${row.sessions}',
                            ),
                          )
                          .toList(),
                    ),
            );
          },
        );
      case 'locations':
        final report = ref.watch(analyticsLocationProvider(query));
        return report.when(
          loading: () =>
              _Panel(title: item.title, child: const LinearProgressIndicator()),
          error: (error, stack) => _Panel(
            title: item.title,
            child: _TablePlaceholder(
              label: context.tr('Location report unavailable', '地域报表暂不可用'),
            ),
          ),
          data: (data) {
            final rows = data.rows
                .where((row) => row.level == item.locationLevel)
                .take(limit)
                .toList(growable: false);
            return _Panel(
              title: item.title,
              exportColumns: const [
                'Level',
                'Location',
                'Sessions',
                'Visitors',
              ],
              exportRows: rows
                  .map(
                    (row) => <Object?>[
                      row.level,
                      row.label,
                      row.sessions,
                      row.visitors,
                    ],
                  )
                  .toList(growable: false),
              exportMetadata: exportMetadata,
              child: rows.isEmpty
                  ? _TablePlaceholder(
                      label: data.sourceConfigured
                          ? context.tr('No location data yet', '暂无地域数据')
                          : context.tr(
                              'Location collection is not configured',
                              '地域采集尚未配置',
                            ),
                    )
                  : Column(
                      children: rows
                          .map(
                            (row) => _TableRow(
                              label: row.label,
                              value: '${row.sessions}',
                            ),
                          )
                          .toList(),
                    ),
            );
          },
        );
      case 'page_behaviour':
        final report = ref.watch(analyticsBehaviourProvider(query));
        return report.when(
          loading: () =>
              _Panel(title: item.title, child: const LinearProgressIndicator()),
          error: (error, stack) => _Panel(
            title: item.title,
            child: _TablePlaceholder(
              label: context.tr('Page report unavailable', '页面报表暂不可用'),
            ),
          ),
          data: (result) {
            final pages = result.pages.take(10).toList(growable: false);
            return _Panel(
              title: item.title,
              exportColumns: const ['Page title', 'Path', 'Page views'],
              exportRows: pages
                  .map(
                    (row) => <Object?>[
                      row.title?.isNotEmpty == true ? row.title : row.path,
                      row.path,
                      row.pageViews,
                    ],
                  )
                  .toList(growable: false),
              exportMetadata: exportMetadata,
              child: pages.isEmpty
                  ? _TablePlaceholder(
                      label: context.tr('No page titles yet', '暂无页面标题数据'),
                    )
                  : Column(
                      children: pages
                          .map(
                            (row) => _TableRow(
                              label: row.title?.isNotEmpty == true
                                  ? row.title!
                                  : row.path,
                              value: '${row.pageViews}',
                            ),
                          )
                          .toList(),
                    ),
            );
          },
        );
      case 'custom_report':
        final filters = (item.filters ?? const <SavedDashboardFilter>[])
            .map((filter) => Map<String, Object?>.from(filter.toJson()))
            .toList(growable: false);
        final report = ref.watch(
          customReportProvider(
            CustomReportQuery(
              siteId: query.siteId,
              range: query.range,
              segmentId: query.segmentId,
              dimension: item.dimension ?? 'browser',
              secondaryDimension: item.secondaryDimension,
              metric: item.metric ?? 'sessions',
              formula: item.formula,
              limit: limit,
              matchMode: item.matchMode ?? 'all',
              filters: filters,
            ),
          ),
        );
        return report.when(
          loading: () =>
              _Panel(title: item.title, child: const LinearProgressIndicator()),
          error: (error, stack) => _Panel(
            title: item.title,
            child: _TablePlaceholder(
              label: context.tr('Custom report unavailable', '自定义报表暂不可用'),
            ),
          ),
          data: (result) {
            final dimensionLabel =
                result.customDimensionName ??
                _reportDimensionLabel(context, item.dimension ?? 'browser');
            final metricLabel = item.metric == 'formula'
                ? result.formulaName ??
                      item.formula?.name ??
                      context.tr('Calculated metric', '计算指标')
                : _reportMetricLabel(context, item.metric ?? 'sessions');
            final secondaryDimensionLabel = result.secondaryDimension == null
                ? null
                : result.secondaryCustomDimensionName ??
                      _reportDimensionLabel(
                        context,
                        result.secondaryDimension!,
                      );
            if (result.rows.isEmpty) {
              return _Panel(
                title: item.title,
                exportColumns: [
                  dimensionLabel,
                  ?secondaryDimensionLabel,
                  metricLabel,
                ],
                exportRows: const [],
                exportMetadata: exportMetadata,
                child: _TablePlaceholder(
                  label: context.tr('No matching report data', '没有匹配的报表数据'),
                ),
              );
            }
            final maximum = result.rows.fold<double>(
              0,
              (value, row) => math.max(value, row.metricValue),
            );
            return _Panel(
              title: item.title,
              exportColumns: [
                dimensionLabel,
                ?secondaryDimensionLabel,
                metricLabel,
              ],
              exportRows: result.rows
                  .map(
                    (row) => <Object?>[
                      row.dimensionValue,
                      if (secondaryDimensionLabel != null)
                        row.secondaryDimensionValue ?? 'Unknown',
                      row.metricValue,
                    ],
                  )
                  .toList(growable: false),
              exportMetadata: exportMetadata,
              child: item.chartType == 'bars'
                  ? Column(
                      children: result.rows.map((row) {
                        final rowLabel = secondaryDimensionLabel == null
                            ? row.dimensionValue
                            : '$dimensionLabel: ${row.dimensionValue} · '
                                  '$secondaryDimensionLabel: ${row.secondaryDimensionValue ?? 'Unknown'}';
                        return _CustomReportBarRow(
                          label: rowLabel,
                          value: _customReportValue(
                            item.metric ?? 'sessions',
                            row.metricValue,
                            formulaFormat: item.formula?.format,
                          ),
                          progress: maximum <= 0
                              ? 0
                              : row.metricValue / maximum,
                        );
                      }).toList(),
                    )
                  : secondaryDimensionLabel == null
                  ? Column(
                      children: result.rows
                          .map(
                            (row) => _TableRow(
                              label: row.dimensionValue,
                              value: _customReportValue(
                                item.metric ?? 'sessions',
                                row.metricValue,
                                formulaFormat: item.formula?.format,
                              ),
                            ),
                          )
                          .toList(),
                    )
                  : _CustomReportCrossTable(
                      dimensionLabel: dimensionLabel,
                      secondaryDimensionLabel: secondaryDimensionLabel,
                      metricLabel: metricLabel,
                      metric: item.metric ?? 'sessions',
                      formulaFormat: item.formula?.format,
                      rows: result.rows,
                    ),
            );
          },
        );
      default:
        return _Panel(
          title: item.title,
          child: _TablePlaceholder(
            label: context.tr(
              'This report widget is not available.',
              '此报表组件暂不可用。',
            ),
          ),
        );
    }
  }
}

Map<String, Object?> _dashboardWidgetExportMetadata(
  SavedDashboardWidget widget,
  AnalyticsDashboardQuery query, {
  bool useRange = true,
  Map<String, Object?> extra = const {},
}) => {
  'siteId': query.siteId,
  'reportTitle': widget.title,
  'reportType': widget.type,
  if (useRange) 'from': query.range.fromQuery,
  if (useRange) 'to': query.range.toQuery,
  if (query.segmentId != null) 'segmentId': query.segmentId!,
  if (widget.dimension != null) 'dimension': widget.dimension!,
  if (widget.secondaryDimension != null)
    'secondaryDimension': widget.secondaryDimension!,
  if (widget.metric != null) 'metric': widget.metric!,
  if (widget.formula != null) 'formula': widget.formula!.toJson(),
  if (widget.limit != null) 'limit': widget.limit!,
  if (widget.chartType != null) 'visualization': widget.chartType!,
  if (widget.matchMode != null) 'matchMode': widget.matchMode!,
  if (widget.filters != null)
    'filters': widget.filters!.map((filter) => filter.toJson()).toList(),
  ...extra,
};

String _customReportValue(
  String metric,
  double value, {
  String? formulaFormat,
}) => switch (metric) {
  'bounce_rate' => '${(value * 100).toStringAsFixed(1)}%',
  'average_duration_ms' => _duration(value.round()),
  'formula' when formulaFormat == 'percent' => '${value.toStringAsFixed(2)}%',
  _ =>
    value == value.roundToDouble()
        ? value.toInt().toString()
        : value.toStringAsFixed(2),
};

class _CustomReportCrossTable extends StatelessWidget {
  const _CustomReportCrossTable({
    required this.dimensionLabel,
    required this.secondaryDimensionLabel,
    required this.metricLabel,
    required this.metric,
    required this.rows,
    this.formulaFormat,
  });

  final String dimensionLabel;
  final String secondaryDimensionLabel;
  final String metricLabel;
  final String metric;
  final String? formulaFormat;
  final List<CustomReportRow> rows;

  @override
  Widget build(BuildContext context) {
    final headerStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w700,
    );
    return Column(
      children: [
        _row(
          Text(
            dimensionLabel,
            style: headerStyle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            secondaryDimensionLabel,
            style: headerStyle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            metricLabel,
            style: headerStyle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.end,
          ),
          header: true,
        ),
        const Divider(height: 18),
        for (final row in rows)
          _row(
            Text(
              row.dimensionValue,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              row.secondaryDimensionValue ?? 'Unknown',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              _customReportValue(
                metric,
                row.metricValue,
                formulaFormat: formulaFormat,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
      ],
    );
  }

  Widget _row(
    Widget first,
    Widget second,
    Widget value, {
    bool header = false,
  }) => Padding(
    padding: EdgeInsets.symmetric(vertical: header ? 2 : 7),
    child: Row(
      children: [
        Expanded(flex: 3, child: first),
        const SizedBox(width: 10),
        Expanded(flex: 3, child: second),
        const SizedBox(width: 10),
        Expanded(flex: 2, child: value),
      ],
    ),
  );
}

class _CustomReportBarRow extends StatelessWidget {
  const _CustomReportBarRow({
    required this.label,
    required this.value,
    required this.progress,
  });

  final String label;
  final String value;
  final double progress;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(width: 12),
            Text(value, style: Theme.of(context).textTheme.labelLarge),
          ],
        ),
        const SizedBox(height: 5),
        LinearProgressIndicator(value: progress.clamp(0, 1)),
      ],
    ),
  );
}

class _LiveDashboardWidget extends ConsumerStatefulWidget {
  const _LiveDashboardWidget({required this.definition, required this.query});

  final SavedDashboardWidget definition;
  final AnalyticsDashboardQuery query;

  @override
  ConsumerState<_LiveDashboardWidget> createState() =>
      _LiveDashboardWidgetState();
}

class _LiveDashboardWidgetState extends ConsumerState<_LiveDashboardWidget> {
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) {
        ref.invalidate(
          analyticsRealtimeProvider((
            siteId: widget.query.siteId,
            windowMinutes: 30,
          )),
        );
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final metadata = _dashboardWidgetExportMetadata(
      widget.definition,
      widget.query,
      useRange: false,
      extra: const {'windowMinutes': 30},
    );
    final report = ref.watch(
      analyticsRealtimeProvider((
        siteId: widget.query.siteId,
        windowMinutes: 30,
      )),
    );
    return report.when(
      loading: () => _Panel(
        title: widget.definition.title,
        child: const LinearProgressIndicator(),
      ),
      error: (error, stack) => _Panel(
        title: widget.definition.title,
        child: _TablePlaceholder(
          label: context.tr('Live report unavailable', '实时报告暂不可用'),
        ),
      ),
      data: (visitors) {
        final rows = visitors
            .take(widget.definition.limit ?? 5)
            .map(
              (visitor) => <Object?>[
                visitor.countryCode ?? '—',
                visitor.currentTitle?.isNotEmpty == true
                    ? visitor.currentTitle
                    : visitor.currentPage ??
                          visitor.entryPage ??
                          'Unknown page',
                visitor.pageViews,
              ],
            )
            .toList(growable: false);
        return _Panel(
          title: widget.definition.title,
          exportColumns: const ['Country', 'Current page', 'Page views'],
          exportRows: rows,
          exportMetadata: metadata,
          child: visitors.isEmpty
              ? _TablePlaceholder(
                  label: context.tr(
                    'No active visits in the last 30 minutes',
                    '最近 30 分钟暂无活跃访问',
                  ),
                )
              : Column(
                  children: visitors.take(widget.definition.limit ?? 5).map((
                    visitor,
                  ) {
                    final page = visitor.currentTitle?.isNotEmpty == true
                        ? visitor.currentTitle!
                        : visitor.currentPage ??
                              visitor.entryPage ??
                              context.tr('Unknown page', '未知页面');
                    return _TableRow(
                      label: '${visitor.countryCode ?? '—'} · $page',
                      value:
                          '${visitor.pageViews} ${context.tr('views', '次浏览')}',
                    );
                  }).toList(),
                ),
        );
      },
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 190,
    child: Card(
      elevation: 0,
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: const Color(0xff3766a0)),
            const SizedBox(height: 15),
            Text(
              value,
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    ),
  );
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.title,
    required this.child,
    this.exportColumns,
    this.exportRows,
    this.exportMetadata,
  });

  final String title;
  final Widget child;
  final List<String>? exportColumns;
  final List<List<Object?>>? exportRows;
  final Map<String, Object?>? exportMetadata;

  @override
  Widget build(BuildContext context) => Card(
    elevation: 0,
    color: Colors.white,
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (exportColumns != null &&
                  exportRows != null &&
                  exportMetadata != null)
                PopupMenuButton<String>(
                  tooltip: context.tr('Export report data', '导出报表数据'),
                  icon: const Icon(Icons.download_outlined),
                  onSelected: (format) => unawaited(
                    _saveAnalyticsExport(
                      context,
                      format: format,
                      metadata: exportMetadata!,
                      columns: exportColumns!,
                      rows: exportRows!,
                    ),
                  ),
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'csv',
                      child: Text(context.tr('Download CSV', '下载 CSV')),
                    ),
                    PopupMenuItem(
                      value: 'json',
                      child: Text(context.tr('Download JSON', '下载 JSON')),
                    ),
                    PopupMenuItem(
                      value: 'pdf',
                      child: Text(context.tr('Download PDF', '下载 PDF')),
                    ),
                  ],
                ),
            ],
          ),
          const Divider(height: 28),
          child,
        ],
      ),
    ),
  );
}

Future<void> _saveAnalyticsExport(
  BuildContext context, {
  required String format,
  required Map<String, Object?> metadata,
  required List<String> columns,
  required List<List<Object?>> rows,
}) async {
  final dialogTitle = context.tr('Export report', '导出报表');
  final exportedMessage = context.tr('Report exported.', '报表已导出。');
  final errorMessage = context.tr('Could not export this report.', '无法导出此报表。');
  try {
    final reportName =
        metadata['reportTitle']?.toString() ?? 'analytics-report';
    final safeReportName = reportName
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_-]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    final rangeFrom = metadata['from']?.toString();
    final rangeTo = metadata['to']?.toString();
    final dateSuffix = rangeFrom == null || rangeTo == null
        ? ''
        : '_${rangeFrom}_$rangeTo';
    final fileName =
        '${safeReportName.isEmpty ? 'analytics-report' : safeReportName}'
        '$dateSuffix.$format';
    final bytes = format == 'pdf'
        ? await AnalyticsReportExport.pdf(
            metadata: metadata,
            columns: columns,
            rows: rows,
          )
        : Uint8List.fromList(
            utf8.encode(
              format == 'csv'
                  ? AnalyticsReportExport.csv(columns, rows)
                  : AnalyticsReportExport.json(
                      metadata: metadata,
                      columns: columns,
                      rows: rows,
                    ),
            ),
          );
    final result = await FilePicker.platform.saveFile(
      dialogTitle: dialogTitle,
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: [format],
      bytes: bytes,
    );
    if (result != null && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(exportedMessage)));
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(errorMessage)));
    }
  }
}

class _TableRow extends StatelessWidget {
  const _TableRow({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      children: [
        Expanded(child: Text(label, overflow: TextOverflow.ellipsis)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
      ],
    ),
  );
}

class _AcquisitionTableRow extends StatelessWidget {
  const _AcquisitionTableRow(this.row);

  final AnalyticsTraffic row;

  @override
  Widget build(BuildContext context) {
    final details =
        <String, String?>{
              'Source': row.source,
              'Medium': row.medium,
              'Campaign': row.campaign,
              'Term': row.term,
              'Content': row.content,
            }.entries
            .where((entry) => entry.value?.isNotEmpty == true)
            .map(
              (entry) =>
                  '${context.tr(entry.key, switch (entry.key) {
                    'Source' => '来源',
                    'Medium' => '媒介',
                    'Campaign' => '活动',
                    'Term' => '关键词',
                    _ => '内容',
                  })}: ${entry.value}',
            )
            .join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr(
                    switch (row.channel) {
                      'direct' => 'Direct',
                      'referral' => 'Website referral',
                      'campaign' => 'Campaign',
                      'search_engine' => 'Search engine',
                      'social' => 'Social network',
                      'ai_assistant' => 'AI assistant',
                      _ => row.channel,
                    },
                    switch (row.channel) {
                      'direct' => '直接访问',
                      'referral' => '网站引荐',
                      'campaign' => '活动',
                      'search_engine' => '搜索引擎',
                      'social' => '社交网络',
                      'ai_assistant' => 'AI 助手',
                      _ => row.channel,
                    },
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                if (details.isNotEmpty)
                  Text(
                    details,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ),
          Text(
            '${row.sessions}',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _TablePlaceholder extends StatelessWidget {
  const _TablePlaceholder({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 125,
    child: Center(
      child: Text(
        label,
        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    ),
  );
}

class _EmptyChart extends StatelessWidget {
  const _EmptyChart();
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 230,
    child: Center(
      child: Text(
        context.tr(
          'Data will appear after your tracker receives events.',
          '追踪器收到事件后，数据将在这里显示。',
        ),
      ),
    ),
  );
}

class _TrendChart extends StatelessWidget {
  const _TrendChart({required this.values, required this.chartType});
  final List<double> values;
  final String chartType;
  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _TrendPainter(values, chartType),
    child: const SizedBox.expand(),
  );
}

class _TrendPainter extends CustomPainter {
  const _TrendPainter(this.values, this.chartType);
  final List<double> values;
  final String chartType;
  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = const Color(0xffe6eaf0)
      ..strokeWidth = 1;
    for (var i = 1; i < 4; i++) {
      canvas.drawLine(
        Offset(0, size.height * i / 4),
        Offset(size.width, size.height * i / 4),
        grid,
      );
    }
    if (values.isEmpty) {
      return;
    }
    final maxValue = math.max(1, values.reduce(math.max));
    if (chartType == 'bar') {
      final slot = size.width / values.length;
      final barWidth = slot * .62;
      final paint = Paint()..color = const Color(0xff3766a0);
      for (var i = 0; i < values.length; i++) {
        final height = values[i] / maxValue * (size.height - 24);
        final left = i * slot + (slot - barWidth) / 2;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(left, size.height - height - 12, barWidth, height),
            const Radius.circular(3),
          ),
          paint,
        );
      }
      return;
    }
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = values.length == 1
          ? size.width / 2
          : i * size.width / (values.length - 1);
      final y = size.height - (values[i] / maxValue * (size.height - 24)) - 12;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    final fill = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(fill, Paint()..color = const Color(0x223766a0));
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xff3766a0)
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _TrendPainter old) =>
      old.values != values || old.chartType != chartType;
}

class _DashboardSkeleton extends StatelessWidget {
  const _DashboardSkeleton();
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: const [
      _Skeleton(height: 32, width: 180),
      SizedBox(height: 20),
      _Skeleton(height: 115),
      SizedBox(height: 18),
      _Skeleton(height: 300),
    ],
  );
}

class _Skeleton extends StatelessWidget {
  const _Skeleton({required this.height, this.width = double.infinity});
  final double height;
  final double width;
  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xffe2e7ed),
        borderRadius: BorderRadius.circular(8),
      ),
    ),
  );
}

class _DashboardError extends StatelessWidget {
  const _DashboardError({required this.onRetry});
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.cloud_off_outlined, size: 42),
        const SizedBox(height: 12),
        Text(context.tr('Analytics could not be loaded.', '无法加载分析数据。')),
        const SizedBox(height: 10),
        FilledButton.tonal(
          onPressed: onRetry,
          child: Text(context.tr('Retry', '重试')),
        ),
      ],
    ),
  );
}

String _duration(int milliseconds) {
  final seconds = milliseconds ~/ 1000;
  return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}
