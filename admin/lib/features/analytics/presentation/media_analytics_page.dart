import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/i18n/app_i18n.dart';
import '../../../shared/presentation/page_help_button.dart';
import '../../../shared/presentation/site_top_bar.dart';
import '../application/analytics_range.dart';
import '../application/media_analytics.dart';

class MediaAnalyticsPage extends ConsumerWidget {
  const MediaAnalyticsPage({
    required this.siteId,
    this.embedded = false,
    super.key,
  });

  final String siteId;
  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final range = ref.watch(analyticsRangeProvider(siteId));
    final query = MediaAnalyticsQuery(siteId: siteId, range: range.range);
    final report = ref.watch(mediaAnalyticsProvider(query));
    return Scaffold(
      backgroundColor: const Color(0xfff3f5f8),
      appBar: embedded
          ? null
          : SiteTopBar(
              siteId: siteId,
              selected: SiteTopTab.media,
              help: const PageHelpButton(
                englishTitle: 'Media analytics',
                chineseTitle: '媒体分析说明',
                englishBody:
                    'Counts only audio/video elements explicitly marked with a stable media ID after the tracker enables media analytics. It records starts, 25/50/75/90% milestones and natural completion; source URLs, titles and media content are never collected.',
                chineseBody:
                    '仅统计追踪代码启用媒体分析且明确标记稳定媒体 ID 的 audio/video 元素。记录开始播放、25/50/75/90% 进度和自然播放完成；不会采集媒体源地址、标题或媒体内容。',
              ),
              rangeState: range,
              onSelectRange: () =>
                  showAnalyticsRangePicker(context, range).then((selected) {
                    if (selected != null) {
                      ref
                          .read(analyticsRangeProvider(siteId).notifier)
                          .setRange(selected);
                    }
                  }),
              onRefresh: () => ref.invalidate(mediaAnalyticsProvider),
            ),
      body: report.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              context.tr(
                'Could not load media analytics. Check the selected date range and try again.',
                '无法加载媒体分析。请检查所选日期范围后重试。',
              ),
            ),
          ),
        ),
        data: (data) => _MediaAnalyticsReport(siteId: siteId, report: data),
      ),
    );
  }
}

class _MediaAnalyticsReport extends StatelessWidget {
  const _MediaAnalyticsReport({required this.siteId, required this.report});

  final String siteId;
  final MediaAnalyticsReport report;

  @override
  Widget build(BuildContext context) {
    final rows = report.rows;
    final starts = rows.fold<int>(0, (sum, row) => sum + row.starts);
    final completions = rows.fold<int>(0, (sum, row) => sum + row.completions);
    final incomplete = rows.fold<int>(
      0,
      (sum, row) => sum + row.incompleteSessions,
    );
    final completionRate = starts == 0 ? 0.0 : completions / starts;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.tr('Media analytics', '媒体分析'),
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    context.tr(
                      'Compare starts, playback milestones and natural completions for marked audio and video.',
                      '比较明确标记的音频/视频播放开始、进度节点和自然播放完成情况。',
                    ),
                  ),
                ],
              ),
            ),
            TextButton.icon(
              onPressed: () =>
                  context.go('/sites/$siteId/integration?tab=media'),
              icon: const Icon(Icons.integration_instructions_outlined),
              label: Text(context.tr('Setup', '接入设置')),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _Metric(label: context.tr('Play starts', '播放开始'), value: starts),
            _Metric(label: context.tr('Completed', '播放完成'), value: completions),
            _Metric(
              label: context.tr('Not completed', '尚未完成'),
              value: incomplete,
            ),
            _Metric(
              label: context.tr('Start → completion', '开始 → 完成率'),
              value: completionRate,
              percent: true,
            ),
          ],
        ),
        const SizedBox(height: 16),
        Card(
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr('Playback by media and page', '按媒体和页面查看播放'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  context.tr(
                    'Milestones count sessions that reached each playback threshold. A completion is recorded only when the browser emits the natural ended event; seeking to the end is not treated as completion.',
                    '进度节点按到达对应播放比例的会话统计。只有浏览器自然触发 ended 事件才记为完成；拖动进度条到结尾不会误算完成。',
                  ),
                ),
                const SizedBox(height: 12),
                if (rows.isEmpty)
                  _EmptyMedia(siteId: siteId)
                else
                  LayoutBuilder(
                    builder: (context, constraints) {
                      if (constraints.maxWidth < 760) {
                        return Column(
                          children: rows
                              .map((row) => _MediaRowCard(row: row))
                              .toList(),
                        );
                      }
                      return SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          columns: [
                            DataColumn(
                              label: Text(
                                context.tr('Media / page', '媒体 / 页面'),
                              ),
                            ),
                            DataColumn(label: Text(context.tr('Type', '类型'))),
                            DataColumn(
                              label: Text(context.tr('Visitors', '访客')),
                            ),
                            DataColumn(label: Text(context.tr('Starts', '开始'))),
                            DataColumn(label: Text('25%')),
                            DataColumn(label: Text('50%')),
                            DataColumn(label: Text('75%')),
                            DataColumn(label: Text('90%')),
                            DataColumn(
                              label: Text(context.tr('Complete', '完成')),
                            ),
                            DataColumn(
                              label: Text(context.tr('Not completed', '尚未完成')),
                            ),
                            DataColumn(
                              label: Text(context.tr('Avg. length', '平均时长')),
                            ),
                            DataColumn(
                              label: Text(context.tr('Completion rate', '完成率')),
                            ),
                          ],
                          rows: rows
                              .map(
                                (row) => DataRow(
                                  cells: [
                                    DataCell(
                                      SizedBox(
                                        width: 190,
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Text(
                                              row.mediaId,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            Text(
                                              row.pagePath,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    DataCell(Text(row.mediaType)),
                                    DataCell(Text('${row.uniqueVisitors}')),
                                    DataCell(Text('${row.starts}')),
                                    DataCell(Text('${row.reached25}')),
                                    DataCell(Text('${row.reached50}')),
                                    DataCell(Text('${row.reached75}')),
                                    DataCell(Text('${row.reached90}')),
                                    DataCell(Text('${row.completions}')),
                                    DataCell(Text('${row.incompleteSessions}')),
                                    DataCell(
                                      Text(
                                        _duration(row.averageDurationSeconds),
                                      ),
                                    ),
                                    DataCell(
                                      Text(
                                        '${(row.completionRate * 100).toStringAsFixed(1)}%',
                                      ),
                                    ),
                                  ],
                                ),
                              )
                              .toList(),
                        ),
                      );
                    },
                  ),
                if (report.hasMore)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      context.tr(
                        'Showing the 100 most active media/page pairs. Narrow the date range to inspect a smaller period.',
                        '当前显示最活跃的 100 个媒体/页面组合；缩小日期范围可查看更细的时间段。',
                      ),
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

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    this.percent = false,
  });
  final String label;
  final num value;
  final bool percent;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 185,
    child: Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            Text(
              percent ? '${(value * 100).toStringAsFixed(1)}%' : '$value',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ],
        ),
      ),
    ),
  );
}

class _MediaRowCard extends StatelessWidget {
  const _MediaRowCard({required this.row});
  final MediaAnalyticsRow row;

  @override
  Widget build(BuildContext context) => Card(
    elevation: 0,
    child: ListTile(
      title: Text(row.mediaId),
      subtitle: Text(
        '${row.mediaType} · ${row.pagePath}\n${context.tr('Visitors', '访客')}: ${row.uniqueVisitors} · ${context.tr('Starts', '开始')}: ${row.starts} · 25%: ${row.reached25} · 50%: ${row.reached50} · 75%: ${row.reached75} · 90%: ${row.reached90} · ${context.tr('Complete', '完成')}: ${row.completions} · ${context.tr('Not completed', '尚未完成')}: ${row.incompleteSessions} · ${_duration(row.averageDurationSeconds)}',
      ),
      isThreeLine: true,
      trailing: Text('${(row.completionRate * 100).toStringAsFixed(1)}%'),
    ),
  );
}

class _EmptyMedia extends StatelessWidget {
  const _EmptyMedia({required this.siteId});
  final String siteId;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 24),
    child: Column(
      children: [
        const Icon(Icons.play_circle_outline, size: 40),
        const SizedBox(height: 8),
        Text(
          context.tr('No media analytics yet', '暂无媒体分析数据'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 6),
        Text(
          context.tr(
            'Enable the opt-in tracker flag and add a stable, non-personal ID to the audio/video elements you want measured.',
            '请启用追踪代码中的媒体分析选项，并为希望统计的 audio/video 元素添加稳定且不含个人信息的 ID。',
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => context.go('/sites/$siteId/integration?tab=media'),
          icon: const Icon(Icons.integration_instructions_outlined),
          label: Text(context.tr('View setup instructions', '查看接入说明')),
        ),
      ],
    ),
  );
}

String _duration(int seconds) =>
    seconds < 60 ? '${seconds}s' : '${seconds ~/ 60}m ${seconds % 60}s';
