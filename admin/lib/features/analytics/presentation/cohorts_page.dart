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
  String _period = 'week';
  int _periods = 8;
  String _basis = 'first_visit';
  String? _goalId;
  String _metric = 'returning_visitors';
  String? _metricGoalId;

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
    final selectedMetricGoalId =
        enabledGoals?.any((goal) => goal.id == _metricGoalId) == true
        ? _metricGoalId
        : null;
    final query = AnalyticsCohortQuery(
      siteId: widget.siteId,
      range: range.range,
      segmentId: segmentId,
      period: _period,
      periods: _periods,
      basis: _basis,
      goalId: selectedGoalId,
      metric: _metric,
      metricGoalId: selectedMetricGoalId,
    );
    final report =
        (_basis == 'first_visit' || selectedGoalId != null) &&
            (_metric != 'goal_conversions' || selectedMetricGoalId != null)
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
                englishTitle: 'Cohort analysis',
                chineseTitle: '队列分析',
                englishBody:
                    'Choose daily, weekly or monthly cohorts, based on first meaningful visit or first conversion of a configured goal. Compare returning visitors, visits, per-goal conversions, or aggregate goal value; incomplete periods are left blank.',
                chineseBody:
                    '可按日、周或月建立队列，并按首次有效访问或首次目标转化分组。可比较回访访客、访问量、单目标转化或整体目标价值；尚未完整结束的周期留空。',
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
        metric: _metric,
        selectedMetricGoalId: selectedMetricGoalId,
        report: report,
        onBasisChanged: (basis) => setState(() {
          _basis = basis;
          _goalId = null;
        }),
        onGoalChanged: (goalId) => setState(() => _goalId = goalId),
        onMetricChanged: (metric) => setState(() {
          _metric = metric;
          _metricGoalId = null;
        }),
        onMetricGoalChanged: (goalId) => setState(() => _metricGoalId = goalId),
        period: _period,
        periods: _periods,
        onPeriodChanged: (period) => setState(() {
          _period = period;
          _periods = period == 'day'
              ? 14
              : period == 'month'
              ? 6
              : 8;
        }),
        segmentSelected: segmentId != null,
        onPeriodsChanged: (periods) => setState(() => _periods = periods),
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
    required this.metric,
    required this.selectedMetricGoalId,
    required this.report,
    required this.onBasisChanged,
    required this.onGoalChanged,
    required this.onMetricChanged,
    required this.onMetricGoalChanged,
    required this.period,
    required this.periods,
    required this.onPeriodChanged,
    required this.segmentSelected,
    required this.onPeriodsChanged,
  });

  final String siteId;
  final AsyncValue<List<AttributionGoal>> goals;
  final String basis;
  final String? selectedGoalId;
  final String metric;
  final String? selectedMetricGoalId;
  final AsyncValue<List<AnalyticsCohortCell>>? report;
  final ValueChanged<String> onBasisChanged;
  final ValueChanged<String?> onGoalChanged;
  final ValueChanged<String> onMetricChanged;
  final ValueChanged<String?> onMetricGoalChanged;
  final String period;
  final int periods;
  final ValueChanged<String> onPeriodChanged;
  final bool segmentSelected;
  final ValueChanged<int> onPeriodsChanged;

  @override
  Widget build(BuildContext context) {
    final currentReport = report;
    final cells = currentReport?.asData?.value ?? const <AnalyticsCohortCell>[];
    final cohorts = cells.map((cell) => cell.cohortPeriod).toSet().toList()
      ..sort((left, right) => right.compareTo(left));
    final grouped = <String, Map<int, AnalyticsCohortCell>>{};
    for (final cell in cells) {
      grouped.putIfAbsent(cell.cohortPeriod, () => {})[cell.periodIndex] = cell;
    }
    final metricMax = cells.where((cell) => cell.complete).fold<double>(0, (
      maximum,
      cell,
    ) {
      final value = switch (metric) {
        'visits' => cell.visits.toDouble(),
        'goal_value' => cell.goalValue,
        _ => 0.0,
      };
      return value > maximum ? value : maximum;
    });
    final periodName = switch (period) {
      'day' => context.tr('day', '日'),
      'month' => context.tr('month', '月'),
      _ => context.tr('week', '周'),
    };
    final periodTitle = metric == 'goal_conversions'
        ? context.tr('Goal conversion rate', '目标转化率')
        : metric == 'goal_value'
        ? context.tr('Goal value per cohort period', '队列周期目标价值')
        : metric == 'visits'
        ? context.tr('Visits per cohort period', '队列周期访问量')
        : switch (period) {
            'day' => context.tr('Daily retention', '每日留存'),
            'month' => context.tr('Monthly retention', '每月留存'),
            _ => context.tr('Weekly retention', '每周留存'),
          };
    final periodOptions = switch (period) {
      'day' => const [7, 14, 30],
      'month' => const [3, 6, 12],
      _ => const [4, 8, 12],
    };
    final periodNamePlural = switch (period) {
      'day' => 'days',
      'month' => 'months',
      _ => 'weeks',
    };
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          context.tr('Cohort analysis', '队列分析'),
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 6),
        Text(
          context.tr(
            metric == 'goal_conversions'
                ? 'Measure conversions of the selected goal by cohort period. Each cell shows the share of the original cohort that converted; the tooltip includes conversion count and goal value.'
                : metric == 'goal_value'
                ? 'Sum the configured fixed values of all enabled goals for each cohort period. This is goal value, not ecommerce revenue.'
                : metric == 'visits'
                ? 'Count meaningful visits made by each cohort during each calendar period, starting from the cohort entry date.'
                : basis == 'first_visit'
                ? 'See whether visitors return after their first meaningful visit. A return is a new meaningful session; cohorts use anonymous session facts.'
                : 'See whether visitors return after their first conversion of the selected goal. Return activity is still measured as a meaningful session.',
            metric == 'goal_conversions'
                ? '按队列周期统计所选目标的转化。单元格显示原始队列中的转化访客占比；悬浮提示包含转化次数和目标值。'
                : metric == 'goal_value'
                ? '按队列周期合计所有已启用目标配置的固定值；这是目标价值，不是电商收入。'
                : metric == 'visits'
                ? '按自然周期统计各队列产生的有效访问次数，仅计算访客进入队列后的访问。'
                : basis == 'first_visit'
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
                  context.tr('Periods to compare', '留存观察窗口'),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                SegmentedButton<int>(
                  segments: [
                    for (final count in periodOptions)
                      ButtonSegment(
                        value: count,
                        label: Text(
                          context.tr(
                            '$count $periodNamePlural',
                            '$count $periodName',
                          ),
                        ),
                      ),
                  ],
                  selected: {periods},
                  onSelectionChanged: (selection) =>
                      onPeriodsChanged(selection.single),
                ),
                const SizedBox(height: 10),
                Text(
                  context.tr(
                    basis == 'first_visit'
                        ? 'Period 0 is the first meaningful-visit $periodName. A visitor is retained later when another meaningful session starts during that period. The selected segment is evaluated on the qualifying first visit.'
                        : 'Period 0 is the $periodName of the visitor’s first conversion for the selected goal. Later retention means a meaningful session; the selected segment is evaluated on that conversion session.',
                    basis == 'first_visit'
                        ? '第 0 个周期是首次有效访问所在的$periodName。之后在对应周期再次开始有效访问，即计为留存；分群按首次有效访问判断。'
                        : '第 0 个周期是首次达成所选目标所在的$periodName；之后的留存仍按有效访问计算，分群按首次目标转化会话判断。',
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
        if ((basis == 'goal_conversion' && selectedGoalId == null) ||
            (metric == 'goal_conversions' && selectedMetricGoalId == null))
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
                        metric == 'goal_conversions' && basis == 'first_visit'
                            ? 'Select an enabled goal to measure conversions.'
                            : 'Select an enabled goal to build conversion cohorts.',
                        metric == 'goal_conversions' && basis == 'first_visit'
                            ? '选择一个已启用的目标以衡量转化。'
                            : '选择一个已启用的目标以查看转化队列。',
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
                  'Could not load the cohort report. Check the date range and selected audience, then try again.',
                  '无法加载队列报告。请检查日期范围和所选分群后重试。',
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
                          periodTitle,
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
                    dataRowMinHeight: 66,
                    dataRowMaxHeight: 66,
                    columnSpacing: 12,
                    columns: [
                      DataColumn(
                        label: Text(
                          context.tr(
                            basis == 'first_visit'
                                ? 'First visit $periodName'
                                : 'First conversion $periodName',
                            basis == 'first_visit'
                                ? '首次访问$periodName'
                                : '首次转化$periodName',
                          ),
                        ),
                      ),
                      DataColumn(
                        numeric: true,
                        label: Text(context.tr('Visitors', '访客数')),
                      ),
                      for (var index = 0; index < periods; index++)
                        DataColumn(
                          numeric: true,
                          label: Tooltip(
                            message: index == 0
                                ? context.tr(
                                    basis == 'first_visit'
                                        ? 'Period 0: first meaningful-visit $periodName'
                                        : 'Period 0: first goal-conversion $periodName',
                                    basis == 'first_visit'
                                        ? '第 0 个周期：首次有效访问$periodName'
                                        : '第 0 个周期：首次目标转化$periodName',
                                  )
                                : context.tr(
                                    basis == 'first_visit'
                                        ? 'Period $index after the first visit'
                                        : 'Period $index after the first conversion',
                                    basis == 'first_visit'
                                        ? '首次访问后的第 $index 个周期'
                                        : '首次转化后的第 $index 个周期',
                                  ),
                            child: Text('P$index'),
                          ),
                        ),
                    ],
                    rows: [
                      for (final cohortPeriod in cohorts)
                        DataRow(
                          cells: [
                            DataCell(Text(cohortPeriod)),
                            DataCell(
                              Text(
                                '${grouped[cohortPeriod]?[0]?.cohortSize ?? 0}',
                              ),
                            ),
                            for (var index = 0; index < periods; index++)
                              DataCell(
                                _CohortMetricCell(
                                  cell: grouped[cohortPeriod]?[index],
                                  metric: metric,
                                  metricMax: metricMax,
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
                            'A dash means that the full calendar period has not finished yet; partial periods are not compared.',
                            '短横线表示完整自然周期尚未结束；未完成的周期不会参与对比。',
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
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: period,
              decoration: InputDecoration(
                labelText: context.tr('Cohort period', '队列周期'),
                border: const OutlineInputBorder(),
              ),
              items: [
                DropdownMenuItem(
                  value: 'day',
                  child: Text(context.tr('Daily', '按日')),
                ),
                DropdownMenuItem(
                  value: 'week',
                  child: Text(context.tr('Weekly', '按周')),
                ),
                DropdownMenuItem(
                  value: 'month',
                  child: Text(context.tr('Monthly', '按月')),
                ),
              ],
              onChanged: (value) {
                if (value != null) onPeriodChanged(value);
              },
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: metric,
              decoration: InputDecoration(
                labelText: context.tr('Measure', '衡量指标'),
                border: const OutlineInputBorder(),
              ),
              items: [
                DropdownMenuItem(
                  value: 'returning_visitors',
                  child: Text(context.tr('Returning visitors', '回访访客')),
                ),
                DropdownMenuItem(
                  value: 'visits',
                  child: Text(context.tr('Visits', '访问量')),
                ),
                DropdownMenuItem(
                  value: 'goal_value',
                  child: Text(context.tr('Goal value', '目标价值')),
                ),
                DropdownMenuItem(
                  value: 'goal_conversions',
                  child: Text(context.tr('Goal conversions', '目标转化')),
                ),
              ],
              onChanged: (value) {
                if (value != null) onMetricChanged(value);
              },
            ),
            if (metric == 'goal_value' &&
                (goals.hasError ||
                    (!goals.isLoading && enabledGoals.isEmpty))) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      goals.hasError
                          ? context.tr('Could not load goals.', '无法加载目标。')
                          : context.tr(
                              'No enabled goals yet; goal-value cells will be zero.',
                              '尚无已启用目标；队列目标价值将显示为零。',
                            ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => context.go('/sites/$siteId/goals'),
                    icon: const Icon(Icons.tune),
                    label: Text(context.tr('Manage goals', '管理目标')),
                  ),
                ],
              ),
            ],
            if (metric == 'goal_conversions') ...[
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
                                'Create and enable a goal to measure conversions.',
                                '请先创建并启用一个目标，再衡量转化。',
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
                  initialValue: selectedMetricGoalId,
                  decoration: InputDecoration(
                    labelText: context.tr('Metric goal', '指标目标'),
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    for (final goal in enabledGoals)
                      DropdownMenuItem(
                        value: goal.id,
                        child: Text(goal.name, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: onMetricGoalChanged,
                ),
            ],
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

class _CohortMetricCell extends StatelessWidget {
  const _CohortMetricCell({
    required this.cell,
    required this.metric,
    required this.metricMax,
  });

  final AnalyticsCohortCell? cell;
  final String metric;
  final double metricMax;

  @override
  Widget build(BuildContext context) {
    final current = cell;
    if (current == null || !current.complete) {
      return Tooltip(
        message: context.tr(
          'This calendar period is incomplete.',
          '此自然周期尚未完整。',
        ),
        child: Container(
          width: 64,
          height: 54,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(6),
          ),
          child: const Text('—'),
        ),
      );
    }
    final converting = metric == 'goal_conversions';
    final countingVisits = metric == 'visits';
    final countingGoalValue = metric == 'goal_value';
    final rate = countingVisits || countingGoalValue
        ? metricMax <= 0
              ? 0.0
              : (countingVisits ? current.visits : current.goalValue) /
                    metricMax
        : converting
        ? current.cohortSize == 0
              ? 0.0
              : current.goalConvertedVisitors / current.cohortSize
        : current.retentionRate;
    return Tooltip(
      message: context.tr(
        countingVisits
            ? '${current.visits} meaningful visits from ${current.cohortSize} cohort visitors'
            : countingGoalValue
            ? 'Summed fixed value of all enabled goals: ${_formatGoalValue(current.goalValue)} (not ecommerce revenue)'
            : converting
            ? '${current.goalConvertedVisitors} visitors made ${current.goalConversions} conversions; goal value ${current.goalValue}'
            : '${current.retainedVisitors} of ${current.cohortSize} visitors returned',
        countingVisits
            ? '${current.cohortSize} 位队列访客产生了 ${current.visits} 次有效访问'
            : countingGoalValue
            ? '所有已启用目标固定值合计 ${_formatGoalValue(current.goalValue)}（非电商收入）'
            : converting
            ? '${current.cohortSize} 位访客中有 ${current.goalConvertedVisitors} 位转化，共 ${current.goalConversions} 次，目标值 ${current.goalValue}'
            : '${current.cohortSize} 位访客中有 ${current.retainedVisitors} 位回访',
      ),
      child: Container(
        width: 64,
        height: 54,
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
            Text(
              countingVisits
                  ? '${current.visits}'
                  : countingGoalValue
                  ? _formatGoalValue(current.goalValue)
                  : '${(rate * 100).round()}%',
            ),
            Text(
              countingVisits
                  ? context.tr('visits', '次访问')
                  : countingGoalValue
                  ? context.tr('goal value', '目标值')
                  : converting
                  ? '${current.goalConversions} 次'
                  : '${current.retainedVisitors}/${current.cohortSize}',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
      ),
    );
  }
}

String _formatGoalValue(double value) =>
    value.toStringAsFixed(4).replaceFirst(RegExp(r'\.?0+$'), '');
