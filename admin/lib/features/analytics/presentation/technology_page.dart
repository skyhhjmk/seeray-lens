import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_i18n.dart';
import '../../../shared/presentation/page_help_button.dart';
import '../../../shared/presentation/site_top_bar.dart';
import '../application/analytics_controller.dart';
import '../application/analytics_range.dart';
import '../application/analytics_segment.dart';

class TechnologyPage extends ConsumerWidget {
  const TechnologyPage({
    required this.siteId,
    this.embedded = false,
    super.key,
  });

  final String siteId;
  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final range = ref.watch(analyticsRangeProvider(siteId));
    final segmentId = ref.watch(analyticsSegmentSelectionProvider(siteId));
    final query = AnalyticsDashboardQuery(
      siteId,
      range.range,
      segmentId: segmentId,
    );
    final report = ref.watch(analyticsTechnologyProvider(query));
    return Scaffold(
      backgroundColor: const Color(0xfff3f5f8),
      appBar: embedded
          ? null
          : SiteTopBar(
              siteId: siteId,
              selected: SiteTopTab.technology,
              help: const PageHelpButton(
                englishTitle: 'Technology report',
                chineseTitle: '技术报表说明',
                englishBody:
                    'Browser, operating system, device, language and display details are summarized from each visit’s first page view. Only normalized metadata is collected; the raw browser user agent is not stored.',
                chineseBody:
                    '浏览器、操作系统、设备、语言与显示信息来自每次访问的首个页面浏览。系统只采集归一化信息，不保存原始浏览器 User-Agent。',
              ),
            ),
      body: report.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Text(
            context.tr('Could not load technology report', '无法加载技术报表'),
          ),
        ),
        data: (rows) => _TechnologyReport(rows: rows),
      ),
    );
  }
}

class _TechnologyReport extends StatelessWidget {
  const _TechnologyReport({required this.rows});

  final List<AnalyticsTechnology> rows;

  static const _dimensionOrder = [
    'Browser',
    'Browser version',
    'Operating system',
    'OS version',
    'Device type',
    'Language',
    'Screen size',
    'Viewport size',
    'Display scale',
  ];

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<AnalyticsTechnology>>{};
    for (final row in rows) {
      groups.putIfAbsent(row.dimension, () => []).add(row);
    }
    final dimensions = _dimensionOrder
        .where(groups.containsKey)
        .toList(growable: false);
    if (dimensions.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            context.tr('Technology', '访客技术'),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                context.tr(
                  'No technology data yet. New tracker events will include browser, device, language and display details.',
                  '暂无技术数据。升级后的追踪器会开始采集浏览器、设备、语言与显示信息。',
                ),
              ),
            ),
          ),
        ],
      );
    }
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          context.tr('Technology', '访客技术'),
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 6),
        Text(
          context.tr(
            'Visit-level breakdowns use the first page view in each visit.',
            '以下访问级统计使用每次访问中的首个页面浏览。',
          ),
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 1160
                ? 3
                : constraints.maxWidth >= 760
                ? 2
                : 1;
            const spacing = 16.0;
            final width =
                (constraints.maxWidth - spacing * (columns - 1)) / columns;
            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [
                for (final dimension in dimensions)
                  SizedBox(
                    width: width,
                    child: _TechnologyCard(
                      dimension: dimension,
                      rows: groups[dimension]!,
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _TechnologyCard extends StatelessWidget {
  const _TechnologyCard({required this.dimension, required this.rows});

  final String dimension;
  final List<AnalyticsTechnology> rows;

  @override
  Widget build(BuildContext context) {
    final totalSessions = rows.fold<int>(0, (sum, row) => sum + row.sessions);
    final title = switch (dimension) {
      'Browser' => context.tr('Browsers', '浏览器'),
      'Browser version' => context.tr('Browser versions', '浏览器版本'),
      'Operating system' => context.tr('Operating systems', '操作系统'),
      'OS version' => context.tr('Operating system versions', '系统版本'),
      'Device type' => context.tr('Device types', '设备类型'),
      'Language' => context.tr('Languages', '语言'),
      'Screen size' => context.tr('Screen sizes', '屏幕尺寸'),
      'Viewport size' => context.tr('Viewport sizes', '视口尺寸'),
      _ => context.tr('Display scale', '显示缩放'),
    };
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(child: Text(context.tr('Value', '项目'))),
                Text(context.tr('Visits', '访问')),
                const SizedBox(width: 18),
                Text(context.tr('Visitors', '访客')),
              ],
            ),
            const Divider(height: 16),
            for (final row in rows.take(8)) ...[
              Row(
                children: [
                  Expanded(
                    child: Text(row.value, overflow: TextOverflow.ellipsis),
                  ),
                  SizedBox(
                    width: 54,
                    child: Text('${row.sessions}', textAlign: TextAlign.end),
                  ),
                  SizedBox(
                    width: 64,
                    child: Text('${row.visitors}', textAlign: TextAlign.end),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              LinearProgressIndicator(
                value: totalSessions == 0 ? 0 : row.sessions / totalSessions,
                minHeight: 4,
                borderRadius: BorderRadius.circular(4),
                backgroundColor: const Color(0xffe7ebf0),
              ),
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }
}
