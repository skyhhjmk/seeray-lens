import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/i18n/app_i18n.dart';
import '../../../shared/presentation/page_help_button.dart';
import '../../../shared/presentation/site_top_bar.dart';
import '../application/analytics_range.dart';
import '../application/form_analytics.dart';

class FormAnalyticsPage extends ConsumerWidget {
  const FormAnalyticsPage({
    required this.siteId,
    this.embedded = false,
    super.key,
  });

  final String siteId;
  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final range = ref.watch(analyticsRangeProvider(siteId));
    final query = FormAnalyticsQuery(siteId: siteId, range: range.range);
    final report = ref.watch(formAnalyticsProvider(query));
    return Scaffold(
      backgroundColor: const Color(0xfff3f5f8),
      appBar: embedded
          ? null
          : SiteTopBar(
              siteId: siteId,
              selected: SiteTopTab.forms,
              help: const PageHelpButton(
                englishTitle: 'Form analytics',
                chineseTitle: '表单分析说明',
                englishBody:
                    'Counts only forms explicitly marked with a stable ID after the tracking snippet enables form analytics. Field values, names, labels and error messages are never collected. A submit is not a confirmed conversion; call trackFormResult after your server returns the result.',
                chineseBody:
                    '仅统计追踪代码启用表单分析且明确标记稳定 ID 的表单。不会采集字段值、名称、标签或错误消息。提交不等于转化成功；请在服务器返回结果后调用 trackFormResult。',
              ),
              rangeState: range,
              onSelectRange: () =>
                  showAnalyticsRangePicker(context, range).then((selected) {
                    if (selected != null) {
                      ref
                          .read(analyticsRangeProvider(siteId).notifier)
                          .setRange(selected);
                    }
                  }),
              onRefresh: () => ref.invalidate(formAnalyticsProvider),
            ),
      body: report.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              context.tr(
                'Could not load form analytics. Check the selected date range and try again.',
                '无法加载表单分析。请检查所选日期范围后重试。',
              ),
            ),
          ),
        ),
        data: (data) => _FormAnalyticsReport(siteId: siteId, report: data),
      ),
    );
  }
}

class _FormAnalyticsReport extends StatelessWidget {
  const _FormAnalyticsReport({required this.siteId, required this.report});

  final String siteId;
  final FormAnalyticsReport report;

  @override
  Widget build(BuildContext context) {
    final rows = report.rows;
    final views = rows.fold<int>(0, (sum, row) => sum + row.views);
    final starts = rows.fold<int>(0, (sum, row) => sum + row.starts);
    final successes = rows.fold<int>(0, (sum, row) => sum + row.successes);
    final errors = rows.fold<int>(0, (sum, row) => sum + row.validationErrors);
    final failures = rows.fold<int>(0, (sum, row) => sum + row.failures);
    final abandonments = rows.fold<int>(
      0,
      (sum, row) => sum + row.abandonments,
    );
    final conversionRate = starts == 0 ? 0.0 : successes / starts;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.tr('Form analytics', '表单分析'),
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    context.tr(
                      'Understand where visitors start, encounter validation errors and complete explicitly instrumented forms.',
                      '了解访客从哪里开始填写、遇到哪些校验问题，以及明确标记表单的完成情况。',
                    ),
                  ),
                ],
              ),
            ),
            TextButton.icon(
              onPressed: () =>
                  context.go('/sites/$siteId/integration?tab=forms'),
              icon: const Icon(Icons.integration_instructions_outlined),
              label: Text(context.tr('Setup', '接入设置')),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _Metric(label: context.tr('Form views', '表单浏览'), value: views),
            _Metric(label: context.tr('Started', '开始填写'), value: starts),
            _Metric(
              label: context.tr('Confirmed successes', '确认成功'),
              value: successes,
            ),
            _Metric(
              label: context.tr('Confirmed failures', '确认失败'),
              value: failures,
            ),
            _Metric(
              label: context.tr('Validation errors', '校验错误'),
              value: errors,
            ),
            _Metric(
              label: context.tr('Abandoned', '未提交离开'),
              value: abandonments,
            ),
            _Metric(
              label: context.tr('Start → success', '开始 → 成功'),
              value: conversionRate,
              percent: true,
            ),
          ],
        ),
        const SizedBox(height: 16),
        Card(
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr('Forms by page', '按页面查看表单'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  context.tr(
                    'Field interactions are grouped by safe field type only. No input values, field names or validation text are available in this report.',
                    '字段互动仅按安全字段类型汇总。此报表不会保存或展示输入值、字段名称或校验文本。',
                  ),
                ),
                const SizedBox(height: 12),
                if (rows.isEmpty)
                  _EmptyForms(siteId: siteId)
                else
                  LayoutBuilder(
                    builder: (context, constraints) {
                      if (constraints.maxWidth < 760) {
                        return Column(
                          children: rows
                              .map((row) => _FormRowCard(row: row))
                              .toList(),
                        );
                      }
                      return SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          columns: [
                            DataColumn(
                              label: Text(context.tr('Form / page', '表单 / 页面')),
                            ),
                            DataColumn(label: Text(context.tr('Views', '浏览'))),
                            DataColumn(
                              label: Text(context.tr('Visitors', '访客')),
                            ),
                            DataColumn(label: Text(context.tr('Starts', '开始'))),
                            DataColumn(
                              label: Text(context.tr('Interactions', '互动')),
                            ),
                            DataColumn(label: Text(context.tr('Errors', '错误'))),
                            DataColumn(
                              label: Text(context.tr('Submits', '提交')),
                            ),
                            DataColumn(
                              label: Text(context.tr('Success', '成功')),
                            ),
                            DataColumn(label: Text(context.tr('Failed', '失败'))),
                            DataColumn(
                              label: Text(context.tr('Abandoned', '未提交离开')),
                            ),
                            DataColumn(
                              label: Text(
                                context.tr('Avg. field time', '平均字段耗时'),
                              ),
                            ),
                            DataColumn(
                              label: Text(context.tr('Conversion', '转化率')),
                            ),
                          ],
                          rows: rows
                              .map(
                                (row) => DataRow(
                                  cells: [
                                    DataCell(
                                      SizedBox(
                                        width: 200,
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Text(
                                              row.formId,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            Text(
                                              row.pagePath,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    DataCell(Text('${row.views}')),
                                    DataCell(Text('${row.uniqueVisitors}')),
                                    DataCell(Text('${row.starts}')),
                                    DataCell(Text('${row.fieldInteractions}')),
                                    DataCell(Text('${row.validationErrors}')),
                                    DataCell(Text('${row.submits}')),
                                    DataCell(Text('${row.successes}')),
                                    DataCell(Text('${row.failures}')),
                                    DataCell(Text('${row.abandonments}')),
                                    DataCell(
                                      Text(_duration(row.averageFieldTimeMs)),
                                    ),
                                    DataCell(
                                      Text(
                                        '${(row.conversionRate * 100).toStringAsFixed(1)}%',
                                      ),
                                    ),
                                  ],
                                ),
                              )
                              .toList(),
                        ),
                      );
                    },
                  ),
                if (report.hasMore)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      context.tr(
                        'Showing the 100 most active form/page pairs. Narrow the date range to inspect a smaller period.',
                        '当前显示最活跃的 100 个表单/页面组合；缩小日期范围可查看更细的时间段。',
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    this.percent = false,
  });
  final String label;
  final num value;
  final bool percent;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 175,
    child: Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            Text(
              percent ? '${(value * 100).toStringAsFixed(1)}%' : '$value',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ],
        ),
      ),
    ),
  );
}

class _FormRowCard extends StatelessWidget {
  const _FormRowCard({required this.row});
  final FormAnalyticsRow row;

  @override
  Widget build(BuildContext context) => Card(
    elevation: 0,
    child: ListTile(
      title: Text(row.formId),
      subtitle: Text(
        '${row.pagePath}\n${context.tr('Visitors', '访客')}: ${row.uniqueVisitors} · ${context.tr('Starts', '开始')}: ${row.starts} · ${context.tr('Errors', '错误')}: ${row.validationErrors} · ${context.tr('Submits', '提交')}: ${row.submits} · ${context.tr('Success', '成功')}: ${row.successes} · ${context.tr('Failed', '失败')}: ${row.failures} · ${context.tr('Abandoned', '未提交离开')}: ${row.abandonments} · ${_duration(row.averageFieldTimeMs)}',
      ),
      isThreeLine: true,
      trailing: Text('${(row.conversionRate * 100).toStringAsFixed(1)}%'),
    ),
  );
}

class _EmptyForms extends StatelessWidget {
  const _EmptyForms({required this.siteId});
  final String siteId;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 24),
    child: Column(
      children: [
        const Icon(Icons.dynamic_form_outlined, size: 40),
        const SizedBox(height: 8),
        Text(
          context.tr('No form analytics yet', '暂无表单分析数据'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 6),
        Text(
          context.tr(
            'Enable the opt-in tracker flag and mark only the forms you want measured. Then send a confirmed result after server-side validation.',
            '请启用追踪代码中的表单分析选项，并只标记希望统计的表单；服务器确认处理结果后再发送成功/失败状态。',
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => context.go('/sites/$siteId/integration?tab=forms'),
          icon: const Icon(Icons.integration_instructions_outlined),
          label: Text(context.tr('View setup instructions', '查看接入说明')),
        ),
      ],
    ),
  );
}

String _duration(int milliseconds) => milliseconds < 1000
    ? '${milliseconds}ms'
    : '${(milliseconds / 1000).toStringAsFixed(1)}s';
