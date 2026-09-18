import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_i18n.dart';
import '../../auth/application/auth_controller.dart';

class CrashAnalyticsSetup extends ConsumerStatefulWidget {
  const CrashAnalyticsSetup({
    required this.siteId,
    required this.trackingId,
    required this.trackerUrl,
    required this.requireConsent,
    super.key,
  });

  final String siteId;
  final String trackingId;
  final String trackerUrl;
  final bool requireConsent;

  @override
  ConsumerState<CrashAnalyticsSetup> createState() =>
      _CrashAnalyticsSetupState();
}

class _CrashAnalyticsSetupState extends ConsumerState<CrashAnalyticsSetup> {
  static const _maxMapBytes = 5 * 1024 * 1024;
  late final TextEditingController _releaseController;
  late final TextEditingController _bundleController;
  List<_SourceMapRow> _maps = const [];
  bool _canManage = false;
  bool _loading = true;
  bool _uploading = false;
  String? _loadError;

  String get _path => '/api/v1/sites/${widget.siteId}/crash-source-maps';
  String get _snippet {
    final release = _releaseController.text.trim();
    final attribute =
        RegExp(r'^[A-Za-z0-9][A-Za-z0-9._+-]{0,99}$').hasMatch(release)
        ? ' data-release="$release"'
        : '';
    final consent = widget.requireConsent ? ' data-require-consent="true"' : '';
    return '<script src="${widget.trackerUrl}" data-site-id="${widget.trackingId}"$consent data-track-errors$attribute></script>';
  }

  @override
  void initState() {
    super.initState();
    _releaseController = TextEditingController()..addListener(_refreshSnippet);
    _bundleController = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadMaps());
  }

  @override
  void dispose() {
    _releaseController.dispose();
    _bundleController.dispose();
    super.dispose();
  }

  void _refreshSnippet() {
    if (mounted) setState(() {});
  }

  Future<void> _loadMaps() async {
    try {
      final response =
          await ref.read(apiProvider).request('GET', _path) as Map? ?? const {};
      if (!mounted) return;
      setState(() {
        _canManage = response['canManage'] == true;
        _maps = (response['maps'] as List? ?? const [])
            .whereType<Map>()
            .map(
              (row) => _SourceMapRow.fromJson(Map<String, dynamic>.from(row)),
            )
            .toList(growable: false);
        _loadError = null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _uploadMap() async {
    final release = _releaseController.text.trim();
    final bundlePath = _bundleController.text.trim();
    if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9._+-]{0,99}$').hasMatch(release)) {
      _message(
        context.tr('Enter a valid release identifier first.', '请先输入有效的版本标识。'),
      );
      return;
    }
    if (bundlePath.isEmpty) {
      _message(
        context.tr(
          'Enter the deployed JavaScript bundle path.',
          '请先填写线上 JavaScript bundle 路径。',
        ),
      );
      return;
    }
    try {
      final selection = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['map'],
        allowMultiple: false,
        withData: true,
      );
      if (selection == null || selection.files.isEmpty || !mounted) {
        return;
      }
      final file = selection.files.single;
      final bytes = file.bytes;
      if (bytes == null) {
        throw const FormatException('The selected file could not be read.');
      }
      if (bytes.length > _maxMapBytes) {
        throw const FormatException('Source maps must be 5 MiB or smaller.');
      }
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Choose a valid version-3 .map file.');
      }
      setState(() => _uploading = true);
      await ref
          .read(apiProvider)
          .request(
            'PUT',
            _path,
            body: {
              'releaseId': release,
              'bundlePath': bundlePath,
              'sourceMap': decoded,
            },
          );
      if (!mounted) return;
      setState(() => _uploading = false);
      _message(
        context.tr(
          'Source map saved. Future errors from this release can be symbolicated.',
          'Source map 已保存；此版本后续发生的错误可显示原始源码位置。',
        ),
      );
      await _loadMaps();
    } catch (error) {
      if (!mounted) return;
      setState(() => _uploading = false);
      _message(
        context.tr(
          'Could not upload source map: $error',
          'Source map 上传失败：$error',
        ),
      );
    }
  }

  Future<void> _deleteMap(_SourceMapRow map) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.tr('Remove source map?', '删除 Source map？')),
        content: Text(
          context.tr(
            'New errors for ${map.releaseId} will no longer be symbolicated. Existing crash reports are unchanged.',
            '删除后，版本 ${map.releaseId} 的新错误将不再进行符号化；已有崩溃报告不会改变。',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.tr('Cancel', '取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.tr('Remove', '删除')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref.read(apiProvider).request('DELETE', '$_path/${map.id}');
      if (!mounted) return;
      _message(context.tr('Source map removed.', 'Source map 已删除。'));
      await _loadMaps();
    } catch (error) {
      if (mounted) {
        _message(
          context.tr(
            'Could not remove source map: $error',
            'Source map 删除失败：$error',
          ),
        );
      }
    }
  }

  void _message(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      Text(
        context.tr('Measure browser JavaScript crashes', '采集浏览器 JavaScript 崩溃'),
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: 8),
      Text(
        context.tr(
          'Crash collection is off by default. Add data-track-errors only after reviewing your privacy notice and consent policy. The tracker records uncaught JavaScript exceptions and unhandled promise rejections; it ignores resource load errors. It never sends stack traces, document titles, referrers, query strings, or visitor/session IDs. Messages are redacted again on the server, source/page paths have common IDs removed, and native iOS/Android crashes are not included. Do not enable crash collection on sensitive pages: data-seeray-no-track does not suppress global JavaScript error hooks, and applications can put secrets into error messages.',
          '崩溃采集默认关闭。请先检查隐私告知和同意策略，再添加 data-track-errors。追踪器记录未捕获的 JavaScript 异常和未处理的 Promise 拒绝，忽略资源加载错误；不会发送 stack、页面标题、来源页、查询参数或访客/会话 ID。服务器会再次脱敏错误消息，并从页面/脚本路径中移除常见标识；不包含 iOS/Android 原生崩溃。敏感页面不要启用崩溃采集：data-seeray-no-track 不会屏蔽全局 JavaScript 错误钩子，而且应用可能把机密放入错误消息。',
        ),
      ),
      const SizedBox(height: 14),
      Card(
        elevation: 0,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.tr('Install this tracker snippet', '安装追踪代码'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _releaseController,
                decoration: InputDecoration(
                  labelText: context.tr('Release identifier', '版本标识'),
                  hintText: 'web-2026.09.18',
                  helperText: context.tr(
                    'Use the same immutable release value when uploading each bundle map.',
                    '上传每个 bundle map 时都使用相同且不可变的版本标识。',
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SelectableText(
                _snippet,
                style: const TextStyle(fontFamily: 'monospace'),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () =>
                      Clipboard.setData(ClipboardData(text: _snippet)),
                  icon: const Icon(Icons.copy),
                  label: Text(context.tr('Copy code', '复制代码')),
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 12),
      if (_canManage)
        Card(
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr(
                    'Upload a JavaScript source map',
                    '上传 JavaScript Source map',
                  ),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                Text(
                  context.tr(
                    'Match the release above and the exact pathname from the deployed bundle URL (for example /assets/app.js). The server accepts flat version-3 maps up to 5 MiB. Embedded source text is discarded; the map is retained so future errors can be mapped.',
                    '版本标识必须与上方一致，bundle 路径需填写线上脚本 URL 的 pathname（例如 /assets/app.js）。服务端接受最大 5 MiB 的扁平 version-3 map；内嵌源码会丢弃，映射数据会保留以便转换后续错误的位置。',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _bundleController,
                  decoration: InputDecoration(
                    labelText: context.tr(
                      'Deployed bundle pathname',
                      '线上 bundle 路径',
                    ),
                    hintText: '/assets/app.js',
                  ),
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: _uploading ? null : _uploadMap,
                    icon: _uploading
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.upload_file),
                    label: Text(
                      _uploading
                          ? context.tr('Uploading…', '正在上传…')
                          : context.tr('Choose .map and upload', '选择 .map 并上传'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      const SizedBox(height: 12),
      Card(
        elevation: 0,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.tr('Uploaded source maps', '已上传的 Source map'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              if (_loading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator(),
                  ),
                )
              else if (_loadError != null)
                Row(
                  children: [
                    Expanded(child: Text(_loadError!)),
                    TextButton(
                      onPressed: _loadMaps,
                      child: Text(context.tr('Retry', '重试')),
                    ),
                  ],
                )
              else if (_maps.isEmpty)
                Text(
                  context.tr(
                    'No source maps uploaded yet.',
                    '尚未上传 Source map。',
                  ),
                )
              else
                ..._maps.map(
                  (map) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.description_outlined),
                    title: Text(
                      map.bundlePath,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${map.releaseId} · ${context.tr('${map.sourceCount} source files', '${map.sourceCount} 个源码文件')}',
                    ),
                    trailing: _canManage
                        ? IconButton(
                            tooltip: context.tr('Remove', '删除'),
                            onPressed: () => _deleteMap(map),
                            icon: const Icon(Icons.delete_outline),
                          )
                        : null,
                  ),
                ),
              const Divider(),
              Text(
                context.tr(
                  'Source maps are accessible only to workspace owners and admins. Source text is not returned in crash reports; remove maps after the release is no longer active if you do not need them for diagnosis.',
                  'Source map 仅工作区所有者和管理员可管理。崩溃报告不会返回源码文本；不再需要诊断旧版本时可删除对应 map。',
                ),
              ),
            ],
          ),
        ),
      ),
    ],
  );
}

class _SourceMapRow {
  const _SourceMapRow({
    required this.id,
    required this.releaseId,
    required this.bundlePath,
    required this.sourceCount,
  });

  final String id;
  final String releaseId;
  final String bundlePath;
  final int sourceCount;

  factory _SourceMapRow.fromJson(Map<String, dynamic> json) => _SourceMapRow(
    id: json['id'] as String? ?? '',
    releaseId: json['releaseId'] as String? ?? '',
    bundlePath: json['bundlePath'] as String? ?? '',
    sourceCount: (json['sourceCount'] as num?)?.toInt() ?? 0,
  );
}
