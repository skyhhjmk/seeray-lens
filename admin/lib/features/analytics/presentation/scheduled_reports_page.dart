import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_i18n.dart';
import '../../../shared/presentation/page_help_button.dart';
import '../../../shared/presentation/site_top_bar.dart';
import '../application/scheduled_reports.dart';

class ScheduledReportsPage extends ConsumerStatefulWidget {
  const ScheduledReportsPage({
    required this.siteId,
    this.embedded = false,
    super.key,
  });

  final String siteId;
  final bool embedded;

  @override
  ConsumerState<ScheduledReportsPage> createState() =>
      _ScheduledReportsPageState();
}

class _ScheduledReportsPageState extends ConsumerState<ScheduledReportsPage> {
  bool _busy = false;
  String? _actionError;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(scheduledReportsProvider(widget.siteId));
    return Scaffold(
      backgroundColor: const Color(0xfff3f5f8),
      appBar: widget.embedded
          ? null
          : SiteTopBar(
              siteId: widget.siteId,
              selected: SiteTopTab.scheduledReports,
              help: const PageHelpButton(
                englishTitle: 'Scheduled reports',
                chineseTitle: '定期报表说明',
                englishBody:
                    'Send completed weekly or monthly analytics periods to selected recipients. Delivery uses the server SMTP settings and site timezone.',
                chineseBody: '按周或按月将已完成周期的分析报告发送给指定收件人。投递使用服务器 SMTP 配置和站点时区。',
              ),
              onRefresh: _busy ? null : () => _reload(),
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
                          context.tr('Scheduled reports', '定期报表'),
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          context.tr(
                            'Deliver weekly or monthly analytics by email. All schedules use the site timezone: ${value.timezone}.',
                            '通过邮件发送每周或每月分析报告。所有计划均使用站点时区：${value.timezone}。',
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (value.canManage)
                    FilledButton.icon(
                      onPressed: _busy ? null : () => _edit(value),
                      icon: const Icon(Icons.add),
                      label: Text(context.tr('New report', '新建报表')),
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
              if (value.reports.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(30),
                    child: Column(
                      children: [
                        const Icon(Icons.mark_email_read_outlined, size: 42),
                        const SizedBox(height: 12),
                        Text(
                          context.tr('No scheduled reports yet.', '暂无定期报表。'),
                        ),
                        if (value.canManage) ...[
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: _busy ? null : () => _edit(value),
                            icon: const Icon(Icons.add),
                            label: Text(context.tr('Create a report', '创建报表')),
                          ),
                        ],
                      ],
                    ),
                  ),
                )
              else
                ...value.reports.map((report) => _reportCard(report, value)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _deliveryCard(ScheduledReportsState state) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            state.emailEnabled ? Icons.mark_email_read : Icons.mail_outline,
            color: state.emailEnabled
                ? Colors.green.shade700
                : Colors.orange.shade800,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  state.emailEnabled
                      ? context.tr('Email delivery is enabled', '邮件投递已启用')
                      : context.tr(
                          'Email delivery is not configured',
                          '尚未配置邮件投递',
                        ),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  state.emailEnabled
                      ? context.tr(
                          'Reports will be sent by the server mail service. SMTP credentials are managed by the server administrator.',
                          '报表将通过服务器邮件服务发送。SMTP 凭据由服务器管理员管理。',
                        )
                      : context.tr(
                          'An administrator must set SEERAY_REPORTS_EMAIL_ENABLED=true and configure SEERAY_SMTP_HOST, SEERAY_SMTP_PORT, SEERAY_SMTP_FROM and the server-side SMTP credentials. No SMTP password is entered here.',
                          '管理员需要设置 SEERAY_REPORTS_EMAIL_ENABLED=true，并配置 SEERAY_SMTP_HOST、SEERAY_SMTP_PORT、SEERAY_SMTP_FROM 和服务器端 SMTP 凭据。此页面不会收集 SMTP 密码。',
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _reportCard(
    ScheduledAnalyticsReport report,
    ScheduledReportsState state,
  ) {
    final when = report.frequency == 'weekly'
        ? context.tr(
            'Every ${_weekday(report.weekday)} at ${_time(report.localTime)}',
            '每周${_weekdayZh(report.weekday)} ${_time(report.localTime)}',
          )
        : context.tr(
            'Day ${report.monthDay} of each month at ${_time(report.localTime)}',
            '每月 ${report.monthDay} 日 ${_time(report.localTime)}',
          );
    final next = report.nextRunLocal == null
        ? context.tr('No next delivery', '暂无下次投递时间')
        : context.tr(
            'Next: ${report.nextRunLocal} · ${report.timezone}',
            '下次：${report.nextRunLocal} · ${report.timezone}',
          );
    final last = report.lastRunLocal == null
        ? context.tr('Never sent', '尚未发送')
        : context.tr(
            'Last ${report.lastRunStatus == 'sent' ? 'sent' : 'failed'} ${report.lastRunLocal} · ${report.timezone} · ${report.lastRunPeriod ?? ''}',
            '最近${report.lastRunStatus == 'sent' ? '成功' : '失败'} ${report.lastRunLocal} · ${report.timezone} · ${report.lastRunPeriod ?? ''}',
          );
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
                    report.name,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                Chip(
                  avatar: Icon(
                    report.enabled
                        ? Icons.schedule
                        : Icons.pause_circle_outline,
                    size: 16,
                  ),
                  label: Text(
                    report.enabled
                        ? context.tr('Active', '运行中')
                        : context.tr('Paused', '已暂停'),
                  ),
                ),
                if (state.canManage)
                  PopupMenuButton<String>(
                    tooltip: context.tr('Report actions', '报表操作'),
                    onSelected: (action) => switch (action) {
                      'edit' => _edit(state, report: report),
                      'send' => _sendNow(report),
                      'toggle' => _toggle(state, report),
                      'delete' => _delete(report),
                      _ => null,
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'edit',
                        child: Text(context.tr('Edit', '编辑')),
                      ),
                      PopupMenuItem(
                        value: 'send',
                        child: Text(context.tr('Send now', '立即发送')),
                      ),
                      PopupMenuItem(
                        value: 'toggle',
                        child: Text(
                          report.enabled
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
            const SizedBox(height: 4),
            Text('$when · ${report.timezone}'),
            if (report.timezone != state.timezone)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  context.tr(
                    'This schedule retains its saved timezone. Edit it to use the current site timezone (${state.timezone}).',
                    '此计划仍使用保存时的时区。编辑并保存即可切换为当前站点时区（${state.timezone}）。',
                  ),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: -8,
              children: [
                for (final recipient in report.recipients)
                  Chip(
                    avatar: const Icon(Icons.email_outlined, size: 14),
                    label: Text(recipient),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${context.tr('Sections', '报表内容')}: ${report.sections.map((section) => _sectionName(section)).join(' · ')}',
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 16,
              runSpacing: 4,
              children: [
                Text(next, style: Theme.of(context).textTheme.bodySmall),
                Text(last, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
            if (report.lastRunStatus == 'failed' &&
                report.lastRunMessage != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  report.lastRunMessage!,
                  style: TextStyle(color: Colors.red.shade700),
                ),
              ),
            if (!state.emailEnabled && report.enabled)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  context.tr(
                    'Delivery is currently blocked by server email settings.',
                    '当前服务器邮件设置阻止投递。',
                  ),
                  style: TextStyle(color: Colors.orange.shade900),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _error(String message) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 36),
          const SizedBox(height: 12),
          Text(context.tr('Could not load scheduled reports', '无法加载定期报表')),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: _reload,
            child: Text(context.tr('Retry', '重试')),
          ),
        ],
      ),
    ),
  );

  Future<void> _edit(
    ScheduledReportsState state, {
    ScheduledAnalyticsReport? report,
  }) async {
    final values = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (_) => _ScheduledReportEditor(
        report: report,
        timezone: state.timezone,
        emailEnabled: state.emailEnabled,
      ),
    );
    if (values == null || !mounted) return;
    await _mutate(
      () => ref
          .read(scheduledReportsRepositoryProvider)
          .save(siteId: widget.siteId, reportId: report?.id, values: values),
    );
  }

  Future<void> _toggle(
    ScheduledReportsState state,
    ScheduledAnalyticsReport report,
  ) => _mutate(
    () => ref
        .read(scheduledReportsRepositoryProvider)
        .save(
          siteId: widget.siteId,
          reportId: report.id,
          values: _reportValues(report, enabled: !report.enabled),
        ),
  );

  Future<void> _sendNow(ScheduledAnalyticsReport report) async {
    if (!await _confirm(
      context.tr(
        'Send this report to all configured recipients now?',
        '现在立即向所有配置的收件人发送此报表？',
      ),
    )) {
      return;
    }
    await _mutate(
      () => ref
          .read(scheduledReportsRepositoryProvider)
          .sendNow(widget.siteId, report.id),
    );
  }

  Future<void> _delete(ScheduledAnalyticsReport report) async {
    if (!await _confirm(
      context.tr('Delete “${report.name}”?', '删除“${report.name}”？'),
    )) {
      return;
    }
    await _mutate(
      () => ref
          .read(scheduledReportsRepositoryProvider)
          .delete(widget.siteId, report.id),
    );
  }

  Future<bool> _confirm(String question) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          content: Text(question),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.tr('Cancel', '取消')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(context.tr('Continue', '继续')),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _mutate(Future<Object?> Function() action) async {
    setState(() {
      _busy = true;
      _actionError = null;
    });
    try {
      await action();
      ref.invalidate(scheduledReportsProvider(widget.siteId));
    } catch (error) {
      if (mounted) setState(() => _actionError = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reload() async =>
      ref.invalidate(scheduledReportsProvider(widget.siteId));

  Map<String, Object?> _reportValues(
    ScheduledAnalyticsReport report, {
    required bool enabled,
  }) => {
    'name': report.name,
    'frequency': report.frequency,
    'weekday': report.weekday,
    'monthDay': report.monthDay,
    'localTime': _timeWithSeconds(report.localTime),
    'recipients': report.recipients,
    'sections': report.sections,
    'enabled': enabled,
  };

  String _weekday(String? value) => switch (value) {
    'MON' => context.tr('Monday', '周一'),
    'TUE' => context.tr('Tuesday', '周二'),
    'WED' => context.tr('Wednesday', '周三'),
    'THU' => context.tr('Thursday', '周四'),
    'FRI' => context.tr('Friday', '周五'),
    'SAT' => context.tr('Saturday', '周六'),
    'SUN' => context.tr('Sunday', '周日'),
    _ => value ?? '',
  };

  String _weekdayZh(String? value) => switch (value) {
    'MON' => '一',
    'TUE' => '二',
    'WED' => '三',
    'THU' => '四',
    'FRI' => '五',
    'SAT' => '六',
    'SUN' => '日',
    _ => '',
  };

  String _time(String value) =>
      value.length >= 5 ? value.substring(0, 5) : value;
  String _timeWithSeconds(String value) =>
      value.length == 5 ? '$value:00' : value;
  String _sectionName(String value) => switch (value) {
    'overview' => context.tr('Overview', '概览'),
    'pages' => context.tr('Top pages', '热门页面'),
    'acquisition' => context.tr('Acquisition', '流量来源'),
    _ => value,
  };
}

class _ScheduledReportEditor extends StatefulWidget {
  const _ScheduledReportEditor({
    required this.timezone,
    required this.emailEnabled,
    this.report,
  });

  final String timezone;
  final bool emailEnabled;
  final ScheduledAnalyticsReport? report;

  @override
  State<_ScheduledReportEditor> createState() => _ScheduledReportEditorState();
}

class _ScheduledReportEditorState extends State<_ScheduledReportEditor> {
  late final _name = TextEditingController(text: widget.report?.name ?? '');
  late final _recipient = TextEditingController();
  late final List<String> _recipients = [...?widget.report?.recipients];
  late final Set<String> _sections = {...?widget.report?.sections};
  late String _frequency = widget.report?.frequency ?? 'weekly';
  late String _weekday = widget.report?.weekday ?? 'MON';
  late int _monthDay = widget.report?.monthDay ?? 1;
  late TimeOfDay _time = _parseTime(widget.report?.localTime);
  late bool _enabled = widget.report?.enabled ?? false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _recipient.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.report == null
          ? context.tr('Create scheduled report', '创建定期报表')
          : context.tr('Edit scheduled report', '编辑定期报表'),
    ),
    content: SizedBox(
      width: 520,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _name,
              maxLength: 120,
              decoration: InputDecoration(
                labelText: context.tr('Report name', '报表名称'),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              context.tr('Recipients (up to 10)', '收件人（最多 10 个）'),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              children: [
                for (final email in _recipients)
                  InputChip(
                    label: Text(email),
                    onDeleted: () => setState(() => _recipients.remove(email)),
                  ),
              ],
            ),
            TextField(
              controller: _recipient,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                labelText: context.tr('Add an email address', '添加邮箱地址'),
                helperText: context.tr(
                  'Press Enter to add; repeated addresses are ignored.',
                  '按回车添加，重复邮箱会被忽略。',
                ),
                suffixIcon: IconButton(
                  tooltip: context.tr('Add recipient', '添加收件人'),
                  onPressed: _addRecipients,
                  icon: const Icon(Icons.add),
                ),
              ),
              onSubmitted: (_) => _addRecipients(),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _frequency,
              decoration: InputDecoration(
                labelText: context.tr('Frequency', '频率'),
              ),
              items: [
                DropdownMenuItem(
                  value: 'weekly',
                  child: Text(context.tr('Weekly', '每周')),
                ),
                DropdownMenuItem(
                  value: 'monthly',
                  child: Text(context.tr('Monthly', '每月')),
                ),
              ],
              onChanged: (value) =>
                  setState(() => _frequency = value ?? 'weekly'),
            ),
            const SizedBox(height: 8),
            if (_frequency == 'weekly')
              DropdownButtonFormField<String>(
                initialValue: _weekday,
                decoration: InputDecoration(
                  labelText: context.tr('Day of week', '星期'),
                ),
                items: [
                  for (final entry in const {
                    'MON': 'Monday',
                    'TUE': 'Tuesday',
                    'WED': 'Wednesday',
                    'THU': 'Thursday',
                    'FRI': 'Friday',
                    'SAT': 'Saturday',
                    'SUN': 'Sunday',
                  }.entries)
                    DropdownMenuItem(
                      value: entry.key,
                      child: Text(
                        context.tr(
                          entry.value,
                          '周${_weekdayChinese(entry.key)}',
                        ),
                      ),
                    ),
                ],
                onChanged: (value) => setState(() => _weekday = value ?? 'MON'),
              )
            else
              DropdownButtonFormField<int>(
                initialValue: _monthDay,
                decoration: InputDecoration(
                  labelText: context.tr('Day of month', '每月日期'),
                ),
                items: [
                  for (var day = 1; day <= 28; day++)
                    DropdownMenuItem(value: day, child: Text('$day')),
                ],
                onChanged: (value) => setState(() => _monthDay = value ?? 1),
              ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(context.tr('Delivery time', '发送时间')),
              subtitle: Text('${_time.format(context)} · ${widget.timezone}'),
              trailing: const Icon(Icons.access_time),
              onTap: () async {
                final selected = await showTimePicker(
                  context: context,
                  initialTime: _time,
                );
                if (selected != null) setState(() => _time = selected);
              },
            ),
            const Divider(),
            Text(
              context.tr('Include report sections', '包含报表栏目'),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            for (final section in const ['overview', 'pages', 'acquisition'])
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(switch (section) {
                  'overview' => context.tr(
                    'Overview (visitors, sessions, page views)',
                    '概览（访客、会话、浏览量）',
                  ),
                  'pages' => context.tr('Top pages', '热门页面'),
                  _ => context.tr('Acquisition sources', '流量来源'),
                }),
                value: _sections.contains(section),
                onChanged: (checked) => setState(() {
                  if (checked == true) {
                    _sections.add(section);
                  } else {
                    _sections.remove(section);
                  }
                }),
              ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(context.tr('Schedule active', '启用计划')),
              subtitle: widget.emailEnabled
                  ? null
                  : Text(
                      context.tr(
                        'Server email delivery is disabled; the schedule cannot be activated yet.',
                        '服务器邮件投递未启用，暂时无法激活计划。',
                      ),
                    ),
              value: _enabled,
              onChanged: widget.emailEnabled
                  ? (value) => setState(() => _enabled = value)
                  : null,
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
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

  void _addRecipients() {
    final values = _recipient.text
        .split(RegExp(r'[,;\s]+'))
        .map((value) => value.trim().toLowerCase())
        .where((value) => value.isNotEmpty);
    setState(() {
      for (final value in values) {
        if (!_recipients.contains(value)) _recipients.add(value);
      }
      _recipient.clear();
    });
  }

  void _save() {
    if (_recipient.text.trim().isNotEmpty) _addRecipients();
    if (_name.text.trim().isEmpty || _recipients.isEmpty || _sections.isEmpty) {
      setState(
        () => _error = context.tr(
          'Add a name, at least one recipient, and one report section.',
          '请填写名称、至少一个收件人和一个报表栏目。',
        ),
      );
      return;
    }
    Navigator.pop<Map<String, Object?>>(context, {
      'name': _name.text.trim(),
      'frequency': _frequency,
      'weekday': _frequency == 'weekly' ? _weekday : null,
      'monthDay': _frequency == 'monthly' ? _monthDay : null,
      'localTime':
          '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}:00',
      'recipients': List<String>.unmodifiable(_recipients),
      'sections': _sections.toList()..sort(),
      'enabled': _enabled,
    });
  }

  TimeOfDay _parseTime(String? value) {
    final parts = (value ?? '09:00').split(':');
    return TimeOfDay(
      hour: int.tryParse(parts.first) ?? 9,
      minute: parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0,
    );
  }

  String _weekdayChinese(String day) => switch (day) {
    'MON' => '一',
    'TUE' => '二',
    'WED' => '三',
    'THU' => '四',
    'FRI' => '五',
    'SAT' => '六',
    'SUN' => '日',
    _ => day,
  };
}
