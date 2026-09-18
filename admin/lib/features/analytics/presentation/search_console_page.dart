import 'dart:convert';
import 'dart:math' as math;
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
import '../application/search_console.dart';

class SearchConsolePage extends ConsumerStatefulWidget {
  const SearchConsolePage({
    required this.siteId,
    this.embedded = false,
    super.key,
  });

  final String siteId;
  final bool embedded;

  @override
  ConsumerState<SearchConsolePage> createState() => _SearchConsolePageState();
}

class _SearchConsolePageState extends ConsumerState<SearchConsolePage> {
  final _propertyController = TextEditingController();
  String _dimension = 'query';
  bool _propertyDirty = false;
  bool _ready = false;
  bool _saving = false;
  bool _checking = false;
  SearchConsoleValidation? _validation;
  String? _actionError;

  @override
  void initState() {
    super.initState();
    _propertyController.addListener(() => _propertyDirty = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final range = ref.read(analyticsRangeProvider(widget.siteId));
      if (range.period == AnalyticsPeriod.realtime) {
        final end = analyticsDateOnly(
          DateTime.now(),
        ).subtract(const Duration(days: 3));
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
    _propertyController.dispose();
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
    final property = ref.watch(searchConsolePropertyProvider(widget.siteId));
    ref.listen(searchConsolePropertyProvider(widget.siteId), (previous, next) {
      next.whenData((value) {
        if (!_propertyDirty && _propertyController.text != value.propertyUrl) {
          _propertyController.text = value.propertyUrl ?? '';
        }
      });
    });
    final query = SearchConsoleReportQuery(
      siteId: widget.siteId,
      range: range.range,
      dimension: _dimension,
    );
    final report = ref.watch(searchConsoleReportProvider(query));
    return Scaffold(
      backgroundColor: const Color(0xfff3f5f8),
      appBar: widget.embedded
          ? null
          : SiteTopBar(
              siteId: widget.siteId,
              selected: SiteTopTab.acquisition,
              help: const PageHelpButton(
                englishTitle: 'Google Search Console',
                chineseTitle: 'Google Search Console 搜索表现',
                englishBody:
                    'Read Google organic-search clicks, impressions, CTR and average ranking by query, page, country, device or date. This page requires server-side Google Application Default Credentials granted to the saved Search Console property.',
                chineseBody:
                    '按搜索词、网页、国家/地区、设备或日期查看 Google 自然搜索点击、曝光、点击率和平均排名。需要服务端 Google ADC 身份获得已配置 Search Console 属性的读取权限。',
              ),
              rangeState: range,
              onSelectRange: () async {
                final selected = await showAnalyticsRangePicker(
                  context,
                  range,
                  maximumRangeDays: 367,
                );
                if (selected != null && context.mounted) {
                  ref
                      .read(analyticsRangeProvider(widget.siteId).notifier)
                      .setRange(selected);
                }
              },
              onRefresh: () {
                ref.invalidate(searchConsolePropertyProvider(widget.siteId));
                ref.invalidate(searchConsoleReportProvider(query));
              },
            ),
      body: property.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => _loadError(context),
        data: (configured) =>
            _buildContent(context, configured, report, query, range),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    SearchConsoleProperty property,
    AsyncValue<SearchConsoleReport> report,
    SearchConsoleReportQuery query,
    AnalyticsRangeState range,
  ) {
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(searchConsolePropertyProvider(widget.siteId));
        ref.invalidate(searchConsoleReportProvider(query));
        await ref.read(searchConsolePropertyProvider(widget.siteId).future);
      },
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            runSpacing: 12,
            spacing: 16,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 670),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tr('Google Search performance', 'Google 搜索表现'),
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 5),
                    Text(
                      context.tr(
                        'Organic search performance from Search Console, alongside SeeRay onsite acquisition analytics.',
                        '将 Search Console 的自然搜索表现与 SeeRay 站内流量分析并列查看。',
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
          _PropertyCard(
            property: property,
            propertyController: _propertyController,
            saving: _saving,
            checking: _checking,
            validation: _validation,
            actionError: _actionError,
            onSave: _save,
            onValidate: _validate,
            onDelete: () => _delete(property),
          ),
          if (property.configured) ...[
            const SizedBox(height: 16),
            _reportContent(context, report, query, range),
          ],
        ],
      ),
    );
  }

  Widget _reportContent(
    BuildContext context,
    AsyncValue<SearchConsoleReport> report,
    SearchConsoleReportQuery query,
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
                'Search Console report unavailable',
                'Search Console 报表暂不可用',
              ),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              context.tr(
                'Check that server ADC is configured, the service identity has access to this property, and the Search Console API is enabled.',
                '请检查服务端 ADC 配置、服务身份对该属性的访问权限，以及 Search Console API 是否已启用。',
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () =>
                  ref.invalidate(searchConsoleReportProvider(query)),
              icon: const Icon(Icons.refresh),
              label: Text(context.tr('Retry', '重试')),
            ),
          ],
        ),
      ),
    ),
    data: (data) => _reportCard(context, data, query, range),
  );

  Widget _reportCard(
    BuildContext context,
    SearchConsoleReport report,
    SearchConsoleReportQuery query,
    AnalyticsRangeState range,
  ) {
    final labels = <String, String>{
      'query': context.tr('Search queries', '搜索词'),
      'page': context.tr('Pages', '网页'),
      'country': context.tr('Countries', '国家/地区'),
      'device': context.tr('Devices', '设备'),
      'date': context.tr('Daily trend', '每日趋势'),
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
                    Text(
                      '${report.from} – ${report.to} · ${report.propertyUrl}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
                OutlinedButton.icon(
                  onPressed: () => _exportCsv(context, report, range),
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
                for (final dimension in searchConsoleDimensions)
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
                _MetricCard(
                  title: context.tr('Average position', '平均排名'),
                  value: report.averagePosition.toStringAsFixed(1),
                  icon: Icons.format_list_numbered,
                ),
              ],
            ),
            if (_dimension == 'date' && report.rows.isNotEmpty) ...[
              const SizedBox(height: 16),
              SizedBox(
                height: 150,
                width: double.infinity,
                child: CustomPaint(
                  painter: _SearchClicksChart(report.rows),
                  child: const SizedBox.expand(),
                ),
              ),
            ],
            const SizedBox(height: 12),
            if (report.mayBeTruncated || report.dataLimitNote.isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  context.tr(
                    '${report.dataLimitNote} Summary cards use a separate property-total query.',
                    '${report.dataLimitNote} 汇总卡片来自单独的属性总量查询。',
                  ),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            const SizedBox(height: 12),
            if (report.rows.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    context.tr(
                      'No Search Console rows were returned for this period.',
                      '该日期范围内没有返回 Search Console 明细。',
                    ),
                  ),
                ),
              )
            else
              _rowsTable(context, report),
          ],
        ),
      ),
    );
  }

  Widget _rowsTable(BuildContext context, SearchConsoleReport report) {
    final firstColumn = switch (_dimension) {
      'query' => context.tr('Search query', '搜索词'),
      'page' => context.tr('Landing page', '落地页'),
      'country' => context.tr('Country code', '国家/地区代码'),
      'device' => context.tr('Device', '设备'),
      _ => context.tr('Date', '日期'),
    };
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: [
          DataColumn(label: Text(firstColumn)),
          DataColumn(label: Text(context.tr('Clicks', '点击')), numeric: true),
          DataColumn(
            label: Text(context.tr('Impressions', '曝光')),
            numeric: true,
          ),
          DataColumn(label: Text('CTR'), numeric: true),
          DataColumn(label: Text(context.tr('Position', '排名')), numeric: true),
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
                DataCell(Text('${(row.ctr * 100).toStringAsFixed(2)}%')),
                DataCell(Text(row.position.toStringAsFixed(1))),
              ],
            ),
        ],
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
      await SearchConsoleRepository(
        ref,
      ).saveProperty(widget.siteId, _propertyController.text.trim());
      _propertyDirty = false;
      ref.invalidate(searchConsolePropertyProvider(widget.siteId));
      ref.invalidate(searchConsoleReportProvider);
      if (mounted) _snack(context.tr('Property saved.', '属性已保存。'));
    } catch (error) {
      if (mounted) {
        setState(() => _actionError = _apiMessage(error));
      }
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
      final result = await SearchConsoleRepository(ref).validate(widget.siteId);
      if (mounted) setState(() => _validation = result);
    } catch (error) {
      if (mounted) setState(() => _actionError = _apiMessage(error));
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _delete(SearchConsoleProperty property) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.tr('Remove property?', '移除 Search Console 属性？')),
        content: Text(
          context.tr(
            'This removes the saved property from this site. No Google credentials are stored here.',
            '这会移除当前站点保存的属性标识；本产品不保存 Google 凭据。',
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
      await SearchConsoleRepository(ref).deleteProperty(widget.siteId);
      _propertyController.clear();
      _propertyDirty = false;
      ref.invalidate(searchConsolePropertyProvider(widget.siteId));
      ref.invalidate(searchConsoleReportProvider);
      if (mounted) _snack(context.tr('Property removed.', '属性已移除。'));
    } catch (error) {
      if (mounted) setState(() => _actionError = _apiMessage(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _exportCsv(
    BuildContext context,
    SearchConsoleReport report,
    AnalyticsRangeState range,
  ) async {
    final csv = AnalyticsReportExport.csv(
      const ['dimension', 'clicks', 'impressions', 'ctr', 'position'],
      report.rows
          .map(
            (row) => <Object?>[
              row.key,
              row.clicks,
              row.impressions,
              row.ctr,
              row.position,
            ],
          )
          .toList(growable: false),
    );
    final result = await FilePicker.platform.saveFile(
      dialogTitle: context.tr(
        'Export Search Console rows',
        '导出 Search Console 明细',
      ),
      fileName:
          'seeray-search-console-$_dimension-${range.range.fromQuery}-${range.range.toQuery}.csv',
      allowedExtensions: const ['csv'],
      bytes: Uint8List.fromList(utf8.encode(csv)),
    );
    if (result != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('CSV exported.', 'CSV 已导出。'))),
      );
    }
  }

  Widget _loadError(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          context.tr(
            'Could not load Search Console settings.',
            '无法加载 Search Console 设置。',
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () =>
              ref.invalidate(searchConsolePropertyProvider(widget.siteId)),
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

class _PropertyCard extends StatelessWidget {
  const _PropertyCard({
    required this.property,
    required this.propertyController,
    required this.saving,
    required this.checking,
    required this.validation,
    required this.actionError,
    required this.onSave,
    required this.onValidate,
    required this.onDelete,
  });

  final SearchConsoleProperty property;
  final TextEditingController propertyController;
  final bool saving;
  final bool checking;
  final SearchConsoleValidation? validation;
  final String? actionError;
  final VoidCallback onSave;
  final VoidCallback onValidate;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final color = validation == null
        ? Theme.of(context).colorScheme.primary
        : validation!.accessible
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
                  context.tr('Property connection', '属性连接'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Chip(
                  avatar: Icon(
                    validation?.accessible == true
                        ? Icons.check_circle
                        : property.configured
                        ? Icons.link
                        : Icons.link_off,
                    size: 18,
                    color: color,
                  ),
                  label: Text(
                    validation?.accessible == true
                        ? context.tr('Access verified', '已验证访问权限')
                        : property.configured
                        ? context.tr('Property configured', '已配置属性')
                        : context.tr('Not configured', '未配置'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              context.tr(
                'Enter a URL-prefix property (https://example.com/) or domain property (sc-domain:example.com). Google credentials remain on the server.',
                '输入 URL 前缀属性（https://example.com/）或域名属性（sc-domain:example.com）。Google 凭据仅保留在服务端。',
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
                      controller: propertyController,
                      maxLength: 2048,
                      decoration: InputDecoration(
                        labelText: context.tr(
                          'Search Console property',
                          'Search Console 属性',
                        ),
                        hintText:
                            'https://example.com/  or  sc-domain:example.com',
                        prefixIcon: const Icon(Icons.travel_explore),
                        border: const OutlineInputBorder(),
                        counterText: '',
                      ),
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: saving ? null : onSave,
                    icon: saving
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_outlined),
                    label: Text(context.tr('Save property', '保存属性')),
                  ),
                  OutlinedButton.icon(
                    onPressed: !property.configured || checking || saving
                        ? null
                        : onValidate,
                    icon: checking
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.verified_outlined),
                    label: Text(context.tr('Test access', '测试访问')),
                  ),
                  if (property.configured)
                    IconButton(
                      tooltip: context.tr('Remove property', '移除属性'),
                      onPressed: saving ? null : onDelete,
                      icon: const Icon(Icons.delete_outline),
                    ),
                ],
              )
            else
              SelectableText(property.propertyUrl ?? '—'),
            if (validation != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(
                    validation!.accessible
                        ? Icons.check_circle
                        : Icons.error_outline,
                    color: color,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      validation!.permissionLevel == null
                          ? validation!.message
                          : '${validation!.message} · ${validation!.permissionLevel}',
                    ),
                  ),
                ],
              ),
            ],
            if (actionError != null) ...[
              const SizedBox(height: 10),
              Text(
                actionError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              context.tr(
                'Setup: enable Search Console API, configure ADC on the SeeRay server, and grant its service identity at least read access to this property. Search Console data is usually delayed and may omit anonymized or low-volume queries.',
                '配置方式：启用 Search Console API、在 SeeRay 服务端配置 ADC，并向服务身份授予此属性至少只读权限。Search Console 数据通常有延迟，且可能省略匿名或低流量搜索词。',
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
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

class _SearchClicksChart extends CustomPainter {
  const _SearchClicksChart(this.rows);

  final List<SearchConsoleReportRow> rows;

  @override
  void paint(Canvas canvas, Size size) {
    if (rows.isEmpty) return;
    const inset = 8.0;
    final width = size.width - inset * 2;
    final height = size.height - inset * 2;
    final maxClicks = rows.fold<double>(
      0,
      (maximum, row) => math.max(maximum, row.clicks),
    );
    final path = Path();
    for (var index = 0; index < rows.length; index++) {
      final x =
          inset +
          (rows.length == 1 ? width / 2 : width * index / (rows.length - 1));
      final y =
          inset +
          height -
          (maxClicks == 0 ? 0 : height * rows[index].clicks / maxClicks);
      if (index == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawLine(
      Offset(inset, size.height - inset),
      Offset(size.width - inset, size.height - inset),
      Paint()..color = Colors.blueGrey.withValues(alpha: 0.3),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xff2878d0)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_SearchClicksChart oldDelegate) =>
      oldDelegate.rows != rows;
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
