import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/i18n/app_i18n.dart';
import '../../../shared/presentation/app_back_button.dart';
import '../../../shared/presentation/page_help_button.dart';
import '../../../shared/presentation/site_top_bar.dart';
import '../application/analytics_controller.dart';
import '../application/analytics_range.dart';

class AnalyticsDashboardPage extends ConsumerStatefulWidget {
  const AnalyticsDashboardPage({
    required this.siteId,
    this.embedded = false,
    super.key,
  });
  final String siteId;
  final bool embedded;

  @override
  ConsumerState<AnalyticsDashboardPage> createState() =>
      _AnalyticsDashboardPageState();
}

class _AnalyticsDashboardPageState
    extends ConsumerState<AnalyticsDashboardPage> {
  @override
  Widget build(BuildContext context) {
    final rangeState = ref.watch(analyticsRangeProvider(widget.siteId));
    final query = AnalyticsDashboardQuery(widget.siteId, rangeState.range);
    final dashboard = ref.watch(analyticsDashboardRangeProvider(query));
    return Scaffold(
      backgroundColor: const Color(0xfff3f5f8),
      appBar: widget.embedded
          ? null
          : SiteTopBar(
              siteId: widget.siteId,
              selected: SiteTopTab.dashboard,
              help: const PageHelpButton(
                englishTitle: 'Analytics dashboard',
                chineseTitle: '分析仪表盘',
                englishBody:
                    'This dashboard summarizes the selected site for the chosen reporting period. Visitors are exact across the whole range; bounce rate and average visit duration are calculated from sessions.',
                chineseBody:
                    '此仪表盘汇总所选站点在当前统计周期内的数据。独立访客会在整个范围内精确去重；跳出率和平均访问时长由会话数据计算。',
              ),
            ),
      body: dashboard.when(
        loading: () => const _DashboardSkeleton(),
        error: (error, stack) => _DashboardError(
          onRetry: () => ref.invalidate(analyticsDashboardRangeProvider(query)),
        ),
        data: (data) => _DashboardBody(
          data: data,
          rangeState: rangeState,
          onSelectRange: () => _selectRange(rangeState),
        ),
      ),
    );
  }

  Future<void> _selectRange(AnalyticsRangeState current) async {
    final selection = await showAnalyticsRangePicker(context, current);
    if (selection == null || !mounted) return;
    ref
        .read(analyticsRangeProvider(widget.siteId).notifier)
        .setRange(selection);
  }
}

// Kept temporarily for source compatibility with older dashboard snapshots.
// ignore: unused_element
class _TopBar extends ConsumerWidget implements PreferredSizeWidget {
  const _TopBar({required this.siteId, required this.siteName});
  final String siteId;
  final String siteName;

  @override
  Size get preferredSize => const Size.fromHeight(104);

  @override
  Widget build(BuildContext context, WidgetRef ref) => AppBar(
    backgroundColor: const Color(0xff202b3b),
    foregroundColor: Colors.white,
    leading: AppBackButton(fallback: '/sites'),
    titleSpacing: 0,
    title: Text('SeeRay Lens · $siteName', overflow: TextOverflow.ellipsis),
    actions: [
      const PageHelpButton(
        englishTitle: 'Analytics dashboard',
        chineseTitle: '分析仪表盘',
        englishBody:
            'This dashboard summarizes the selected site for the chosen reporting period. Visitors are exact across the whole range; bounce rate and average visit duration are calculated from sessions.',
        chineseBody: '此仪表盘汇总所选站点在当前统计周期内的数据。独立访客会在整个范围内精确去重；跳出率和平均访问时长由会话数据计算。',
      ),
      IconButton(
        tooltip: context.tr('Site settings', '站点设置'),
        onPressed: () => context.go('/sites/$siteId'),
        icon: const Icon(Icons.settings_outlined),
      ),
      const LanguageMenu(),
    ],
    bottom: PreferredSize(
      preferredSize: const Size.fromHeight(48),
      child: Align(
        alignment: Alignment.centerLeft,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.only(left: 12, bottom: 8),
          child: Row(
            children: [
              _NavTab(
                label: context.tr('Dashboard', '仪表盘'),
                route: '/sites/$siteId/dashboard',
                selected: true,
              ),
              _NavTab(
                label: context.tr('Visitors', '访客'),
                route: '/sites/$siteId/visitors',
              ),
              _NavTab(
                label: context.tr('Acquisition', '流量获取'),
                route: '/sites/$siteId/acquisition',
              ),
              _NavTab(
                label: context.tr('Behaviour', '用户行为'),
                route: '/sites/$siteId/behaviour',
              ),
              _NavTab(
                label: context.tr('Goals', '目标'),
                route: '/sites/$siteId/goals',
              ),
              _NavTab(
                label: context.tr('Integration', '集成'),
                route: '/sites/$siteId/integration',
              ),
              _NavTab(
                label: context.tr('Settings', '站点设置'),
                route: '/sites/$siteId',
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _NavTab extends StatelessWidget {
  const _NavTab({
    required this.label,
    required this.route,
    this.selected = false,
  });
  final String label;
  final String route;
  final bool selected;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: TextButton(
      onPressed: selected ? null : () => context.go(route),
      style: TextButton.styleFrom(
        foregroundColor: selected ? Colors.white : const Color(0xffc7d1df),
        backgroundColor: selected
            ? const Color(0xff385172)
            : Colors.transparent,
      ),
      child: Text(label),
    ),
  );
}

class _DashboardBody extends StatelessWidget {
  const _DashboardBody({
    required this.data,
    required this.rangeState,
    required this.onSelectRange,
  });
  final AnalyticsDashboard data;
  final AnalyticsRangeState rangeState;
  final VoidCallback onSelectRange;

  @override
  Widget build(BuildContext context) {
    final o = data.overview;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                analyticsRangeLabel(context, rangeState),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            OutlinedButton.icon(
              onPressed: onSelectRange,
              icon: const Icon(Icons.calendar_today_outlined, size: 18),
              label: Text(analyticsRangeLabel(context, rangeState)),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            _MetricCard(
              icon: Icons.visibility_outlined,
              label: context.tr('Page views', '页面浏览'),
              value: '${o.pageViews}',
            ),
            _MetricCard(
              icon: Icons.people_outline,
              label: context.tr('Unique visitors', '独立访客'),
              value: '${o.uniqueVisitors}',
            ),
            _MetricCard(
              icon: Icons.forum_outlined,
              label: context.tr('Visits', '访问次数'),
              value: '${o.sessions}',
            ),
            _MetricCard(
              icon: Icons.trending_down,
              label: context.tr('Bounce rate', '跳出率'),
              value: '${(o.bounceRate * 100).toStringAsFixed(1)}%',
            ),
            _MetricCard(
              icon: Icons.timer_outlined,
              label: context.tr('Avg. visit duration', '平均访问时长'),
              value: _duration(o.averageSessionDurationMs),
            ),
          ],
        ),
        const SizedBox(height: 18),
        _Panel(
          title: context.tr('Visits over time', '访问趋势'),
          child: data.trend.isEmpty
              ? const _EmptyChart()
              : SizedBox(height: 230, child: _TrendChart(days: data.trend)),
        ),
        const SizedBox(height: 18),
        LayoutBuilder(
          builder: (context, constraints) => constraints.maxWidth > 700
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _PagesPanel(pages: data.pages)),
                    const SizedBox(width: 18),
                    Expanded(child: _TrafficPanel(traffic: data.traffic)),
                  ],
                )
              : Column(
                  children: [
                    _PagesPanel(pages: data.pages),
                    const SizedBox(height: 18),
                    _TrafficPanel(traffic: data.traffic),
                  ],
                ),
        ),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 190,
    child: Card(
      elevation: 0,
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: const Color(0xff3766a0)),
            const SizedBox(height: 15),
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
    ),
  );
}

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.child});
  final String title;
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
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const Divider(height: 28),
          child,
        ],
      ),
    ),
  );
}

class _PagesPanel extends StatelessWidget {
  const _PagesPanel({required this.pages});
  final List<AnalyticsPage> pages;
  @override
  Widget build(BuildContext context) => _Panel(
    title: context.tr('Top pages', '热门页面'),
    child: pages.isEmpty
        ? _TablePlaceholder(label: context.tr('No page views yet', '暂无页面浏览数据'))
        : Column(
            children: pages
                .take(5)
                .map(
                  (page) =>
                      _TableRow(label: page.path, value: '${page.pageViews}'),
                )
                .toList(),
          ),
  );
}

class _TrafficPanel extends StatelessWidget {
  const _TrafficPanel({required this.traffic});
  final List<AnalyticsTraffic> traffic;
  @override
  Widget build(BuildContext context) => _Panel(
    title: context.tr('Traffic channels', '流量渠道'),
    child: traffic.isEmpty
        ? _TablePlaceholder(label: context.tr('No traffic data yet', '暂无流量数据'))
        : Column(
            children: traffic
                .take(5)
                .map(
                  (item) =>
                      _TableRow(label: item.channel, value: '${item.sessions}'),
                )
                .toList(),
          ),
  );
}

class _TableRow extends StatelessWidget {
  const _TableRow({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      children: [
        Expanded(child: Text(label, overflow: TextOverflow.ellipsis)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
      ],
    ),
  );
}

class _TablePlaceholder extends StatelessWidget {
  const _TablePlaceholder({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 125,
    child: Center(
      child: Text(
        label,
        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    ),
  );
}

class _EmptyChart extends StatelessWidget {
  const _EmptyChart();
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 230,
    child: Center(
      child: Text(
        context.tr(
          'Data will appear after your tracker receives events.',
          '追踪器收到事件后，数据将在这里显示。',
        ),
      ),
    ),
  );
}

class _TrendChart extends StatelessWidget {
  const _TrendChart({required this.days});
  final List<AnalyticsDay> days;
  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _TrendPainter(
      days.map((item) => item.sessions.toDouble()).toList(),
    ),
    child: const SizedBox.expand(),
  );
}

class _TrendPainter extends CustomPainter {
  const _TrendPainter(this.values);
  final List<double> values;
  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = const Color(0xffe6eaf0)
      ..strokeWidth = 1;
    for (var i = 1; i < 4; i++) {
      canvas.drawLine(
        Offset(0, size.height * i / 4),
        Offset(size.width, size.height * i / 4),
        grid,
      );
    }
    if (values.isEmpty) {
      return;
    }
    final maxValue = math.max(1, values.reduce(math.max));
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = values.length == 1
          ? size.width / 2
          : i * size.width / (values.length - 1);
      final y = size.height - (values[i] / maxValue * (size.height - 24)) - 12;
      if (i == 0) {
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
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _TrendPainter old) => old.values != values;
}

class _DashboardSkeleton extends StatelessWidget {
  const _DashboardSkeleton();
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: const [
      _Skeleton(height: 32, width: 180),
      SizedBox(height: 20),
      _Skeleton(height: 115),
      SizedBox(height: 18),
      _Skeleton(height: 300),
    ],
  );
}

class _Skeleton extends StatelessWidget {
  const _Skeleton({required this.height, this.width = double.infinity});
  final double height;
  final double width;
  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xffe2e7ed),
        borderRadius: BorderRadius.circular(8),
      ),
    ),
  );
}

class _DashboardError extends StatelessWidget {
  const _DashboardError({required this.onRetry});
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.cloud_off_outlined, size: 42),
        const SizedBox(height: 12),
        Text(context.tr('Analytics could not be loaded.', '无法加载分析数据。')),
        const SizedBox(height: 10),
        FilledButton.tonal(
          onPressed: onRetry,
          child: Text(context.tr('Retry', '重试')),
        ),
      ],
    ),
  );
}

String _duration(int milliseconds) {
  final seconds = milliseconds ~/ 1000;
  return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}
