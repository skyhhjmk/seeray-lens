import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/i18n/app_i18n.dart';
import '../../../core/network/seeray_api.dart';
import '../../../shared/presentation/app_back_button.dart';
import '../../../shared/presentation/page_help_button.dart';
import '../../../shared/presentation/site_top_bar.dart';
import '../../auth/application/auth_controller.dart';
import '../../domains/application/domain_controller.dart';
import '../application/analytics_controller.dart';
import '../application/analytics_range.dart';
import '../application/analytics_segment.dart';
import '../application/user_flow_controller.dart';
import 'visitor_log_panel.dart';

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
    final segmentId = ref.watch(analyticsSegmentSelectionProvider(siteId));
    final query = AnalyticsDashboardQuery(
      siteId,
      rangeState.range,
      segmentId: segmentId,
    );
    final reportBody = view == AnalyticsView.behaviour
        ? ref
              .watch(analyticsBehaviourProvider(query))
              .when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => Center(
                  child: Text(
                    context.tr('Could not load analytics', '无法加载分析数据'),
                  ),
                ),
                data: (data) =>
                    _BehaviourBody(siteId: siteId, data: data, query: query),
              )
        : view == AnalyticsView.goals
        ? ref
              .watch(analyticsGoalsProvider(query))
              .when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => Center(
                  child: Text(
                    context.tr('Could not load analytics', '无法加载分析数据'),
                  ),
                ),
                data: (goals) => _GoalsBody(siteId: siteId, goals: goals),
              )
        : ref
              .watch(analyticsDashboardRangeProvider(query))
              .when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => Center(
                  child: Text(
                    context.tr('Could not load analytics', '无法加载分析数据'),
                  ),
                ),
                data: (data) => _Body(view: view, data: data, siteId: siteId),
              );
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
                    'These reports use the selected site, date range, and optional saved audience segment. Empty panels mean no collected matching events yet.',
                chineseBody: '这些报表使用当前站点、所选日期范围和可选的已保存分群。空白面板表示尚未采集到匹配事件。',
              ),
            ),
      body: reportBody,
    );
  }
}

class _BehaviourBody extends StatelessWidget {
  const _BehaviourBody({
    required this.siteId,
    required this.data,
    required this.query,
  });

  final String siteId;
  final AnalyticsBehaviourData data;
  final AnalyticsDashboardQuery query;

  @override
  Widget build(BuildContext context) {
    final entries = data.flows.where((item) => item.flow == 'entry').toList();
    final exits = data.flows.where((item) => item.flow == 'exit').toList();
    final pages = data.pages
        .map(
          (item) => _ReportRow(
            item.title?.isNotEmpty == true
                ? item.title!
                : context.tr('Untitled page', '未命名页面'),
            item.path,
            item.pageViews,
          ),
        )
        .toList(growable: false);
    final entryRows = entries.map(_pageFlowRow).toList(growable: false);
    final exitRows = exits.map(_pageFlowRow).toList(growable: false);
    final eventRows = data.events
        .map((item) => _ReportRow(item.type, null, item.count))
        .toList(growable: false);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          context.tr('Behaviour', '用户行为'),
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 6),
        Text(
          context.tr(
            'Understand which content people view, where visits begin and end, and which actions are tracked.',
            '查看访客浏览的内容、访问的起点与终点，以及追踪到的行为事件。',
          ),
        ),
        const SizedBox(height: 16),
        _BehaviourPanel(
          title: context.tr('Page titles', '页面标题'),
          metric: context.tr('Page views', '页面浏览'),
          empty: context.tr('No page views yet', '暂无页面浏览数据'),
          rows: pages,
        ),
        const SizedBox(height: 16),
        _PageOverlayLauncher(siteId: siteId, pages: data.pages, query: query),
        const SizedBox(height: 16),
        _SiteSearchPanel(siteId: siteId, report: data.siteSearch),
        const SizedBox(height: 16),
        _ContentAnalyticsPanel(siteId: siteId, report: data.content),
        const SizedBox(height: 16),
        _WebVitalsPanel(siteId: siteId, report: data.webVitals),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth > 760;
            final entryPanel = _BehaviourPanel(
              title: context.tr('Entry pages', '入口页面'),
              metric: context.tr('Visits', '访问'),
              empty: context.tr('No entry-page data yet', '暂无入口页面数据'),
              rows: entryRows,
            );
            final exitPanel = _BehaviourPanel(
              title: context.tr('Exit pages', '退出页面'),
              metric: context.tr('Visits', '访问'),
              empty: context.tr('No exit-page data yet', '暂无退出页面数据'),
              rows: exitRows,
            );
            return wide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: entryPanel),
                      const SizedBox(width: 16),
                      Expanded(child: exitPanel),
                    ],
                  )
                : Column(
                    children: [
                      entryPanel,
                      const SizedBox(height: 16),
                      exitPanel,
                    ],
                  );
          },
        ),
        const SizedBox(height: 16),
        _BehaviourPanel(
          title: context.tr('Tracked events', '已追踪事件'),
          metric: context.tr('Events', '事件数'),
          empty: context.tr('No events collected yet', '暂无事件数据'),
          rows: eventRows,
        ),
        const SizedBox(height: 16),
        _UserFlowExplorer(edges: data.userFlow, query: query),
      ],
    );
  }

  _ReportRow _pageFlowRow(AnalyticsPageFlow item) => _ReportRow(
    item.title?.isNotEmpty == true ? item.title! : item.path,
    item.title?.isNotEmpty == true ? item.path : null,
    item.sessions,
  );
}

class _PageOverlayLauncher extends ConsumerStatefulWidget {
  const _PageOverlayLauncher({
    required this.siteId,
    required this.pages,
    required this.query,
  });

  final String siteId;
  final List<AnalyticsPageTitle> pages;
  final AnalyticsDashboardQuery query;

  @override
  ConsumerState<_PageOverlayLauncher> createState() =>
      _PageOverlayLauncherState();
}

class _PageOverlayLauncherState extends ConsumerState<_PageOverlayLauncher> {
  String? _path;
  String? _domainId;
  String? _launchUrl;
  bool _creating = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final domains = ref.watch(domainsProvider(widget.siteId));
    final domainValues = domains.maybeWhen(
      data: (values) => values,
      orElse: () => const <AllowedDomain>[],
    );
    final paths = widget.pages.map((page) => page.path).toSet().toList();
    final selectedPath = paths.contains(_path)
        ? _path!
        : paths.isEmpty
        ? null
        : paths.first;
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.tr('Page overlay', '页面覆盖层'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              context.tr(
                'Open a tracked page with session-based next-page counts beside matching links. This is navigation attribution, not a click heatmap.',
                '在已安装 tracker 的页面上查看匹配链接旁的会话级下一页转移数。这是页面导航归因，不是点击热图。',
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 12,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 320,
                  child: DropdownButtonFormField<String>(
                    key: ValueKey(selectedPath),
                    initialValue: selectedPath,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: context.tr('Source page', '来源页面'),
                      border: const OutlineInputBorder(),
                    ),
                    items: [
                      for (final path in paths)
                        DropdownMenuItem(
                          value: path,
                          child: Text(
                            widget.pages
                                    .where((page) => page.path == path)
                                    .map((page) => page.title)
                                    .whereType<String>()
                                    .where((title) => title.isNotEmpty)
                                    .firstOrNull ??
                                path,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: _creating
                        ? null
                        : (value) => setState(() {
                            _path = value;
                            _launchUrl = null;
                            _error = null;
                          }),
                  ),
                ),
                domains.when(
                  loading: () => const SizedBox(
                    width: 220,
                    child: LinearProgressIndicator(),
                  ),
                  error: (error, _) => Text(
                    context.tr('Could not load allowed domains', '无法加载允许域名'),
                  ),
                  data: (values) {
                    final enabled = values
                        .where((domain) => domain.enabled)
                        .toList();
                    final selectedDomainId =
                        enabled.any((domain) => domain.id == _domainId)
                        ? _domainId
                        : enabled.isEmpty
                        ? null
                        : enabled.first.id;
                    return SizedBox(
                      width: 240,
                      child: DropdownButtonFormField<String>(
                        key: ValueKey(selectedDomainId),
                        initialValue: selectedDomainId,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: context.tr(
                            'Allowed site domain',
                            '站点允许域名',
                          ),
                          border: const OutlineInputBorder(),
                        ),
                        items: [
                          for (final domain in enabled)
                            DropdownMenuItem(
                              value: domain.id,
                              child: Text(
                                domain.host,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: _creating
                            ? null
                            : (value) => setState(() {
                                _domainId = value;
                                _launchUrl = null;
                                _error = null;
                              }),
                      ),
                    );
                  },
                ),
                FilledButton.tonalIcon(
                  onPressed: _creating || selectedPath == null
                      ? null
                      : () => _create(selectedPath, domainValues),
                  icon: _creating
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.open_in_new),
                  label: Text(context.tr('Create overlay link', '生成覆盖层链接')),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            if (_launchUrl case final launchUrl?) ...[
              const SizedBox(height: 12),
              SelectableText(launchUrl),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: launchUrl));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          context.tr('Overlay link copied', '覆盖层链接已复制'),
                        ),
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.copy),
                label: Text(
                  context.tr(
                    'Copy link and open it in a tracked browser',
                    '复制链接并在已安装 tracker 的浏览器中打开',
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _create(String sourcePath, List<AllowedDomain> domains) async {
    final enabled = domains.where((domain) => domain.enabled).toList();
    final domain = enabled.where((value) => value.id == _domainId).isNotEmpty
        ? enabled.firstWhere((value) => value.id == _domainId)
        : enabled.isEmpty
        ? null
        : enabled.first;
    if (domain == null) {
      setState(() {
        _error = context.tr(
          'Add and enable an allowed site domain first.',
          '请先添加并启用站点允许域名。',
        );
      });
      return;
    }
    setState(() {
      _creating = true;
      _error = null;
      _launchUrl = null;
    });
    try {
      final result =
          await ref
                  .read(apiProvider)
                  .request(
                    'POST',
                    '/api/v1/sites/${widget.siteId}/analytics/page-overlay-sessions',
                    body: {
                      'sourcePath': sourcePath,
                      'from': widget.query.range.fromQuery,
                      'to': widget.query.range.toQuery,
                      if (widget.query.segmentId != null)
                        'segmentId': widget.query.segmentId,
                    },
                  )
              as Map<String, dynamic>;
      final uri = Uri.parse('https://${domain.host}$sourcePath').replace(
        fragment: Uri(
          queryParameters: {
            '__seeray_overlay_session': result['sessionId'] as String,
            '__seeray_overlay_token': result['token'] as String,
          },
        ).query,
      );
      if (mounted) setState(() => _launchUrl = uri.toString());
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }
}

class _SiteSearchPanel extends StatelessWidget {
  const _SiteSearchPanel({required this.siteId, required this.report});

  final String siteId;
  final AnalyticsSiteSearchReport report;

  @override
  Widget build(BuildContext context) {
    final noResultRate = report.measuredResultSearches == 0
        ? null
        : report.zeroResultSearches / report.measuredResultSearches * 100;
    final terms = report.terms.take(20).toList(growable: false);
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
                    context.tr('Site search', '站内搜索'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: context.tr('Tracking setup', '追踪接入说明'),
                  onPressed: () => context.go('/sites/$siteId/integration'),
                  icon: const Icon(Icons.integration_instructions_outlined),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              context.tr(
                'Search terms are collected only from opted-in search forms or explicit tracker calls. Result metrics use searches that supplied a result count.',
                '搜索词仅从明确标记的搜索表单或显式追踪调用中采集。结果数指标只统计提供了结果数的搜索。',
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _SiteSearchMetric(
                  label: context.tr('Searches', '搜索次数'),
                  value: '${report.searches}',
                ),
                _SiteSearchMetric(
                  label: context.tr('Search sessions', '搜索访问'),
                  value: '${report.sessions}',
                ),
                _SiteSearchMetric(
                  label: context.tr('No-result rate', '无结果率'),
                  value: noResultRate == null
                      ? '—'
                      : '${noResultRate.toStringAsFixed(1)}%',
                  detail: context.tr(
                    '${report.zeroResultSearches} of ${report.measuredResultSearches} measured',
                    '已知结果数 ${report.measuredResultSearches} 次中有 ${report.zeroResultSearches} 次无结果',
                  ),
                ),
                _SiteSearchMetric(
                  label: context.tr('Average results', '平均结果数'),
                  value: report.averageResultsCount?.toStringAsFixed(1) ?? '—',
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (terms.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Column(
                    children: [
                      Text(
                        context.tr(
                          'No site-search events in this date range.',
                          '当前日期范围内没有站内搜索事件。',
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        context.tr(
                          'Open tracking setup to mark your search form or call the tracker after a search.',
                          '打开追踪接入说明，为搜索表单加上追踪标记，或在搜索完成后调用追踪器。',
                        ),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              )
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: [
                    DataColumn(label: Text(context.tr('Search term', '搜索词'))),
                    DataColumn(label: Text(context.tr('Category', '类别'))),
                    DataColumn(
                      numeric: true,
                      label: Text(context.tr('Searches', '搜索次数')),
                    ),
                    DataColumn(
                      numeric: true,
                      label: Text(context.tr('Visitors', '访客')),
                    ),
                    DataColumn(
                      numeric: true,
                      label: Text(context.tr('No results', '无结果')),
                    ),
                    DataColumn(
                      numeric: true,
                      label: Text(context.tr('Avg. results', '平均结果数')),
                    ),
                  ],
                  rows: [
                    for (final term in terms)
                      DataRow(
                        cells: [
                          DataCell(
                            Tooltip(
                              message: term.keyword,
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 240,
                                ),
                                child: Text(
                                  term.keyword,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ),
                          DataCell(Text(term.category ?? '—')),
                          DataCell(Text('${term.searches}')),
                          DataCell(Text('${term.uniqueVisitors}')),
                          DataCell(Text('${term.zeroResultSearches}')),
                          DataCell(
                            Text(
                              term.averageResultsCount?.toStringAsFixed(1) ??
                                  '—',
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            if (terms.isNotEmpty && report.terms.length > terms.length)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  context.tr(
                    'Showing the 20 most searched terms.',
                    '仅显示搜索次数最多的 20 个词。',
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SiteSearchMetric extends StatelessWidget {
  const _SiteSearchMetric({
    required this.label,
    required this.value,
    this.detail,
  });

  final String label;
  final String value;
  final String? detail;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minWidth: 140),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 3),
        Text(value, style: Theme.of(context).textTheme.titleLarge),
        if (detail != null)
          Text(detail!, style: Theme.of(context).textTheme.labelSmall),
      ],
    ),
  );
}

class _ContentAnalyticsPanel extends StatelessWidget {
  const _ContentAnalyticsPanel({required this.siteId, required this.report});

  final String siteId;
  final AnalyticsContentReport report;

  @override
  Widget build(BuildContext context) {
    final entries = report.entries.take(20).toList(growable: false);
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.campaign_outlined),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    context.tr('Content performance', '内容表现'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: context.tr('Tracking setup', '追踪接入说明'),
                  onPressed: () => context.go('/sites/$siteId/integration'),
                  icon: const Icon(Icons.integration_instructions_outlined),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              context.tr(
                'Only content with explicit SeeRay labels is measured. Impressions count when at least 10% of a marked item becomes visible; text and markup are never collected.',
                '仅统计明确添加 SeeRay 标记的内容；标记项至少 10% 进入可视区域时记为曝光，不采集内容文本或页面结构。',
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _SiteSearchMetric(
                  label: context.tr('Impressions', '曝光'),
                  value: '${report.impressions}',
                ),
                _SiteSearchMetric(
                  label: context.tr('Interactions', '互动'),
                  value: '${report.interactions}',
                ),
                _SiteSearchMetric(
                  label: context.tr('Interaction rate', '互动率'),
                  value:
                      '${(report.interactionRate * 100).toStringAsFixed(1)}%',
                ),
                _SiteSearchMetric(
                  label: context.tr('Reached visitors', '触达访客'),
                  value: '${report.uniqueVisitors}',
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (entries.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Column(
                    children: [
                      Text(
                        context.tr(
                          'No marked content has been seen in this date range.',
                          '当前日期范围内尚无已标记内容的曝光。',
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        context.tr(
                          'Open tracking setup to label a content item and its interaction controls.',
                          '打开追踪接入说明，为内容项及其互动控件添加标记。',
                        ),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              )
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: [
                    DataColumn(label: Text(context.tr('Content', '内容'))),
                    DataColumn(label: Text(context.tr('Piece', '素材'))),
                    DataColumn(label: Text(context.tr('Target', '目标'))),
                    DataColumn(
                      numeric: true,
                      label: Text(context.tr('Impressions', '曝光')),
                    ),
                    DataColumn(
                      numeric: true,
                      label: Text(context.tr('Interactions', '互动')),
                    ),
                    DataColumn(
                      numeric: true,
                      label: Text(context.tr('Rate', '互动率')),
                    ),
                  ],
                  rows: [
                    for (final entry in entries)
                      DataRow(
                        cells: [
                          DataCell(_BoundedReportText(entry.name)),
                          DataCell(Text(entry.piece ?? '—')),
                          DataCell(_BoundedReportText(entry.target ?? '—')),
                          DataCell(Text('${entry.impressions}')),
                          DataCell(Text('${entry.interactions}')),
                          DataCell(
                            Text(
                              '${(entry.interactionRate * 100).toStringAsFixed(1)}%',
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            if (report.entries.length > entries.length)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  context.tr(
                    'Showing the 20 content variants with the most impressions.',
                    '仅显示曝光最多的 20 个内容变体。',
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _WebVitalsPanel extends StatelessWidget {
  const _WebVitalsPanel({required this.siteId, required this.report});

  final String siteId;
  final AnalyticsWebVitalsReport report;

  String _value(String metric, double p75) => switch (metric) {
    'LCP' => '${(p75 / 1000).toStringAsFixed(2)} s',
    'INP' => '${p75.round()} ms',
    'CLS' => p75.toStringAsFixed(3),
    _ => p75.toStringAsFixed(1),
  };

  @override
  Widget build(BuildContext context) {
    final metrics = {for (final item in report.metrics) item.metric: item};
    final pages = report.pages.take(30).toList(growable: false);
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.speed_outlined),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    context.tr(
                      'Page performance · Web Vitals',
                      '页面性能 · Web Vitals',
                    ),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: context.tr('Tracking setup', '追踪接入说明'),
                  onPressed: () =>
                      context.go('/sites/$siteId/integration?tab=web-vitals'),
                  icon: const Icon(Icons.integration_instructions_outlined),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              context.tr(
                'The p75 summarizes the slowest quarter of measured experiences. Each page’s metric ID is deduplicated so later CLS/INP updates replace earlier values instead of inflating samples.',
                'p75 表示本范围内第 75 百分位的体验值。每个页面指标 ID 会去重，CLS / INP 的后续更新会替换早先数值，不会重复增加样本。',
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Text(
              context.tr(
                'Good: LCP ≤ 2.5 s · INP ≤ 200 ms · CLS ≤ 0.1. Poor: > 4 s · > 500 ms · > 0.25; values in between need improvement.',
                '良好：LCP ≤ 2.5 秒 · INP ≤ 200 毫秒 · CLS ≤ 0.1。较差：> 4 秒 · > 500 毫秒 · > 0.25；中间值需改进。',
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 14),
            if (report.metrics.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 18),
                child: Center(
                  child: Column(
                    children: [
                      Text(
                        context.tr(
                          'No Web Vitals have been collected in this date range.',
                          '当前日期范围内尚无 Web Vitals 数据。',
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        context.tr(
                          'Enable the Web Vitals snippet in tracking setup. Collection starts only after the tracker is installed and the page has a supported browser API.',
                          '请在追踪接入说明中启用 Web Vitals。安装追踪代码并由支持相关浏览器 API 的页面访问后才会开始采集。',
                        ),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: () => context.go(
                          '/sites/$siteId/integration?tab=web-vitals',
                        ),
                        icon: const Icon(
                          Icons.integration_instructions_outlined,
                        ),
                        label: Text(context.tr('Set up collection', '配置采集')),
                      ),
                    ],
                  ),
                ),
              )
            else ...[
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final metric in const ['LCP', 'INP', 'CLS'])
                    if (metrics[metric] case final summary?)
                      _SiteSearchMetric(
                        label: '$metric ${context.tr('p75', 'p75')}',
                        value: _value(metric, summary.p75),
                        detail: context.tr(
                          '${summary.samples} samples · ${summary.good} good · ${summary.needsImprovement} needs work · ${summary.poor} poor',
                          '${summary.samples} 个样本 · ${summary.good} 良好 · ${summary.needsImprovement} 需改进 · ${summary.poor} 较差',
                        ),
                      ),
                ],
              ),
              const SizedBox(height: 14),
              if (pages.isEmpty)
                Text(
                  context.tr('No page-level measurements yet.', '暂无页面级测量数据。'),
                )
              else
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: [
                      DataColumn(label: Text(context.tr('Page', '页面'))),
                      DataColumn(label: Text(context.tr('Metric', '指标'))),
                      DataColumn(
                        numeric: true,
                        label: Text(context.tr('p75', 'p75')),
                      ),
                      DataColumn(
                        numeric: true,
                        label: Text(context.tr('Samples', '样本')),
                      ),
                      DataColumn(
                        numeric: true,
                        label: Text(context.tr('Good', '良好')),
                      ),
                      DataColumn(
                        numeric: true,
                        label: Text(context.tr('Needs work', '需改进')),
                      ),
                      DataColumn(
                        numeric: true,
                        label: Text(context.tr('Poor', '较差')),
                      ),
                    ],
                    rows: [
                      for (final page in pages)
                        DataRow(
                          cells: [
                            DataCell(_BoundedReportText(page.pagePath ?? '/')),
                            DataCell(Text(page.metric)),
                            DataCell(Text(_value(page.metric, page.p75))),
                            DataCell(Text('${page.samples}')),
                            DataCell(Text('${page.good}')),
                            DataCell(Text('${page.needsImprovement}')),
                            DataCell(Text('${page.poor}')),
                          ],
                        ),
                    ],
                  ),
                ),
              if (report.pages.length > pages.length)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    context.tr(
                      'Showing the 30 page and metric combinations with the most samples.',
                      '仅显示样本量最多的 30 个页面和指标组合。',
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _BoundedReportText extends StatelessWidget {
  const _BoundedReportText(this.value);

  final String value;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: value,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 220),
      child: Text(value, maxLines: 1, overflow: TextOverflow.ellipsis),
    ),
  );
}

class _UserFlowExplorer extends StatefulWidget {
  const _UserFlowExplorer({required this.edges, required this.query});

  final List<AnalyticsUserFlowEdge> edges;
  final AnalyticsDashboardQuery query;

  @override
  State<_UserFlowExplorer> createState() => _UserFlowExplorerState();
}

class _UserFlowExplorerState extends State<_UserFlowExplorer> {
  int _step = 1;
  String? _sourcePath;

  @override
  Widget build(BuildContext context) {
    final stepEdges = widget.edges.where((edge) => edge.step == _step).toList();
    final sources = stepEdges.map((edge) => edge.sourcePath).toSet().toList();
    if (_sourcePath != null && !sources.contains(_sourcePath)) {
      sources.insert(0, _sourcePath!);
    }
    final edges = _sourcePath == null
        ? stepEdges
        : stepEdges.where((edge) => edge.sourcePath == _sourcePath).toList();
    final maxSessions = edges.fold<int>(
      0,
      (current, edge) => edge.sessions > current ? edge.sessions : current,
    );

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.route_outlined),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    context.tr('User flow', '用户路径'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              context.tr(
                'Follow the most common page-to-page journeys. Counts are visits, and each step represents one page transition.',
                '查看常见的页面访问路径。数字表示访问次数，每一步代表一次页面跳转。',
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (var step = 1; step <= 5; step++)
                  ChoiceChip(
                    label: Text(context.tr('Step $step', '第 $step 步')),
                    selected: _step == step,
                    onSelected: (_) => setState(() {
                      _step = step;
                      _sourcePath = null;
                    }),
                  ),
              ],
            ),
            if (sources.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                context.tr('Starting page', '起始页面'),
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilterChip(
                    label: Text(context.tr('All pages', '全部页面')),
                    selected: _sourcePath == null,
                    onSelected: (_) => setState(() => _sourcePath = null),
                  ),
                  for (final path in sources.take(9))
                    FilterChip(
                      label: SizedBox(
                        width: 190,
                        child: Text(path, overflow: TextOverflow.ellipsis),
                      ),
                      selected: _sourcePath == path,
                      onSelected: (_) => setState(() => _sourcePath = path),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            if (edges.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 22),
                child: Center(
                  child: Text(
                    _sourcePath == null
                        ? context.tr(
                            'No page transitions recorded for this step.',
                            '此步骤暂无页面跳转记录。',
                          )
                        : context.tr(
                            'No recorded transition from $_sourcePath at this step.',
                            '$_sourcePath 在此步骤没有后续跳转记录。',
                          ),
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            else ...[
              for (final edge in edges)
                _UserFlowTransition(
                  edge: edge,
                  maxSessions: maxSessions,
                  onInspect: () => showDialog<void>(
                    context: context,
                    builder: (_) => _UserFlowSamplesDialog(
                      query: AnalyticsUserFlowSamplesQuery(
                        dashboard: widget.query,
                        edge: edge,
                      ),
                      edge: edge,
                    ),
                  ),
                  onFollow: edge.targetPath == null || _step == 5
                      ? null
                      : () => setState(() {
                          _step++;
                          _sourcePath = edge.targetPath;
                        }),
                ),
              const SizedBox(height: 4),
              Text(
                context.tr(
                  'Select a destination to follow that journey into the next step.',
                  '选择一个目标页面，可继续查看它在下一步的去向。',
                ),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _UserFlowTransition extends StatelessWidget {
  const _UserFlowTransition({
    required this.edge,
    required this.maxSessions,
    required this.onInspect,
    required this.onFollow,
  });

  final AnalyticsUserFlowEdge edge;
  final int maxSessions;
  final VoidCallback onInspect;
  final VoidCallback? onFollow;

  @override
  Widget build(BuildContext context) {
    final source = _pageLabel(edge.sourceTitle, edge.sourcePath);
    final target = edge.targetPath == null
        ? context.tr('Exit after this page', '访问在此页面结束')
        : _pageLabel(edge.targetTitle, edge.targetPath!);
    final ratio = maxSessions == 0 ? 0.0 : edge.sessions / maxSessions;
    return Card(
      margin: const EdgeInsets.only(top: 8),
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: InkWell(
        onTap: onFollow,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(child: _FlowPageNode(label: source)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Icon(
                      edge.targetPath == null
                          ? Icons.logout
                          : Icons.arrow_forward_rounded,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  Expanded(
                    child: _FlowPageNode(
                      label: target,
                      isExit: edge.targetPath == null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: LinearProgressIndicator(
                      value: ratio,
                      minHeight: 5,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    context.tr(
                      '${edge.sessions} visits',
                      '${edge.sessions} 次访问',
                    ),
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ],
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: onInspect,
                  icon: const Icon(Icons.travel_explore_outlined),
                  label: Text(context.tr('View visits', '查看访问样本')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _pageLabel(String? title, String path) =>
      title?.isNotEmpty == true ? '$title · $path' : path;
}

class _UserFlowSamplesDialog extends ConsumerStatefulWidget {
  const _UserFlowSamplesDialog({required this.query, required this.edge});

  final AnalyticsUserFlowSamplesQuery query;
  final AnalyticsUserFlowEdge edge;

  @override
  ConsumerState<_UserFlowSamplesDialog> createState() =>
      _UserFlowSamplesDialogState();
}

class _UserFlowSamplesDialogState
    extends ConsumerState<_UserFlowSamplesDialog> {
  final List<AnalyticsUserFlowSampleSession> _olderSessions = [];
  String? _nextCursor;
  bool? _hasMore;
  bool _loadingMore = false;
  Object? _loadError;

  Future<void> _loadMore(String? cursor) async {
    if (cursor == null || _loadingMore) return;
    setState(() {
      _loadingMore = true;
      _loadError = null;
    });
    try {
      final page = await ref.read(
        analyticsUserFlowSamplesProvider(
          widget.query.withCursor(cursor),
        ).future,
      );
      if (!mounted) return;
      setState(() {
        _olderSessions.addAll(page.sessions);
        _nextCursor = page.nextCursor;
        _hasMore = page.hasMore;
        _loadingMore = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error;
        _loadingMore = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final edge = widget.edge;
    final source = edge.sourceTitle?.isNotEmpty == true
        ? '${edge.sourceTitle} · ${edge.sourcePath}'
        : edge.sourcePath;
    final target = edge.targetPath == null
        ? context.tr('Exit after this page', '访问在此页面结束')
        : edge.targetTitle?.isNotEmpty == true
        ? '${edge.targetTitle} · ${edge.targetPath}'
        : edge.targetPath!;
    return AlertDialog(
      title: Text(context.tr('Visits for this transition', '此路径的访问样本')),
      content: SizedBox(
        width: 680,
        child: ref
            .watch(analyticsUserFlowSamplesProvider(widget.query))
            .when(
              loading: () => const SizedBox(
                height: 180,
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, _) => SizedBox(
                height: 180,
                child: Center(
                  child: Text(
                    context.tr('Could not load visit samples', '无法加载访问样本'),
                  ),
                ),
              ),
              data: (report) {
                final sessions = [...report.sessions, ..._olderSessions];
                final hasMore = _hasMore ?? report.hasMore;
                final cursor = _nextCursor ?? report.nextCursor;
                return ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 560),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('$source  →  $target'),
                      const SizedBox(height: 4),
                      Text(
                        context.tr(
                          '${report.totalSessions} matching visits · showing ${sessions.length}',
                          '${report.totalSessions} 次匹配访问 · 已展示 ${sessions.length} 次',
                        ),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: sessions.isEmpty
                            ? Center(
                                child: Text(
                                  context.tr('No matching visits', '暂无匹配访问'),
                                ),
                              )
                            : ListView.builder(
                                itemCount: sessions.length + (hasMore ? 1 : 0),
                                itemBuilder: (context, index) {
                                  if (index < sessions.length) {
                                    return _UserFlowSampleCard(
                                      number: index + 1,
                                      sample: sessions[index],
                                      transitionStep: edge.step,
                                      isExit: edge.targetPath == null,
                                    );
                                  }
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 10,
                                    ),
                                    child: Column(
                                      children: [
                                        if (_loadError != null)
                                          Text(
                                            context.tr(
                                              'Could not load older visits. Try again.',
                                              '加载更早访问失败，请重试。',
                                            ),
                                          ),
                                        OutlinedButton.icon(
                                          onPressed:
                                              _loadingMore || cursor == null
                                              ? null
                                              : () => _loadMore(cursor),
                                          icon: _loadingMore
                                              ? const SizedBox(
                                                  width: 16,
                                                  height: 16,
                                                  child:
                                                      CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                      ),
                                                )
                                              : const Icon(Icons.expand_more),
                                          label: Text(
                                            context.tr(
                                              'Load older visits',
                                              '加载更早访问',
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                );
              },
            ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.tr('Close', '关闭')),
        ),
      ],
    );
  }
}

class _UserFlowSampleCard extends StatelessWidget {
  const _UserFlowSampleCard({
    required this.number,
    required this.sample,
    required this.transitionStep,
    required this.isExit,
  });

  final int number;
  final AnalyticsUserFlowSampleSession sample;
  final int transitionStep;
  final bool isExit;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 10),
    elevation: 0,
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr(
              'Visit $number · ${_formatSampleTime(sample.startedAt)}',
              '访问 $number · ${_formatSampleTime(sample.startedAt)}',
            ),
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 8),
          if (sample.pages.isEmpty)
            Text(context.tr('No page sequence available', '暂无页面序列'))
          else
            for (final page in sample.pages) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color:
                      page.step == transitionStep ||
                          (!isExit && page.step == transitionStep + 1)
                      ? Theme.of(context).colorScheme.primaryContainer
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 46,
                      child: Text(
                        'S${page.step}',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        page.title?.isNotEmpty == true
                            ? '${page.title} · ${page.path}'
                            : page.path,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _formatSampleTime(page.at),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (page.step == transitionStep && isExit)
                Padding(
                  padding: const EdgeInsets.only(left: 56, top: 2, bottom: 2),
                  child: Text(
                    context.tr('Visit ended', '访问结束'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
            ],
        ],
      ),
    ),
  );

  String _formatSampleTime(DateTime value) {
    final local = value.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }
}

class _FlowPageNode extends StatelessWidget {
  const _FlowPageNode({required this.label, this.isExit = false});

  final String label;
  final bool isExit;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 48),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
    ),
    child: Row(
      children: [
        Icon(
          isExit ? Icons.flag_outlined : Icons.web_outlined,
          size: 17,
          color: isExit
              ? Theme.of(context).colorScheme.onSurfaceVariant
              : Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      ],
    ),
  );
}

class _ReportRow {
  const _ReportRow(this.title, this.subtitle, this.count);

  final String title;
  final String? subtitle;
  final int count;
}

class _BehaviourPanel extends StatelessWidget {
  const _BehaviourPanel({
    required this.title,
    required this.metric,
    required this.empty,
    required this.rows,
  });

  final String title;
  final String metric;
  final String empty;
  final List<_ReportRow> rows;

  @override
  Widget build(BuildContext context) => Card(
    elevation: 0,
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const Divider(height: 28),
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Center(child: Text(empty)),
            )
          else
            for (final row in rows.take(10))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(row.title, overflow: TextOverflow.ellipsis),
                          if (row.subtitle != null)
                            Text(
                              row.subtitle!,
                              style: Theme.of(context).textTheme.bodySmall,
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text('$metric · ${row.count}'),
                  ],
                ),
              ),
        ],
      ),
    ),
  );
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
  const _Body({required this.view, required this.data, required this.siteId});
  final AnalyticsView view;
  final AnalyticsDashboard data;
  final String siteId;
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
      AnalyticsView.acquisition => <_Metric>[],
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
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.headlineSmall),
            if (view == AnalyticsView.acquisition) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: () =>
                        context.go('/sites/$siteId/acquisition/attribution'),
                    icon: const Icon(Icons.compare_arrows),
                    label: Text(context.tr('Attribution models', '多触点归因')),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: () =>
                        context.go('/sites/$siteId/acquisition/campaign-costs'),
                    icon: const Icon(Icons.payments_outlined),
                    label: Text(context.tr('Campaign costs', '广告活动费用')),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: () => context.go(
                      '/sites/$siteId/acquisition/offline-conversions',
                    ),
                    icon: const Icon(Icons.offline_bolt_outlined),
                    label: Text(context.tr('Offline conversions', '线下转化')),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: () =>
                        context.go('/sites/$siteId/acquisition/search-console'),
                    icon: const Icon(Icons.travel_explore),
                    label: Text(context.tr('Search Console', '搜索表现')),
                  ),
                ],
              ),
            ],
          ],
        ),
        const SizedBox(height: 16),
        if (view == AnalyticsView.acquisition && data.traffic.isNotEmpty)
          ...data.traffic.map((item) => _AcquisitionMetric(item))
        else if (rows.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(context.tr('No data collected yet.', '尚未采集到数据。')),
            ),
          )
        else
          ...rows,
        if (view == AnalyticsView.visitors) ...[
          const SizedBox(height: 16),
          VisitorLogPanel(siteId: siteId),
        ],
      ],
    );
  }
}

class _AcquisitionMetric extends StatelessWidget {
  const _AcquisitionMetric(this.traffic);

  final AnalyticsTraffic traffic;

  @override
  Widget build(BuildContext context) {
    final dimensions = <String, String?>{
      'Source': traffic.source,
      'Medium': traffic.medium,
      'Campaign': traffic.campaign,
      'Term': traffic.term,
      'Content': traffic.content,
    };
    final details = dimensions.entries
        .where((entry) => entry.value?.isNotEmpty == true)
        .map(
          (entry) =>
              '${context.tr(entry.key, switch (entry.key) {
                'Source' => '来源',
                'Medium' => '媒介',
                'Campaign' => '活动',
                'Term' => '关键词',
                _ => '内容',
              })}: ${entry.value}',
        )
        .toList(growable: false);
    return Card(
      child: ListTile(
        title: Text(
          context.tr(
            switch (traffic.channel) {
              'direct' => 'Direct',
              'referral' => 'Website referral',
              'campaign' => 'Campaign',
              'search_engine' => 'Search engine',
              'social' => 'Social network',
              'ai_assistant' => 'AI assistant',
              _ => traffic.channel,
            },
            switch (traffic.channel) {
              'direct' => '直接访问',
              'referral' => '网站引荐',
              'campaign' => '活动',
              'search_engine' => '搜索引擎',
              'social' => '社交网络',
              'ai_assistant' => 'AI 助手',
              _ => traffic.channel,
            },
          ),
        ),
        subtitle: details.isEmpty
            ? Text(context.tr('No campaign parameters', '无活动参数'))
            : Text(details.join(' · ')),
        trailing: Text(
          '${traffic.sessions} ${context.tr('visits', '次访问')}',
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ),
    );
  }
}

enum _GoalComparisonMode { previousPeriod, audiences }

AnalyticsDateRange _previousAnalyticsRange(AnalyticsDateRange range) {
  final days = range.to.difference(range.from).inDays + 1;
  final to = range.from.subtract(const Duration(days: 1));
  final from = to.subtract(Duration(days: days - 1));
  return AnalyticsDateRange(from, to);
}

String _signedInteger(int value) => value > 0 ? '+$value' : '$value';

String _signedPercent(double value) =>
    '${value > 0 ? '+' : ''}${value.toStringAsFixed(1)}';

String _signedDecimal(double value) =>
    '${value > 0 ? '+' : ''}${value.toStringAsFixed(2)}';

class _GoalsBody extends ConsumerStatefulWidget {
  const _GoalsBody({required this.siteId, required this.goals});

  final String siteId;
  final List<AnalyticsGoal> goals;

  @override
  ConsumerState<_GoalsBody> createState() => _GoalsBodyState();
}

class _GoalsBodyState extends ConsumerState<_GoalsBody> {
  List<Map<String, dynamic>> _definitions = const [];
  bool _loading = true;
  String? _error;
  _GoalComparisonMode _comparisonMode = _GoalComparisonMode.previousPeriod;
  String? _audienceA;
  String? _audienceB;
  bool _audiencesInitialized = false;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_load);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result =
          await ref
                  .read(apiProvider)
                  .request('GET', '/api/v1/sites/${widget.siteId}/goals')
              as List;
      if (!mounted) return;
      setState(() {
        _definitions = result
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList(growable: false);
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _message(error);
      });
    }
  }

  Future<void> _edit([Map<String, dynamic>? initial]) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _GoalEditorDialog(initial: initial),
    );
    if (result == null) return;
    final id = initial?['id'];
    try {
      await ref
          .read(apiProvider)
          .request(
            id == null ? 'POST' : 'PUT',
            id == null
                ? '/api/v1/sites/${widget.siteId}/goals'
                : '/api/v1/sites/${widget.siteId}/goals/$id',
            body: result,
          );
      await _load();
      if (mounted) _invalidateReport();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_message(error))));
    }
  }

  Future<void> _delete(Map<String, dynamic> definition) async {
    final id = definition['id'];
    if (id == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          context.tr(
            'Delete ${definition['name'] ?? 'goal'}?',
            '删除“${definition['name'] ?? '目标'}”？',
          ),
        ),
        content: Text(
          context.tr(
            'Historical raw events remain, but this definition will no longer produce configured conversions.',
            '历史原始事件会保留，但该定义将不再产生配置目标转化。',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.tr('Cancel', '取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.tr('Delete', '删除')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref
          .read(apiProvider)
          .request('DELETE', '/api/v1/sites/${widget.siteId}/goals/$id');
      await _load();
      if (mounted) _invalidateReport();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_message(error))));
    }
  }

  void _invalidateReport() {
    final range = ref.read(analyticsRangeProvider(widget.siteId)).range;
    final segmentId = ref.read(
      analyticsSegmentSelectionProvider(widget.siteId),
    );
    final savedSegments = ref
        .read(analyticsSegmentOptionsProvider(widget.siteId))
        .maybeWhen(
          data: (segments) => segments.map((segment) => segment.id),
          orElse: () => const <String>[],
        );
    final segmentIds = <String?>{null, segmentId, ...savedSegments};
    for (final period in [range, _previousAnalyticsRange(range)]) {
      for (final selectedSegment in segmentIds) {
        ref.invalidate(
          analyticsGoalsProvider(
            AnalyticsDashboardQuery(
              widget.siteId,
              period,
              segmentId: selectedSegment,
            ),
          ),
        );
      }
    }
    ref.invalidate(
      analyticsDashboardRangeProvider(
        AnalyticsDashboardQuery(widget.siteId, range, segmentId: segmentId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rangeState = ref.watch(analyticsRangeProvider(widget.siteId));
    final selectedSegmentId = ref.watch(
      analyticsSegmentSelectionProvider(widget.siteId),
    );
    final segmentOptions = ref.watch(
      analyticsSegmentOptionsProvider(widget.siteId),
    );
    ref.listen(analyticsSegmentOptionsProvider(widget.siteId), (_, next) {
      next.whenData((segments) {
        if (!mounted) return;
        final currentSelection = ref.read(
          analyticsSegmentSelectionProvider(widget.siteId),
        );
        final ids = segments.map((segment) => segment.id).toSet();
        setState(() {
          if (!_audiencesInitialized) {
            _audienceA = ids.contains(currentSelection)
                ? currentSelection
                : segments.firstOrNull?.id;
            _audienceB = segments
                .where((segment) => segment.id != _audienceA)
                .firstOrNull
                ?.id;
            _audiencesInitialized = true;
          } else {
            if (_audienceA != null && !ids.contains(_audienceA)) {
              _audienceA = segments.firstOrNull?.id;
            }
            if (_audienceB != null && !ids.contains(_audienceB)) {
              _audienceB = null;
            }
            if (_audienceA == _audienceB) _audienceB = null;
          }
        });
      });
    });

    final range = rangeState.range;
    final previousRange = _previousAnalyticsRange(range);
    final audienceA = _audiencesInitialized ? _audienceA : selectedSegmentId;
    final audienceB = _audiencesInitialized ? _audienceB : null;
    final firstRange = range;
    final secondRange = _comparisonMode == _GoalComparisonMode.previousPeriod
        ? previousRange
        : range;
    final firstSegment = _comparisonMode == _GoalComparisonMode.previousPeriod
        ? selectedSegmentId
        : audienceA;
    final secondSegment = _comparisonMode == _GoalComparisonMode.previousPeriod
        ? selectedSegmentId
        : audienceB;
    final comparisonQuery = AnalyticsGoalsComparisonQuery(
      first: AnalyticsDashboardQuery(
        widget.siteId,
        firstRange,
        segmentId: firstSegment,
      ),
      second: AnalyticsDashboardQuery(
        widget.siteId,
        secondRange,
        segmentId: secondSegment,
      ),
    );
    final comparison = ref.watch(
      analyticsGoalsComparisonProvider(comparisonQuery),
    );
    final firstLabel = _comparisonMode == _GoalComparisonMode.previousPeriod
        ? context.tr('Selected period', '当前周期')
        : _audienceLabel(context, audienceA, segmentOptions);
    final secondLabel = _comparisonMode == _GoalComparisonMode.previousPeriod
        ? context.tr('Previous equal-length period', '前一等长周期')
        : _audienceLabel(context, audienceB, segmentOptions);
    final firstDates = '${firstRange.fromQuery} – ${firstRange.toQuery}';
    final secondDates = '${secondRange.fromQuery} – ${secondRange.toQuery}';
    final audienceOptionsUnavailable =
        _comparisonMode == _GoalComparisonMode.audiences &&
        (segmentOptions.isLoading ||
            segmentOptions.hasError ||
            segmentOptions.maybeWhen(
              data: (items) => items.isEmpty,
              orElse: () => false,
            ));

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                context.tr('Goals', '目标'),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            IconButton(
              tooltip: context.tr('Refresh', '刷新'),
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh),
            ),
            FilledButton.icon(
              onPressed: _loading ? null : () => _edit(),
              icon: const Icon(Icons.add),
              label: Text(context.tr('Create goal', '新建目标')),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_error != null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(_error!),
            ),
          ),
        Text(
          context.tr('Conversion report', '转化报告'),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        if (widget.goals.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(context.tr('No goal conversions yet.', '暂无目标转化。')),
            ),
          )
        else
          ...widget.goals.map(
            (goal) => _Metric(goal.name, 'Conversions', '${goal.count}'),
          ),
        const SizedBox(height: 20),
        Text(
          context.tr('Compare conversions', '对比目标转化'),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: Text(context.tr('Previous period', '对比前一周期')),
                      selected:
                          _comparisonMode == _GoalComparisonMode.previousPeriod,
                      onSelected: (_) => setState(
                        () => _comparisonMode =
                            _GoalComparisonMode.previousPeriod,
                      ),
                    ),
                    ChoiceChip(
                      label: Text(context.tr('Compare audiences', '对比分群')),
                      selected:
                          _comparisonMode == _GoalComparisonMode.audiences,
                      onSelected: (_) => setState(
                        () => _comparisonMode = _GoalComparisonMode.audiences,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_comparisonMode == _GoalComparisonMode.previousPeriod)
                  Text(
                    context.tr(
                      'Compares the selected dates with the immediately preceding period of the same length. The site-wide segment filter applies to both.',
                      '将当前日期范围与紧邻其前、长度相同的周期比较；站点顶部选择的分群会同时应用于两侧。',
                    ),
                    style: Theme.of(context).textTheme.bodySmall,
                  )
                else ...[
                  Text(
                    context.tr(
                      'Compare two saved audiences over the same dates. These choices replace the site-wide segment filter for this comparison.',
                      '在相同日期内比较两个已保存分群；本对比使用下方选择，不受站点顶部的分群筛选影响。',
                    ),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 10),
                  segmentOptions.when(
                    loading: () => const LinearProgressIndicator(),
                    error: (error, stack) => Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => ref.invalidate(
                          analyticsSegmentOptionsProvider(widget.siteId),
                        ),
                        icon: const Icon(Icons.refresh),
                        label: Text(
                          context.tr('Retry loading segments', '重试加载分群'),
                        ),
                      ),
                    ),
                    data: (segments) => segments.isEmpty
                        ? Row(
                            children: [
                              Expanded(
                                child: Text(
                                  context.tr(
                                    'Create a saved segment before comparing audiences.',
                                    '请先创建已保存的分群，再进行受众对比。',
                                  ),
                                ),
                              ),
                              TextButton.icon(
                                onPressed: () => context.go(
                                  '/sites/${widget.siteId}/segments',
                                ),
                                icon: const Icon(Icons.groups_outlined),
                                label: Text(
                                  context.tr('Manage segments', '管理分群'),
                                ),
                              ),
                            ],
                          )
                        : Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              SizedBox(
                                width: 260,
                                child: _audienceDropdown(
                                  context,
                                  label: context.tr('Audience A', '分群 A'),
                                  value: _segmentValue(audienceA),
                                  excludedValue: _segmentValue(audienceB),
                                  segments: segments,
                                  onChanged: (value) => setState(() {
                                    _audiencesInitialized = true;
                                    _audienceA = _segmentId(value);
                                  }),
                                ),
                              ),
                              SizedBox(
                                width: 260,
                                child: _audienceDropdown(
                                  context,
                                  label: context.tr('Audience B', '分群 B'),
                                  value: _segmentValue(audienceB),
                                  excludedValue: _segmentValue(audienceA),
                                  segments: segments,
                                  onChanged: (value) => setState(() {
                                    _audiencesInitialized = true;
                                    _audienceB = _segmentId(value);
                                  }),
                                ),
                              ),
                            ],
                          ),
                  ),
                ],
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '$firstLabel · $firstDates',
                        style: Theme.of(context).textTheme.labelMedium,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '$secondLabel · $secondDates',
                        style: Theme.of(context).textTheme.labelMedium,
                        textAlign: TextAlign.end,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const Divider(height: 20),
                if (audienceOptionsUnavailable)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      segmentOptions.hasError
                          ? context.tr(
                              'Load saved segments to compare audiences.',
                              '加载已保存分群后才能对比受众。',
                            )
                          : segmentOptions.isLoading
                          ? context.tr('Loading saved segments…', '正在加载已保存分群…')
                          : context.tr(
                              'Create a saved segment to compare audiences.',
                              '创建已保存分群后即可对比受众。',
                            ),
                    ),
                  )
                else
                  comparison.when(
                    loading: () => const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: LinearProgressIndicator(),
                    ),
                    error: (error, stack) => Row(
                      children: [
                        Expanded(
                          child: Text(
                            context.tr(
                              'Could not load the goal comparison.',
                              '无法加载目标对比数据。',
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: context.tr('Retry', '重试'),
                          onPressed: () => ref.invalidate(
                            analyticsGoalsComparisonProvider(comparisonQuery),
                          ),
                          icon: const Icon(Icons.refresh),
                        ),
                      ],
                    ),
                    data: (report) => _comparisonRows(
                      context,
                      report.first,
                      report.second,
                      firstLabel,
                      secondLabel,
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: Text(
                context.tr('Configured goals', '已配置目标'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            if (_loading)
              const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (!_loading && _definitions.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(context.tr('No configured goals.', '还没有配置目标。')),
            ),
          )
        else
          ..._definitions.map(_definitionCard),
      ],
    );
  }

  Widget _audienceDropdown(
    BuildContext context, {
    required String label,
    required String value,
    required String excludedValue,
    required List<AnalyticsSegmentOption> segments,
    required ValueChanged<String> onChanged,
  }) => DropdownButtonFormField<String>(
    isExpanded: true,
    initialValue: value,
    decoration: InputDecoration(labelText: label),
    items: [
      if (excludedValue != '')
        DropdownMenuItem(
          value: '',
          child: Text(context.tr('All visitors', '全部访客')),
        ),
      for (final segment in segments)
        if (segment.id != excludedValue)
          DropdownMenuItem(
            value: segment.id,
            child: Text(segment.name, overflow: TextOverflow.ellipsis),
          ),
    ],
    onChanged: (selected) {
      if (selected != null) onChanged(selected);
    },
  );

  Widget _comparisonRows(
    BuildContext context,
    List<AnalyticsGoal> first,
    List<AnalyticsGoal> second,
    String firstLabel,
    String secondLabel,
  ) {
    final firstByName = {for (final goal in first) goal.name: goal};
    final secondByName = {for (final goal in second) goal.name: goal};
    final names = {...firstByName.keys, ...secondByName.keys}.toList()
      ..sort((a, b) {
        final aCount =
            (firstByName[a]?.count ?? 0) + (secondByName[a]?.count ?? 0);
        final bCount =
            (firstByName[b]?.count ?? 0) + (secondByName[b]?.count ?? 0);
        final byCount = bCount.compareTo(aCount);
        return byCount == 0 ? a.compareTo(b) : byCount;
      });
    if (names.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(
          context.tr(
            'No matching goal conversions in either range.',
            '两个比较范围内都没有目标转化。',
          ),
        ),
      );
    }
    return Column(
      children: [
        for (final name in names)
          _goalComparisonRow(
            context,
            name,
            firstByName[name],
            secondByName[name],
            firstLabel,
            secondLabel,
          ),
      ],
    );
  }

  Widget _goalComparisonRow(
    BuildContext context,
    String name,
    AnalyticsGoal? first,
    AnalyticsGoal? second,
    String firstLabel,
    String secondLabel,
  ) {
    final firstCount = first?.count ?? 0;
    final secondCount = second?.count ?? 0;
    final conversionDelta = firstCount - secondCount;
    final conversionChange = secondCount == 0
        ? context.tr('change unavailable from zero', '基数为 0，无法计算增幅')
        : '${_signedPercent((conversionDelta / secondCount) * 100)}%';
    final rateDelta =
        ((first?.conversionRate ?? 0) - (second?.conversionRate ?? 0)) * 100;
    final valueDelta = (first?.value ?? 0) - (second?.value ?? 0);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(name, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          LayoutBuilder(
            builder: (context, constraints) {
              final firstValue = _GoalComparisonValue(
                label: firstLabel,
                goal: first,
              );
              final secondValue = _GoalComparisonValue(
                label: secondLabel,
                goal: second,
              );
              if (constraints.maxWidth < 560) {
                return Column(
                  children: [
                    firstValue,
                    const SizedBox(height: 8),
                    secondValue,
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: firstValue),
                  const SizedBox(width: 8),
                  Expanded(child: secondValue),
                ],
              );
            },
          ),
          const SizedBox(height: 6),
          Text(
            context.tr(
              '${_signedInteger(conversionDelta)} conversions ($conversionChange) · ${_signedPercent(rateDelta)} pp conversion rate · ${_signedDecimal(valueDelta)} goal value',
              '${_signedInteger(conversionDelta)} 次转化（$conversionChange）· 转化率 ${_signedPercent(rateDelta)} 个百分点 · 目标价值 ${_signedDecimal(valueDelta)}',
            ),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const Divider(height: 18),
        ],
      ),
    );
  }

  String _audienceLabel(
    BuildContext context,
    String? segmentId,
    AsyncValue<List<AnalyticsSegmentOption>> options,
  ) {
    if (segmentId == null) return context.tr('All visitors', '全部访客');
    final segments = options.maybeWhen(
      data: (value) => value,
      orElse: () => const <AnalyticsSegmentOption>[],
    );
    return segments
            .where((segment) => segment.id == segmentId)
            .firstOrNull
            ?.name ??
        context.tr('Saved segment', '已保存分群');
  }

  String _segmentValue(String? segmentId) => segmentId ?? '';

  String? _segmentId(String value) => value.isEmpty ? null : value;

  Widget _definitionCard(Map<String, dynamic> definition) {
    final event = definition['triggerType'] == 'event';
    final detail = event
        ? '${definition['eventType'] ?? ''}${definition['eventName'] == null ? '' : ' · ${definition['eventName']}'}'
        : '${definition['pathPattern'] ?? ''} · ${definition['pathMatchMode'] ?? 'exact'}';
    return Card(
      child: ListTile(
        leading: Icon(event ? Icons.bolt_outlined : Icons.route_outlined),
        title: Text(definition['name'] as String? ?? ''),
        subtitle: Text(
          '$detail · ${context.tr('Value', '价值')} ${definition['fixedValue'] ?? 0}',
        ),
        trailing: Wrap(
          spacing: 2,
          children: [
            if (definition['enabled'] != true)
              const Icon(Icons.pause_circle_outline),
            IconButton(
              tooltip: context.tr('Edit', '编辑'),
              onPressed: () => _edit(definition),
              icon: const Icon(Icons.edit_outlined),
            ),
            IconButton(
              tooltip: context.tr('Delete', '删除'),
              onPressed: () => _delete(definition),
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
      ),
    );
  }

  String _message(Object error) =>
      error is ApiFailure ? error.message : '$error';
}

class _GoalComparisonValue extends StatelessWidget {
  const _GoalComparisonValue({required this.label, required this.goal});

  final String label;
  final AnalyticsGoal? goal;

  @override
  Widget build(BuildContext context) {
    final rate = (goal?.conversionRate ?? 0) * 100;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xfff3f5f8),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 4),
          Text(
            '${goal?.count ?? 0}',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          Text(context.tr('conversions', '次转化')),
          const SizedBox(height: 3),
          Text(
            context.tr(
              '${goal?.convertedSessions ?? 0} converted visits · ${rate.toStringAsFixed(1)}% rate',
              '${goal?.convertedSessions ?? 0} 次转化访问 · 转化率 ${rate.toStringAsFixed(1)}%',
            ),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          Text(
            context.tr(
              'Goal value ${goal?.value.toStringAsFixed(2) ?? '0.00'}',
              '目标价值 ${goal?.value.toStringAsFixed(2) ?? '0.00'}',
            ),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _GoalEditorDialog extends StatefulWidget {
  const _GoalEditorDialog({this.initial});

  final Map<String, dynamic>? initial;

  @override
  State<_GoalEditorDialog> createState() => _GoalEditorDialogState();
}

class _GoalEditorDialogState extends State<_GoalEditorDialog> {
  late final TextEditingController _name;
  late final TextEditingController _eventType;
  late final TextEditingController _eventName;
  late final TextEditingController _path;
  late final TextEditingController _fixedValue;
  late String _triggerType;
  late String _pathMatchMode;
  late bool _enabled;
  String? _error;

  bool get _editing => widget.initial != null;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _name = TextEditingController(text: initial?['name'] as String? ?? '');
    _eventType = TextEditingController(
      text: initial?['eventType'] as String? ?? '',
    );
    _eventName = TextEditingController(
      text: initial?['eventName'] as String? ?? '',
    );
    _path = TextEditingController(
      text: initial?['pathPattern'] as String? ?? '',
    );
    _fixedValue = TextEditingController(text: '${initial?['fixedValue'] ?? 0}');
    _triggerType = initial?['triggerType'] == 'page_view'
        ? 'page_view'
        : 'event';
    _pathMatchMode = initial?['pathMatchMode'] == 'contains'
        ? 'contains'
        : 'exact';
    _enabled = initial?['enabled'] as bool? ?? true;
  }

  @override
  void dispose() {
    _name.dispose();
    _eventType.dispose();
    _eventName.dispose();
    _path.dispose();
    _fixedValue.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      context.tr(
        '${_editing ? 'Edit' : 'Create'} goal',
        '${_editing ? '编辑' : '新建'}目标',
      ),
    ),
    content: SizedBox(
      width: 560,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 600),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _name,
                autofocus: !_editing,
                decoration: InputDecoration(
                  labelText: context.tr('Name', '名称'),
                ),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: Text(context.tr('Enabled', '启用')),
                value: _enabled,
                onChanged: (value) => setState(() => _enabled = value),
              ),
              DropdownButtonFormField<String>(
                initialValue: _triggerType,
                decoration: InputDecoration(
                  labelText: context.tr('Goal trigger', '目标触发方式'),
                ),
                items: [
                  DropdownMenuItem(
                    value: 'event',
                    child: Text(context.tr('Event', '事件')),
                  ),
                  DropdownMenuItem(
                    value: 'page_view',
                    child: Text(context.tr('Page view', '页面浏览')),
                  ),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _triggerType = value;
                    _error = null;
                  });
                },
              ),
              const SizedBox(height: 8),
              if (_triggerType == 'event') ...[
                TextField(
                  controller: _eventType,
                  onChanged: (_) => setState(() => _error = null),
                  decoration: InputDecoration(
                    labelText: context.tr('Event type', '事件类型'),
                    hintText: 'signup',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _eventName,
                  decoration: InputDecoration(
                    labelText: context.tr('Event name (optional)', '事件名称（可选）'),
                  ),
                ),
              ] else ...[
                TextField(
                  controller: _path,
                  onChanged: (_) => setState(() => _error = null),
                  decoration: InputDecoration(
                    labelText: context.tr('Page path', '页面路径'),
                    hintText: '/thank-you',
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: _pathMatchMode,
                  decoration: InputDecoration(
                    labelText: context.tr('Path matching', '路径匹配'),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: 'exact',
                      child: Text(context.tr('Exact path', '完整匹配')),
                    ),
                    DropdownMenuItem(
                      value: 'contains',
                      child: Text(context.tr('Contains path', '包含匹配')),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _pathMatchMode = value);
                  },
                ),
              ],
              const SizedBox(height: 8),
              TextField(
                controller: _fixedValue,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: context.tr('Conversion value', '转化价值'),
                  hintText: '0',
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.tr('Cancel', '取消')),
      ),
      FilledButton(onPressed: _save, child: Text(context.tr('Save', '保存'))),
    ],
  );

  void _save() {
    final name = _name.text.trim();
    final fixed = double.tryParse(_fixedValue.text.trim());
    if (name.isEmpty) {
      setState(() => _error = context.tr('Name is required.', '名称不能为空。'));
      return;
    }
    if (fixed == null || fixed < 0) {
      setState(
        () => _error = context.tr(
          'Value must be a non-negative number.',
          '价值必须是非负数字。',
        ),
      );
      return;
    }
    final body = <String, dynamic>{
      'name': name,
      'enabled': _enabled,
      'triggerType': _triggerType,
      'eventType': _triggerType == 'event' ? _eventType.text.trim() : null,
      'eventName': _triggerType == 'event' ? _eventName.text.trim() : null,
      'pathPattern': _triggerType == 'page_view' ? _path.text.trim() : null,
      'pathMatchMode': _pathMatchMode,
      'fixedValue': fixed,
    };
    if (_triggerType == 'event' && (body['eventType'] as String).isEmpty) {
      setState(
        () => _error = context.tr('Event type is required.', '事件类型不能为空。'),
      );
      return;
    }
    if (_triggerType == 'page_view' &&
        !(body['pathPattern'] as String).startsWith('/')) {
      setState(
        () => _error = context.tr('Path must start with /.', '路径必须以 / 开头。'),
      );
      return;
    }
    Navigator.pop(context, body);
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
