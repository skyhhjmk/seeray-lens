import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_i18n.dart';
import '../../auth/application/auth_controller.dart';
import 'capture_view.dart';

class RecordingsPage extends ConsumerStatefulWidget {
  const RecordingsPage({required this.siteId, super.key});
  final String siteId;

  @override
  ConsumerState<RecordingsPage> createState() => _RecordingsPageState();
}

class _RecordingsPageState extends ConsumerState<RecordingsPage> {
  List<Map<String, dynamic>> _recordings = const [];
  Map<String, dynamic>? _selected;
  Object? _error;
  bool _loading = true;
  int _page = 0;
  static const int _pageSize = 10;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
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
                    '/api/v1/sites/${widget.siteId}/heatmaps/recordings?limit=100',
                  )
              as List;
      final values = response
          .cast<Map>()
          .map((item) => item.cast<String, dynamic>())
          .toList();
      if (!mounted) return;
      setState(() {
        _recordings = values;
        _selected = values.isEmpty ? null : values.first;
        _page = 0;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    final pageCount = (_recordings.length / _pageSize).ceil();
    final firstItem = _recordings.isEmpty ? 0 : _page * _pageSize + 1;
    final lastItem = math.min((_page + 1) * _pageSize, _recordings.length);
    final pageItems = _recordings
        .skip(_page * _pageSize)
        .take(_pageSize)
        .toList();
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  tr('Session recordings', '会话回放'),
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
            ],
          ),
          Text(
            tr(
              'Inputs are masked in the visitor browser before upload.',
              '输入内容会在访客浏览器中完成遮罩后再上传。',
            ),
          ),
          const SizedBox(height: 16),
          if (_loading) const LinearProgressIndicator(),
          if (_error != null)
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: ListTile(title: Text('$_error')),
            ),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 320,
                  child: Card(
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  tr('Sessions', '会话列表'),
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                              ),
                              Text(
                                '$firstItem–$lastItem / ${_recordings.length}',
                              ),
                            ],
                          ),
                        ),
                        const Divider(height: 1),
                        Expanded(
                          child: ListView.builder(
                            itemCount: pageItems.length,
                            itemBuilder: (context, index) {
                              final item = pageItems[index];
                              final active = identical(item, _selected);
                              return ListTile(
                                selected: active,
                                title: Text(
                                  _readableDateTime(item['startedAt']),
                                ),
                                subtitle: Text(
                                  '${item['pageCount']} ${tr('pages', '页')} · ${item['eventCount']} ${tr('events', '事件')}',
                                ),
                                trailing: item['truncated'] == true
                                    ? const Icon(Icons.warning_amber)
                                    : null,
                                onTap: () => setState(() => _selected = item),
                              );
                            },
                          ),
                        ),
                        const Divider(height: 1),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconButton(
                              tooltip: tr('First page', '第一页'),
                              onPressed: _page > 0
                                  ? () => setState(() => _page = 0)
                                  : null,
                              icon: const Icon(Icons.first_page),
                            ),
                            IconButton(
                              tooltip: tr('Previous page', '上一页'),
                              onPressed: _page > 0
                                  ? () => setState(() => _page--)
                                  : null,
                              icon: const Icon(Icons.chevron_left),
                            ),
                            Text(
                              '${pageCount == 0 ? 0 : _page + 1} / $pageCount',
                            ),
                            IconButton(
                              tooltip: tr('Next page', '下一页'),
                              onPressed: _page + 1 < pageCount
                                  ? () => setState(() => _page++)
                                  : null,
                              icon: const Icon(Icons.chevron_right),
                            ),
                            IconButton(
                              tooltip: tr('Last page', '最后一页'),
                              onPressed: _page + 1 < pageCount
                                  ? () => setState(() => _page = pageCount - 1)
                                  : null,
                              icon: const Icon(Icons.last_page),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Card(
                    clipBehavior: Clip.antiAlias,
                    child: _selected == null
                        ? Center(child: Text(tr('No recordings yet', '暂无会话回放')))
                        : CaptureView(
                            key: ValueKey(_selected!['id']),
                            apiBase: ref.read(apiProvider).baseUrl,
                            siteId: widget.siteId,
                            resourceId: '${_selected!['id']}',
                            accessToken:
                                ref.read(apiProvider).accessToken ?? '',
                            mode: 'recording',
                          ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _readableDateTime(Object? value) {
  final parsed = DateTime.tryParse(value?.toString() ?? '');
  if (parsed == null) return '—';
  final local = parsed.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
}
