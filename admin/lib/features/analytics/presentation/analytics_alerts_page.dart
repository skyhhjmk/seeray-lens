import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_i18n.dart';
import '../../../shared/presentation/page_help_button.dart';
import '../../../shared/presentation/site_top_bar.dart';
import '../application/analytics_alerts.dart';

class AnalyticsAlertsPage extends ConsumerStatefulWidget {
  const AnalyticsAlertsPage({
    required this.siteId,
    this.embedded = false,
    super.key,
  });

  final String siteId;
  final bool embedded;

  @override
  ConsumerState<AnalyticsAlertsPage> createState() =>
      _AnalyticsAlertsPageState();
}

class _AnalyticsAlertsPageState extends ConsumerState<AnalyticsAlertsPage> {
  bool _busy = false;
  String? _actionError;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(analyticsAlertsProvider(widget.siteId));
    return Scaffold(
      backgroundColor: const Color(0xfff3f5f8),
      appBar: widget.embedded
          ? null
          : SiteTopBar(
              siteId: widget.siteId,
              selected: SiteTopTab.alerts,
              help: const PageHelpButton(
                englishTitle: 'Analytics alerts',
                chineseTitle: '分析告警说明',
                englishBody:
                    'Evaluate yesterday’s completed site-local metrics against the previous day or the same weekday last week. Delivery credentials are managed by the server administrator.',
                chineseBody: '按站点时区比较最近一个完整自然日与前一日或上周同日。通知渠道凭据由服务器管理员管理。',
              ),
              onRefresh: _busy ? null : _reload,
            ),
      body: state.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _error(error.toString()),
        data: (value) => RefreshIndicator(
          onRefresh: _reload,
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
                          context.tr('Analytics alerts', '分析告警'),
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          context.tr(
                            'Get notified when a daily metric moves beyond your threshold. Schedules use ${value.timezone}.',
                            '当每日指标变化超过阈值时接收通知。计划使用站点时区 ${value.timezone}。',
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (value.canManage)
                    FilledButton.icon(
                      onPressed: _busy ? null : () => _edit(value),
                      icon: const Icon(Icons.add_alert_outlined),
                      label: Text(context.tr('New alert', '新建告警')),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              _deliveryCard(value),
              if (_actionError != null) ...[
                const SizedBox(height: 12),
                Card(
                  color: const Color(0xffffeeee),
                  child: ListTile(
                    leading: const Icon(Icons.error_outline, color: Colors.red),
                    title: Text(_actionError!),
                    trailing: IconButton(
                      tooltip: context.tr('Dismiss', '关闭'),
                      onPressed: () => setState(() => _actionError = null),
                      icon: const Icon(Icons.close),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              if (value.alerts.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(30),
                    child: Column(
                      children: [
                        const Icon(
                          Icons.notifications_active_outlined,
                          size: 42,
                        ),
                        const SizedBox(height: 12),
                        Text(context.tr('No alerts yet.', '暂无告警。')),
                        if (value.canManage) ...[
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: _busy ? null : () => _edit(value),
                            icon: const Icon(Icons.add),
                            label: Text(context.tr('Create an alert', '创建告警')),
                          ),
                        ],
                      ],
                    ),
                  ),
                )
              else
                ...value.alerts.map((alert) => _alertCard(alert, value)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _deliveryCard(AnalyticsAlertsState state) {
    final available = <String>[
      if (state.emailEnabled) 'email',
      if (state.slackEnabled) 'slack',
      if (state.teamsEnabled) 'teams',
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              available.isEmpty
                  ? Icons.notifications_off_outlined
                  : Icons.notifications_active_outlined,
              color: available.isEmpty
                  ? Colors.orange.shade800
                  : Colors.green.shade700,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    available.isEmpty
                        ? context.tr(
                            'No delivery channel is configured',
                            '尚未配置通知渠道',
                          )
                        : context.tr('Available delivery channels', '可用通知渠道'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    available.isEmpty
                        ? context.tr(
                            'Ask the server administrator to configure SMTP, Slack, or Microsoft Teams delivery. Secret URLs and credentials are never entered in this page.',
                            '请联系服务器管理员配置 SMTP、Slack 或 Microsoft Teams 通知。此页面不会收集密钥或 webhook 地址。',
                          )
                        : context.tr(
                            '${available.map(_channelLabel).join(' · ')} are configured by the server administrator. Webhook URLs and SMTP credentials stay server-side.',
                            '已由服务器管理员配置：${available.map(_channelLabelZh).join(' · ')}。Webhook 地址和 SMTP 凭据仅保存在服务端。',
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _alertCard(AnalyticsAlert alert, AnalyticsAlertsState state) {
    final triggered = alert.lastStatus == 'triggered';
    final failed = alert.lastStatus == 'failed';
    final last = alert.lastEvaluatedDate == null
        ? context.tr('Not evaluated yet', '尚未评估')
        : context.tr(
            'Last checked ${alert.lastEvaluatedDate} · ${alert.timezone}',
            '最近检查 ${alert.lastEvaluatedDate} · ${alert.timezone}',
          );
    final next = alert.enabled && alert.nextRunLocal != null
        ? context.tr(
            'Next check ${alert.nextRunLocal} · ${alert.timezone}',
            '下次检查 ${alert.nextRunLocal} · ${alert.timezone}',
          )
        : context.tr('Paused', '已暂停');
    final comparison = alert.baseline == 'same_weekday_last_week'
        ? context.tr('same weekday last week', '上周同日')
        : context.tr('previous day', '前一日');
    final direction = alert.direction == 'increase'
        ? context.tr('increase', '上升')
        : context.tr('decrease', '下降');
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    alert.name,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                Chip(
                  avatar: Icon(
                    failed
                        ? Icons.error_outline
                        : triggered
                        ? Icons.notifications_active
                        : alert.enabled
                        ? Icons.check_circle_outline
                        : Icons.pause_circle_outline,
                    size: 16,
                  ),
                  label: Text(
                    failed
                        ? context.tr('Delivery failed', '通知失败')
                        : triggered
                        ? context.tr('Triggered', '已触发')
                        : alert.enabled
                        ? context.tr('Monitoring', '监控中')
                        : context.tr('Paused', '已暂停'),
                  ),
                  backgroundColor: failed
                      ? const Color(0xffffe8e8)
                      : triggered
                      ? const Color(0xfffff1d6)
                      : alert.enabled
                      ? const Color(0xffe5f4ed)
                      : const Color(0xffeceff3),
                ),
                if (state.canManage)
                  PopupMenuButton<String>(
                    enabled: !_busy,
                    onSelected: (action) {
                      if (action == 'edit') _edit(state, alert);
                      if (action == 'toggle') _toggle(state, alert);
                      if (action == 'delete') _delete(alert);
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'edit',
                        child: Text(context.tr('Edit', '编辑')),
                      ),
                      PopupMenuItem(
                        value: 'toggle',
                        child: Text(
                          alert.enabled
                              ? context.tr('Pause', '暂停')
                              : context.tr('Resume', '恢复'),
                        ),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Text(context.tr('Delete', '删除')),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                Chip(label: Text(_metricLabel(alert.metric))),
                Chip(
                  label: Text(
                    context.tr(
                      '$direction by ${alert.thresholdPercent.toStringAsFixed(0)}% vs $comparison',
                      '$comparison 比较${alert.thresholdPercent.toStringAsFixed(0)}%$direction时通知',
                    ),
                  ),
                ),
                Chip(
                  label: Text('${_time(alert.localTime)} · ${alert.timezone}'),
                ),
                ...alert.channels.map(
                  (channel) => Chip(
                    avatar: Icon(_channelIcon(channel), size: 16),
                    label: Text(_channelLabel(channel)),
                  ),
                ),
              ],
            ),
            if (alert.recipients.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                '${context.tr('Recipients', '收件人')}: ${alert.recipients.join(', ')}',
              ),
            ],
            const SizedBox(height: 8),
            Text(last),
            Text(next),
            if (alert.lastMessage != null && (failed || triggered)) ...[
              const SizedBox(height: 4),
              Text(
                alert.lastMessage!,
                style: TextStyle(
                  color: failed ? Colors.red.shade800 : Colors.brown.shade800,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _edit(
    AnalyticsAlertsState state, [
    AnalyticsAlert? alert,
  ]) async {
    final values = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (context) => _AnalyticsAlertEditor(state: state, alert: alert),
    );
    if (values == null || !mounted) return;
    await _perform(() async {
      await ref
          .read(analyticsAlertsRepositoryProvider)
          .save(siteId: widget.siteId, alertId: alert?.id, values: values);
    });
  }

  Future<void> _toggle(AnalyticsAlertsState state, AnalyticsAlert alert) async {
    await _perform(() async {
      await ref
          .read(analyticsAlertsRepositoryProvider)
          .save(
            siteId: widget.siteId,
            alertId: alert.id,
            values: _alertValues(alert, enabled: !alert.enabled),
          );
    });
  }

  Future<void> _delete(AnalyticsAlert alert) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.tr('Delete alert?', '删除告警？')),
        content: Text(
          context.tr(
            '“${alert.name}” will stop running and its configuration will be removed.',
            '“${alert.name}”将停止运行并删除其配置。',
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
    if (confirmed != true || !mounted) return;
    await _perform(() async {
      await ref
          .read(analyticsAlertsRepositoryProvider)
          .delete(widget.siteId, alert.id);
    });
  }

  Future<void> _perform(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _actionError = null;
    });
    try {
      await action();
      if (mounted) ref.invalidate(analyticsAlertsProvider(widget.siteId));
    } catch (error) {
      if (mounted) setState(() => _actionError = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reload() async =>
      ref.invalidate(analyticsAlertsProvider(widget.siteId));

  Widget _error(String message) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 36),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
            label: Text(context.tr('Retry', '重试')),
          ),
        ],
      ),
    ),
  );
}

class _AnalyticsAlertEditor extends StatefulWidget {
  const _AnalyticsAlertEditor({required this.state, this.alert});
  final AnalyticsAlertsState state;
  final AnalyticsAlert? alert;

  @override
  State<_AnalyticsAlertEditor> createState() => _AnalyticsAlertEditorState();
}

class _AnalyticsAlertEditorState extends State<_AnalyticsAlertEditor> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _threshold;
  late final TextEditingController _recipient;
  late final Set<String> _channels;
  late final List<String> _recipients;
  late String _metric;
  late String _direction;
  late String _baseline;
  late String _time;
  late bool _enabled;
  String? _formError;

  List<String> get _available => [
    if (widget.state.emailEnabled) 'email',
    if (widget.state.slackEnabled) 'slack',
    if (widget.state.teamsEnabled) 'teams',
  ];

  @override
  void initState() {
    super.initState();
    final alert = widget.alert;
    _name = TextEditingController(text: alert?.name ?? '');
    _threshold = TextEditingController(
      text: alert?.thresholdPercent.toStringAsFixed(0) ?? '20',
    );
    _recipient = TextEditingController();
    _metric = alert?.metric ?? 'visitors';
    _direction = alert?.direction ?? 'increase';
    _baseline = alert?.baseline ?? 'previous_day';
    _time = alert?.localTime ?? '09:00:00';
    _enabled = alert?.enabled ?? true;
    _channels = {...?alert?.channels};
    if (alert == null && _available.isNotEmpty) _channels.add(_available.first);
    _recipients = [...?alert?.recipients];
  }

  @override
  void dispose() {
    _name.dispose();
    _threshold.dispose();
    _recipient.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      context.tr(
        widget.alert == null ? 'New analytics alert' : 'Edit analytics alert',
        widget.alert == null ? '新建分析告警' : '编辑分析告警',
      ),
    ),
    content: SizedBox(
      width: 560,
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _name,
                maxLength: 120,
                decoration: InputDecoration(
                  labelText: context.tr('Alert name', '告警名称'),
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? context.tr('Enter a name.', '请输入名称。')
                    : null,
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _metric,
                decoration: InputDecoration(
                  labelText: context.tr('Metric', '指标'),
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'visitors',
                    child: Text('Unique visitors'),
                  ),
                  DropdownMenuItem(value: 'sessions', child: Text('Sessions')),
                  DropdownMenuItem(
                    value: 'page_views',
                    child: Text('Page views'),
                  ),
                  DropdownMenuItem(
                    value: 'bounce_rate',
                    child: Text('Bounce rate'),
                  ),
                ],
                onChanged: (value) => setState(() => _metric = value!),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _baseline,
                decoration: InputDecoration(
                  labelText: context.tr('Compare with', '比较基线'),
                ),
                items: [
                  DropdownMenuItem(
                    value: 'previous_day',
                    child: Text(context.tr('Previous day', '前一日')),
                  ),
                  DropdownMenuItem(
                    value: 'same_weekday_last_week',
                    child: Text(context.tr('Same weekday last week', '上周同日')),
                  ),
                ],
                onChanged: (value) => setState(() => _baseline = value!),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _direction,
                      decoration: InputDecoration(
                        labelText: context.tr('Alert on', '触发方向'),
                      ),
                      items: [
                        DropdownMenuItem(
                          value: 'increase',
                          child: Text(context.tr('Increase', '上升')),
                        ),
                        DropdownMenuItem(
                          value: 'decrease',
                          child: Text(context.tr('Decrease', '下降')),
                        ),
                      ],
                      onChanged: (value) => setState(() => _direction = value!),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _threshold,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: context.tr('Threshold (%)', '变化阈值 (%)'),
                      ),
                      validator: (value) {
                        final number = double.tryParse(value ?? '');
                        return number == null || number <= 0 || number > 1000
                            ? context.tr('Enter 0.01–1000.', '请输入 0.01–1000。')
                            : null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(context.tr('Evaluation time', '检查时间')),
                subtitle: Text(
                  '${_time.substring(0, 5)} · ${widget.state.timezone}',
                ),
                trailing: const Icon(Icons.schedule),
                onTap: _chooseTime,
              ),
              const Divider(),
              Text(
                context.tr('Notify through', '通知渠道'),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              if (_available.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    context.tr(
                      'No channel is configured. Ask your server administrator to enable SMTP, Slack, or Teams.',
                      '尚无可用渠道，请联系服务器管理员配置 SMTP、Slack 或 Teams。',
                    ),
                  ),
                )
              else
                ...['email', 'slack', 'teams'].map((channel) {
                  final enabled = _available.contains(channel);
                  return CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: enabled && _channels.contains(channel),
                    onChanged: enabled
                        ? (value) => setState(
                            () => value == true
                                ? _channels.add(channel)
                                : _channels.remove(channel),
                          )
                        : null,
                    title: Text(_channelLabel(channel)),
                    subtitle: Text(
                      enabled
                          ? context.tr('Configured on server', '服务端已配置')
                          : context.tr('Not configured on server', '服务端未配置'),
                    ),
                  );
                }),
              if (_channels.contains('email')) ...[
                const SizedBox(height: 4),
                Text(
                  context.tr('Email recipients (up to 10)', '邮件收件人（最多 10 个）'),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                Wrap(
                  spacing: 6,
                  children: _recipients
                      .map(
                        (email) => InputChip(
                          label: Text(email),
                          onDeleted: () =>
                              setState(() => _recipients.remove(email)),
                        ),
                      )
                      .toList(),
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _recipient,
                        keyboardType: TextInputType.emailAddress,
                        decoration: InputDecoration(
                          hintText: context.tr(
                            'name@example.com',
                            'name@example.com',
                          ),
                        ),
                        onSubmitted: (_) => _addRecipient(),
                      ),
                    ),
                    IconButton(
                      tooltip: context.tr('Add recipient', '添加收件人'),
                      onPressed: _addRecipient,
                      icon: const Icon(Icons.add_circle_outline),
                    ),
                  ],
                ),
              ],
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(context.tr('Enable monitoring', '启用监控')),
                subtitle: Text(
                  context.tr(
                    'Checks once a day after the selected local time.',
                    '每天在所选站点本地时间执行一次。',
                  ),
                ),
                value: _enabled,
                onChanged: _available.isEmpty || _channels.isEmpty
                    ? null
                    : (value) => setState(() => _enabled = value),
              ),
              if (_formError != null)
                Text(
                  _formError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
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
      FilledButton(
        onPressed: _save,
        child: Text(context.tr('Save alert', '保存告警')),
      ),
    ],
  );

  Future<void> _chooseTime() async {
    final parsed = _time.split(':');
    final selected = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: int.tryParse(parsed[0]) ?? 9,
        minute: int.tryParse(parsed[1]) ?? 0,
      ),
    );
    if (selected != null) {
      setState(
        () => _time =
            '${selected.hour.toString().padLeft(2, '0')}:${selected.minute.toString().padLeft(2, '0')}:00',
      );
    }
  }

  void _addRecipient() {
    final email = _recipient.text.trim().toLowerCase();
    if (email.isEmpty) return;
    setState(() {
      if (!_recipients.contains(email) && _recipients.length < 10) {
        _recipients.add(email);
      }
      _recipient.clear();
    });
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    if (_channels.isEmpty) {
      setState(
        () => _formError = context.tr(
          'Choose at least one configured notification channel.',
          '请选择至少一个已配置的通知渠道。',
        ),
      );
      return;
    }
    if (_channels.contains('email') && _recipients.isEmpty) {
      setState(
        () => _formError = context.tr(
          'Add at least one email recipient.',
          '请至少添加一个邮件收件人。',
        ),
      );
      return;
    }
    Navigator.pop(context, <String, Object?>{
      'name': _name.text.trim(),
      'metric': _metric,
      'direction': _direction,
      'baseline': _baseline,
      'thresholdPercent': double.parse(_threshold.text),
      'localTime': _time,
      'channels': _channels.toList()..sort(),
      'recipients': _channels.contains('email') ? _recipients : <String>[],
      'enabled': _enabled,
    });
  }
}

Map<String, Object?> _alertValues(
  AnalyticsAlert alert, {
  required bool enabled,
}) => {
  'name': alert.name,
  'metric': alert.metric,
  'direction': alert.direction,
  'baseline': alert.baseline,
  'thresholdPercent': alert.thresholdPercent,
  'localTime': alert.localTime,
  'channels': alert.channels,
  'recipients': alert.recipients,
  'enabled': enabled,
};

String _metricLabel(String metric) => switch (metric) {
  'visitors' => 'Unique visitors',
  'sessions' => 'Sessions',
  'page_views' => 'Page views',
  'bounce_rate' => 'Bounce rate',
  _ => metric,
};

String _channelLabel(String channel) => switch (channel) {
  'email' => 'Email',
  'slack' => 'Slack',
  'teams' => 'Microsoft Teams',
  _ => channel,
};

String _channelLabelZh(String channel) => switch (channel) {
  'email' => '邮件',
  'slack' => 'Slack',
  'teams' => 'Microsoft Teams',
  _ => channel,
};

IconData _channelIcon(String channel) => switch (channel) {
  'email' => Icons.email_outlined,
  'slack' => Icons.forum_outlined,
  _ => Icons.groups_outlined,
};

String _time(String value) => value.length >= 5 ? value.substring(0, 5) : value;
