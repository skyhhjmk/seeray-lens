import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/i18n/app_i18n.dart';
import '../../../shared/presentation/page_help_button.dart';
import '../../../shared/presentation/site_top_bar.dart';
import '../application/analytics_controller.dart';
import '../application/analytics_export.dart';
import '../application/analytics_range.dart';
import '../application/bing_webmaster.dart';

class BingWebmasterPage extends ConsumerStatefulWidget {
  const BingWebmasterPage({
    required this.siteId,
    this.embedded = false,
    super.key,
  });

  final String siteId;
  final bool embedded;

  @override
  ConsumerState<BingWebmasterPage> createState() => _BingWebmasterPageState();
}

class _BingWebmasterPageState extends ConsumerState<BingWebmasterPage> {
  final _siteUrlController = TextEditingController();
  final _apiKeyController = TextEditingController();
  String _dimension = 'query';
  bool _siteUrlDirty = false;
  bool _ready = false;
  bool _saving = false;
  bool _checking = false;
  BingWebmasterValidation? _validation;
  String? _actionError;

  @override
  void initState() {
    super.initState();
    _siteUrlController.addListener(() => _siteUrlDirty = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final range = ref.read(analyticsRangeProvider(widget.siteId));
      final safeEnd = analyticsDateOnly(
        DateTime.now(),
      ).subtract(const Duration(days: 3));
      if (range.period == AnalyticsPeriod.realtime ||
          range.range.to.isAfter(safeEnd)) {
        final end = safeEnd;
        final start = end.subtract(const Duration(days: 27));
        ref
            .read(analyticsRangeProvider(widget.siteId).notifier)
            .setRange(
              AnalyticsRangeState(
                period: AnalyticsPeriod.custom,
                range: AnalyticsDateRange(start, end),
              ),
            );
      }
      setState(() => _ready = true);
    });
  }

  @override
  void dispose() {
    _siteUrlController.dispose();
    _apiKeyController.dispose();
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
    final property = ref.watch(bingWebmasterPropertyProvider(widget.siteId));
    ref.listen(bingWebmasterPropertyProvider(widget.siteId), (previous, next) {
      next.whenData((value) {
        if (!_siteUrlDirty && _siteUrlController.text != value.siteUrl) {
          _siteUrlController.text = value.siteUrl ?? '';
        }
      });
    });
    final query = BingWebmasterReportQuery(
      siteId: widget.siteId,
      range: range.range,
      dimension: _dimension,
    );
    final report = ref.watch(bingWebmasterReportProvider(query));
    return Scaffold(
      backgroundColor: const Color(0xfff3f5f8),
      appBar: widget.embedded
          ? null
          : SiteTopBar(
              siteId: widget.siteId,
              selected: SiteTopTab.acquisition,
              help: const PageHelpButton(
                englishTitle: 'Bing Webmaster Tools',
                chineseTitle: 'Bing Webmaster Tools 必应站长工具',
                englishBody:
                    'View Bing organic-search clicks, impressions and CTR by query, page or date. Query and page details are updated weekly and may contain only Bing’s top rows. The API key is encrypted on the SeeRay server.',
                chineseBody:
                    '按搜索词、网页或日期查看 Bing 自然搜索点击、曝光和点击率。搜索词和网页明细按周更新，且可能仅包含 Bing 返回的热门结果。API 密钥在 SeeRay 服务端加密保存。',
              ),
              rangeState: range,
              onSelectRange: () async {
                final selected = await showAnalyticsRangePicker(
                  context,
                  range,
                  maximumRangeDays: 184,
                );
                if (selected != null && context.mounted) {
                  ref
                      .read(analyticsRangeProvider(widget.siteId).notifier)
                      .setRange(selected);
                }
              },
              onRefresh: () {
                ref.invalidate(bingWebmasterPropertyProvider(widget.siteId));
                ref.invalidate(bingWebmasterReportProvider(query));
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
    BingWebmasterProperty property,
    AsyncValue<BingWebmasterReport> report,
    BingWebmasterReportQuery query,
    AnalyticsRangeState range,
  ) => RefreshIndicator(
    onRefresh: () async {
      ref.invalidate(bingWebmasterPropertyProvider(widget.siteId));
      ref.invalidate(bingWebmasterReportProvider(query));
      await ref.read(bingWebmasterPropertyProvider(widget.siteId).future);
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
                      'Bing organic search performance',
                      'Bing 自然搜索表现',
                    ),
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 5),
                  Text(
                    context.tr(
                      'Connect a verified Bing Webmaster site to compare external search discovery with SeeRay onsite analytics.',
                      '连接已验证的 Bing Webmaster 站点，将外部搜索发现与 SeeRay 站内分析并列查看。',
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

  Widget _connectionCard(BingWebmasterProperty property) {
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
                  context.tr('Bing site connection', 'Bing 站点连接'),
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
                'Use the exact URL shown in Bing Webmaster Tools (for example https://www.example.com/). API keys belong to a Bing user and can access that user’s other sites, so use a dedicated, trusted account and configure a separate key for each SeeRay site.',
                '填写 Bing Webmaster Tools 中显示的准确站点 URL（例如 https://www.example.com/）。API 密钥属于 Bing 用户，也能访问该用户的其他站点；建议使用专用可信账号，并为每个 SeeRay 站点单独配置密钥。',
              ),
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
                        labelText: context.tr('Bing site URL', 'Bing 站点 URL'),
                        hintText: 'https://www.example.com/',
                        prefixIcon: const Icon(Icons.travel_explore),
                        border: const OutlineInputBorder(),
                        counterText: '',
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 340,
                    child: TextField(
                      controller: _apiKeyController,
                      maxLength: 4096,
                      obscureText: true,
                      enableSuggestions: false,
                      autocorrect: false,
                      decoration: InputDecoration(
                        labelText: property.credentialConfigured
                            ? context.tr(
                                'Replace API key (optional)',
                                '替换 API 密钥（可选）',
                              )
                            : context.tr('Bing API key', 'Bing API 密钥'),
                        hintText: property.credentialConfigured
                            ? context.tr(
                                'Leave blank to keep the saved key',
                                '留空则保留已保存密钥',
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
                        : const Icon(Icons.save_outlined),
                    label: Text(context.tr('Save connection', '保存连接')),
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
                'The API key is encrypted at rest on the server and is never returned to this page. The server needs SEERAY_SECRET_ENCRYPTION_KEY set to a stable base64-encoded 32-byte key. Query/page data is weekly; country and device dimensions are not exposed by these API methods.',
                'API 密钥在服务端加密保存，不会回传到页面。服务端必须配置稳定的 base64 32 字节 SEERAY_SECRET_ENCRYPTION_KEY。搜索词/网页数据按周更新；这些 API 方法不提供国家/设备维度。',
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _reportContent(
    AsyncValue<BingWebmasterReport> report,
    BingWebmasterReportQuery query,
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
                'Bing Webmaster report unavailable',
                'Bing Webmaster 报表暂不可用',
              ),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              context.tr(
                'Check the API key, exact site URL, verification status and server encryption-key configuration.',
                '请检查 API 密钥、准确站点 URL、验证状态及服务端加密密钥配置。',
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () =>
                  ref.invalidate(bingWebmasterReportProvider(query)),
              icon: const Icon(Icons.refresh),
              label: Text(context.tr('Retry', '重试')),
            ),
          ],
        ),
      ),
    ),
    data: (data) => _reportCard(data, query, range),
  );

  Widget _reportCard(
    BingWebmasterReport report,
    BingWebmasterReportQuery query,
    AnalyticsRangeState range,
  ) {
    final labels = <String, String>{
      'query': context.tr('Search queries', '搜索词'),
      'page': context.tr('Pages', '网页'),
      'date': context.tr('Daily trend', '每日趋势'),
    };
    final keyLabel = switch (_dimension) {
      'query' => context.tr('Search query', '搜索词'),
      'page' => context.tr('Page URL', '网页 URL'),
      _ => context.tr('Date', '日期'),
    };
    return Card(
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
                      labels[_dimension]!,
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
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final dimension in bingWebmasterDimensions)
                  ChoiceChip(
                    label: Text(labels[dimension]!),
                    selected: _dimension == dimension,
                    onSelected: (_) => setState(() => _dimension = dimension),
                  ),
              ],
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
              ],
            ),
            if (report.mayBeTruncated || report.dataLimitNote.isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(report.dataLimitNote),
              ),
            ],
            const SizedBox(height: 12),
            if (report.rows.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    context.tr(
                      'No Bing Webmaster rows were returned for this period.',
                      '该日期范围内没有返回 Bing Webmaster 明细。',
                    ),
                  ),
                ),
              )
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: [
                    DataColumn(label: Text(keyLabel)),
                    DataColumn(
                      label: Text(context.tr('Clicks', '点击')),
                      numeric: true,
                    ),
                    DataColumn(
                      label: Text(context.tr('Impressions', '曝光')),
                      numeric: true,
                    ),
                    DataColumn(label: const Text('CTR'), numeric: true),
                    if (_dimension != 'date')
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
                              child: SelectableText(row.key),
                            ),
                          ),
                          DataCell(Text(_number(row.clicks))),
                          DataCell(Text(_number(row.impressions))),
                          DataCell(
                            Text('${(row.ctr * 100).toStringAsFixed(2)}%'),
                          ),
                          if (_dimension != 'date')
                            DataCell(
                              Text(row.averagePosition.toStringAsFixed(1)),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _actionError = null;
      _validation = null;
    });
    try {
      await BingWebmasterRepository(ref).saveProperty(
        widget.siteId,
        _siteUrlController.text.trim(),
        _apiKeyController.text.trim(),
      );
      _apiKeyController.clear();
      _siteUrlDirty = false;
      ref.invalidate(bingWebmasterPropertyProvider(widget.siteId));
      ref.invalidate(bingWebmasterReportProvider);
      if (mounted) _snack(context.tr('Connection saved.', '连接已保存。'));
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
      final result = await BingWebmasterRepository(ref).validate(widget.siteId);
      if (mounted) setState(() => _validation = result);
    } catch (error) {
      if (mounted) setState(() => _actionError = _apiMessage(error));
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _delete(BingWebmasterProperty property) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.tr('Remove Bing connection?', '移除 Bing 连接？')),
        content: Text(
          context.tr(
            'This permanently removes the saved Bing site URL and encrypted API key for this SeeRay site.',
            '这会永久删除当前 SeeRay 站点保存的 Bing URL 和加密 API 密钥。',
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
      await BingWebmasterRepository(ref).deleteProperty(widget.siteId);
      _siteUrlController.clear();
      _apiKeyController.clear();
      _siteUrlDirty = false;
      ref.invalidate(bingWebmasterPropertyProvider(widget.siteId));
      ref.invalidate(bingWebmasterReportProvider);
      if (mounted) _snack(context.tr('Connection removed.', '连接已移除。'));
    } catch (error) {
      if (mounted) setState(() => _actionError = _apiMessage(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _exportCsv(
    BingWebmasterReport report,
    AnalyticsRangeState range,
  ) async {
    final includePosition = _dimension != 'date';
    final csv = AnalyticsReportExport.csv(
      includePosition
          ? const [
              'dimension',
              'clicks',
              'impressions',
              'ctr',
              'average_position',
            ]
          : const ['date', 'clicks', 'impressions', 'ctr'],
      report.rows
          .map(
            (row) => <Object?>[
              row.key,
              row.clicks,
              row.impressions,
              row.ctr,
              if (includePosition) row.averagePosition,
            ],
          )
          .toList(growable: false),
    );
    final result = await FilePicker.platform.saveFile(
      dialogTitle: context.tr(
        'Export Bing Webmaster rows',
        '导出 Bing Webmaster 明细',
      ),
      fileName:
          'seeray-bing-webmaster-$_dimension-${range.range.fromQuery}-${range.range.toQuery}.csv',
      allowedExtensions: const ['csv'],
      bytes: Uint8List.fromList(utf8.encode(csv)),
    );
    if (result != null && mounted) {
      _snack(context.tr('CSV exported.', 'CSV 已导出。'));
    }
  }

  Widget _loadError(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          context.tr(
            'Could not load Bing Webmaster settings.',
            '无法加载 Bing Webmaster 设置。',
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () =>
              ref.invalidate(bingWebmasterPropertyProvider(widget.siteId)),
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
