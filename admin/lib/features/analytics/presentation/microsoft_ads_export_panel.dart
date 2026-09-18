import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_i18n.dart';
import '../../auth/application/auth_controller.dart';
import '../application/analytics_attribution.dart';
import '../application/offline_conversions.dart';

class MicrosoftAdsOfflineExportPanel extends ConsumerStatefulWidget {
  const MicrosoftAdsOfflineExportPanel({
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
  ConsumerState<MicrosoftAdsOfflineExportPanel> createState() =>
      _MicrosoftAdsOfflineExportPanelState();
}

class _MicrosoftAdsOfflineExportPanelState
    extends ConsumerState<MicrosoftAdsOfflineExportPanel> {
  final _tagId = TextEditingController();
  final _currency = TextEditingController(text: 'USD');
  final _token = TextEditingController();
  final _eventName = TextEditingController();
  MicrosoftAdsConversionImportPreview? _preview;
  String? _goalId;
  String? _error;
  String? _result;
  bool _consentConfirmed = false;
  bool _busy = false;
  bool _initialized = false;

  @override
  void dispose() {
    _tagId.dispose();
    _currency.dispose();
    _token.dispose();
    _eventName.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final configAsync = ref.watch(
      microsoftAdsConversionConfigProvider(widget.siteId),
    );
    if (!_initialized && configAsync.hasValue) {
      final config = configAsync.value!;
      _tagId.text = config.tagId ?? '';
      _currency.text = config.currencyCode ?? 'USD';
      _goalId = widget.selectedGoalId;
      final mapping = config.mappingFor(_goalId);
      _eventName.text = mapping?.eventName ?? '';
      _initialized = true;
    }

    return Card(
      elevation: 0,
      child: ExpansionTile(
        leading: const Icon(Icons.ads_click_outlined),
        title: Text(
          context.tr(
            'Send conversions to Microsoft Ads',
            '回传转化到 Microsoft Ads',
          ),
        ),
        subtitle: Text(
          widget.canManage
              ? context.tr(
                  'Map a SeeRay goal to a UET event, preview a recent imported CSV, then confirm the live send.',
                  '将 SeeRay 目标映射到 UET 事件，预览近期导入的 CSV，再确认实时发送。',
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
            error: (error, stack) => _MessageCard(
              error: true,
              message: context.tr(
                'Could not load Microsoft Ads destination settings.',
                '无法加载 Microsoft Ads 接收配置。',
              ),
            ),
            data: (config) => _buildConfiguredPanel(context, config),
          ),
        ],
      ),
    );
  }

  Widget _buildConfiguredPanel(
    BuildContext context,
    MicrosoftAdsConversionConfig config,
  ) {
    final selectedGoalId = widget.goals.any((goal) => goal.id == _goalId)
        ? _goalId
        : widget.goals.any((goal) => goal.id == widget.selectedGoalId)
        ? widget.selectedGoalId
        : null;
    final mapping = config.mappingFor(selectedGoalId);
    final eligible = _preview?.eligibleRows ?? 0;
    final tooOld = _preview?.tooOldRows ?? 0;
    final future = _preview?.futureRows ?? 0;
    final canManage = widget.canManage && config.canManage;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.tr(
            'Create or choose a UET tag in Microsoft Advertising, enable Conversions API, and copy its tag-specific token. The token is encrypted on SeeRay servers and never shown again. Only the reselected MSCLKID is sent; SeeRay keeps its stored click identifier hashed.',
            '在 Microsoft Advertising 中创建或选择 UET 标记，启用 Conversions API 并复制该标记专属令牌。SeeRay 服务端会加密保存令牌且不会再次显示。仅重新选择的 MSCLKID 会发送给平台；SeeRay 存储的点击标识仍为哈希值。',
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 10,
          children: [
            _configField(
              context,
              _tagId,
              context.tr('UET tag ID', 'UET 标记 ID'),
              width: 210,
            ),
            _configField(
              context,
              _currency,
              context.tr('Currency', '币种'),
              width: 140,
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
                        ? 'Replace UET API token (optional)'
                        : 'UET Conversions API token',
                    config.credentialConfigured
                        ? '替换 UET API 令牌（可留空）'
                        : 'UET Conversions API 令牌',
                  ),
                  border: const OutlineInputBorder(),
                  isDense: true,
                  helperText: config.credentialConfigured
                      ? context.tr(
                          'Saved securely; blank keeps the current token.',
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
                label: Text('${config.tagId} · ${config.currencyCode}'),
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
          const SizedBox(height: 8),
          Text(
            context.tr(
              'Each mapped event name must exactly match a Microsoft Ads custom conversion goal. The selected SeeRay goal fixed value and configured currency are sent.',
              '映射的事件名称必须与 Microsoft Ads 自定义转化目标完全一致。发送时使用所选 SeeRay 目标的固定价值及已配置币种。',
            ),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 260,
                child: DropdownButtonFormField<String>(
                  initialValue: selectedGoalId,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: context.tr('SeeRay goal', 'SeeRay 目标'),
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: widget.goals
                      .map(
                        (goal) => DropdownMenuItem(
                          value: goal.id,
                          child: Text(goal.name),
                        ),
                      )
                      .toList(),
                  onChanged: !canManage || _busy
                      ? null
                      : (value) => setState(() {
                          _goalId = value;
                          _eventName.text =
                              config.mappingFor(value)?.eventName ?? '';
                        }),
                ),
              ),
              _configField(
                context,
                _eventName,
                context.tr('Microsoft event name', 'Microsoft 事件名称'),
                width: 260,
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
              onPressed: !canManage || _busy ? null : _chooseExportFile,
              icon: const Icon(Icons.folder_open_outlined),
              label: Text(
                context.tr(
                  'Preview imported Microsoft Ads CSV',
                  '预览已导入的 Microsoft Ads CSV',
                ),
              ),
            ),
          ),
          if (_preview != null) ...[
            const SizedBox(height: 10),
            Text(
              '${_preview!.rows.length} ${context.tr('rows', '行')} · $eligible ${context.tr('within 7 days', '在 7 天范围内')}',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            if (tooOld > 0 || future > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  context.tr(
                    '$tooOld rows are older than 7 days and $future rows have future timestamps. Replace the file before sending.',
                    '$tooOld 行早于 7 天窗口，$future 行时间在未来。请更换文件后再发送。',
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
                        '${_maskIdentifier(row.conversionId)} · ${_maskIdentifier(row.clickId)}',
                  )
                  .join('   '),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: selectedGoalId,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: context.tr('Imported goal', '导入目标'),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              items: widget.goals
                  .map(
                    (goal) => DropdownMenuItem(
                      value: goal.id,
                      child: Text(goal.name),
                    ),
                  )
                  .toList(),
              onChanged: _busy
                  ? null
                  : (value) => setState(() {
                      _goalId = value;
                      _eventName.text =
                          config.mappingFor(value)?.eventName ?? '';
                    }),
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
                  'SeeRay does not infer consent from a CRM export. This confirmation is sent with each event.',
                  'SeeRay 不会从 CRM 文件推断同意状态。此确认会随每个事件发送。',
                ),
              ),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            Text(
              context.tr(
                'This is a live send, not a dry run. Microsoft processes events only within the last 7 days; the first send also checks whether the tag token is valid. Accepted events can take several hours to appear in Ads reports.',
                '这是实时发送，不是模拟预检。Microsoft 仅处理最近 7 天内的事件；首次发送会实际验证标记令牌。已接收事件可能数小时后才出现在 Ads 报告中。',
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
                      eligible == _preview!.rows.length &&
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
          _MessageCard(message: _error!, error: true),
        ],
        if (_result != null) ...[
          const SizedBox(height: 10),
          _MessageCard(message: _result!),
        ],
      ],
    );
  }

  Widget _configField(
    BuildContext context,
    TextEditingController controller,
    String label, {
    required double width,
  }) => SizedBox(
    width: width,
    child: TextField(
      controller: controller,
      enabled: widget.canManage && !_busy,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
    ),
  );

  Future<void> _saveConfig() async {
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
    });
    try {
      await ref
          .read(apiProvider)
          .request(
            'PUT',
            '/api/v1/sites/${widget.siteId}/offline-conversions/microsoft-ads/config',
            body: {
              'tagId': _tagId.text,
              'currencyCode': _currency.text,
              'apiToken': _token.text,
            },
          );
      _token.clear();
      ref.invalidate(microsoftAdsConversionConfigProvider(widget.siteId));
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveMapping(String goalId) async {
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
    });
    try {
      await ref
          .read(apiProvider)
          .request(
            'PUT',
            '/api/v1/sites/${widget.siteId}/offline-conversions/microsoft-ads/config/goals/$goalId',
            body: {'eventName': _eventName.text},
          );
      ref.invalidate(microsoftAdsConversionConfigProvider(widget.siteId));
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removeMapping(String goalId) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(apiProvider)
          .request(
            'DELETE',
            '/api/v1/sites/${widget.siteId}/offline-conversions/microsoft-ads/config/goals/$goalId',
          );
      ref.invalidate(microsoftAdsConversionConfigProvider(widget.siteId));
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removeConfig() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          context.tr('Disconnect Microsoft Ads?', '断开 Microsoft Ads？'),
        ),
        content: Text(
          context.tr(
            'This removes the encrypted UET token and tag settings. Imported conversions and goal mappings remain.',
            '这会删除加密 UET 令牌和标记配置，但保留已导入转化及目标映射。',
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
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
    });
    try {
      await ref
          .read(apiProvider)
          .request(
            'DELETE',
            '/api/v1/sites/${widget.siteId}/offline-conversions/microsoft-ads/config',
          );
      _token.clear();
      ref.invalidate(microsoftAdsConversionConfigProvider(widget.siteId));
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
      if (parsed.rows.any((row) => row.platform != 'microsoft_ads')) {
        throw const FormatException(
          'Every export row must use platform microsoft_ads.',
        );
      }
      setState(() {
        _preview = MicrosoftAdsConversionImportPreview(parsed.rows);
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
            'Send ${_preview!.rows.length} conversion events to the configured UET tag. This action cannot be undone in Microsoft Ads.',
            '将向已配置的 UET 标记发送 ${_preview!.rows.length} 条转化事件。Microsoft Ads 中无法撤销此操作。',
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
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
    });
    try {
      final response = await ref
          .read(apiProvider)
          .request(
            'POST',
            '/api/v1/sites/${widget.siteId}/offline-conversions/microsoft-ads/send',
            body: {
              'goalId': goalId,
              'consentConfirmed': true,
              'rows': _preview!.rows.map((row) => row.toJson()).toList(),
            },
          );
      final result = MicrosoftAdsTransferResult.fromJson(
        Map<String, dynamic>.from(response as Map),
      );
      if (mounted) {
        setState(() {
          _result = context.tr(
            '${result.eventsReceived} of ${result.rowsProcessed} events accepted${result.validationWarnings.isEmpty ? '' : ' · ${result.validationWarnings.length} optional-field warnings'}',
            '已接收 ${result.eventsReceived}/${result.rowsProcessed} 条事件${result.validationWarnings.isEmpty ? '' : ' · ${result.validationWarnings.length} 条可选字段警告'}',
          );
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _maskIdentifier(String value) => value.length <= 8
      ? '••••'
      : '${value.substring(0, 4)}…${value.substring(value.length - 4)}';
}

class MicrosoftAdsConversionImportPreview {
  const MicrosoftAdsConversionImportPreview(this.rows);

  final List<OfflineConversionImportRow> rows;

  int get tooOldRows => rows.where((row) {
    final time = DateTime.parse(row.convertedAt).toUtc();
    return DateTime.now().toUtc().difference(time) > const Duration(days: 7);
  }).length;

  int get futureRows => rows.where((row) {
    final time = DateTime.parse(row.convertedAt).toUtc();
    return time.isAfter(DateTime.now().toUtc().add(const Duration(minutes: 5)));
  }).length;

  int get eligibleRows => rows.length - tooOldRows - futureRows;
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({required this.message, this.error = false});

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
