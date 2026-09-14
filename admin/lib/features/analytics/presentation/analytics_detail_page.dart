import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/i18n/app_i18n.dart';
import '../../../shared/presentation/app_back_button.dart';
import '../../../shared/presentation/page_help_button.dart';
import '../../../shared/presentation/site_top_bar.dart';
import '../application/analytics_controller.dart';
import '../application/analytics_range.dart';

enum AnalyticsView { visitors, acquisition, behaviour, goals }

class AnalyticsDetailPage extends ConsumerWidget {
  const AnalyticsDetailPage({
    required this.siteId,
    required this.view,
    this.embedded = false,
    super.key,
  });
  final String siteId;
  final AnalyticsView view;
  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rangeState = ref.watch(analyticsRangeProvider(siteId));
    final query = AnalyticsDashboardQuery(siteId, rangeState.range);
    return Scaffold(
      backgroundColor: const Color(0xfff3f5f8),
      appBar: embedded
          ? null
          : SiteTopBar(
              siteId: siteId,
              selected: switch (view) {
                AnalyticsView.visitors => SiteTopTab.visitors,
                AnalyticsView.acquisition => SiteTopTab.acquisition,
                AnalyticsView.behaviour => SiteTopTab.behaviour,
                AnalyticsView.goals => SiteTopTab.goals,
              },
              help: const PageHelpButton(
                englishTitle: 'Analytics view',
                chineseTitle: '分析视图说明',
                englishBody:
                    'These reports use the selected site and the last 30 days. Empty panels mean no collected matching events yet.',
                chineseBody: '这些报表显示当前站点最近 30 天的数据。空白面板表示尚未采集到匹配事件。',
              ),
            ),
      body: ref
          .watch(analyticsDashboardRangeProvider(query))
          .when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Center(
              child: Text(context.tr('Could not load analytics', '无法加载分析数据')),
            ),
            data: (data) => _Body(view: view, data: data),
          ),
    );
  }
}

// ignore: unused_element
class _AnalyticsBar extends StatelessWidget implements PreferredSizeWidget {
  const _AnalyticsBar({required this.siteId, required this.view});
  final String siteId;
  final AnalyticsView view;
  @override
  Size get preferredSize => const Size.fromHeight(104);
  @override
  Widget build(BuildContext context) => AppBar(
    backgroundColor: const Color(0xff202b3b),
    foregroundColor: Colors.white,
    leading: AppBackButton(fallback: '/sites'),
    title: const Text('SeeRay Lens'),
    actions: const [
      PageHelpButton(
        englishTitle: 'Analytics view',
        chineseTitle: '分析视图说明',
        englishBody:
            'These reports use the selected site and the last 30 days. Empty panels mean no collected matching events yet.',
        chineseBody: '这些报表显示当前站点最近 30 天的数据。空白面板表示尚未采集到匹配事件。',
      ),
      LanguageMenu(),
    ],
    bottom: PreferredSize(
      preferredSize: const Size.fromHeight(48),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(left: 12, bottom: 8),
        child: Row(
          children: [
            _Tab('Dashboard', '仪表盘', '/sites/$siteId/dashboard', false),
            _Tab(
              'Visitors',
              '访客',
              '/sites/$siteId/visitors',
              view == AnalyticsView.visitors,
            ),
            _Tab(
              'Acquisition',
              '流量获取',
              '/sites/$siteId/acquisition',
              view == AnalyticsView.acquisition,
            ),
            _Tab(
              'Behaviour',
              '用户行为',
              '/sites/$siteId/behaviour',
              view == AnalyticsView.behaviour,
            ),
            _Tab(
              'Goals',
              '目标',
              '/sites/$siteId/goals',
              view == AnalyticsView.goals,
            ),
            _Tab('Integration', '集成', '/sites/$siteId/integration', false),
            _Tab('Settings', '站点设置', '/sites/$siteId', false),
          ],
        ),
      ),
    ),
  );
}

class _Tab extends StatelessWidget {
  const _Tab(this.en, this.zh, this.route, this.selected);
  final String en, zh, route;
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
      child: Text(context.tr(en, zh)),
    ),
  );
}

class _Body extends StatelessWidget {
  const _Body({required this.view, required this.data});
  final AnalyticsView view;
  final AnalyticsDashboard data;
  @override
  Widget build(BuildContext context) {
    final rows = switch (view) {
      AnalyticsView.visitors => [
        _Metric('Unique visitors', '独立访客', '${data.visitors.uniqueVisitors}'),
        _Metric('Visits', '访问次数', '${data.visitors.sessions}'),
        _Metric('New visits', '新访问', '${data.visitors.newSessions}'),
        _Metric('Returning visits', '回访', '${data.visitors.returningSessions}'),
        _Metric(
          'Bounce rate',
          '跳出率',
          '${(data.visitors.bounceRate * 100).toStringAsFixed(1)}%',
        ),
      ],
      AnalyticsView.acquisition =>
        data.traffic
            .map(
              (x) => _Metric(
                x.channel,
                x.source ?? 'direct',
                '${x.sessions} ${context.tr('visits', '次访问')}',
              ),
            )
            .toList(),
      AnalyticsView.behaviour => [
        ...data.pages.map(
          (x) => _Metric(x.path, 'Page views', '${x.pageViews}'),
        ),
        ...data.events.map((x) => _Metric(x.type, 'Events', '${x.count}')),
      ],
      AnalyticsView.goals =>
        data.goals
            .map((x) => _Metric(x.name, 'Conversions', '${x.count}'))
            .toList(),
    };
    final title = switch (view) {
      AnalyticsView.visitors => context.tr('Visitor overview', '访客概览'),
      AnalyticsView.acquisition => context.tr('Acquisition', '流量获取'),
      AnalyticsView.behaviour => context.tr('Behaviour', '用户行为'),
      AnalyticsView.goals => context.tr('Goals', '目标'),
    };
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(title, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 16),
        if (rows.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(context.tr('No data collected yet.', '尚未采集到数据。')),
            ),
          )
        else
          ...rows,
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric(this.title, this.subtitle, this.value);
  final String title, subtitle, value;
  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: Text(value, style: Theme.of(context).textTheme.titleLarge),
    ),
  );
}
