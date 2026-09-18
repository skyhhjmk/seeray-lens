import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_i18n.dart';
import '../../../shared/presentation/page_help_button.dart';
import '../../../shared/presentation/site_top_bar.dart';
import '../application/analytics_controller.dart';
import '../application/analytics_range.dart';
import '../application/analytics_segment.dart';

class LocationsPage extends ConsumerWidget {
  const LocationsPage({required this.siteId, this.embedded = false, super.key});

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
    final report = ref.watch(analyticsLocationProvider(query));
    return Scaffold(
      backgroundColor: const Color(0xfff3f5f8),
      appBar: embedded
          ? null
          : SiteTopBar(
              siteId: siteId,
              selected: SiteTopTab.locations,
              help: const PageHelpButton(
                englishTitle: 'Visitor locations',
                chineseTitle: '访客地域说明',
                englishBody:
                    'Location is estimated from the visitor IP by your trusted edge proxy and is attached to the first page view of a visit. Raw IP addresses are not stored. Configure a trusted proxy and its country/location headers on the server.',
                chineseBody:
                    '访客地域由可信边缘代理根据 IP 估算，并记录在每次访问的首个页面浏览上。系统不保存原始 IP。请在服务端配置可信代理及地域请求头。',
              ),
            ),
      body: report.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Text(context.tr('Could not load location report', '无法加载地域报表')),
        ),
        data: (data) => _LocationReport(data: data),
      ),
    );
  }
}

class _LocationReport extends StatefulWidget {
  const _LocationReport({required this.data});

  final AnalyticsLocationReport data;

  @override
  State<_LocationReport> createState() => _LocationReportState();
}

class _LocationReportState extends State<_LocationReport> {
  static const _levels = ['country', 'continent', 'region', 'city'];
  String _level = 'country';

  @override
  Widget build(BuildContext context) {
    final rows = widget.data.rows.where((row) => row.level == _level).toList();
    final total = rows.fold<int>(0, (sum, row) => sum + row.sessions);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          context.tr('Visitor locations', '访客地域'),
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 5),
        Text(
          context.tr(
            'Estimated visits by country, continent, region and city.',
            '按国家、洲、地区和城市查看估算访问量。',
          ),
        ),
        const SizedBox(height: 14),
        Card(
          color: const Color(0xffedf4fb),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.privacy_tip_outlined,
                  color: Color(0xff315e87),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    context.tr(
                      'IP geolocation is approximate. Raw visitor IP addresses are not retained.',
                      'IP 地理定位仅为估算；系统不会留存访客原始 IP 地址。',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (!widget.data.sourceConfigured) ...[
          const SizedBox(height: 10),
          Card(
            color: const Color(0xfffff5e6),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.tr(
                      'Location collection is not configured',
                      '地域采集尚未配置',
                    ),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    context.tr(
                      'Enable SEERAY_GEO_LOCATION_ENABLED and set SEERAY_GEO_TRUSTED_PROXY_CIDRS to the exact proxy CIDRs. Configure Cloudflare location headers at the edge. Do not trust headers from arbitrary clients.',
                      '请启用 SEERAY_GEO_LOCATION_ENABLED，并将 SEERAY_GEO_TRUSTED_PROXY_CIDRS 设置为精确的代理网段，同时在 Cloudflare 边缘配置地域请求头。不要信任任意客户端传入的请求头。',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final level in _levels)
              ChoiceChip(
                label: Text(_levelLabel(context, level)),
                selected: _level == level,
                onSelected: (_) => setState(() => _level = level),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (rows.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                context.tr(
                  widget.data.sourceConfigured
                      ? 'No location data yet. New visits will appear when the trusted edge proxy provides valid location headers.'
                      : 'No location data is available until collection is configured.',
                  widget.data.sourceConfigured
                      ? '暂无地域数据。可信边缘代理提供有效地域请求头后，新访问会显示在这里。'
                      : '完成地域采集配置后，这里才会显示数据。',
                ),
              ),
            ),
          )
        else
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                  child: Row(
                    children: [
                      Expanded(child: Text(context.tr('Location', '地域'))),
                      Text(context.tr('Visits', '访问')),
                      const SizedBox(width: 32),
                      Text(context.tr('Visitors', '访客')),
                    ],
                  ),
                ),
                const Divider(height: 1),
                for (final row in rows.take(100))
                  _LocationRow(row: row, totalSessions: total),
              ],
            ),
          ),
      ],
    );
  }

  String _levelLabel(BuildContext context, String level) => switch (level) {
    'country' => context.tr('Countries', '国家'),
    'continent' => context.tr('Continents', '大洲'),
    'region' => context.tr('Regions', '地区'),
    _ => context.tr('Cities', '城市'),
  };
}

class _LocationRow extends StatelessWidget {
  const _LocationRow({required this.row, required this.totalSessions});

  final AnalyticsLocation row;
  final int totalSessions;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
    child: Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(row.label, overflow: TextOverflow.ellipsis),
                  if (row.timezone != null && row.level == 'city')
                    Text(
                      row.timezone!,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            ),
            SizedBox(
              width: 58,
              child: Text('${row.sessions}', textAlign: TextAlign.end),
            ),
            SizedBox(
              width: 74,
              child: Text('${row.visitors}', textAlign: TextAlign.end),
            ),
          ],
        ),
        const SizedBox(height: 7),
        LinearProgressIndicator(
          value: totalSessions == 0 ? 0 : row.sessions / totalSessions,
          minHeight: 5,
          borderRadius: BorderRadius.circular(5),
          backgroundColor: const Color(0xffe7ebf0),
        ),
      ],
    ),
  );
}
