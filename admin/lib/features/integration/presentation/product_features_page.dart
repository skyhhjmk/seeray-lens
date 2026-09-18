import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_i18n.dart';
import '../../../core/network/seeray_api.dart';
import '../../auth/application/auth_controller.dart';
import '../../analytics/application/analytics_segment.dart';
import '../application/experiment_sample_size.dart';
import '../application/tag_manager_preview.dart';

enum ProductFeatureMode { funnels, experiments, tagManager }

class ProductFeaturesPage extends ConsumerStatefulWidget {
  const ProductFeaturesPage({
    required this.siteId,
    required this.trackingId,
    required this.trackerUrl,
    required this.mode,
    this.requireConsent = false,
    super.key,
  });

  final String siteId;
  final String trackingId;
  final String trackerUrl;
  final ProductFeatureMode mode;
  final bool requireConsent;

  @override
  ConsumerState<ProductFeaturesPage> createState() =>
      _ProductFeaturesPageState();
}

class _ProductFeaturesPageState extends ConsumerState<ProductFeaturesPage> {
  List<Map<String, dynamic>> _items = const [];
  final Map<String, int> _draftVersions = {};
  bool _loading = true;
  String? _error;
  String? _notice;

  String get _path => switch (widget.mode) {
    ProductFeatureMode.funnels => '/api/v1/sites/${widget.siteId}/funnels',
    ProductFeatureMode.experiments =>
      '/api/v1/sites/${widget.siteId}/experiments',
    ProductFeatureMode.tagManager =>
      '/api/v1/sites/${widget.siteId}/tag-manager/containers',
  };

  String get _title => switch (widget.mode) {
    ProductFeatureMode.funnels => context.tr('Funnels', '漏斗'),
    ProductFeatureMode.experiments => context.tr('A/B tests', 'A/B 测试'),
    ProductFeatureMode.tagManager => context.tr('Tag Manager', 'Tag Manager'),
  };

  String get _consentAttribute =>
      widget.requireConsent ? ' data-require-consent="true"' : '';

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_load);
  }

  @override
  void didUpdateWidget(covariant ProductFeaturesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.siteId != widget.siteId || oldWidget.mode != widget.mode) {
      _draftVersions.clear();
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await ref.read(apiProvider).request('GET', _path) as List;
      if (!mounted) return;
      setState(() {
        _items = data
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

  Future<void> _create() async {
    if (widget.mode == ProductFeatureMode.experiments) {
      ref.invalidate(analyticsSegmentOptionsProvider(widget.siteId));
    }
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => widget.mode == ProductFeatureMode.tagManager
          ? const _ContainerEditorDialog()
          : _FeatureEditorDialog(
              mode: widget.mode,
              siteId: widget.siteId,
              availableAllocationGroups: _availableAllocationGroups,
            ),
    );
    if (result == null) return;
    await _run(() async {
      await ref.read(apiProvider).request('POST', _path, body: result);
      await _load();
    });
  }

  Future<void> _edit(Map<String, dynamic> item) async {
    final id = item['id'] as String?;
    if (id == null) return;
    if (widget.mode == ProductFeatureMode.tagManager) {
      final result = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => _ContainerEditorDialog(initial: item),
      );
      if (result == null) return;
      await _run(() async {
        await ref.read(apiProvider).request('PUT', '$_path/$id', body: result);
        await _load();
      });
      return;
    }
    if (widget.mode == ProductFeatureMode.experiments) {
      ref.invalidate(analyticsSegmentOptionsProvider(widget.siteId));
    }
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _FeatureEditorDialog(
        mode: widget.mode,
        siteId: widget.siteId,
        initial: item,
        availableAllocationGroups: _availableAllocationGroups,
      ),
    );
    if (result == null) return;
    await _run(() async {
      await ref.read(apiProvider).request('PUT', '$_path/$id', body: result);
      await _load();
    });
  }

  List<String> get _availableAllocationGroups =>
      _items
          .map((item) => item['allocationGroup'] as String?)
          .whereType<String>()
          .where((group) => group.isNotEmpty)
          .toSet()
          .toList()
        ..sort();

  String _experimentStatusLabel(String status) => switch (status) {
    'draft' => context.tr('Draft', '草稿'),
    'running' => context.tr('Running', '运行中'),
    'paused' => context.tr('Paused', '已暂停'),
    'completed' => context.tr('Completed', '已完成'),
    'archived' => context.tr('Archived', '已归档'),
    _ => status,
  };

  List<String> _experimentNextStatuses(String status) => switch (status) {
    'draft' => const ['running', 'archived'],
    'running' => const ['paused', 'completed'],
    'paused' => const ['running', 'completed', 'archived'],
    'completed' => const ['archived'],
    _ => const [],
  };

  String _experimentStatusAction(String nextStatus) => switch (nextStatus) {
    'running' => context.tr('Start', '开始'),
    'paused' => context.tr('Pause', '暂停'),
    'completed' => context.tr('Complete', '完成'),
    'archived' => context.tr('Archive', '归档'),
    _ => nextStatus,
  };

  String _experimentStatusActionZh(String nextStatus) => switch (nextStatus) {
    'running' => '开始',
    'paused' => '暂停',
    'completed' => '完成',
    'archived' => '归档',
    _ => nextStatus,
  };

  String _experimentStatusConfirmation(
    String nextStatus,
  ) => switch (nextStatus) {
    'running' =>
      'New eligible visitors will be assigned and exposed to this experiment.',
    'paused' =>
      'No new visitors will be assigned; existing reports remain available.',
    'completed' =>
      'New exposure stops and the experiment remains available for reporting.',
    'archived' =>
      'The experiment becomes read-only. You can delete it after archiving.',
    _ => '',
  };

  String _experimentStatusConfirmationZh(String nextStatus) =>
      switch (nextStatus) {
        'running' => '符合条件的新访客将开始进入该实验并记录曝光。',
        'paused' => '不再分配新访客；已有报告仍可查看。',
        'completed' => '停止新增曝光，实验仍保留供报告查看。',
        'archived' => '实验将转为只读；归档后才可删除。',
        _ => '',
      };

  Future<void> _changeExperimentStatus(
    Map<String, dynamic> item,
    String nextStatus,
  ) async {
    final id = item['id'] as String?;
    if (id == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          context.tr(
            '${_experimentStatusAction(nextStatus)} “${item['name'] ?? ''}”?',
            '要${_experimentStatusActionZh(nextStatus)}“${item['name'] ?? ''}”吗？',
          ),
        ),
        content: Text(
          context.tr(
            _experimentStatusConfirmation(nextStatus),
            _experimentStatusConfirmationZh(nextStatus),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.tr('Cancel', '取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(_experimentStatusAction(nextStatus)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _run(() async {
      await ref
          .read(apiProvider)
          .request(
            'PUT',
            '$_path/$id',
            body: {
              'name': item['name'],
              'variants': item['variants'],
              'targeting': item['targeting'],
              'allocationGroup': item['allocationGroup'],
              'status': nextStatus,
              'enabled': nextStatus == 'running',
            },
          );
      await _load();
    });
  }

  Future<void> _delete(Map<String, dynamic> item) async {
    final id = item['id'] as String?;
    if (id == null) return;
    final name = item['name'] as String? ?? id;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.tr('Delete $name?', '删除“$name”？')),
        content: Text(
          context.tr(
            'Reports and future tracking for this definition will no longer be available.',
            '删除后将无法继续查看该定义的报告，也不会再用于后续追踪。',
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
    await _run(() async {
      await ref.read(apiProvider).request('DELETE', '$_path/$id');
      await _load();
    });
  }

  Future<void> _draft(String id) async {
    List<dynamic>? initialTags;
    try {
      final versions =
          await ref.read(apiProvider).request('GET', '$_path/$id/versions')
              as List;
      if (versions.isNotEmpty) {
        final latest = versions.whereType<Map>().first;
        if (latest['tags'] is List) initialTags = latest['tags'] as List;
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_message(error))));
      return;
    }
    if (!mounted) return;
    final result = await showDialog<List<dynamic>>(
      context: context,
      builder: (context) => _TagDraftDialog(
        initialTags: initialTags,
        onStartLivePreview: (tags, executeCustomCode) async {
          final preview =
              await ref
                      .read(apiProvider)
                      .request(
                        'POST',
                        '$_path/$id/preview-sessions',
                        body: {
                          'tags': tags,
                          'executeCustomCode': executeCustomCode,
                        },
                      )
                  as Map;
          final sessionId = preview['sessionId'] as String?;
          final token = preview['token'] as String?;
          final expiresAt = preview['expiresAt'] as String?;
          if (sessionId == null || token == null || expiresAt == null) {
            throw StateError('The preview session response is incomplete.');
          }
          if (!context.mounted) return;
          await showDialog<void>(
            context: context,
            barrierDismissible: false,
            builder: (context) => _TagManagerLivePreviewDialog(
              siteId: widget.siteId,
              containerId: id,
              trackingId: widget.trackingId,
              trackerUrl: widget.trackerUrl,
              requireConsent: widget.requireConsent,
              sessionId: sessionId,
              token: token,
              expiresAt: expiresAt,
            ),
          );
        },
      ),
    );
    if (result == null) return;
    await _run(() async {
      final data =
          await ref
                  .read(apiProvider)
                  .request('POST', '$_path/$id/versions', body: result)
              as Map;
      _draftVersions[id] = (data['version'] as num).toInt();
      if (mounted) setState(() {});
    });
  }

  Future<void> _publish(String id) async {
    final version = _draftVersions[id];
    if (version == null) return;
    await _publishVersion(id, version);
  }

  Future<void> _publishVersion(String id, int version) async {
    await _requestProductionRelease(id, version);
  }

  Future<void> _requestProductionRelease(String id, int version) async {
    final requestNote = await showDialog<String>(
      context: context,
      builder: (context) => const _ProductionRequestNoteDialog(),
    );
    if (requestNote == null || requestNote.trim().isEmpty) return;
    await _run(() async {
      await ref
          .read(apiProvider)
          .request(
            'POST',
            '$_path/$id/production-requests',
            body: {'version': version, 'requestNote': requestNote.trim()},
          );
      _draftVersions.remove(id);
      await _load();
      if (!mounted) return;
      setState(
        () => _notice = context.tr(
          'Production review requested. A different workspace admin must approve it.',
          '已提交生产发布审核，需要另一位工作区管理员批准。',
        ),
      );
    });
  }

  Future<void> _productionApprovals(String id) async {
    Future<List<Map<String, dynamic>>> loadRequests() async {
      final data =
          await ref
                  .read(apiProvider)
                  .request('GET', '$_path/$id/production-requests')
              as List;
      return data
          .whereType<Map>()
          .map((request) => Map<String, dynamic>.from(request))
          .toList(growable: false);
    }

    await _run(() async {
      final initial = await loadRequests();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => _ProductionApprovalsDialog(
          requests: initial,
          onAction: (requestId, action, note) async {
            await ref
                .read(apiProvider)
                .request(
                  'POST',
                  '$_path/$id/production-requests/$requestId/$action',
                  body: action == 'cancel' ? null : {'reviewNote': note},
                );
            return loadRequests();
          },
        ),
      );
      if (mounted) await _load();
    });
  }

  Future<void> _versions(String id) async {
    await _run(() async {
      final data =
          await ref.read(apiProvider).request('GET', '$_path/$id/versions')
              as List;
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => _VersionsDialog(
          versions: data
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList(growable: false),
          onPublish: (version) async {
            Navigator.of(context).pop();
            await _publishVersion(id, version);
          },
        ),
      );
    });
  }

  Future<void> _deployEnvironment(
    String id,
    Map<String, dynamic> container,
  ) async {
    await _run(() async {
      final data =
          await ref.read(apiProvider).request('GET', '$_path/$id/versions')
              as List;
      final versions = data
          .whereType<Map>()
          .map((entry) => Map<String, dynamic>.from(entry))
          .toList(growable: false);
      final releases = Map<String, dynamic>.from(
        (container['environmentVersions'] as Map?) ?? const {},
      );
      var selectedEnvironment = 'staging';
      var selectedVersion = versions.isEmpty
          ? null
          : (versions.first['version'] as num).toInt();
      if (!mounted) return;
      final selection = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (innerContext, setDialogState) => AlertDialog(
            title: Text(context.tr('Deploy a version', '部署版本')),
            content: SizedBox(
              width: 440,
              child: versions.isEmpty
                  ? Text(context.tr('Create a version first.', '请先创建一个版本。'))
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        DropdownButtonFormField<String>(
                          initialValue: selectedEnvironment,
                          decoration: InputDecoration(
                            labelText: context.tr('Environment', '环境'),
                          ),
                          items: [
                            for (final environment in const [
                              'development',
                              'staging',
                              'production',
                            ])
                              DropdownMenuItem(
                                value: environment,
                                child: Text(_environmentLabel(environment)),
                              ),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              setDialogState(() => selectedEnvironment = value);
                            }
                          },
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<int>(
                          initialValue: selectedVersion,
                          decoration: InputDecoration(
                            labelText: context.tr('Version', '版本'),
                          ),
                          items: [
                            for (final version in versions)
                              DropdownMenuItem(
                                value: (version['version'] as num).toInt(),
                                child: Text('v${version['version']}'),
                              ),
                          ],
                          onChanged: (value) =>
                              setDialogState(() => selectedVersion = value),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          context.tr(
                            'Current release: ${releases[selectedEnvironment] == null ? 'none' : 'v${releases[selectedEnvironment]}'}',
                            '当前环境版本：${releases[selectedEnvironment] == null ? '无' : 'v${releases[selectedEnvironment]}'}',
                          ),
                        ),
                      ],
                    ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(innerContext),
                child: Text(context.tr('Cancel', '取消')),
              ),
              FilledButton(
                onPressed: selectedVersion == null
                    ? null
                    : () => Navigator.pop(innerContext, {
                        'environment': selectedEnvironment,
                        'version': selectedVersion,
                      }),
                child: Text(
                  context.tr(
                    selectedEnvironment == 'production'
                        ? 'Request production review'
                        : 'Deploy',
                    selectedEnvironment == 'production' ? '申请生产审核' : '部署',
                  ),
                ),
              ),
            ],
          ),
        ),
      );
      if (selection == null) return;
      if (selection['environment'] == 'production') {
        await _requestProductionRelease(id, selection['version'] as int);
        return;
      }
      await ref
          .read(apiProvider)
          .request(
            'POST',
            '$_path/$id/versions/${selection['version']}/environments/${selection['environment']}/publish',
          );
      await _load();
    });
  }

  Future<void> _templates() async {
    await showDialog<void>(
      context: context,
      builder: (_) => _TagTemplateLibraryDialog(
        siteId: widget.siteId,
        containers: _items,
        onUse: _useTemplate,
      ),
    );
  }

  Future<void> _useTemplate(
    String containerId,
    List<dynamic> templateTags,
  ) async {
    await _run(() async {
      final data =
          await ref
                  .read(apiProvider)
                  .request('GET', '$_path/$containerId/versions')
              as List;
      final versions = data.whereType<Map>().toList(growable: false);
      final selectedVersion = _draftVersions[containerId];
      final baseVersion = versions.cast<Map?>().firstWhere(
        (item) => item?['version'] == selectedVersion,
        orElse: () => versions.isEmpty ? null : versions.first,
      );
      final baseTags = baseVersion?['tags'] is List
          ? List<dynamic>.from(baseVersion?['tags'] as List)
          : <dynamic>[];
      final response =
          await ref
                  .read(apiProvider)
                  .request(
                    'POST',
                    '$_path/$containerId/versions',
                    body: [...baseTags, ...templateTags],
                  )
              as Map;
      _draftVersions[containerId] = (response['version'] as num).toInt();
      await _load();
    });
  }

  String _environmentLabel(String environment) => switch (environment) {
    'development' => context.tr('Development', '开发'),
    'staging' => context.tr('Staging', '预发布'),
    'production' => context.tr('Production', '生产'),
    _ => environment,
  };

  Future<void> _report(String id) async {
    final now = DateTime.now();
    final from = _date(now.subtract(const Duration(days: 29)));
    final to = _date(now);
    final path = '$_path/$id/report?from=$from&to=$to';
    await _run(() async {
      final data = await ref.read(apiProvider).request('GET', path) as Map;
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => _ReportDialog(mode: widget.mode, report: data),
      );
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_message(error))));
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      Row(
        children: [
          Expanded(
            child: Text(_title, style: Theme.of(context).textTheme.titleLarge),
          ),
          IconButton(
            tooltip: context.tr('Refresh', '刷新'),
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
          if (widget.mode == ProductFeatureMode.tagManager)
            OutlinedButton.icon(
              onPressed: _loading ? null : _templates,
              icon: const Icon(Icons.library_books_outlined),
              label: Text(context.tr('Templates', '模板库')),
            ),
          FilledButton.icon(
            onPressed: _loading ? null : _create,
            icon: const Icon(Icons.add),
            label: Text(context.tr('Create', '新建')),
          ),
        ],
      ),
      const SizedBox(height: 12),
      if (_error != null)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(_error!),
          ),
        ),
      if (_notice != null)
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.check_circle_outline),
                const SizedBox(width: 8),
                Expanded(child: Text(_notice!)),
                IconButton(
                  tooltip: context.tr('Dismiss', '关闭提示'),
                  onPressed: () => setState(() => _notice = null),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
        ),
      if (widget.mode == ProductFeatureMode.tagManager)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr('Install the published container', '安装已发布容器'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                SelectableText(
                  '<script src="${widget.trackerUrl}" data-site-id="${widget.trackingId}"$_consentAttribute data-tag-manager="true"></script>',
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
                const SizedBox(height: 8),
                Text(context.tr('Staging install snippet', '预发布环境安装代码')),
                SelectableText(
                  '<script src="${widget.trackerUrl}" data-site-id="${widget.trackingId}"$_consentAttribute data-tag-manager="true" data-tag-manager-environment="staging"></script>',
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
                const SizedBox(height: 8),
                Text(
                  context.tr(
                    'The tracker supports event tags, page-view tags, and custom HTML/JavaScript snippets. Published snippets run in the visitor\'s page, so only publish code you trust.',
                    '追踪器支持事件标签、页面浏览标签，以及自定义 HTML/JavaScript 代码段。已发布代码会在访客页面执行，请只发布可信代码。',
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  context.tr(
                    'Production releases require a second workspace administrator to review the change summary. Development and staging remain available for testing.',
                    '生产发布需要另一位工作区管理员审阅变更摘要；开发和预发布环境仍可直接用于测试。',
                  ),
                ),
              ],
            ),
          ),
        ),
      if (_loading)
        const Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: CircularProgressIndicator()),
        )
      else if (_items.isEmpty)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Text(context.tr('Nothing configured yet.', '还没有配置。')),
          ),
        )
      else
        ..._items.map(_card),
    ],
  );

  Widget _card(Map<String, dynamic> item) {
    final id = item['id'] as String? ?? '';
    final name = item['name'] as String? ?? id;
    final enabled = item['enabled'] as bool? ?? true;
    final experimentStatus =
        item['status'] as String? ?? (enabled ? 'running' : 'paused');
    final configurationLocked = item['configurationLocked'] as bool? ?? false;
    final allocationGroup = item['allocationGroup'] as String?;
    final variants = (item['variants'] as List?)?.join(', ');
    final steps = (item['steps'] as List?)?.length;
    final published = item['publishedVersion'];
    final releases = Map<String, dynamic>.from(
      (item['environmentVersions'] as Map?) ?? const {},
    );
    final draft = _draftVersions[id];
    return Card(
      child: ListTile(
        leading: Icon(switch (widget.mode) {
          ProductFeatureMode.funnels => Icons.filter_alt_outlined,
          ProductFeatureMode.experiments => Icons.science_outlined,
          ProductFeatureMode.tagManager => Icons.sell_outlined,
        }),
        title: Text(name),
        subtitle: widget.mode == ProductFeatureMode.experiments
            ? _experimentCardSubtitle(
                variants ?? '',
                experimentStatus,
                allocationGroup,
                configurationLocked,
              )
            : Text(switch (widget.mode) {
                ProductFeatureMode.funnels => context.tr(
                  '$steps ordered steps',
                  '$steps 个顺序步骤',
                ),
                ProductFeatureMode.experiments => '',
                ProductFeatureMode.tagManager => context.tr(
                  'Published version: ${published ?? "none"}\nDevelopment ${releases['development'] == null ? "—" : "v${releases['development']}"} · Staging ${releases['staging'] == null ? "—" : "v${releases['staging']}"} · Production ${releases['production'] == null ? "—" : "v${releases['production']}"}',
                  '已发布版本：${published ?? "无"}\n开发 ${releases['development'] == null ? "—" : "v${releases['development']}"} · 预发布 ${releases['staging'] == null ? "—" : "v${releases['staging']}"} · 生产 ${releases['production'] == null ? "—" : "v${releases['production']}"}',
                ),
              }),
        trailing: Wrap(
          spacing: 4,
          children: [
            if (widget.mode != ProductFeatureMode.tagManager)
              IconButton(
                tooltip: context.tr('Report', '报告'),
                onPressed: () => _report(id),
                icon: const Icon(Icons.bar_chart_outlined),
              ),
            if (widget.mode != ProductFeatureMode.experiments ||
                (!configurationLocked && experimentStatus != 'archived'))
              IconButton(
                tooltip: context.tr('Edit', '编辑'),
                onPressed: () => _edit(item),
                icon: const Icon(Icons.edit_outlined),
              ),
            if (widget.mode == ProductFeatureMode.experiments &&
                _experimentNextStatuses(experimentStatus).isNotEmpty)
              PopupMenuButton<String>(
                key: ValueKey('experiment-lifecycle-menu-$id'),
                tooltip: context.tr('Manage lifecycle', '管理实验状态'),
                icon: const Icon(Icons.tune),
                onSelected: (status) => _changeExperimentStatus(item, status),
                itemBuilder: (context) => [
                  for (final status in _experimentNextStatuses(
                    experimentStatus,
                  ))
                    PopupMenuItem(
                      value: status,
                      child: Text(_experimentStatusAction(status)),
                    ),
                ],
              ),
            if (widget.mode == ProductFeatureMode.experiments &&
                experimentStatus == 'running')
              IconButton(
                tooltip: context.tr('Install snippet', '安装代码'),
                onPressed: () => _showExperimentSnippet(item),
                icon: const Icon(Icons.integration_instructions_outlined),
              ),
            if (widget.mode != ProductFeatureMode.experiments ||
                experimentStatus == 'archived')
              IconButton(
                tooltip: context.tr('Delete', '删除'),
                onPressed: () => _delete(item),
                icon: const Icon(Icons.delete_outline),
              ),
            if (widget.mode == ProductFeatureMode.tagManager) ...[
              IconButton(
                tooltip: context.tr('Versions', '版本'),
                onPressed: () => _versions(id),
                icon: const Icon(Icons.history),
              ),
              IconButton(
                tooltip: context.tr('Production approvals', '生产发布审核'),
                onPressed: () => _productionApprovals(id),
                icon: const Icon(Icons.fact_check_outlined),
              ),
              IconButton(
                tooltip: context.tr('Deploy version', '部署版本'),
                onPressed: () => _deployEnvironment(id, item),
                icon: const Icon(Icons.rocket_launch_outlined),
              ),
              IconButton(
                tooltip: context.tr('Edit tags', '编辑标签'),
                onPressed: () => _draft(id),
                icon: const Icon(Icons.edit_outlined),
              ),
              if (draft != null)
                IconButton(
                  tooltip: context.tr(
                    'Request production review for v$draft',
                    '申请审核并发布 v$draft',
                  ),
                  onPressed: () => _publish(id),
                  icon: const Icon(Icons.publish_outlined),
                ),
            ],
            if (widget.mode != ProductFeatureMode.experiments && !enabled)
              const Icon(Icons.pause_circle_outline),
          ],
        ),
      ),
    );
  }

  Widget _experimentCardSubtitle(
    String variants,
    String status,
    String? allocationGroup,
    bool configurationLocked,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(context.tr('Variants: $variants', '变体：$variants')),
      const SizedBox(height: 6),
      Wrap(
        spacing: 6,
        runSpacing: 4,
        children: [
          Chip(
            visualDensity: VisualDensity.compact,
            avatar: Icon(
              status == 'running'
                  ? Icons.play_circle_outline
                  : Icons.science_outlined,
              size: 16,
            ),
            label: Text(_experimentStatusLabel(status)),
          ),
          if (allocationGroup != null && allocationGroup.isNotEmpty)
            Chip(
              visualDensity: VisualDensity.compact,
              avatar: const Icon(Icons.layers_outlined, size: 16),
              label: Text(
                context.tr('Layer: $allocationGroup', '分层：$allocationGroup'),
              ),
            ),
          if (configurationLocked)
            Chip(
              visualDensity: VisualDensity.compact,
              avatar: const Icon(Icons.lock_outline, size: 16),
              label: Text(context.tr('Setup locked', '配置已锁定')),
            ),
        ],
      ),
      if (configurationLocked) ...[
        const SizedBox(height: 4),
        Text(
          context.tr(
            'Variants, audience, name, and allocation are locked after the first exposure. Create a new experiment to test a changed setup.',
            '首次曝光后，变体、受众、名称和分层配置均已锁定。如需测试新配置，请新建实验。',
          ),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    ],
  );

  Future<void> _showExperimentSnippet(Map<String, dynamic> item) async {
    final name = item['name'] as String? ?? '';
    final snippet =
        '<script src="${widget.trackerUrl}" data-site-id="${widget.trackingId}"$_consentAttribute data-experiments="true"></script>\n'
        '<script>\n'
        '  SeeRay.ready().then(() => {\n'
        "    const variant = SeeRay.assignExperiment('$name');\n"
        '    // undefined means the visitor is outside this experiment\'s target.\n'
        '    if (variant) { /* Render the experience identified by variant. */ }\n'
        '  });\n'
        '</script>';
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.tr('Install A/B test', '安装 A/B 测试')),
        content: SizedBox(
          width: 620,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                context.tr(
                  'This snippet loads enabled variants and applies saved-segment, page and device targeting. Segment eligibility uses recorded sessions in the selected lookback; unknown visitors remain outside until a matching session is recorded.',
                  '这段代码会读取已启用变体，并应用保存分群、页面和设备定向。分群资格按所选回溯期内已记录的会话判断；尚无匹配会话的访客不会进入实验。',
                ),
              ),
              const SizedBox(height: 12),
              SelectableText(
                snippet,
                style: const TextStyle(fontFamily: 'monospace'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.tr('Close', '关闭')),
          ),
        ],
      ),
    );
  }

  String _message(Object error) =>
      error is ApiFailure ? error.message : '$error';

  String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
}

class _FeatureEditorDialog extends ConsumerStatefulWidget {
  const _FeatureEditorDialog({
    required this.mode,
    required this.siteId,
    this.initial,
    this.availableAllocationGroups = const [],
  });

  final ProductFeatureMode mode;
  final String siteId;
  final Map<String, dynamic>? initial;
  final List<String> availableAllocationGroups;

  @override
  ConsumerState<_FeatureEditorDialog> createState() =>
      _FeatureEditorDialogState();
}

class _FeatureEditorDialogState extends ConsumerState<_FeatureEditorDialog> {
  late final TextEditingController _name;
  late final TextEditingController _allocationGroup;
  late bool _enabled;
  late String _status;
  bool _useAllocationGroup = false;
  final _steps = <_FunnelStepForm>[];
  final _variants = <TextEditingController>[];
  final _targetPathPrefixes = <TextEditingController>[];
  final _targetDeviceTypes = <String>{};
  String? _targetSegmentId;
  int _segmentLookbackDays = 30;
  double _baselineConversionRate = 0.05;
  double _minimumDetectableLift = 0.20;
  int _confidenceLevel = 95;
  int _statisticalPower = 80;
  String? _error;

  bool get _editing => widget.initial != null;

  String _editorStatusLabel(String status) => switch (status) {
    'draft' => context.tr('Draft', '草稿'),
    'running' => context.tr('Running', '运行中'),
    'paused' => context.tr('Paused', '已暂停'),
    'completed' => context.tr('Completed', '已完成'),
    'archived' => context.tr('Archived', '已归档'),
    _ => status,
  };

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _name = TextEditingController(text: initial?['name'] as String? ?? '');
    _enabled = initial?['enabled'] as bool? ?? true;
    _status =
        initial?['status'] as String? ??
        (initial == null ? 'draft' : (_enabled ? 'running' : 'paused'));
    final allocationGroup = initial?['allocationGroup'] as String?;
    _allocationGroup = TextEditingController(text: allocationGroup ?? '');
    _useAllocationGroup = allocationGroup?.isNotEmpty ?? false;
    if (widget.mode == ProductFeatureMode.funnels) {
      final rawSteps = initial?['steps'];
      if (rawSteps is List) {
        _steps.addAll(rawSteps.whereType<Map>().map(_FunnelStepForm.fromJson));
      }
      if (_steps.isEmpty) _steps.add(_FunnelStepForm());
    } else {
      final rawVariants = initial?['variants'];
      if (rawVariants is List) {
        for (final variant in rawVariants.whereType<String>()) {
          _variants.add(TextEditingController(text: variant));
        }
      }
      final rawTargeting = initial?['targeting'];
      if (rawTargeting is Map) {
        final rawPaths = rawTargeting['pathPrefixes'];
        if (rawPaths is List) {
          for (final path in rawPaths.whereType<String>()) {
            _targetPathPrefixes.add(TextEditingController(text: path));
          }
        }
        final rawDevices = rawTargeting['deviceTypes'];
        if (rawDevices is List) {
          _targetDeviceTypes.addAll(rawDevices.whereType<String>());
        }
        _targetSegmentId = rawTargeting['segmentId'] as String?;
        final lookbackDays = rawTargeting['segmentLookbackDays'];
        if (lookbackDays is int && const {7, 30, 90}.contains(lookbackDays)) {
          _segmentLookbackDays = lookbackDays;
        }
      }
      if (_variants.isEmpty) {
        _variants.add(TextEditingController(text: 'control'));
        _variants.add(TextEditingController(text: 'new_copy'));
      }
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _allocationGroup.dispose();
    for (final step in _steps) {
      step.dispose();
    }
    for (final variant in _variants) {
      variant.dispose();
    }
    for (final path in _targetPathPrefixes) {
      path.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      context.tr(
        '${_editing ? 'Edit' : 'Create'} ${_label(context)}',
        '${_editing ? '编辑' : '新建'}${_label(context)}',
      ),
    ),
    content: SizedBox(
      width: 620,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 620),
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
              if (widget.mode == ProductFeatureMode.funnels)
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: Text(context.tr('Enabled', '启用')),
                  subtitle: Text(
                    context.tr(
                      'Disabled definitions remain available for reporting but are not used for new tracking.',
                      '停用后仍保留历史报告，但不会用于新的追踪。',
                    ),
                  ),
                  value: _enabled,
                  onChanged: (value) => setState(() => _enabled = value),
                )
              else
                _buildExperimentLifecycle(context),
              const Divider(),
              if (widget.mode == ProductFeatureMode.funnels)
                _buildFunnelEditor(context)
              else
                _buildExperimentEditor(context),
              if (_error != null) ...[
                const SizedBox(height: 12),
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

  Widget _buildFunnelEditor(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        context.tr('Ordered steps', '顺序步骤'),
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 4),
      Text(
        context.tr(
          'A session advances only when it matches the next step. Reorder steps to change the journey.',
          '会话只有匹配下一个步骤才会前进。调整顺序即可改变用户路径。',
        ),
      ),
      const SizedBox(height: 12),
      for (var index = 0; index < _steps.length; index++) ...[
        _FunnelStepCard(
          index: index,
          form: _steps[index],
          canRemove: _steps.length > 2,
          onChanged: () => setState(() => _error = null),
          onRemove: () {
            setState(() {
              final removed = _steps.removeAt(index);
              removed.dispose();
            });
          },
          onMoveUp: index == 0
              ? null
              : () => setState(() {
                  final step = _steps.removeAt(index);
                  _steps.insert(index - 1, step);
                }),
          onMoveDown: index == _steps.length - 1
              ? null
              : () => setState(() {
                  final step = _steps.removeAt(index);
                  _steps.insert(index + 1, step);
                }),
        ),
        if (index != _steps.length - 1) const SizedBox(height: 10),
      ],
      const SizedBox(height: 10),
      OutlinedButton.icon(
        onPressed: () => setState(() {
          _steps.add(_FunnelStepForm());
          _error = null;
        }),
        icon: const Icon(Icons.add),
        label: Text(context.tr('Add step', '添加步骤')),
      ),
    ],
  );

  Widget _buildExperimentLifecycle(BuildContext context) => Card(
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.route_outlined,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                context.tr('Experiment lifecycle', '实验生命周期'),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const Spacer(),
              Chip(label: Text(_editorStatusLabel(_status))),
            ],
          ),
          Text(
            context.tr(
              'New experiments start as drafts. Use the lifecycle menu on the experiment card to start, pause, complete, or archive it. Completed and archived reports remain available.',
              '新实验以草稿创建。请在实验卡片的状态菜单中开始、暂停、完成或归档。完成和归档后仍可查看报告。',
            ),
          ),
        ],
      ),
    ),
  );

  Widget _buildTrafficAllocation(BuildContext context) => Card(
    key: const ValueKey('experiment-traffic-allocation'),
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.tr('Traffic allocation', '流量分配'),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          Text(
            context.tr(
              'Keep this experiment independent, or place it in a shared layer so each visitor can enter at most one running experiment in that layer.',
              '可独立运行，也可加入共享分层；同一访客在一个分层中最多进入一个运行中的实验。',
            ),
          ),
          SwitchListTile.adaptive(
            key: const ValueKey('experiment-use-allocation-group'),
            contentPadding: EdgeInsets.zero,
            title: Text(context.tr('Share a traffic layer', '加入共享流量分层')),
            value: _useAllocationGroup,
            onChanged: (value) => setState(() {
              _useAllocationGroup = value;
              _error = null;
            }),
          ),
          if (_useAllocationGroup) ...[
            TextField(
              key: const ValueKey('experiment-allocation-group'),
              controller: _allocationGroup,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9_-]')),
              ],
              decoration: InputDecoration(
                labelText: context.tr('Layer name', '分层名称'),
                hintText: 'checkout',
                helperText: context.tr(
                  'Use a short reusable ID; letters, numbers, _ and - only.',
                  '使用简短且可复用的标识；仅支持字母、数字、_ 和 -。',
                ),
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() => _error = null),
            ),
            if (widget.availableAllocationGroups
                .where((group) => group != _allocationGroup.text.trim())
                .isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                context.tr('Existing layers on this site', '本站已有分层'),
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final group in widget.availableAllocationGroups.where(
                    (group) => group != _allocationGroup.text.trim(),
                  ))
                    ActionChip(
                      label: Text(group),
                      onPressed: () => setState(() {
                        _allocationGroup.text = group;
                        _error = null;
                      }),
                    ),
                ],
              ),
            ],
          ],
        ],
      ),
    ),
  );

  Widget _buildExperimentEditor(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _buildTrafficAllocation(context),
      const SizedBox(height: 12),
      Text(
        context.tr('Variants', '变体'),
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 4),
      Text(
        context.tr(
          'The first variant is the control used for lift and significance comparisons.',
          '第一个变体是对照组，用于提升比例和显著性比较。',
        ),
      ),
      const SizedBox(height: 12),
      for (var index = 0; index < _variants.length; index++)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              CircleAvatar(radius: 14, child: Text('${index + 1}')),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _variants[index],
                  onChanged: (_) => setState(() => _error = null),
                  decoration: InputDecoration(
                    labelText: index == 0
                        ? context.tr('Control variant', '对照变体')
                        : context.tr('Variant ${index + 1}', '变体 ${index + 1}'),
                  ),
                ),
              ),
              IconButton(
                tooltip: context.tr('Remove variant', '删除变体'),
                onPressed: _variants.length <= 2
                    ? null
                    : () => setState(() {
                        final removed = _variants.removeAt(index);
                        removed.dispose();
                      }),
                icon: const Icon(Icons.remove_circle_outline),
              ),
            ],
          ),
        ),
      OutlinedButton.icon(
        onPressed: () => setState(() {
          _variants.add(
            TextEditingController(text: 'variant_${_variants.length + 1}'),
          );
          _error = null;
        }),
        icon: const Icon(Icons.add),
        label: Text(context.tr('Add variant', '添加变体')),
      ),
      const SizedBox(height: 16),
      _buildExperimentSampleSizePlanner(context),
      const SizedBox(height: 12),
      const Divider(),
      const SizedBox(height: 8),
      Text(
        context.tr('Audience targeting', '受众定向'),
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 4),
      Text(
        context.tr(
          'Page paths and device types are ORed within their groups; configured groups are combined with AND. Saved-segment targeting additionally requires a previously recorded matching session within its lookback window.',
          '页面路径和设备类型各自在组内满足任意一项即可；已配置的条件组之间为 AND。保存分群还要求回溯期内存在匹配的已记录会话。',
        ),
      ),
      const SizedBox(height: 12),
      _buildSavedSegmentTargeting(context),
      const SizedBox(height: 12),
      for (var index = 0; index < _targetPathPrefixes.length; index++)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _targetPathPrefixes[index],
                  onChanged: (_) => setState(() => _error = null),
                  decoration: InputDecoration(
                    labelText: context.tr('Page path prefix', '页面路径前缀'),
                    hintText: '/pricing',
                  ),
                ),
              ),
              IconButton(
                tooltip: context.tr('Remove page filter', '移除页面条件'),
                onPressed: () => setState(() {
                  final removed = _targetPathPrefixes.removeAt(index);
                  removed.dispose();
                  _error = null;
                }),
                icon: const Icon(Icons.remove_circle_outline),
              ),
            ],
          ),
        ),
      OutlinedButton.icon(
        onPressed: _targetPathPrefixes.length >= 20
            ? null
            : () => setState(() {
                _targetPathPrefixes.add(TextEditingController());
                _error = null;
              }),
        icon: const Icon(Icons.add),
        label: Text(context.tr('Add page path', '添加页面路径')),
      ),
      const SizedBox(height: 12),
      Text(
        context.tr('Devices', '设备类型'),
        style: Theme.of(context).textTheme.labelLarge,
      ),
      Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          for (final device in const ['desktop', 'mobile', 'tablet', 'other'])
            FilterChip(
              label: Text(
                context.tr(_deviceLabel(device), _deviceLabelZh(device)),
              ),
              selected: _targetDeviceTypes.contains(device),
              onSelected: (selected) => setState(() {
                if (selected) {
                  _targetDeviceTypes.add(device);
                } else {
                  _targetDeviceTypes.remove(device);
                }
              }),
            ),
        ],
      ),
    ],
  );

  Widget _buildExperimentSampleSizePlanner(BuildContext context) {
    final estimate = estimateExperimentSampleSize(
      baselineConversionRate: _baselineConversionRate,
      relativeMinimumDetectableLift: _minimumDetectableLift,
      confidenceLevel: _confidenceLevel,
      power: _statisticalPower,
      variantCount: _variants.length,
    );
    return Card(
      key: const ValueKey('experiment-sample-size-planner'),
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              context.tr('Sample size estimate', '样本量预估'),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              context.tr(
                'Plan traffic before launch. Adjust the expected control rate and the smallest relative lift worth detecting.',
                '上线前规划流量：设置预期对照转化率，以及值得检测的最小相对提升幅度。',
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    context.tr('Expected control conversion', '预期对照组转化率'),
                  ),
                ),
                Text(
                  '${(_baselineConversionRate * 100).toStringAsFixed(1)}%',
                  key: const ValueKey('experiment-baseline-rate-value'),
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ],
            ),
            Slider(
              key: const ValueKey('experiment-baseline-rate'),
              value: _baselineConversionRate,
              min: 0.001,
              max: 0.49,
              divisions: 489,
              label: '${(_baselineConversionRate * 100).toStringAsFixed(1)}%',
              onChanged: (value) =>
                  setState(() => _baselineConversionRate = value),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    context.tr('Minimum detectable relative lift', '最小可检测相对提升'),
                  ),
                ),
                Text(
                  '+${(_minimumDetectableLift * 100).toStringAsFixed(0)}%',
                  key: const ValueKey('experiment-minimum-lift-value'),
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ],
            ),
            Slider(
              key: const ValueKey('experiment-minimum-lift'),
              value: _minimumDetectableLift,
              min: 0.05,
              max: 1,
              divisions: 19,
              label: '+${(_minimumDetectableLift * 100).toStringAsFixed(0)}%',
              onChanged: (value) =>
                  setState(() => _minimumDetectableLift = value),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    key: const ValueKey('experiment-confidence-level'),
                    initialValue: _confidenceLevel,
                    decoration: InputDecoration(
                      labelText: context.tr('Confidence', '置信水平'),
                      border: const OutlineInputBorder(),
                    ),
                    items: [
                      for (final value in const [90, 95, 99])
                        DropdownMenuItem(value: value, child: Text('$value%')),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _confidenceLevel = value);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    key: const ValueKey('experiment-statistical-power'),
                    initialValue: _statisticalPower,
                    decoration: InputDecoration(
                      labelText: context.tr('Statistical power', '统计功效'),
                      border: const OutlineInputBorder(),
                    ),
                    items: [
                      for (final value in const [80, 90])
                        DropdownMenuItem(value: value, child: Text('$value%')),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _statisticalPower = value);
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              key: const ValueKey('experiment-sample-size-result'),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.groups_2_outlined,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.tr(
                            '${_formatSampleCount(estimate.perVariant)} exposures needed per variant',
                            '每个变体约需 ${_formatSampleCount(estimate.perVariant)} 次曝光',
                          ),
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        Text(
                          context.tr(
                            'About ${_formatSampleCount(estimate.totalExposures)} exposures across ${_variants.length} variants',
                            '${_variants.length} 个变体合计约需 ${_formatSampleCount(estimate.totalExposures)} 次曝光',
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              context.tr(
                'Two-sided normal approximation with equal allocation. For 3+ variants the total is a traffic estimate only; it does not correct for multiple comparisons. Do not use this estimate alone as a stopping rule.',
                '按双侧正态近似、各组等比例分流计算。3 个及以上变体的总量仅为流量估算，未校正多重比较；不要仅凭该估算决定提前停止实验。',
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSavedSegmentTargeting(BuildContext context) => ref
      .watch(analyticsSegmentOptionsProvider(widget.siteId))
      .when(
        data: (segments) {
          final selectedExists =
              _targetSegmentId == null ||
              segments.any((segment) => segment.id == _targetSegmentId);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String?>(
                key: ValueKey(
                  'experiment-segment-${_targetSegmentId ?? 'all'}',
                ),
                initialValue: _targetSegmentId,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: context.tr('Saved audience segment', '保存的受众分群'),
                  border: const OutlineInputBorder(),
                ),
                items: [
                  DropdownMenuItem<String?>(
                    value: null,
                    child: Text(context.tr('All visitors', '所有访客')),
                  ),
                  if (!selectedExists)
                    DropdownMenuItem<String?>(
                      value: _targetSegmentId,
                      child: Text(
                        context.tr(
                          'Unavailable segment — choose another',
                          '分群不可用，请重新选择',
                        ),
                      ),
                    ),
                  for (final segment in segments)
                    DropdownMenuItem<String?>(
                      value: segment.id,
                      child: Text(
                        segment.name,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (value) => setState(() {
                  _targetSegmentId = value;
                  _error = null;
                }),
              ),
              if (segments.isEmpty && _targetSegmentId == null) ...[
                const SizedBox(height: 6),
                Text(
                  context.tr(
                    'Create and enable a segment in the Segments tab to target a saved audience.',
                    '如需按保存的受众定向，请先在“分群”页创建并启用一个分群。',
                  ),
                ),
              ],
              if (_targetSegmentId != null) ...[
                const SizedBox(height: 10),
                DropdownButtonFormField<int>(
                  key: const ValueKey('experiment-segment-lookback'),
                  initialValue: _segmentLookbackDays,
                  decoration: InputDecoration(
                    labelText: context.tr('Audience lookback', '受众回溯期'),
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    for (final days in const [7, 30, 90])
                      DropdownMenuItem<int>(
                        value: days,
                        child: Text(
                          context.tr('Last $days days', '最近 $days 天'),
                        ),
                      ),
                  ],
                  onChanged: (value) => setState(() {
                    if (value != null) _segmentLookbackDays = value;
                  }),
                ),
                const SizedBox(height: 6),
                Text(
                  context.tr(
                    'A visitor is eligible when at least one recorded session in this window matches the segment. New or unknown visitors are excluded until a matching session is recorded.',
                    '回溯窗口内至少有一个已记录会话符合该分群，访客才具备资格。新访客或尚未记录的访客暂不进入实验。',
                  ),
                ),
              ],
              if (!selectedExists) ...[
                const SizedBox(height: 6),
                Text(
                  context.tr(
                    'The selected segment is disabled or no longer available. Choose an enabled segment before saving.',
                    '所选分群已停用或不存在。请改选一个已启用的分群再保存。',
                  ),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          );
        },
        loading: () => const LinearProgressIndicator(),
        error: (error, stackTrace) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.tr(
                'Saved segments could not be loaded. Retry before changing audience targeting.',
                '无法加载保存的分群。更改受众定向前请重试。',
              ),
            ),
            TextButton.icon(
              onPressed: () => ref.invalidate(
                analyticsSegmentOptionsProvider(widget.siteId),
              ),
              icon: const Icon(Icons.refresh),
              label: Text(context.tr('Retry', '重试')),
            ),
          ],
        ),
      );

  String _deviceLabel(String device) => switch (device) {
    'desktop' => 'Desktop',
    'mobile' => 'Mobile',
    'tablet' => 'Tablet',
    _ => 'Other',
  };

  String _deviceLabelZh(String device) => switch (device) {
    'desktop' => '桌面设备',
    'mobile' => '手机',
    'tablet' => '平板',
    _ => '其他设备',
  };

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = context.tr('Name is required.', '名称不能为空。'));
      return;
    }
    final body = <String, dynamic>{'name': name, 'enabled': _enabled};
    if (widget.mode == ProductFeatureMode.funnels) {
      if (_steps.length < 2) {
        setState(
          () => _error = context.tr(
            'A funnel needs at least two steps.',
            '漏斗至少需要两个步骤。',
          ),
        );
        return;
      }
      final steps = <Map<String, dynamic>>[];
      for (var index = 0; index < _steps.length; index++) {
        final step = _steps[index].toJson();
        if (step == null) {
          setState(
            () => _error = context.tr(
              'Step ${index + 1} is incomplete.',
              '第 ${index + 1} 个步骤未填写完整。',
            ),
          );
          return;
        }
        steps.add(step);
      }
      body['steps'] = steps;
    } else {
      final allocationGroup = _useAllocationGroup
          ? _allocationGroup.text.trim().toLowerCase()
          : null;
      if (_useAllocationGroup &&
          (allocationGroup == null ||
              !RegExp(
                r'^[a-z0-9][a-z0-9_-]{0,63}$',
              ).hasMatch(allocationGroup))) {
        setState(
          () => _error = context.tr(
            'Use a layer ID beginning with a letter or number and up to 64 characters.',
            '分层标识须以字母或数字开头，且不超过 64 个字符。',
          ),
        );
        return;
      }
      body['status'] = _status;
      body['enabled'] = _status == 'running';
      body['allocationGroup'] = allocationGroup;
      final availableSegments = ref
          .read(analyticsSegmentOptionsProvider(widget.siteId))
          .value;
      if (_targetSegmentId != null &&
          (availableSegments == null ||
              !availableSegments.any(
                (segment) => segment.id == _targetSegmentId,
              ))) {
        setState(
          () => _error = context.tr(
            'Choose an available enabled segment, or retry loading segments.',
            '请选择一个可用的已启用分群，或重试加载分群。',
          ),
        );
        return;
      }
      final variants = _variants
          .map((controller) => controller.text.trim())
          .where((value) => value.isNotEmpty)
          .toList();
      if (variants.length < 2 || variants.toSet().length != variants.length) {
        setState(
          () => _error = context.tr(
            'Add at least two unique variants.',
            '请添加至少两个不重复的变体。',
          ),
        );
        return;
      }
      body['variants'] = variants;
      final pathPrefixes = _targetPathPrefixes
          .map((controller) => controller.text.trim())
          .toList(growable: false);
      if (pathPrefixes.any((path) => path.isEmpty)) {
        setState(
          () => _error = context.tr(
            'Complete each page path or remove the empty filter.',
            '请填写页面路径，或移除空白条件。',
          ),
        );
        return;
      }
      if (pathPrefixes.length > 20 ||
          pathPrefixes.toSet().length != pathPrefixes.length ||
          pathPrefixes.any(
            (path) =>
                path.length > 512 ||
                !path.startsWith('/') ||
                path.contains('?') ||
                path.contains('#'),
          )) {
        setState(
          () => _error = context.tr(
            'Use unique page paths starting with / and without query strings.',
            '页面路径必须以 / 开头且不含查询参数，并且不能重复。',
          ),
        );
        return;
      }
      body['targeting'] = {
        'pathPrefixes': pathPrefixes,
        'deviceTypes': _targetDeviceTypes.toList()..sort(),
        'segmentId': _targetSegmentId,
        'segmentLookbackDays': _segmentLookbackDays,
      };
    }
    Navigator.pop(context, body);
  }

  String _label(BuildContext context) =>
      widget.mode == ProductFeatureMode.funnels
      ? context.tr('funnel', '漏斗')
      : context.tr('A/B test', 'A/B 测试');
}

class _FunnelStepCard extends StatelessWidget {
  const _FunnelStepCard({
    required this.index,
    required this.form,
    required this.canRemove,
    required this.onChanged,
    required this.onRemove,
    required this.onMoveUp,
    required this.onMoveDown,
  });

  final int index;
  final _FunnelStepForm form;
  final bool canRemove;
  final VoidCallback onChanged;
  final VoidCallback onRemove;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                context.tr('Step ${index + 1}', '步骤 ${index + 1}'),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const Spacer(),
              IconButton(
                tooltip: context.tr('Move up', '上移'),
                onPressed: onMoveUp,
                icon: const Icon(Icons.arrow_upward, size: 18),
              ),
              IconButton(
                tooltip: context.tr('Move down', '下移'),
                onPressed: onMoveDown,
                icon: const Icon(Icons.arrow_downward, size: 18),
              ),
              IconButton(
                tooltip: context.tr('Remove step', '删除步骤'),
                onPressed: canRemove ? onRemove : null,
                icon: const Icon(Icons.delete_outline, size: 18),
              ),
            ],
          ),
          DropdownButtonFormField<String>(
            initialValue: form.type,
            decoration: InputDecoration(
              labelText: context.tr('Step type', '步骤类型'),
            ),
            items: [
              DropdownMenuItem(
                value: 'page_view',
                child: Text(context.tr('Page view', '页面浏览')),
              ),
              DropdownMenuItem(
                value: 'event',
                child: Text(context.tr('Event', '事件')),
              ),
            ],
            onChanged: (value) {
              if (value == null) return;
              form.type = value;
              onChanged();
            },
          ),
          const SizedBox(height: 8),
          TextField(
            controller: form.name,
            onChanged: (_) => onChanged(),
            decoration: InputDecoration(
              labelText: context.tr('Step name', '步骤名称'),
            ),
          ),
          if (form.type == 'page_view') ...[
            const SizedBox(height: 8),
            TextField(
              controller: form.path,
              onChanged: (_) => onChanged(),
              decoration: InputDecoration(
                labelText: context.tr('Page path', '页面路径'),
                hintText: '/checkout',
              ),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: form.matchMode,
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
                if (value == null) return;
                form.matchMode = value;
                onChanged();
              },
            ),
          ] else ...[
            const SizedBox(height: 8),
            TextField(
              controller: form.eventType,
              onChanged: (_) => onChanged(),
              decoration: InputDecoration(
                labelText: context.tr('Event type', '事件类型'),
                hintText: 'signup',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: form.eventName,
              onChanged: (_) => onChanged(),
              decoration: InputDecoration(
                labelText: context.tr('Event name (optional)', '事件名称（可选）'),
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

class _FunnelStepForm {
  _FunnelStepForm();

  factory _FunnelStepForm.fromJson(Map value) {
    final form = _FunnelStepForm();
    form.type = value['type'] == 'event' ? 'event' : 'page_view';
    form.name.text = '${value['name'] ?? ''}';
    form.eventType.text = '${value['eventType'] ?? ''}';
    form.eventName.text = '${value['eventName'] ?? ''}';
    form.path.text = '${value['path'] ?? ''}';
    form.matchMode = value['matchMode'] == 'contains' ? 'contains' : 'exact';
    return form;
  }

  String type = 'page_view';
  String matchMode = 'exact';
  final name = TextEditingController();
  final eventType = TextEditingController();
  final eventName = TextEditingController();
  final path = TextEditingController();

  Map<String, dynamic>? toJson() {
    final stepName = name.text.trim();
    if (stepName.isEmpty) return null;
    if (type == 'page_view') {
      final value = path.text.trim();
      if (!value.startsWith('/')) return null;
      return {
        'name': stepName,
        'type': type,
        'path': value,
        'matchMode': matchMode,
      };
    }
    final event = eventType.text.trim();
    if (event.isEmpty) return null;
    final result = <String, dynamic>{
      'name': stepName,
      'type': type,
      'eventType': event,
    };
    final eventNameValue = eventName.text.trim();
    if (eventNameValue.isNotEmpty) result['eventName'] = eventNameValue;
    return result;
  }

  void dispose() {
    name.dispose();
    eventType.dispose();
    eventName.dispose();
    path.dispose();
  }
}

class _ContainerEditorDialog extends StatefulWidget {
  const _ContainerEditorDialog({this.initial});

  final Map<String, dynamic>? initial;

  @override
  State<_ContainerEditorDialog> createState() => _ContainerEditorDialogState();
}

class _ContainerEditorDialogState extends State<_ContainerEditorDialog> {
  late final TextEditingController _name;
  late bool _enabled;

  bool get _editing => widget.initial != null;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(
      text: widget.initial?['name'] as String? ?? '',
    );
    _enabled = widget.initial?['enabled'] as bool? ?? true;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      context.tr(
        '${_editing ? 'Edit' : 'Create'} container',
        '${_editing ? '编辑' : '新建'}容器',
      ),
    ),
    content: SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            autofocus: !_editing,
            decoration: InputDecoration(labelText: context.tr('Name', '名称')),
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: Text(context.tr('Enabled', '启用')),
            value: _enabled,
            onChanged: (value) => setState(() => _enabled = value),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.tr('Cancel', '取消')),
      ),
      FilledButton(
        onPressed: () {
          final name = _name.text.trim();
          if (name.isEmpty) return;
          Navigator.pop(context, {'name': name, 'enabled': _enabled});
        },
        child: Text(
          context.tr(_editing ? 'Save' : 'Create', _editing ? '保存' : '新建'),
        ),
      ),
    ],
  );
}

class _TagDraftDialog extends StatefulWidget {
  const _TagDraftDialog({
    this.initialTags,
    this.templateMode = false,
    this.onStartLivePreview,
  });

  final List<dynamic>? initialTags;
  final bool templateMode;
  final Future<void> Function(
    List<Map<String, dynamic>> tags,
    bool executeCustomCode,
  )?
  onStartLivePreview;

  @override
  State<_TagDraftDialog> createState() => _TagDraftDialogState();
}

class _TagDraftDialogState extends State<_TagDraftDialog> {
  final _tags = <_TagFormEntry>[];
  final _savedTags = <_TagFormEntry>[];
  final _dirtyTags = <bool>[];
  var _selectedIndex = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialTags ?? const [];
    _tags.addAll(initial.whereType<Map>().map(_TagFormEntry.fromJson));
    if (_tags.isEmpty) _tags.add(_TagFormEntry());
    _savedTags.addAll(_tags.map((entry) => entry.clone()));
    _dirtyTags.addAll(List<bool>.filled(_tags.length, false));
  }

  @override
  void dispose() {
    for (final tag in _tags) {
      tag.dispose();
    }
    for (final tag in _savedTags) {
      tag.dispose();
    }
    super.dispose();
  }

  double _editorHeight(BuildContext context) =>
      (MediaQuery.sizeOf(context).height - 220).clamp(320.0, 540.0).toDouble();

  void _addTag() {
    setState(() {
      final tag = _TagFormEntry();
      _tags.add(tag);
      _savedTags.add(tag.clone());
      _dirtyTags.add(false);
      _selectedIndex = _tags.length - 1;
      _error = null;
    });
  }

  void _removeTag(int index) {
    if (_tags.length <= 1) return;
    setState(() {
      _tags.removeAt(index).dispose();
      _savedTags.removeAt(index).dispose();
      _dirtyTags.removeAt(index);
      if (_selectedIndex >= _tags.length) {
        _selectedIndex = _tags.length - 1;
      } else if (_selectedIndex > index) {
        _selectedIndex--;
      }
      _error = null;
    });
  }

  void _markTagChanged(int index) {
    if (!mounted) return;
    setState(() {
      _dirtyTags[index] = true;
      _error = null;
    });
  }

  void _saveTagChanges(int index) {
    final tag = _tags[index].toJson();
    if (tag == null) {
      setState(() {
        _selectedIndex = index;
        _error = _tagValidationMessage(index);
      });
      return;
    }
    setState(() {
      _savedTags[index].dispose();
      _savedTags[index] = _tags[index].clone();
      _dirtyTags[index] = false;
      _selectedIndex = index;
      _error = null;
    });
  }

  void _discardTagChanges(int index) {
    setState(() {
      _tags[index].copyFrom(_savedTags[index]);
      _dirtyTags[index] = false;
      _selectedIndex = index;
      _error = null;
    });
  }

  String _tagValidationMessage(int index) => context.tr(
    'Tag ${index + 1} needs a valid trigger and event definition or code snippet; complete every event filter.',
    '第 ${index + 1} 个标签需要有效触发器及事件定义或代码段，并填写完整的事件筛选条件。',
  );

  void _previewDraft() {
    final tags = <Map<String, dynamic>>[];
    for (var index = 0; index < _tags.length; index++) {
      final tag = _tags[index].toJson();
      if (tag == null) {
        setState(() {
          _selectedIndex = index;
          _error = _tagValidationMessage(index);
        });
        return;
      }
      tags.add(tag);
    }
    showDialog<void>(
      context: context,
      builder: (context) => _TagPreviewDialog(tags: tags),
    );
  }

  Future<void> _startLivePreview() async {
    final tags = <Map<String, dynamic>>[];
    for (var index = 0; index < _tags.length; index++) {
      final tag = _tags[index].toJson();
      if (tag == null) {
        setState(() {
          _selectedIndex = index;
          _error = _tagValidationMessage(index);
        });
        return;
      }
      tags.add(tag);
    }
    final executeCustomCode = await showDialog<bool>(
      context: context,
      builder: (context) => const _TagPreviewSetupDialog(),
    );
    if (executeCustomCode == null || !mounted) return;
    try {
      await widget.onStartLivePreview?.call(tags, executeCustomCode);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    }
  }

  String _tagTitle(BuildContext context, int index) {
    final tag = _tags[index];
    final name = tag.name.text.trim();
    if (name.isNotEmpty) return name;
    final eventType = tag.eventType.text.trim();
    if (eventType.isNotEmpty) return eventType;
    return context.tr('Tag ${index + 1}', '标签 ${index + 1}');
  }

  String _tagSubtitle(BuildContext context, _TagFormEntry tag) =>
      switch (tag.type) {
        'custom_html' => context.tr(
          'Custom HTML / JavaScript',
          '自定义 HTML / JavaScript',
        ),
        'page_view' => context.tr('Page view', '页面浏览'),
        _ => context.tr('Event', '事件'),
      };

  Widget _tagListItem(BuildContext context, int index) {
    final selected = index == _selectedIndex;
    final dirty = _dirtyTags[index];
    final colors = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: selected ? colors.primaryContainer : null,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => setState(() {
          _selectedIndex = index;
          _error = null;
        }),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _tagTitle(context, index),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (_tags.length > 1)
                    IconButton(
                      tooltip: context.tr('Remove tag', '删除标签'),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _removeTag(index),
                      icon: const Icon(Icons.delete_outline, size: 18),
                    ),
                ],
              ),
              Text(
                _tagSubtitle(context, _tags[index]),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (dirty) ...[
                const SizedBox(height: 6),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        minimumSize: const Size(0, 34),
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: () => _saveTagChanges(index),
                      icon: const Icon(Icons.save_outlined, size: 16),
                      label: Text(context.tr('Save', '保存')),
                    ),
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        minimumSize: const Size(0, 34),
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: () => _discardTagChanges(index),
                      icon: const Icon(Icons.undo, size: 16),
                      label: Text(context.tr('Discard', '丢弃')),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _tagManagement(BuildContext context, double panelHeight) => SizedBox(
    width: 220,
    height: panelHeight,
    child: Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              context.tr('Tags', '标签管理'),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              context.tr('Select a tag to edit it.', '选择标签后在右侧编辑。'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _addTag,
              icon: const Icon(Icons.add),
              label: Text(context.tr('Add tag', '添加标签')),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  for (var index = 0; index < _tags.length; index++)
                    _tagListItem(context, index),
                ],
              ),
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
  );

  @override
  Widget build(BuildContext context) {
    final editorHeight = _editorHeight(context);
    final panelHeight = editorHeight + 88;
    const leftWidth = 220.0;
    const editorWidth = 1080.0;
    const contentWidth = leftWidth + 16 + editorWidth;
    return AlertDialog(
      title: Text(
        context.tr(
          widget.templateMode
              ? 'Configure reusable template tags'
              : 'Edit container tags',
          widget.templateMode ? '配置可复用模板标签' : '编辑容器标签',
        ),
      ),
      content: SizedBox(
        width: contentWidth,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 700),
          child: SingleChildScrollView(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: contentWidth,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _tagManagement(context, panelHeight),
                    const SizedBox(width: 16),
                    SizedBox(
                      width: editorWidth,
                      child: _ThreeColumnTagFormCard(
                        key: ValueKey('tag-editor-$_selectedIndex'),
                        entry: _tags[_selectedIndex],
                        onChanged: () => _markTagChanged(_selectedIndex),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.tr('Cancel', '取消')),
        ),
        OutlinedButton.icon(
          onPressed: _previewDraft,
          icon: const Icon(Icons.play_arrow),
          label: Text(context.tr('Preview draft', '预览草稿')),
        ),
        if (!widget.templateMode && widget.onStartLivePreview != null)
          OutlinedButton.icon(
            onPressed: _startLivePreview,
            icon: const Icon(Icons.open_in_browser),
            label: Text(context.tr('Test on live site', '在真实页面测试')),
          ),
        FilledButton(
          onPressed: _save,
          child: Text(
            context.tr(
              widget.templateMode ? 'Save template tags' : 'Save draft',
              widget.templateMode ? '保存模板标签' : '保存草稿',
            ),
          ),
        ),
      ],
    );
  }

  void _save() {
    final tags = <Map<String, dynamic>>[];
    for (var index = 0; index < _tags.length; index++) {
      final tag = _tags[index].toJson();
      if (tag == null) {
        setState(() {
          _selectedIndex = index;
          _error = _tagValidationMessage(index);
        });
        return;
      }
      tags.add(tag);
    }
    Navigator.pop(context, tags);
  }
}

class _TagTemplateLibraryDialog extends ConsumerStatefulWidget {
  const _TagTemplateLibraryDialog({
    required this.siteId,
    required this.containers,
    required this.onUse,
  });

  final String siteId;
  final List<Map<String, dynamic>> containers;
  final Future<void> Function(String containerId, List<dynamic> tags) onUse;

  @override
  ConsumerState<_TagTemplateLibraryDialog> createState() =>
      _TagTemplateLibraryDialogState();
}

class _TagTemplateLibraryDialogState
    extends ConsumerState<_TagTemplateLibraryDialog> {
  List<Map<String, dynamic>> _templates = const [];
  bool _loading = true;
  String? _error;

  String get _path => '/api/v1/sites/${widget.siteId}/tag-manager/templates';

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
      final data = await ref.read(apiProvider).request('GET', _path) as List;
      if (!mounted) return;
      setState(() {
        _templates = data
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList(growable: false);
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _errorMessage(error);
      });
    }
  }

  Future<void> _editTemplate([Map<String, dynamic>? initial]) async {
    final originalTags = initial?['tags'] as List?;
    final tags = await showDialog<List<dynamic>>(
      context: context,
      builder: (_) =>
          _TagDraftDialog(initialTags: originalTags, templateMode: true),
    );
    if (tags == null || !mounted) return;
    final details = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _TemplateDetailsDialog(initial: initial),
    );
    if (details == null || !mounted) return;
    try {
      final id = initial?['id'] as String?;
      await ref
          .read(apiProvider)
          .request(
            id == null ? 'POST' : 'PUT',
            id == null ? _path : '$_path/$id',
            body: {...details, 'tags': tags},
          );
      await _load();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _errorMessage(error));
    }
  }

  Future<void> _useTemplate(Map<String, dynamic> item) async {
    if (widget.containers.isEmpty) return;
    final containerId = await showDialog<String>(
      context: context,
      builder: (_) => _TemplateTargetDialog(containers: widget.containers),
    );
    if (containerId == null || !mounted) return;
    final tags = (item['tags'] as List?)?.toList(growable: false) ?? const [];
    Navigator.of(context).pop();
    await widget.onUse(containerId, tags);
  }

  Future<void> _deleteTemplate(Map<String, dynamic> item) async {
    final id = item['id'] as String?;
    if (id == null) return;
    final name = item['name'] as String? ?? '';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.tr('Delete template?', '删除模板？')),
        content: Text(
          context.tr(
            '“$name” will be removed from the workspace template library. Existing container versions will not change.',
            '“$name”将从工作区模板库中删除，已保存的容器版本不会改变。',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.tr('Cancel', '取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(context.tr('Delete', '删除')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(apiProvider).request('DELETE', '$_path/$id');
      await _load();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _errorMessage(error));
    }
  }

  String _errorMessage(Object error) =>
      error is ApiFailure ? error.message : '$error';

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return AlertDialog(
      title: Text(context.tr('Reusable tag templates', '可复用标签模板')),
      content: SizedBox(
        width: (size.width - 80).clamp(320.0, 760.0),
        height: (size.height * 0.62).clamp(280.0, 520.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              context.tr(
                'Shared across sites in this workspace. Templates are inserted into a new draft; they never publish automatically.',
                '模板在工作区内的站点间共享。使用模板会创建容器草稿，不会自动发布。',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 12),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _templates.isEmpty
                  ? Center(
                      child: Text(
                        context.tr(
                          'No templates yet. Create one from the visual tag editor.',
                          '还没有模板。可以使用图形化标签编辑器创建模板。',
                        ),
                      ),
                    )
                  : ListView.separated(
                      itemCount: _templates.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final item = _templates[index];
                        final tags = item['tags'] as List? ?? const [];
                        final name = item['name'] as String? ?? '';
                        final description = item['description'] as String?;
                        return ListTile(
                          title: Text(name),
                          subtitle: Text(
                            description?.isNotEmpty == true
                                ? '$description · ${context.tr('${tags.length} tags', '${tags.length} 个标签')}'
                                : context.tr(
                                    '${tags.length} tags',
                                    '${tags.length} 个标签',
                                  ),
                          ),
                          trailing: Wrap(
                            spacing: 0,
                            children: [
                              OutlinedButton.icon(
                                onPressed: widget.containers.isEmpty
                                    ? null
                                    : () => _useTemplate(item),
                                icon: const Icon(Icons.playlist_add),
                                label: Text(context.tr('Use', '使用')),
                              ),
                              IconButton(
                                tooltip: context.tr('Edit template', '编辑模板'),
                                onPressed: () => _editTemplate(item),
                                icon: const Icon(Icons.edit_outlined),
                              ),
                              IconButton(
                                tooltip: context.tr('Delete template', '删除模板'),
                                onPressed: () => _deleteTemplate(item),
                                icon: const Icon(Icons.delete_outline),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            if (widget.containers.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  context.tr(
                    'Create a container before inserting a template.',
                    '请先创建容器，再插入模板。',
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.tr('Close', '关闭')),
        ),
        FilledButton.icon(
          onPressed: () => _editTemplate(),
          icon: const Icon(Icons.add),
          label: Text(context.tr('Create template', '新建模板')),
        ),
      ],
    );
  }
}

class _TemplateDetailsDialog extends StatefulWidget {
  const _TemplateDetailsDialog({this.initial});

  final Map<String, dynamic>? initial;

  @override
  State<_TemplateDetailsDialog> createState() => _TemplateDetailsDialogState();
}

class _TemplateDetailsDialogState extends State<_TemplateDetailsDialog> {
  late final TextEditingController _name;
  late final TextEditingController _description;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(
      text: widget.initial?['name'] as String? ?? '',
    );
    _description = TextEditingController(
      text: widget.initial?['description'] as String? ?? '',
    );
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
        widget.initial == null ? 'Name this template' : 'Edit template details',
        widget.initial == null ? '命名模板' : '编辑模板信息',
      ),
    ),
    content: SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            decoration: InputDecoration(labelText: context.tr('Name', '名称')),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _description,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: context.tr('When to use it (optional)', '用途说明（可选）'),
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.tr('Cancel', '取消')),
      ),
      FilledButton(
        onPressed: () {
          final name = _name.text.trim();
          if (name.isEmpty) return;
          Navigator.pop(context, {
            'name': name,
            'description': _description.text.trim(),
          });
        },
        child: Text(context.tr('Save', '保存')),
      ),
    ],
  );
}

class _TemplateTargetDialog extends StatefulWidget {
  const _TemplateTargetDialog({required this.containers});

  final List<Map<String, dynamic>> containers;

  @override
  State<_TemplateTargetDialog> createState() => _TemplateTargetDialogState();
}

class _TemplateTargetDialogState extends State<_TemplateTargetDialog> {
  late String _containerId;

  @override
  void initState() {
    super.initState();
    _containerId = widget.containers.first['id'] as String;
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(context.tr('Add template to container', '选择目标容器')),
    content: SizedBox(
      width: 420,
      child: DropdownButtonFormField<String>(
        initialValue: _containerId,
        decoration: InputDecoration(labelText: context.tr('Container', '容器')),
        items: [
          for (final container in widget.containers)
            DropdownMenuItem(
              value: container['id'] as String,
              child: Text(container['name'] as String? ?? ''),
            ),
        ],
        onChanged: (value) {
          if (value != null) setState(() => _containerId = value);
        },
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.tr('Cancel', '取消')),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _containerId),
        child: Text(context.tr('Add as draft', '添加为草稿')),
      ),
    ],
  );
}

class _TagPreviewDialog extends StatefulWidget {
  const _TagPreviewDialog({required this.tags});

  final List<Map<String, dynamic>> tags;

  @override
  State<_TagPreviewDialog> createState() => _TagPreviewDialogState();
}

class _TagPreviewDialogState extends State<_TagPreviewDialog> {
  final _event = TextEditingController(text: 'page_view');
  final _url = TextEditingController(text: 'https://example.test/');
  final _title = TextEditingController(text: 'Preview page');
  final _referrer = TextEditingController();
  final _eventName = TextEditingController();
  final _eventCategory = TextEditingController();
  final _eventAction = TextEditingController();
  final _properties = <_TagPropertyEntry>[];
  final _context = <String, TextEditingController>{
    'Browser': TextEditingController(text: 'Chrome'),
    'Operating System': TextEditingController(text: 'Linux'),
    'Device Type': TextEditingController(text: 'desktop'),
    'Language': TextEditingController(text: 'zh-CN'),
    'Screen Width': TextEditingController(text: '1920'),
    'Screen Height': TextEditingController(text: '1080'),
    'Viewport Width': TextEditingController(text: '1440'),
    'Viewport Height': TextEditingController(text: '900'),
  };

  @override
  void dispose() {
    _event.dispose();
    _url.dispose();
    _title.dispose();
    _referrer.dispose();
    _eventName.dispose();
    _eventCategory.dispose();
    _eventAction.dispose();
    for (final property in _properties) {
      property.dispose();
    }
    for (final controller in _context.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Map<String, Object?> get _eventPropertyValues => {
    for (final property in _properties)
      if (property.key.text.trim().isNotEmpty)
        property.key.text.trim(): property.value.text,
  };

  List<TagPreviewResult> get _results => TagManagerPreview.evaluate(
    widget.tags,
    event: _event.text.trim(),
    url: _url.text.trim(),
    title: _title.text.trim(),
    referrer: _referrer.text.trim(),
    eventName: _eventName.text.trim(),
    eventCategory: _eventCategory.text.trim(),
    eventAction: _eventAction.text.trim(),
    eventProperties: _eventPropertyValues,
    context: {
      for (final entry in _context.entries) entry.key: entry.value.text,
    },
  );

  void _changed() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return AlertDialog(
      title: Row(
        children: [
          Expanded(child: Text(context.tr('Draft preview', '草稿预览'))),
          Chip(
            avatar: const Icon(Icons.science_outlined, size: 16),
            label: Text(context.tr('Dry run', '模拟运行')),
          ),
        ],
      ),
      content: SizedBox(
        width: (size.width - 64).clamp(420.0, 1040.0),
        height: (size.height - 190).clamp(300.0, 680.0),
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                context.tr(
                  'No tracking request is sent and no custom code runs here. Custom JavaScript triggers need a live browser check.',
                  '此处不会发送追踪请求或执行自定义代码。自定义 JavaScript 触发器仍需在真实浏览器中验证。',
                ),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 5, child: _inputPanel(context)),
                  const VerticalDivider(width: 24),
                  Expanded(flex: 6, child: _resultPanel(context)),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.tr('Close', '关闭')),
        ),
      ],
    );
  }

  Widget _inputPanel(BuildContext context) => SingleChildScrollView(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          context.tr('Simulated visitor event', '模拟访客事件'),
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 4,
          runSpacing: 0,
          children: [
            for (final event in const [
              'page_view',
              'signup',
              'purchase',
              'download',
              'outlink',
            ])
              ChoiceChip(
                label: Text(event),
                selected: _event.text == event,
                onSelected: (_) {
                  _event.text = event;
                  _changed();
                },
              ),
          ],
        ),
        TextField(
          controller: _event,
          onChanged: (_) => _changed(),
          decoration: InputDecoration(
            labelText: context.tr('Event name', '事件名称'),
            helperText: context.tr(
              'Use a suggested event or enter a custom name.',
              '可选择建议事件，或输入自定义事件名。',
            ),
          ),
        ),
        TextField(
          controller: _url,
          onChanged: (_) => _changed(),
          decoration: InputDecoration(
            labelText: context.tr('Page URL', '页面网址'),
          ),
        ),
        TextField(
          controller: _title,
          onChanged: (_) => _changed(),
          decoration: InputDecoration(
            labelText: context.tr('Page title', '页面标题'),
          ),
        ),
        TextField(
          controller: _referrer,
          onChanged: (_) => _changed(),
          decoration: InputDecoration(
            labelText: context.tr('Referrer', '来源页面'),
          ),
        ),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: Text(context.tr('Event details and properties', '事件信息与属性')),
          children: [
            TextField(
              controller: _eventName,
              onChanged: (_) => _changed(),
              decoration: InputDecoration(
                labelText: context.tr('Event display name', '事件显示名称'),
              ),
            ),
            TextField(
              controller: _eventCategory,
              onChanged: (_) => _changed(),
              decoration: InputDecoration(
                labelText: context.tr('Category', '类别'),
              ),
            ),
            TextField(
              controller: _eventAction,
              onChanged: (_) => _changed(),
              decoration: InputDecoration(
                labelText: context.tr('Action', '动作'),
              ),
            ),
            for (final property in _properties)
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: property.key,
                      onChanged: (_) => _changed(),
                      decoration: InputDecoration(
                        labelText: context.tr('Property key', '属性键'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: property.value,
                      onChanged: (_) => _changed(),
                      decoration: InputDecoration(
                        labelText: context.tr('Property value', '属性值'),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: context.tr('Remove property', '删除属性'),
                    onPressed: () {
                      _properties.remove(property);
                      property.dispose();
                      _changed();
                    },
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                ],
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () {
                  _properties.add(_TagPropertyEntry());
                  _changed();
                },
                icon: const Icon(Icons.add, size: 18),
                label: Text(context.tr('Add event property', '添加事件属性')),
              ),
            ),
          ],
        ),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: Text(context.tr('Sample visitor context', '示例访客环境')),
          subtitle: Text(context.tr('Editable preview values', '可编辑的预览值')),
          children: [
            for (final entry in _context.entries)
              TextField(
                controller: entry.value,
                onChanged: (_) => _changed(),
                decoration: InputDecoration(
                  labelText: context.tr(entry.key, switch (entry.key) {
                    'Operating System' => '操作系统',
                    'Device Type' => '设备类型',
                    'Screen Width' => '屏幕宽度',
                    'Screen Height' => '屏幕高度',
                    'Viewport Width' => '视口宽度',
                    'Viewport Height' => '视口高度',
                    'Language' => '语言',
                    _ => '浏览器',
                  }),
                ),
              ),
          ],
        ),
      ],
    ),
  );

  Widget _resultPanel(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              context.tr('Tag results', '标签结果'),
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          Text(
            '${_results.where((result) => result.status == TagPreviewStatus.fires).length}/${_results.length}',
          ),
        ],
      ),
      const SizedBox(height: 8),
      Expanded(
        child: _results.isEmpty
            ? Center(child: Text(context.tr('No draft tags.', '没有草稿标签。')))
            : ListView.separated(
                padding: EdgeInsets.zero,
                itemCount: _results.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) =>
                    _resultCard(context, _results[index]),
              ),
      ),
    ],
  );

  Widget _resultCard(BuildContext context, TagPreviewResult result) {
    final colors = Theme.of(context).colorScheme;
    final status = result.status;
    final statusColor = switch (status) {
      TagPreviewStatus.fires => colors.primary,
      TagPreviewStatus.notFired => colors.outline,
      TagPreviewStatus.needsBrowserCheck => colors.tertiary,
    };
    final statusText = switch (status) {
      TagPreviewStatus.fires => context.tr('Would fire', '将触发'),
      TagPreviewStatus.notFired => context.tr('Not matched', '未匹配'),
      TagPreviewStatus.needsBrowserCheck => context.tr(
        'Needs browser check',
        '需浏览器验证',
      ),
    };
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(switch (status) {
                  TagPreviewStatus.fires => Icons.check_circle_outline,
                  TagPreviewStatus.notFired => Icons.remove_circle_outline,
                  TagPreviewStatus.needsBrowserCheck => Icons.help_outline,
                }, color: statusColor),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        result.name,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text('${result.type} · ${_event.text}'),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Chip(
                  label: Text(statusText),
                  visualDensity: VisualDensity.compact,
                  side: BorderSide(color: statusColor.withValues(alpha: 0.35)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (status == TagPreviewStatus.fires &&
                result.type == 'custom_html')
              Text(
                context.tr(
                  'Trigger matches. Custom HTML/JavaScript is intentionally not executed during this dry run.',
                  '触发条件匹配。模拟运行不会执行自定义 HTML/JavaScript。',
                ),
              )
            else if (status == TagPreviewStatus.needsBrowserCheck)
              Text(
                context.tr(
                  'This tag has a custom JavaScript trigger. Its result can only be confirmed in a live browser.',
                  '此标签包含自定义 JavaScript 触发器，只能在真实浏览器中确认结果。',
                ),
              )
            else if (status == TagPreviewStatus.notFired)
              Text(
                context.tr(
                  'No configured trigger matches “${_event.text}”.',
                  '没有已配置的触发条件匹配“${_event.text}”。',
                ),
              )
            else ...[
              Text(
                context.tr(
                  'Would emit event: ${result.eventType ?? result.name}',
                  '将发送事件：${result.eventType ?? result.name}',
                ),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              for (final property in result.properties.entries)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        property.key,
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                      SelectableText('${property.value ?? ''}'),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

// ignore: unused_element
class _TagFormCard extends StatelessWidget {
  const _TagFormCard({
    required this.index,
    required this.entry,
    required this.canRemove,
    required this.onChanged,
    required this.onRemove,
  });

  final int index;
  final _TagFormEntry entry;
  final bool canRemove;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  context.tr('Tag ${index + 1}', '标签 ${index + 1}'),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              if (canRemove)
                IconButton(
                  tooltip: context.tr('Remove tag', '删除标签'),
                  onPressed: onRemove,
                  icon: const Icon(Icons.delete_outline),
                ),
            ],
          ),
          DropdownButtonFormField<String>(
            initialValue: entry.type,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: context.tr('Tag type', '标签类型'),
            ),
            items: [
              DropdownMenuItem(
                value: 'custom_html',
                child: Text(
                  context.tr(
                    'Custom HTML / JavaScript',
                    '自定义 HTML / JavaScript',
                  ),
                ),
              ),
              DropdownMenuItem(
                value: 'event',
                child: Text(context.tr('Custom event', '自定义事件')),
              ),
              DropdownMenuItem(
                value: 'page_view',
                child: Text(context.tr('Page view', '页面浏览')),
              ),
            ],
            onChanged: (value) {
              if (value == null) return;
              entry.type = value;
              onChanged();
            },
          ),
          if (entry.type == 'event' || entry.type == 'custom_html') ...[
            const SizedBox(height: 8),
            TextField(
              controller: entry.trigger,
              onChanged: (_) => onChanged(),
              decoration: InputDecoration(
                labelText: context.tr(
                  'Trigger event (use page_view for page load)',
                  '触发事件（页面加载请输入 page_view）',
                ),
                hintText: entry.type == 'custom_html' ? 'page_view' : 'signup',
              ),
            ),
          ],
          if (entry.type == 'custom_html') ...[
            const SizedBox(height: 8),
            TextField(
              controller: entry.name,
              onChanged: (_) => onChanged(),
              decoration: InputDecoration(
                labelText: context.tr('Display name', '显示名称'),
                hintText: 'marketing_pixel',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: entry.code,
              onChanged: (_) => onChanged(),
              minLines: 7,
              maxLines: 14,
              keyboardType: TextInputType.multiline,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              decoration: InputDecoration(
                alignLabelWithHint: true,
                labelText: context.tr(
                  'Code snippet (HTML / JavaScript)',
                  '代码段（HTML / JavaScript）',
                ),
                hintText: '<script>\n  // your code\n</script>',
                helperText: context.tr(
                  'HTML nodes are inserted into the page and script tags are executed when the trigger fires.',
                  'HTML 节点会插入页面，script 标签会在触发条件满足时执行。',
                ),
                border: const OutlineInputBorder(),
              ),
            ),
          ],
          if (entry.type != 'custom_html') ...[
            const SizedBox(height: 8),
            TextField(
              controller: entry.eventType,
              onChanged: (_) => onChanged(),
              decoration: InputDecoration(
                labelText: context.tr('Sent event type', '发送的事件类型'),
                hintText: 'tag_signup',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: entry.name,
              onChanged: (_) => onChanged(),
              decoration: InputDecoration(
                labelText: context.tr('Display name (optional)', '显示名称（可选）'),
                hintText: 'signup_tag',
              ),
            ),
            const SizedBox(height: 12),
            Text(
              context.tr('Event properties (optional)', '事件属性（可选）'),
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 4),
            for (
              var propertyIndex = 0;
              propertyIndex < entry.properties.length;
              propertyIndex++
            )
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: entry.properties[propertyIndex].key,
                        onChanged: (_) => onChanged(),
                        decoration: InputDecoration(
                          labelText: context.tr('Key', '键'),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: entry.properties[propertyIndex].value,
                        onChanged: (_) => onChanged(),
                        decoration: InputDecoration(
                          labelText: context.tr('Value', '值'),
                          isDense: true,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: context.tr('Remove property', '删除属性'),
                      onPressed: () {
                        final removed = entry.properties.removeAt(
                          propertyIndex,
                        );
                        removed.dispose();
                        onChanged();
                      },
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                  ],
                ),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () {
                  entry.properties.add(_TagPropertyEntry());
                  onChanged();
                },
                icon: const Icon(Icons.add, size: 18),
                label: Text(context.tr('Add property', '添加属性')),
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

class _TagTriggerOption {
  const _TagTriggerOption(this.id, this.english, this.chinese);

  final String id;
  final String english;
  final String chinese;
}

const _tagTriggerOptions = [
  _TagTriggerOption('page_view', 'Page view', '页面浏览'),
  _TagTriggerOption('session_start', 'Session start', '会话开始'),
  _TagTriggerOption('goal', 'Goal', '目标完成'),
  _TagTriggerOption('download', 'Download', '下载'),
  _TagTriggerOption('outlink', 'Outbound link', '外链点击'),
  _TagTriggerOption('signup', 'Signup', '注册'),
  _TagTriggerOption('login', 'Login', '登录'),
  _TagTriggerOption('purchase', 'Purchase', '购买'),
  _TagTriggerOption('add_to_cart', 'Add to cart', '加入购物车'),
  _TagTriggerOption('form_submit', 'Form submit', '表单提交'),
  _TagTriggerOption('search', 'Search', '搜索'),
  _TagTriggerOption('experiment_exposure', 'Experiment exposure', '实验曝光'),
];

class _TagVariableOption {
  const _TagVariableOption(this.token, this.english, this.chinese);

  final String token;
  final String english;
  final String chinese;
}

const _tagVariableOptions = [
  _TagVariableOption('{{Page URL}}', 'Page URL', '页面网址'),
  _TagVariableOption('{{Page Title}}', 'Page title', '页面标题'),
  _TagVariableOption('{{Referrer}}', 'Referrer', '来源页面'),
  _TagVariableOption('{{Event}}', 'Event', '事件'),
  _TagVariableOption('{{Event Name}}', 'Event name', '事件名称'),
  _TagVariableOption('{{Event Category}}', 'Event category', '事件类别'),
  _TagVariableOption('{{Event Action}}', 'Event action', '事件动作'),
  _TagVariableOption(
    '{{Event Property: property_name}}',
    'Event property (uses this row\'s key)',
    '事件属性（使用本行的键）',
  ),
  _TagVariableOption('{{Browser}}', 'Browser', '浏览器'),
  _TagVariableOption('{{Operating System}}', 'Operating system', '操作系统'),
  _TagVariableOption('{{Device Type}}', 'Device type', '设备类型'),
  _TagVariableOption('{{Language}}', 'Language', '语言'),
  _TagVariableOption('{{Screen Width}}', 'Screen width', '屏幕宽度'),
  _TagVariableOption('{{Screen Height}}', 'Screen height', '屏幕高度'),
  _TagVariableOption('{{Viewport Width}}', 'Viewport width', '视口宽度'),
  _TagVariableOption('{{Viewport Height}}', 'Viewport height', '视口高度'),
];

class _TagEventConditionOperator {
  const _TagEventConditionOperator(this.id, this.english, this.chinese);

  final String id;
  final String english;
  final String chinese;
}

const _tagEventConditionOperators = [
  _TagEventConditionOperator('equals', 'equals', '等于'),
  _TagEventConditionOperator('not_equals', 'does not equal', '不等于'),
  _TagEventConditionOperator('contains', 'contains', '包含'),
  _TagEventConditionOperator('starts_with', 'starts with', '开头匹配'),
  _TagEventConditionOperator('ends_with', 'ends with', '结尾匹配'),
  _TagEventConditionOperator('exists', 'exists', '存在'),
];

class _ThreeColumnTagFormCard extends StatefulWidget {
  const _ThreeColumnTagFormCard({
    super.key,
    required this.entry,
    required this.onChanged,
  });

  final _TagFormEntry entry;
  final VoidCallback onChanged;

  @override
  State<_ThreeColumnTagFormCard> createState() =>
      _ThreeColumnTagFormCardState();
}

class _ThreeColumnTagFormCardState extends State<_ThreeColumnTagFormCard> {
  final _settingsScrollController = ScrollController();
  final _triggersScrollController = ScrollController();
  final _codeScrollController = ScrollController();

  _TagFormEntry get entry => widget.entry;
  VoidCallback get onChanged => widget.onChanged;

  @override
  void dispose() {
    _settingsScrollController.dispose();
    _triggersScrollController.dispose();
    _codeScrollController.dispose();
    super.dispose();
  }

  void _insertVariable(TextEditingController controller, String token) {
    final selection = controller.selection;
    final start = selection.isValid ? selection.start : controller.text.length;
    final end = selection.isValid ? selection.end : controller.text.length;
    final nextText = controller.text.replaceRange(start, end, token);
    controller.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: start + token.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    final editorHeight = (MediaQuery.sizeOf(context).height - 220)
        .clamp(320.0, 540.0)
        .toDouble();
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: editorHeight,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: _scrollingColumn(
                      _settings(context),
                      _settingsScrollController,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 4,
                    child: _scrollingColumn(
                      _triggers(context),
                      _triggersScrollController,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 5,
                    child: _scrollingColumn(
                      _code(context),
                      _codeScrollController,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _scrollingColumn(Widget child, ScrollController controller) =>
      Scrollbar(
        controller: controller,
        thumbVisibility: true,
        child: SingleChildScrollView(
          controller: controller,
          primary: false,
          padding: const EdgeInsets.only(right: 8),
          child: child,
        ),
      );

  Widget _settings(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        context.tr('Settings', '基础设置'),
        style: Theme.of(context).textTheme.labelLarge,
      ),
      const SizedBox(height: 8),
      DropdownButtonFormField<String>(
        initialValue: entry.type,
        isExpanded: true,
        decoration: InputDecoration(labelText: context.tr('Tag type', '标签类型')),
        items: [
          DropdownMenuItem(
            value: 'custom_html',
            child: Text(
              context.tr('Custom HTML / JavaScript', '自定义 HTML / JavaScript'),
            ),
          ),
          DropdownMenuItem(
            value: 'event',
            child: Text(context.tr('Custom event', '自定义事件')),
          ),
          DropdownMenuItem(
            value: 'page_view',
            child: Text(context.tr('Page view', '页面浏览')),
          ),
        ],
        onChanged: (value) {
          if (value == null) return;
          entry.type = value;
          if (value == 'page_view') {
            entry.predefinedTriggers.add('page_view');
          }
          onChanged();
        },
      ),
      const SizedBox(height: 8),
      TextField(
        controller: entry.name,
        onChanged: (_) => onChanged(),
        decoration: InputDecoration(
          labelText: context.tr(
            entry.type == 'custom_html'
                ? 'Display name'
                : 'Display name (optional)',
            entry.type == 'custom_html' ? '显示名称' : '显示名称（可选）',
          ),
          hintText: 'marketing_pixel',
        ),
      ),
      if (entry.type != 'custom_html') ...[
        const SizedBox(height: 8),
        TextField(
          controller: entry.eventType,
          onChanged: (_) => onChanged(),
          decoration: InputDecoration(
            labelText: context.tr('Sent event type', '发送的事件类型'),
            hintText: 'tag_signup',
          ),
        ),
        const SizedBox(height: 12),
        Text(
          context.tr('Event properties (optional)', '事件属性（可选）'),
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 4),
        Text(
          context.tr(
            'Insert page, event, or visitor-context values into a property.',
            '可将页面、事件或访客环境变量插入属性值。',
          ),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 4),
        for (final property in entry.properties)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: property.key,
                    onChanged: (_) => onChanged(),
                    decoration: InputDecoration(
                      labelText: context.tr('Key', '键'),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: property.value,
                    onChanged: (_) => onChanged(),
                    decoration: InputDecoration(
                      labelText: context.tr('Value', '值'),
                      isDense: true,
                      suffixIcon: PopupMenuButton<_TagVariableOption>(
                        tooltip: context.tr('Insert variable', '插入变量'),
                        icon: const Icon(Icons.data_object, size: 18),
                        onSelected: (option) {
                          final token =
                              option.token ==
                                  '{{Event Property: property_name}}'
                              ? '{{Event Property: ${property.key.text.trim().isEmpty ? 'property_name' : property.key.text.trim()}}}'
                              : option.token;
                          _insertVariable(property.value, token);
                          onChanged();
                        },
                        itemBuilder: (context) => [
                          for (final option in _tagVariableOptions)
                            PopupMenuItem(
                              value: option,
                              child: Text(
                                context.tr(option.english, option.chinese),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: context.tr('Remove property', '删除属性'),
                  onPressed: () {
                    entry.properties.remove(property);
                    property.dispose();
                    onChanged();
                  },
                  icon: const Icon(Icons.remove_circle_outline),
                ),
              ],
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () {
              entry.properties.add(_TagPropertyEntry());
              onChanged();
            },
            icon: const Icon(Icons.add, size: 18),
            label: Text(context.tr('Add property', '添加属性')),
          ),
        ),
      ],
    ],
  );

  Widget _triggers(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        context.tr('Triggers (match any)', '触发条件（满足任意一项即可）'),
        style: Theme.of(context).textTheme.labelLarge,
      ),
      const SizedBox(height: 4),
      Text(
        context.tr('Select one or more predefined events.', '可多选预定义事件。'),
        style: Theme.of(context).textTheme.bodySmall,
      ),
      const SizedBox(height: 4),
      Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          TextButton.icon(
            onPressed: () {
              entry.customEvents.add(_TagCustomEventEntry());
              onChanged();
            },
            icon: const Icon(Icons.add, size: 18),
            label: Text(context.tr('Add custom event', '添加自定义事件')),
          ),
          TextButton.icon(
            onPressed: () {
              entry.customJsTriggers.add(_TagCustomJsTriggerEntry());
              onChanged();
            },
            icon: const Icon(Icons.add, size: 18),
            label: Text(context.tr('Add custom JS trigger', '添加自定义 JS 触发器')),
          ),
        ],
      ),
      for (final option in _tagTriggerOptions)
        CheckboxListTile(
          value: entry.predefinedTriggers.contains(option.id),
          onChanged: (checked) {
            if (checked == true) {
              entry.predefinedTriggers.add(option.id);
            } else {
              entry.predefinedTriggers.remove(option.id);
            }
            onChanged();
          },
          title: Text(context.tr(option.english, option.chinese)),
          subtitle: Text(option.id),
          dense: true,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
        ),
      const Divider(),
      Text(
        context.tr('Custom event triggers', '自定义事件触发器'),
        style: Theme.of(context).textTheme.labelLarge,
      ),
      if (entry.customEvents.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            context.tr(
              'All filters within one event trigger must match. Different triggers still use OR.',
              '同一个事件触发器内的筛选条件需全部匹配；不同触发器仍为“或”。',
            ),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      for (final custom in entry.customEvents)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Card(
            margin: EdgeInsets.zero,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: custom.name,
                          onChanged: (_) => onChanged(),
                          decoration: InputDecoration(
                            labelText: context.tr('Event name', '事件名称'),
                            hintText: 'checkout_started',
                            isDense: true,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: context.tr('Remove trigger', '删除触发条件'),
                        onPressed: () {
                          entry.customEvents.remove(custom);
                          custom.dispose();
                          onChanged();
                        },
                        icon: const Icon(Icons.remove_circle_outline),
                      ),
                    ],
                  ),
                  for (final condition in custom.conditions)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Column(
                        children: [
                          TextField(
                            controller: condition.property,
                            onChanged: (_) => onChanged(),
                            decoration: InputDecoration(
                              labelText: context.tr(
                                'Event property key',
                                '事件属性键',
                              ),
                              hintText: 'plan',
                              isDense: true,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  initialValue: condition.operator,
                                  isExpanded: true,
                                  decoration: InputDecoration(
                                    labelText: context.tr('Match rule', '匹配规则'),
                                    isDense: true,
                                  ),
                                  items: [
                                    for (final option
                                        in _tagEventConditionOperators)
                                      DropdownMenuItem(
                                        value: option.id,
                                        child: Text(
                                          context.tr(
                                            option.english,
                                            option.chinese,
                                          ),
                                        ),
                                      ),
                                  ],
                                  onChanged: (value) {
                                    if (value == null) return;
                                    condition.operator = value;
                                    onChanged();
                                  },
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: TextField(
                                  controller: condition.value,
                                  enabled: condition.operator != 'exists',
                                  onChanged: (_) => onChanged(),
                                  decoration: InputDecoration(
                                    labelText: context.tr('Value', '值'),
                                    hintText: condition.operator == 'exists'
                                        ? context.tr('Not needed', '无需填写')
                                        : 'pro',
                                    isDense: true,
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: context.tr('Remove filter', '删除筛选条件'),
                                onPressed: () {
                                  custom.conditions.remove(condition);
                                  condition.dispose();
                                  onChanged();
                                },
                                icon: const Icon(
                                  Icons.remove_circle_outline,
                                  size: 18,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () {
                        custom.conditions.add(_TagEventConditionEntry());
                        onChanged();
                      },
                      icon: const Icon(Icons.filter_alt_outlined, size: 18),
                      label: Text(context.tr('Add filter', '添加筛选条件')),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      const Divider(),
      Text(
        context.tr('Custom JavaScript triggers', '自定义 JavaScript 触发器'),
        style: Theme.of(context).textTheme.labelLarge,
      ),
      Text(
        context.tr(
          'The tracker calls window.functionName(event, context). Return true to fire this tag.',
          '追踪器会调用 window.functionName(event, context)，返回 true 才会触发标签。',
        ),
        style: Theme.of(context).textTheme.bodySmall,
      ),
      for (var i = 0; i < entry.customJsTriggers.length; i++)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Card(
            margin: EdgeInsets.zero,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: entry.customJsTriggers[i].functionName,
                          onChanged: (_) => onChanged(),
                          decoration: InputDecoration(
                            labelText: context.tr(
                              'window function name',
                              'window 函数名',
                            ),
                            hintText: 'shouldFireMarketingTag',
                            isDense: true,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: context.tr('Remove trigger', '删除触发条件'),
                        onPressed: () {
                          final removed = entry.customJsTriggers.removeAt(i);
                          removed.dispose();
                          onChanged();
                        },
                        icon: const Icon(Icons.remove_circle_outline),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: entry.customJsTriggers[i].code,
                    onChanged: (_) => onChanged(),
                    minLines: 2,
                    maxLines: 5,
                    keyboardType: TextInputType.multiline,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                    decoration: InputDecoration(
                      alignLabelWithHint: true,
                      labelText: context.tr(
                        'Function expression (optional)',
                        '函数表达式（可选）',
                      ),
                      hintText:
                          '(event, context) => event.event === \'purchase\'',
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
    ],
  );

  Widget _code(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        context.tr('Injected code', '注入代码段'),
        style: Theme.of(context).textTheme.labelLarge,
      ),
      const SizedBox(height: 4),
      if (entry.type == 'custom_html')
        TextField(
          controller: entry.code,
          onChanged: (_) => onChanged(),
          minLines: 18,
          maxLines: 28,
          keyboardType: TextInputType.multiline,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
          decoration: InputDecoration(
            alignLabelWithHint: true,
            labelText: context.tr(
              'HTML / JavaScript snippet',
              'HTML / JavaScript 代码段',
            ),
            hintText: '<script>\n  // code executed on trigger\n</script>',
            helperText: context.tr(
              'HTML is inserted into the page. Script tags and raw JavaScript are executed when a trigger matches.',
              'HTML 会插入页面；触发条件满足时会执行 script 标签和原始 JavaScript。',
            ),
            border: const OutlineInputBorder(),
          ),
        )
      else
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).colorScheme.outline),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            context.tr(
              'This tag emits an analytics event and does not inject code. Choose Custom HTML / JavaScript when you need a code snippet.',
              '此标签只发送分析事件，不注入代码。需要代码段时请选择“自定义 HTML / JavaScript”。',
            ),
          ),
        ),
    ],
  );
}

class _TagFormEntry {
  _TagFormEntry();

  String type = 'event';
  final trigger = TextEditingController();
  final eventType = TextEditingController();
  final name = TextEditingController();
  final code = TextEditingController();
  final predefinedTriggers = <String>{};
  final customEvents = <_TagCustomEventEntry>[];
  final customJsTriggers = <_TagCustomJsTriggerEntry>[];
  final properties = <_TagPropertyEntry>[];

  factory _TagFormEntry.fromJson(Map value) {
    final entry = _TagFormEntry();
    entry.type = value['type'] == 'page_view'
        ? 'page_view'
        : value['type'] == 'custom_html'
        ? 'custom_html'
        : 'event';
    final triggerValue = value['trigger'];
    entry.trigger.text = triggerValue is String
        ? triggerValue
        : triggerValue is Map
        ? '${triggerValue['event'] ?? ''}'
        : '';
    final rawTriggers = value['triggers'];
    if (rawTriggers is List) {
      for (final rawTrigger in rawTriggers) {
        entry._readTrigger(rawTrigger);
      }
    } else if (triggerValue != null) {
      entry._readTrigger(triggerValue);
    }
    if (entry.type == 'page_view' &&
        entry.predefinedTriggers.isEmpty &&
        entry.customEvents.isEmpty &&
        entry.customJsTriggers.isEmpty) {
      entry.predefinedTriggers.add('page_view');
    }
    entry.eventType.text = '${value['eventType'] ?? ''}';
    entry.name.text = '${value['name'] ?? ''}';
    entry.code.text = '${value['code'] ?? ''}';
    final rawProperties = value['properties'];
    if (rawProperties is Map) {
      for (final property in rawProperties.entries) {
        entry.properties.add(
          _TagPropertyEntry(
            keyValue: '${property.key}',
            valueValue: '${property.value}',
          ),
        );
      }
    }
    return entry;
  }

  Map<String, dynamic>? toJson() {
    final eventTypeValue = eventType.text.trim();
    final nameValue = name.text.trim();
    final codeValue = code.text.trim();
    final triggers = <Map<String, dynamic>>[
      for (final value in predefinedTriggers)
        {'type': 'predefined', 'event': value},
    ];
    for (final custom in customEvents) {
      if (custom.name.text.trim().isEmpty) {
        if (custom.conditions.isNotEmpty) return null;
        continue;
      }
      final trigger = custom.toJson();
      if (trigger == null) return null;
      triggers.add(trigger);
    }
    triggers.addAll([
      for (final custom in customJsTriggers)
        if (custom.functionName.text.trim().isNotEmpty)
          {
            'type': 'custom_js',
            'functionName': custom.functionName.text.trim(),
            if (custom.code.text.trim().isNotEmpty)
              'code': custom.code.text.trim(),
          },
    ]);
    if (type == 'custom_html'
        ? (nameValue.isEmpty || triggers.isEmpty || codeValue.isEmpty)
        : ((eventTypeValue.isEmpty && nameValue.isEmpty) ||
              (type == 'event' && triggers.isEmpty))) {
      return null;
    }
    final result = <String, dynamic>{'type': type};
    if (triggers.isNotEmpty) result['triggers'] = triggers;
    if (eventTypeValue.isNotEmpty) result['eventType'] = eventTypeValue;
    if (nameValue.isNotEmpty) result['name'] = nameValue;
    if (codeValue.isNotEmpty) result['code'] = codeValue;
    final values = <String, String>{};
    for (final property in properties) {
      final key = property.key.text.trim();
      final value = property.value.text.trim();
      if (key.isNotEmpty) values[key] = value;
    }
    if (values.isNotEmpty) result['properties'] = values;
    return result;
  }

  _TagFormEntry clone() {
    final copy = _TagFormEntry()..type = type;
    copy.trigger.text = trigger.text;
    copy.eventType.text = eventType.text;
    copy.name.text = name.text;
    copy.code.text = code.text;
    copy.predefinedTriggers.addAll(predefinedTriggers);
    copy.customEvents.addAll(customEvents.map((event) => event.copy()));
    copy.customJsTriggers.addAll(
      customJsTriggers.map(
        (trigger) => _TagCustomJsTriggerEntry(
          functionNameValue: trigger.functionName.text,
          codeValue: trigger.code.text,
        ),
      ),
    );
    copy.properties.addAll(
      properties.map(
        (property) => _TagPropertyEntry(
          keyValue: property.key.text,
          valueValue: property.value.text,
        ),
      ),
    );
    return copy;
  }

  void copyFrom(_TagFormEntry source) {
    type = source.type;
    trigger.text = source.trigger.text;
    eventType.text = source.eventType.text;
    name.text = source.name.text;
    code.text = source.code.text;
    predefinedTriggers
      ..clear()
      ..addAll(source.predefinedTriggers);
    for (final event in customEvents) {
      event.dispose();
    }
    customEvents
      ..clear()
      ..addAll(source.customEvents.map((event) => event.copy()));
    for (final trigger in customJsTriggers) {
      trigger.dispose();
    }
    customJsTriggers
      ..clear()
      ..addAll(
        source.customJsTriggers.map(
          (trigger) => _TagCustomJsTriggerEntry(
            functionNameValue: trigger.functionName.text,
            codeValue: trigger.code.text,
          ),
        ),
      );
    for (final property in properties) {
      property.dispose();
    }
    properties
      ..clear()
      ..addAll(
        source.properties.map(
          (property) => _TagPropertyEntry(
            keyValue: property.key.text,
            valueValue: property.value.text,
          ),
        ),
      );
  }

  void _readTrigger(dynamic value) {
    if (value is String) {
      final id = value.trim();
      if (_tagTriggerOptions.any((option) => option.id == id)) {
        predefinedTriggers.add(id);
      } else if (id.isNotEmpty) {
        customEvents.add(_TagCustomEventEntry(nameValue: id));
      }
      return;
    }
    if (value is! Map) return;
    final kind = '${value['type'] ?? 'event'}';
    if (kind == 'custom_js') {
      customJsTriggers.add(
        _TagCustomJsTriggerEntry(
          functionNameValue: '${value['functionName'] ?? ''}',
          codeValue: '${value['code'] ?? ''}',
        ),
      );
      return;
    }
    if (value['type'] == 'event' ||
        value['conditions'] is List &&
            (value['conditions'] as List).isNotEmpty) {
      customEvents.add(
        _TagCustomEventEntry(
          nameValue: '${value['event'] ?? ''}',
          conditionValues: value['conditions'] is List
              ? value['conditions'] as List
              : const [],
        ),
      );
      return;
    }
    _readTrigger('${value['event'] ?? ''}');
  }

  void dispose() {
    trigger.dispose();
    eventType.dispose();
    name.dispose();
    code.dispose();
    for (final property in properties) {
      property.dispose();
    }
    for (final event in customEvents) {
      event.dispose();
    }
    for (final customJsTrigger in customJsTriggers) {
      customJsTrigger.dispose();
    }
  }
}

class _TagCustomEventEntry {
  _TagCustomEventEntry({
    String nameValue = '',
    List<dynamic> conditionValues = const [],
  }) : name = TextEditingController(text: nameValue) {
    for (final condition in conditionValues.whereType<Map>()) {
      conditions.add(_TagEventConditionEntry.fromJson(condition));
    }
  }

  final TextEditingController name;
  final conditions = <_TagEventConditionEntry>[];

  Map<String, dynamic>? toJson() {
    final event = name.text.trim();
    if (event.isEmpty) return null;
    final encodedConditions = <Map<String, String>>[];
    for (final condition in conditions) {
      final encoded = condition.toJson();
      if (encoded == null) return null;
      encodedConditions.add(encoded);
    }
    return {
      'type': 'event',
      'event': event,
      if (encodedConditions.isNotEmpty) 'conditions': encodedConditions,
    };
  }

  _TagCustomEventEntry copy() => _TagCustomEventEntry(
    nameValue: name.text,
    conditionValues: conditions.map((condition) => condition.toMap()).toList(),
  );

  void dispose() {
    name.dispose();
    for (final condition in conditions) {
      condition.dispose();
    }
  }
}

class _TagEventConditionEntry {
  _TagEventConditionEntry({
    String propertyValue = '',
    this.operator = 'equals',
    String valueValue = '',
  }) : property = TextEditingController(text: propertyValue),
       value = TextEditingController(text: valueValue);

  factory _TagEventConditionEntry.fromJson(Map value) =>
      _TagEventConditionEntry(
        propertyValue: '${value['property'] ?? ''}',
        operator: '${value['operator'] ?? 'equals'}',
        valueValue: '${value['value'] ?? ''}',
      );

  final TextEditingController property;
  String operator;
  final TextEditingController value;

  Map<String, String>? toJson() {
    final propertyName = property.text.trim();
    if (propertyName.isEmpty ||
        !_tagEventConditionOperators.any((option) => option.id == operator) ||
        operator != 'exists' && value.text.isEmpty) {
      return null;
    }
    return {
      'property': propertyName,
      'operator': operator,
      if (operator != 'exists') 'value': value.text,
    };
  }

  Map<String, String> toMap() => {
    'property': property.text,
    'operator': operator,
    'value': value.text,
  };

  void dispose() {
    property.dispose();
    value.dispose();
  }
}

class _TagCustomJsTriggerEntry {
  _TagCustomJsTriggerEntry({
    String functionNameValue = '',
    String codeValue = '',
  }) : functionName = TextEditingController(text: functionNameValue),
       code = TextEditingController(text: codeValue);

  final TextEditingController functionName;
  final TextEditingController code;

  void dispose() {
    functionName.dispose();
    code.dispose();
  }
}

class _TagPropertyEntry {
  _TagPropertyEntry({String keyValue = '', String valueValue = ''})
    : key = TextEditingController(text: keyValue),
      value = TextEditingController(text: valueValue);

  final TextEditingController key;
  final TextEditingController value;

  void dispose() {
    key.dispose();
    value.dispose();
  }
}

String _formatSampleCount(int value) => value.toString().replaceAllMapped(
  RegExp(r'\B(?=(\d{3})+(?!\d))'),
  (match) => ',',
);

class _ReportDialog extends StatelessWidget {
  const _ReportDialog({required this.mode, required this.report});

  final ProductFeatureMode mode;
  final Map report;

  @override
  Widget build(BuildContext context) {
    final rows = mode == ProductFeatureMode.funnels
        ? ((report['steps'] as List?) ?? const [])
        : ((report['variants'] as List?) ?? const []);
    if (mode == ProductFeatureMode.experiments) {
      final variants = rows.whereType<Map>().toList(growable: false);
      final highestInterval = variants.fold<double>(0, (highest, row) {
        final upper = (row['conversionRateCiUpper'] as num?)?.toDouble() ?? 0;
        return upper > highest ? upper : highest;
      });
      final intervalScaleMax = highestInterval <= 0
          ? 1.0
          : (highestInterval * 1.25).clamp(0.01, 1.0).toDouble();
      final from = report['from'] as String?;
      final to = report['to'] as String?;
      return AlertDialog(
        title: Text(report['name'] as String? ?? context.tr('Report', '报告')),
        content: SizedBox(
          width: 560,
          child: variants.isEmpty
              ? Text(context.tr('No data yet.', '暂无数据。'))
              : SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (from != null && to != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Text(
                            '$from – $to',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      Text(
                        context.tr(
                          'Conversion performance by variant',
                          '各变体转化表现',
                        ),
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      for (var index = 0; index < variants.length; index++)
                        _experimentVariantCard(
                          context,
                          variants[index],
                          isControl: index == 0,
                          intervalScaleMax: intervalScaleMax,
                        ),
                      const SizedBox(height: 4),
                      Text(
                        context.tr(
                          'Conversion-rate intervals use the pointwise 95% Wilson score method. Variant differences use the pointwise 95% Newcombe-Wilson interval; intervals are not adjusted for multiple comparisons. A confidence interval describes uncertainty, not a guarantee or automatic stop signal.',
                          '转化率区间采用逐项 95% Wilson 得分法，变体差值采用逐项 95% Newcombe-Wilson 区间；区间未针对多重比较调整。置信区间用于表达不确定性，不是保证，也不会自动触发停止。',
                        ),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.tr('Close', '关闭')),
          ),
        ],
      );
    }
    return AlertDialog(
      title: Text(report['name'] as String? ?? context.tr('Report', '报告')),
      content: SizedBox(
        width: 520,
        child: rows.isEmpty
            ? Text(context.tr('No data yet.', '暂无数据。'))
            : ListView(
                shrinkWrap: true,
                children: [
                  for (final row in rows.whereType<Map>())
                    ListTile(
                      title: Text(
                        row['name'] as String? ??
                            row['variant'] as String? ??
                            '',
                      ),
                      subtitle: Text(
                        mode == ProductFeatureMode.funnels
                            ? '${row['sessions'] ?? 0} sessions · ${_percent(row['rate'])}${_funnelDropOff(row)}'
                            : '${row['exposures'] ?? 0} exposures · ${row['conversions'] ?? 0} conversions · ${_percent(row['conversionRate'])}${_experimentComparison(row)}',
                      ),
                    ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.tr('Close', '关闭')),
        ),
      ],
    );
  }

  String _percent(dynamic value) =>
      '${(((value as num?)?.toDouble() ?? 0) * 100).toStringAsFixed(1)}%';

  Widget _experimentVariantCard(
    BuildContext context,
    Map row, {
    required bool isControl,
    required double intervalScaleMax,
  }) {
    final rate = (row['conversionRate'] as num?)?.toDouble() ?? 0;
    final interval = _formatRateInterval(
      context,
      row['conversionRateCiLower'],
      row['conversionRateCiUpper'],
    );
    final exposures = (row['exposures'] as num?)?.toInt() ?? 0;
    final conversions = (row['conversions'] as num?)?.toInt() ?? 0;
    final rateDifference = (row['conversionRateDifference'] as num?)
        ?.toDouble();
    final differenceInterval = _formatDifferenceInterval(
      context,
      row['conversionRateDifferenceCiLower'],
      row['conversionRateDifferenceCiUpper'],
    );
    final pValue = (row['pValue'] as num?)?.toDouble();
    final significant = row['statisticallySignificant'] == true;
    final relativeLift = (row['relativeLift'] as num?)?.toDouble();
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    row['variant'] as String? ?? '',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Chip(
                  label: Text(
                    isControl
                        ? context.tr('Control', '对照组')
                        : context.tr('Variant', '实验组'),
                  ),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            Text(
              context.tr(
                '$conversions conversions from $exposures exposed sessions',
                '$exposures 个曝光会话中转化 $conversions 个',
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    context.tr('Conversion rate', '转化率'),
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
                Text(
                  _percent(rate),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 6),
            _ConfidenceIntervalBar(
              lower: (row['conversionRateCiLower'] as num?)?.toDouble(),
              upper: (row['conversionRateCiUpper'] as num?)?.toDouble(),
              estimate: rate,
              scaleMax: intervalScaleMax,
            ),
            const SizedBox(height: 6),
            Text(
              context.tr('95% rate interval: $interval', '95% 转化率区间：$interval'),
            ),
            if (!isControl) ...[
              const Divider(height: 20),
              if (rateDifference != null)
                Text(
                  context.tr(
                    'Absolute difference: ${_signedPercentagePoints(rateDifference)}',
                    '绝对转化率差：${_signedPercentagePoints(rateDifference)}',
                  ),
                ),
              Text(
                context.tr(
                  '95% difference interval: $differenceInterval',
                  '95% 差值区间：$differenceInterval',
                ),
              ),
              if (relativeLift != null)
                Text(
                  context.tr(
                    'Relative lift: ${_signedPercent(relativeLift * 100)}%',
                    '相对提升：${_signedPercent(relativeLift * 100)}%',
                  ),
                ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(
                    significant
                        ? Icons.check_circle_outline
                        : pValue == null
                        ? Icons.hourglass_empty
                        : Icons.info_outline,
                    size: 18,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      pValue == null
                          ? context.tr(
                              'Not enough data for a significance estimate',
                              '数据不足，暂无法估计显著性',
                            )
                          : context.tr(
                              '${significant ? 'Statistically significant' : 'Not conclusive'} · p=${pValue.toStringAsFixed(3)}',
                              '${significant ? '达到统计显著性' : '暂无明确结论'} · p=${pValue.toStringAsFixed(3)}',
                            ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatRateInterval(
    BuildContext context,
    dynamic lower,
    dynamic upper,
  ) {
    if (lower is! num || upper is! num) {
      return context.tr('Not available', '暂无');
    }
    return '${_percent(lower)} – ${_percent(upper)}';
  }

  String _formatDifferenceInterval(
    BuildContext context,
    dynamic lower,
    dynamic upper,
  ) {
    if (lower is! num || upper is! num) {
      return context.tr('Not available', '暂无');
    }
    return '${_signedPercentagePoints(lower.toDouble())} – ${_signedPercentagePoints(upper.toDouble())}';
  }

  String _signedPercentagePoints(double value) {
    final points = value * 100;
    return '${points > 0 ? '+' : ''}${points.toStringAsFixed(1)} pp';
  }

  String _signedPercent(double value) =>
      '${value > 0 ? '+' : ''}${value.toStringAsFixed(1)}';

  String _experimentComparison(Map row) {
    if (mode != ProductFeatureMode.experiments || row['relativeLift'] == null) {
      return '';
    }
    final lift = (row['relativeLift'] as num).toDouble() * 100;
    final marker = row['statisticallySignificant'] == true
        ? ' · significant'
        : '';
    return ' · ${lift >= 0 ? '+' : ''}${lift.toStringAsFixed(1)}% lift$marker';
  }

  String _funnelDropOff(Map row) {
    final dropOff = row['dropOff'] as num?;
    if (dropOff == null || dropOff == 0) return '';
    return ' · ${dropOff.toInt()} drop-off (${_percent(row['dropOffRate'])})';
  }
}

class _ConfidenceIntervalBar extends StatelessWidget {
  const _ConfidenceIntervalBar({
    required this.lower,
    required this.upper,
    required this.estimate,
    required this.scaleMax,
  });

  final double? lower;
  final double? upper;
  final double estimate;
  final double scaleMax;

  @override
  Widget build(BuildContext context) {
    if (lower == null || upper == null) {
      return Text(context.tr('Interval unavailable', '区间暂无数据'));
    }
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          key: const ValueKey('experiment-rate-confidence-interval'),
          height: 24,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final intervalStart =
                  (lower!.clamp(0.0, scaleMax) / scaleMax) * width;
              final intervalEnd =
                  (upper!.clamp(0.0, scaleMax) / scaleMax) * width;
              final point = (estimate.clamp(0.0, scaleMax) / scaleMax) * width;
              final pointLeft = (point - 6).clamp(0.0, width - 12).toDouble();
              return Stack(
                alignment: Alignment.centerLeft,
                children: [
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 11,
                    child: Container(height: 2, color: colors.outlineVariant),
                  ),
                  Positioned(
                    left: intervalStart,
                    width: (intervalEnd - intervalStart)
                        .clamp(2.0, width)
                        .toDouble(),
                    top: 10,
                    child: Container(height: 4, color: colors.primary),
                  ),
                  Positioned(
                    left: pointLeft,
                    top: 5,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: colors.primary,
                        shape: BoxShape.circle,
                        border: Border.all(color: colors.surface, width: 2),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('0%'),
            Text('${(scaleMax * 100).toStringAsFixed(1)}%'),
          ],
        ),
      ],
    );
  }
}

class _ProductionRequestNoteDialog extends StatefulWidget {
  const _ProductionRequestNoteDialog();

  @override
  State<_ProductionRequestNoteDialog> createState() =>
      _ProductionRequestNoteDialogState();
}

class _ProductionRequestNoteDialogState
    extends State<_ProductionRequestNoteDialog> {
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(context.tr('Request production review', '申请生产发布审核')),
    content: SizedBox(
      width: 480,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr(
              'Explain what is changing and why. A different workspace administrator will review the version summary before it can go live.',
              '请说明变更内容和原因。另一位工作区管理员会先审阅版本摘要，批准后才会对访客生效。',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            autofocus: true,
            minLines: 3,
            maxLines: 5,
            maxLength: 1000,
            decoration: InputDecoration(
              labelText: context.tr('Release summary', '发布说明'),
              hintText: context.tr(
                'For example: Add the signup conversion tag after QA.',
                '例如：QA 验收后新增注册转化标签。',
              ),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.tr('Cancel', '取消')),
      ),
      FilledButton(
        onPressed: _note.text.trim().isEmpty
            ? null
            : () => Navigator.pop(context, _note.text.trim()),
        child: Text(context.tr('Submit for review', '提交审核')),
      ),
    ],
  );
}

typedef _ProductionRequestAction =
    Future<List<Map<String, dynamic>>> Function(
      String requestId,
      String action,
      String? note,
    );

class _ProductionApprovalsDialog extends StatefulWidget {
  const _ProductionApprovalsDialog({
    required this.requests,
    required this.onAction,
  });

  final List<Map<String, dynamic>> requests;
  final _ProductionRequestAction onAction;

  @override
  State<_ProductionApprovalsDialog> createState() =>
      _ProductionApprovalsDialogState();
}

class _ProductionApprovalsDialogState
    extends State<_ProductionApprovalsDialog> {
  late List<Map<String, dynamic>> _requests = widget.requests;
  String? _busyId;
  String? _error;

  Future<void> _act(
    Map<String, dynamic> request,
    String action, {
    String? note,
  }) async {
    final id = request['id'] as String?;
    if (id == null) return;
    setState(() {
      _busyId = id;
      _error = null;
    });
    try {
      final refreshed = await widget.onAction(id, action, note);
      if (!mounted) return;
      setState(() {
        _requests = refreshed;
        _busyId = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busyId = null;
        _error = error is ApiFailure ? error.message : '$error';
      });
    }
  }

  Future<void> _reject(Map<String, dynamic> request) async {
    final note = TextEditingController();
    var valid = false;
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(context.tr('Reject production release', '拒绝生产发布')),
          content: TextField(
            controller: note,
            minLines: 2,
            maxLines: 4,
            maxLength: 1000,
            decoration: InputDecoration(labelText: context.tr('Reason', '原因')),
            onChanged: (value) =>
                setDialogState(() => valid = value.trim().isNotEmpty),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.tr('Cancel', '取消')),
            ),
            FilledButton(
              onPressed: valid
                  ? () => Navigator.pop(context, note.text.trim())
                  : null,
              child: Text(context.tr('Reject', '拒绝')),
            ),
          ],
        ),
      ),
    );
    note.dispose();
    if (reason == null) return;
    await _act(request, 'reject', note: reason);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(context.tr('Production approvals', '生产发布审核')),
    content: SizedBox(
      width: 680,
      height: 480,
      child: _requests.isEmpty
          ? Center(
              child: Text(
                context.tr('No production release requests yet.', '暂无生产发布申请。'),
              ),
            )
          : ListView.separated(
              itemCount: _requests.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) => _requestCard(_requests[index]),
            ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.tr('Close', '关闭')),
      ),
    ],
  );

  Widget _requestCard(Map<String, dynamic> request) {
    final pending = request['status'] == 'pending';
    final id = request['id'] as String? ?? '';
    final changes =
        (request['changes'] as List?)
            ?.whereType<Map>()
            .map((change) => Map<String, dynamic>.from(change))
            .toList(growable: false) ??
        const <Map<String, dynamic>>[];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    context.tr(
                      'Production v${request['targetVersion']} · ${request['status']}',
                      '生产 v${request['targetVersion']} · ${_statusLabel(request['status'] as String? ?? '')}',
                    ),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                Text(
                  context.tr(
                    'From ${request['baseVersion'] == null ? 'none' : 'v${request['baseVersion']}'}',
                    '基于 ${request['baseVersion'] == null ? '首次发布' : 'v${request['baseVersion']}'}',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              context.tr(
                'Requested by ${request['requestedByEmail'] ?? 'unknown'} · ${_timeLabel(request['requestedAt'])}',
                '申请人 ${request['requestedByEmail'] ?? '未知'} · ${_timeLabel(request['requestedAt'])}',
              ),
            ),
            const SizedBox(height: 6),
            Text(request['requestNote'] as String? ?? ''),
            if (changes.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  context.tr(
                    'No tag differences from the reviewed base version.',
                    '与基准版本相比没有标签差异。',
                  ),
                ),
              )
            else ...[
              const SizedBox(height: 8),
              Text(context.tr('Version changes', '版本变更')),
              for (final change in changes) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '• ${_changeLabel(change['kind'] as String? ?? '')} ${change['name'] ?? 'Tag'} · ${_tagTypeLabel(change['type'] as String? ?? '')}${change['customCodeChanged'] == true ? ' · ${context.tr('custom script added/changed', '自定义脚本新增/修改')}' : ''}',
                  ),
                ),
                if (change['emittedEvent'] is String)
                  Padding(
                    padding: const EdgeInsets.only(left: 16, top: 2),
                    child: Text(
                      context.tr(
                        'Emits ${change['emittedEvent']}',
                        '发送事件 ${change['emittedEvent']}',
                      ),
                    ),
                  ),
                for (final trigger
                    in (change['triggers'] as List? ?? const [])
                        .whereType<Map>())
                  Padding(
                    padding: const EdgeInsets.only(left: 16, top: 2),
                    child: Text(
                      _releaseTriggerLabel(Map<String, dynamic>.from(trigger)),
                    ),
                  ),
              ],
            ],
            if (request['reviewNote'] is String &&
                (request['reviewNote'] as String).isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                context.tr(
                  'Review by ${request['reviewedByEmail'] ?? 'unknown'}: ${request['reviewNote']}',
                  '审核人 ${request['reviewedByEmail'] ?? '未知'}：${request['reviewNote']}',
                ),
              ),
            ],
            if (pending && request['canReview'] != true)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  context.tr(
                    'The requester cannot approve their own release; another workspace administrator must review it.',
                    '申请人不能批准自己的发布；需要另一位工作区管理员审核。',
                  ),
                ),
              ),
            if (pending &&
                (request['canReview'] == true ||
                    request['canCancel'] == true)) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  if (request['canReview'] == true) ...[
                    FilledButton.tonal(
                      onPressed: _busyId == id
                          ? null
                          : () => _act(request, 'approve'),
                      child: Text(context.tr('Approve and publish', '批准并发布')),
                    ),
                    TextButton(
                      onPressed: _busyId == id ? null : () => _reject(request),
                      child: Text(context.tr('Reject', '拒绝')),
                    ),
                  ],
                  if (request['canCancel'] == true)
                    TextButton(
                      onPressed: _busyId == id
                          ? null
                          : () => _act(request, 'cancel'),
                      child: Text(context.tr('Cancel request', '撤回申请')),
                    ),
                  if (_busyId == id)
                    const Padding(
                      padding: EdgeInsets.all(10),
                      child: SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                ],
              ),
            ],
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _statusLabel(String status) => switch (status) {
    'pending' => context.tr('pending', '待审核'),
    'approved' => context.tr('approved', '已批准'),
    'rejected' => context.tr('rejected', '已拒绝'),
    'cancelled' => context.tr('cancelled', '已撤回'),
    _ => status,
  };

  String _changeLabel(String kind) => switch (kind) {
    'added' => context.tr('Added', '新增'),
    'removed' => context.tr('Removed', '移除'),
    _ => context.tr('Changed', '修改'),
  };

  String _tagTypeLabel(String type) => switch (type) {
    'custom_html' => context.tr(
      'Custom HTML/JavaScript',
      '自定义 HTML/JavaScript',
    ),
    'page_view' => context.tr('Page view', '页面浏览'),
    'event' => context.tr('Event', '事件'),
    _ => type,
  };

  String _releaseTriggerLabel(Map<String, dynamic> trigger) {
    final kind = trigger['kind'] as String? ?? 'event';
    final value = trigger['value'] as String? ?? '';
    final label = switch (kind) {
      'predefined' => context.tr('Predefined event', '预设事件'),
      'custom_js' => context.tr('Custom JS function', '自定义 JS 函数'),
      _ => context.tr('Event', '事件'),
    };
    final filters = (trigger['filterCount'] as num?)?.toInt() ?? 0;
    if (filters == 0) return '$label $value';
    return '$label $value · ${context.tr('$filters property filter(s)', '$filters 个属性条件')}';
  }

  String _timeLabel(Object? value) {
    if (value is! String) return '';
    final date = DateTime.tryParse(value)?.toLocal();
    if (date == null) return value;
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}

class _VersionsDialog extends StatelessWidget {
  const _VersionsDialog({required this.versions, required this.onPublish});

  final List<Map<String, dynamic>> versions;
  final Future<void> Function(int version) onPublish;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(context.tr('Container versions', '容器版本')),
    content: SizedBox(
      width: 480,
      child: versions.isEmpty
          ? Text(context.tr('No versions yet.', '暂无版本。'))
          : ListView(
              shrinkWrap: true,
              children: [
                for (final version in versions)
                  ListTile(
                    title: Text('v${version['version'] ?? ''}'),
                    subtitle: Text(version['status'] as String? ?? 'draft'),
                    trailing: version['status'] == 'published'
                        ? const Icon(Icons.check_circle_outline)
                        : TextButton(
                            onPressed: () =>
                                onPublish((version['version'] as num).toInt()),
                            child: Text(context.tr('Request review', '申请审核')),
                          ),
                  ),
              ],
            ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.tr('Close', '关闭')),
      ),
    ],
  );
}

class _TagPreviewSetupDialog extends StatefulWidget {
  const _TagPreviewSetupDialog();

  @override
  State<_TagPreviewSetupDialog> createState() => _TagPreviewSetupDialogState();
}

class _TagPreviewSetupDialogState extends State<_TagPreviewSetupDialog> {
  bool _executeCustomCode = false;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(context.tr('Start a live-site test?', '开始真实页面测试？')),
    content: SizedBox(
      width: 520,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr(
              'The test uses a temporary preview token and expires automatically after 15 minutes. Put the generated snippet only on a test page hosted on a domain allowed for this site.',
              '测试使用临时预览令牌，15 分钟后自动过期。请只把生成的代码放在此站点已允许域名下的测试页面。',
            ),
          ),
          const SizedBox(height: 12),
          DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.shield_outlined,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      context.tr(
                        'SeeRay analytics collection is suppressed in preview mode. Custom HTML and JavaScript can make external requests or change the test page, so they stay blocked unless you explicitly opt in.',
                        '预览模式不会向 SeeRay 发送分析数据。自定义 HTML/JavaScript 仍可能向外部发送请求或修改测试页面，默认阻止，只有明确同意后才会执行。',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _executeCustomCode,
            onChanged: (value) =>
                setState(() => _executeCustomCode = value ?? false),
            title: Text(
              context.tr(
                'Execute custom HTML / JavaScript on the test page',
                '在测试页面执行自定义 HTML / JavaScript',
              ),
            ),
            subtitle: Text(
              context.tr(
                'Includes custom JavaScript trigger functions.',
                '也包括自定义 JavaScript 触发条件函数。',
              ),
            ),
            controlAffinity: ListTileControlAffinity.leading,
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.tr('Cancel', '取消')),
      ),
      FilledButton.icon(
        onPressed: () => Navigator.pop(context, _executeCustomCode),
        icon: const Icon(Icons.open_in_browser),
        label: Text(context.tr('Create test session', '创建测试会话')),
      ),
    ],
  );
}

class _TagManagerLivePreviewDialog extends ConsumerStatefulWidget {
  const _TagManagerLivePreviewDialog({
    required this.siteId,
    required this.containerId,
    required this.trackingId,
    required this.trackerUrl,
    required this.requireConsent,
    required this.sessionId,
    required this.token,
    required this.expiresAt,
  });

  final String siteId;
  final String containerId;
  final String trackingId;
  final String trackerUrl;
  final bool requireConsent;
  final String sessionId;
  final String token;
  final String expiresAt;

  @override
  ConsumerState<_TagManagerLivePreviewDialog> createState() =>
      _TagManagerLivePreviewDialogState();
}

class _TagManagerLivePreviewDialogState
    extends ConsumerState<_TagManagerLivePreviewDialog> {
  Timer? _poller;
  List<Map<String, dynamic>> _events = const [];
  bool _loading = true;
  bool _requestInFlight = false;
  bool _stopping = false;
  String? _error;

  String get _basePath =>
      '/api/v1/sites/${widget.siteId}/tag-manager/containers/${widget.containerId}/preview-sessions/${widget.sessionId}';

  String get _snippet =>
      '<script src="${_attribute(widget.trackerUrl)}" '
      'data-site-id="${_attribute(widget.trackingId)}" '
      '${widget.requireConsent ? 'data-require-consent="true" ' : ''}'
      'data-tag-manager="true" '
      'data-tag-manager-preview-session="${_attribute(widget.sessionId)}" '
      'data-tag-manager-preview-token="${_attribute(widget.token)}"></script>';

  String _attribute(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('"', '&quot;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');

  @override
  void initState() {
    super.initState();
    unawaited(_loadEvents());
    _poller = Timer.periodic(
      const Duration(seconds: 2),
      (_) => unawaited(_loadEvents()),
    );
  }

  @override
  void dispose() {
    _poller?.cancel();
    super.dispose();
  }

  Future<void> _loadEvents() async {
    if (_requestInFlight || !mounted) return;
    _requestInFlight = true;
    try {
      final response =
          await ref.read(apiProvider).request('GET', '$_basePath/events')
              as List;
      if (!mounted) return;
      setState(() {
        _events = response
            .whereType<Map>()
            .map((event) => Map<String, dynamic>.from(event))
            .toList(growable: false);
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    } finally {
      _requestInFlight = false;
    }
  }

  Future<void> _stop() async {
    setState(() {
      _stopping = true;
      _error = null;
    });
    try {
      await ref.read(apiProvider).request('DELETE', _basePath);
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        setState(() {
          _stopping = false;
          _error = error.toString();
        });
      }
    }
  }

  String _expiryLabel(BuildContext context) {
    final expiry = DateTime.tryParse(widget.expiresAt)?.toLocal();
    if (expiry == null) return widget.expiresAt;
    final date = expiry.toIso8601String().replaceFirst('T', ' ');
    return context.tr('Expires at $date', '$date 过期');
  }

  (String, Color) _status(BuildContext context, String? value) =>
      switch (value) {
        'fired' => (context.tr('Fired', '已触发'), Colors.green),
        'blocked' => (context.tr('Code blocked', '代码已阻止'), Colors.deepOrange),
        _ => (context.tr('No match', '未匹配'), Colors.blueGrey),
      };

  Widget _eventTile(BuildContext context, Map<String, dynamic> event) {
    final status = _status(context, event['outcome'] as String?);
    final name = event['tagName'] as String? ?? 'Tag';
    final trigger = event['triggerEvent'] as String? ?? '';
    final path = event['pagePath'] as String? ?? '/';
    final timestamp = DateTime.tryParse(event['occurredAt'] as String? ?? '');
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: status.$2.withValues(alpha: 0.12),
          child: Icon(Icons.bolt, color: status.$2),
        ),
        title: Row(
          children: [
            Expanded(child: Text(name, overflow: TextOverflow.ellipsis)),
            const SizedBox(width: 8),
            Chip(
              label: Text(status.$1),
              visualDensity: VisualDensity.compact,
              side: BorderSide.none,
              backgroundColor: status.$2.withValues(alpha: 0.12),
              labelStyle: TextStyle(color: status.$2),
            ),
          ],
        ),
        subtitle: Text('$trigger  ·  $path'),
        trailing: timestamp == null
            ? null
            : Text(
                timestamp.toLocal().toIso8601String().substring(11, 19),
                style: Theme.of(context).textTheme.labelSmall,
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Row(
      children: [
        const Icon(Icons.travel_explore),
        const SizedBox(width: 10),
        Expanded(child: Text(context.tr('Live site preview', '真实页面预览'))),
        IconButton(
          tooltip: context.tr('Refresh events', '刷新事件'),
          onPressed: _requestInFlight ? null : _loadEvents,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    content: SizedBox(
      width: 820,
      height: 560,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.timer_outlined,
                size: 18,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(_expiryLabel(context))),
              TextButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: _snippet));
                  if (context.mounted) {
                    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                      SnackBar(
                        content: Text(
                          context.tr('Test snippet copied', '测试代码已复制'),
                        ),
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.copy, size: 18),
                label: Text(context.tr('Copy snippet', '复制代码')),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: SelectableText(
              _snippet,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            context.tr(
              'Paste this into a test page on an allowed site domain, then use the page normally or call SeeRay.push() with test events. No SeeRay analytics are recorded. Query strings and event properties are not included in this debug log.',
              '将代码放入已允许域名下的测试页面，再正常操作页面或调用 SeeRay.push() 触发测试事件。不会记录 SeeRay 分析数据；调试日志不包含查询参数或事件属性。',
            ),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const Divider(height: 24),
          Row(
            children: [
              Expanded(
                child: Text(
                  context.tr('Tag events', '标签事件'),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              Text(
                context.tr('Refreshes every 2 seconds', '每 2 秒刷新'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 8),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _events.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.ads_click, size: 36),
                        const SizedBox(height: 8),
                        Text(
                          context.tr(
                            'Waiting for the test page…',
                            '等待测试页面触发事件…',
                          ),
                        ),
                        Text(
                          context.tr(
                            'Install the snippet above to begin.',
                            '先在测试页面安装上方代码。',
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: _events.length,
                    itemBuilder: (context, index) =>
                        _eventTile(context, _events[index]),
                  ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: _stopping ? null : _stop,
        child: Text(context.tr('Stop preview and close', '停止预览并关闭')),
      ),
    ],
  );
}
