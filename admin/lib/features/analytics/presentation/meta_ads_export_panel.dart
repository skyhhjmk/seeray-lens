import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_i18n.dart';
import '../../auth/application/auth_controller.dart';
import '../application/analytics_attribution.dart';
import '../application/offline_conversions.dart';

class MetaAdsOfflineExportPanel extends ConsumerStatefulWidget {
  const MetaAdsOfflineExportPanel({
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
  ConsumerState<MetaAdsOfflineExportPanel> createState() =>
      _MetaAdsOfflineExportPanelState();
}

class _MetaAdsOfflineExportPanelState
    extends ConsumerState<MetaAdsOfflineExportPanel> {
  final _datasetId = TextEditingController();
  final _currency = TextEditingController(text: 'USD');
  final _token = TextEditingController();
  final _eventName = TextEditingController();
  OfflineConversionImportPreview? _preview;
  String? _goalId;
  String _actionSource = 'other';
  String? _error;
  String? _result;
  bool _consentConfirmed = false;
  bool _busy = false;
  bool _initialized = false;

  @override
  void dispose() {
    _datasetId.dispose();
    _currency.dispose();
    _token.dispose();
    _eventName.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final configAsync = ref.watch(
      metaAdsConversionConfigProvider(widget.siteId),
    );
    if (!_initialized && configAsync.hasValue) {
      final config = configAsync.value!;
      _datasetId.text = config.datasetId ?? '';
      _currency.text = config.currencyCode ?? 'USD';
      _goalId = widget.selectedGoalId;
      _eventName.text = config.mappingFor(_goalId)?.eventName ?? '';
      _initialized = true;
    }
    return Card(
      elevation: 0,
      child: ExpansionTile(
        leading: const Icon(Icons.ads_click_outlined),
        title: Text(
          context.tr('Send conversions to Meta Ads', '回传转化到 Meta Ads'),
        ),
        subtitle: Text(
          widget.canManage
              ? context.tr(
                  'Configure a dataset, map goals to events, preview imported rows, then explicitly confirm the live send.',
                  '配置数据集，将目标映射到事件，预览已导入记录后，再明确确认实时发送。',
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
            error: (error, stack) => _MetaMessage(
              error: true,
              message: context.tr(
                'Could not load Meta Ads destination settings.',
                '无法加载 Meta Ads 接收配置。',
              ),
            ),
            data: (config) => _buildPanel(context, config),
          ),
        ],
      ),
    );
  }

  Widget _buildPanel(BuildContext context, MetaAdsConversionConfig config) {
    final selectedGoalId = widget.goals.any((goal) => goal.id == _goalId)
        ? _goalId
        : widget.goals.any((goal) => goal.id == widget.selectedGoalId)
        ? widget.selectedGoalId
        : null;
    final mapping = config.mappingFor(selectedGoalId);
    final canManage = widget.canManage && config.canManage;
    final eligibleRows = _preview?.eligibleRows ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.tr(
            'Connect the Meta dataset/pixel ID and an Events Manager Conversions API access token. The token is encrypted on the server and never shown again. Only consent-confirmed, imported FBCLID rows are eligible; no email, phone, visitor ID, or session ID is sent.',
            '填写 Meta 数据集/Pixel ID 和 Events Manager 中的 Conversions API 访问令牌。令牌会在服务端加密保存且不再回显。仅发送已导入且明确确认同意的 FBCLID 记录；不会发送邮箱、电话、访客 ID 或会话 ID。',
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 10,
          children: [
            _field(
              _datasetId,
              context.tr('Dataset / Pixel ID', '数据集 / Pixel ID'),
              width: 220,
              enabled: canManage && !_busy,
            ),
            _field(
              _currency,
              context.tr('ISO currency', 'ISO 币种'),
              width: 130,
              enabled: canManage && !_busy,
            ),
            SizedBox(
              width: 330,
              child: TextField(
                controller: _token,
                enabled: canManage && !_busy,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: context.tr(
                    config.credentialConfigured
                        ? 'Replace access token (optional)'
                        : 'Conversions API access token',
                    config.credentialConfigured
                        ? '替换访问令牌（可留空）'
                        : 'Conversions API 访问令牌',
                  ),
                  border: const OutlineInputBorder(),
                  isDense: true,
                  helperText: config.credentialConfigured
                      ? context.tr(
                          'Saved encrypted; blank keeps it.',
                          '已加密保存；留空则保留当前令牌。',
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
                label: Text('${config.datasetId} · ${config.currencyCode}'),
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
              'Map each enabled SeeRay goal to a Meta standard or custom event name. The goal fixed value and configured currency are sent.',
              '将每个启用的 SeeRay 目标映射到 Meta 标准事件或自定义事件名称。发送时使用目标固定价值和已配置币种。',
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
                _eventName,
                context.tr('Meta event name', 'Meta 事件名称'),
                width: 250,
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
                      label: Text('${item.goalName} → ${item.eventName}'),
                      onDeleted: !canManage || _busy
                          ? null
                          : () => _removeMapping(item.goalId),
                    ),
                  )
                  .toList(),
            ),
          ],
          const Divider(height: 28),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: canManage && !_busy ? _chooseExportFile : null,
              icon: const Icon(Icons.folder_open_outlined),
              label: Text(
                context.tr(
                  'Preview imported Meta Ads CSV',
                  '预览已导入的 Meta Ads CSV',
                ),
              ),
            ),
          ),
          if (_preview != null) ...[
            const SizedBox(height: 10),
            Text(
              '${_preview!.rows.length} ${context.tr('rows', '行')} · $eligibleRows ${context.tr('within 7 days', '在 7 天范围内')}',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            if (_preview!.tooOldRows > 0 || _preview!.futureRows > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  context.tr(
                    '${_preview!.tooOldRows} rows are older than 7 days and ${_preview!.futureRows} rows have future timestamps. Replace the file before sending.',
                    '${_preview!.tooOldRows} 行早于 7 天窗口，${_preview!.futureRows} 行时间在未来。请更换文件后再发送。',
                  ),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 5),
            Text(
              _preview!.rows
                  .take(4)
                  .map(
                    (row) =>
                        '${_mask(row.conversionId)} · ${_mask(row.clickId)}',
                  )
                  .join('   '),
            ),
            const SizedBox(height: 8),
            _goalSelector(
              selectedGoalId,
              canManage,
              label: context.tr('Imported goal', '导入目标'),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: 260,
              child: DropdownButtonFormField<String>(
                initialValue: _actionSource,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: context.tr('Conversion source', '转化来源'),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                items:
                    const [
                          'website',
                          'app',
                          'business_messaging',
                          'chat',
                          'email',
                          'phone_call',
                          'physical_store',
                          'system_generated',
                          'other',
                        ]
                        .map(
                          (source) => DropdownMenuItem(
                            value: source,
                            child: Text(source),
                          ),
                        )
                        .toList(),
                onChanged: !canManage || _busy
                    ? null
                    : (source) {
                        if (source != null) {
                          setState(() => _actionSource = source);
                        }
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
                  'I confirm these rows have consent for ad-storage and conversion measurement.',
                  '我确认这些记录已获得广告存储和转化衡量所需的同意。',
                ),
              ),
              subtitle: Text(
                context.tr(
                  'SeeRay does not infer consent from a CRM export. The server rechecks imported rows and tracked FBCLID matches before sending.',
                  'SeeRay 不会从 CRM 文件推断同意状态。发送前服务端会重新核验已导入记录和站内 FBCLID 匹配。',
                ),
              ),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            Text(
              context.tr(
                'This is a live send, not a dry run. Choose the source that best describes where each imported conversion occurred; the default is “other”. The server derives the FBCLID timestamp from the matched first-party session and keeps a stable event ID for retries.',
                '这是实时发送，不是模拟预检。请选择最符合导入转化发生位置的来源，默认是“other”。服务端从匹配的一方会话推导 FBCLID 时间戳，并使用稳定事件 ID 支持安全重试。',
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed:
                  canManage &&
                      !_busy &&
                      config.configured &&
                      mapping != null &&
                      _preview!.rows.length <= 1000 &&
                      eligibleRows == _preview!.rows.length &&
                      _consentConfirmed
                  ? _confirmAndSend
                  : null,
              icon: const Icon(Icons.send_outlined),
              label: Text(context.tr('Send conversions', '发送转化')),
            ),
          ],
        ],
        if (_error != null) ...[
          const SizedBox(height: 10),
          _MetaMessage(message: _error!, error: true),
        ],
        if (_result != null) ...[
          const SizedBox(height: 10),
          _MetaMessage(message: _result!),
        ],
      ],
    );
  }

  Widget _goalSelector(String? value, bool canManage, {String? label}) =>
      SizedBox(
        width: 260,
        child: DropdownButtonFormField<String>(
          initialValue: value,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: label ?? context.tr('SeeRay goal', 'SeeRay 目标'),
            border: const OutlineInputBorder(),
            isDense: true,
          ),
          items: widget.goals
              .map(
                (goal) =>
                    DropdownMenuItem(value: goal.id, child: Text(goal.name)),
              )
              .toList(),
          onChanged: !canManage || _busy
              ? null
              : (selected) => setState(() {
                  _goalId = selected;
                  _eventName.text =
                      ref
                          .read(metaAdsConversionConfigProvider(widget.siteId))
                          .value
                          ?.mappingFor(selected)
                          ?.eventName ??
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
    final datasetId = _datasetId.text.trim();
    final currency = _currency.text.trim().toUpperCase();
    if (!RegExp(r'^\d{1,32}$').hasMatch(datasetId) ||
        !RegExp(r'^[A-Z]{3}$').hasMatch(currency)) {
      setState(
        () => _error = context.tr(
          'Enter a numeric dataset ID and a three-letter currency code.',
          '请输入数字数据集 ID 和三位币种代码。',
        ),
      );
      return;
    }
    await _run(() async {
      await ref
          .read(apiProvider)
          .request(
            'PUT',
            '/api/v1/sites/${widget.siteId}/offline-conversions/meta-ads/config',
            body: {
              'datasetId': datasetId,
              'currencyCode': currency,
              'apiToken': _token.text,
            },
          );
      _token.clear();
      ref.invalidate(metaAdsConversionConfigProvider(widget.siteId));
    });
  }

  Future<void> _removeConfig() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.tr('Disconnect Meta Ads?', '断开 Meta Ads？')),
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
            '/api/v1/sites/${widget.siteId}/offline-conversions/meta-ads/config',
          );
      ref.invalidate(metaAdsConversionConfigProvider(widget.siteId));
    });
  }

  Future<void> _saveMapping(String? goalId) async {
    final eventName = _eventName.text.trim();
    if (goalId == null || eventName.isEmpty || eventName.length > 128) {
      setState(
        () => _error = context.tr(
          'Choose a goal and enter a Meta event name.',
          '请选择目标并填写 Meta 事件名称。',
        ),
      );
      return;
    }
    await _run(() async {
      await ref
          .read(apiProvider)
          .request(
            'PUT',
            '/api/v1/sites/${widget.siteId}/offline-conversions/meta-ads/config/goals/$goalId',
            body: {'eventName': eventName},
          );
      ref.invalidate(metaAdsConversionConfigProvider(widget.siteId));
    });
  }

  Future<void> _removeMapping(String goalId) async {
    await _run(() async {
      await ref
          .read(apiProvider)
          .request(
            'DELETE',
            '/api/v1/sites/${widget.siteId}/offline-conversions/meta-ads/config/goals/$goalId',
          );
      ref.invalidate(metaAdsConversionConfigProvider(widget.siteId));
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
      if (parsed.rows.any((row) => row.platform != 'meta_ads')) {
        throw const FormatException(
          'Every export row must use platform meta_ads.',
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
            'Send ${_preview!.rows.length} conversions to Meta dataset ${_datasetId.text.trim()}? The send cannot be undone in Meta.',
            '将 ${_preview!.rows.length} 条转化发送到 Meta 数据集 ${_datasetId.text.trim()}？发送后无法在 Meta 撤销。',
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
            '/api/v1/sites/${widget.siteId}/offline-conversions/meta-ads/send',
            body: {
              'goalId': goalId,
              'actionSource': _actionSource,
              'consentConfirmed': true,
              'rows': _preview!.rows.map((row) => row.toJson()).toList(),
            },
          );
      final result = MetaAdsTransferResult.fromJson(
        Map<String, dynamic>.from(response as Map),
      );
      if (!mounted) return;
      _result = context.tr(
        '${result.eventsReceived} of ${result.rowsProcessed} events accepted by Meta.',
        'Meta 已接收 ${result.eventsReceived}/${result.rowsProcessed} 条事件。',
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

class _MetaMessage extends StatelessWidget {
  const _MetaMessage({required this.message, this.error = false});

  final String message;
  final bool error;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: error
          ? Theme.of(context).colorScheme.errorContainer
          : Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(message),
  );
}
