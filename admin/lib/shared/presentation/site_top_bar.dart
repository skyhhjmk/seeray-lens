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
          children: [
            _tab(
              context,
              SiteTopTab.dashboard,
              'Dashboard',
              '仪表盘',
              'dashboard',
            ),
            _tab(
              context,
              SiteTopTab.annotations,
              'Annotations',
              '分析注释',
              'annotations',
            ),
            _tab(context, SiteTopTab.insights, 'Insights', '趋势洞察', 'insights'),
            _tab(context, SiteTopTab.realtime, 'Live', '实时访客', 'realtime'),
            _tab(context, SiteTopTab.visitors, 'Visitors', '访客', 'visitors'),
            _tab(
              context,
              SiteTopTab.visitorInterest,
              'Engagement',
              '参与度',
              'visitors/engagement',
            ),
            _tab(
              context,
              SiteTopTab.visitTime,
              'Visit time',
              '访问时段',
              'visitors/time',
            ),
            _tab(
              context,
              SiteTopTab.cohorts,
              'Cohorts',
              '留存队列',
              'visitors/cohorts',
            ),
            _tab(
              context,
              SiteTopTab.technology,
              'Technology',
              '访客技术',
              'visitors/technology',
            ),
            _tab(
              context,
              SiteTopTab.locations,
              'Locations',
              '地域',
              'visitors/locations',
            ),
            _tab(
              context,
              SiteTopTab.acquisition,
              'Acquisition',
              '流量获取',
              'acquisition',
            ),
            _tab(
              context,
              SiteTopTab.behaviour,
              'Behaviour',
              '用户行为',
              'behaviour',
            ),
            _tab(context, SiteTopTab.forms, 'Forms', '表单分析', 'behaviour/forms'),
            _tab(context, SiteTopTab.media, 'Media', '媒体分析', 'behaviour/media'),
            _tab(
              context,
              SiteTopTab.crashes,
              'Crashes',
              '崩溃分析',
              'behaviour/crashes',
            ),
            _tab(
              context,
              SiteTopTab.heatmaps,
              'Heatmaps',
              '行为热图',
              'behaviour/heatmaps',
            ),
            _tab(
              context,
              SiteTopTab.recordings,
              'Recordings',
              '会话回放',
              'behaviour/recordings',
            ),
            _tab(
              context,
              SiteTopTab.dimensions,
              'Dimensions',
              '自定义维度',
              'dimensions',
            ),
            _tab(context, SiteTopTab.segments, 'Segments', '用户分群', 'segments'),
            _tab(context, SiteTopTab.goals, 'Goals', '目标', 'goals'),
            _tab(context, SiteTopTab.alerts, 'Alerts', '告警', 'alerts'),
            _tab(
              context,
              SiteTopTab.auditLog,
              'Audit log',
              '审计日志',
              'audit-log',
            ),
            _tab(
              context,
              SiteTopTab.scheduledReports,
              'Email reports',
              '邮件报表',
              'scheduled-reports',
            ),
            _tab(
              context,
              SiteTopTab.integration,
              'Integration',
              '集成',
              'integration',
            ),
            _tab(context, SiteTopTab.settings, 'Settings', '站点设置', ''),
          ],
        ),
      ),
    ),
  );

  Widget _tab(
    BuildContext context,
    SiteTopTab tab,
    String en,
    String zh,
    String suffix,
  ) {
    final active = selected == tab;
    final route = suffix.isEmpty ? '/sites/$siteId' : '/sites/$siteId/$suffix';
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: TextButton(
        onPressed: active
            ? null
            : () =>
                  context.go(route, extra: tab.index > selected.index ? 1 : -1),
        style: TextButton.styleFrom(
          foregroundColor: active ? Colors.white : const Color(0xffc7d1df),
          backgroundColor: active
              ? const Color(0xff385172)
              : Colors.transparent,
        ),
        child: Text(context.tr(en, zh)),
      ),
    );
  }
}
