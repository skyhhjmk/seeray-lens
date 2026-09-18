import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/i18n/app_i18n.dart';
import '../../../shared/presentation/page_help_button.dart';
import '../../../shared/presentation/site_top_bar.dart';
import '../../auth/application/auth_controller.dart';
import '../application/analytics_attribution.dart';
import '../application/analytics_range.dart';
import '../application/analytics_segment.dart';
import '../application/offline_conversions.dart';
import '../application/analytics_export.dart';

class OfflineConversionsPage extends ConsumerStatefulWidget {
  const OfflineConversionsPage({
    required this.siteId,
    this.embedded = false,
    super.key,
  });

  final String siteId;
  final bool embedded;

  @override
  ConsumerState<OfflineConversionsPage> createState() =>
      _OfflineConversionsPageState();
}

class _OfflineConversionsPageState
    extends ConsumerState<OfflineConversionsPage> {
  String _model = 'last_touch';
  int _lookbackDays = 30;
  String? _goalId;
  OfflineConversionImportPreview? _preview;
  String? _importError;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final range = ref.watch(analyticsRangeProvider(widget.siteId));
    final segmentId = ref.watch(
      analyticsSegmentSelectionProvider(widget.siteId),
    );
    final query = OfflineConversionQuery(
      siteId: widget.siteId,
      range: range.range,
      model: _model,
      lookbackDays: _lookbackDays,
      goalId: _goalId,
      segmentId: segmentId,
    );
    final result = ref.watch(offlineConversionAnalyticsProvider(query));
    final goals = ref
        .watch(analyticsGoalDefinitionsProvider(widget.siteId))
        .maybeWhen(
          data: (value) => value.where((goal) => goal.enabled).toList(),
          orElse: () => const <AttributionGoal>[],
        );
    final segments = ref
        .watch(analyticsSegmentOptionsProvider(widget.siteId))
        .maybeWhen(
          data: (value) => value,
          orElse: () => const <AnalyticsSegmentOption>[],
        );

    return Scaffold(
      backgroundColor: const Color(0xfff3f5f8),
      appBar: widget.embedded
          ? null
          : SiteTopBar(
              siteId: widget.siteId,
              selected: SiteTopTab.acquisition,
              help: const PageHelpButton(
                englishTitle: 'Offline conversion attribution',
                chineseTitle: '线下转化归因说明',
                englishBody:
                    'Import conversion IDs and paid click IDs from your CRM or sales system. SeeRay hashes identifiers before storage and matches them to collected acquisition visits. A match is not causal proof and can be lost when browser identity is unavailable.',
                chineseBody:
                    '从 CRM 或销售系统导入转化 ID 和广告点击 ID。SeeRay 在存储前对标识进行哈希，并将其匹配到已采集的获客访问。匹配不等于因果证明；浏览器身份缺失时，跨访问关联可能不完整。',
              ),
            ),
      body: result.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Text(
            context.tr(
              'Could not load offline conversion attribution.',
              '无法加载线下转化归因报表。',
            ),
          ),
        ),
        data: (data) => _buildContent(context, data, goals, segments, query),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    OfflineConversionData data,
    List<AttributionGoal> goals,
    List<AnalyticsSegmentOption> segments,
    OfflineConversionQuery query,
  ) {
    final selectedGoalId = goals.any((goal) => goal.id == _goalId)
        ? _goalId
        : null;
    final segmentId = ref.watch(
      analyticsSegmentSelectionProvider(widget.siteId),
    );
    final selectedSegmentId = segments.any((segment) => segment.id == segmentId)
        ? segmentId
        : null;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          runSpacing: 12,
          spacing: 16,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 250, maxWidth: 540),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.tr('Offline conversion attribution', '线下转化归因'),
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    context.tr(
                      'Match CRM conversions to privacy-safe paid click IDs and attribute their acquisition journeys.',
                      '将 CRM 转化匹配到隐私保护的广告点击 ID，并分析对应获客旅程。',
                    ),
                  ),
                ],
              ),
            ),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => context.go(
                    '/sites/${widget.siteId}/acquisition/attribution',
                  ),
                  icon: const Icon(Icons.compare_arrows),
                  label: Text(context.tr('Web attribution', '站内转化归因')),
                ),
                OutlinedButton.icon(
                  onPressed: () =>
                      context.go('/sites/${widget.siteId}/acquisition'),
                  icon: const Icon(Icons.arrow_back),
                  label: Text(context.tr('Acquisition', '流量获取')),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 18),
        _controls(context, goals, segments, selectedGoalId, selectedSegmentId),
        const SizedBox(height: 16),
        _importPanel(context, data.history.canManage),
        if (_importError != null) ...[
          const SizedBox(height: 12),
          _MessageCard(message: _importError!, error: true),
        ],
        if (_preview != null) ...[
          const SizedBox(height: 12),
          _previewPanel(context, goals, selectedGoalId),
        ],
        const SizedBox(height: 16),
        _summary(context, data.report),
        const SizedBox(height: 16),
        _reportTable(context, data.report),
        const SizedBox(height: 16),
        _importHistory(context, data.history),
        const SizedBox(height: 16),
        _explanation(context),
      ],
    );
  }

  Widget _controls(
    BuildContext context,
    List<AttributionGoal> goals,
    List<AnalyticsSegmentOption> segments,
    String? selectedGoal,
    String? selectedSegment,
  ) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          spacing: 18,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _dropdown<String>(
              context,
              label: context.tr('Attribution model', '归因模型'),
              value: _model,
              items: const [
                ('first_touch', 'First touch', '首次触点'),
                ('last_touch', 'Last touch', '末次触点'),
                ('linear', 'Linear', '线性'),
                ('position_based', 'Position-based', '位置权重'),
                ('time_decay', 'Time decay', '时间衰减'),
              ],
              onChanged: (value) => setState(() => _model = value),
            ),
            _dropdown<int>(
              context,
              label: context.tr('Lookback window', '归因窗口'),
              value: _lookbackDays,
              items: const [
                (7, '7 days', '7 天'),
                (30, '30 days', '30 天'),
                (90, '90 days', '90 天'),
              ],
              onChanged: (value) => setState(() => _lookbackDays = value),
            ),
            SizedBox(
              width: 240,
              child: DropdownButtonFormField<String?>(
                initialValue: selectedGoal,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: context.tr('Goal', '目标'),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                items: [
                  DropdownMenuItem<String?>(
                    value: null,
                    child: Text(context.tr('All enabled goals', '全部已启用目标')),
                  ),
                  ...goals.map(
                    (goal) => DropdownMenuItem<String?>(
                      value: goal.id,
                      child: Text(goal.name, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                ],
                onChanged: (value) => setState(() => _goalId = value),
              ),
            ),
            SizedBox(
              width: 240,
              child: DropdownButtonFormField<String?>(
                initialValue: selectedSegment,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: context.tr('Match segment', '匹配客群'),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                items: [
                  DropdownMenuItem<String?>(
                    value: null,
                    child: Text(context.tr('All click sessions', '全部点击访问')),
                  ),
                  ...segments.map(
                    (segment) => DropdownMenuItem<String?>(
                      value: segment.id,
                      child: Text(
                        segment.name,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
                onChanged: (value) => ref
                    .read(
                      analyticsSegmentSelectionProvider(widget.siteId).notifier,
                    )
                    .select(value),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dropdown<T>(
    BuildContext context, {
    required String label,
    required T value,
    required List<(T, String, String)> items,
    required ValueChanged<T> onChanged,
  }) {
    return SizedBox(
      width: 210,
      child: DropdownButtonFormField<T>(
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        items: [
          for (final item in items)
            DropdownMenuItem<T>(
              value: item.$1,
              child: Text(context.tr(item.$2, item.$3)),
            ),
        ],
        onChanged: (next) {
          if (next != null) onChanged(next);
        },
      ),
    );
  }

  Widget _importPanel(BuildContext context, bool canManage) => Card(
    elevation: 0,
    child: ExpansionTile(
      leading: const Icon(Icons.upload_file_outlined),
      title: Text(context.tr('Import offline conversions', '导入线下转化')),
      subtitle: Text(
        canManage
            ? context.tr(
                'Select a goal, preview the file, then import.',
                '选择目标、预览文件后再导入。',
              )
            : context.tr(
                'Only workspace owners and admins can import conversions.',
                '仅工作区所有者和管理员可以导入转化。',
              ),
      ),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            context.tr(
              'CSV columns: conversion_id, platform, click_id, converted_at. Use platform keys google_ads, microsoft_ads, meta_ads, tiktok_ads, linkedin_ads, or x_ads. Each file is assigned to one enabled goal. Click IDs and conversion IDs are hashed before storage; filenames and raw identifiers are not retained.',
              'CSV 列：conversion_id、platform、click_id、converted_at。平台键支持 google_ads、microsoft_ads、meta_ads、tiktok_ads、linkedin_ads、x_ads。每个文件指定一个已启用目标。点击 ID 和转化 ID 入库前会哈希；文件名和原始标识不会保留。',
            ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: _saveTemplate,
              icon: const Icon(Icons.download_outlined),
              label: Text(context.tr('Download CSV template', '下载 CSV 模板')),
            ),
            FilledButton.icon(
              onPressed: !canManage || _busy ? null : _chooseFile,
              icon: const Icon(Icons.folder_open_outlined),
              label: Text(context.tr('Choose CSV file', '选择 CSV 文件')),
            ),
          ],
        ),
        if (!canManage)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              context.tr(
                'Ask a workspace owner or admin to import offline conversions.',
                '请联系工作区所有者或管理员导入线下转化。',
              ),
            ),
          ),
      ],
    ),
  );

  Future<void> _saveTemplate() async {
    try {
      final csv = AnalyticsReportExport.csv(
        offlineConversionCsvHeaders,
        const <List<Object?>>[],
      );
      final result = await FilePicker.platform.saveFile(
        dialogTitle: context.tr('Save offline conversion template', '保存线下转化模板'),
        fileName: 'seeray-offline-conversions-template.csv',
        type: FileType.custom,
        allowedExtensions: const ['csv'],
        bytes: Uint8List.fromList(utf8.encode(csv)),
      );
      if (result != null && mounted) {
        _message(context.tr('Template saved.', '模板已保存。'));
      }
    } catch (_) {
      if (mounted) {
        _message(
          context.tr('Could not save the CSV template.', '无法保存 CSV 模板。'),
          error: true,
        );
      }
    }
  }

  Future<void> _chooseFile() async {
    try {
      final selection = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['csv'],
        allowMultiple: false,
        withData: true,
      );
      if (selection == null || selection.files.isEmpty || !mounted) return;
      final bytes = selection.files.single.bytes;
      if (bytes == null) {
        throw const FormatException('The selected file could not be read.');
      }
      if (bytes.length > OfflineConversionImportPreview.maximumBytes) {
        throw const FormatException('CSV files must be 2 MiB or smaller.');
      }
      final preview = OfflineConversionImportPreview.parse(utf8.decode(bytes));
      setState(() {
        _preview = preview;
        _importError = null;
      });
    } on FormatException catch (error) {
      if (!mounted) return;
      setState(() {
        _preview = null;
        _importError = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _preview = null;
        _importError = context.tr(
          'The CSV file could not be opened.',
          '无法读取该 CSV 文件。',
        );
      });
    }
  }

  Widget _previewPanel(
    BuildContext context,
    List<AttributionGoal> goals,
    String? selectedGoalId,
  ) {
    final preview = _preview!;
    final selectedGoal = goals.where((goal) => goal.id == selectedGoalId);
    final goalName = selectedGoal.isEmpty ? null : selectedGoal.first.name;
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.tr(
                'Ready to import · ${preview.rows.length} rows',
                '已通过校验 · ${preview.rows.length} 行',
              ),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              '${_formatDateTime(preview.firstConversion)} – ${_formatDateTime(preview.lastConversion)} · '
              '${goalName ?? context.tr('Select a goal below', '请在上方选择目标')}',
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: [
                  DataColumn(label: Text(context.tr('Conversion ID', '转化 ID'))),
                  DataColumn(label: Text(context.tr('Platform', '平台'))),
                  DataColumn(label: Text(context.tr('Click ID', '点击 ID'))),
                  DataColumn(label: Text(context.tr('Converted at', '转化时间'))),
                ],
                rows: [
                  for (final row in preview.rows.take(8))
                    DataRow(
                      cells: [
                        DataCell(Text(_maskIdentifier(row.conversionId))),
                        DataCell(Text(_platformLabel(context, row.platform))),
                        DataCell(Text(_maskIdentifier(row.clickId))),
                        DataCell(Text(row.convertedAt)),
                      ],
                    ),
                ],
              ),
            ),
            if (preview.rows.length > 8)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  context.tr(
                    'Showing the first 8 rows of ${preview.rows.length}.',
                    '当前预览前 8 行，共 ${preview.rows.length} 行。',
                  ),
                ),
              ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: _busy || selectedGoalId == null
                      ? null
                      : () => _importRows(selectedGoalId),
                  icon: _busy
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.cloud_upload_outlined),
                  label: Text(
                    context.tr(
                      'Import ${preview.rows.length} rows',
                      '导入 ${preview.rows.length} 行',
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                          _preview = null;
                          _importError = null;
                        }),
                  child: Text(context.tr('Discard preview', '清除预览')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _importRows(String goalId) async {
    final preview = _preview;
    if (preview == null) return;
    setState(() {
      _busy = true;
      _importError = null;
    });
    try {
      final result =
          await ref
                  .read(apiProvider)
                  .request(
                    'POST',
                    '/api/v1/sites/${widget.siteId}/offline-conversions/imports',
                    body: {
                      'goalId': goalId,
                      'rows': preview.rows.map((row) => row.toJson()).toList(),
                    },
                  )
              as Map;
      if (!mounted) return;
      setState(() {
        _busy = false;
        _preview = null;
      });
      _message(
        result['alreadyImported'] == true
            ? context.tr(
                'This exact import was already processed; no duplicate conversions were added.',
                '相同内容已处理，没有重复添加转化。',
              )
            : context.tr(
                'Imported ${preview.rows.length} offline conversions.',
                '已导入 ${preview.rows.length} 条线下转化。',
              ),
      );
      final segmentId = ref.read(
        analyticsSegmentSelectionProvider(widget.siteId),
      );
      final range = ref.read(analyticsRangeProvider(widget.siteId)).range;
      ref.invalidate(
        offlineConversionAnalyticsProvider(
          OfflineConversionQuery(
            siteId: widget.siteId,
            range: range,
            model: _model,
            lookbackDays: _lookbackDays,
            goalId: _goalId,
            segmentId: segmentId,
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _importError = error.toString();
      });
    }
  }

  Widget _summary(BuildContext context, OfflineConversionReport report) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Wrap(
          spacing: 28,
          runSpacing: 18,
          children: [
            _Metric(
              label: context.tr('Imported conversions', '导入转化'),
              value: '${report.totalImported}',
            ),
            _Metric(
              label: context.tr('Matched click IDs', '匹配点击 ID'),
              value: '${report.matchedConversions}',
            ),
            _Metric(
              label: context.tr('Unmatched', '未匹配'),
              value: '${report.unmatchedConversions}',
            ),
            _Metric(
              label: context.tr('Attributed conversions', '归因转化'),
              value: report.attributedConversions.toStringAsFixed(2),
            ),
            _Metric(
              label: context.tr('Configured goal value', '目标配置价值'),
              value: report.attributedValue.toStringAsFixed(2),
            ),
          ],
        ),
      ),
    );
  }

  Widget _reportTable(BuildContext context, OfflineConversionReport report) {
    if (report.rows.isEmpty) {
      return Card(
        elevation: 0,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              const Icon(Icons.insights_outlined),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  context.tr(
                    'No offline conversions matched collected ad click IDs in this reporting range.',
                    '当前日期范围内没有线下转化匹配到已采集的广告点击 ID。',
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                context.tr('Offline conversion performance', '线下转化表现'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: [
                  for (final label in [
                    context.tr('Goal', '目标'),
                    context.tr('Platform', '平台'),
                    context.tr('Channel', '渠道'),
                    context.tr('Source / medium', '来源 / 媒介'),
                    context.tr('Campaign', '活动'),
                    context.tr('Attributed conversions', '归因转化'),
                    context.tr('Configured value', '目标配置价值'),
                  ])
                    DataColumn(label: Text(label)),
                ],
                rows: [
                  for (final row in report.rows)
                    DataRow(
                      cells: [
                        DataCell(Text(row.goalName)),
                        DataCell(Text(_platformLabel(context, row.platform))),
                        DataCell(Text(_channelLabel(context, row.channel))),
                        DataCell(
                          Text('${row.source ?? '—'} / ${row.medium ?? '—'}'),
                        ),
                        DataCell(Text(row.campaign ?? '—')),
                        DataCell(
                          Text(row.attributedConversions.toStringAsFixed(2)),
                        ),
                        DataCell(Text(row.attributedValue.toStringAsFixed(2))),
                      ],
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 2),
              child: Text(
                context.tr(
                  'The selected audience filters the click-matched session; earlier visits in the lookback window remain eligible. Attribution value uses the goal fixed value and does not represent ecommerce revenue.',
                  '所选客群用于筛选点击匹配访问；归因窗口内更早的访问仍可参与分配。归因价值使用目标固定值，不代表电商收入。',
                ),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _importHistory(
    BuildContext context,
    OfflineConversionHistory history,
  ) => Card(
    elevation: 0,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr('Recent imports', '最近导入'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          if (history.imports.isEmpty)
            Text(context.tr('No imports yet.', '还没有导入记录。'))
          else
            for (final batch in history.imports)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.upload_file_outlined),
                title: Text(batch.goalName),
                subtitle: Text(
                  '${batch.rowCount} ${context.tr('conversions', '条转化')} · ${_formatDateTime(batch.importedAt)}',
                ),
              ),
        ],
      ),
    ),
  );

  Widget _explanation(BuildContext context) => Card(
    elevation: 0,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.privacy_tip_outlined),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              context.tr(
                'Only supported paid click IDs can match. The collector and import must use the same site, platform, and exact click ID. SeeRay stores site-scoped hashes rather than raw IDs; data retention removes expired conversion rows. Attribution is modeled credit, not proof that an ad caused the conversion.',
                '仅支持通过已识别的付费点击 ID 进行匹配。采集与导入必须属于同一站点、平台，并使用一致的点击 ID。SeeRay 只保存站点级哈希，不保存原始 ID；数据保留策略会清理过期转化记录。归因是模型分配，不证明广告导致了转化。',
              ),
            ),
          ),
        ],
      ),
    ),
  );

  void _message(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }
}

String _maskIdentifier(String value) => value.length <= 4
    ? '••••'
    : '${value.substring(0, 2)}…${value.substring(value.length - 2)}';

String _platformLabel(BuildContext context, String platform) =>
    switch (platform) {
      'google_ads' => 'Google Ads',
      'microsoft_ads' => 'Microsoft Ads',
      'meta_ads' => 'Meta Ads',
      'tiktok_ads' => 'TikTok Ads',
      'linkedin_ads' => 'LinkedIn Ads',
      'x_ads' => 'X Ads',
      _ => context.tr('Other', '其他'),
    };

String _channelLabel(BuildContext context, String channel) => switch (channel) {
  'campaign' => context.tr('Campaign', '广告活动'),
  'direct' => context.tr('Direct', '直接访问'),
  'referral' => context.tr('Referral', '引荐'),
  'search_engine' => context.tr('Search', '搜索引擎'),
  'social' => context.tr('Social', '社交'),
  'ai_assistant' => context.tr('AI assistant', 'AI 助手'),
  _ => channel,
};

String _formatDateTime(DateTime value) {
  final local = value.toLocal();
  String two(int part) => part.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 170,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 4),
        Text(value, style: Theme.of(context).textTheme.titleLarge),
      ],
    ),
  );
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({required this.message, this.error = false});

  final String message;
  final bool error;

  @override
  Widget build(BuildContext context) => Card(
    color: error ? Theme.of(context).colorScheme.errorContainer : null,
    elevation: 0,
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Icon(error ? Icons.error_outline : Icons.check_circle_outline),
          const SizedBox(width: 10),
          Expanded(child: Text(message)),
        ],
      ),
    ),
  );
}
