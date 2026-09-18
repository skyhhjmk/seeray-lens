import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/i18n/app_i18n.dart';
import '../../../shared/presentation/page_help_button.dart';
import '../../../shared/presentation/site_top_bar.dart';
import '../application/analytics_attribution.dart';
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
  String _basis = 'first_visit';
  String? _goalId;

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
    final goals = ref.watch(analyticsGoalDefinitionsProvider(widget.siteId));
    final enabledGoals = goals.asData?.value
        .where((goal) => goal.enabled)
        .toList(growable: false);
    final selectedGoalId =
        enabledGoals?.any((goal) => goal.id == _goalId) == true
        ? _goalId
        : null;
    final query = AnalyticsCohortQuery(
      siteId: widget.siteId,
      range: range.range,
      segmentId: segmentId,
      weeks: _weeks,
      basis: _basis,
      goalId: selectedGoalId,
    );
    final report = _basis == 'first_visit' || selectedGoalId != null
        ? ref.watch(analyticsCohortProvider(query))
        : null;
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
                    'Choose cohorts by first meaningful visit or first conversion of a configured goal. Each later cell shows the share that started another meaningful session in that calendar week. Incomplete weeks are left blank.',
                chineseBody:
                    '可按首次有效访问或首次达成指定目标的时间分组。后续单元格显示该队列在对应自然周再次开始有效访问的比例；尚未完整结束的周留空。',
              ),
              rangeState: range,
              segmentFilter: SegmentFilterSelector(siteId: widget.siteId),
              onSelectRange: () => _selectRange(context, range),
              onRefresh: () {
                ref.invalidate(analyticsGoalDefinitionsProvider(widget.siteId));
                ref.invalidate(analyticsCohortProvider);
              },
            ),
      body: _CohortReport(
        siteId: widget.siteId,
        goals: goals,
        basis: _basis,
        selectedGoalId: selectedGoalId,
        report: report,
        onBasisChanged: (basis) => setState(() {
          _basis = basis;
          _goalId = null;
        }),
        onGoalChanged: (goalId) => setState(() => _goalId = goalId),
        weeks: _weeks,
        segmentSelected: segmentId != null,
        onWeeksChanged: (weeks) => setState(() => _weeks = weeks),
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
    required this.siteId,
    required this.goals,
    required this.basis,
    required this.selectedGoalId,
    required this.report,
    required this.onBasisChanged,
    required this.onGoalChanged,
    required this.weeks,
    required this.segmentSelected,
    required this.onWeeksChanged,
  });

  final String siteId;
  final AsyncValue<List<AttributionGoal>> goals;
  final String basis;
  final String? selectedGoalId;
  final AsyncValue<List<AnalyticsCohortCell>>? report;
  final ValueChanged<String> onBasisChanged;
  final ValueChanged<String?> onGoalChanged;
  final int weeks;
  final bool segmentSelected;
  final ValueChanged<int> onWeeksChanged;

  @override
  Widget build(BuildContext context) {
    final currentReport = report;
    final cells = currentReport?.asData?.value ?? const <AnalyticsCohortCell>[];
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
            basis == 'first_visit'
                ? 'See whether visitors return after their first meaningful visit. A return is a new meaningful session; cohorts use anonymous session facts.'
                : 'See whether visitors return after their first conversion of the selected goal. Return activity is still measured as a meaningful session.',
            basis == 'first_visit'
                ? '查看访客首次有效访问后是否回访。回访按新的有效访问计算；队列使用匿名会话事实。'
                : '查看访客首次达成所选目标后是否回访；后续回访仍按新的有效访问计算。',
          ),
        ),
        const SizedBox(height: 16),
        _cohortDefinitionCard(context),
        const SizedBox(height: 12),
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
                    basis == 'first_visit'
                        ? 'Week 0 is the first meaningful-visit week. A visitor is retained later when another meaningful session starts that week. The selected segment is evaluated on the qualifying first visit.'
                        : 'Week 0 is the week of the visitor’s first conversion for the selected goal. Later retention means a meaningful session; the selected segment is evaluated on that conversion session.',
                    basis == 'first_visit'
                        ? '第 0 周是首次有效访问周。后续自然周中再次开始有效访问，即计为留存。所选分群按首次有效访问判断。'
                        : '第 0 周是访客首次达成所选目标的周；后续留存仍按有效访问计算。所选分群按首次目标转化会话判断。',
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
        if (basis == 'goal_conversion' && selectedGoalId == null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                goals.hasError
                    ? context.tr(
                        'Configured goals could not be loaded. Retry or open goal management.',
                        '无法加载已配置目标。请重试或打开目标管理。',
                      )
                    : context.tr(
                        'Select an enabled goal to build conversion cohorts.',
                        '选择一个已启用的目标以查看转化队列。',
                      ),
              ),
            ),
          )
        else if (currentReport == null || currentReport.isLoading)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(28),
              child: Center(child: CircularProgressIndicator()),
            ),
          )
        else if (currentReport.hasError)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                context.tr(
                  'Could not load cohort retention. Check the date range and selected audience, then try again.',
                  '无法加载队列留存。请检查日期范围和所选分群后重试。',
                ),
              ),
            ),
          )
        else if (cohorts.isEmpty)
          Card(
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                children: [
                  const Icon(Icons.groups_2_outlined, size: 38),
                  const SizedBox(height: 10),
                  Text(
                    context.tr(
                      basis == 'first_visit'
                          ? 'No cohorts in this period'
                          : 'No visitors converted this goal in the selected period',
                      basis == 'first_visit' ? '此日期范围暂无队列' : '所选日期范围内没有访客达成此目标',
                    ),
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
                        label: Text(
                          context.tr(
                            basis == 'first_visit'
                                ? 'First visit week'
                                : 'First conversion week',
                            basis == 'first_visit' ? '首次访问周' : '首次转化周',
                          ),
                        ),
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
                                    basis == 'first_visit'
                                        ? 'Week 0: first meaningful-visit week'
                                        : 'Week 0: first goal-conversion week',
                                    basis == 'first_visit'
                                        ? '第 0 周：首次有效访问周'
                                        : '第 0 周：首次目标转化周',
                                  )
                                : context.tr(
                                    basis == 'first_visit'
                                        ? 'Week $index after the first visit'
                                        : 'Week $index after the first conversion',
                                    basis == 'first_visit'
                                        ? '首次访问后的第 $index 周'
                                        : '首次转化后的第 $index 周',
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

  Widget _cohortDefinitionCard(BuildContext context) {
    final enabledGoals =
        goals.asData?.value
            .where((goal) => goal.enabled)
            .toList(growable: false) ??
        const <AttributionGoal>[];
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.tr('Cohort definition', '队列定义'),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: basis,
              decoration: InputDecoration(
                labelText: context.tr('Group visitors by', '访客分组依据'),
                border: const OutlineInputBorder(),
              ),
              items: [
                DropdownMenuItem(
                  value: 'first_visit',
                  child: Text(context.tr('First meaningful visit', '首次有效访问')),
                ),
                DropdownMenuItem(
                  value: 'goal_conversion',
                  child: Text(context.tr('First goal conversion', '首次目标转化')),
                ),
              ],
              onChanged: (value) {
                if (value != null) onBasisChanged(value);
              },
            ),
            if (basis == 'goal_conversion') ...[
              const SizedBox(height: 10),
              if (goals.isLoading)
                const LinearProgressIndicator()
              else if (goals.hasError || enabledGoals.isEmpty)
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        goals.hasError
                            ? context.tr('Could not load goals.', '无法加载目标。')
                            : context.tr(
                                'Create and enable a goal to use conversion cohorts.',
                                '请先创建并启用一个目标，再使用转化队列。',
                              ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => context.go('/sites/$siteId/goals'),
                      icon: const Icon(Icons.tune),
                      label: Text(context.tr('Manage goals', '管理目标')),
                    ),
                  ],
                )
              else
                DropdownButtonFormField<String>(
                  initialValue: selectedGoalId,
                  decoration: InputDecoration(
                    labelText: context.tr('Conversion goal', '转化目标'),
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    for (final goal in enabledGoals)
                      DropdownMenuItem(
                        value: goal.id,
                        child: Text(goal.name, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: onGoalChanged,
                ),
            ],
          ],
        ),
      ),
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
