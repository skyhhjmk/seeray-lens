import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';

import '../../../core/i18n/app_i18n.dart';
import '../../auth/application/auth_controller.dart';
import '../application/analytics_range.dart';
import 'capture_view.dart';

enum _HeatmapType { click, move, scroll }

class HeatmapPage extends ConsumerStatefulWidget {
  const HeatmapPage({required this.siteId, this.embedded = false, super.key});
  final String siteId;
  final bool embedded;

  @override
  ConsumerState<HeatmapPage> createState() => _HeatmapPageState();
}

class _HeatmapPageState extends ConsumerState<HeatmapPage> {
  List<Map<String, dynamic>> _variants = const [];
  Map<String, dynamic>? _selected;
  Map<String, dynamic>? _stats;
  List<Map<String, dynamic>> _snapshots = const [];
  Map<String, dynamic>? _snapshot;
  Map<String, dynamic>? _domSnapshot;
  bool _useDomSnapshot = true;
  bool _toolsOpen = false;
  Object? _error;
  bool _loading = true;
  _HeatmapType _type = _HeatmapType.click;
  double _overlayOpacity = .75;
  int _variantPage = 0;
  static const _variantPageSize = 6;
  final TextEditingController _variantPageInput = TextEditingController();
  final ScrollController _previewScrollController = ScrollController();
  int _variantsRequest = 0;
  int _snapshotsRequest = 0;
  int _statsRequest = 0;

  @override
  void initState() {
    super.initState();
    _loadVariants();
  }

  @override
  void didUpdateWidget(covariant HeatmapPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.siteId != widget.siteId) {
      _variantsRequest++;
      _snapshotsRequest++;
      _statsRequest++;
      _variants = const [];
      _selected = null;
      _stats = null;
      _domSnapshot = null;
      _loadVariants();
    }
  }

  @override
  void dispose() {
    _previewScrollController.dispose();
    _variantPageInput.dispose();
    super.dispose();
  }

  void _scrollPreview(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !_previewScrollController.hasClients) {
      return;
    }
    GestureBinding.instance.pointerSignalResolver.register(event, (
      resolvedEvent,
    ) {
      final scrollEvent = resolvedEvent as PointerScrollEvent;
      final position = _previewScrollController.position;
      final next = (position.pixels + scrollEvent.scrollDelta.dy).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      _previewScrollController.jumpTo(next.toDouble());
    });
  }

  Future<void> _loadVariants() async {
    final request = ++_variantsRequest;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response =
          await ref
                  .read(apiProvider)
                  .request(
                    'GET',
                    '/api/v1/sites/${widget.siteId}/heatmaps/variants',
                  )
              as List;
      final variants = response
          .cast<Map>()
          .map((x) => x.cast<String, dynamic>())
          .toList();
      if (!mounted || request != _variantsRequest) return;
      setState(() {
        _variants = variants;
        _selected = variants.isEmpty ? null : variants.first;
        _loading = false;
      });
      await _loadStats();
      await _loadSnapshots();
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = error;
        });
      }
    }
  }

  Future<void> _loadSnapshots() async {
    final variant = _selected;
    if (variant == null) return;
    final request = ++_snapshotsRequest;
    try {
      final result =
          await ref
                  .read(apiProvider)
                  .request(
                    'GET',
                    '/api/v1/sites/${widget.siteId}/heatmaps/snapshots?variantId=${variant['id']}',
                  )
              as List;
      final snapshots = result
          .cast<Map>()
          .map((item) => item.cast<String, dynamic>())
          .toList();
      Map<String, dynamic>? domSnapshot;
      try {
        final metadata =
            await ref
                    .read(apiProvider)
                    .request(
                      'GET',
                      '/api/v1/sites/${widget.siteId}/heatmaps/dom-snapshots/${variant['id']}/metadata',
                    )
                as Map;
        domSnapshot = metadata.cast<String, dynamic>();
      } catch (_) {
        domSnapshot = null;
      }
      if (mounted &&
          request == _snapshotsRequest &&
          identical(variant, _selected)) {
        setState(() {
          _snapshots = snapshots;
          _snapshot = snapshots.isEmpty ? null : snapshots.first;
          _domSnapshot = domSnapshot;
          _useDomSnapshot = domSnapshot != null;
        });
      }
    } catch (error) {
      if (mounted && request == _snapshotsRequest) {
        setState(() => _error = error);
      }
    }
  }

  Future<void> _uploadSnapshot() async {
    final variant = _selected;
    if (variant == null) return;
    final selected = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['png', 'jpg', 'jpeg'],
      withData: true,
    );
    final file = selected?.files.single;
    if (file?.bytes == null) return;
    final extension = file!.extension?.toLowerCase();
    final contentType = extension == 'png' ? 'image/png' : 'image/jpeg';
    try {
      await ref
          .read(apiProvider)
          .requestBytes(
            'POST',
            '/api/v1/sites/${widget.siteId}/heatmaps/snapshots?variantId=${variant['id']}',
            file.bytes!,
            contentType: contentType,
          );
      await _loadSnapshots();
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _deleteSnapshot() async {
    final snapshot = _snapshot;
    if (snapshot == null) return;
    try {
      await ref
          .read(apiProvider)
          .request(
            'DELETE',
            '/api/v1/sites/${widget.siteId}/heatmaps/snapshots/${snapshot['id']}',
          );
      await _loadSnapshots();
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _loadStats() async {
    final variant = _selected;
    if (variant == null) return;
    final request = ++_statsRequest;
    final range = ref.read(analyticsRangeProvider(widget.siteId)).range;
    try {
      final result =
          await ref
                  .read(apiProvider)
                  .request(
                    'GET',
                    '/api/v1/sites/${widget.siteId}/heatmaps/stats?variantId=${variant['id']}&from=${_date(range.from)}&to=${_date(range.to)}&type=${_type.name}',
                  )
              as Map;
      if (mounted &&
          request == _statsRequest &&
          identical(variant, _selected)) {
        setState(() {
          _stats = result.cast<String, dynamic>();
          _error = null;
        });
      }
    } catch (error) {
      if (mounted && request == _statsRequest) setState(() => _error = error);
    }
  }

  Future<void> _selectVariant(Map<String, dynamic>? value) async {
    if (value == null || identical(value, _selected)) return;
    setState(() {
      _snapshotsRequest++;
      _statsRequest++;
      _selected = value;
      _variantPage = _variants.indexOf(value) ~/ _variantPageSize;
      _stats = null;
      _snapshots = const [];
      _snapshot = null;
      _domSnapshot = null;
      _useDomSnapshot = true;
    });
    await _loadStats();
    await _loadSnapshots();
  }

  Future<void> _selectType(Set<_HeatmapType> value) async {
    final type = value.first;
    if (type == _type) return;
    setState(() {
      _type = type;
      _stats = null;
    });
    await _loadStats();
  }

  void _goToVariantPage(int page) {
    final pageCount = (_variants.length / _variantPageSize).ceil();
    if (pageCount == 0) return;
    setState(() => _variantPage = page.clamp(0, pageCount - 1));
  }

  Widget _buildVariantPane(BuildContext context) {
    final tr = context.tr;
    final pageCount = (_variants.length / _variantPageSize).ceil();
    final pageItems = _variants
        .skip(_variantPage * _variantPageSize)
        .take(_variantPageSize)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          tr('Page instances', '页面实例'),
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 4),
        Expanded(
          child: ListView.builder(
            itemCount: pageItems.length,
            itemBuilder: (context, index) {
              final item = pageItems[index];
              final active = identical(item, _selected);
              return ListTile(
                dense: true,
                selected: active,
                title: Text(
                  '${item['pageUrl']}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${item['contentWidth']}×${item['contentHeight']} · ${_readableDateTime(item['createdAt'])}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => _selectVariant(item),
              );
            },
          ),
        ),
        const Divider(height: 12),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 0,
          children: [
            IconButton(
              tooltip: tr('First page', '第一页'),
              onPressed: _variantPage > 0 ? () => _goToVariantPage(0) : null,
              icon: const Icon(Icons.first_page),
            ),
            IconButton(
              tooltip: tr('Previous page', '上一页'),
              onPressed: _variantPage > 0
                  ? () => _goToVariantPage(_variantPage - 1)
                  : null,
              icon: const Icon(Icons.chevron_left),
            ),
            DropdownButton<int>(
              value: pageCount == 0 ? null : _variantPage,
              hint: const Text('—'),
              items: List.generate(
                pageCount,
                (index) => DropdownMenuItem(
                  value: index,
                  child: Text('${index + 1} / $pageCount'),
                ),
              ),
              onChanged: (value) {
                if (value != null) _goToVariantPage(value);
              },
            ),
            IconButton(
              tooltip: tr('Next page', '下一页'),
              onPressed: _variantPage + 1 < pageCount
                  ? () => _goToVariantPage(_variantPage + 1)
                  : null,
              icon: const Icon(Icons.chevron_right),
            ),
            IconButton(
              tooltip: tr('Last page', '最后一页'),
              onPressed: _variantPage + 1 < pageCount
                  ? () => _goToVariantPage(pageCount - 1)
                  : null,
              icon: const Icon(Icons.last_page),
            ),
          ],
        ),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _variantPageInput,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  isDense: true,
                  labelText: tr('Go to page', '跳转页码'),
                ),
                onSubmitted: (value) {
                  final page = int.tryParse(value);
                  if (page != null) _goToVariantPage(page - 1);
                },
              ),
            ),
            IconButton(
              tooltip: tr('Go', '跳转'),
              onPressed: () {
                final page = int.tryParse(_variantPageInput.text);
                if (page != null) _goToVariantPage(page - 1);
              },
              icon: const Icon(Icons.arrow_forward),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AnalyticsRangeState>(analyticsRangeProvider(widget.siteId), (
      previous,
      next,
    ) {
      if (previous == null ||
          previous.range.fromQuery != next.range.fromQuery ||
          previous.range.toQuery != next.range.toQuery) {
        _loadStats();
      }
    });
    final tr = context.tr;
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_variants.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _Empty(
            title: tr('No matched page layouts yet', '尚无匹配的页面布局'),
            message: tr(
              'Enable heatmaps, visit a page, then return here. Layouts are kept separate by URL, version, target, and CSS dimensions.',
              '请先开启热图并访问页面，再返回此处。系统会按地址、版本、目标和 CSS 尺寸分别保存布局。',
            ),
            retry: _loadVariants,
            error: _error,
          ),
        ],
      );
    }
    final selected = _selected!;
    final cells = ((_stats?['cells'] as List?) ?? const []).cast<Map>();
    final depth = ((_stats?['depth'] as List?) ?? const []).cast<Map>();
    return LayoutBuilder(
      builder: (context, constraints) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_error != null)
              Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: ListTile(
                  title: Text(
                    tr(
                      'Could not refresh heatmap; the last visible result is retained.',
                      '热图刷新失败；已显示的结果仍会保留。',
                    ),
                  ),
                  trailing: TextButton(
                    onPressed: _loadStats,
                    child: Text(tr('Retry', '重试')),
                  ),
                ),
              ),
            if (_type == _HeatmapType.scroll) ...[
              _ScrollDepth(depth: depth),
              const SizedBox(height: 8),
            ] else
              _HeatLegend(type: _type),
            const SizedBox(height: 8),
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Card(
                      clipBehavior: Clip.antiAlias,
                      child: Listener(
                        onPointerSignal: _scrollPreview,
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final contentWidth =
                                (selected['contentWidth'] as num).toDouble();
                            final contentHeight =
                                (selected['contentHeight'] as num).toDouble();
                            final scale = math
                                .min(1.0, constraints.maxWidth / contentWidth)
                                .toDouble();
                            final previewWidth = contentWidth * scale;
                            final previewHeight = contentHeight * scale;
                            return Scrollbar(
                              controller: _previewScrollController,
                              thumbVisibility: true,
                              child: SingleChildScrollView(
                                controller: _previewScrollController,
                                primary: false,
                                child: Align(
                                  alignment: Alignment.topCenter,
                                  child: SizedBox(
                                    width: previewWidth,
                                    height: previewHeight,
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        if (_useDomSnapshot &&
                                            _domSnapshot != null)
                                          CaptureView(
                                            apiBase: ref
                                                .read(apiProvider)
                                                .baseUrl,
                                            siteId: widget.siteId,
                                            resourceId: '${selected['id']}',
                                            accessToken:
                                                ref
                                                    .read(apiProvider)
                                                    .accessToken ??
                                                '',
                                            mode: 'snapshot',
                                          )
                                        else if (_snapshot != null)
                                          _SnapshotTiles(
                                            baseUrl: ref
                                                .read(apiProvider)
                                                .baseUrl,
                                            siteId: widget.siteId,
                                            snapshot: _snapshot!,
                                            accessToken: ref
                                                .read(apiProvider)
                                                .accessToken,
                                            scale: scale,
                                          )
                                        else
                                          Center(
                                            child: Text(
                                              tr(
                                                'No automatic or manual snapshot for this layout',
                                                '此布局暂无自动或手动快照',
                                              ),
                                            ),
                                          ),
                                        Opacity(
                                          opacity: _overlayOpacity,
                                          child: CustomPaint(
                                            painter: _GridPainter(
                                              cells,
                                              contentWidth,
                                              contentHeight,
                                              (_stats?['gridSize'] as num?)
                                                      ?.toDouble() ??
                                                  16,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 16,
                    bottom: 16,
                    child: AnimatedContainer(
                      // Rendering the expanded controls while this container is
                      // still constrained to 56×56 produces a transient Flex
                      // overflow. Swap the two layouts atomically instead.
                      duration: Duration.zero,
                      width: _toolsOpen ? 760 : 56,
                      height: _toolsOpen ? 528 : 56,
                      padding: EdgeInsets.all(_toolsOpen ? 12 : 0),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(
                          _toolsOpen ? 20 : 28,
                        ),
                        boxShadow: const [
                          BoxShadow(blurRadius: 18, color: Color(0x44000000)),
                        ],
                      ),
                      child: _toolsOpen
                          ? Stack(
                              children: [
                                Positioned.fill(
                                  child: Row(
                                    children: [
                                      SizedBox(
                                        width: 310,
                                        child: _buildVariantPane(context),
                                      ),
                                      const VerticalDivider(width: 25),
                                      Expanded(
                                        child: Padding(
                                          padding: const EdgeInsets.only(
                                            top: 48,
                                          ),
                                          child: SingleChildScrollView(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.stretch,
                                              children: [
                                                Text(
                                                  tr(
                                                    'Heatmap controls',
                                                    '热图快捷设置',
                                                  ),
                                                  style: Theme.of(
                                                    context,
                                                  ).textTheme.titleMedium,
                                                ),
                                                const SizedBox(height: 8),
                                                _Summary(
                                                  stats: _stats,
                                                  compact: true,
                                                ),
                                                const SizedBox(height: 12),
                                                SegmentedButton<_HeatmapType>(
                                                  segments: [
                                                    ButtonSegment(
                                                      value: _HeatmapType.click,
                                                      label: Text(
                                                        tr('Clicks', '点击'),
                                                      ),
                                                      icon: const Icon(
                                                        Icons.ads_click,
                                                      ),
                                                    ),
                                                    ButtonSegment(
                                                      value: _HeatmapType.move,
                                                      label: Text(
                                                        tr('Moves', '鼠标'),
                                                      ),
                                                      icon: const Icon(
                                                        Icons.mouse,
                                                      ),
                                                    ),
                                                    ButtonSegment(
                                                      value:
                                                          _HeatmapType.scroll,
                                                      label: Text(
                                                        tr('Scroll', '滚动'),
                                                      ),
                                                      icon: const Icon(
                                                        Icons.swap_vert,
                                                      ),
                                                    ),
                                                  ],
                                                  selected: {_type},
                                                  onSelectionChanged:
                                                      _selectType,
                                                ),
                                                const SizedBox(height: 10),
                                                Wrap(
                                                  spacing: 8,
                                                  runSpacing: 8,
                                                  children: [
                                                    OutlinedButton.icon(
                                                      onPressed: _loadStats,
                                                      icon: const Icon(
                                                        Icons.refresh,
                                                      ),
                                                      label: Text(
                                                        tr('Refresh', '刷新'),
                                                      ),
                                                    ),
                                                    OutlinedButton.icon(
                                                      onPressed:
                                                          _uploadSnapshot,
                                                      icon: const Icon(
                                                        Icons.upload_file,
                                                      ),
                                                      label: Text(
                                                        tr(
                                                          'Upload image',
                                                          '上传图片',
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 10),
                                                Text(
                                                  tr('Preview source', '预览来源'),
                                                ),
                                                if (_domSnapshot != null)
                                                  ChoiceChip(
                                                    label: Text(
                                                      '${tr('Automatic DOM', '自动 DOM')} · ${_readableDateTime(_domSnapshot!['createdAt'])}',
                                                    ),
                                                    selected: _useDomSnapshot,
                                                    onSelected: (_) => setState(
                                                      () => _useDomSnapshot =
                                                          true,
                                                    ),
                                                  ),
                                                if (_snapshots.isNotEmpty)
                                                  DropdownButton<
                                                    Map<String, dynamic>
                                                  >(
                                                    isExpanded: true,
                                                    value: _useDomSnapshot
                                                        ? null
                                                        : _snapshot,
                                                    hint: Text(
                                                      tr(
                                                        'Manual image',
                                                        '手动图片',
                                                      ),
                                                    ),
                                                    items: _snapshots
                                                        .map(
                                                          (
                                                            snapshot,
                                                          ) => DropdownMenuItem(
                                                            value: snapshot,
                                                            child: Text(
                                                              _readableDateTime(
                                                                snapshot['createdAt'],
                                                              ),
                                                            ),
                                                          ),
                                                        )
                                                        .toList(),
                                                    onChanged: (value) =>
                                                        setState(() {
                                                          _snapshot = value;
                                                          _useDomSnapshot =
                                                              false;
                                                        }),
                                                  ),
                                                if (!_useDomSnapshot &&
                                                    _snapshot != null)
                                                  Align(
                                                    alignment:
                                                        Alignment.centerLeft,
                                                    child: TextButton.icon(
                                                      onPressed:
                                                          _deleteSnapshot,
                                                      icon: const Icon(
                                                        Icons.delete_outline,
                                                      ),
                                                      label: Text(
                                                        tr(
                                                          'Delete image',
                                                          '删除图片',
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                const Divider(height: 24),
                                                Row(
                                                  children: [
                                                    Text(tr('Opacity', '透明度')),
                                                    Expanded(
                                                      child: Slider(
                                                        value: _overlayOpacity,
                                                        min: .1,
                                                        max: 1,
                                                        onChanged: (value) =>
                                                            setState(
                                                              () =>
                                                                  _overlayOpacity =
                                                                      value,
                                                            ),
                                                      ),
                                                    ),
                                                    IconButton(
                                                      tooltip: tr(
                                                        'Back to top',
                                                        '回到顶部',
                                                      ),
                                                      onPressed: () =>
                                                          _previewScrollController
                                                              .jumpTo(0),
                                                      icon: const Icon(
                                                        Icons
                                                            .vertical_align_top,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Positioned(
                                  top: 0,
                                  right: 0,
                                  child: IconButton.filledTonal(
                                    tooltip: tr('Close controls', '关闭快捷设置'),
                                    onPressed: () =>
                                        setState(() => _toolsOpen = false),
                                    icon: const Icon(Icons.close),
                                  ),
                                ),
                              ],
                            )
                          : IconButton(
                              tooltip: tr('Heatmap controls', '热图快捷设置'),
                              onPressed: () =>
                                  setState(() => _toolsOpen = true),
                              icon: const Icon(Icons.tune),
                            ),
                    ),
                  ),
                ],
              ),
            ),
            if (_stats == null)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
          ],
        ),
      ),
    );
  }
}

class _HeatLegend extends StatelessWidget {
  const _HeatLegend({required this.type});
  final _HeatmapType type;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(context.tr('Low', '低')),
      const SizedBox(width: 6),
      Container(
        width: 96,
        height: 10,
        decoration: const BoxDecoration(
          gradient: LinearGradient(colors: [Colors.transparent, Colors.red]),
        ),
      ),
      const SizedBox(width: 6),
      Text(context.tr('High', '高')),
      const SizedBox(width: 6),
      Text(
        type == _HeatmapType.move
            ? context.tr('sample count', '采样点数')
            : context.tr('count', '次数'),
      ),
    ],
  );
}

class _SnapshotTiles extends StatelessWidget {
  const _SnapshotTiles({
    required this.baseUrl,
    required this.siteId,
    required this.snapshot,
    required this.accessToken,
    required this.scale,
  });
  final String baseUrl;
  final String siteId;
  final Map<String, dynamic> snapshot;
  final String? accessToken;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final height = (snapshot['height'] as num?)?.toInt() ?? 1;
    final tiles = (snapshot['tileCount'] as num?)?.toInt() ?? 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: List.generate(tiles, (index) {
        final top = index * 2048;
        final tileHeight = (height - top).clamp(1, 2048).toInt();
        return SizedBox(
          height: tileHeight * scale,
          child: Image.network(
            '$baseUrl/api/v1/sites/$siteId/heatmaps/snapshots/${snapshot['id']}/tiles/$index',
            headers: {
              if (accessToken != null) 'Authorization': 'Bearer $accessToken',
            },
            fit: BoxFit.fill,
            filterQuality: FilterQuality.none,
          ),
        );
      }),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.stats, this.compact = false});
  final Map<String, dynamic>? stats;
  final bool compact;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: compact ? 4 : 12,
    runSpacing: compact ? 4 : 12,
    children: [
      _metric(
        context,
        context.tr('Sampled instances', '采集页面实例'),
        '${stats?['instances'] ?? 0}',
      ),
      _metric(
        context,
        context.tr('Raw count', '原始计数'),
        '${stats?['rawCount'] ?? 0}',
      ),
      _metric(
        context,
        context.tr('Updated', '数据更新'),
        _readableDateTime(stats?['updatedAt']),
      ),
      _metric(
        context,
        context.tr('Truncated instances', '截断实例'),
        '${stats?['truncatedInstances'] ?? 0}',
      ),
      _metric(
        context,
        context.tr('Client dropped points', '客户端丢弃点'),
        '${stats?['dropped'] ?? 0}',
      ),
    ],
  );
  Widget _metric(BuildContext context, String label, String value) => SizedBox(
    width: compact ? 148 : 180,
    child: Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: EdgeInsets.all(compact ? 7 : 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label),
            SizedBox(height: compact ? 1 : 4),
            Text(
              value,
              style: compact
                  ? Theme.of(context).textTheme.bodyMedium
                  : Theme.of(context).textTheme.titleMedium,
            ),
          ],
        ),
      ),
    ),
  );
}

class _GridPainter extends CustomPainter {
  const _GridPainter(
    this.cells,
    this.contentWidth,
    this.contentHeight,
    this.gridSize,
  );
  final List<Map> cells;
  final double contentWidth;
  final double contentHeight;
  final double gridSize;
  @override
  void paint(Canvas canvas, Size size) {
    final max = cells.fold<num>(
      0,
      (value, cell) =>
          (cell['count'] as num) > value ? cell['count'] as num : value,
    );
    final paint = Paint();
    for (final cell in cells) {
      final strength = max == 0
          ? 0.0
          : (cell['count'] as num).toDouble() / max.toDouble();
      paint.color = Color.lerp(
        Colors.transparent,
        Colors.red,
        strength,
      )!.withValues(alpha: .2 + strength * .65);
      canvas.drawRect(
        Rect.fromLTWH(
          (cell['x'] as num).toDouble() * gridSize / contentWidth * size.width,
          (cell['y'] as num).toDouble() *
              gridSize /
              contentHeight *
              size.height,
          gridSize / contentWidth * size.width,
          gridSize / contentHeight * size.height,
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_GridPainter oldDelegate) =>
      oldDelegate.cells != cells ||
      oldDelegate.contentWidth != contentWidth ||
      oldDelegate.contentHeight != contentHeight ||
      oldDelegate.gridSize != gridSize;
}

class _ScrollDepth extends StatelessWidget {
  const _ScrollDepth({required this.depth});
  final List<Map> depth;
  @override
  Widget build(BuildContext context) => Card(
    child: Column(
      children: depth.map((item) {
        final ratio = (item['ratio'] as num?)?.toDouble() ?? 0;
        return ListTile(
          title: LinearProgressIndicator(
            value: ratio,
            color: Color.lerp(Colors.blue, Colors.red, ratio),
          ),
          subtitle: Text('${item['bin']}%'),
          trailing: Text('${(ratio * 100).toStringAsFixed(1)}%'),
        );
      }).toList(),
    ),
  );
}

class _Empty extends StatelessWidget {
  const _Empty({
    required this.title,
    required this.message,
    required this.retry,
    this.error,
  });
  final String title, message;
  final VoidCallback retry;
  final Object? error;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(message),
              if (error != null) const SizedBox(height: 12),
              FilledButton(
                onPressed: retry,
                child: Text(context.tr('Retry', '重试')),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

String _date(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

String _readableDateTime(Object? value) {
  if (value == null) return '—';
  final parsed = DateTime.tryParse(value.toString());
  if (parsed == null) return value.toString();
  final local = parsed.toLocal();
  return '${local.year.toString().padLeft(4, '0')}-'
      '${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')} '
      '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}:'
      '${local.second.toString().padLeft(2, '0')}';
}
