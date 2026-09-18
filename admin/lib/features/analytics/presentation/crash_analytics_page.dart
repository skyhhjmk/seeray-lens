import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/i18n/app_i18n.dart';
import '../../../shared/presentation/page_help_button.dart';
import '../../../shared/presentation/site_top_bar.dart';
import '../application/analytics_range.dart';
import '../application/crash_analytics.dart';

class CrashAnalyticsPage extends ConsumerWidget {
  const CrashAnalyticsPage({
    required this.siteId,
    this.embedded = false,
    super.key,
  });

  final String siteId;
  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final range = ref.watch(analyticsRangeProvider(siteId));
    final report = ref.watch(
      crashAnalyticsProvider(
        CrashAnalyticsQuery(siteId: siteId, range: range.range),
      ),
    );
    return Scaffold(
      backgroundColor: const Color(0xfff3f5f8),
      appBar: embedded
          ? null
          : SiteTopBar(
              siteId: siteId,
              selected: SiteTopTab.crashes,
              help: const PageHelpButton(
                englishTitle: 'Crash analytics',
                chineseTitle: '崩溃分析说明',
                englishBody:
                    'Reports opt-in JavaScript exceptions and unhandled promise rejections grouped by a privacy-scrubbed fingerprint. Resource load failures and native mobile crashes are not included.',
                chineseBody:
                    '报告明确启用后的 JavaScript 异常和未处理 Promise 拒绝，并按脱敏指纹聚类。不包含资源加载失败和原生移动端崩溃。',
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
              onRefresh: () => ref.invalidate(crashAnalyticsProvider),
            ),
      body: report.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              context.tr(
                'Could not load crash analytics. Check the selected date range and try again.',
                '无法加载崩溃分析。请检查所选日期范围后重试。',
              ),
            ),
          ),
        ),
        data: (data) => _CrashReport(siteId: siteId, report: data),
      ),
    );
  }
}

class _CrashReport extends StatelessWidget {
  const _CrashReport({required this.siteId, required this.report});

  final String siteId;
  final CrashAnalyticsReport report;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr('Crash analytics', '崩溃分析'),
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  context.tr(
                    'Find recurring browser exceptions by error, script location and affected pages.',
                    '按错误类型、脚本位置和受影响页面定位重复出现的浏览器异常。',
                  ),
                ),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: () =>
                context.go('/sites/$siteId/integration?tab=crashes'),
            icon: const Icon(Icons.integration_instructions_outlined),
            label: Text(context.tr('Setup', '接入设置')),
          ),
        ],
      ),
      const SizedBox(height: 12),
      Card(
        elevation: 0,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.privacy_tip_outlined),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  context.tr(
                    'Collection is off by default and requires the data-track-errors flag. The server stores only redacted error summaries and source positions; it discards stack traces, page titles, referrers, query strings and visitor/session IDs.',
                    '默认不采集，需显式添加 data-track-errors。服务器只保存脱敏后的错误摘要和脚本位置；会丢弃 stack、页面标题、来源页、查询参数及访客/会话 ID。',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          _Metric(
            label: context.tr('Error occurrences', '错误发生次数'),
            value: report.occurrences,
          ),
          _Metric(
            label: context.tr('Distinct issues', '错误类型数'),
            value: report.issueCount,
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
                context.tr('Recurring browser errors', '重复出现的浏览器错误'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 10),
              if (report.rows.isEmpty)
                _EmptyCrashes(siteId: siteId)
              else
                LayoutBuilder(
                  builder: (context, constraints) => constraints.maxWidth < 820
                      ? Column(
                          children: report.rows
                              .map((row) => _CrashCard(issue: row))
                              .toList(growable: false),
                        )
                      : SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: DataTable(
                            columns: [
                              DataColumn(
                                label: Text(context.tr('Error', '错误')),
                              ),
                              DataColumn(
                                label: Text(context.tr('Source', '脚本位置')),
                              ),
                              DataColumn(
                                label: Text(context.tr('Occurrences', '次数')),
                              ),
                              DataColumn(
                                label: Text(context.tr('Pages', '页面数')),
                              ),
                              DataColumn(
                                label: Text(context.tr('Browsers', '浏览器')),
                              ),
                              DataColumn(
                                label: Text(context.tr('First seen', '首次发生')),
                              ),
                              DataColumn(
                                label: Text(context.tr('Last seen', '最近发生')),
                              ),
                            ],
                            rows: report.rows
                                .map(
                                  (issue) => DataRow(
                                    cells: [
                                      DataCell(
                                        SizedBox(
                                          width: 300,
                                          child: Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                issue.errorName,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                              Text(
                                                issue.message,
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      DataCell(
                                        Text(_source(issue), maxLines: 2),
                                      ),
                                      DataCell(Text('${issue.occurrences}')),
                                      DataCell(Text('${issue.affectedPages}')),
                                      DataCell(Text(issue.browsers)),
                                      DataCell(
                                        Text(_timestamp(issue.firstSeen)),
                                      ),
                                      DataCell(
                                        Text(_timestamp(issue.lastSeen)),
                                      ),
                                    ],
                                  ),
                                )
                                .toList(growable: false),
                          ),
                        ),
                ),
              if (report.hasMore)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    context.tr(
                      'Showing the 100 most frequent issues. Narrow the date range to inspect a smaller period.',
                      '当前显示发生次数最多的 100 类错误；可缩小日期范围查看较短周期。',
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

class _CrashCard extends StatelessWidget {
  const _CrashCard({required this.issue});
  final CrashIssue issue;

  @override
  Widget build(BuildContext context) => Card(
    color: const Color(0xfff7f8fa),
    elevation: 0,
    child: ListTile(
      title: Text(issue.errorName),
      subtitle: Text(
        '${issue.message}\n${_source(issue)} · ${issue.browsers}\n${context.tr('Affected pages', '受影响页面')}: ${issue.affectedPages} · ${context.tr('First seen', '首次发生')}: ${_timestamp(issue.firstSeen)} · ${context.tr('Last seen', '最近发生')}: ${_timestamp(issue.lastSeen)}',
        maxLines: 5,
        overflow: TextOverflow.ellipsis,
      ),
      isThreeLine: true,
      trailing: Text('${issue.occurrences}×'),
    ),
  );
}

class _EmptyCrashes extends StatelessWidget {
  const _EmptyCrashes({required this.siteId});
  final String siteId;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 28),
    child: Column(
      children: [
        const Icon(Icons.bug_report_outlined, size: 40),
        const SizedBox(height: 8),
        Text(
          context.tr('No browser errors in this period', '此周期暂无浏览器错误'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 6),
        Text(
          context.tr(
            'Crash tracking is optional. Add data-track-errors to the tracker only if your privacy notice and consent policy allow it.',
            '崩溃追踪为可选功能；请确认隐私告知与同意策略允许后，再为追踪代码添加 data-track-errors。',
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => context.go('/sites/$siteId/integration?tab=crashes'),
          icon: const Icon(Icons.integration_instructions_outlined),
          label: Text(context.tr('View setup instructions', '查看接入说明')),
        ),
      ],
    ),
  );
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) => Card(
    elevation: 0,
    child: SizedBox(
      width: 210,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label),
            const SizedBox(height: 8),
            Text(
              '$value',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    ),
  );
}

String _source(CrashIssue issue) => [
  if (issue.functionName != null && issue.functionName!.isNotEmpty)
    issue.functionName!,
  if (issue.line == null)
    issue.sourcePath
  else
    '${issue.sourcePath}:${issue.line}${issue.column == null ? '' : ':${issue.column}'}',
].join(' · ');

String _timestamp(DateTime? value) => value == null
    ? '—'
    : '${value.toLocal().year.toString().padLeft(4, '0')}-${value.toLocal().month.toString().padLeft(2, '0')}-${value.toLocal().day.toString().padLeft(2, '0')} ${value.toLocal().hour.toString().padLeft(2, '0')}:${value.toLocal().minute.toString().padLeft(2, '0')}';
