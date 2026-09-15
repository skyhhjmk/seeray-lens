import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';

import '../../../core/i18n/app_i18n.dart';
import '../../auth/application/auth_controller.dart';
import '../application/analytics_range.dart';
import 'heatmap_config_card.dart';

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
  Map<String, dynamic>? _config;
  List<Map<String, dynamic>> _snapshots = const [];
  Map<String, dynamic>? _snapshot;
  Object? _error;
  bool _loading = true;
  _HeatmapType _type = _HeatmapType.click;
  double _overlayOpacity = .75;
  final TransformationController _canvasTransform = TransformationController();
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
      _loadVariants();
    }
  }

  @override
  void dispose() {
    _canvasTransform.dispose();
    super.dispose();
  }

  Future<void> _loadVariants() async {
    final request = ++_variantsRequest;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final responses = await Future.wait<dynamic>([
        ref
            .read(apiProvider)
            .request('GET', '/api/v1/sites/${widget.siteId}/heatmaps/variants'),
        ref
            .read(apiProvider)
            .request('GET', '/api/v1/sites/${widget.siteId}/heatmaps/config'),
      ]);
      final response = responses[0] as List;
      final variants = response
          .cast<Map>()
          .map((x) => x.cast<String, dynamic>())
          .toList();
      if (!mounted || request != _variantsRequest) return;
      setState(() {
        _variants = variants;
        _selected = variants.isEmpty ? null : variants.first;
        _config = (responses[1] as Map).cast<String, dynamic>();
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
      if (mounted && request == _snapshotsRequest && identical(variant, _selected)) {
        setState(() {
          _snapshots = snapshots;
          _snapshot = snapshots.isEmpty ? null : snapshots.first;
        });
      }
    } catch (error) {
      if (mounted && request == _snapshotsRequest) setState(() => _error = error);
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

  Future<void> _saveConfig({bool? enabled, int? sampleRate}) async {
    final config = _config;
    if (config == null) return;
    final next = <String, dynamic>{
      'enabled': enabled ?? config['enabled'] == true,
      'sampleRate': sampleRate ?? (config['sampleRate'] as num?)?.toInt() ?? 10,
      'rawRetentionDays': (config['rawRetentionDays'] as num?)?.toInt() ?? 30,
      'aggregateRetentionDays':
          (config['aggregateRetentionDays'] as num?)?.toInt() ?? 180,
    };
    try {
      final response =
          await ref
                  .read(apiProvider)
                  .request(
                    'PUT',
                    '/api/v1/sites/${widget.siteId}/heatmaps/config',
                    body: next,
                  )
              as Map;
      if (mounted) setState(() => _config = response.cast<String, dynamic>());
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
      if (mounted && request == _statsRequest && identical(variant, _selected)) {
        setState(() {
          _stats = result.cast<String, dynamic>();
          _error = null;
        });
      }
    } catch (error) {
      if (mounted && request == _statsRequest) setState(() => _error = error);
    }
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
          if (_config != null)
            ConfigCard(
              config: _config!,
              onEnabled: (value) => _saveConfig(enabled: value),
              onRate: (value) => _saveConfig(sampleRate: value),
            ),
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
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          tr('Behaviour heatmaps', '页面行为热图'),
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 6),
        Text(
          tr(
            'Coordinates are sampled CSS pixels. Mouse points are samples, not attention time; scroll reach is geometric and may be non-monotonic.',
            '坐标采用采样 CSS 像素。鼠标点是采样而非注意力时长；滚动到达表示几何可见区域，曲线可能不单调。',
          ),
        ),
        const SizedBox(height: 16),
        if (_config != null)
          ConfigCard(
            config: _config!,
            onEnabled: (value) => _saveConfig(enabled: value),
            onRate: (value) => _saveConfig(sampleRate: value),
          ),
        if (_config != null) const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            DropdownButton<Map<String, dynamic>>(
              value: selected,
              items: _variants
                  .map(
                    (variant) => DropdownMenuItem(
                      value: variant,
                      child: Text(
                        '${variant['pageUrl']} · ${variant['layoutVersion']} · ${variant['contentWidth']}×${variant['contentHeight']}',
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (value) async {
                if (value == null) return;
                setState(() {
                  _snapshotsRequest++;
                  _statsRequest++;
                  _selected = value;
                  _stats = null;
                  _snapshots = const [];
                  _snapshot = null;
                });
                await _loadStats();
                await _loadSnapshots();
              },
            ),
            SegmentedButton<_HeatmapType>(
              segments: [
                ButtonSegment(
                  value: _HeatmapType.click,
                  label: Text(tr('Clicks', '点击')),
                ),
                ButtonSegment(
                  value: _HeatmapType.move,
                  label: Text(tr('Mouse moves', '鼠标移动')),
                ),
                ButtonSegment(
                  value: _HeatmapType.scroll,
                  label: Text(tr('Scroll depth', '滚动深度')),
                ),
              ],
              selected: {_type},
              onSelectionChanged: (value) async {
                setState(() {
                  _type = value.first;
                  _stats = null;
                });
                await _loadStats();
              },
            ),
            FilledButton.icon(
              onPressed: _loadStats,
              icon: const Icon(Icons.refresh),
              label: Text(tr('Refresh', '刷新')),
            ),
            OutlinedButton.icon(
              onPressed: _uploadSnapshot,
              icon: const Icon(Icons.upload_file_outlined),
              label: Text(tr('Upload snapshot', '上传截图')),
            ),
            if (_snapshots.isNotEmpty)
              DropdownButton<Map<String, dynamic>>(
                value: _snapshot,
                items: _snapshots
                    .map(
                      (snapshot) => DropdownMenuItem(
                        value: snapshot,
                        child: Text(
                          '${snapshot['width']}×${snapshot['height']} · ${snapshot['createdAt']}',
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() => _snapshot = value),
              ),
            if (_snapshot != null)
              IconButton(
                tooltip: tr('Delete selected snapshot', '删除选中截图'),
                onPressed: _deleteSnapshot,
                icon: const Icon(Icons.delete_outline),
              ),
          ],
        ),
        const SizedBox(height: 16),
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
        _Summary(stats: _stats),
        const SizedBox(height: 16),
        if (_type == _HeatmapType.scroll)
          _ScrollDepth(depth: depth)
        else ...[
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            children: [
              Text(tr('Overlay opacity', '覆盖层透明度')),
              SizedBox(
                width: 180,
                child: Slider(
                  value: _overlayOpacity,
                  min: .1,
                  max: 1,
                  onChanged: (value) => setState(() => _overlayOpacity = value),
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => setState(() {
                  _canvasTransform.value = Matrix4.identity();
                }),
                icon: const Icon(Icons.center_focus_strong),
                label: Text(tr('Reset view', '重置视图')),
              ),
              _HeatLegend(type: _type),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 560,
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: InteractiveViewer(
                transformationController: _canvasTransform,
                minScale: .25,
                maxScale: 4,
                boundaryMargin: const EdgeInsets.all(240),
                child: Center(
                  child: AspectRatio(
                    aspectRatio:
                        (selected['contentWidth'] as num).toDouble() /
                        (selected['contentHeight'] as num).toDouble(),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (_snapshot != null)
                          _SnapshotTiles(
                            baseUrl: ref.read(apiProvider).baseUrl,
                            siteId: widget.siteId,
                            snapshot: _snapshot!,
                            accessToken: ref.read(apiProvider).accessToken,
                          )
                        else
                          Center(
                            child: Text(
                              tr('No snapshot uploaded for this layout', '此布局尚未上传截图'),
                            ),
                          ),
                        Opacity(
                          opacity: _overlayOpacity,
                          child: CustomPaint(
                            painter: _GridPainter(
                              cells,
                              (selected['contentWidth'] as num).toDouble(),
                              (selected['contentHeight'] as num).toDouble(),
                              (_stats?['gridSize'] as num?)?.toDouble() ?? 16,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
        if (_stats == null)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          ),
      ],
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
      Text(type == _HeatmapType.move ? context.tr('sample count', '采样点数') : context.tr('count', '次数')),
    ],
  );
}

class _SnapshotTiles extends StatelessWidget {
  const _SnapshotTiles({
    required this.baseUrl,
    required this.siteId,
    required this.snapshot,
    required this.accessToken,
  });
  final String baseUrl;
  final String siteId;
  final Map<String, dynamic> snapshot;
  final String? accessToken;

  @override
  Widget build(BuildContext context) {
    final height = (snapshot['height'] as num?)?.toInt() ?? 1;
    final tiles = (snapshot['tileCount'] as num?)?.toInt() ?? 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: List.generate(tiles, (index) {
        final top = index * 2048;
        final tileHeight = (height - top).clamp(1, 2048).toInt();
        return Expanded(
          flex: tileHeight,
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
  const _Summary({required this.stats});
  final Map<String, dynamic>? stats;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 12,
    runSpacing: 12,
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
        stats?['updatedAt']?.toString() ?? '—',
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
    width: 180,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label),
            const SizedBox(height: 4),
            Text(value, style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
      ),
    ),
  );
}

class _GridPainter extends CustomPainter {
  const _GridPainter(this.cells, this.contentWidth, this.contentHeight, this.gridSize);
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
          (cell['y'] as num).toDouble() * gridSize / contentHeight * size.height,
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
