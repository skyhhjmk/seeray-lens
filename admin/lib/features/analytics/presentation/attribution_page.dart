import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/i18n/app_i18n.dart';
import '../../../shared/presentation/page_help_button.dart';
import '../../../shared/presentation/site_top_bar.dart';
import '../application/analytics_attribution.dart';
import '../application/analytics_range.dart';
import '../application/analytics_segment.dart';

class AttributionPage extends ConsumerStatefulWidget {
  const AttributionPage({
    required this.siteId,
    this.embedded = false,
    super.key,
  });

  final String siteId;
  final bool embedded;

  @override
  ConsumerState<AttributionPage> createState() => _AttributionPageState();
}

class _AttributionPageState extends ConsumerState<AttributionPage> {
  String _model = 'last_touch';
  int _lookbackDays = 30;
  String? _goalId;

  @override
  Widget build(BuildContext context) {
    final range = ref.watch(analyticsRangeProvider(widget.siteId));
    final segmentId = ref.watch(
      analyticsSegmentSelectionProvider(widget.siteId),
    );
    final query = AttributionQuery(
      siteId: widget.siteId,
      range: range.range,
      model: _model,
      lookbackDays: _lookbackDays,
      goalId: _goalId,
      segmentId: segmentId,
    );
    final result = ref.watch(analyticsAttributionProvider(query));
    return Scaffold(
      backgroundColor: const Color(0xfff3f5f8),
      appBar: widget.embedded
          ? null
          : SiteTopBar(
              siteId: widget.siteId,
              selected: SiteTopTab.acquisition,
              help: const PageHelpButton(
                englishTitle: 'Conversion attribution',
                chineseTitle: '转化归因说明',
                englishBody:
                    'Fractionally assigns each unique goal-converting visit across the acquisition visits in its lookback window. Direct visits can receive credit. This is modeled attribution, not causal proof.',
                chineseBody:
                    '将每个目标转化访问按归因窗口中的获客访问分配为小数贡献。直接访问也会参与分配。这是归因模型，不代表因果证明。',
              ),
            ),
      body: result.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Text(
            context.tr('Could not load attribution report', '无法加载归因报表'),
          ),
        ),
        data: (data) => _buildReport(context, data),
      ),
    );
  }

  Widget _buildReport(BuildContext context, AttributionData data) {
    final goals = data.goals.where((goal) => goal.enabled).toList();
    final selectedGoalId = goals.any((goal) => goal.id == _goalId)
        ? _goalId
        : null;
    final report = data.report;
    final goalNames = {for (final goal in goals) goal.id: goal.name};
    final maxConversions = report.rows.fold<double>(
      0,
      (max, row) =>
          row.attributedConversions > max ? row.attributedConversions : max,
    );
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
                    context.tr('Conversion attribution', '转化归因'),
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    context.tr(
                      'Compare how acquisition visits share credit for configured goal conversions.',
                      '比较获客访问如何共同获得已配置目标转化的贡献。',
                    ),
                  ),
                ],
              ),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                TextButton.icon(
                  onPressed: () =>
                      context.go('/sites/${widget.siteId}/acquisition'),
                  icon: const Icon(Icons.arrow_back),
                  label: Text(context.tr('Acquisition', '流量获取')),
                ),
                FilledButton.tonalIcon(
                  onPressed: () => context.go(
                    '/sites/${widget.siteId}/acquisition/campaign-costs',
                  ),
                  icon: const Icon(Icons.payments_outlined),
                  label: Text(context.tr('Campaign costs', '广告活动费用')),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 18),
        Card(
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Wrap(
              spacing: 24,
              runSpacing: 16,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _select<String>(
                  context,
                  label: context.tr('Attribution model', '归因模型'),
                  value: _model,
                  values: const [
                    ('first_touch', 'First touch', '首次触点'),
                    ('last_touch', 'Last touch', '末次触点'),
                    ('linear', 'Linear', '线性'),
                    ('position_based', 'Position-based', '位置权重'),
                    ('time_decay', 'Time decay · 7 days', '时间衰减 · 7 天'),
                  ],
                  onChanged: (value) => setState(() => _model = value),
                ),
                _select<int>(
                  context,
                  label: context.tr('Lookback window', '归因窗口'),
                  value: _lookbackDays,
                  values: const [
                    (7, '7 days', '7 天'),
                    (30, '30 days', '30 天'),
                    (90, '90 days', '90 天'),
                  ],
                  onChanged: (value) => setState(() => _lookbackDays = value),
                ),
                _goalSelector(context, goals, selectedGoalId),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (goals.isEmpty)
          _InfoCard(
            icon: Icons.flag_outlined,
            message: context.tr(
              'Create and enable a goal before attributing conversions.',
              '请先创建并启用目标，再查看转化归因。',
            ),
            action: TextButton(
              onPressed: () => context.go('/sites/${widget.siteId}/goals'),
              child: Text(context.tr('Configure goals', '配置目标')),
            ),
          )
        else ...[
          _SummaryCard(
            conversions: report.attributedConversions,
            value: report.attributedValue,
            model: _modelLabel(context, report.model),
            lookbackDays: report.lookbackDays,
          ),
          const SizedBox(height: 16),
          Card(
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.tr('Attributed acquisition', '获客来源贡献'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    context.tr(
                      'Each conversion contributes a total of 1.0 across its eligible visits. Rows may be fractional.',
                      '每次转化在符合窗口的访问间总计分配 1.0；单行贡献可能是小数。',
                    ),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const Divider(height: 28),
                  if (report.rows.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text(
                          context.tr(
                            'No matching goal conversions in this period.',
                            '所选周期内没有符合条件的目标转化。',
                          ),
                        ),
                      ),
                    )
                  else
                    for (final row in report.rows)
                      _AttributionRow(
                        row: row,
                        goalName: goalNames[row.goalId] ?? row.goalName,
                        maxConversions: maxConversions,
                      ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _goalSelector(
    BuildContext context,
    List<AttributionGoal> goals,
    String? selectedGoalId,
  ) => _select<String>(
    context,
    label: context.tr('Goal', '目标'),
    value: selectedGoalId ?? '',
    values: [
      ('', 'All enabled goals', '所有已启用目标'),
      ...goals.map((goal) => (goal.id, goal.name, goal.name)),
    ],
    onChanged: (value) =>
        setState(() => _goalId = value.isEmpty ? null : value),
  );

  Widget _select<T>(
    BuildContext context, {
    required String label,
    required T value,
    required List<(T, String, String)> values,
    required ValueChanged<T> onChanged,
  }) => SizedBox(
    width: 230,
    child: DropdownButtonFormField<T>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      items: values
          .map(
            (item) => DropdownMenuItem<T>(
              value: item.$1,
              child: Text(
                context.tr(item.$2, item.$3),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          )
          .toList(growable: false),
      onChanged: (selected) {
        if (selected != null) onChanged(selected);
      },
    ),
  );

  String _modelLabel(BuildContext context, String model) => switch (model) {
    'first_touch' => context.tr('First touch', '首次触点'),
    'linear' => context.tr('Linear', '线性'),
    'position_based' => context.tr('Position-based', '位置权重'),
    'time_decay' => context.tr('Time decay', '时间衰减'),
    _ => context.tr('Last touch', '末次触点'),
  };
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.icon, required this.message, this.action});

  final IconData icon;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Card(
    elevation: 0,
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Icon(icon),
          const SizedBox(width: 12),
          Expanded(child: Text(message)),
          ?action,
        ],
      ),
    ),
  );
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.conversions,
    required this.value,
    required this.model,
    required this.lookbackDays,
  });

  final double conversions;
  final double value;
  final String model;
  final int lookbackDays;

  @override
  Widget build(BuildContext context) => Card(
    elevation: 0,
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Wrap(
        spacing: 40,
        runSpacing: 18,
        children: [
          _SummaryMetric(
            label: context.tr('Attributed conversions', '归因转化'),
            value: conversions.toStringAsFixed(2),
          ),
          _SummaryMetric(
            label: context.tr('Attributed goal value', '归因目标价值'),
            value: value.toStringAsFixed(2),
          ),
          _SummaryMetric(
            label: context.tr('Rule', '规则'),
            value: '$model · $lookbackDays ${context.tr('days', '天')}',
          ),
        ],
      ),
    ),
  );
}

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 205,
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

class _AttributionRow extends StatelessWidget {
  const _AttributionRow({
    required this.row,
    required this.goalName,
    required this.maxConversions,
  });

  final AttributionRow row;
  final String goalName;
  final double maxConversions;

  @override
  Widget build(BuildContext context) {
    final detail = <String?>[
      row.source,
      row.medium == null ? null : '(${row.medium})',
      row.campaign,
    ].whereType<String>().where((value) => value.isNotEmpty).join(' · ');
    final fraction = maxConversions <= 0
        ? 0.0
        : (row.attributedConversions / maxConversions).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(_channelIcon(row.channel), size: 20),
          const SizedBox(width: 12),
          Expanded(
            flex: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_channelLabel(context, row.channel)} · $goalName',
                  overflow: TextOverflow.ellipsis,
                ),
                if (detail.isNotEmpty)
                  Text(
                    detail,
                    style: Theme.of(context).textTheme.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                const SizedBox(height: 5),
                LinearProgressIndicator(value: fraction, minHeight: 4),
              ],
            ),
          ),
          const SizedBox(width: 16),
          SizedBox(
            width: 90,
            child: Text(
              row.attributedConversions.toStringAsFixed(2),
              textAlign: TextAlign.end,
            ),
          ),
          SizedBox(
            width: 104,
            child: Text(
              row.attributedValue.toStringAsFixed(2),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}

String _channelLabel(BuildContext context, String channel) => switch (channel) {
  'campaign' => context.tr('Campaign', '营销活动'),
  'referral' => context.tr('Referral', '引荐'),
  'search_engine' => context.tr('Search', '搜索'),
  'social' => context.tr('Social', '社交'),
  'ai_assistant' => context.tr('AI assistant', 'AI 助手'),
  _ => context.tr('Direct', '直接访问'),
};

IconData _channelIcon(String channel) => switch (channel) {
  'campaign' => Icons.campaign_outlined,
  'referral' => Icons.link,
  'search_engine' => Icons.search,
  'social' => Icons.people_outline,
  'ai_assistant' => Icons.auto_awesome_outlined,
  _ => Icons.open_in_browser,
};
