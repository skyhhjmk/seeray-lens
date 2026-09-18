import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/i18n/app_i18n.dart';
import '../../../shared/presentation/page_help_button.dart';
import '../../../shared/presentation/site_top_bar.dart';
import '../application/analytics_controller.dart';
import '../application/analytics_export.dart';
import '../application/analytics_range.dart';
import '../application/yandex_webmaster.dart';

class YandexWebmasterPage extends ConsumerStatefulWidget {
  const YandexWebmasterPage({
    required this.siteId,
    this.embedded = false,
    super.key,
  });

  final String siteId;
  final bool embedded;

  @override
  ConsumerState<YandexWebmasterPage> createState() =>
      _YandexWebmasterPageState();
}

class _YandexWebmasterPageState extends ConsumerState<YandexWebmasterPage> {
  final _siteUrlController = TextEditingController();
  final _clientIdController = TextEditingController();
  final _oauthTokenController = TextEditingController();
  String _deviceType = 'ALL';
  bool _siteUrlDirty = false;
  bool _ready = false;
  bool _saving = false;
  bool _checking = false;
  YandexWebmasterValidation? _validation;
  String? _actionError;

  @override
  void initState() {
    super.initState();
    _siteUrlController.addListener(() => _siteUrlDirty = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final range = ref.read(analyticsRangeProvider(widget.siteId));
      final today = analyticsDateOnly(DateTime.now());
      if (range.period == AnalyticsPeriod.realtime ||
          range.range.to.isAfter(today)) {
        ref
            .read(analyticsRangeProvider(widget.siteId).notifier)
            .setRange(
              AnalyticsRangeState(
                period: AnalyticsPeriod.custom,
                range: AnalyticsDateRange(
                  today.subtract(const Duration(days: 6)),
                  today,
                ),
              ),
            );
      }
      setState(() => _ready = true);
    });
  }

  @override
  void dispose() {
    _siteUrlController.dispose();
    _clientIdController.dispose();
    _oauthTokenController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final range = ref.watch(analyticsRangeProvider(widget.siteId));
    if (!_ready) {
      return const Scaffold(
        backgroundColor: Color(0xfff3f5f8),
        body: Center(child: CircularProgressIndicator()),
      );
    }
    final property = ref.watch(yandexWebmasterPropertyProvider(widget.siteId));
    ref.listen(yandexWebmasterPropertyProvider(widget.siteId), (
      previous,
      next,
    ) {
      next.whenData((value) {
        if (!_siteUrlDirty && _siteUrlController.text != value.siteUrl) {
          _siteUrlController.text = value.siteUrl ?? '';
        }
      });
    });
    final query = YandexWebmasterReportQuery(
      siteId: widget.siteId,
      range: range.range,
      deviceType: _deviceType,
    );
    final report = ref.watch(yandexWebmasterReportProvider(query));
    return Scaffold(
      backgroundColor: const Color(0xfff3f5f8),
      appBar: widget.embedded
          ? null
          : SiteTopBar(
              siteId: widget.siteId,
              selected: SiteTopTab.acquisition,
              help: const PageHelpButton(
                englishTitle: 'Yandex Webmaster',
                chineseTitle: 'Yandex Webmaster 搜索表现',
                englishBody:
                    'Review Yandex search queries, clicks, impressions, CTR and average position. The official popular-queries API returns provider-ranked rows for the selected interval and device type; it does not return a daily trend or page breakdown.',
                chineseBody:
                    '查看 Yandex 搜索词、点击、曝光、点击率和平均排名。官方热门查询 API 按所选日期范围和设备返回排序结果；不提供每日趋势或页面明细。',
              ),
              rangeState: range,
              onSelectRange: () async {
                final selected = await showAnalyticsRangePicker(
                  context,
                  range,
                  maximumRangeDays: 366,
                );
                if (selected != null && context.mounted) {
                  ref
                      .read(analyticsRangeProvider(widget.siteId).notifier)
                      .setRange(selected);
                }
              },
              onRefresh: () {
                ref.invalidate(yandexWebmasterPropertyProvider(widget.siteId));
                ref.invalidate(yandexWebmasterReportProvider(query));
              },
            ),
      body: property.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => _loadError(context),
        data: (configured) => _buildContent(configured, report, query, range),
      ),
    );
  }

  Widget _buildContent(
    YandexWebmasterProperty property,
    AsyncValue<YandexWebmasterReport> report,
    YandexWebmasterReportQuery query,
    AnalyticsRangeState range,
  ) => RefreshIndicator(
    onRefresh: () async {
      ref.invalidate(yandexWebmasterPropertyProvider(widget.siteId));
      ref.invalidate(yandexWebmasterReportProvider(query));
      await ref.read(yandexWebmasterPropertyProvider(widget.siteId).future);
    },
    child: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 16,
          runSpacing: 12,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 700),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.tr(
                      'Yandex organic search performance',
                      'Yandex 自然搜索表现',
                    ),
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 5),
                  Text(
                    context.tr(
                      'Connect a verified Yandex Webmaster site to review search discovery alongside SeeRay onsite acquisition.',
                      '连接已验证的 Yandex Webmaster 站点，与 SeeRay 站内获客数据一起查看搜索发现情况。',
                    ),
                  ),
                ],
              ),
            ),
            OutlinedButton.icon(
              onPressed: () =>
                  context.go('/sites/${widget.siteId}/acquisition'),
              icon: const Icon(Icons.arrow_back),
              label: Text(context.tr('Acquisition reports', '流量获取报表')),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _connectionCard(property),
        if (property.configured) ...[
          const SizedBox(height: 16),
          _reportContent(report, query, range),
        ],
      ],
    ),
  );

  Widget _connectionCard(YandexWebmasterProperty property) {
    final color = _validation == null
        ? Theme.of(context).colorScheme.primary
        : _validation!.accessible && _validation!.verified
        ? Colors.green.shade700
        : Theme.of(context).colorScheme.error;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  context.tr('Yandex site connection', 'Yandex 站点连接'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Chip(
                  avatar: Icon(
                    _validation?.accessible == true &&
                            _validation?.verified == true
                        ? Icons.check_circle
                        : property.configured
                        ? Icons.link
                        : Icons.link_off,
                    size: 18,
                    color: color,
                  ),
                  label: Text(
                    _validation?.accessible == true &&
                            _validation?.verified == true
                        ? context.tr('Access verified', '已验证访问权限')
                        : property.configured
                        ? context.tr('Site configured', '已配置站点')
                        : context.tr('Not configured', '未配置'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              context.tr(
                'Create a Yandex OAuth application with Webmaster access, authorize the account that owns this verified property, then paste its OAuth token below. Yandex currently documents a six-month token lifetime.',
                '创建具有 Webmaster 权限的 Yandex OAuth 应用，并授权拥有此已验证站点的账号，然后将 OAuth 令牌粘贴到下方。Yandex 当前说明令牌有效期为六个月。',
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                TextButton.icon(
                  onPressed: () => _copy(
                    'https://yandex.com/dev/webmaster/doc/en/tasks/how-to-get-oauth',
                    context.tr('Copy setup guide URL', '复制接入指南地址'),
                  ),
                  icon: const Icon(Icons.menu_book_outlined),
                  label: Text(context.tr('OAuth setup guide', 'OAuth 配置指南')),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (property.canManage)
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 10,
                runSpacing: 10,
                children: [
                  SizedBox(
                    width: 520,
                    child: TextField(
                      controller: _siteUrlController,
                      maxLength: 2048,
                      decoration: InputDecoration(
                        labelText: context.tr(
                          'Yandex site URL',
                          'Yandex 站点 URL',
                        ),
                        hintText: 'https://www.example.com/',
                        prefixIcon: const Icon(Icons.travel_explore),
                        border: const OutlineInputBorder(),
                        counterText: '',
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 320,
                    child: TextField(
                      controller: _clientIdController,
                      maxLength: 256,
                      decoration: InputDecoration(
                        labelText: context.tr(
                          'Yandex OAuth client ID',
                          'Yandex OAuth 应用 Client ID',
                        ),
                        hintText: context.tr(
                          'Not stored by SeeRay',
                          'SeeRay 不会保存此值',
                        ),
                        prefixIcon: const Icon(Icons.app_registration_outlined),
                        border: const OutlineInputBorder(),
                        counterText: '',
                      ),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _copyAuthorizationLink,
                    icon: const Icon(Icons.link_outlined),
                    label: Text(
                      context.tr('Copy authorization link', '复制授权链接'),
                    ),
                  ),
                  SizedBox(
                    width: 360,
                    child: TextField(
                      controller: _oauthTokenController,
                      maxLength: 8192,
                      obscureText: true,
                      enableSuggestions: false,
                      autocorrect: false,
                      decoration: InputDecoration(
                        labelText: property.credentialConfigured
                            ? context.tr(
                                'Replace OAuth token (optional)',
                                '替换 OAuth 令牌（可选）',
                              )
                            : context.tr(
                                'Yandex OAuth token',
                                'Yandex OAuth 令牌',
                              ),
                        hintText: property.credentialConfigured
                            ? context.tr(
                                'Leave blank to keep the saved token',
                                '留空则保留已保存令牌',
                              )
                            : null,
                        prefixIcon: const Icon(Icons.key_outlined),
                        border: const OutlineInputBorder(),
                        counterText: '',
                      ),
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.verified_user_outlined),
                    label: Text(context.tr('Save & verify', '保存并验证')),
                  ),
                  OutlinedButton.icon(
                    onPressed: !property.configured || _checking || _saving
                        ? null
                        : _validate,
                    icon: _checking
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.verified_outlined),
                    label: Text(context.tr('Test access', '测试访问')),
                  ),
                  if (property.configured)
                    IconButton(
                      tooltip: context.tr('Remove connection', '移除连接'),
                      onPressed: _saving ? null : () => _delete(property),
                      icon: const Icon(Icons.delete_outline),
                    ),
                ],
              )
            else
              SelectableText(property.siteUrl ?? '—'),
            if (_validation != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(
                    _validation!.accessible && _validation!.verified
                        ? Icons.check_circle
                        : Icons.error_outline,
                    color: color,
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_validation!.message)),
                ],
              ),
            ],
            if (_actionError != null) ...[
              const SizedBox(height: 10),
              Text(
                _actionError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              context.tr(
                'The OAuth token is encrypted at rest on the SeeRay server and never returned to this page. Configure SEERAY_SECRET_ENCRYPTION_KEY before saving credentials. Tokens expire; replace them here after reauthorization. Saving also checks that the selected URL is an exact, verified site in the token owner’s account.',
                'OAuth 令牌在 SeeRay 服务端加密保存，不会回传到此页面。保存凭据前请配置 SEERAY_SECRET_ENCRYPTION_KEY。令牌会过期，可重新授权后在此替换。保存时也会检查此 URL 是否为令牌所属账号中的准确已验证站点。',
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _reportContent(
    AsyncValue<YandexWebmasterReport> report,
    YandexWebmasterReportQuery query,
    AnalyticsRangeState range,
  ) => report.when(
    loading: () => const Card(
      child: SizedBox(
        height: 180,
        child: Center(child: CircularProgressIndicator()),
      ),
    ),
    error: (error, stack) => Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.tr(
                'Yandex Webmaster report unavailable',
                'Yandex Webmaster 报表暂不可用',
              ),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              context.tr(
                'Reauthorize the token if expired, confirm that Yandex approved the OAuth app, and verify that this account still owns the site.',
                '如令牌过期请重新授权，并检查 Yandex OAuth 应用审批状态及该账号的站点管理权限。',
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () =>
                  ref.invalidate(yandexWebmasterReportProvider(query)),
              icon: const Icon(Icons.refresh),
              label: Text(context.tr('Retry', '重试')),
            ),
          ],
        ),
      ),
    ),
    data: (data) => _reportCard(data, range),
  );

  Widget _reportCard(
    YandexWebmasterReport report,
    AnalyticsRangeState range,
  ) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            runSpacing: 10,
            spacing: 16,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.tr('Popular search queries', '热门搜索词'),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 3),
                  Text('${report.from} – ${report.to} · ${report.siteUrl}'),
                ],
              ),
              OutlinedButton.icon(
                onPressed: () => _exportCsv(report, range),
                icon: const Icon(Icons.download_outlined),
                label: Text(context.tr('Export CSV', '导出 CSV')),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: 320,
            child: DropdownButtonFormField<String>(
              initialValue: _deviceType,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: context.tr('Device type', '设备类型'),
                border: const OutlineInputBorder(),
              ),
              items: [
                for (final type in yandexWebmasterDeviceTypes)
                  DropdownMenuItem(
                    value: type,
                    child: Text(_deviceLabel(type)),
                  ),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _deviceType = value);
              },
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _MetricCard(
                title: context.tr('Clicks', '点击'),
                value: _number(report.clicks),
                icon: Icons.ads_click,
              ),
              _MetricCard(
                title: context.tr('Impressions', '曝光'),
                value: _number(report.impressions),
                icon: Icons.visibility_outlined,
              ),
              _MetricCard(
                title: context.tr('Average CTR', '平均点击率'),
                value: '${(report.ctr * 100).toStringAsFixed(2)}%',
                icon: Icons.percent,
              ),
              _MetricCard(
                title: context.tr('Avg. position', '平均排名'),
                value: report.averagePosition.toStringAsFixed(1),
                icon: Icons.format_list_numbered,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '${report.dataLimitNote} ${context.tr('Rows returned', '返回条数')}: ${report.rows.length} / ${report.totalQueries}.',
            ),
          ),
          const SizedBox(height: 12),
          if (report.rows.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  context.tr(
                    'No Yandex search-query rows were returned for this period.',
                    '该日期范围内没有返回 Yandex 搜索词明细。',
                  ),
                ),
              ),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: [
                  DataColumn(label: Text(context.tr('Search query', '搜索词'))),
                  DataColumn(
                    label: Text(context.tr('Clicks', '点击')),
                    numeric: true,
                  ),
                  DataColumn(
                    label: Text(context.tr('Impressions', '曝光')),
                    numeric: true,
                  ),
                  DataColumn(label: const Text('CTR'), numeric: true),
                  DataColumn(
                    label: Text(context.tr('Avg. position', '平均排名')),
                    numeric: true,
                  ),
                ],
                rows: [
                  for (final row in report.rows)
                    DataRow(
                      cells: [
                        DataCell(
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 420),
                            child: SelectableText(row.query),
                          ),
                        ),
                        DataCell(Text(_number(row.clicks))),
                        DataCell(Text(_number(row.impressions))),
                        DataCell(
                          Text('${(row.ctr * 100).toStringAsFixed(2)}%'),
                        ),
                        DataCell(Text(row.averagePosition.toStringAsFixed(1))),
                      ],
                    ),
                ],
              ),
            ),
        ],
      ),
    ),
  );

  String _deviceLabel(String value) => switch (value) {
    'DESKTOP' => context.tr('Computers', '电脑'),
    'MOBILE_AND_TABLET' => context.tr('Mobile and tablet', '手机和平板'),
    'MOBILE' => context.tr('Mobile', '手机'),
    'TABLET' => context.tr('Tablet', '平板'),
    _ => context.tr('All devices', '全部设备'),
  };

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _actionError = null;
      _validation = null;
    });
    try {
      await YandexWebmasterRepository(ref).saveProperty(
        widget.siteId,
        _siteUrlController.text.trim(),
        _oauthTokenController.text.trim(),
      );
      _oauthTokenController.clear();
      _siteUrlDirty = false;
      ref.invalidate(yandexWebmasterPropertyProvider(widget.siteId));
      ref.invalidate(yandexWebmasterReportProvider);
      if (mounted) {
        _snack(context.tr('Connection saved and verified.', '连接已保存并验证。'));
      }
    } catch (error) {
      if (mounted) setState(() => _actionError = _apiMessage(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _validate() async {
    setState(() {
      _checking = true;
      _actionError = null;
      _validation = null;
    });
    try {
      final result = await YandexWebmasterRepository(
        ref,
      ).validate(widget.siteId);
      if (mounted) setState(() => _validation = result);
    } catch (error) {
      if (mounted) setState(() => _actionError = _apiMessage(error));
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _delete(YandexWebmasterProperty property) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.tr('Remove Yandex connection?', '移除 Yandex 连接？')),
        content: Text(
          context.tr(
            'This permanently removes the selected Yandex site and encrypted OAuth token from this SeeRay site.',
            '这会永久删除当前 SeeRay 站点保存的 Yandex 属性和加密 OAuth 令牌。',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.tr('Cancel', '取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.tr('Remove', '移除')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() {
      _saving = true;
      _actionError = null;
    });
    try {
      await YandexWebmasterRepository(ref).deleteProperty(widget.siteId);
      _siteUrlController.clear();
      _oauthTokenController.clear();
      _siteUrlDirty = false;
      ref.invalidate(yandexWebmasterPropertyProvider(widget.siteId));
      ref.invalidate(yandexWebmasterReportProvider);
      if (mounted) _snack(context.tr('Connection removed.', '连接已移除。'));
    } catch (error) {
      if (mounted) setState(() => _actionError = _apiMessage(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _exportCsv(
    YandexWebmasterReport report,
    AnalyticsRangeState range,
  ) async {
    final csv = AnalyticsReportExport.csv(
      const ['query', 'clicks', 'impressions', 'ctr', 'average_position'],
      report.rows
          .map(
            (row) => <Object?>[
              row.query,
              row.clicks,
              row.impressions,
              row.ctr,
              row.averagePosition,
            ],
          )
          .toList(growable: false),
    );
    final result = await FilePicker.platform.saveFile(
      dialogTitle: context.tr('Export Yandex search queries', '导出 Yandex 搜索词'),
      fileName:
          'seeray-yandex-webmaster-queries-${range.range.fromQuery}-${range.range.toQuery}.csv',
      allowedExtensions: const ['csv'],
      bytes: Uint8List.fromList(utf8.encode(csv)),
    );
    if (result != null && mounted) {
      _snack(context.tr('CSV exported.', 'CSV 已导出。'));
    }
  }

  Future<void> _copy(String value, String label) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (mounted) _snack(context.tr('$label copied.', '已复制$label。'));
  }

  Future<void> _copyAuthorizationLink() async {
    final clientId = _clientIdController.text.trim();
    if (clientId.isEmpty) {
      _snack(
        context.tr(
          'Enter the OAuth client ID first.',
          '请先填写 OAuth 应用 Client ID。',
        ),
      );
      return;
    }
    final authorizationUrl = Uri.https('oauth.yandex.com', '/authorize', {
      'response_type': 'token',
      'client_id': clientId,
    });
    await _copy(
      authorizationUrl.toString(),
      context.tr('Yandex authorization link', 'Yandex 授权链接'),
    );
  }

  Widget _loadError(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          context.tr(
            'Could not load Yandex Webmaster settings.',
            '无法加载 Yandex Webmaster 设置。',
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () =>
              ref.invalidate(yandexWebmasterPropertyProvider(widget.siteId)),
          icon: const Icon(Icons.refresh),
          label: Text(context.tr('Retry', '重试')),
        ),
      ],
    ),
  );

  void _snack(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.title,
    required this.value,
    required this.icon,
  });

  final String title;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 190,
    child: Card(
      margin: EdgeInsets.zero,
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 19, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 9),
            Text(title, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 3),
            Text(value, style: Theme.of(context).textTheme.titleLarge),
          ],
        ),
      ),
    ),
  );
}

String _number(double value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toStringAsFixed(1);

String _apiMessage(Object error) {
  final text = error.toString();
  final jsonMessage = RegExp(r'"message"\s*:\s*"([^"]+)"').firstMatch(text);
  if (jsonMessage != null) return jsonMessage.group(1)!;
  return text.replaceFirst(RegExp(r'^Exception: ?'), '');
}
