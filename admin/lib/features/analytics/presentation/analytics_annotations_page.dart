import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_i18n.dart';
import '../../../shared/presentation/page_help_button.dart';
import '../../../shared/presentation/site_top_bar.dart';
import '../application/analytics_annotations.dart';
import '../application/analytics_range.dart';

class AnalyticsAnnotationsPage extends ConsumerWidget {
  const AnalyticsAnnotationsPage({
    required this.siteId,
    this.embedded = false,
    super.key,
  });

  final String siteId;
  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final range = ref.watch(analyticsRangeProvider(siteId));
    final query = AnalyticsAnnotationsQuery(
      siteId: siteId,
      from: range.range.fromQuery,
      to: range.range.toQuery,
    );
    final annotations = ref.watch(analyticsAnnotationsProvider(query));
    return Scaffold(
      backgroundColor: const Color(0xfff3f5f8),
      appBar: embedded
          ? null
          : SiteTopBar(
              siteId: siteId,
              selected: SiteTopTab.annotations,
              help: const PageHelpButton(
                englishTitle: 'Analytics annotations',
                chineseTitle: '分析注释',
                englishBody:
                    'Add dated notes for launches, campaigns, outages, and other changes. Notes are private to this site and appear as markers on dashboard trend charts.',
                chineseBody: '为发布、活动、故障等事件添加日期注释。注释仅属于当前站点，并会标记在仪表盘趋势图上。',
              ),
              rangeState: range,
              onSelectRange: () async {
                final selected = await showAnalyticsRangePicker(context, range);
                if (selected != null && context.mounted) {
                  ref
                      .read(analyticsRangeProvider(siteId).notifier)
                      .setRange(selected);
                }
              },
              onRefresh: () =>
                  ref.invalidate(analyticsAnnotationsProvider(query)),
            ),
      body: annotations.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => _AnnotationError(
          onRetry: () => ref.invalidate(analyticsAnnotationsProvider(query)),
        ),
        data: (state) =>
            _AnnotationTimeline(siteId: siteId, query: query, state: state),
      ),
    );
  }
}

class _AnnotationTimeline extends ConsumerWidget {
  const _AnnotationTimeline({
    required this.siteId,
    required this.query,
    required this.state,
  });

  final String siteId;
  final AnalyticsAnnotationsQuery query;
  final AnalyticsAnnotationsState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final grouped = <String, List<AnalyticsAnnotation>>{};
    for (final annotation in state.annotations) {
      grouped
          .putIfAbsent(_formatDate(annotation.date), () => [])
          .add(annotation);
    }
    final dates = grouped.keys.toList()..sort((a, b) => b.compareTo(a));
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(analyticsAnnotationsProvider(query));
        await ref.read(analyticsAnnotationsProvider(query).future);
      },
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.event_note_outlined, size: 30),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tr('Annotations', '分析注释'),
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      context.tr(
                        'Keep traffic changes in context. Add a note once and see its marker on every dashboard trend in this date range.',
                        '记录流量变化的背景。注释会出现在当前日期范围内的仪表盘趋势图中。',
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${context.tr('Showing', '当前范围')} ${state.from} – ${state.to} · ${state.annotations.length} ${state.annotations.length == 1 ? context.tr('note', '条注释') : context.tr('notes', '条注释')}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (state.canManage)
                FilledButton.icon(
                  onPressed: () => _edit(context, ref),
                  icon: const Icon(Icons.add),
                  label: Text(context.tr('Add note', '添加注释')),
                ),
            ],
          ),
          const SizedBox(height: 18),
          if (state.annotations.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 36,
                ),
                child: Column(
                  children: [
                    const Icon(
                      Icons.event_available_outlined,
                      size: 42,
                      color: Color(0xff748398),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      context.tr(
                        'No notes in this reporting range.',
                        '当前统计范围内还没有注释。',
                      ),
                    ),
                    if (state.canManage) ...[
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: () => _edit(context, ref),
                        icon: const Icon(Icons.add),
                        label: Text(context.tr('Record an event', '记录事件')),
                      ),
                    ],
                  ],
                ),
              ),
            )
          else
            for (final date in dates) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
                child: Row(
                  children: [
                    const Icon(
                      Icons.calendar_today_outlined,
                      size: 16,
                      color: Color(0xff526782),
                    ),
                    const SizedBox(width: 8),
                    Text(date, style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(width: 8),
                    Text(
                      '${grouped[date]!.length}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              for (final annotation in grouped[date]!)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: Color(0xfffff0cc),
                      child: Icon(
                        Icons.push_pin_outlined,
                        color: Color(0xff9a6714),
                      ),
                    ),
                    title: Text(annotation.note),
                    subtitle: Text(
                      context.tr(
                        'This marker is shown on dashboard trend charts.',
                        '此注释会标记在仪表盘趋势图上。',
                      ),
                    ),
                    trailing: state.canManage
                        ? PopupMenuButton<String>(
                            tooltip: context.tr('Note actions', '注释操作'),
                            onSelected: (action) => action == 'edit'
                                ? _edit(context, ref, annotation)
                                : _delete(context, ref, annotation),
                            itemBuilder: (context) => [
                              PopupMenuItem(
                                value: 'edit',
                                child: Text(context.tr('Edit', '编辑')),
                              ),
                              PopupMenuItem(
                                value: 'delete',
                                child: Text(context.tr('Delete', '删除')),
                              ),
                            ],
                          )
                        : null,
                  ),
                ),
            ],
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref, [
    AnalyticsAnnotation? annotation,
  ]) async {
    final currentRange = ref.read(analyticsRangeProvider(siteId)).range;
    final result = await showDialog<_AnnotationDraft>(
      context: context,
      builder: (context) => _AnnotationEditor(
        initialDate: annotation?.date ?? currentRange.to,
        initialNote: annotation?.note ?? '',
      ),
    );
    if (result == null || !context.mounted) return;
    try {
      await ref
          .read(analyticsAnnotationsRepositoryProvider)
          .save(
            siteId: siteId,
            annotationId: annotation?.id,
            date: _formatDate(result.date),
            note: result.note,
          );
      ref.invalidate(analyticsAnnotationsProvider(query));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('Note saved.', '注释已保存。'))),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.tr('Could not save note.', '保存注释失败。')),
          ),
        );
      }
    }
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    AnalyticsAnnotation annotation,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.tr('Delete this note?', '删除这条注释？')),
        content: Text(annotation.note),
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
    if (confirmed != true || !context.mounted) return;
    try {
      await ref
          .read(analyticsAnnotationsRepositoryProvider)
          .delete(siteId, annotation.id);
      ref.invalidate(analyticsAnnotationsProvider(query));
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.tr('Could not delete note.', '删除注释失败。')),
          ),
        );
      }
    }
  }
}

class _AnnotationEditor extends StatefulWidget {
  const _AnnotationEditor({
    required this.initialDate,
    required this.initialNote,
  });

  final DateTime initialDate;
  final String initialNote;

  @override
  State<_AnnotationEditor> createState() => _AnnotationEditorState();
}

class _AnnotationEditorState extends State<_AnnotationEditor> {
  late DateTime _selectedDate = widget.initialDate;
  late final TextEditingController _note = TextEditingController(
    text: widget.initialNote,
  );

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      context.tr(
        widget.initialNote.isEmpty ? 'Add an annotation' : 'Edit annotation',
        widget.initialNote.isEmpty ? '添加分析注释' : '编辑分析注释',
      ),
    ),
    content: SizedBox(
      width: 440,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          OutlinedButton.icon(
            onPressed: _pickDate,
            icon: const Icon(Icons.calendar_month_outlined),
            label: Text(_formatDate(_selectedDate)),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            autofocus: true,
            onChanged: (_) => setState(() {}),
            minLines: 2,
            maxLines: 4,
            maxLength: 500,
            decoration: InputDecoration(
              labelText: context.tr('What happened?', '发生了什么？'),
              hintText: context.tr(
                'e.g. Launched the autumn campaign',
                '例如：上线秋季营销活动',
              ),
              border: const OutlineInputBorder(),
            ),
          ),
          Text(
            context.tr(
              'Notes are visible to workspace members with access to this site.',
              '有权访问此站点的工作区成员都可以查看注释。',
            ),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.tr('Cancel', '取消')),
      ),
      FilledButton(
        onPressed: _note.text.trim().isEmpty
            ? null
            : () => Navigator.pop(
                context,
                _AnnotationDraft(date: _selectedDate, note: _note.text.trim()),
              ),
        child: Text(context.tr('Save note', '保存注释')),
      ),
    ],
  );

  Future<void> _pickDate() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(today.year + 5, 12, 31),
      helpText: context.tr('Choose event date', '选择事件日期'),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }
}

class _AnnotationDraft {
  const _AnnotationDraft({required this.date, required this.note});
  final DateTime date;
  final String note;
}

class _AnnotationError extends StatelessWidget {
  const _AnnotationError({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.red),
            const SizedBox(height: 8),
            Text(context.tr('Could not load annotations.', '无法加载分析注释。')),
            TextButton(
              onPressed: onRetry,
              child: Text(context.tr('Retry', '重试')),
            ),
          ],
        ),
      ),
    ),
  );
}

String _formatDate(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
