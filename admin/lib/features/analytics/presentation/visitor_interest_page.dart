import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_i18n.dart';
import '../../../shared/presentation/page_help_button.dart';
import '../../../shared/presentation/site_top_bar.dart';
import '../application/analytics_controller.dart';
import '../application/analytics_range.dart';
import '../application/analytics_segment.dart';
import 'segment_filter_selector.dart';

class VisitorInterestPage extends ConsumerStatefulWidget {
  const VisitorInterestPage({
    required this.siteId,
    this.embedded = false,
    super.key,
  });

  final String siteId;
  final bool embedded;

  @override
  ConsumerState<VisitorInterestPage> createState() =>
      _VisitorInterestPageState();
}

class _VisitorInterestPageState extends ConsumerState<VisitorInterestPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final current = ref.read(analyticsRangeProvider(widget.siteId));
      if (current.period != AnalyticsPeriod.realtime) return;
      final to = analyticsDateOnly(DateTime.now());
      ref
          .read(analyticsRangeProvider(widget.siteId).notifier)
          .setRange(
            AnalyticsRangeState(
              period: AnalyticsPeriod.custom,
              range: AnalyticsDateRange(
                to.subtract(const Duration(days: 29)),
                to,
              ),
            ),
          );
    });
  }

  @override
  Widget build(BuildContext context) {
    final range = ref.watch(analyticsRangeProvider(widget.siteId));
    final segmentId = ref.watch(
      analyticsSegmentSelectionProvider(widget.siteId),
    );
    final query = AnalyticsDashboardQuery(
      widget.siteId,
      range.range,
      segmentId: segmentId,
    );
    final report = ref.watch(analyticsVisitorInterestProvider(query));
    return Scaffold(
      backgroundColor: const Color(0xfff3f5f8),
      appBar: widget.embedded
          ? null
          : SiteTopBar(
              siteId: widget.siteId,
              selected: SiteTopTab.visitorInterest,
              help: const PageHelpButton(
                englishTitle: 'Visitor engagement',
                chineseTitle: '访客参与度说明',
                englishBody:
                    'Frequency is counted within the selected date range, not over a visitor’s lifetime. Page views and tracker records are grouped per visit; tracker-record counts include page views and heartbeat signals but exclude Web Vitals samples.',
                chineseBody:
                    '访问频率按所选日期范围统计，不代表访客终身次数。页面浏览和追踪记录按每次访问分组；追踪记录数包含页面浏览和心跳信号，不包含 Web Vitals 样本。',
              ),
              rangeState: range,
              segmentFilter: SegmentFilterSelector(siteId: widget.siteId),
              onSelectRange: () => _selectRange(context, range),
              onRefresh: () => ref.invalidate(analyticsVisitorInterestProvider),
            ),
      body: report.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              context.tr(
                'Could not load visitor engagement. Check the date range and selected audience, then try again.',
                '无法加载访客参与度报表。请检查日期范围和所选分群后重试。',
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
        data: (data) => _VisitorInterestReportView(report: data),
      ),
    );
  }

  Future<void> _selectRange(
    BuildContext context,
    AnalyticsRangeState current,
  ) async {
    final selected = await showAnalyticsRangePicker(context, current);
    if (selected == null || !mounted) return;
    ref.read(analyticsRangeProvider(widget.siteId).notifier).setRange(selected);
  }
}

class _VisitorInterestReportView extends StatelessWidget {
  const _VisitorInterestReportView({required this.report});

  final VisitorInterestReport report;

  @override
  Widget build(BuildContext context) {
    if (report.sessions == 0) {
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            context.tr('Visitor engagement', '访客参与度'),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 14),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                context.tr(
                  'No visits match this period and audience. Try a wider date range or clear the selected segment.',
                  '此日期范围和分群没有匹配访问。请扩大日期范围或清除当前分群。',
                ),
              ),
            ),
          ),
        ],
      );
    }

    final pagesPerSession = report.sessions == 0
        ? 0.0
        : report.pageViews / report.sessions;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          context.tr('Visitor engagement', '访客参与度'),
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 6),
        Text(
          context.tr(
            'Understand how often visitors return and how deeply sessions engage. Every distribution follows the selected date range and audience.',
            '了解访客在所选周期内的回访频率，以及每次访问的参与深度。所有分布都遵循当前日期范围和分群。',
          ),
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 1180
                ? 4
                : constraints.maxWidth >= 600
                ? 2
                : 1;
            const gap = 12.0;
            final width =
                (constraints.maxWidth - gap * (columns - 1)) / columns;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                SizedBox(
                  width: width,
                  child: _SummaryCard(
                    label: context.tr('Active visitors', '活跃访客'),
                    value: report.visitors,
                    icon: Icons.people_alt_outlined,
                  ),
                ),
                SizedBox(
                  width: width,
                  child: _SummaryCard(
                    label: context.tr('Visits', '访问次数'),
                    value: report.sessions,
                    icon: Icons.repeat_rounded,
                  ),
                ),
                SizedBox(
                  width: width,
                  child: _SummaryCard(
                    label: context.tr('Pages per visit', '每次访问页面数'),
                    value: pagesPerSession.toStringAsFixed(1),
                    icon: Icons.web_rounded,
                  ),
                ),
                SizedBox(
                  width: width,
                  child: _SummaryCard(
                    label: context.tr('Average visit duration', '平均访问时长'),
                    value: _formatDuration(report.averageSessionDurationMs),
                    icon: Icons.timer_outlined,
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        Card(
          color: const Color(0xffedf4fb),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline, size: 19),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    context.tr(
                      'Visit frequency means sessions per visitor inside this selected period. A visitor with earlier history can still appear in the “1 visit” band if only one of their visits falls in this range.',
                      '访问频率表示当前所选周期内每位访客的会话数。有历史访问的访客，如果本周期只有一次访问，也会出现在“1 次访问”分组中。',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 1050 ? 2 : 1;
            const gap = 14.0;
            final width =
                (constraints.maxWidth - gap * (columns - 1)) / columns;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                SizedBox(
                  width: width,
                  child: _DistributionCard(
                    title: context.tr('Visits per visitor', '每位访客的访问次数'),
                    description: context.tr(
                      'How many sessions each active visitor made in this period.',
                      '显示每位活跃访客在本周期内产生的会话数。',
                    ),
                    subjectLabel: context.tr('visitors', '位访客'),
                    denominator: report.visitors,
                    rows: [
                      for (final band in report.frequency)
                        _DistributionRow(band.visits, band.visitors),
                    ],
                  ),
                ),
                SizedBox(
                  width: width,
                  child: _DistributionCard(
                    title: context.tr('Pages per visit', '每次访问的页面浏览'),
                    description: context.tr(
                      'Sessions grouped by the number of page views they contain.',
                      '按会话中的页面浏览次数分组。',
                    ),
                    subjectLabel: context.tr('visits', '次访问'),
                    denominator: report.sessions,
                    rows: [
                      for (final band in report.pageViewsPerSession)
                        _DistributionRow(band.band, band.sessions),
                    ],
                  ),
                ),
                SizedBox(
                  width: width,
                  child: _DistributionCard(
                    title: context.tr('Tracker records per visit', '每次访问的追踪记录'),
                    description: context.tr(
                      'Includes page views and heartbeat signals; Web Vitals samples are excluded.',
                      '包含页面浏览和心跳信号，不包含 Web Vitals 样本。',
                    ),
                    subjectLabel: context.tr('visits', '次访问'),
                    denominator: report.sessions,
                    rows: [
                      for (final band in report.eventsPerSession)
                        _DistributionRow(band.band, band.sessions),
                    ],
                  ),
                ),
                SizedBox(
                  width: width,
                  child: _DistributionCard(
                    title: context.tr('Visit duration', '访问时长'),
                    description: context.tr(
                      'Elapsed time between the first and last event in a session.',
                      '会话中首个事件与最后一个事件之间的时长。',
                    ),
                    subjectLabel: context.tr('visits', '次访问'),
                    denominator: report.sessions,
                    rows: [
                      for (final band in report.durationPerSession)
                        _DistributionRow(band.band, band.sessions),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  static String _formatDuration(double milliseconds) {
    final seconds = (milliseconds / 1000).round();
    if (seconds < 60) return '${seconds}s';
    final minutes = seconds ~/ 60;
    final remainder = seconds % 60;
    return remainder == 0 ? '${minutes}m' : '${minutes}m ${remainder}s';
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final Object value;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 4),
                Text(
                  value.toString(),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _DistributionRow {
  const _DistributionRow(this.label, this.count);

  final String label;
  final int count;
}

class _DistributionCard extends StatelessWidget {
  const _DistributionCard({
    required this.title,
    required this.description,
    required this.subjectLabel,
    required this.denominator,
    required this.rows,
  });

  final String title;
  final String description;
  final String subjectLabel;
  final int denominator;
  final List<_DistributionRow> rows;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(description, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 14),
          if (rows.isEmpty)
            Text(context.tr('No matching visits', '没有匹配访问'))
          else
            for (final row in rows) ...[
              Row(
                children: [
                  SizedBox(
                    width: 72,
                    child: Text(
                      row.label,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  Expanded(
                    child: Semantics(
                      label: context.tr(
                        '${row.label}: ${row.count} $subjectLabel',
                        '${row.label}：${row.count} $subjectLabel',
                      ),
                      child: LinearProgressIndicator(
                        value: denominator == 0 ? 0 : row.count / denominator,
                        minHeight: 10,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 92,
                    child: Text(
                      '${row.count} · ${denominator == 0 ? 0 : (row.count * 100 / denominator).round()}%',
                      textAlign: TextAlign.end,
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
            ],
        ],
      ),
    ),
  );
}
