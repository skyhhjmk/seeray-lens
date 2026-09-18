import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_i18n.dart';
import '../../../shared/presentation/page_help_button.dart';
import '../../../shared/presentation/site_top_bar.dart';
import '../application/analytics_controller.dart';
import '../application/analytics_range.dart';
import '../application/analytics_segment.dart';
import 'segment_filter_selector.dart';

class VisitTimePage extends ConsumerStatefulWidget {
  const VisitTimePage({required this.siteId, this.embedded = false, super.key});

  final String siteId;
  final bool embedded;

  @override
  ConsumerState<VisitTimePage> createState() => _VisitTimePageState();
}

class _VisitTimePageState extends ConsumerState<VisitTimePage> {
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
    final report = ref.watch(analyticsVisitTimeProvider(query));
    return Scaffold(
      backgroundColor: const Color(0xfff3f5f8),
      appBar: widget.embedded
          ? null
          : SiteTopBar(
              siteId: widget.siteId,
              selected: SiteTopTab.visitTime,
              help: const PageHelpButton(
                englishTitle: 'Visit time',
                chineseTitle: '访问时段说明',
                englishBody:
                    'Each visit is grouped by the local weekday and hour when its session started. The site timezone is used, and each cell can be inspected for its visit count.',
                chineseBody: '按访问开始时站点本地的星期和小时分组。每个格子表示该时段开始的访问次数；日期按站点时区解释。',
              ),
              rangeState: range,
              segmentFilter: SegmentFilterSelector(siteId: widget.siteId),
              onSelectRange: () => _selectRange(context, range),
              onRefresh: () => ref.invalidate(analyticsVisitTimeProvider),
            ),
      body: report.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              context.tr(
                'Could not load visit-time report. Check the date range and selected audience, then try again.',
                '无法加载访问时段报表。请检查日期范围和所选分群后重试。',
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
        data: (cells) => _VisitTimeReport(cells: cells),
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

class _VisitTimeReport extends StatelessWidget {
  const _VisitTimeReport({required this.cells});

  final List<AnalyticsVisitTimeCell> cells;

  static const _englishDays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  static const _chineseDays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

  @override
  Widget build(BuildContext context) {
    final counts = List.generate(7, (_) => List<int>.filled(24, 0));
    for (final cell in cells) {
      if (cell.dayOfWeek >= 0 &&
          cell.dayOfWeek < 7 &&
          cell.hour >= 0 &&
          cell.hour < 24) {
        counts[cell.dayOfWeek][cell.hour] = cell.sessions;
      }
    }
    var peakDay = 0;
    var peakHour = 0;
    var peakSessions = 0;
    var totalSessions = 0;
    var maxSessions = 0;
    for (var day = 0; day < 7; day++) {
      for (var hour = 0; hour < 24; hour++) {
        final value = counts[day][hour];
        totalSessions += value;
        maxSessions = math.max(maxSessions, value);
        if (value > peakSessions) {
          peakSessions = value;
          peakDay = day;
          peakHour = hour;
        }
      }
    }

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          context.tr('Visit time', '访问时段'),
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 6),
        Text(
          context.tr(
            'See when visits begin across the week. Hours follow the site timezone; this report defaults to the last 30 days.',
            '查看一周中访问开始的集中时段。小时按站点时区统计；本报表默认显示最近 30 天。',
          ),
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        if (totalSessions == 0)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                context.tr(
                  'No visits started in this period. Try a longer date range or check that tracking is active.',
                  '所选周期内没有访问。请尝试扩大日期范围，或检查追踪器是否正在采集数据。',
                ),
              ),
            ),
          )
        else ...[
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 980 ? 2 : 1;
              final gap = 14.0;
              final width =
                  (constraints.maxWidth - gap * (columns - 1)) / columns;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  SizedBox(
                    width: width,
                    child: _SummaryCard(
                      label: context.tr('Visits started', '开始访问数'),
                      value: totalSessions,
                      icon: Icons.trending_up_rounded,
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: _SummaryCard(
                      label: context.tr('Busiest hour', '最繁忙时段'),
                      value: context.tr(
                        '${_englishDays[peakDay]} at ${peakHour.toString().padLeft(2, '0')}:00 · $peakSessions visits',
                        '${_chineseDays[peakDay]} ${peakHour.toString().padLeft(2, '0')}:00 · $peakSessions 次访问',
                      ),
                      icon: Icons.schedule_rounded,
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          _VisitTimeGrid(counts: counts, maximum: maxSessions),
        ],
      ],
    );
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

class _VisitTimeGrid extends StatelessWidget {
  const _VisitTimeGrid({required this.counts, required this.maximum});

  final List<List<int>> counts;
  final int maximum;

  static const _englishDays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _chineseDays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr('Visits by weekday and hour', '星期与小时访问分布'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            context.tr(
              'Each visit is counted once, at the hour its session began.',
              '每次访问仅计一次，按会话开始的小时归类。',
            ),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 14),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 942),
              child: Column(
                children: [
                  Row(
                    children: [
                      SizedBox(
                        width: 74,
                        child: Text(
                          context.tr('Day', '星期'),
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ),
                      for (var hour = 0; hour < 24; hour++)
                        SizedBox(
                          width: 36,
                          child: Text(
                            hour.toString().padLeft(2, '0'),
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  for (var day = 0; day < 7; day++) ...[
                    Row(
                      children: [
                        SizedBox(
                          width: 74,
                          child: Text(
                            context.tr(_englishDays[day], _chineseDays[day]),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        for (var hour = 0; hour < 24; hour++)
                          _VisitTimeCell(
                            weekday: context.tr(
                              _englishDays[day],
                              _chineseDays[day],
                            ),
                            hour: hour,
                            sessions: counts[day][hour],
                            maximum: maximum,
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                context.tr('Fewer visits', '较少'),
                style: Theme.of(context).textTheme.labelSmall,
              ),
              const SizedBox(width: 8),
              for (final alpha in [0.18, 0.4, 0.65, 0.88])
                Container(
                  width: 20,
                  height: 14,
                  margin: const EdgeInsets.only(right: 3),
                  decoration: BoxDecoration(
                    color: Color.lerp(
                      const Color(0xffeef2f8),
                      const Color(0xff263b8e),
                      alpha,
                    ),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              const SizedBox(width: 5),
              Text(
                context.tr('More visits', '较多'),
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _VisitTimeCell extends StatelessWidget {
  const _VisitTimeCell({
    required this.weekday,
    required this.hour,
    required this.sessions,
    required this.maximum,
  });

  final String weekday;
  final int hour;
  final int sessions;
  final int maximum;

  @override
  Widget build(BuildContext context) {
    final intensity = sessions == 0 || maximum == 0
        ? 0.0
        : math.sqrt(sessions / maximum);
    final label = context.tr(
      '$weekday ${hour.toString().padLeft(2, '0')}:00 · $sessions visits',
      '$weekday ${hour.toString().padLeft(2, '0')}:00 · $sessions 次访问',
    );
    return SizedBox(
      width: 36,
      height: 34,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        child: Semantics(
          label: label,
          child: Tooltip(
            message: label,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Color.lerp(
                  const Color(0xffeef2f8),
                  const Color(0xff263b8e),
                  intensity,
                ),
                border: Border.all(color: const Color(0xffd9e0eb)),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
