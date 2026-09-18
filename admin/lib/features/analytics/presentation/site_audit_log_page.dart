import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_i18n.dart';
import '../../../core/network/seeray_api.dart';
import '../../../shared/presentation/page_help_button.dart';
import '../../../shared/presentation/site_top_bar.dart';
import '../application/site_audit_log.dart';

class SiteAuditLogPage extends ConsumerStatefulWidget {
  const SiteAuditLogPage({
    required this.siteId,
    this.embedded = false,
    super.key,
  });

  final String siteId;
  final bool embedded;

  @override
  ConsumerState<SiteAuditLogPage> createState() => _SiteAuditLogPageState();
}

class _SiteAuditLogPageState extends ConsumerState<SiteAuditLogPage> {
  late DateTime _from = _day(DateTime.now().subtract(const Duration(days: 29)));
  late DateTime _to = _day(DateTime.now());
  final List<SiteAuditEntry> _entries = [];
  String? _cursor;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(() => _load(reset: true));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xfff3f5f8),
    appBar: widget.embedded
        ? null
        : SiteTopBar(
            siteId: widget.siteId,
            selected: SiteTopTab.auditLog,
            help: const PageHelpButton(
              englishTitle: 'Audit log',
              chineseTitle: '审计日志',
              englishBody:
                  'Review successful site configuration changes, who made them, and when. Request contents, credentials, and analytics queries are never stored in this history.',
              chineseBody: '查看站点配置变更的操作人和时间。日志不保存请求正文、密钥或分析查询内容。',
            ),
            onRefresh: _loading ? null : () => _load(reset: true),
          ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(onRefresh: () => _load(reset: true), child: _body()),
  );

  Widget _body() => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr('Audit log', '审计日志'),
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  context.tr(
                    'Successful changes to site settings and analytics configuration. Data is retained for as long as the site exists.',
                    '记录站点设置与分析配置的成功变更。站点存在期间会保留这些记录。',
                  ),
                ),
              ],
            ),
          ),
          OutlinedButton.icon(
            onPressed: _pickRange,
            icon: const Icon(Icons.date_range_outlined),
            label: Text('${_date(_from)} – ${_date(_to)}'),
          ),
        ],
      ),
      const SizedBox(height: 16),
      if (_error != null) ...[
        Card(
          child: ListTile(
            leading: const Icon(Icons.error_outline, color: Colors.red),
            title: Text(_error!),
            trailing: TextButton(
              onPressed: () => _load(reset: true),
              child: Text(context.tr('Retry', '重试')),
            ),
          ),
        ),
        const SizedBox(height: 12),
      ],
      if (_entries.isEmpty && _error == null)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              children: [
                const Icon(Icons.history, size: 40, color: Color(0xff748398)),
                const SizedBox(height: 12),
                Text(
                  context.tr(
                    'No configuration changes in this period.',
                    '此时间段内没有配置变更。',
                  ),
                ),
              ],
            ),
          ),
        )
      else
        ..._entries.map(_entryCard),
      if (_cursor != null)
        Align(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: OutlinedButton.icon(
              onPressed: _loadingMore ? null : _loadMore,
              icon: _loadingMore
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.expand_more),
              label: Text(context.tr('Load older activity', '加载更早记录')),
            ),
          ),
        ),
      const SizedBox(height: 24),
    ],
  );

  Widget _entryCard(SiteAuditEntry entry) {
    final action = switch (entry.action) {
      'CREATE' => context.tr('Created', '创建了'),
      'UPDATE' => context.tr('Updated', '更新了'),
      'DELETE' => context.tr('Deleted', '删除了'),
      'PUBLISH' => context.tr('Published', '发布了'),
      'DUPLICATE' => context.tr('Duplicated', '复制了'),
      'SEND_NOW' => context.tr('Sent immediately', '立即发送了'),
      _ => entry.action,
    };
    final resource = switch (entry.resource) {
      'custom-dimensions' => context.tr('custom dimension', '自定义维度'),
      'tag-manager' => context.tr('tag manager item', '标签管理项'),
      'site' => context.tr('site settings', '站点设置'),
      'domains' => context.tr('allowed domain', '允许的域名'),
      'dashboards' => context.tr('dashboard', '仪表盘'),
      'segments' => context.tr('segment', '用户分群'),
      'goals' => context.tr('goal', '目标'),
      'experiments' => context.tr('experiment', '实验'),
      'funnels' => context.tr('funnel', '漏斗'),
      'heatmaps' => context.tr('heatmap settings', '热图设置'),
      'annotations' => context.tr('analytics annotation', '分析注释'),
      _ => entry.resource,
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: const Color(0xffe8edf4),
          child: Icon(
            _icon(entry.action),
            color: const Color(0xff385172),
            size: 20,
          ),
        ),
        title: Text(
          '${entry.actorEmail ?? context.tr('Former user', '已移除用户')} $action $resource',
        ),
        subtitle: Text(
          [
            if (entry.resourceId != null)
              '${context.tr('Record', '记录')} · ${entry.resourceId}',
            _dateTime(entry.createdAt),
          ].join('  ·  '),
        ),
        isThreeLine: entry.resourceId != null,
      ),
    );
  }

  IconData _icon(String action) => switch (action) {
    'CREATE' => Icons.add_circle_outline,
    'DELETE' => Icons.delete_outline,
    'PUBLISH' => Icons.rocket_launch_outlined,
    'DUPLICATE' => Icons.copy_outlined,
    'SEND_NOW' => Icons.outgoing_mail,
    _ => Icons.edit_outlined,
  };

  Future<void> _load({required bool reset}) async {
    if (reset) {
      setState(() {
        _loading = true;
        _error = null;
        _cursor = null;
        _entries.clear();
      });
    }
    try {
      final page = await ref
          .read(siteAuditLogProvider)
          .load(siteId: widget.siteId, from: _from, to: _to);
      if (!mounted) return;
      setState(() {
        _entries.addAll(page.entries);
        _cursor = page.nextCursor;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error is ApiFailure
            ? error.message
            : context.tr('Could not load audit history.', '无法加载审计记录。');
      });
    }
  }

  Future<void> _loadMore() async {
    final cursor = _cursor;
    if (cursor == null) return;
    setState(() => _loadingMore = true);
    try {
      final page = await ref
          .read(siteAuditLogProvider)
          .load(siteId: widget.siteId, from: _from, to: _to, cursor: cursor);
      if (!mounted) return;
      setState(() {
        _entries.addAll(page.entries);
        _cursor = page.nextCursor;
        _loadingMore = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingMore = false;
        _error = error is ApiFailure
            ? error.message
            : context.tr('Could not load older activity.', '无法加载更早记录。');
      });
    }
  }

  Future<void> _pickRange() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _from, end: _to),
      helpText: context.tr('Choose audit period', '选择审计时间范围'),
    );
    if (!mounted) return;
    if (range == null) return;
    final start = _day(range.start);
    final end = _day(range.end);
    if (end.difference(start).inDays > 365) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.tr(
              'Choose a period of 366 days or less.',
              '请选择不超过 366 天的时间范围。',
            ),
          ),
        ),
      );
      return;
    }
    setState(() {
      _from = start;
      _to = end;
    });
    await _load(reset: true);
  }

  static DateTime _day(DateTime value) =>
      DateTime(value.year, value.month, value.day);
  static String _date(DateTime value) =>
      '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
  static String _dateTime(DateTime value) =>
      '${_date(value)} ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
}
