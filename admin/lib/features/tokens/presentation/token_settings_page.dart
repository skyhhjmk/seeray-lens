import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_i18n.dart';
import '../../../shared/presentation/app_back_button.dart';
import '../../../shared/presentation/page_help_button.dart';
import '../application/token_controller.dart';
import '../../workspaces/application/workspace_controller.dart';

class TokenSettingsPage extends ConsumerWidget {
  const TokenSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(apiTokensProvider);
    final workspaceId = ref.watch(currentWorkspaceProvider)?.id;
    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(fallback: '/sites'),
        title: Text(context.tr('Workspace API tokens', '工作区 API 令牌')),
        actions: const [
          PageHelpButton(
            englishTitle: 'API tokens',
            chineseTitle: 'API 令牌',
            englishBody:
                'API tokens allow server-to-server access to this workspace. Choose the least privilege needed, copy a new token immediately, and revoke it if it is no longer needed.',
            chineseBody: 'API 令牌用于服务端访问当前工作区。请按最小权限创建、立即保存新令牌，并在不再需要时撤销。',
          ),
          LanguageMenu(),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _create(context, ref),
        icon: const Icon(Icons.key),
        label: Text(context.tr('Create token', '创建令牌')),
      ),
      body: tokens.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(
          child: FilledButton.tonal(
            onPressed: () => ref.invalidate(apiTokensProvider),
            child: Text(context.tr('Retry loading tokens', '重新加载令牌')),
          ),
        ),
        data: (items) => ListView(
          padding: const EdgeInsets.all(16),
          children: items
              .map(
                (token) => Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      ListTile(
                        title: Text(token.name),
                        subtitle: Text(
                          '${token.prefix} • ${_scopeLabels(context, token.scopes)}'
                          '\n${context.tr('Created', '创建于')} ${token.createdAt}'
                          '\n${context.tr('Last used', '上次使用')} ${token.lastUsedAt ?? context.tr('Never', '从未使用')}'
                          '${token.expiresAt == null ? '' : '\n${context.tr('Expires', '到期于')} ${token.expiresAt}'}',
                        ),
                        trailing: token.revokedAt != null
                            ? Chip(label: Text(context.tr('Revoked', '已撤销')))
                            : token.isExpired
                            ? Chip(label: Text(context.tr('Expired', '已过期')))
                            : TextButton(
                                onPressed: () => ref
                                    .read(apiTokensProvider.notifier)
                                    .revoke(token.id),
                                child: Text(context.tr('Revoke', '撤销')),
                              ),
                      ),
                      const Divider(height: 1),
                      ExpansionTile(
                        title: Text(
                          context.tr('Recent API activity', '近期 API 活动'),
                        ),
                        subtitle: Text(
                          context.tr(
                            'Request method, route and response status · 30 days',
                            '仅记录请求方法、路由和状态码 · 保留 30 天',
                          ),
                        ),
                        children: [
                          _ApiTokenUsagePanel(
                            key: ValueKey('$workspaceId/${token.id}'),
                            workspaceId: workspaceId,
                            tokenId: token.id,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              )
              .toList(),
        ),
      ),
    );
  }

  String _scopeLabels(BuildContext context, String scopes) {
    final normalized = scopes.toLowerCase();
    final labels = <String>[
      if (normalized.contains('sites:read')) context.tr('Sites: read', '站点：读取'),
      if (normalized.contains('sites:write'))
        context.tr('Sites: write', '站点：写入'),
    ];
    return labels.isEmpty ? scopes : labels.join(', ');
  }

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final input = await showDialog<_TokenInput>(
      context: context,
      builder: (_) => const _CreateTokenDialog(),
    );
    if (input == null) {
      return;
    }
    try {
      final created = await ref
          .read(apiTokensProvider.notifier)
          .create(input.name, input.scopes, expiresAt: input.expiresAt);
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(context.tr('Copy this token now', '立即复制此令牌')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.tr(
                  'Save this token now. You cannot view it again after closing this dialog.',
                  '请立即保存此令牌。关闭此对话框后将无法再次查看。',
                ),
              ),
              const SizedBox(height: 12),
              SelectableText(created.plainToken),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.tr('Close', '关闭')),
            ),
            TextButton(
              onPressed: () async {
                await Clipboard.setData(
                  ClipboardData(text: created.plainToken),
                );
                if (context.mounted) Navigator.pop(context);
              },
              child: Text(context.tr('Copy and close', '复制并关闭')),
            ),
          ],
        ),
      );
    } on Exception catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }
}

class _ApiTokenUsagePanel extends ConsumerStatefulWidget {
  const _ApiTokenUsagePanel({
    required this.workspaceId,
    required this.tokenId,
    super.key,
  });

  final String? workspaceId;
  final String tokenId;

  @override
  ConsumerState<_ApiTokenUsagePanel> createState() =>
      _ApiTokenUsagePanelState();
}

class _ApiTokenUsagePanelState extends ConsumerState<_ApiTokenUsagePanel> {
  List<ApiTokenUsageEntry> _entries = const [];
  String? _nextCursor;
  int _retentionDays = 30;
  bool _loading = false;
  bool _loadingMore = false;
  Object? _error;
  Object? _moreError;
  bool _requested = false;

  @override
  Widget build(BuildContext context) {
    if (!_requested && !_loading && widget.workspaceId != null) {
      _requested = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load();
      });
    }
    if (widget.workspaceId == null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(context.tr('Select a workspace first.', '请先选择工作区。')),
      );
    }
    if ((!_requested || _loading) && _entries.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null && _entries.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(context.tr('Could not load token activity.', '无法加载令牌活动。')),
            TextButton(
              onPressed: _load,
              child: Text(context.tr('Retry', '重试')),
            ),
          ],
        ),
      );
    }
    if (_entries.isEmpty && !_loading) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Text(
          context.tr(
            'No API requests recorded in the last $_retentionDays days.',
            '最近 $_retentionDays 天没有 API 请求记录。',
          ),
        ),
      );
    }
    return Column(
      children: [
        for (final entry in _entries)
          ListTile(
            dense: true,
            leading: SizedBox(
              width: 80,
              child: Chip(
                visualDensity: VisualDensity.compact,
                label: Text(entry.method),
                padding: EdgeInsets.zero,
              ),
            ),
            title: SelectableText(
              entry.routeTemplate,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
            subtitle: Text(
              '${context.tr('Status', '状态')} ${entry.statusCode} · ${entry.createdAt}',
            ),
            trailing: Icon(
              entry.statusCode < 400
                  ? Icons.check_circle_outline
                  : Icons.error_outline,
              color: entry.statusCode < 400 ? Colors.green : Colors.deepOrange,
            ),
          ),
        if (_moreError != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              context.tr('Could not load more activity.', '无法加载更多活动。'),
            ),
          ),
        if (_nextCursor != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: OutlinedButton.icon(
              onPressed: _loadingMore ? null : _loadMore,
              icon: _loadingMore
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.expand_more),
              label: Text(context.tr('Load older requests', '加载更早请求')),
            ),
          ),
      ],
    );
  }

  Future<void> _load() async {
    final workspaceId = widget.workspaceId;
    if (workspaceId == null || !mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await ref
          .read(apiTokenUsageRepositoryProvider)
          .load(workspaceId: workspaceId, tokenId: widget.tokenId);
      if (!mounted) return;
      setState(() {
        _entries = page.entries;
        _nextCursor = page.nextCursor;
        _retentionDays = page.retentionDays;
        _loading = false;
      });
    } on Exception catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    final workspaceId = widget.workspaceId;
    final cursor = _nextCursor;
    if (workspaceId == null || cursor == null) return;
    setState(() {
      _loadingMore = true;
      _moreError = null;
    });
    try {
      final page = await ref
          .read(apiTokenUsageRepositoryProvider)
          .load(
            workspaceId: workspaceId,
            tokenId: widget.tokenId,
            cursor: cursor,
          );
      if (!mounted) return;
      setState(() {
        _entries = [..._entries, ...page.entries];
        _nextCursor = page.nextCursor;
        _loadingMore = false;
      });
    } on Exception catch (error) {
      if (!mounted) return;
      setState(() {
        _moreError = error;
        _loadingMore = false;
      });
    }
  }
}

class _TokenInput {
  const _TokenInput(this.name, this.scopes, this.expiresAt);
  final String name;
  final List<String> scopes;
  final DateTime? expiresAt;
}

class _CreateTokenDialog extends StatefulWidget {
  const _CreateTokenDialog();

  @override
  State<_CreateTokenDialog> createState() => _CreateTokenDialogState();
}

class _CreateTokenDialogState extends State<_CreateTokenDialog> {
  final _name = TextEditingController();
  bool _read = true;
  bool _write = false;
  DateTime? _expiresAt;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(context.tr('Create API token', '创建 API 令牌')),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _name,
          decoration: InputDecoration(
            labelText: context.tr('Token name', '令牌名称'),
          ),
        ),
        CheckboxListTile(
          value: _read,
          onChanged: (value) => setState(() => _read = value ?? false),
          title: Text(context.tr('Sites: read', '站点：读取')),
        ),
        CheckboxListTile(
          value: _write,
          onChanged: (value) => setState(() => _write = value ?? false),
          title: Text(context.tr('Sites: write', '站点：写入')),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(context.tr('Expiration', '到期时间')),
          subtitle: Text(
            _expiresAt == null
                ? context.tr('Never expires', '永不过期')
                : _dateLabel(_expiresAt!),
          ),
          trailing: Wrap(
            spacing: 0,
            children: [
              if (_expiresAt != null)
                IconButton(
                  tooltip: context.tr('Clear expiration', '清除到期时间'),
                  onPressed: () => setState(() => _expiresAt = null),
                  icon: const Icon(Icons.clear),
                ),
              IconButton(
                tooltip: context.tr('Choose expiration', '选择到期时间'),
                onPressed: _chooseExpiration,
                icon: const Icon(Icons.calendar_month_outlined),
              ),
            ],
          ),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.tr('Cancel', '取消')),
      ),
      FilledButton(
        onPressed: () {
          if (_name.text.trim().isEmpty || (!_read && !_write)) return;
          Navigator.pop(
            context,
            _TokenInput(_name.text.trim(), [
              if (_read) 'sites:read',
              if (_write) 'sites:write',
            ], _expiresAt),
          );
        },
        child: Text(context.tr('Create', '创建')),
      ),
    ],
  );

  Future<void> _chooseExpiration() async {
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: _expiresAt ?? now.add(const Duration(days: 90)),
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 10, now.month, now.day),
    );
    if (selected != null && mounted) {
      setState(() {
        _expiresAt = DateTime(
          selected.year,
          selected.month,
          selected.day,
          23,
          59,
          59,
        );
      });
    }
  }

  String _dateLabel(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}
