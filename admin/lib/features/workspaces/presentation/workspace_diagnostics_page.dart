import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_i18n.dart';
import '../../../core/network/seeray_api.dart';
import '../../../shared/presentation/app_back_button.dart';
import '../../../shared/presentation/page_help_button.dart';
import '../../auth/application/auth_controller.dart';

class WorkspaceDiagnosticsPage extends ConsumerStatefulWidget {
  const WorkspaceDiagnosticsPage({required this.workspaceId, super.key});

  final String workspaceId;

  @override
  ConsumerState<WorkspaceDiagnosticsPage> createState() =>
      _WorkspaceDiagnosticsPageState();
}

class _WorkspaceDiagnosticsPageState
    extends ConsumerState<WorkspaceDiagnosticsPage> {
  Map<String, dynamic>? _report;
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
      final data = await ref
          .read(apiProvider)
          .request(
            'GET',
            '/api/v1/workspaces/${widget.workspaceId}/diagnostics',
          );
      if (data is! Map) {
        throw const FormatException('Invalid diagnostics response');
      }
      if (!mounted) return;
      setState(() {
        _report = Map<String, dynamic>.from(data);
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error is ApiFailure ? error.message : '$error';
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: const AppBackButton(fallback: '/workspaces'),
      title: Text(context.tr('System diagnostics', '系统诊断')),
      actions: [
        const PageHelpButton(
          englishTitle: 'System diagnostics',
          chineseTitle: '系统诊断',
          englishBody:
              'These read-only checks help workspace owners and admins find configuration problems that can prevent tracking or reporting. They do not inspect event contents or expose secrets.',
          chineseBody: '这些只读检查帮助工作区所有者和管理员发现可能阻止采集或报表的配置问题，不读取事件内容，也不会暴露密钥。',
        ),
        const LanguageMenu(),
        IconButton(
          tooltip: context.tr('Refresh', '刷新'),
          onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(onRefresh: _load, child: _body(context)),
  );

  Widget _body(BuildContext context) {
    if (_error != null) {
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.error_outline, color: Colors.red),
              title: Text(_error!),
              trailing: TextButton(
                onPressed: _load,
                child: Text(context.tr('Retry', '重试')),
              ),
            ),
          ),
        ],
      );
    }
    final report = _report ?? const <String, dynamic>{};
    final checks =
        (report['checks'] as List?)
            ?.whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList(growable: false) ??
        const <Map<String, dynamic>>[];
    final overall = report['overallStatus'] as String? ?? 'error';
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _summaryCard(context, overall, report['checkedAt']),
        const SizedBox(height: 16),
        Text(
          context.tr('Checks and recommended actions', '检查项与建议操作'),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        for (final check in checks) ...[
          _checkCard(context, check),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  Widget _summaryCard(BuildContext context, String status, Object? checkedAt) {
    final color = _statusColor(context, status);
    final icon = status == 'pass'
        ? Icons.check_circle_outline
        : status == 'warning'
        ? Icons.warning_amber_outlined
        : Icons.error_outline;
    final parsed = checkedAt is String
        ? DateTime.tryParse(checkedAt)?.toLocal()
        : null;
    final time = parsed == null
        ? ''
        : context.tr(
            'Checked ${parsed.year}-${parsed.month.toString().padLeft(2, '0')}-${parsed.day.toString().padLeft(2, '0')} ${parsed.hour.toString().padLeft(2, '0')}:${parsed.minute.toString().padLeft(2, '0')}',
            '检查于 ${parsed.year}-${parsed.month.toString().padLeft(2, '0')}-${parsed.day.toString().padLeft(2, '0')} ${parsed.hour.toString().padLeft(2, '0')}:${parsed.minute.toString().padLeft(2, '0')}',
          );
    return Card(
      color: color.withValues(alpha: 0.08),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: Icon(icon, color: color, size: 32),
        title: Text(
          _overallLabel(context, status),
          style: TextStyle(color: color, fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          context.tr(
            'Read-only checks for tracking, origins, retention, migrations and database connectivity. $time',
            '检查采集、来源、留存、迁移和数据库连通性，只读不读取事件内容。$time',
          ),
        ),
      ),
    );
  }

  Widget _checkCard(BuildContext context, Map<String, dynamic> check) {
    final status = check['status'] as String? ?? 'error';
    final color = _statusColor(context, status);
    final title = _checkTitle(context, check['key'] as String? ?? '');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_statusIcon(status), color: color),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Chip(
                  label: Text(_statusLabel(context, status)),
                  side: BorderSide(color: color.withValues(alpha: 0.5)),
                  labelStyle: TextStyle(color: color),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(check['detail'] as String? ?? ''),
            if (check['remediation'] is String &&
                (check['remediation'] as String).isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                context.tr(
                  'Recommended action: ${check['remediation']}',
                  '建议操作：${check['remediation']}',
                ),
                style: TextStyle(color: color, fontWeight: FontWeight.w600),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Color _statusColor(BuildContext context, String status) {
    final colors = Theme.of(context).colorScheme;
    return switch (status) {
      'pass' => Colors.green.shade700,
      'warning' => colors.tertiary,
      _ => colors.error,
    };
  }

  IconData _statusIcon(String status) => switch (status) {
    'pass' => Icons.check_circle_outline,
    'warning' => Icons.warning_amber_outlined,
    _ => Icons.error_outline,
  };

  String _overallLabel(BuildContext context, String status) => switch (status) {
    'pass' => context.tr('All checks passed', '全部检查通过'),
    'warning' => context.tr('Review recommended actions', '建议处理以下问题'),
    _ => context.tr('Action required', '需要处理问题'),
  };

  String _statusLabel(BuildContext context, String status) => switch (status) {
    'pass' => context.tr('Healthy', '正常'),
    'warning' => context.tr('Review', '需关注'),
    _ => context.tr('Action required', '需处理'),
  };

  String _checkTitle(BuildContext context, String key) => switch (key) {
    'database' => context.tr('Database connectivity', '数据库连通性'),
    'sites' => context.tr('Workspace sites', '工作区站点'),
    'tracking' => context.tr('Tracking availability', '采集可用性'),
    'origins' => context.tr('Allowed tracker origins', '允许的采集来源'),
    'retention' => context.tr('Retention policy', '留存策略'),
    'release' => context.tr('Release and migrations', '版本与迁移'),
    _ => key,
  };
}
