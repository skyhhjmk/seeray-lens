import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/i18n/app_i18n.dart';
import '../../auth/application/auth_controller.dart';

class SystemAdminPage extends ConsumerStatefulWidget {
  const SystemAdminPage({super.key});

  @override
  ConsumerState<SystemAdminPage> createState() => _SystemAdminPageState();
}

class _SystemAdminPageState extends ConsumerState<SystemAdminPage> {
  static const _pageSize = 50;
  int _userPage = 0;
  int _sitePage = 0;
  int _userTotal = 0;
  int _siteTotal = 0;
  bool _loadingUsers = true;
  bool _loadingSites = true;
  String? _error;
  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _sites = [];
  List<Map<String, dynamic>> _workspaces = [];

  @override
  void initState() {
    super.initState();
    Future.microtask(_loadInitial);
  }

  Future<void> _loadInitial() async {
    try {
      final api = ref.read(apiProvider);
      final workspaceData = await api.request('GET', '/api/v1/admin/workspaces') as List;
      if (!mounted) return;
      setState(() => _workspaces = workspaceData.cast<Map<String, dynamic>>());
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
    await Future.wait([_loadUsers(), _loadSites()]);
  }

  Future<void> _loadUsers({int? page}) async {
    final nextPage = page ?? _userPage;
    setState(() {
      _loadingUsers = true;
      _error = null;
    });
    try {
      final data = await ref.read(apiProvider).request(
        'GET',
        '/api/v1/admin/users?page=$nextPage&size=$_pageSize',
      ) as Map;
      if (!mounted) return;
      setState(() {
        _userPage = nextPage;
        _userTotal = data['total'] as int;
        _users = (data['items'] as List).cast<Map<String, dynamic>>();
        _loadingUsers = false;
      });
    } catch (error) {
      if (mounted) setState(() { _loadingUsers = false; _error = '$error'; });
    }
  }

  Future<void> _loadSites({int? page}) async {
    final nextPage = page ?? _sitePage;
    setState(() {
      _loadingSites = true;
      _error = null;
    });
    try {
      final data = await ref.read(apiProvider).request(
        'GET',
        '/api/v1/admin/sites?page=$nextPage&size=$_pageSize',
      ) as Map;
      if (!mounted) return;
      setState(() {
        _sitePage = nextPage;
        _siteTotal = data['total'] as int;
        _sites = (data['items'] as List).cast<Map<String, dynamic>>();
        _loadingSites = false;
      });
    } catch (error) {
      if (mounted) setState(() { _loadingSites = false; _error = '$error'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!ref.watch(authProvider).isSystemAdmin) {
      return Scaffold(
        appBar: AppBar(title: Text(context.tr('System administration', '系统管理'))),
        body: Center(child: Text(context.tr('System administrator permission required.', '需要系统管理员权限。'))),
      );
    }
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(onPressed: () => context.go('/workspaces'), icon: const Icon(Icons.arrow_back)),
          title: Text(context.tr('System administration', '系统管理')),
          actions: [
            IconButton(tooltip: context.tr('Refresh', '刷新'), onPressed: _loadInitial, icon: const Icon(Icons.refresh)),
            const LanguageMenu(),
          ],
          bottom: TabBar(tabs: [
            Tab(text: context.tr('Users', '用户')),
            Tab(text: context.tr('Sites', '站点')),
          ]),
        ),
        body: Column(
          children: [
            if (_error != null)
              MaterialBanner(
                content: Text(_error!),
                actions: [TextButton(onPressed: _loadInitial, child: Text(context.tr('Retry', '重试')))],
              ),
            Expanded(child: TabBarView(children: [_usersTab(), _sitesTab()])),
          ],
        ),
      ),
    );
  }

  Widget _usersTab() => Column(children: [
    Expanded(
      child: _loadingUsers
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: _users.length,
              itemBuilder: (context, index) {
                final user = _users[index];
                final active = user['status'] == 'active';
                final systemAdmin = user['systemAdmin'] == true;
                return Card(
                  margin: const EdgeInsets.fromLTRB(12, 6, 12, 2),
                  child: ListTile(
                    leading: CircleAvatar(child: Icon(systemAdmin ? Icons.admin_panel_settings : Icons.person_outline)),
                    title: Text(user['displayName'] as String),
                    subtitle: Text('${user['email']} · ${active ? context.tr('Active', '启用') : context.tr('Disabled', '停用')} · ${user['workspaceCount']} ${context.tr('workspaces', '个工作区')}'),
                    isThreeLine: false,
                    trailing: PopupMenuButton<String>(
                      onSelected: (action) => _userAction(user, action),
                      itemBuilder: (_) => [
                        PopupMenuItem(value: 'edit', child: Text(context.tr('Edit profile', '编辑资料'))),
                        PopupMenuItem(value: 'status', child: Text(active ? context.tr('Disable account', '停用账号') : context.tr('Enable account', '启用账号'))),
                        PopupMenuItem(value: 'admin', child: Text(systemAdmin ? context.tr('Remove system admin', '撤销系统管理员') : context.tr('Make system admin', '设为系统管理员'))),
                        PopupMenuItem(value: 'password', child: Text(context.tr('Reset password', '重置密码'))),
                      ],
                    ),
                  ),
                );
              },
            ),
    ),
    _pager(_userPage, _userTotal, _loadingUsers, _loadUsers),
  ]);

  Widget _sitesTab() => Column(children: [
    Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Align(
        alignment: Alignment.centerRight,
        child: FilledButton.icon(onPressed: _createSite, icon: const Icon(Icons.add), label: Text(context.tr('Create site', '创建站点'))),
      ),
    ),
    Expanded(
      child: _loadingSites
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: _sites.length,
              itemBuilder: (context, index) {
                final site = _sites[index];
                final workspace = _workspaceName(site['workspaceId'] as String);
                return Card(
                  margin: const EdgeInsets.fromLTRB(12, 6, 12, 2),
                  child: ListTile(
                    leading: Icon(site['trackingEnabled'] == true ? Icons.language : Icons.language_outlined),
                    title: Text(site['name'] as String),
                    subtitle: Text('$workspace · ${site['trackingId']} · ${site['timezone']}'),
                    trailing: PopupMenuButton<String>(
                      onSelected: (action) => _siteAction(site, action),
                      itemBuilder: (_) => [
                        PopupMenuItem(value: 'edit', child: Text(context.tr('Edit site', '编辑站点'))),
                        PopupMenuItem(value: 'domains', child: Text(context.tr('Manage allowed domains', '管理允许域名'))),
                        PopupMenuItem(value: 'delete', child: Text(context.tr('Delete site', '删除站点'))),
                      ],
                    ),
                  ),
                );
              },
            ),
    ),
    _pager(_sitePage, _siteTotal, _loadingSites, _loadSites),
  ]);

  Widget _pager(int page, int total, bool loading, Future<void> Function({int? page}) load) {
    final lastPage = total == 0 ? 0 : (total - 1) ~/ _pageSize;
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        IconButton(onPressed: loading || page == 0 ? null : () => load(page: page - 1), icon: const Icon(Icons.chevron_left)),
        Text('${page + 1} / ${lastPage + 1} · $total'),
        IconButton(onPressed: loading || page >= lastPage ? null : () => load(page: page + 1), icon: const Icon(Icons.chevron_right)),
      ]),
    );
  }

  Future<void> _userAction(Map<String, dynamic> user, String action) async {
    try {
      if (action == 'edit') {
        final email = TextEditingController(text: user['email'] as String);
        final name = TextEditingController(text: user['displayName'] as String);
        final result = await showDialog<Map<String, String>>(context: context, builder: (dialogContext) => AlertDialog(
          title: Text(context.tr('Edit user', '编辑用户')),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: name, decoration: InputDecoration(labelText: context.tr('Display name', '显示名称'))),
            TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: InputDecoration(labelText: context.tr('Login email', '登录邮箱'))),
          ]),
          actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(context.tr('Cancel', '取消'))), FilledButton(onPressed: () => Navigator.pop(dialogContext, {'email': email.text.trim(), 'displayName': name.text.trim()}), child: Text(context.tr('Save', '保存')))],
        ));
        email.dispose();
        name.dispose();
        if (result == null) return;
        await ref.read(apiProvider).request('PATCH', '/api/v1/admin/users/${user['id']}', body: result);
      } else if (action == 'status' || action == 'admin') {
        final body = action == 'status'
            ? {'status': user['status'] == 'active' ? 'disabled' : 'active'}
            : {'systemAdmin': user['systemAdmin'] != true};
        await ref.read(apiProvider).request('PATCH', '/api/v1/admin/users/${user['id']}', body: body);
      } else {
        final result = await ref.read(apiProvider).request('POST', '/api/v1/admin/users/${user['id']}/reset-password') as Map;
        if (!mounted) return;
        await showDialog<void>(context: context, builder: (dialogContext) => AlertDialog(
          title: Text(context.tr('Temporary password', '临时密码')),
          content: SelectableText('${result['temporaryPassword']}\n\n${context.tr('This is shown once. The user must replace it after signing in.', '此密码仅显示一次。用户登录后必须立即更改。')}'),
          actions: [FilledButton(onPressed: () => Navigator.pop(dialogContext), child: Text(context.tr('Done', '完成')))],
        ));
      }
      await _loadUsers();
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _siteAction(Map<String, dynamic> site, String action) async {
    if (action == 'domains') {
      context.go('/sites/${site['id']}/domains');
      return;
    }
    if (action == 'delete') {
      final confirm = TextEditingController();
      final accepted = await showDialog<bool>(context: context, builder: (dialogContext) => AlertDialog(
        title: Text(context.tr('Delete site and its data?', '删除站点及其数据？')),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(context.tr('This permanently removes analytics and site configuration. Enter the tracking ID to confirm.', '此操作会永久删除分析数据和站点配置。请输入追踪 ID 确认。')),
          const SizedBox(height: 12),
          SelectableText(site['trackingId'] as String),
          TextField(controller: confirm, decoration: InputDecoration(labelText: context.tr('Tracking ID', '追踪 ID'))),
        ]),
        actions: [TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(context.tr('Cancel', '取消'))), FilledButton(onPressed: () => Navigator.pop(dialogContext, confirm.text.trim() == site['trackingId']), child: Text(context.tr('Delete permanently', '永久删除')))],
      ));
      final value = confirm.text.trim();
      confirm.dispose();
      if (accepted != true) return;
      try {
        await ref.read(apiProvider).request('DELETE', '/api/v1/admin/sites/${site['id']}', body: {'confirmTrackingId': value});
        await _loadSites();
      } catch (error) { _showError(error); }
      return;
    }
    await _editSite(site);
  }

  Future<void> _createSite() async {
    await _editSite(null);
  }

  Future<void> _editSite(Map<String, dynamic>? site) async {
    if (_workspaces.isEmpty) {
      _showError(context.tr('No workspaces are available.', '当前没有可用工作区。'));
      return;
    }
    final name = TextEditingController(text: site?['name'] as String? ?? '');
    final timezone = TextEditingController(text: site?['timezone'] as String? ?? 'UTC');
    final language = TextEditingController(text: site?['defaultLanguage'] as String? ?? 'en');
    String workspaceId = site?['workspaceId'] as String? ?? _workspaces.first['id'] as String;
    bool enabled = site?['trackingEnabled'] as bool? ?? true;
    final result = await showDialog<Map<String, dynamic>>(context: context, builder: (dialogContext) => StatefulBuilder(builder: (context, update) => AlertDialog(
      title: Text(site == null ? context.tr('Create site', '创建站点') : context.tr('Edit site', '编辑站点')),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (site == null) DropdownButtonFormField<String>(value: workspaceId, decoration: InputDecoration(labelText: context.tr('Workspace', '工作区')), items: [for (final workspace in _workspaces) DropdownMenuItem(value: workspace['id'] as String, child: Text(workspace['name'] as String))], onChanged: (value) => update(() => workspaceId = value!)),
        TextField(controller: name, decoration: InputDecoration(labelText: context.tr('Site name', '站点名称'))),
        TextField(controller: timezone, decoration: InputDecoration(labelText: context.tr('Time zone', '时区'))),
        TextField(controller: language, decoration: InputDecoration(labelText: context.tr('Default language', '默认语言'))),
        if (site != null) SwitchListTile(value: enabled, onChanged: (value) => update(() => enabled = value), title: Text(context.tr('Tracking enabled', '启用采集'))),
      ])),
      actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(context.tr('Cancel', '取消'))), FilledButton(onPressed: () => Navigator.pop(dialogContext, {'workspaceId': workspaceId, 'name': name.text.trim(), 'timezone': timezone.text.trim(), 'defaultLanguage': language.text.trim(), 'trackingEnabled': enabled}), child: Text(context.tr('Save', '保存')))],
    )));
    name.dispose(); timezone.dispose(); language.dispose();
    if (result == null) return;
    try {
      if (site == null) {
        await ref.read(apiProvider).request('POST', '/api/v1/admin/sites', body: {...result, 'rawRetentionDays': 30, 'aggregateRetentionDays': 730, 'requireConsent': false, 'fingerprintRiskEnabled': false, 'fingerprintRetentionDays': 30});
      } else {
        await ref.read(apiProvider).request('PATCH', '/api/v1/admin/sites/${site['id']}', body: {
          'name': result['name'],
          'timezone': result['timezone'],
          'defaultLanguage': result['defaultLanguage'],
          'trackingEnabled': result['trackingEnabled'],
        });
      }
      await _loadSites();
    } catch (error) { _showError(error); }
  }

  void _showError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
  }

  String _workspaceName(String id) {
    for (final workspace in _workspaces) {
      if (workspace['id'] == id) return workspace['name'] as String;
    }
    return id;
  }
}
