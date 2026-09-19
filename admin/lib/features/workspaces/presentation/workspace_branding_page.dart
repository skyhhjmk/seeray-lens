import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_i18n.dart';
import '../../../core/network/seeray_api.dart';
import '../../../shared/presentation/app_back_button.dart';
import '../../../shared/presentation/page_help_button.dart';
import '../../auth/application/auth_controller.dart';
import '../application/workspace_controller.dart';

class WorkspaceBrandingPage extends ConsumerStatefulWidget {
  const WorkspaceBrandingPage({required this.workspaceId, super.key});

  final String workspaceId;

  @override
  ConsumerState<WorkspaceBrandingPage> createState() =>
      _WorkspaceBrandingPageState();
}

class _WorkspaceBrandingPageState extends ConsumerState<WorkspaceBrandingPage> {
  final _formKey = GlobalKey<FormState>();
  final _brandName = TextEditingController();
  final _accentColor = TextEditingController();
  final _logoUrl = TextEditingController();
  bool _canManage = false;
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String? _notice;

  static const _presets = <String>[
    '#2855D9',
    '#0F766E',
    '#7C3AED',
    '#C2410C',
    '#BE123C',
  ];

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_load);
  }

  @override
  void dispose() {
    _brandName.dispose();
    _accentColor.dispose();
    _logoUrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await ref
          .read(apiProvider)
          .request('GET', '/api/v1/workspaces/${widget.workspaceId}/branding');
      if (data is! Map) {
        throw const FormatException('Invalid branding response');
      }
      _brandName.text = data['brandName'] as String? ?? '';
      _accentColor.text = data['brandAccentColor'] as String? ?? '';
      _logoUrl.text = data['brandLogoUrl'] as String? ?? '';
      if (!mounted) return;
      setState(() {
        _canManage = data['canManage'] as bool? ?? false;
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

  Future<void> _save() async {
    if (!_canManage || !_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
      _notice = null;
    });
    try {
      await ref
          .read(apiProvider)
          .request(
            'PATCH',
            '/api/v1/workspaces/${widget.workspaceId}/branding',
            body: {
              'brandName': _brandName.text.trim().isEmpty
                  ? null
                  : _brandName.text.trim(),
              'brandAccentColor': _accentColor.text.trim().isEmpty
                  ? null
                  : _accentColor.text.trim().toUpperCase(),
              'brandLogoUrl': _logoUrl.text.trim().isEmpty
                  ? null
                  : _logoUrl.text.trim(),
            },
          );
      await ref.read(workspaceProvider.notifier).load();
      if (!mounted) return;
      setState(() {
        _saving = false;
        _notice = context.tr('Branding saved.', '品牌设置已保存。');
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error is ApiFailure ? error.message : '$error';
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: const AppBackButton(fallback: '/workspaces'),
      title: Text(context.tr('Workspace branding', '工作区品牌设置')),
      actions: [
        const PageHelpButton(
          englishTitle: 'Workspace branding',
          chineseTitle: '工作区品牌设置',
          englishBody:
              'Set the name, accent color and optional logo that should represent this workspace in the admin experience. Branding is workspace-scoped and does not change tracked-site data.',
          chineseBody: '设置管理界面中代表该工作区的名称、强调色和可选 Logo。品牌设置只属于工作区，不会改变已采集的站点数据。',
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
        : _error != null && !_canManage
        ? _errorBody(context)
        : _body(context),
  );

  Widget _body(BuildContext context) => Form(
    key: _formKey,
    child: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (!_canManage)
          Card(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: ListTile(
              leading: const Icon(Icons.lock_outline),
              title: Text(context.tr('Owner-only settings', '仅所有者可修改')),
              subtitle: Text(
                context.tr(
                  'You can preview the current branding, but only the workspace owner can change it.',
                  '你可以预览当前品牌设置，但只有工作区所有者可以修改。',
                ),
              ),
            ),
          ),
        if (_error != null) _messageCard(context, _error!, true),
        if (_notice != null) _messageCard(context, _notice!, false),
        LayoutBuilder(
          builder: (context, constraints) {
            final editor = _editor(context);
            final preview = _preview(context);
            if (constraints.maxWidth < 760) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [editor, const SizedBox(height: 16), preview],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: editor),
                const SizedBox(width: 16),
                SizedBox(width: 320, child: preview),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: !_canManage || _saving ? null : _save,
            icon: _saving
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: Text(context.tr('Save branding', '保存品牌设置')),
          ),
        ),
      ],
    ),
  );

  Widget _editor(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr('Brand identity', '品牌标识'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 6),
          Text(
            context.tr(
              'These settings apply to the selected workspace only. Leave a field empty to use SeeRay defaults.',
              '这些设置只作用于当前工作区。留空即可使用 SeeRay 默认值。',
            ),
          ),
          const SizedBox(height: 20),
          TextFormField(
            controller: _brandName,
            enabled: _canManage,
            maxLength: 120,
            decoration: InputDecoration(
              labelText: context.tr('Display name', '显示名称'),
              helperText: context.tr(
                'Used in the admin title and workspace site header.',
                '用于管理界面标题和工作区站点页标题。',
              ),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _accentColor,
            enabled: _canManage,
            maxLength: 7,
            decoration: InputDecoration(
              labelText: context.tr('Accent color', '强调色'),
              hintText: '#2855D9',
              helperText: context.tr(
                'Use a six-digit hex color. It changes the admin color scheme.',
                '填写六位十六进制颜色，会改变管理界面的配色。',
              ),
              prefixIcon: Padding(
                padding: const EdgeInsets.all(12),
                child: _colorSwatch(_parseColor(_accentColor.text)),
              ),
            ),
            validator: (value) {
              final text = value?.trim() ?? '';
              if (text.isEmpty || RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(text)) {
                return null;
              }
              return context.tr(
                'Use a color such as #2855D9.',
                '请输入类似 #2855D9 的颜色。',
              );
            },
            onChanged: (_) => setState(() {}),
          ),
          Wrap(
            spacing: 8,
            children: [
              for (final preset in _presets)
                ActionChip(
                  avatar: _colorSwatch(_parseColor(preset), size: 16),
                  label: Text(preset),
                  onPressed: !_canManage
                      ? null
                      : () => setState(() => _accentColor.text = preset),
                ),
            ],
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _logoUrl,
            enabled: _canManage,
            maxLength: 2048,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(
              labelText: context.tr('Logo URL (optional)', 'Logo 地址（可选）'),
              hintText: 'https://cdn.example.com/brand/logo.png',
              helperText: context.tr(
                'Use an HTTPS image URL. Credentials, data URLs and fragments are not accepted.',
                '只能使用 HTTPS 图片地址，不接受凭据、data URL 和片段标识。',
              ),
            ),
            validator: (value) {
              final text = value?.trim() ?? '';
              if (text.isEmpty) return null;
              final uri = Uri.tryParse(text);
              if (uri == null ||
                  uri.scheme.toLowerCase() != 'https' ||
                  uri.host.isEmpty) {
                return context.tr(
                  'Use an HTTPS URL with a hostname.',
                  '请输入带主机名的 HTTPS 地址。',
                );
              }
              return null;
            },
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
    ),
  );

  Widget _preview(BuildContext context) {
    final color = _parseColor(_accentColor.text) ?? const Color(0xFF2855D9);
    final name = _brandName.text.trim().isEmpty
        ? context.tr('SeeRay Lens', 'SeeRay Lens')
        : _brandName.text.trim();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.tr('Live preview', '实时预览'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: color.withValues(alpha: 0.35)),
              ),
              child: Row(
                children: [
                  _logoPreview(color, name),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      name,
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              context.tr(
                'The preview uses the same workspace-scoped name and accent color that the admin shell will use after saving.',
                '保存后，管理界面会使用当前工作区的名称和强调色。',
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _logoPreview(Color color, String name) {
    final initial = name.trim().isEmpty ? 'S' : name.trim()[0].toUpperCase();
    final logo = _logoUrl.text.trim();
    final uri = Uri.tryParse(logo);
    if (uri != null &&
        uri.scheme.toLowerCase() == 'https' &&
        uri.host.isNotEmpty) {
      return ClipOval(
        child: Image.network(
          logo,
          width: 40,
          height: 40,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => CircleAvatar(
            backgroundColor: color,
            foregroundColor: Colors.white,
            child: Text(initial),
          ),
        ),
      );
    }
    return CircleAvatar(
      backgroundColor: color,
      foregroundColor: Colors.white,
      child: Text(initial),
    );
  }

  Widget _colorSwatch(Color? color, {double size = 20}) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: color ?? Colors.transparent,
      shape: BoxShape.circle,
      border: Border.all(color: Colors.black26),
    ),
  );

  Color? _parseColor(String? value) {
    if (value == null || !RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(value.trim())) {
      return null;
    }
    return Color(int.parse('FF${value.trim().substring(1)}', radix: 16));
  }

  Widget _messageCard(BuildContext context, String message, bool error) => Card(
    color: (error ? Theme.of(context).colorScheme.error : Colors.green)
        .withValues(alpha: 0.10),
    child: ListTile(
      leading: Icon(error ? Icons.error_outline : Icons.check_circle_outline),
      title: Text(message),
    ),
  );

  Widget _errorBody(BuildContext context) => Center(
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: _load,
              child: Text(context.tr('Retry', '重试')),
            ),
          ],
        ),
      ),
    ),
  );
}
