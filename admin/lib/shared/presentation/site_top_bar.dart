import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n/app_i18n.dart';
import '../../features/analytics/application/analytics_range.dart';
import 'app_back_button.dart';
import 'page_help_button.dart';

enum SiteTopTab {
  dashboard,
  insights,
  annotations,
  realtime,
  visitors,
  visitorInterest,
  visitTime,
  cohorts,
  technology,
  locations,
  acquisition,
  attribution,
  campaignCosts,
  offlineConversions,
  searchConsole,
  bingWebmaster,
  yandexWebmaster,
  behaviour,
  forms,
  media,
  crashes,
  heatmaps,
  recordings,
  dimensions,
  segments,
  goals,
  alerts,
  auditLog,
  scheduledReports,
  integration,
  settings,
}

class SiteTopBar extends StatelessWidget implements PreferredSizeWidget {
  const SiteTopBar({
    required this.siteId,
    required this.selected,
    required this.help,
    this.rangeState,
    this.onSelectRange,
    this.segmentFilter,
    this.onRefresh,
    super.key,
  });
  final String siteId;
  final SiteTopTab selected;
  final PageHelpButton help;
  final AnalyticsRangeState? rangeState;
  final VoidCallback? onSelectRange;
  final Widget? segmentFilter;
  final VoidCallback? onRefresh;

  @override
  Size get preferredSize => const Size.fromHeight(104);

  @override
  Widget build(BuildContext context) => AppBar(
    backgroundColor: const Color(0xff202b3b),
    foregroundColor: Colors.white,
    leading: const AppBackButton(fallback: '/sites'),
    title: const Text('SeeRay Lens'),
    actions: [
      if (rangeState != null && onSelectRange != null)
        TextButton.icon(
          onPressed: onSelectRange,
          icon: const Icon(Icons.date_range_outlined, size: 18),
          label: Text(analyticsRangeLabel(context, rangeState!)),
          style: TextButton.styleFrom(foregroundColor: Colors.white),
        ),
      ?segmentFilter,
      if (onRefresh != null)
        IconButton(
          tooltip: context.tr('Refresh', '刷新'),
          onPressed: onRefresh,
          icon: const Icon(Icons.refresh),
        ),
      help,
      const LanguageMenu(),
    ],
    bottom: PreferredSize(
      preferredSize: const Size.fromHeight(48),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(left: 12, bottom: 8),
        child: Row(
          children: _siteNavGroups
              .map((group) => _groupMenu(context, group))
              .toList(),
        ),
      ),
    ),
  );

  Widget _groupMenu(BuildContext context, _SiteNavGroup group) {
    final active = group.items.any((item) => item.tab == selected);
    final current = group.items
        .where((item) => item.tab == selected)
        .firstOrNull;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: PopupMenuButton<SiteTopTab>(
        tooltip: context.tr(group.english, group.chinese),
        onSelected: (tab) => _go(context, tab),
        itemBuilder: (context) => [
          for (final item in group.items)
            PopupMenuItem<SiteTopTab>(
              value: item.tab,
              child: Row(
                children: [
                  Icon(
                    item.tab == selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Text(context.tr(item.english, item.chinese)),
                ],
              ),
            ),
        ],
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: active ? const Color(0xff385172) : Colors.transparent,
            border: Border.all(
              color: active ? const Color(0xff9eb8db) : const Color(0xff53677f),
            ),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  group.icon,
                  size: 17,
                  color: active ? Colors.white : const Color(0xffc7d1df),
                ),
                const SizedBox(width: 7),
                Text(
                  current == null
                      ? context.tr(group.english, group.chinese)
                      : '${context.tr(group.english, group.chinese)} · ${context.tr(current.english, current.chinese)}',
                  style: TextStyle(
                    color: active ? Colors.white : const Color(0xffc7d1df),
                  ),
                ),
                const SizedBox(width: 3),
                Icon(
                  Icons.arrow_drop_down,
                  size: 18,
                  color: active ? Colors.white : const Color(0xffc7d1df),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _go(BuildContext context, SiteTopTab tab) {
    final item = _siteNavGroups
        .expand((group) => group.items)
        .firstWhere((item) => item.tab == tab);
    final route = item.suffix.isEmpty
        ? '/sites/$siteId'
        : '/sites/$siteId/${item.suffix}';
    context.go(route, extra: tab.index > selected.index ? 1 : -1);
  }
}

class _SiteNavGroup {
  const _SiteNavGroup(this.english, this.chinese, this.icon, this.items);
  final String english;
  final String chinese;
  final IconData icon;
  final List<_SiteNavItem> items;
}

class _SiteNavItem {
  const _SiteNavItem(this.tab, this.english, this.chinese, this.suffix);
  final SiteTopTab tab;
  final String english;
  final String chinese;
  final String suffix;
}

const _siteNavGroups = <_SiteNavGroup>[
  _SiteNavGroup('Overview', '概览', Icons.dashboard_outlined, [
    _SiteNavItem(SiteTopTab.dashboard, 'Dashboard', '仪表盘', 'dashboard'),
    _SiteNavItem(SiteTopTab.insights, 'Insights', '趋势洞察', 'insights'),
    _SiteNavItem(SiteTopTab.annotations, 'Annotations', '分析注释', 'annotations'),
    _SiteNavItem(SiteTopTab.realtime, 'Live', '实时访客', 'realtime'),
  ]),
  _SiteNavGroup('Visitors', '访客', Icons.people_outline, [
    _SiteNavItem(SiteTopTab.visitors, 'Visitors', '访客', 'visitors'),
    _SiteNavItem(
      SiteTopTab.visitorInterest,
      'Engagement',
      '参与度',
      'visitors/engagement',
    ),
    _SiteNavItem(SiteTopTab.visitTime, 'Visit time', '访问时段', 'visitors/time'),
    _SiteNavItem(SiteTopTab.cohorts, 'Cohorts', '留存队列', 'visitors/cohorts'),
    _SiteNavItem(
      SiteTopTab.technology,
      'Technology',
      '访客技术',
      'visitors/technology',
    ),
    _SiteNavItem(SiteTopTab.locations, 'Locations', '地域', 'visitors/locations'),
  ]),
  _SiteNavGroup('Acquisition', '获客', Icons.campaign_outlined, [
    _SiteNavItem(SiteTopTab.acquisition, 'Acquisition', '流量获取', 'acquisition'),
    _SiteNavItem(
      SiteTopTab.attribution,
      'Attribution',
      '归因分析',
      'acquisition/attribution',
    ),
    _SiteNavItem(
      SiteTopTab.campaignCosts,
      'Campaign costs',
      '活动成本',
      'acquisition/campaign-costs',
    ),
    _SiteNavItem(
      SiteTopTab.offlineConversions,
      'Offline conversions',
      '离线转化',
      'acquisition/offline-conversions',
    ),
    _SiteNavItem(
      SiteTopTab.searchConsole,
      'Search Console',
      'Search Console',
      'acquisition/search-console',
    ),
    _SiteNavItem(
      SiteTopTab.bingWebmaster,
      'Bing Webmaster',
      'Bing Webmaster',
      'acquisition/bing-webmaster',
    ),
    _SiteNavItem(
      SiteTopTab.yandexWebmaster,
      'Yandex Webmaster',
      'Yandex Webmaster',
      'acquisition/yandex-webmaster',
    ),
  ]),
  _SiteNavGroup('Behaviour', '行为', Icons.touch_app_outlined, [
    _SiteNavItem(SiteTopTab.behaviour, 'Behaviour', '用户行为', 'behaviour'),
    _SiteNavItem(SiteTopTab.forms, 'Forms', '表单分析', 'behaviour/forms'),
    _SiteNavItem(SiteTopTab.media, 'Media', '媒体分析', 'behaviour/media'),
    _SiteNavItem(SiteTopTab.crashes, 'Crashes', '崩溃分析', 'behaviour/crashes'),
    _SiteNavItem(SiteTopTab.heatmaps, 'Heatmaps', '行为热图', 'behaviour/heatmaps'),
    _SiteNavItem(
      SiteTopTab.recordings,
      'Recordings',
      '会话回放',
      'behaviour/recordings',
    ),
  ]),
  _SiteNavGroup('Configuration', '配置', Icons.tune_outlined, [
    _SiteNavItem(SiteTopTab.dimensions, 'Dimensions', '自定义维度', 'dimensions'),
    _SiteNavItem(SiteTopTab.segments, 'Segments', '用户分群', 'segments'),
    _SiteNavItem(SiteTopTab.goals, 'Goals', '目标', 'goals'),
    _SiteNavItem(SiteTopTab.alerts, 'Alerts', '告警', 'alerts'),
    _SiteNavItem(SiteTopTab.auditLog, 'Audit log', '审计日志', 'audit-log'),
    _SiteNavItem(
      SiteTopTab.scheduledReports,
      'Email reports',
      '邮件报表',
      'scheduled-reports',
    ),
    _SiteNavItem(SiteTopTab.integration, 'Integration', '集成', 'integration'),
    _SiteNavItem(SiteTopTab.settings, 'Settings', '站点设置', ''),
  ]),
];

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
