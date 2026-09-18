import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/i18n/app_i18n.dart';
import '../../../shared/presentation/page_help_button.dart';
import '../../../shared/presentation/site_top_bar.dart';
import '../application/analytics_range.dart';
import '../application/analytics_segment.dart';
import '../application/visitor_profile_controller.dart';

class VisitorProfilePage extends ConsumerWidget {
  const VisitorProfilePage({
    required this.siteId,
    required this.visitorId,
    this.embedded = false,
    super.key,
  });

  final String siteId;
  final String visitorId;
  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rangeState = ref.watch(analyticsRangeProvider(siteId));
    final segmentId = ref.watch(analyticsSegmentSelectionProvider(siteId));
    final query = AnalyticsVisitorProfileQuery(
      siteId: siteId,
      visitorId: visitorId,
      range: rangeState.range,
      segmentId: segmentId,
    );
    final profile = ref.watch(analyticsVisitorProfileProvider(query));
    return Scaffold(
      backgroundColor: const Color(0xfff3f5f8),
      appBar: embedded
          ? null
          : SiteTopBar(
              siteId: siteId,
              selected: SiteTopTab.visitors,
              help: const PageHelpButton(
                englishTitle: 'Visitor profile',
                chineseTitle: '访客画像说明',
                englishBody:
                    'Profiles use anonymous IDs scoped to this site. If the site sends a consented opaque User ID, browser profiles can be linked for this timeline. Conflicting IDs on one browser are kept separate. Lifetime first/last seen and visit totals are shown separately from details filtered to the selected date range and saved audience. Raw IP addresses and arbitrary event properties are not exposed.',
                chineseBody:
                    '画像使用当前站点范围内的匿名 ID；站点在取得同意后发送不含个人信息的 User ID 时，可关联多个浏览器档案。同一浏览器出现冲突 ID 时会保持分离。首次/最近出现时间和累计访问数与所选日期及分群筛选的明细分开展示；不会暴露原始 IP 或任意事件属性。',
              ),
              onRefresh: () =>
                  ref.invalidate(analyticsVisitorProfileProvider(query)),
            ),
      body: profile.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => _ProfileError(
          siteId: siteId,
          visitorId: visitorId,
          onRetry: () => ref.invalidate(analyticsVisitorProfileProvider(query)),
        ),
        data: (data) =>
            _VisitorProfileBody(siteId: siteId, profile: data, query: query),
      ),
    );
  }
}

class _ProfileError extends StatelessWidget {
  const _ProfileError({
    required this.siteId,
    required this.visitorId,
    required this.onRetry,
  });

  final String siteId;
  final String visitorId;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.person_search_outlined, size: 36),
              const SizedBox(height: 10),
              Text(
                context.tr('Visitor profile unavailable', '无法加载访客画像'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(
                context.tr(
                  'This anonymous visitor may no longer exist in this site or the request may have failed.',
                  '该匿名访客可能已不在此站点中，或请求暂时失败。',
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => context.go('/sites/$siteId/visitors'),
                    icon: const Icon(Icons.arrow_back),
                    label: Text(context.tr('Visitor reports', '返回访客报告')),
                  ),
                  FilledButton.tonal(
                    onPressed: onRetry,
                    child: Text(context.tr('Retry', '重试')),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SelectableText(
                visitorId,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _VisitorProfileBody extends ConsumerStatefulWidget {
  const _VisitorProfileBody({
    required this.siteId,
    required this.profile,
    required this.query,
  });

  final String siteId;
  final AnalyticsVisitorProfile profile;
  final AnalyticsVisitorProfileQuery query;

  @override
  ConsumerState<_VisitorProfileBody> createState() =>
      _VisitorProfileBodyState();
}

class _VisitorProfileBodyState extends ConsumerState<_VisitorProfileBody> {
  late List<AnalyticsVisitorProfileSession> _sessions;
  late List<AnalyticsVisitorProfileAction> _actions;
  String? _nextSessionsCursor;
  String? _nextActionsCursor;
  bool _loadingSessions = false;
  bool _loadingActions = false;
  String? _sessionsError;
  String? _actionsError;

  @override
  void initState() {
    super.initState();
    _resetHistory();
  }

  @override
  void didUpdateWidget(covariant _VisitorProfileBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.query != widget.query ||
        oldWidget.profile != widget.profile) {
      _resetHistory();
    }
  }

  void _resetHistory() {
    _sessions = List.of(widget.profile.sessions);
    _actions = List.of(widget.profile.actions);
    _nextSessionsCursor = widget.profile.nextSessionsCursor;
    _nextActionsCursor = widget.profile.nextActionsCursor;
    _loadingSessions = false;
    _loadingActions = false;
    _sessionsError = null;
    _actionsError = null;
  }

  Future<void> _loadOlderSessions() async {
    final cursor = _nextSessionsCursor;
    if (cursor == null || _loadingSessions) return;
    final pageQuery = AnalyticsVisitorProfileHistoryQuery(
      profileQuery: widget.query,
      sessionsCursor: cursor,
    );
    setState(() {
      _loadingSessions = true;
      _sessionsError = null;
    });
    try {
      ref.invalidate(analyticsVisitorProfileHistoryProvider(pageQuery));
      final page = await ref.read(
        analyticsVisitorProfileHistoryProvider(pageQuery).future,
      );
      if (!mounted) return;
      setState(() {
        _sessions.addAll(page.sessions);
        _nextSessionsCursor = page.nextSessionsCursor;
        _loadingSessions = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingSessions = false;
        _sessionsError = context.tr(
          'Could not load older visits. Please retry.',
          '无法加载更早访问，请重试。',
        );
      });
    }
  }

  Future<void> _loadOlderActions() async {
    final cursor = _nextActionsCursor;
    if (cursor == null || _loadingActions) return;
    final pageQuery = AnalyticsVisitorProfileHistoryQuery(
      profileQuery: widget.query,
      actionsCursor: cursor,
    );
    setState(() {
      _loadingActions = true;
      _actionsError = null;
    });
    try {
      ref.invalidate(analyticsVisitorProfileHistoryProvider(pageQuery));
      final page = await ref.read(
        analyticsVisitorProfileHistoryProvider(pageQuery).future,
      );
      if (!mounted) return;
      setState(() {
        _actions.addAll(page.actions);
        _nextActionsCursor = page.nextActionsCursor;
        _loadingActions = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingActions = false;
        _actionsError = context.tr(
          'Could not load earlier actions. Please retry.',
          '无法加载更早动作，请重试。',
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;
    final siteId = widget.siteId;
    final shortId = profile.visitorId.length > 20
        ? '${profile.visitorId.substring(0, 12)}…${profile.visitorId.substring(profile.visitorId.length - 6)}'
        : profile.visitorId;
    final bounceRate = profile.rangeSessions == 0
        ? 0.0
        : profile.rangeBouncedSessions / profile.rangeSessions * 100;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        OutlinedButton.icon(
          onPressed: () => context.go('/sites/$siteId/visitors'),
          icon: const Icon(Icons.arrow_back),
          label: Text(context.tr('All visitors', '返回访客报告')),
          style: OutlinedButton.styleFrom(alignment: Alignment.centerLeft),
        ),
        const SizedBox(height: 14),
        Card(
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                const CircleAvatar(
                  radius: 25,
                  child: Icon(Icons.person_outline, size: 28),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.tr('Visitor profile', '访客画像'),
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 3),
                      SelectableText(shortId),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: context.tr('Copy anonymous ID', '复制匿名 ID'),
                  onPressed: () async {
                    await Clipboard.setData(
                      ClipboardData(text: profile.visitorId),
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(context.tr('ID copied', '已复制 ID')),
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.copy_outlined),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _MetricCard(
              icon: Icons.history,
              label: context.tr('Lifetime visits', '累计访问'),
              value: '${profile.lifetimeSessions}',
              detail: context.tr(
                'First seen ${_date(profile.firstSeenAt)} · last seen ${_date(profile.lastSeenAt)}',
                '首次 ${_date(profile.firstSeenAt)} · 最近 ${_date(profile.lastSeenAt)}',
              ),
            ),
            if (profile.identityLinkStatus == 'linked')
              _MetricCard(
                icon: Icons.devices_outlined,
                label: context.tr('Linked browser profiles', '已关联浏览器档案'),
                value: '${profile.linkedBrowserCount}',
                detail: context.tr(
                  'Timeline combined using the site-provided User ID',
                  '按站点提供的 User ID 合并访问时间线',
                ),
              ),
            if (profile.identityLinkStatus == 'ambiguous')
              _MetricCard(
                icon: Icons.warning_amber_outlined,
                label: context.tr('Identity kept separate', '身份保持分离'),
                value: context.tr('Ambiguous', '存在冲突'),
                detail: context.tr(
                  'Multiple User IDs were seen on this browser profile; visits were not merged.',
                  '此浏览器档案曾出现多个 User ID，因此没有合并访问记录。',
                ),
              ),
            _MetricCard(
              icon: Icons.visibility_outlined,
              label: context.tr('Visits in selected period', '所选周期访问'),
              value: '${profile.rangeSessions}',
              detail: context.tr(
                'Filtered by date range and saved audience',
                '按日期范围和已选分群筛选',
              ),
            ),
            _MetricCard(
              icon: Icons.web_outlined,
              label: context.tr('Page views', '页面浏览'),
              value: '${profile.rangePageViews}',
            ),
            _MetricCard(
              icon: Icons.bolt_outlined,
              label: context.tr('Events', '事件'),
              value: '${profile.rangeEvents}',
            ),
            _MetricCard(
              icon: Icons.logout,
              label: context.tr('Bounce rate', '跳出率'),
              value: '${bounceRate.toStringAsFixed(1)}%',
              detail: context.tr(
                '${profile.rangeBouncedSessions} bounced visits',
                '${profile.rangeBouncedSessions} 次跳出访问',
              ),
            ),
            _MetricCard(
              icon: Icons.schedule,
              label: context.tr('Average visit duration', '平均访问时长'),
              value: _duration(profile.averageSessionDurationMs),
            ),
          ],
        ),
        const SizedBox(height: 18),
        _SectionTitle(
          icon: Icons.laptop_chromebook_outlined,
          title: context.tr('Visit history', '访问历史'),
          subtitle: context.tr(
            '${profile.sessions.length} most recent visits in the selected period',
            '显示所选周期内最近 ${profile.sessions.length} 次访问',
          ),
        ),
        if (_sessions.isEmpty)
          _EmptyCard(
            text: context.tr(
              'No visits match the selected date range and audience.',
              '所选日期范围和分群内没有匹配的访问。',
            ),
          )
        else ...[
          for (final visit in _sessions) _VisitCard(visit: visit),
        ],
        if (_nextSessionsCursor != null || _sessionsError != null)
          _HistoryPageButton(
            label: context.tr('Load older visits', '加载更早访问'),
            loading: _loadingSessions,
            error: _sessionsError,
            onPressed: _loadOlderSessions,
          ),
        const SizedBox(height: 18),
        _SectionTitle(
          icon: Icons.timeline,
          title: context.tr('Page and event timeline', '页面与事件时间线'),
          subtitle: context.tr(
            'The latest recorded actions from matching visits; event properties are intentionally omitted.',
            '显示匹配访问中最近记录的动作；为保护隐私，此处不展示事件属性。',
          ),
        ),
        if (_actions.isEmpty)
          _EmptyCard(
            text: context.tr('No actions in this period.', '此周期内暂无动作。'),
          )
        else ...[
          Card(
            elevation: 0,
            child: Column(
              children: [
                for (final action in _actions) _ActionTile(action: action),
              ],
            ),
          ),
        ],
        if (_nextActionsCursor != null || _actionsError != null)
          _HistoryPageButton(
            label: context.tr('Load earlier actions', '加载更早动作'),
            loading: _loadingActions,
            error: _actionsError,
            onPressed: _loadOlderActions,
          ),
        const SizedBox(height: 20),
        Text(
          context.tr(
            'Visitor IDs are anonymous and site-scoped. First/last seen and lifetime visit totals are retained separately; visit details above follow the selected date range and audience.',
            '访客 ID 为匿名且仅限当前站点。首次/最近出现时间和累计访问数单独保留；上方访问明细遵循所选日期范围和分群。',
          ),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.icon,
    required this.label,
    required this.value,
    this.detail,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? detail;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 230,
    child: Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: Theme.of(context).textTheme.bodySmall),
                  Text(value, style: Theme.of(context).textTheme.titleLarge),
                  if (detail != null) ...[
                    const SizedBox(height: 3),
                    Text(detail!, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 9),
    child: Row(
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ],
    ),
  );
}

class _VisitCard extends StatelessWidget {
  const _VisitCard({required this.visit});

  final AnalyticsVisitorProfileSession visit;

  @override
  Widget build(BuildContext context) {
    final location = [visit.city, visit.region, visit.countryCode]
        .whereType<String>()
        .where((value) => value.isNotEmpty)
        .toSet()
        .join(' · ');
    final campaign = [
      visit.campaignSource,
      visit.campaignMedium,
      visit.campaignName,
    ].whereType<String>().where((value) => value.isNotEmpty).join(' / ');
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 17,
                  child: Icon(
                    visit.visitorType == 'returning'
                        ? Icons.history
                        : Icons.looks_one_outlined,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _page(visit.entryPage),
                    style: Theme.of(context).textTheme.titleSmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  _date(visit.startedAt),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(left: 44, top: 3),
              child: Text(
                '${context.tr('Exit', '退出')}: ${_page(visit.exitPage)} · ${visit.pageViews} ${context.tr('pages', '页')} · ${visit.events} ${context.tr('events', '事件')} · ${_duration(visit.durationMs)}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 7,
              runSpacing: 4,
              children: [
                if (visit.visitorType == 'returning')
                  _InfoChip(text: context.tr('Returning visit', '回访'))
                else
                  _InfoChip(text: context.tr('New visit', '新访客')),
                if (visit.bounce) _InfoChip(text: context.tr('Bounce', '跳出')),
                if (visit.browser != null) _InfoChip(text: visit.browser!),
                if (visit.operatingSystem != null)
                  _InfoChip(text: visit.operatingSystem!),
                if (visit.deviceType != null)
                  _InfoChip(text: visit.deviceType!),
                if (visit.language != null) _InfoChip(text: visit.language!),
                if (location.isNotEmpty) _InfoChip(text: location),
                if (visit.referrerHost != null)
                  _InfoChip(
                    text:
                        '${context.tr('Referrer', '来源')}: ${visit.referrerHost}',
                  ),
                if (campaign.isNotEmpty)
                  _InfoChip(text: '${context.tr('Campaign', '活动')}: $campaign'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.action});

  final AnalyticsVisitorProfileAction action;

  @override
  Widget build(BuildContext context) => ListTile(
    dense: true,
    leading: CircleAvatar(
      radius: 17,
      child: Icon(
        action.eventType == 'page_view'
            ? Icons.web_outlined
            : Icons.bolt_outlined,
        size: 18,
      ),
    ),
    title: Text(
      action.title?.isNotEmpty == true
          ? action.title!
          : action.path ?? action.eventType,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    ),
    subtitle: Text(
      '${action.eventType} · ${_date(action.at)} · ${context.tr('Visit', '访问')} ${_shortSessionId(action.sessionId)}',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    ),
    trailing: Text(_time(action.at)),
  );
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Chip(
    label: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis),
    visualDensity: VisualDensity.compact,
    padding: EdgeInsets.zero,
  );
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Card(
    elevation: 0,
    child: Padding(
      padding: const EdgeInsets.all(22),
      child: Center(child: Text(text, textAlign: TextAlign.center)),
    ),
  );
}

class _HistoryPageButton extends StatelessWidget {
  const _HistoryPageButton({
    required this.label,
    required this.loading,
    required this.error,
    required this.onPressed,
  });

  final String label;
  final bool loading;
  final String? error;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        TextButton.icon(
          onPressed: loading ? null : onPressed,
          icon: loading
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.expand_more),
          label: Text(label),
        ),
      ],
    ),
  );
}

String _page(String? value) => value?.isNotEmpty == true ? value! : '—';

String _date(DateTime value) => value.toString().substring(0, 16);

String _time(DateTime value) => value.toString().substring(11, 16);

String _duration(int milliseconds) {
  final seconds = milliseconds ~/ 1000;
  if (seconds < 60) return '${seconds}s';
  return '${seconds ~/ 60}m ${seconds % 60}s';
}

String _shortSessionId(String value) =>
    value.length > 8 ? value.substring(0, 8) : value;
