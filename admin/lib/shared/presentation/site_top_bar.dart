import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n/app_i18n.dart';
import '../../features/analytics/application/analytics_range.dart';
import 'app_back_button.dart';
import 'page_help_button.dart';

enum SiteTopTab {
  dashboard,
  visitors,
  acquisition,
  behaviour,
  goals,
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
    this.onRefresh,
    super.key,
  });
  final String siteId;
  final SiteTopTab selected;
  final PageHelpButton help;
  final AnalyticsRangeState? rangeState;
  final VoidCallback? onSelectRange;
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
            _tab(context, SiteTopTab.visitors, 'Visitors', '访客', 'visitors'),
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
            _tab(context, SiteTopTab.goals, 'Goals', '目标', 'goals'),
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
