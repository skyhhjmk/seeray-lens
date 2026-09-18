import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_i18n.dart';
import '../../auth/application/auth_controller.dart';
import '../application/analytics_attribution.dart';
import '../application/offline_conversions.dart';

class LinkedInAdsOfflineExportPanel extends ConsumerStatefulWidget {
  const LinkedInAdsOfflineExportPanel({
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
  ConsumerState<LinkedInAdsOfflineExportPanel> createState() =>
      _LinkedInAdsOfflineExportPanelState();
}

class _LinkedInAdsOfflineExportPanelState
    extends ConsumerState<LinkedInAdsOfflineExportPanel> {
  final _currency = TextEditingController(text: 'USD');
  final _token = TextEditingController();
  final _conversionUrn = TextEditingController();
  OfflineConversionImportPreview? _preview;
  String? _goalId;
  String? _error;
  String? _result;
  bool _consentConfirmed = false;
  bool _busy = false;
  bool _initialized = false;

  @override
  void dispose() {
    _currency.dispose();
    _token.dispose();
    _conversionUrn.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final configAsync = ref.watch(
      linkedInAdsConversionConfigProvider(widget.siteId),
    );
    if (!_initialized && configAsync.hasValue) {
      final config = configAsync.value!;
      _currency.text = config.currencyCode ?? 'USD';
      _goalId = widget.selectedGoalId;
      _conversionUrn.text = config.mappingFor(_goalId)?.conversionUrn ?? '';
      _initialized = true;
    }
    return Card(
      elevation: 0,
      child: ExpansionTile(
        leading: const Icon(Icons.ads_click_outlined),
        title: Text(
          context.tr('Send conversions to LinkedIn Ads', '回传转化到 LinkedIn Ads'),
        ),
        subtitle: Text(
          widget.canManage
              ? context.tr(
                  'Configure an OAuth token, map a goal to a conversion rule, preview imported rows, then confirm the live send.',
                  '配置 OAuth 令牌，将目标映射到转化规则，预览已导入记录后再确认实时发送。',
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
            error: (error, stack) => _LinkedInMessage(
              error: true,
              message: context.tr(
                'Could not load LinkedIn destination settings.',
                '无法加载 LinkedIn 接收配置。',
              ),
            ),
            data: (config) => _buildPanel(context, config),
          ),
        ],
      ),
    );
  }

  Widget _buildPanel(BuildContext context, LinkedInAdsConversionConfig config) {
    final selectedGoalId = widget.goals.any((goal) => goal.id == _goalId)
        ? _goalId
        : widget.goals.any((goal) => goal.id == widget.selectedGoalId)
        ? widget.selectedGoalId
        : null;
    final mapping = config.mappingFor(selectedGoalId);
    final canManage = widget.canManage && config.canManage;
    final tooOld = _preview?.linkedinTooOldRows ?? 0;
    final future = _preview?.linkedinFutureRows ?? 0;
    final eligible = (_preview?.rows.length ?? 0) - tooOld - future;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.tr(
            'Enable Enhanced conversion tracking for the LinkedIn Insight Tag so ad clicks include li_fat_id. Create an active Conversions API rule with dynamic value, associate it with campaigns, and use the ad account currency. The OAuth token needs rw_conversions and r_ads permissions and is encrypted on SeeRay servers. Only the reselected li_fat_id is sent; no email, name, IP address, visitor ID, or session ID is included.',
            '为 LinkedIn Insight Tag 启用 Enhanced conversion tracking，让广告点击包含 li_fat_id。创建启用 Conversions API 且价值类型为 dynamic 的规则并关联广告系列，币种需与广告账户一致。OAuth 令牌需要 rw_conversions 和 r_ads 权限，且会在 SeeRay 服务端加密。仅发送重新选择 CSV 中的 li_fat_id，不发送邮箱、姓名、IP、访客 ID 或会话 ID。',
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 10,
          children: [
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
                        ? 'Replace OAuth access token (optional)'
                        : 'LinkedIn Marketing API OAuth token',
                    config.credentialConfigured
                        ? '替换 OAuth 访问令牌（可留空）'
                        : 'LinkedIn Marketing API OAuth 令牌',
                  ),
                  border: const OutlineInputBorder(),
                  isDense: true,
                  helperText: config.credentialConfigured
                      ? context.tr(
                          'Saved encrypted; blank keeps the current token.',
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
                label: Text('LinkedIn · ${config.currencyCode}'),
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
            context.tr('Goal-to-conversion rule mapping', '目标与转化规则映射'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            context.tr(
              'Paste the URN of an enabled LinkedIn conversion rule configured for Conversions API and dynamic value (for example, urn:lla:llaPartnerConversion:123456). The selected SeeRay goal fixed value and currency are sent as the event value.',
              '粘贴已启用、配置为 Conversions API 且使用动态价值的 LinkedIn 转化规则 URN（例如 urn:lla:llaPartnerConversion:123456）。发送时将所选 SeeRay 目标的固定价值和币种作为事件价值。',
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
                _conversionUrn,
                context.tr('LinkedIn conversion rule URN', 'LinkedIn 转化规则 URN'),
                width: 360,
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
                      label: Text('${item.goalName} → ${item.conversionUrn}'),
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
                  'Preview imported LinkedIn Ads CSV',
                  '预览已导入的 LinkedIn Ads CSV',
                ),
              ),
            ),
          ),
          if (_preview != null) ...[
            const SizedBox(height: 10),
            Text(
              '${_preview!.rows.length} ${context.tr('rows', '行')} · $eligible ${context.tr('within the 90-day window', '在 90 天范围内')}',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            if (tooOld > 0 || future > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  context.tr(
                    '$tooOld rows are older than 90 days and $future rows have future timestamps. Replace the file before sending.',
                    '$tooOld 行早于 90 天窗口，$future 行时间在未来。请更换文件后再发送。',
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
                  'The server rechecks the imported LinkedIn rows and matching tracked clicks. LinkedIn accepts events from the past 90 days only.',
                  '服务端会重新核验已导入记录及站内匹配点击。LinkedIn 仅接受过去 90 天内的事件。',
                ),
              ),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            Text(
              context.tr(
                'This is a live send, not a dry run. Events must match a LinkedIn first-party click tracked on this site before the conversion. SeeRay sends the click ID only for matching and keeps a stable event ID for retries.',
                '这是实时发送，不是模拟预检。事件必须匹配本站在转化前采集的 LinkedIn 一方点击。SeeRay 仅为匹配而发送点击 ID，并使用稳定事件 ID 便于识别重试。',
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
                      _preview!.rows.length <= 5000 &&
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
          _LinkedInMessage(message: _error!, error: true),
        ],
        if (_result != null) ...[
          const SizedBox(height: 10),
          _LinkedInMessage(message: _result!),
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
                  _conversionUrn.text =
                      ref
                          .read(
                            linkedInAdsConversionConfigProvider(widget.siteId),
                          )
                          .value
                          ?.mappingFor(selected)
                          ?.conversionUrn ??
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
    if (!RegExp(r'^[A-Z]{3}$').hasMatch(currency)) {
      setState(
        () => _error = context.tr(
          'Enter a three-letter ISO currency code.',
          '请输入三位 ISO 币种代码。',
        ),
      );
      return;
    }
    await _run(() async {
      await ref
          .read(apiProvider)
          .request(
            'PUT',
            '/api/v1/sites/${widget.siteId}/offline-conversions/linkedin-ads/config',
            body: {'currencyCode': currency, 'apiToken': _token.text},
          );
      _token.clear();
      ref.invalidate(linkedInAdsConversionConfigProvider(widget.siteId));
    });
  }

  Future<void> _removeConfig() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.tr('Disconnect LinkedIn Ads?', '断开 LinkedIn Ads？')),
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
            '/api/v1/sites/${widget.siteId}/offline-conversions/linkedin-ads/config',
          );
      ref.invalidate(linkedInAdsConversionConfigProvider(widget.siteId));
    });
  }

  Future<void> _saveMapping(String? goalId) async {
    final urn = _conversionUrn.text.trim();
    if (goalId == null ||
        !RegExp(r'^urn:lla:llaPartnerConversion:\d{1,32}$').hasMatch(urn)) {
      setState(
        () => _error = context.tr(
          'Choose a goal and enter a LinkedIn conversion rule URN.',
          '请选择目标并填写 LinkedIn 转化规则 URN。',
        ),
      );
      return;
    }
    await _run(() async {
      await ref
          .read(apiProvider)
          .request(
            'PUT',
            '/api/v1/sites/${widget.siteId}/offline-conversions/linkedin-ads/config/goals/$goalId',
            body: {'conversionUrn': urn},
          );
      ref.invalidate(linkedInAdsConversionConfigProvider(widget.siteId));
    });
  }

  Future<void> _removeMapping(String goalId) async {
    await _run(() async {
      await ref
          .read(apiProvider)
          .request(
            'DELETE',
            '/api/v1/sites/${widget.siteId}/offline-conversions/linkedin-ads/config/goals/$goalId',
          );
      ref.invalidate(linkedInAdsConversionConfigProvider(widget.siteId));
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
      if (parsed.rows.any((row) => row.platform != 'linkedin_ads')) {
        throw const FormatException(
          'Every export row must use platform linkedin_ads.',
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
            'Send ${_preview!.rows.length} conversions to the mapped LinkedIn conversion rule? This live send cannot be undone in LinkedIn.',
            '将 ${_preview!.rows.length} 条转化发送到已映射的 LinkedIn 转化规则？发送后无法在 LinkedIn 撤销。',
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
            '/api/v1/sites/${widget.siteId}/offline-conversions/linkedin-ads/send',
            body: {
              'goalId': goalId,
              'consentConfirmed': true,
              'rows': _preview!.rows.map((row) => row.toJson()).toList(),
            },
          );
      final result = LinkedInAdsTransferResult.fromJson(
        Map<String, dynamic>.from(response as Map),
      );
      if (!mounted) return;
      _result = context.tr(
        '${result.eventsReceived} of ${result.rowsProcessed} events accepted by LinkedIn.',
        'LinkedIn 已接收 ${result.eventsReceived}/${result.rowsProcessed} 条事件。',
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

class _LinkedInMessage extends StatelessWidget {
  const _LinkedInMessage({required this.message, this.error = false});

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
