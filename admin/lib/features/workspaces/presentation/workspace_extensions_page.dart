import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_i18n.dart';
import '../../../core/network/seeray_api.dart';
import '../../../shared/presentation/app_back_button.dart';
import '../../../shared/presentation/page_help_button.dart';
import '../../auth/application/auth_controller.dart';

class WorkspaceExtensionsPage extends ConsumerStatefulWidget {
  const WorkspaceExtensionsPage({required this.workspaceId, super.key});

  final String workspaceId;

  @override
  ConsumerState<WorkspaceExtensionsPage> createState() =>
      _WorkspaceExtensionsPageState();
}

class _WorkspaceExtensionsPageState
    extends ConsumerState<WorkspaceExtensionsPage> {
  static const _subscriptionLabels = <String, String>{
    'analytics.event': 'Analytics events / 分析事件',
    'analytics.page_view': 'Page views / 页面浏览',
    'diagnostics.alert': 'Diagnostic alerts / 诊断告警',
  };

  List<Map<String, dynamic>> _extensions = const [];
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
            '/api/v1/workspaces/${widget.workspaceId}/extensions',
          );
      if (data is! List) {
        throw const FormatException('Invalid extensions response');
      }
      if (!mounted) return;
      setState(() {
        _extensions = data
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList(growable: false);
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
      title: Text(context.tr('Workspace extensions', '工作区扩展')),
      actions: [
        const PageHelpButton(
          englishTitle: 'Workspace extensions',
          chineseTitle: '工作区扩展',
          englishBody:
              'Register a HTTPS extension endpoint, choose the events it may receive, and rotate its signing secret. SeeRay Lens never executes extension code.',
          chineseBody:
              '注册 HTTPS 扩展端点并选择可接收的事件，支持轮换签名密钥。SeeRay Lens 不会在服务端执行扩展代码。',
        ),
        const LanguageMenu(),
        IconButton(
          tooltip: context.tr('Refresh', '刷新'),
          onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: _loading ? null : _create,
      icon: const Icon(Icons.add_link),
      label: Text(context.tr('Add extension', '添加扩展')),
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
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          context.tr(
            'Signed webhooks for product extensions',
            '面向产品扩展的签名 Webhook',
          ),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 6),
        Text(
          context.tr(
            'Only HTTPS endpoints are accepted. Secrets are shown once when created or rotated.',
            '仅接受 HTTPS 端点。创建或轮换时只显示一次密钥。',
          ),
        ),
        const SizedBox(height: 16),
        if (_extensions.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                context.tr('No extensions registered yet.', '还没有注册扩展。'),
              ),
            ),
          ),
        for (final extension in _extensions) ...[
          _extensionCard(context, extension),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  Widget _extensionCard(BuildContext context, Map<String, dynamic> extension) {
    final status = extension['status'] as String? ?? 'disabled';
    final archived = status == 'archived';
    final subscriptions =
        (extension['subscriptions'] as List?)?.whereType<String>().toList() ??
        const [];
    final color = status == 'enabled'
        ? Colors.green
        : status == 'archived'
        ? Colors.grey
        : Colors.orange;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.extension_outlined, color: color),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${extension['name']}  v${extension['version']}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Chip(
                  label: Text(_statusLabel(context, status)),
                  side: BorderSide(color: color.withValues(alpha: .5)),
                  labelStyle: TextStyle(color: color),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${extension['extensionKey']}  ·  ${extension['endpointUrl']}',
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: subscriptions
                  .map(
                    (value) =>
                        Chip(label: Text(_subscriptionLabels[value] ?? value)),
                  )
                  .toList(),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: archived ? null : () => _edit(extension),
                  icon: const Icon(Icons.edit_outlined),
                  label: Text(context.tr('Edit', '编辑')),
                ),
                OutlinedButton.icon(
                  onPressed: archived ? null : () => _test(extension),
                  icon: const Icon(Icons.send_outlined),
                  label: Text(context.tr('Send test', '发送测试')),
                ),
                OutlinedButton.icon(
                  onPressed: archived ? null : () => _rotate(extension),
                  icon: const Icon(Icons.key_outlined),
                  label: Text(context.tr('Rotate secret', '轮换密钥')),
                ),
                TextButton.icon(
                  onPressed: archived ? null : () => _archive(extension),
                  icon: const Icon(Icons.archive_outlined),
                  label: Text(context.tr('Archive', '归档')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _statusLabel(BuildContext context, String status) => switch (status) {
    'enabled' => context.tr('Enabled', '启用'),
    'archived' => context.tr('Archived', '已归档'),
    _ => context.tr('Disabled', '停用'),
  };

  Future<void> _create() async {
    final values = await _showForm(null);
    if (values == null) return;
    try {
      final result =
          await ref
                  .read(apiProvider)
                  .request(
                    'POST',
                    '/api/v1/workspaces/${widget.workspaceId}/extensions',
                    body: values,
                  )
              as Map;
      await _load();
      if (mounted && result['secret'] is String) {
        _showSecret(result['secret'] as String);
      }
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _edit(Map<String, dynamic> extension) async {
    final values = await _showForm(extension);
    if (values == null) return;
    try {
      await ref
          .read(apiProvider)
          .request(
            'PUT',
            '/api/v1/workspaces/${widget.workspaceId}/extensions/${extension['id']}',
            body: values,
          );
      await _load();
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _archive(Map<String, dynamic> extension) async {
    try {
      await ref
          .read(apiProvider)
          .request(
            'POST',
            '/api/v1/workspaces/${widget.workspaceId}/extensions/${extension['id']}/archive',
          );
      await _load();
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _rotate(Map<String, dynamic> extension) async {
    try {
      final result =
          await ref
                  .read(apiProvider)
                  .request(
                    'POST',
                    '/api/v1/workspaces/${widget.workspaceId}/extensions/${extension['id']}/rotate-secret',
                  )
              as Map;
      if (mounted && result['secret'] is String) {
        _showSecret(result['secret'] as String);
      }
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _test(Map<String, dynamic> extension) async {
    try {
      final result =
          await ref
                  .read(apiProvider)
                  .request(
                    'POST',
                    '/api/v1/workspaces/${widget.workspaceId}/extensions/${extension['id']}/test',
                  )
              as Map;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${context.tr('Test', '测试')} ${result['status']} · ${result['latencyMs']} ms',
          ),
        ),
      );
    } catch (error) {
      _showError(error);
    }
  }

  Future<Map<String, dynamic>?> _showForm(
    Map<String, dynamic>? existing,
  ) async {
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) =>
          _ExtensionForm(existing: existing, labels: _subscriptionLabels),
    );
  }

  void _showSecret(String secret) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(context.tr('Copy this secret now', '请立即复制此密钥')),
        content: SelectableText(secret),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.tr('Done', '完成')),
          ),
        ],
      ),
    );
  }

  void _showError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error is ApiFailure ? error.message : '$error')),
    );
  }
}

class _ExtensionForm extends StatefulWidget {
  const _ExtensionForm({required this.existing, required this.labels});
  final Map<String, dynamic>? existing;
  final Map<String, String> labels;

  @override
  State<_ExtensionForm> createState() => _ExtensionFormState();
}

class _ExtensionFormState extends State<_ExtensionForm> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _key;
  late final TextEditingController _name;
  late final TextEditingController _version;
  late final TextEditingController _endpoint;
  late Set<String> _subscriptions;
  String _status = 'enabled';

  @override
  void initState() {
    super.initState();
    final value = widget.existing;
    _key = TextEditingController(text: value?['extensionKey'] as String? ?? '');
    _name = TextEditingController(text: value?['name'] as String? ?? '');
    _version = TextEditingController(
      text: value?['version'] as String? ?? '1.0.0',
    );
    _endpoint = TextEditingController(
      text: value?['endpointUrl'] as String? ?? 'https://',
    );
    _subscriptions = {
      ...((value?['subscriptions'] as List?)?.whereType<String>() ?? const []),
    };
    _status = value?['status'] as String? ?? 'enabled';
  }

  @override
  void dispose() {
    _key.dispose();
    _name.dispose();
    _version.dispose();
    _endpoint.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      context.tr(
        widget.existing == null ? 'Add extension' : 'Edit extension',
        widget.existing == null ? '添加扩展' : '编辑扩展',
      ),
    ),
    content: SizedBox(
      width: 520,
      child: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.existing == null)
                TextFormField(
                  controller: _key,
                  decoration: const InputDecoration(labelText: 'Extension key'),
                  validator: (value) =>
                      value == null ||
                          !RegExp(
                            r'^[a-z][a-z0-9._-]{1,79}$',
                          ).hasMatch(value.trim())
                      ? 'Use 2-80 lowercase characters'
                      : null,
                ),
              TextFormField(
                controller: _name,
                decoration: InputDecoration(
                  labelText: context.tr('Name', '名称'),
                ),
                validator: _required,
              ),
              TextFormField(
                controller: _version,
                decoration: InputDecoration(
                  labelText: context.tr('Version', '版本'),
                ),
                validator: _required,
              ),
              TextFormField(
                controller: _endpoint,
                decoration: const InputDecoration(labelText: 'HTTPS endpoint'),
                validator: (value) =>
                    value == null || !value.trim().startsWith('https://')
                    ? 'HTTPS endpoint required'
                    : null,
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  context.tr('Subscriptions', '订阅事件'),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              for (final entry in widget.labels.entries)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _subscriptions.contains(entry.key),
                  title: Text(entry.value),
                  onChanged: (selected) => setState(
                    () => selected == true
                        ? _subscriptions.add(entry.key)
                        : _subscriptions.remove(entry.key),
                  ),
                ),
              if (widget.existing != null)
                DropdownButtonFormField<String>(
                  initialValue: _status,
                  decoration: InputDecoration(
                    labelText: context.tr('Lifecycle status', '生命周期状态'),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'enabled',
                      child: Text('Enabled / 启用'),
                    ),
                    DropdownMenuItem(
                      value: 'disabled',
                      child: Text('Disabled / 停用'),
                    ),
                  ],
                  onChanged: (value) =>
                      setState(() => _status = value ?? 'disabled'),
                ),
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
      FilledButton(onPressed: _submit, child: Text(context.tr('Save', '保存'))),
    ],
  );

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'Required / 必填' : null;

  void _submit() {
    if (!_form.currentState!.validate()) return;
    Navigator.pop(context, {
      if (widget.existing == null) 'extensionKey': _key.text.trim(),
      'name': _name.text.trim(),
      'version': _version.text.trim(),
      'endpointUrl': _endpoint.text.trim(),
      'subscriptions': _subscriptions.toList(),
      if (widget.existing != null) 'status': _status,
    });
  }
}
