import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_i18n.dart';
import '../../../shared/presentation/page_help_button.dart';
import '../../../shared/presentation/site_top_bar.dart';
import '../application/analytics_controller.dart';
import '../application/analytics_insights.dart';
import '../application/analytics_range.dart';
import '../application/analytics_segment.dart';
import 'segment_filter_selector.dart';

class AnalyticsInsightsPage extends ConsumerStatefulWidget {
  const AnalyticsInsightsPage({
    required this.siteId,
    this.embedded = false,
    super.key,
  });

  final String siteId;
  final bool embedded;

  @override
  ConsumerState<AnalyticsInsightsPage> createState() =>
      _AnalyticsInsightsPageState();
}

class _AnalyticsInsightsPageState extends ConsumerState<AnalyticsInsightsPage> {
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
              period: AnalyticsPeriod.last30Days,
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
    final query = AnalyticsInsightsQuery(
      widget.siteId,
      range.range,
      segmentId: segmentId,
    );
    final report = ref.watch(analyticsInsightsProvider(query));
    return Scaffold(
      backgroundColor: const Color(0xfff3f5f8),
      appBar: widget.embedded
          ? null
          : SiteTopBar(
              siteId: widget.siteId,
              selected: SiteTopTab.insights,
              help: const PageHelpButton(
                englishTitle: 'Insights',
                chineseTitle: '趋势洞察',
                englishBody:
                    'Highlights meaningful changes in pages, acquisition, and events against the immediately preceding period of equal length. Small-volume changes are hidden to reduce noise.',
                chineseBody: '对比紧邻的等长前置周期，突出页面、流量来源和事件的显著变化；低基数变化会过滤以降低噪声。',
              ),
              rangeState: range,
              segmentFilter: SegmentFilterSelector(siteId: widget.siteId),
              onSelectRange: () async {
                final selected = await showAnalyticsRangePicker(context, range);
                if (selected == null || !mounted) return;
                ref
                    .read(analyticsRangeProvider(widget.siteId).notifier)
                    .setRange(selected);
              },
              onRefresh: () => ref.invalidate(analyticsInsightsProvider(query)),
            ),
      body: report.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              context.tr(
                'Could not load insights. Check the date range and selected segment, then try again.',
                '无法加载趋势洞察。请检查日期范围和分群后重试。',
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
        data: (data) => _InsightsReportView(report: data),
      ),
    );
  }
}

class _InsightsReportView extends StatelessWidget {
  const _InsightsReportView({required this.report});

  final AnalyticsInsightsReport report;

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<AnalyticsInsightChange>>{};
    for (final change in report.changes) {
      groups.putIfAbsent(change.category, () => []).add(change);
    }
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          context.tr('Insights', '趋势洞察'),
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 4),
        Text(
          context.tr(
            'Current: ${report.from} – ${report.to}    Compared with: ${report.previousFrom} – ${report.previousTo}',
            '当前周期：${report.from} – ${report.to}    对比周期：${report.previousFrom} – ${report.previousTo}',
          ),
        ),
        const SizedBox(height: 8),
        Text(
          context.tr(
            'Changes are ranked within each area. New or disappeared items need at least 20 visits/events; other changes need at least 10 and 25%.',
            '各类变化分别排序。新出现或消失的项目至少需要 20 次访问/事件；其他变化需同时达到至少 10 次且变化幅度不低于 25%。',
          ),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 900
                ? 3
                : constraints.maxWidth >= 580
                ? 2
                : 1;
            final width = (constraints.maxWidth - 12 * (columns - 1)) / columns;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final metric in report.metrics)
                  SizedBox(
                    width: width,
                    child: _MetricCard(metric: metric),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        if (report.changes.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                report.metrics.every(
                      (metric) => metric.current == 0 && metric.previous == 0,
                    )
                    ? context.tr(
                        'No visits were recorded in either comparison period.',
                        '两个对比周期均没有访问数据。',
                      )
                    : context.tr(
                        'No changes met the volume and change thresholds for this period.',
                        '此周期没有变化达到基数和变化幅度门槛。',
                      ),
                textAlign: TextAlign.center,
              ),
            ),
          )
        else ...[
          for (final category in const ['page', 'acquisition', 'event'])
            if (groups[category]?.isNotEmpty ?? false) ...[
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 6, top: 6),
                child: Text(
                  _categoryName(context, category),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              for (final change in groups[category]!)
                _ChangeCard(change: change),
            ],
        ],
      ],
    );
  }

  String _categoryName(BuildContext context, String category) =>
      switch (category) {
        'page' => context.tr('Pages', '页面'),
        'acquisition' => context.tr('Acquisition', '流量获取'),
        'event' => context.tr('Events', '事件'),
        _ => category,
      };
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.metric});
  final AnalyticsInsightMetric metric;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(switch (metric.key) {
            'page_views' => context.tr('Page views', '页面浏览'),
            'unique_visitors' => context.tr('Unique visitors', '独立访客'),
            'sessions' => context.tr('Sessions', '访问次数'),
            _ => metric.label,
          }, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Text(
            _number(metric.current),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 5),
          Text(
            context.tr(
              'Previous ${_number(metric.previous)} · ${_changeLabel(metric.delta, metric.percentChange)}',
              '上期 ${_number(metric.previous)} · ${_changeLabel(metric.delta, metric.percentChange)}',
            ),
          ),
        ],
      ),
    ),
  );
}

class _ChangeCard extends StatelessWidget {
  const _ChangeCard({required this.change});
  final AnalyticsInsightChange change;

  @override
  Widget build(BuildContext context) {
    final up = change.direction == 'increase' || change.direction == 'new';
    final color = change.direction == 'new' || change.direction == 'disappeared'
        ? const Color(0xff546579)
        : up
        ? const Color(0xff1b7f50)
        : const Color(0xffb54738);
    final direction = switch (change.direction) {
      'new' => context.tr('New', '新出现'),
      'disappeared' => context.tr('Disappeared', '已消失'),
      'increase' => context.tr('Increased', '上升'),
      _ => context.tr('Decreased', '下降'),
    };
    final metricName = switch (change.category) {
      'page' => context.tr('Page views', '页面浏览'),
      'acquisition' => context.tr('Sessions', '访问次数'),
      'event' => context.tr('Events', '事件数'),
      _ => change.metric,
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(
              change.direction == 'decrease' ||
                      change.direction == 'disappeared'
                  ? Icons.trending_down
                  : Icons.trending_up,
              color: color,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    change.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (change.detail != null && change.detail!.isNotEmpty)
                    Text(
                      change.detail!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '$direction · ${_changeLabel(change.delta, change.percentChange)}',
                  style: TextStyle(color: color, fontWeight: FontWeight.w600),
                ),
                Text(
                  '$metricName: ${_number(change.previous)} → ${_number(change.current)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _number(int value) => value.toString().replaceAllMapped(
  RegExp(r'\B(?=(\d{3})+(?!\d))'),
  (_) => ',',
);

String _changeLabel(int delta, double? percent) {
  final signed = delta > 0 ? '+$delta' : '$delta';
  return percent == null
      ? signed
      : '$signed (${percent > 0 ? '+' : ''}${percent.toStringAsFixed(1)}%)';
}
