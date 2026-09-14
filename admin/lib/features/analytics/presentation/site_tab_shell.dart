import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/presentation/page_help_button.dart';
import '../../../shared/presentation/site_top_bar.dart';
import '../application/analytics_controller.dart';
import '../application/analytics_range.dart';

class SiteTabShell extends ConsumerWidget {
  const SiteTabShell({required this.state, required this.child, super.key});
  final GoRouterState state;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = state.uri.path;
    final siteId = state.pathParameters['siteId']!;
    final selected = path.endsWith('/dashboard')
        ? SiteTopTab.dashboard
        : path.endsWith('/visitors')
        ? SiteTopTab.visitors
        : path.endsWith('/acquisition')
        ? SiteTopTab.acquisition
        : path.endsWith('/behaviour')
        ? SiteTopTab.behaviour
        : path.endsWith('/goals')
        ? SiteTopTab.goals
        : path.endsWith('/integration')
        ? SiteTopTab.integration
        : SiteTopTab.settings;
    final isAnalytics =
        selected != SiteTopTab.integration && selected != SiteTopTab.settings;
    final rangeState = isAnalytics
        ? ref.watch(analyticsRangeProvider(siteId))
        : null;
    return Scaffold(
      backgroundColor: const Color(0xfff3f5f8),
      appBar: SiteTopBar(
        siteId: siteId,
        selected: selected,
        help: const PageHelpButton(
          englishTitle: 'Site analytics',
          chineseTitle: '站点分析说明',
          englishBody:
              'Use these tabs to switch reports for the same site. The reporting period is the last 30 days unless a report says otherwise.',
          chineseBody: '使用这些标签切换同一站点的报表。除非页面另有说明，统计周期为最近 30 天。',
        ),
        rangeState: rangeState,
        onSelectRange: rangeState == null
            ? null
            : () => _selectRange(context, ref, siteId, rangeState),
        onRefresh: isAnalytics
            ? () {
                ref.invalidate(analyticsDashboardRangeProvider);
                ref.invalidate(analyticsDashboardProvider);
              }
            : null,
      ),
      body: child,
    );
  }

  Future<void> _selectRange(
    BuildContext context,
    WidgetRef ref,
    String siteId,
    AnalyticsRangeState current,
  ) async {
    final selected = await showAnalyticsRangePicker(context, current);
    if (selected == null) return;
    ref.read(analyticsRangeProvider(siteId).notifier).setRange(selected);
  }
}
