import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_i18n.dart';
import '../../../core/network/seeray_api.dart';
import '../../../shared/presentation/app_back_button.dart';
import '../../../shared/presentation/page_help_button.dart';
import '../application/workspace_audit_log.dart';

enum _WorkspaceActivityView { changes, apiReads, apiWrites, authentication }

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
  final List<WorkspaceApiReadEntry> _apiReadEntries = [];
  final List<WorkspaceApiWriteEntry> _apiWriteEntries = [];
  final List<WorkspaceAuthActivityEntry> _authEntries = [];
  String? _cursor;
  _WorkspaceActivityView _view = _WorkspaceActivityView.changes;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  int _loadGeneration = 0;

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
              'Review administrative changes, human-user API reads and writes, and member authentication activity. API and authentication history are retained for 30 days and never store query values, request or response bodies, credentials, IP addresses or user agents.',
          chineseBody:
              '查看管理变更、真人用户 API 读取/写入和成员认证活动。API 读取/写入及认证历史保留 30 天；不保存查询值、请求或响应正文、凭据、IP 或 User-Agent。',
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
        _viewSelector(context, constraints.maxWidth),
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
        if (_activeEntriesEmpty && _error == null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                children: [
                  Icon(
                    _view == _WorkspaceActivityView.changes
                        ? Icons.history
                        : _view == _WorkspaceActivityView.apiReads
                        ? Icons.visibility_outlined
                        : _view == _WorkspaceActivityView.apiWrites
                        ? Icons.edit_note_outlined
                        : Icons.login_outlined,
                    size: 40,
                    color: const Color(0xff748398),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _view == _WorkspaceActivityView.changes
                        ? context.tr(
                            'No administrative changes in this period.',
                            '此时间段内没有管理变更。',
                          )
                        : _view == _WorkspaceActivityView.apiReads
                        ? context.tr(
                            'No human-user API reads in the retained period.',
                            '保留时间段内没有真人用户 API 读取记录。',
                          )
                        : _view == _WorkspaceActivityView.apiWrites
                        ? context.tr(
                            'No successful human-user API writes in the retained period.',
                            '保留时间段内没有真人用户成功写入记录。',
                          )
                        : context.tr(
                            'No authentication activity in the retained period.',
                            '保留时间段内没有认证活动记录。',
                          ),
                  ),
                ],
              ),
            ),
          )
        else if (_view == _WorkspaceActivityView.changes)
          ..._entries.map(_entryCard)
        else if (_view == _WorkspaceActivityView.apiReads)
          ..._apiReadEntries.map(_apiReadCard),
        if (_view == _WorkspaceActivityView.apiWrites)
          ..._apiWriteEntries.map(_apiWriteCard),
        if (_view == _WorkspaceActivityView.authentication)
          ..._authEntries.map(_authCard),
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
        _view == _WorkspaceActivityView.changes
            ? context.tr('Administrative history', '管理操作历史')
            : _view == _WorkspaceActivityView.apiReads
            ? context.tr('Human-user API read access', '真人用户 API 读取记录')
            : _view == _WorkspaceActivityView.apiWrites
            ? context.tr('Human-user API write history', '真人用户 API 写入记录')
            : context.tr('Authentication activity', '认证活动'),
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 4),
      Text(
        _view == _WorkspaceActivityView.changes
            ? context.tr(
                'Workspace, member, invitation, site-creation, and API-token changes · date filter in UTC, event times shown locally',
                '工作区、成员、邀请、站点创建与 API Token 变更 · 日期筛选按 UTC，事件时间按本地时区显示',
              )
            : _view == _WorkspaceActivityView.apiReads
            ? context.tr(
                'Authenticated user GET/HEAD reads only · route templates, status and site scope · retained for 30 days',
                '只记录已认证用户的 GET/HEAD 读取 · 路由模板、状态与站点范围 · 保留 30 天',
              )
            : _view == _WorkspaceActivityView.apiWrites
            ? context.tr(
                'Successful authenticated user POST/PUT/PATCH/DELETE requests only · route templates, status and site scope · retained for 30 days',
                '只记录已认证用户成功的 POST/PUT/PATCH/DELETE 请求 · 路由模板、状态与站点范围 · 保留 30 天',
              )
            : context.tr(
                'Sign-in, rejected sign-in, session refresh, sign-out and rejected refresh · no credentials, IP addresses or user agents · retained for 30 days',
                '登录、拒绝登录、会话刷新、登出和拒绝刷新 · 不记录凭据、IP 或 User-Agent · 保留 30 天',
              ),
      ),
    ],
  );

  Widget _viewSelector(BuildContext context, double width) {
    final options = <(_WorkspaceActivityView, String, String, IconData)>[
      (
        _WorkspaceActivityView.changes,
        'Admin changes',
        '管理变更',
        Icons.edit_note_outlined,
      ),
      (
        _WorkspaceActivityView.apiReads,
        'API read access',
        'API 读取记录',
        Icons.visibility_outlined,
      ),
      (
        _WorkspaceActivityView.apiWrites,
        'API write history',
        'API 写入记录',
        Icons.edit_note_outlined,
      ),
      (
        _WorkspaceActivityView.authentication,
        'Authentication',
        '认证活动',
        Icons.login_outlined,
      ),
    ];
    if (width < 720) {
      return Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          for (final (view, english, chinese, icon) in options)
            ChoiceChip(
              avatar: Icon(icon, size: 18),
              label: Text(context.tr(english, chinese)),
              selected: _view == view,
              onSelected: (_) => _selectView(view),
            ),
        ],
      );
    }
    return SegmentedButton<_WorkspaceActivityView>(
      segments: [
        for (final (view, english, chinese, icon) in options)
          ButtonSegment(
            value: view,
            icon: Icon(icon),
            label: Text(context.tr(english, chinese)),
          ),
      ],
      selected: {_view},
      showSelectedIcon: false,
      onSelectionChanged: (selection) => _selectView(selection.first),
    );
  }

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

  Widget _apiReadCard(WorkspaceApiReadEntry entry) => Card(
    margin: const EdgeInsets.only(bottom: 8),
    child: ListTile(
      leading: CircleAvatar(
        backgroundColor: const Color(0xffe8edf4),
        child: Icon(
          entry.statusCode < 400
              ? Icons.visibility_outlined
              : Icons.error_outline,
          color: entry.statusCode < 400
              ? const Color(0xff385172)
              : Colors.deepOrange,
          size: 20,
        ),
      ),
      title: Text(
        '${entry.actorEmail ?? context.tr('Former user', '已移除用户')} · ${entry.method} ${entry.routeTemplate}',
      ),
      subtitle: Text(
        [
          entry.siteName ?? context.tr('Workspace endpoint', '工作区接口'),
          '${context.tr('Status', '状态')} ${entry.statusCode}',
          _dateTime(entry.createdAt),
        ].join('  ·  '),
      ),
      isThreeLine: true,
    ),
  );

  Widget _apiWriteCard(WorkspaceApiWriteEntry entry) => Card(
    margin: const EdgeInsets.only(bottom: 8),
    child: ListTile(
      leading: CircleAvatar(
        backgroundColor: const Color(0xffe8edf4),
        child: Icon(
          entry.statusCode < 400
              ? Icons.edit_note_outlined
              : Icons.error_outline,
          color: entry.statusCode < 400
              ? const Color(0xff385172)
              : Colors.deepOrange,
          size: 20,
        ),
      ),
      title: Text(
        '${entry.actorEmail ?? context.tr('Former user', '已移除用户')} · ${entry.method} ${entry.routeTemplate}',
      ),
      subtitle: Text(
        [
          entry.siteName ?? context.tr('Workspace endpoint', '工作区接口'),
          '${context.tr('Status', '状态')} ${entry.statusCode}',
          _dateTime(entry.createdAt),
        ].join('  ·  '),
      ),
      isThreeLine: true,
    ),
  );

  Widget _authCard(WorkspaceAuthActivityEntry entry) {
    final (label, icon, color) = switch (entry.eventType) {
      'LOGIN_SUCCEEDED' => (
        context.tr('signed in', '登录成功'),
        Icons.check_circle_outline,
        const Color(0xff287044),
      ),
      'LOGIN_FAILED' => (
        context.tr('sign-in rejected', '登录被拒绝'),
        Icons.warning_amber_outlined,
        Colors.deepOrange,
      ),
      'SESSION_REFRESHED' => (
        context.tr('refreshed a session', '刷新了会话'),
        Icons.sync,
        const Color(0xff385172),
      ),
      'LOGOUT' => (
        context.tr('signed out', '已登出'),
        Icons.logout,
        const Color(0xff385172),
      ),
      'REFRESH_REJECTED' => (
        context.tr('session refresh rejected', '会话刷新被拒绝'),
        Icons.error_outline,
        Colors.deepOrange,
      ),
      _ => (entry.eventType, Icons.security_outlined, const Color(0xff385172)),
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: const Color(0xffe8edf4),
          child: Icon(icon, color: color, size: 20),
        ),
        title: Text(
          '${entry.actorEmail ?? context.tr('Former user', '已移除用户')} $label',
        ),
        subtitle: Text(_dateTime(entry.createdAt)),
      ),
    );
  }

  bool get _activeEntriesEmpty => switch (_view) {
    _WorkspaceActivityView.changes => _entries.isEmpty,
    _WorkspaceActivityView.apiReads => _apiReadEntries.isEmpty,
    _WorkspaceActivityView.apiWrites => _apiWriteEntries.isEmpty,
    _WorkspaceActivityView.authentication => _authEntries.isEmpty,
  };

  void _selectView(_WorkspaceActivityView view) {
    if (view == _view) return;
    setState(() => _view = view);
    _load(reset: true);
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
    final generation = reset ? ++_loadGeneration : _loadGeneration;
    if (reset) {
      setState(() {
        _loading = true;
        _loadingMore = false;
        _error = null;
        _cursor = null;
        _entries.clear();
        _apiReadEntries.clear();
        _apiWriteEntries.clear();
        _authEntries.clear();
      });
    }
    try {
      String? nextCursor;
      WorkspaceAuditPage? changePage;
      WorkspaceApiReadPage? readPage;
      WorkspaceApiWritePage? writePage;
      WorkspaceAuthActivityPage? authPage;
      if (_view == _WorkspaceActivityView.changes) {
        changePage = await ref
            .read(workspaceAuditLogProvider)
            .load(workspaceId: widget.workspaceId, from: _from, to: _to);
        nextCursor = changePage.nextCursor;
      } else if (_view == _WorkspaceActivityView.apiReads) {
        readPage = await ref
            .read(workspaceApiReadLogProvider)
            .load(workspaceId: widget.workspaceId, from: _from, to: _to);
        nextCursor = readPage.nextCursor;
      } else if (_view == _WorkspaceActivityView.apiWrites) {
        writePage = await ref
            .read(workspaceApiWriteLogProvider)
            .load(workspaceId: widget.workspaceId, from: _from, to: _to);
        nextCursor = writePage.nextCursor;
      } else {
        authPage = await ref
            .read(workspaceAuthActivityProvider)
            .load(workspaceId: widget.workspaceId, from: _from, to: _to);
        nextCursor = authPage.nextCursor;
      }
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        if (changePage != null) _entries.addAll(changePage.entries);
        if (readPage != null) _apiReadEntries.addAll(readPage.entries);
        if (writePage != null) _apiWriteEntries.addAll(writePage.entries);
        if (authPage != null) _authEntries.addAll(authPage.entries);
        _cursor = nextCursor;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted || generation != _loadGeneration) return;
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
    final generation = _loadGeneration;
    setState(() => _loadingMore = true);
    try {
      String? nextCursor;
      WorkspaceAuditPage? changePage;
      WorkspaceApiReadPage? readPage;
      WorkspaceApiWritePage? writePage;
      WorkspaceAuthActivityPage? authPage;
      if (_view == _WorkspaceActivityView.changes) {
        changePage = await ref
            .read(workspaceAuditLogProvider)
            .load(
              workspaceId: widget.workspaceId,
              from: _from,
              to: _to,
              cursor: cursor,
            );
        nextCursor = changePage.nextCursor;
      } else if (_view == _WorkspaceActivityView.apiReads) {
        readPage = await ref
            .read(workspaceApiReadLogProvider)
            .load(
              workspaceId: widget.workspaceId,
              from: _from,
              to: _to,
              cursor: cursor,
            );
        nextCursor = readPage.nextCursor;
      } else if (_view == _WorkspaceActivityView.apiWrites) {
        writePage = await ref
            .read(workspaceApiWriteLogProvider)
            .load(
              workspaceId: widget.workspaceId,
              from: _from,
              to: _to,
              cursor: cursor,
            );
        nextCursor = writePage.nextCursor;
      } else {
        authPage = await ref
            .read(workspaceAuthActivityProvider)
            .load(
              workspaceId: widget.workspaceId,
              from: _from,
              to: _to,
              cursor: cursor,
            );
        nextCursor = authPage.nextCursor;
      }
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        if (changePage != null) _entries.addAll(changePage.entries);
        if (readPage != null) _apiReadEntries.addAll(readPage.entries);
        if (writePage != null) _apiWriteEntries.addAll(writePage.entries);
        if (authPage != null) _authEntries.addAll(authPage.entries);
        _cursor = nextCursor;
        _loadingMore = false;
      });
    } catch (error) {
      if (!mounted || generation != _loadGeneration) return;
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
