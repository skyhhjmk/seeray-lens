import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_i18n.dart';
import '../../../shared/presentation/page_help_button.dart';
import '../../../shared/presentation/site_top_bar.dart';
import '../application/realtime_controller.dart';

class RealtimePage extends ConsumerStatefulWidget {
  const RealtimePage({required this.siteId, this.embedded = false, super.key});

  final String siteId;
  final bool embedded;

  @override
  ConsumerState<RealtimePage> createState() => _RealtimePageState();
}

class _RealtimePageState extends ConsumerState<RealtimePage> {
  static const _windows = [5, 15, 30];
  late Timer _refreshTimer;
  int _windowMinutes = 30;

  AnalyticsRealtimeQuery get _query =>
      (siteId: widget.siteId, windowMinutes: _windowMinutes);

  @override
  void initState() {
    super.initState();
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) ref.invalidate(analyticsRealtimeProvider(_query));
    });
  }

  @override
  void dispose() {
    _refreshTimer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final report = ref.watch(analyticsRealtimeProvider(_query));
    return Scaffold(
      backgroundColor: const Color(0xfff3f5f8),
      appBar: widget.embedded
          ? null
          : SiteTopBar(
              siteId: widget.siteId,
              selected: SiteTopTab.realtime,
              help: const PageHelpButton(
                englishTitle: 'Live visitors',
                chineseTitle: '实时访客说明',
                englishBody:
                    'Live visits are read directly from accepted raw events, so they appear before the periodic analytics rollup. The page refreshes every 10 seconds and shows the latest 20 actions for each active visit.',
                chineseBody:
                    '实时访问直接读取已接收的原始事件，因此不必等待定期汇总。页面每 10 秒刷新，并展示每次活跃访问最近 20 个动作。',
              ),
              onRefresh: () =>
                  ref.invalidate(analyticsRealtimeProvider(_query)),
            ),
      body: report.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Text(context.tr('Could not load live visitors', '无法加载实时访客')),
        ),
        data: (visitors) => _body(context, visitors),
      ),
    );
  }

  Widget _body(BuildContext context, List<AnalyticsLiveVisitor> visitors) {
    final uniqueVisitors = visitors
        .map((visitor) => visitor.visitorId)
        .toSet()
        .length;
    final eventCount = visitors.fold<int>(
      0,
      (sum, visitor) => sum + visitor.events,
    );
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(analyticsRealtimeProvider(_query)),
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tr('Live visitors', '实时访客'),
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      context.tr(
                        'Live event stream · updates every 10 seconds',
                        '实时事件流 · 每 10 秒自动刷新',
                      ),
                    ),
                  ],
                ),
              ),
              DropdownButton<int>(
                value: _windowMinutes,
                underline: const SizedBox.shrink(),
                onChanged: (value) {
                  if (value != null) setState(() => _windowMinutes = value);
                },
                items: [
                  for (final minutes in _windows)
                    DropdownMenuItem(
                      value: minutes,
                      child: Text(
                        context.tr('Last $minutes min', '最近 $minutes 分钟'),
                      ),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _SummaryCard(
                icon: Icons.people_alt_outlined,
                label: context.tr('Active visitors', '活跃访客'),
                value: '$uniqueVisitors',
              ),
              _SummaryCard(
                icon: Icons.bolt_outlined,
                label: context.tr('Active visits', '活跃访问'),
                value: '${visitors.length}',
              ),
              _SummaryCard(
                icon: Icons.ads_click_outlined,
                label: context.tr('Events in active visits', '活跃访问事件'),
                value: '$eventCount',
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (visitors.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  children: [
                    const Icon(Icons.sensors_off_outlined, size: 36),
                    const SizedBox(height: 10),
                    Text(
                      context.tr(
                        'No active visits in this window',
                        '此时间范围内暂无活跃访问',
                      ),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 5),
                    Text(
                      context.tr(
                        'Once the site tracker sends events, visitors will appear here with their recent page and event activity.',
                        '站点追踪器开始发送事件后，这里会显示访客及其最近页面和事件活动。',
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                context.tr(
                  'Showing the latest ${visitors.length} active visits',
                  '显示最近的 ${visitors.length} 次活跃访问',
                ),
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
            for (final visitor in visitors) _LiveVisitCard(visitor: visitor),
          ],
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 210,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(icon, color: const Color(0xff42678f)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: Theme.of(context).textTheme.bodySmall),
                  Text(value, style: Theme.of(context).textTheme.titleLarge),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _LiveVisitCard extends StatelessWidget {
  const _LiveVisitCard({required this.visitor});

  final AnalyticsLiveVisitor visitor;

  @override
  Widget build(BuildContext context) {
    final id = visitor.visitorId;
    final shortId = id.length <= 8 ? id : id.substring(0, 8);
    final page = visitor.currentTitle?.isNotEmpty == true
        ? visitor.currentTitle!
        : visitor.currentPage ?? context.tr('Unknown page', '未知页面');
    final location = [visitor.city, visitor.region, visitor.countryCode]
        .whereType<String>()
        .where((value) => value.isNotEmpty)
        .toSet()
        .join(' · ');

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        leading: const CircleAvatar(
          backgroundColor: Color(0xffe8eff7),
          child: Icon(Icons.person_outline, color: Color(0xff315e87)),
        ),
        title: Text(page, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '${context.tr('Visitor', '访客')} $shortId · ${_relativeTime(context, visitor.lastActivityAt)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('${visitor.pageViews} ${context.tr('pages', '页')}'),
            Text('${visitor.events} ${context.tr('events', '事件')}'),
          ],
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (location.isNotEmpty)
                _InfoChip(icon: Icons.place_outlined, text: location),
              if (visitor.deviceType != null)
                _InfoChip(
                  icon: Icons.devices_outlined,
                  text: visitor.deviceType!,
                ),
              if (visitor.browser != null)
                _InfoChip(
                  icon: Icons.language_outlined,
                  text: visitor.browser!,
                ),
              if (visitor.operatingSystem != null)
                _InfoChip(
                  icon: Icons.computer_outlined,
                  text: visitor.operatingSystem!,
                ),
              if (visitor.language != null)
                _InfoChip(
                  icon: Icons.translate_outlined,
                  text: visitor.language!,
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${context.tr('Entry', '入口')}: ${visitor.entryPage ?? '—'}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(_duration(context, visitor.durationMs)),
            ],
          ),
          const Divider(height: 22),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              context.tr('Recent activity', '最近活动'),
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          const SizedBox(height: 4),
          for (final action in visitor.actions)
            ListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                action.eventType == 'page_view'
                    ? Icons.web_outlined
                    : Icons.bolt_outlined,
                size: 18,
              ),
              title: Text(
                action.title?.isNotEmpty == true
                    ? action.title!
                    : action.path ?? action.eventType,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                '${action.eventType} · ${action.at.toString().substring(0, 16)}',
                maxLines: 1,
              ),
            ),
        ],
      ),
    );
  }

  static String _relativeTime(BuildContext context, DateTime time) {
    final seconds = DateTime.now().difference(time).inSeconds.clamp(0, 86400);
    if (seconds < 60) return context.tr('$seconds sec ago', '$seconds 秒前');
    final minutes = seconds ~/ 60;
    if (minutes < 60) return context.tr('$minutes min ago', '$minutes 分钟前');
    return context.tr('${minutes ~/ 60} hr ago', '${minutes ~/ 60} 小时前');
  }

  static String _duration(BuildContext context, int durationMs) {
    final seconds = durationMs ~/ 1000;
    if (seconds < 60) return context.tr('Visit ${seconds}s', '访问 $seconds 秒');
    return context.tr(
      'Visit ${seconds ~/ 60}m ${seconds % 60}s',
      '访问 ${seconds ~/ 60} 分 ${seconds % 60} 秒',
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Chip(
    avatar: Icon(icon, size: 16),
    label: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis),
    visualDensity: VisualDensity.compact,
  );
}
