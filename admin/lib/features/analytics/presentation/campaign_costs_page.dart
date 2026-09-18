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
import '../application/campaign_costs.dart';
import '../application/analytics_export.dart';

class CampaignCostsPage extends ConsumerStatefulWidget {
  const CampaignCostsPage({
    required this.siteId,
    this.embedded = false,
    super.key,
  });

  final String siteId;
  final bool embedded;

  @override
  ConsumerState<CampaignCostsPage> createState() => _CampaignCostsPageState();
}

class _CampaignCostsPageState extends ConsumerState<CampaignCostsPage> {
  String _model = 'last_touch';
  int _lookbackDays = 30;
  String? _goalId;
  CampaignCostImportPreview? _preview;
  String? _fileName;
  String? _importError;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final range = ref.watch(analyticsRangeProvider(widget.siteId));
    final segmentId = ref.watch(
      analyticsSegmentSelectionProvider(widget.siteId),
    );
    final query = CampaignCostQuery(
      siteId: widget.siteId,
      range: range.range,
      model: _model,
      lookbackDays: _lookbackDays,
      goalId: _goalId,
      segmentId: segmentId,
    );
    final report = ref.watch(campaignCostAnalyticsProvider(query));
    final goals = ref
        .watch(analyticsGoalDefinitionsProvider(widget.siteId))
        .maybeWhen(
          data: (value) => value.where((goal) => goal.enabled).toList(),
          orElse: () => const <AttributionGoal>[],
        );
    return Scaffold(
      backgroundColor: const Color(0xfff3f5f8),
      appBar: widget.embedded
          ? null
          : SiteTopBar(
              siteId: widget.siteId,
              selected: SiteTopTab.acquisition,
              help: const PageHelpButton(
                englishTitle: 'Campaign costs',
                chineseTitle: '广告活动费用',
                englishBody:
                    'Import daily advertising costs from a normalized CSV, then compare spend with tracked sessions and modeled goal attribution. Imported goal value uses the configured fixed value; it is not ecommerce revenue.',
                chineseBody:
                    '从标准 CSV 导入每日广告费用，并与采集到的访问和模型归因目标进行比较。目标价值使用目标配置的固定值，不代表电商收入。',
              ),
            ),
      body: report.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Text(
            context.tr('Could not load campaign cost report.', '无法加载广告活动费用报表。'),
          ),
        ),
        data: (data) => _buildContent(context, data, goals, query),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    CampaignCostData data,
    List<AttributionGoal> goals,
    CampaignCostQuery query,
  ) {
    final selectedGoal = goals.any((goal) => goal.id == _goalId)
        ? _goalId
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
              constraints: const BoxConstraints(minWidth: 250, maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.tr('Campaign costs', '广告活动费用'),
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    context.tr(
                      'Compare imported daily spend with campaign sessions and attributed goal value.',
                      '将每日导入费用与活动访问和目标归因价值对比。',
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
                  label: Text(context.tr('Attribution models', '归因模型')),
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
        _reportControls(context, goals, selectedGoal),
        const SizedBox(height: 16),
        _importPanel(context, data.history.canManage, query),
        if (_importError != null) ...[
          const SizedBox(height: 12),
          _MessageCard(message: _importError!, error: true),
        ],
        if (_preview != null) ...[
          const SizedBox(height: 12),
          _previewPanel(context, query),
        ],
        const SizedBox(height: 16),
        _reportTable(context, data.report),
        const SizedBox(height: 16),
        _importHistory(context, data.history),
        const SizedBox(height: 16),
        _explanation(context),
      ],
    );
  }

  Widget _reportControls(
    BuildContext context,
    List<AttributionGoal> goals,
    String? selectedGoal,
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
              width: 250,
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
              child: Text(
                context.tr(item.$2, item.$3),
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        onChanged: (next) {
          if (next != null) onChanged(next);
        },
      ),
    );
  }

  Widget _importPanel(
    BuildContext context,
    bool canManage,
    CampaignCostQuery query,
  ) {
    return Card(
      elevation: 0,
      child: ExpansionTile(
        leading: const Icon(Icons.upload_file_outlined),
        title: Text(context.tr('Import campaign CSV', '导入广告活动 CSV')),
        subtitle: Text(
          canManage
              ? context.tr(
                  'Preview and validate rows before importing.',
                  '导入前先预览并校验所有行。',
                )
              : context.tr(
                  'Only workspace owners and admins can import costs.',
                  '仅工作区所有者和管理员可以导入费用。',
                ),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              context.tr(
                'Use the template columns in this order: date, platform, source, medium, campaign, currency, cost, clicks, impressions. Matching source/medium/campaign values connect spend to acquisition reports. Re-importing changed rows replaces those daily campaign values; omitted rows are left unchanged.',
                '请按模板提供日期、平台、来源、媒介、活动、币种、费用、点击、展示。来源/媒介/活动必须与流量报告一致，才能关联访问和转化。重新导入已修改的日期活动行会覆盖旧值；本次文件未包含的行保持不变。',
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
                  'Ask a workspace owner or admin to upload campaign costs.',
                  '请联系工作区所有者或管理员上传活动费用。',
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _saveTemplate() async {
    try {
      final csv = AnalyticsReportExport.csv(
        campaignCostCsvHeaders,
        const <List<Object?>>[],
      );
      final result = await FilePicker.platform.saveFile(
        dialogTitle: context.tr('Save campaign cost template', '保存活动费用模板'),
        fileName: 'seeray-campaign-cost-template.csv',
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
      final file = selection.files.single;
      final bytes = file.bytes;
      if (bytes == null) {
        throw const FormatException('The selected file could not be read.');
      }
      if (bytes.length > CampaignCostImportPreview.maximumBytes) {
        throw const FormatException('CSV files must be 2 MiB or smaller.');
      }
      final preview = CampaignCostImportPreview.parse(utf8.decode(bytes));
      setState(() {
        _preview = preview;
        _fileName = file.name;
        _importError = null;
      });
    } on FormatException catch (error) {
      if (!mounted) return;
      setState(() {
        _preview = null;
        _fileName = null;
        _importError = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _preview = null;
        _fileName = null;
        _importError = context.tr(
          'The CSV file could not be opened.',
          '无法读取该 CSV 文件。',
        );
      });
    }
  }

  Widget _previewPanel(BuildContext context, CampaignCostQuery query) {
    final preview = _preview!;
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
              '${_fileName ?? ''} · ${preview.firstDate} – ${preview.lastDate} · '
              '${preview.currencies.join(', ')} · ${preview.clicks} ${context.tr('clicks', '次点击')} · ${preview.impressions} ${context.tr('impressions', '次展示')}',
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: [
                  for (final label in [
                    context.tr('Date', '日期'),
                    context.tr('Platform', '平台'),
                    context.tr('Campaign', '活动'),
                    context.tr('Spend', '费用'),
                    context.tr('Clicks', '点击'),
                    context.tr('Impressions', '展示'),
                  ])
                    DataColumn(label: Text(label)),
                ],
                rows: [
                  for (final row in preview.rows.take(8))
                    DataRow(
                      cells: [
                        DataCell(Text(row.date)),
                        DataCell(Text(_platformLabel(context, row.platform))),
                        DataCell(Text(row.campaign)),
                        DataCell(Text('${row.currency} ${row.cost}')),
                        DataCell(Text('${row.clicks}')),
                        DataCell(Text('${row.impressions}')),
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
                  onPressed: _busy ? null : () => _importRows(query),
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
                          _fileName = null;
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

  Future<void> _importRows(CampaignCostQuery query) async {
    final preview = _preview;
    final fileName = _fileName;
    if (preview == null || fileName == null) return;
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
                    '/api/v1/sites/${widget.siteId}/analytics/campaign-costs/imports',
                    body: {
                      'fileName': fileName,
                      'rows': preview.rows.map((row) => row.toJson()).toList(),
                    },
                  )
              as Map;
      if (!mounted) return;
      setState(() {
        _busy = false;
        _preview = null;
        _fileName = null;
      });
      _message(
        result['alreadyImported'] == true
            ? context.tr(
                'This exact file was already imported; no duplicate costs were added.',
                '该文件内容已导入过，没有重复累加费用。',
              )
            : context.tr(
                'Imported ${preview.rows.length} campaign rows.',
                '已导入 ${preview.rows.length} 行活动费用。',
              ),
      );
      ref.invalidate(campaignCostAnalyticsProvider(query));
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _importError = error.toString();
      });
    }
  }

  Widget _reportTable(BuildContext context, CampaignCostReport report) {
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
                    'No campaign costs have been imported for this reporting range.',
                    '当前统计范围还没有导入广告活动费用。',
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
                context.tr('Campaign performance', '广告活动表现'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: [
                  for (final label in [
                    context.tr('Campaign', '活动'),
                    context.tr('Platform', '平台'),
                    context.tr('Spend', '费用'),
                    context.tr('Clicks', '点击'),
                    context.tr('Sessions', '访问'),
                    context.tr('CPC', '点击成本'),
                    context.tr('Attributed goals', '归因转化'),
                    context.tr('Cost / goal', '单次转化成本'),
                    context.tr('Goal value / spend', '目标价值 / 费用'),
                  ])
                    DataColumn(label: Text(label)),
                ],
                rows: [
                  for (final row in report.rows)
                    DataRow(
                      cells: [
                        DataCell(
                          SizedBox(
                            width: 210,
                            child: Text(
                              '${row.campaign}\n${row.source} / ${row.medium}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        DataCell(Text(_platformLabel(context, row.platform))),
                        DataCell(
                          Text(
                            '${row.currency} ${row.cost.toStringAsFixed(2)}',
                          ),
                        ),
                        DataCell(Text('${row.clicks}')),
                        DataCell(Text('${row.sessions}')),
                        DataCell(Text(_amount(row.currency, row.costPerClick))),
                        DataCell(
                          Text(row.attributedConversions.toStringAsFixed(2)),
                        ),
                        DataCell(
                          Text(
                            _amount(
                              row.currency,
                              row.costPerAttributedConversion,
                            ),
                          ),
                        ),
                        DataCell(
                          Text(
                            row.goalValuePerSpend?.toStringAsFixed(2) ?? '—',
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 2),
              child: Text(
                context.tr(
                  'Attributed conversions use the selected model and lookback. Goal value is the configured fixed value; currencies are never combined.',
                  '归因转化按所选模型和窗口计算。目标价值来自目标固定值；不同币种不会合并。',
                ),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _importHistory(BuildContext context, CampaignCostHistory history) {
    return Card(
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
              Text(context.tr('No files imported yet.', '还没有导入文件。'))
            else
              for (final batch in history.imports)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.description_outlined),
                  title: Text(batch.fileName, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    '${batch.rowCount} ${context.tr('rows', '行')} · ${_dateTime(batch.importedAt)}',
                  ),
                ),
          ],
        ),
      ),
    );
  }

  Widget _explanation(BuildContext context) => Card(
    elevation: 0,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              context.tr(
                'Campaign cost data is imported, not fetched directly from ad platforms. For reliable comparisons, use the same source, medium, and campaign labels as your tracking links. A goal value-per-spend ratio is based on configured goal values, not recognized sales revenue.',
                '广告费用通过文件导入，不会直接连接广告平台。要获得可靠对比，请使用与跟踪链接相同的来源、媒介和活动名称。目标价值/费用使用目标固定价值计算，不是实际销售收入。',
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

String _platformLabel(BuildContext context, String platform) =>
    switch (platform) {
      'google_ads' => context.tr('Google Ads', 'Google Ads'),
      'microsoft_ads' => context.tr('Microsoft Ads', 'Microsoft Ads'),
      'meta_ads' => context.tr('Meta Ads', 'Meta Ads'),
      'tiktok_ads' => context.tr('TikTok Ads', 'TikTok Ads'),
      'linkedin_ads' => context.tr('LinkedIn Ads', 'LinkedIn Ads'),
      'x_ads' => context.tr('X Ads', 'X Ads'),
      _ => context.tr('Other', '其他'),
    };

String _amount(String currency, double? amount) =>
    amount == null ? '—' : '$currency ${amount.toStringAsFixed(2)}';

String _dateTime(DateTime value) {
  final local = value.toLocal();
  String two(int part) => part.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
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
