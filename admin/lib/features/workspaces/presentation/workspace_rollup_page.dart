import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/i18n/app_i18n.dart';
import '../../../shared/presentation/app_back_button.dart';
import '../../../shared/presentation/page_help_button.dart';
import '../../sites/application/site_controller.dart';
import '../application/workspace_rollup_controller.dart';

class WorkspaceRollupPage extends ConsumerStatefulWidget {
  const WorkspaceRollupPage({required this.workspaceId, super.key});

  final String workspaceId;

  @override
  ConsumerState<WorkspaceRollupPage> createState() =>
      _WorkspaceRollupPageState();
}

class _WorkspaceRollupPageState extends ConsumerState<WorkspaceRollupPage> {
  late DateTime _from;
  late DateTime _to;
  String? _initializedWorkspace;
  Set<String> _selectedSiteIds = {};

  @override
  void initState() {
    super.initState();
    _to = _dateOnly(DateTime.now());
    _from = _to.subtract(const Duration(days: 29));
  }

  @override
  void didUpdateWidget(covariant WorkspaceRollupPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workspaceId != widget.workspaceId) {
      _initializedWorkspace = null;
      _selectedSiteIds = {};
    }
  }

  @override
  Widget build(BuildContext context) {
    final sites = ref.watch(workspaceRollupSitesProvider(widget.workspaceId));
    return Scaffold(
      backgroundColor: const Color(0xfff3f5f8),
      appBar: AppBar(
        title: Text(context.tr('Workspace roll-up', '工作区汇总')),
        leading: AppBackButton(fallback: '/sites'),
        actions: [
          const PageHelpButton(
            englishTitle: 'Workspace roll-up',
            chineseTitle: '工作区汇总说明',
            englishBody:
                'This report combines metrics from the selected sites. Visitor counts are summed site-local unique visitors and are not deduplicated across domains. Business dates follow each site time zone.',
            chineseBody: '此报表汇总所选站点的数据。访客数是各站点内独立访客数之和，不会跨域去重；业务日期沿用各站点时区。',
          ),
          const LanguageMenu(),
        ],
      ),
      body: sites.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: FilledButton.tonal(
            onPressed: () => ref.invalidate(
              workspaceRollupSitesProvider(widget.workspaceId),
            ),
            child: Text(
              context.tr('Could not load sites · Retry', '无法加载站点 · 重试'),
            ),
          ),
        ),
        data: _buildReport,
      ),
    );
  }

  Widget _buildReport(List<Site> sites) {
    if (_initializedWorkspace != widget.workspaceId) {
      _initializedWorkspace = widget.workspaceId;
      _selectedSiteIds = sites.map((site) => site.id).toSet();
    }
    _selectedSiteIds = _selectedSiteIds.intersection(
      sites.map((site) => site.id).toSet(),
    );
    final selectedSites = sites
        .where((site) => _selectedSiteIds.contains(site.id))
        .toList(growable: false);
    final query = WorkspaceRollupQuery(
      workspaceId: widget.workspaceId,
      siteIds: _selectedSiteIds,
      from: _dateQuery(_from),
      to: _dateQuery(_to),
    );
    final report = selectedSites.isEmpty
        ? null
        : ref.watch(workspaceRollupProvider(query));
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
      children: [
        Text(
          context.tr(
            'Compare traffic across the sites your team manages.',
            '对比团队所管理多个站点的流量表现。',
          ),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 6),
        Text(
          context.tr(
            'Counts are summed from site-level reports; visitor identities are not joined across domains.',
            '指标由站点级报表求和；不会跨域关联访客身份。',
          ),
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: const Color(0xff5b6879)),
        ),
        const SizedBox(height: 16),
        Card(
          elevation: 0,
          color: Colors.white,
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.date_range),
                title: Text(context.tr('Reporting period', '统计周期')),
                subtitle: Text('${_dateQuery(_from)} – ${_dateQuery(_to)}'),
                trailing: OutlinedButton.icon(
                  onPressed: () => _chooseRange(),
                  icon: const Icon(Icons.edit_calendar_outlined),
                  label: Text(context.tr('Change dates', '调整日期')),
                ),
              ),
              const Divider(height: 1),
              ExpansionTile(
                leading: const Icon(Icons.language),
                title: Text(
                  context.tr('Sites', '站点'),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  context.tr(
                    '${_selectedSiteIds.length} of ${sites.length} included',
                    '已纳入 ${_selectedSiteIds.length} / ${sites.length} 个站点',
                  ),
                ),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: 8,
                      children: [
                        TextButton.icon(
                          onPressed: () => setState(() {
                            _selectedSiteIds = sites
                                .map((site) => site.id)
                                .toSet();
                          }),
                          icon: const Icon(Icons.select_all),
                          label: Text(context.tr('Select all', '全选')),
                        ),
                        TextButton.icon(
                          onPressed: () =>
                              setState(() => _selectedSiteIds = {}),
                          icon: const Icon(Icons.deselect),
                          label: Text(context.tr('Clear selection', '清空选择')),
                        ),
                      ],
                    ),
                  ),
                  for (final site in sites)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      value: _selectedSiteIds.contains(site.id),
                      onChanged: (checked) => setState(() {
                        if (checked == true) {
                          _selectedSiteIds.add(site.id);
                        } else {
                          _selectedSiteIds.remove(site.id);
                        }
                      }),
                      title: Text(site.name),
                      subtitle: Text(
                        '${site.timezone} · ${site.trackingEnabled ? context.tr('tracking on', '采集中') : context.tr('tracking off', '已停用追踪')}',
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (selectedSites.isEmpty)
          _EmptyPanel(
            icon: Icons.filter_alt_off_outlined,
            message: context.tr(
              'Select at least one site to view its roll-up.',
              '至少选择一个站点以查看汇总数据。',
            ),
          )
        else
          report!.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(48),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, _) => _EmptyPanel(
              icon: Icons.error_outline,
              message: context.tr(
                'Could not load the roll-up report. Check your access and retry.',
                '无法加载汇总报表，请检查访问权限后重试。',
              ),
            ),
            data: _reportContent,
          ),
      ],
    );
  }

  Widget _reportContent(WorkspaceRollupReport report) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth > 900
              ? (constraints.maxWidth - 36) / 4
              : constraints.maxWidth > 580
              ? (constraints.maxWidth - 12) / 2
              : constraints.maxWidth;
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(
                width: width,
                child: _RollupMetric(
                  icon: Icons.visibility_outlined,
                  label: context.tr('Page views', '页面浏览'),
                  value: _formatCount(report.pageViews),
                  accent: const Color(0xff315f9a),
                ),
              ),
              SizedBox(
                width: width,
                child: _RollupMetric(
                  icon: Icons.people_outline,
                  label: context.tr('Site visitors · summed', '站点访客 · 求和'),
                  value: _formatCount(report.siteVisitors),
                  accent: const Color(0xff28806d),
                ),
              ),
              SizedBox(
                width: width,
                child: _RollupMetric(
                  icon: Icons.route_outlined,
                  label: context.tr('Visits', '访问次数'),
                  value: _formatCount(report.sessions),
                  accent: const Color(0xff8958a4),
                ),
              ),
              SizedBox(
                width: width,
                child: _RollupMetric(
                  icon: Icons.exit_to_app_outlined,
                  label: context.tr('Weighted bounce rate', '加权跳出率'),
                  value: '${(report.bounceRate * 100).toStringAsFixed(1)}%',
                  accent: const Color(0xffba7440),
                ),
              ),
            ],
          );
        },
      ),
      const SizedBox(height: 16),
      _RollupPanel(
        title: context.tr('Traffic trend', '流量趋势'),
        subtitle: context.tr(
          'Daily page views · calendar dates use each site’s configured time zone',
          '每日页面浏览 · 日历日期沿用各站点配置的时区',
        ),
        child: Column(
          children: [
            SizedBox(
              height: 208,
              width: double.infinity,
              child: _RollupTrend(
                report.daily.map((item) => item.pageViews).toList(),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [Text(report.from), Text(report.to)],
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      LayoutBuilder(
        builder: (context, constraints) {
          final sitesPanel = _RollupPanel(
            title: context.tr('Site comparison', '站点对比'),
            subtitle: context.tr(
              '${report.siteCount} selected sites · select a row to open its dashboard',
              '已选 ${report.siteCount} 个站点 · 选择一行可打开对应仪表盘',
            ),
            child: _SiteComparison(sites: report.sites),
          );
          final channelsPanel = _RollupPanel(
            title: context.tr('Acquisition channels', '获客渠道'),
            subtitle: context.tr('Summed visits', '访问次数求和'),
            child: _ChannelBreakdown(channels: report.channels),
          );
          return constraints.maxWidth > 920
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 7, child: sitesPanel),
                    const SizedBox(width: 14),
                    Expanded(flex: 4, child: channelsPanel),
                  ],
                )
              : Column(
                  children: [
                    sitesPanel,
                    const SizedBox(height: 14),
                    channelsPanel,
                  ],
                );
        },
      ),
      const SizedBox(height: 8),
      Text(
        context.tr(
          'Unique visitors are deduplicated within each site only, then summed. They are not global people counts. Daily rows group each site’s local business date; sites in different time zones can have different day boundaries.',
          '独立访客只在各站点内去重后求和，不代表跨站点的全局人数。每日数据按各站点本地业务日期汇总；不同站点的自然日边界可能不同。',
        ),
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: const Color(0xff657386)),
      ),
    ],
  );

  Future<void> _chooseRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _from, end: _to),
      helpText: context.tr('Select reporting period', '选择统计周期'),
    );
    if (!mounted || picked == null) return;
    setState(() {
      _from = _dateOnly(picked.start);
      _to = _dateOnly(picked.end);
    });
  }

  static DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static String _dateQuery(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
}

String _formatCount(int value) => value.toString().replaceAllMapped(
  RegExp(r'\B(?=(\d{3})+(?!\d))'),
  (_) => ',',
);

class _RollupMetric extends StatelessWidget {
  const _RollupMetric({
    required this.icon,
    required this.label,
    required this.value,
    required this.accent,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color accent;

  @override
  Widget build(BuildContext context) => Card(
    elevation: 0,
    color: Colors.white,
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: accent),
          const SizedBox(height: 14),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    ),
  );
}

class _RollupPanel extends StatelessWidget {
  const _RollupPanel({required this.title, required this.child, this.subtitle});

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
    elevation: 0,
    color: Colors.white,
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          if (subtitle != null) ...[
            const SizedBox(height: 3),
            Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
          ],
          const Divider(height: 26),
          child,
        ],
      ),
    ),
  );
}

class _SiteComparison extends StatelessWidget {
  const _SiteComparison({required this.sites});

  final List<WorkspaceRollupSite> sites;

  @override
  Widget build(BuildContext context) {
    if (sites.isEmpty) {
      return _EmptyPanel(
        icon: Icons.language,
        message: context.tr('No site metrics in this period.', '此周期暂无站点数据。'),
      );
    }
    final maxViews = math.max(
      1,
      sites.map((site) => site.pageViews).reduce(math.max),
    );
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            children: [
              Expanded(
                flex: 4,
                child: Text(
                  context.tr('Site and visits', '站点与访问'),
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 5,
                child: Text(
                  context.tr('Page views', '页面浏览'),
                  textAlign: TextAlign.end,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
              const SizedBox(width: 16),
              SizedBox(
                width: 72,
                child: Text(
                  context.tr('Bounce', '跳出率'),
                  textAlign: TextAlign.end,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 12),
        for (final site in sites)
          InkWell(
            onTap: () => context.go('/sites/${site.siteId}/dashboard'),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 9),
              child: Row(
                children: [
                  Expanded(
                    flex: 4,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                site.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (!site.trackingEnabled)
                              Tooltip(
                                message: context.tr(
                                  'Tracking disabled',
                                  '追踪已停用',
                                ),
                                child: const Icon(
                                  Icons.pause_circle_outline,
                                  size: 16,
                                ),
                              ),
                          ],
                        ),
                        Text(
                          '${site.timezone} · ${_formatCount(site.sessions)} ${context.tr('visits', '次访问')}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 5,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(_formatCount(site.pageViews)),
                        const SizedBox(height: 5),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(5),
                          child: LinearProgressIndicator(
                            minHeight: 7,
                            value: site.pageViews / maxViews,
                            backgroundColor: const Color(0xffedf1f5),
                            color: const Color(0xff3766a0),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  SizedBox(
                    width: 72,
                    child: Text(
                      '${(site.bounceRate * 100).toStringAsFixed(1)}%',
                      textAlign: TextAlign.end,
                      style: Theme.of(context).textTheme.bodySmall,
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

class _ChannelBreakdown extends StatelessWidget {
  const _ChannelBreakdown({required this.channels});

  final List<WorkspaceRollupChannel> channels;

  @override
  Widget build(BuildContext context) {
    if (channels.isEmpty) {
      return _EmptyPanel(
        icon: Icons.trending_up,
        message: context.tr('No channel data in this period.', '此周期暂无渠道数据。'),
      );
    }
    final total = channels.fold<int>(0, (sum, item) => sum + item.sessions);
    return Column(
      children: [
        for (final item in channels)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(_channelLabel(context, item.channel))),
                    Text(
                      '${_formatCount(item.sessions)} · ${total == 0 ? 0 : (item.sessions * 100 / total).toStringAsFixed(1)}%',
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: LinearProgressIndicator(
                    minHeight: 8,
                    value: total == 0 ? 0 : item.sessions / total,
                    backgroundColor: const Color(0xffedf1f5),
                    color: const Color(0xff579183),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  String _channelLabel(BuildContext context, String channel) =>
      switch (channel) {
        'direct' => context.tr('Direct', '直接访问'),
        'referral' => context.tr('Referral', '引荐'),
        'campaign' => context.tr('Campaign', '推广活动'),
        _ => channel,
      };
}

class _RollupTrend extends StatelessWidget {
  const _RollupTrend(this.values);

  final List<int> values;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _RollupTrendPainter(values),
    child: const SizedBox.expand(),
  );
}

class _RollupTrendPainter extends CustomPainter {
  const _RollupTrendPainter(this.values);

  final List<int> values;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = const Color(0xffe7ebf1)
      ..strokeWidth = 1;
    for (var row = 1; row <= 3; row++) {
      final y = size.height * row / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    if (values.isEmpty) return;
    final maximum = math.max(1, values.reduce(math.max));
    final path = Path();
    for (var index = 0; index < values.length; index++) {
      final x = values.length == 1
          ? size.width / 2
          : index * size.width / (values.length - 1);
      final y = size.height - 14 - values[index] / maximum * (size.height - 28);
      if (index == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    final fill = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(fill, Paint()..color = const Color(0x223766a0));
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xff3766a0)
        ..strokeWidth = 2.6
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _RollupTrendPainter oldDelegate) =>
      !listEquals(values, oldDelegate.values);
}

class _EmptyPanel extends StatelessWidget {
  const _EmptyPanel({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 28),
    child: Center(
      child: Column(
        children: [
          Icon(icon, size: 30, color: const Color(0xff7a8797)),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}
