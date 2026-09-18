import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_i18n.dart';
import '../../../shared/presentation/page_help_button.dart';
import '../../../shared/presentation/site_top_bar.dart';
import '../application/analytics_controller.dart';
import '../application/analytics_range.dart';
import '../application/analytics_segment.dart';
import 'segment_filter_selector.dart';

class CohortsPage extends ConsumerStatefulWidget {
  const CohortsPage({required this.siteId, this.embedded = false, super.key});

  final String siteId;
  final bool embedded;

  @override
  ConsumerState<CohortsPage> createState() => _CohortsPageState();
}

class _CohortsPageState extends ConsumerState<CohortsPage> {
  int _weeks = 8;

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
                to.subtract(const Duration(days: 83)),
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
    final query = AnalyticsCohortQuery(
      siteId: widget.siteId,
      range: range.range,
      segmentId: segmentId,
      weeks: _weeks,
    );
    final report = ref.watch(analyticsCohortProvider(query));
    return Scaffold(
      backgroundColor: const Color(0xfff3f5f8),
      appBar: widget.embedded
          ? null
          : SiteTopBar(
              siteId: widget.siteId,
              selected: SiteTopTab.cohorts,
              help: const PageHelpButton(
                englishTitle: 'Cohort retention',
                chineseTitle: '队列留存',
                englishBody:
                    'Visitors are grouped by the week of their first meaningful visit. Each later cell shows the share that started another meaningful session in that calendar week. Incomplete weeks are left blank.',
                chineseBody:
                    '按访客首次有效访问所在周分组。后续单元格显示该队列在对应自然周再次开始有效访问的比例；尚未完整结束的周留空。',
              ),
              rangeState: range,
              segmentFilter: SegmentFilterSelector(siteId: widget.siteId),
              onSelectRange: () => _selectRange(context, range),
              onRefresh: () => ref.invalidate(analyticsCohortProvider),
            ),
      body: report.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              context.tr(
                'Could not load cohort retention. Check the date range and selected segment, then try again.',
                '无法加载队列留存。请检查日期范围和所选分群后重试。',
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
        data: (cells) => _CohortReport(
          cells: cells,
          weeks: _weeks,
          segmentSelected: segmentId != null,
          onWeeksChanged: (weeks) => setState(() => _weeks = weeks),
        ),
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

class _CohortReport extends StatelessWidget {
  const _CohortReport({
    required this.cells,
    required this.weeks,
    required this.segmentSelected,
    required this.onWeeksChanged,
  });

  final List<AnalyticsCohortCell> cells;
  final int weeks;
  final bool segmentSelected;
  final ValueChanged<int> onWeeksChanged;

  @override
  Widget build(BuildContext context) {
    final cohorts = cells.map((cell) => cell.cohortWeek).toSet().toList()
      ..sort((left, right) => right.compareTo(left));
    final grouped = <String, Map<int, AnalyticsCohortCell>>{};
    for (final cell in cells) {
      grouped.putIfAbsent(cell.cohortWeek, () => {})[cell.weekIndex] = cell;
    }
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          context.tr('Cohort retention', '队列留存'),
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 6),
        Text(
          context.tr(
            'See whether visitors return after their first active week. A return is a new meaningful session; cohorts use anonymous first-session facts.',
            '查看访客首次活跃后是否回访。回访按新的有效访问计算；队列使用匿名的首次访问事实。',
          ),
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
                  context.tr('Retention window', '留存观察窗口'),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                SegmentedButton<int>(
                  segments: [
                    ButtonSegment(
                      value: 4,
                      label: Text(context.tr('4 weeks', '4 周')),
                    ),
                    ButtonSegment(
                      value: 8,
                      label: Text(context.tr('8 weeks', '8 周')),
                    ),
                    ButtonSegment(
                      value: 12,
                      label: Text(context.tr('12 weeks', '12 周')),
                    ),
                  ],
                  selected: {weeks},
                  onSelectionChanged: (selection) =>
                      onWeeksChanged(selection.single),
                ),
                const SizedBox(height: 10),
                Text(
                  context.tr(
                    'Week 0 is the first-visit week. A visitor is retained in a later week when a meaningful session starts during that week. The selected segment is evaluated on each visitor’s first active session.',
                    '第 0 周是首次访问周。后续自然周中开始一次有效访问，即计为留存。若选择分群，规则按访客的首次有效访问判断。',
                  ),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (segmentSelected) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(
                        Icons.filter_alt_outlined,
                        size: 16,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        context.tr(
                          'Filtered by the site segment selected above.',
                          '已按上方选择的站点分群筛选。',
                        ),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (cohorts.isEmpty)
          Card(
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                children: [
                  const Icon(Icons.groups_2_outlined, size: 38),
                  const SizedBox(height: 10),
                  Text(
                    context.tr('No cohorts in this period', '此日期范围暂无队列'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    context.tr(
                      'Try a wider date range or remove the selected segment. A cohort appears after a visitor has a page view or another non-heartbeat event.',
                      '请扩大日期范围或取消当前分群。访客至少产生一次页面浏览或其他非心跳事件后才会进入队列。',
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          )
        else
          Card(
            elevation: 0,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          context.tr('Weekly retention', '每周留存'),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      Text(
                        context.tr('Newest cohort first', '最新队列在前'),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const Divider(height: 16),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    headingRowHeight: 44,
                    dataRowMinHeight: 58,
                    dataRowMaxHeight: 58,
                    columnSpacing: 12,
                    columns: [
                      DataColumn(
                        label: Text(context.tr('First week', '首次访问周')),
                      ),
                      DataColumn(
                        numeric: true,
                        label: Text(context.tr('Visitors', '访客数')),
                      ),
                      for (var index = 0; index < weeks; index++)
                        DataColumn(
                          numeric: true,
                          label: Tooltip(
                            message: index == 0
                                ? context.tr(
                                    'Week 0: first-visit week',
                                    '第 0 周：首次访问周',
                                  )
                                : context.tr(
                                    'Week $index after the first-visit week',
                                    '首次访问后的第 $index 周',
                                  ),
                            child: Text('W$index'),
                          ),
                        ),
                    ],
                    rows: [
                      for (final cohortWeek in cohorts)
                        DataRow(
                          cells: [
                            DataCell(Text(cohortWeek)),
                            DataCell(
                              Text(
                                '${grouped[cohortWeek]?[0]?.cohortSize ?? 0}',
                              ),
                            ),
                            for (var index = 0; index < weeks; index++)
                              DataCell(
                                _RetentionCell(
                                  cell: grouped[cohortWeek]?[index],
                                ),
                              ),
                          ],
                        ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 17,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          context.tr(
                            'A dash means that seven-day period has not finished yet; partial weeks are not compared.',
                            '短横线表示该七天观察期尚未结束；未完成的周不会参与对比。',
                          ),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _RetentionCell extends StatelessWidget {
  const _RetentionCell({required this.cell});

  final AnalyticsCohortCell? cell;

  @override
  Widget build(BuildContext context) {
    final current = cell;
    if (current == null || !current.complete) {
      return Tooltip(
        message: context.tr(
          'This seven-day retention period is incomplete.',
          '此七天留存周期尚未完整。',
        ),
        child: Container(
          width: 64,
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(6),
          ),
          child: const Text('—'),
        ),
      );
    }
    final rate = current.retentionRate.clamp(0.0, 1.0);
    return Tooltip(
      message: context.tr(
        '${current.retainedVisitors} of ${current.cohortSize} visitors returned',
        '${current.cohortSize} 位访客中有 ${current.retainedVisitors} 位回访',
      ),
      child: Container(
        width: 64,
        height: 42,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Theme.of(
            context,
          ).colorScheme.primary.withValues(alpha: 0.04 + rate * 0.20),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('${(rate * 100).round()}%'),
            Text(
              '${current.retainedVisitors}/${current.cohortSize}',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
      ),
    );
  }
}
