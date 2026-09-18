import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_i18n.dart';
import '../../auth/application/auth_controller.dart';
import '../application/analytics_attribution.dart';
import '../application/offline_conversions.dart';

class XAdsOfflineExportPanel extends ConsumerStatefulWidget {
  const XAdsOfflineExportPanel({
    required this.siteId,
    required this.canManage,
    required this.goals,
    required this.selectedGoalId,
    super.key,
  });

  final String siteId;
  final bool canManage;
  final List<AttributionGoal> goals;
  final String? selectedGoalId;

  @override
  ConsumerState<XAdsOfflineExportPanel> createState() =>
      _XAdsOfflineExportPanelState();
}

class _XAdsOfflineExportPanelState
    extends ConsumerState<XAdsOfflineExportPanel> {
  final _pixelId = TextEditingController();
  final _currency = TextEditingController(text: 'USD');
  final _token = TextEditingController();
  final _eventId = TextEditingController();
  OfflineConversionImportPreview? _preview;
  String? _goalId;
  String? _error;
  String? _result;
  bool _consentConfirmed = false;
  bool _busy = false;
  bool _initialized = false;

  @override
  void dispose() {
    _pixelId.dispose();
    _currency.dispose();
    _token.dispose();
    _eventId.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final configAsync = ref.watch(xAdsConversionConfigProvider(widget.siteId));
    if (!_initialized && configAsync.hasValue) {
      final config = configAsync.value!;
      _pixelId.text = config.pixelId ?? '';
      _currency.text = config.currencyCode ?? 'USD';
      _goalId = widget.selectedGoalId;
      _eventId.text = config.mappingFor(_goalId)?.eventId ?? '';
      _initialized = true;
    }
    return Card(
      elevation: 0,
      child: ExpansionTile(
        leading: const Icon(Icons.ads_click_outlined),
        title: Text(context.tr('Send conversions to X Ads', '回传转化到 X Ads')),
        subtitle: Text(
          widget.canManage
              ? context.tr(
                  'Map a SeeRay goal to an X Events Manager event, preview imported click IDs, and confirm each live send.',
                  '将 SeeRay 目标映射到 X Events Manager 事件，预览已导入点击 ID 后再确认实时发送。',
                )
              : context.tr(
                  'Only workspace owners and admins can configure or send conversions.',
                  '仅工作区所有者和管理员可以配置或发送转化。',
                ),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          configAsync.when(
            loading: () => const LinearProgressIndicator(),
            error: (error, stack) => _XAdsMessage(
              error: true,
              message: context.tr(
                'Could not load X destination settings.',
                '无法加载 X 接收配置。',
              ),
            ),
            data: (config) => _buildPanel(context, config),
          ),
        ],
      ),
    );
  }

  Widget _buildPanel(BuildContext context, XAdsConversionConfig config) {
    final selectedGoalId = widget.goals.any((goal) => goal.id == _goalId)
        ? _goalId
        : widget.goals.any((goal) => goal.id == widget.selectedGoalId)
        ? widget.selectedGoalId
        : null;
    final mapping = config.mappingFor(selectedGoalId);
    final canManage = widget.canManage && config.canManage;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.tr(
            'Connect the X Pixel ID and Conversion API access token. The token is encrypted at rest. Only consent-confirmed, already-imported twclid rows that match a tracked click on this site are eligible; SeeRay sends no email, phone, IP address, user agent, visitor ID, or session ID.',
            '填写 X Pixel ID 和 Conversion API 访问令牌。令牌会加密保存。仅发送已明确确认同意、已导入且匹配本站已采集点击的 twclid；SeeRay 不会发送邮箱、电话、IP、用户代理、访客 ID 或会话 ID。',
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 10,
          children: [
            _field(
              _pixelId,
              context.tr('X Pixel ID', 'X Pixel ID'),
              width: 240,
              enabled: canManage && !_busy,
            ),
            _field(
              _currency,
              context.tr('ISO currency', 'ISO 币种'),
              width: 140,
              enabled: canManage && !_busy,
            ),
            SizedBox(
              width: 360,
              child: TextField(
                controller: _token,
                enabled: canManage && !_busy,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: context.tr(
                    config.credentialConfigured
                        ? 'Replace X Pixel access token (optional)'
                        : 'X Conversion API access token',
                    config.credentialConfigured
                        ? '替换 X Pixel 访问令牌（可留空）'
                        : 'X Conversion API 访问令牌',
                  ),
                  border: const OutlineInputBorder(),
                  isDense: true,
                  helperText: config.credentialConfigured
                      ? context.tr(
                          'Encrypted on the server; blank keeps the current token.',
                          '服务端加密保存；留空则保留当前令牌。',
                        )
                      : null,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: canManage && !_busy ? _saveConfig : null,
              icon: const Icon(Icons.save_outlined),
              label: Text(context.tr('Save destination', '保存接收配置')),
            ),
            if (config.configured)
              Chip(
                avatar: const Icon(Icons.check_circle_outline, size: 18),
                label: Text('X · ${config.pixelId} · ${config.currencyCode}'),
              ),
            if (config.configured)
              TextButton.icon(
                onPressed: canManage && !_busy ? _removeConfig : null,
                icon: const Icon(Icons.link_off_outlined),
                label: Text(context.tr('Disconnect', '断开连接')),
              ),
          ],
        ),
        if (config.configured) ...[
          const Divider(height: 28),
          Text(
            context.tr('Goal-to-event mapping', '目标与事件映射'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            context.tr(
              'Enter the Event ID created in X Ads Events Manager. The selected SeeRay goal fixed value and configured currency are sent with a stable conversion ID.',
              '填写在 X Ads Events Manager 创建的 Event ID。发送时使用所选 SeeRay 目标的固定价值、配置币种和稳定 conversion ID。',
            ),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _goalSelector(selectedGoalId, canManage),
              _field(
                _eventId,
                context.tr(
                  'X Events Manager Event ID',
                  'X Events Manager Event ID',
                ),
                width: 330,
                enabled: canManage && !_busy,
              ),
              FilledButton.tonalIcon(
                onPressed: canManage && !_busy && selectedGoalId != null
                    ? () => _saveMapping(selectedGoalId)
                    : null,
                icon: const Icon(Icons.link_outlined),
                label: Text(context.tr('Save mapping', '保存映射')),
              ),
            ],
          ),
          if (config.goalMappings.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: config.goalMappings
                  .map(
                    (item) => InputChip(
                      avatar: const Icon(Icons.compare_arrows, size: 18),
                      label: Text('${item.goalName} → ${item.eventId}'),
                      onDeleted: !canManage || _busy
                          ? null
                          : () => _removeMapping(item.goalId),
                    ),
                  )
                  .toList(),
            ),
          ],
          const Divider(height: 28),
          Text(
            context.tr('Send imported conversions', '发送已导入转化'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            context.tr(
              'Select the same X Ads CSV rows already imported into SeeRay. The server rechecks the import, site click match, and 30-day maximum click attribution window before sending.',
              '选择此前已导入 SeeRay 的同一批 X Ads CSV 记录。发送前服务端会重新核验导入记录、本站点击匹配和 30 天最大点击归因窗口。',
            ),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: canManage && !_busy ? _chooseExportFile : null,
                icon: const Icon(Icons.upload_file_outlined),
                label: Text(
                  context.tr('Preview imported X Ads CSV', '预览已导入的 X Ads CSV'),
                ),
              ),
              if (_preview != null)
                Chip(
                  avatar: const Icon(Icons.table_rows_outlined, size: 18),
                  label: Text(
                    context.tr(
                      '${_preview!.rows.length} rows',
                      '${_preview!.rows.length} 行',
                    ),
                  ),
                ),
            ],
          ),
          if (_preview != null) ...[
            const SizedBox(height: 10),
            Container(
              constraints: const BoxConstraints(maxHeight: 160),
              decoration: BoxDecoration(
                border: Border.all(color: Theme.of(context).dividerColor),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _preview!.rows.length,
                itemBuilder: (context, index) {
                  final row = _preview!.rows[index];
                  return ListTile(
                    dense: true,
                    leading: Text('${index + 1}'),
                    title: Text(_mask(row.conversionId)),
                    subtitle: Text(
                      '${_mask(row.clickId)} · ${row.convertedAt}',
                    ),
                  );
                },
              ),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _consentConfirmed,
              onChanged: !canManage || _busy
                  ? null
                  : (value) =>
                        setState(() => _consentConfirmed = value ?? false),
              title: Text(
                context.tr(
                  'I confirm these rows are permitted for ad-storage and conversion measurement.',
                  '我确认这些记录已获准用于广告存储和转化衡量。',
                ),
              ),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            FilledButton.icon(
              onPressed:
                  canManage &&
                      !_busy &&
                      _consentConfirmed &&
                      selectedGoalId != null &&
                      mapping != null
                  ? _confirmAndSend
                  : null,
              icon: const Icon(Icons.send_outlined),
              label: Text(context.tr('Send to X Ads', '发送到 X Ads')),
            ),
          ],
        ],
        if (_busy) const LinearProgressIndicator(),
        if (_error != null) ...[
          const SizedBox(height: 10),
          _XAdsMessage(message: _error!, error: true),
        ],
        if (_result != null) ...[
          const SizedBox(height: 10),
          _XAdsMessage(message: _result!),
        ],
      ],
    );
  }

  Widget _goalSelector(String? selected, bool enabled) => SizedBox(
    width: 250,
    child: DropdownButtonFormField<String>(
      initialValue: selected,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: context.tr('SeeRay goal', 'SeeRay 目标'),
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      items: widget.goals
          .map(
            (goal) => DropdownMenuItem(value: goal.id, child: Text(goal.name)),
          )
          .toList(),
      onChanged: !enabled
          ? null
          : (value) => setState(() {
              _goalId = value;
              _eventId.text =
                  ref
                      .read(xAdsConversionConfigProvider(widget.siteId))
                      .value
                      ?.mappingFor(value)
                      ?.eventId ??
                  '';
            }),
    ),
  );

  Widget _field(
    TextEditingController controller,
    String label, {
    double width = 250,
    bool enabled = true,
  }) => SizedBox(
    width: width,
    child: TextField(
      controller: controller,
      enabled: enabled,
      autocorrect: false,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
    ),
  );

  Future<void> _saveConfig() async {
    final currency = _currency.text.trim().toUpperCase();
    if (!RegExp(r'^[A-Z]{3}$').hasMatch(currency) ||
        _pixelId.text.trim().isEmpty) {
      setState(
        () => _error = context.tr(
          'Enter an X Pixel ID and a three-letter ISO currency code.',
          '请输入 X Pixel ID 和三位 ISO 币种代码。',
        ),
      );
      return;
    }
    await _run(() async {
      await ref
          .read(apiProvider)
          .request(
            'PUT',
            '/api/v1/sites/${widget.siteId}/offline-conversions/x-ads/config',
            body: {
              'pixelId': _pixelId.text.trim(),
              'currencyCode': currency,
              'accessToken': _token.text,
            },
          );
      _token.clear();
      ref.invalidate(xAdsConversionConfigProvider(widget.siteId));
    });
  }

  Future<void> _removeConfig() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.tr('Disconnect X Ads?', '断开 X Ads？')),
        content: Text(
          context.tr(
            'This removes the encrypted token and all goal mappings.',
            '这会删除加密令牌及所有目标映射。',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.tr('Cancel', '取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.tr('Disconnect', '断开')),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    await _run(() async {
      await ref
          .read(apiProvider)
          .request(
            'DELETE',
            '/api/v1/sites/${widget.siteId}/offline-conversions/x-ads/config',
          );
      ref.invalidate(xAdsConversionConfigProvider(widget.siteId));
    });
  }

  Future<void> _saveMapping(String? goalId) async {
    final eventId = _eventId.text.trim();
    if (goalId == null ||
        !RegExp(r'^[A-Za-z0-9._~-]{1,256}$').hasMatch(eventId)) {
      setState(
        () => _error = context.tr(
          'Choose a goal and enter its X Events Manager Event ID.',
          '请选择目标并填写对应的 X Events Manager Event ID。',
        ),
      );
      return;
    }
    await _run(() async {
      await ref
          .read(apiProvider)
          .request(
            'PUT',
            '/api/v1/sites/${widget.siteId}/offline-conversions/x-ads/config/goals/$goalId',
            body: {'eventId': eventId},
          );
      ref.invalidate(xAdsConversionConfigProvider(widget.siteId));
    });
  }

  Future<void> _removeMapping(String goalId) async {
    await _run(() async {
      await ref
          .read(apiProvider)
          .request(
            'DELETE',
            '/api/v1/sites/${widget.siteId}/offline-conversions/x-ads/config/goals/$goalId',
          );
      ref.invalidate(xAdsConversionConfigProvider(widget.siteId));
    });
  }

  Future<void> _chooseExportFile() async {
    try {
      final selection = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['csv'],
        allowMultiple: false,
        withData: true,
      );
      if (selection == null || selection.files.isEmpty || !mounted) return;
      final bytes = selection.files.single.bytes;
      if (bytes == null ||
          bytes.length > OfflineConversionImportPreview.maximumBytes) {
        throw const FormatException(
          'Choose a readable CSV file no larger than 2 MiB.',
        );
      }
      final parsed = OfflineConversionImportPreview.parse(utf8.decode(bytes));
      if (parsed.rows.any((row) => row.platform != 'x_ads')) {
        throw const FormatException(
          'Every export row must use platform x_ads.',
        );
      }
      if (parsed.rows.length > 2_000) {
        throw const FormatException(
          'A send can contain at most 2,000 X conversion rows.',
        );
      }
      setState(() {
        _preview = parsed;
        _goalId = widget.selectedGoalId;
        _consentConfirmed = false;
        _error = null;
        _result = null;
      });
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = context.tr(
            'Could not open that CSV file.',
            '无法读取该 CSV 文件。',
          ),
        );
      }
    }
  }

  Future<void> _confirmAndSend() async {
    final goalId = _goalId ?? widget.selectedGoalId;
    if (goalId == null || _preview == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.tr('Send live conversion events?', '发送实时转化事件？')),
        content: Text(
          context.tr(
            'Send ${_preview!.rows.length} conversions to the mapped X event? X Ads cannot undo accepted conversion events.',
            '将 ${_preview!.rows.length} 条转化发送到已映射的 X 事件？X Ads 无法撤销已接收的转化事件。',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.tr('Cancel', '取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.tr('Send events', '发送事件')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _run(() async {
      final response = await ref
          .read(apiProvider)
          .request(
            'POST',
            '/api/v1/sites/${widget.siteId}/offline-conversions/x-ads/send',
            body: {
              'goalId': goalId,
              'consentConfirmed': true,
              'rows': _preview!.rows.map((row) => row.toJson()).toList(),
            },
          );
      final result = XAdsTransferResult.fromJson(
        Map<String, dynamic>.from(response as Map),
      );
      if (!mounted) return;
      _result = context.tr(
        '${result.eventsReceived} of ${result.rowsProcessed} events accepted by X Ads.',
        'X Ads 已接收 ${result.eventsReceived}/${result.rowsProcessed} 条事件。',
      );
    });
  }

  Future<void> _run(Future<void> Function() operation) async {
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
    });
    try {
      await operation();
      if (mounted) setState(() {});
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _mask(String value) => value.length <= 8
      ? '••••'
      : '${value.substring(0, 4)}…${value.substring(value.length - 4)}';
}

class _XAdsMessage extends StatelessWidget {
  const _XAdsMessage({required this.message, this.error = false});

  final String message;
  final bool error;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: error
          ? Theme.of(context).colorScheme.errorContainer
          : Theme.of(context).colorScheme.primaryContainer,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(message),
  );
}
