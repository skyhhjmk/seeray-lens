import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/i18n/app_i18n.dart';
import '../application/analytics_controller.dart';
import '../application/analytics_range.dart';
import '../application/analytics_segment.dart';
import '../application/visitor_profile_controller.dart';

class VisitorLogPanel extends ConsumerStatefulWidget {
  const VisitorLogPanel({required this.siteId, super.key});

  final String siteId;

  @override
  ConsumerState<VisitorLogPanel> createState() => _VisitorLogPanelState();
}

class _VisitorLogPanelState extends ConsumerState<VisitorLogPanel> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rangeState = ref.watch(analyticsRangeProvider(widget.siteId));
    final segmentId = ref.watch(
      analyticsSegmentSelectionProvider(widget.siteId),
    );
    final query = AnalyticsDashboardQuery(
      widget.siteId,
      rangeState.range,
      segmentId: segmentId,
    );
    final visits = ref.watch(analyticsVisitorLogProvider(query));

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.manage_search_outlined),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    context.tr('Recent visits', '近期访问'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: context.tr('Refresh', '刷新'),
                  onPressed: () =>
                      ref.invalidate(analyticsVisitorLogProvider(query)),
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              context.tr(
                'Search site-scoped anonymous visits, then open a visitor profile to inspect the selected period. Raw IP addresses are not retained.',
                '搜索站点内的匿名访问记录，并打开访客画像查看所选周期。系统不会留存原始 IP 地址。',
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search),
                hintText: context.tr(
                  'Filter by visitor ID or page',
                  '按访客 ID 或页面筛选',
                ),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: context.tr('Clear search', '清除搜索'),
                        onPressed: () {
                          _search.clear();
                          setState(() {});
                        },
                        icon: const Icon(Icons.close),
                      ),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            visits.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, stack) => ListTile(
                leading: const Icon(Icons.error_outline),
                title: Text(
                  context.tr('Could not load recent visits', '无法加载访问记录'),
                ),
                trailing: TextButton(
                  onPressed: () =>
                      ref.invalidate(analyticsVisitorLogProvider(query)),
                  child: Text(context.tr('Retry', '重试')),
                ),
              ),
              data: (items) {
                final needle = _search.text.trim().toLowerCase();
                final filtered = items
                    .where((item) {
                      if (needle.isEmpty) return true;
                      return item.visitorId.toLowerCase().contains(needle) ||
                          (item.entryPage ?? '').toLowerCase().contains(
                            needle,
                          ) ||
                          (item.exitPage ?? '').toLowerCase().contains(needle);
                    })
                    .toList(growable: false);
                if (filtered.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 22),
                    child: Center(
                      child: Text(
                        items.isEmpty
                            ? context.tr(
                                'No visits in this date range.',
                                '所选日期范围内暂无访问记录。',
                              )
                            : context.tr(
                                'No visits match this search.',
                                '没有匹配的访问记录。',
                              ),
                      ),
                    ),
                  );
                }
                return Column(
                  children: [
                    for (final item in filtered)
                      _VisitorVisitTile(siteId: widget.siteId, entry: item),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          context.tr(
                            'Showing up to 100 recent visits. The visitor profile contains lifetime first/last seen dates and period details for the selected audience.',
                            '最多显示最近 100 次访问。访客画像提供首次/最近出现时间，以及所选分群和周期内的访问详情。',
                          ),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _VisitorVisitTile extends StatelessWidget {
  const _VisitorVisitTile({required this.siteId, required this.entry});

  final String siteId;
  final AnalyticsVisitorLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final shortId = entry.visitorId.length > 12
        ? '${entry.visitorId.substring(0, 8)}…${entry.visitorId.substring(entry.visitorId.length - 4)}'
        : entry.visitorId;
    final path = [entry.entryPage, entry.exitPage]
        .whereType<String>()
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    return Card(
      margin: const EdgeInsets.only(top: 7),
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.surface,
          child: Icon(
            entry.visitorType == 'returning'
                ? Icons.history
                : Icons.person_outline,
          ),
        ),
        title: Text(
          '${context.tr('Visitor', '访客')} $shortId',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          [
            if (path.isNotEmpty) path.join('  →  '),
            '${_date(entry.startedAt)} · ${entry.pageViews} ${context.tr('pages', '页')} · ${entry.events} ${context.tr('events', '事件')}',
          ].join('\n'),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        isThreeLine: true,
        trailing: IconButton(
          tooltip: context.tr('Open visitor profile', '打开访客画像'),
          onPressed: () => context.go(
            '/sites/$siteId/visitors/${Uri.encodeComponent(entry.visitorId)}',
          ),
          icon: const Icon(Icons.arrow_forward),
        ),
        onTap: () => context.go(
          '/sites/$siteId/visitors/${Uri.encodeComponent(entry.visitorId)}',
        ),
      ),
    );
  }

  String _date(DateTime value) => value.toString().substring(0, 16);
}
