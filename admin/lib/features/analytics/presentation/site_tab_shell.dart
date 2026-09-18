import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/presentation/page_help_button.dart';
import '../../../shared/presentation/site_top_bar.dart';
import '../application/analytics_controller.dart';
import '../application/analytics_attribution.dart';
import '../application/analytics_range.dart';
import '../application/realtime_controller.dart';
import 'segment_filter_selector.dart';

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
        : path.endsWith('/realtime')
        ? SiteTopTab.realtime
        : path.endsWith('/visitors/cohorts')
        ? SiteTopTab.cohorts
        : path.endsWith('/visitors/technology')
        ? SiteTopTab.technology
        : path.endsWith('/visitors/locations')
        ? SiteTopTab.locations
        : path.contains('/visitors/') || path.endsWith('/visitors')
        ? SiteTopTab.visitors
        : path.contains('/acquisition')
        ? SiteTopTab.acquisition
        : path.endsWith('/behaviour/heatmaps')
        ? SiteTopTab.heatmaps
        : path.endsWith('/behaviour/recordings')
        ? SiteTopTab.recordings
        : path.endsWith('/dimensions')
        ? SiteTopTab.dimensions
        : path.endsWith('/segments')
        ? SiteTopTab.segments
        : path.contains('/behaviour')
        ? SiteTopTab.behaviour
        : path.endsWith('/goals')
        ? SiteTopTab.goals
        : path.endsWith('/alerts')
        ? SiteTopTab.alerts
        : path.endsWith('/audit-log')
        ? SiteTopTab.auditLog
        : path.endsWith('/scheduled-reports')
        ? SiteTopTab.scheduledReports
        : path.endsWith('/integration')
        ? SiteTopTab.integration
        : SiteTopTab.settings;
    final isAnalytics =
        selected != SiteTopTab.integration &&
        selected != SiteTopTab.settings &&
        selected != SiteTopTab.auditLog &&
        selected != SiteTopTab.scheduledReports &&
        selected != SiteTopTab.alerts;
    final supportsSegmentFilter = {
      SiteTopTab.dashboard,
      SiteTopTab.visitors,
      SiteTopTab.cohorts,
      SiteTopTab.technology,
      SiteTopTab.locations,
      SiteTopTab.acquisition,
      SiteTopTab.behaviour,
      SiteTopTab.dimensions,
      SiteTopTab.goals,
    }.contains(selected);
    final rangeState = isAnalytics && selected != SiteTopTab.realtime
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
        segmentFilter: supportsSegmentFilter
            ? SegmentFilterSelector(siteId: siteId)
            : null,
        onRefresh: isAnalytics && selected != SiteTopTab.dimensions
            ? () {
                ref.invalidate(analyticsDashboardRangeProvider);
                ref.invalidate(analyticsDashboardProvider);
                ref.invalidate(analyticsTechnologyProvider);
                ref.invalidate(analyticsCohortProvider);
                ref.invalidate(analyticsLocationProvider);
                ref.invalidate(analyticsRealtimeProvider);
                ref.invalidate(analyticsBehaviourProvider);
                ref.invalidate(analyticsAttributionProvider);
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
