import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_i18n.dart';
import '../../../core/network/seeray_api.dart';
import '../../../shared/presentation/app_back_button.dart';
import '../../../shared/presentation/page_help_button.dart';
import '../application/workspace_audit_log.dart';

class WorkspaceAuditLogPage extends ConsumerStatefulWidget {
  const WorkspaceAuditLogPage({required this.workspaceId, super.key});

  final String workspaceId;

  @override
  ConsumerState<WorkspaceAuditLogPage> createState() =>
      _WorkspaceAuditLogPageState();
}

class _WorkspaceAuditLogPageState extends ConsumerState<WorkspaceAuditLogPage> {
  late DateTime _from = _day(
    DateTime.now().toUtc().subtract(const Duration(days: 29)),
  );
  late DateTime _to = _day(DateTime.now().toUtc());
  final List<WorkspaceAuditEntry> _entries = [];
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
    appBar: AppBar(
      leading: const AppBackButton(fallback: '/workspaces'),
      title: Text(context.tr('Workspace activity', '工作区活动记录')),
      actions: [
        const PageHelpButton(
          englishTitle: 'Workspace activity',
          chineseTitle: '工作区活动记录',
          englishBody:
              'Review successful workspace and access-management changes. This history stores the actor, action, resource type, and resource ID only; it never stores request bodies, passwords, API-token values, or invitation tokens.',
          chineseBody:
              '查看工作区和访问管理相关的成功变更。日志只保存操作者、动作、资源类型和资源 ID，不保存请求正文、密码、API Token 明文或邀请 Token。',
        ),
        const LanguageMenu(),
        IconButton(
          tooltip: context.tr('Refresh', '刷新'),
          onPressed: _loading ? null : () => _load(reset: true),
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(onRefresh: () => _load(reset: true), child: _body()),
  );

  Widget _body() => LayoutBuilder(
    builder: (context, constraints) => ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (constraints.maxWidth < 720)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _headerTitle(context),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: _rangeButton(context),
              ),
            ],
          )
        else
          Row(
            children: [
              Expanded(child: _headerTitle(context)),
              _rangeButton(context),
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
                      'No administrative changes in this period.',
                      '此时间段内没有管理变更。',
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
    ),
  );

  Widget _headerTitle(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        context.tr('Administrative history', '管理操作历史'),
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 4),
      Text(
        context.tr(
          'Workspace, member, invitation, site-creation, and API-token changes · date filter in UTC, event times shown locally',
          '工作区、成员、邀请、站点创建与 API Token 变更 · 日期筛选按 UTC，事件时间按本地时区显示',
        ),
      ),
    ],
  );

  Widget _rangeButton(BuildContext context) => OutlinedButton.icon(
    onPressed: _pickRange,
    icon: const Icon(Icons.date_range_outlined),
    label: Text('${_date(_from)} – ${_date(_to)} UTC'),
  );

  Widget _entryCard(WorkspaceAuditEntry entry) {
    final action = _action(entry.action);
    final resource = _resource(entry.resource);
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
          '${entry.actorApiTokenName == null ? (entry.actorEmail ?? context.tr('Former user', '已移除用户')) : '${entry.actorEmail ?? context.tr('Former user', '已移除用户')} · API ${entry.actorApiTokenName}'} $action',
        ),
        subtitle: Text(
          [
            resource,
            if (entry.resourceId != null)
              '${context.tr('ID', '标识')} · ${entry.resourceId}',
            _dateTime(entry.createdAt),
          ].join('  ·  '),
        ),
        isThreeLine: entry.resourceId != null,
      ),
    );
  }

  String _action(String action) => switch (action) {
    'CREATE_WORKSPACE' => context.tr('created a workspace', '创建了工作区'),
    'UPDATE_WORKSPACE' => context.tr('updated workspace settings', '更新了工作区设置'),
    'CREATE_SITE' => context.tr('created a site', '创建了站点'),
    'ADD_MEMBER' => context.tr('added a member', '添加了成员'),
    'CHANGE_ROLE' => context.tr('changed a member role', '更改了成员角色'),
    'REMOVE_MEMBER' => context.tr('removed a member', '移除了成员'),
    'TRANSFER_OWNERSHIP' => context.tr(
      'transferred workspace ownership',
      '移交了工作区所有权',
    ),
    'CREATE_INVITATION' => context.tr(
      'sent a workspace invitation',
      '发送了工作区邀请',
    ),
    'REVOKE_INVITATION' => context.tr(
      'revoked a workspace invitation',
      '撤销了工作区邀请',
    ),
    'ACCEPT_INVITATION' => context.tr(
      'accepted a workspace invitation',
      '接受了工作区邀请',
    ),
    'CREATE_API_TOKEN' => context.tr('created an API token', '创建了 API Token'),
    'REVOKE_API_TOKEN' => context.tr('revoked an API token', '撤销了 API Token'),
    _ => action,
  };

  String _resource(String resource) => switch (resource) {
    'workspace' => context.tr('Workspace', '工作区'),
    'site' => context.tr('Site', '站点'),
    'member' => context.tr('Member', '成员'),
    'invitation' => context.tr('Invitation', '邀请'),
    'api-token' => context.tr('API token', 'API Token'),
    _ => resource,
  };

  IconData _icon(String action) => switch (action) {
    'CREATE_WORKSPACE' ||
    'CREATE_SITE' ||
    'ADD_MEMBER' ||
    'CREATE_INVITATION' => Icons.add_circle_outline,
    'REMOVE_MEMBER' ||
    'REVOKE_INVITATION' ||
    'REVOKE_API_TOKEN' => Icons.remove_circle_outline,
    'TRANSFER_OWNERSHIP' => Icons.swap_horiz,
    'ACCEPT_INVITATION' => Icons.check_circle_outline,
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
          .read(workspaceAuditLogProvider)
          .load(workspaceId: widget.workspaceId, from: _from, to: _to);
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
            : context.tr('Could not load workspace activity.', '无法加载工作区活动记录。');
      });
    }
  }

  Future<void> _loadMore() async {
    final cursor = _cursor;
    if (cursor == null) return;
    setState(() => _loadingMore = true);
    try {
      final page = await ref
          .read(workspaceAuditLogProvider)
          .load(
            workspaceId: widget.workspaceId,
            from: _from,
            to: _to,
            cursor: cursor,
          );
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
            : context.tr('Could not load older activity.', '无法加载更早的活动记录。');
      });
    }
  }

  Future<void> _pickRange() async {
    final today = _day(DateTime.now().toUtc());
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: today,
      initialDateRange: DateTimeRange(start: _from, end: _to),
      helpText: context.tr('Choose activity period (UTC)', '选择活动时间范围（UTC）'),
    );
    if (!mounted || range == null) return;
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
      '${value.year}-${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  static String _dateTime(DateTime value) =>
      '${_date(value)} ${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';
}
