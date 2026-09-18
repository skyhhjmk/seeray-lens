import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_i18n.dart';
import '../application/analytics_segment.dart';

class SegmentFilterSelector extends ConsumerWidget {
  const SegmentFilterSelector({required this.siteId, super.key});

  final String siteId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final options = ref.watch(analyticsSegmentOptionsProvider(siteId));
    final selectedId = ref.watch(analyticsSegmentSelectionProvider(siteId));
    ref.listen(analyticsSegmentOptionsProvider(siteId), (previous, next) {
      next.whenData((segments) {
        final current = ref.read(analyticsSegmentSelectionProvider(siteId));
        if (current != null && !segments.any((item) => item.id == current)) {
          ref
              .read(analyticsSegmentSelectionProvider(siteId).notifier)
              .select(null);
        }
      });
    });

    return options.when(
      loading: () => const SizedBox(
        width: 42,
        height: 36,
        child: Center(
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
      error: (error, stack) => IconButton(
        tooltip: context.tr('Could not load segments. Retry.', '无法加载分群，点击重试。'),
        onPressed: () =>
            ref.invalidate(analyticsSegmentOptionsProvider(siteId)),
        icon: const Icon(Icons.filter_alt_off_outlined, color: Colors.white70),
      ),
      data: (segments) {
        final selected = segments
            .where((item) => item.id == selectedId)
            .firstOrNull;
        return PopupMenuButton<String>(
          tooltip: context.tr('Filter reports by segment', '按分群筛选报表'),
          onSelected: (value) => ref
              .read(analyticsSegmentSelectionProvider(siteId).notifier)
              .select(value.isEmpty ? null : value),
          itemBuilder: (context) => [
            PopupMenuItem(
              value: '',
              child: Row(
                children: [
                  Icon(
                    selectedId == null ? Icons.check : Icons.people_outline,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(context.tr('All visitors', '全部访客')),
                ],
              ),
            ),
            for (final segment in segments)
              PopupMenuItem(
                value: segment.id,
                child: Row(
                  children: [
                    Icon(
                      segment.id == selectedId
                          ? Icons.check
                          : Icons.groups_outlined,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        segment.name,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
          ],
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.filter_alt_outlined,
                  size: 18,
                  color: Colors.white,
                ),
                const SizedBox(width: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 180),
                  child: Text(
                    selected?.name ?? context.tr('All visitors', '全部访客'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
                const Icon(Icons.arrow_drop_down, color: Colors.white),
              ],
            ),
          ),
        );
      },
    );
  }
}
