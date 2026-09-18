import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_i18n.dart';
import 'analytics_controller.dart';

enum AnalyticsPeriod { realtime, last7Days, today, last30Days, custom }

class AnalyticsRangeState {
  const AnalyticsRangeState({required this.period, required this.range});

  final AnalyticsPeriod period;
  final AnalyticsDateRange range;
}

final analyticsRangeProvider =
    NotifierProvider.family<
      AnalyticsRangeNotifier,
      AnalyticsRangeState,
      String
    >(AnalyticsRangeNotifier.new);

class AnalyticsRangeNotifier extends Notifier<AnalyticsRangeState> {
  AnalyticsRangeNotifier(this.siteId);

  final String siteId;

  @override
  AnalyticsRangeState build() => AnalyticsRangeState(
    period: AnalyticsPeriod.realtime,
    range: analyticsLastDays(1),
  );

  void setRange(AnalyticsRangeState value) => state = value;
}

AnalyticsDateRange analyticsLastDays(int days) {
  final today = analyticsDateOnly(DateTime.now());
  return AnalyticsDateRange(today.subtract(Duration(days: days - 1)), today);
}

DateTime analyticsDateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

const int analyticsCohortMaximumRangeDays = 3660;

String analyticsRangeLabel(BuildContext context, AnalyticsRangeState state) {
  return switch (state.period) {
    AnalyticsPeriod.realtime => context.tr('Realtime', '实时'),
    AnalyticsPeriod.last7Days => context.tr('Last 7 days', '最近 7 天'),
    AnalyticsPeriod.today => context.tr('Today', '今天'),
    AnalyticsPeriod.last30Days => context.tr('Last 30 days', '最近 30 天'),
    AnalyticsPeriod.custom =>
      '${state.range.fromQuery} – ${state.range.toQuery}',
  };
}

Future<AnalyticsRangeState?> showAnalyticsRangePicker(
  BuildContext context,
  AnalyticsRangeState current, {
  int? maximumRangeDays,
}) async {
  final selection = await showModalBottomSheet<_RangeSelection>(
    context: context,
    showDragHandle: true,
    builder: (context) => _RangeSheet(current: current),
  );
  if (selection == null) return null;
  if (!context.mounted) return null;
  if (selection.custom) {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(
        start: current.range.from,
        end: current.range.to,
      ),
      helpText: maximumRangeDays == null
          ? context.tr('Select reporting range', '选择统计日期范围')
          : context.tr(
              'Select a range of up to $maximumRangeDays days',
              '请选择不超过 $maximumRangeDays 天的范围',
            ),
    );
    if (picked == null) return null;
    if (!context.mounted) return null;
    final selectedDays =
        DateTime.utc(picked.end.year, picked.end.month, picked.end.day)
            .difference(
              DateTime.utc(
                picked.start.year,
                picked.start.month,
                picked.start.day,
              ),
            )
            .inDays +
        1;
    if (maximumRangeDays != null && selectedDays > maximumRangeDays) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.tr(
              'Cohort reports support ranges up to $maximumRangeDays days.',
              '队列报告最多支持 $maximumRangeDays 天的日期范围。',
            ),
          ),
        ),
      );
      return null;
    }
    return AnalyticsRangeState(
      period: AnalyticsPeriod.custom,
      range: AnalyticsDateRange(
        analyticsDateOnly(picked.start),
        analyticsDateOnly(picked.end),
      ),
    );
  }
  return AnalyticsRangeState(period: selection.period, range: selection.range!);
}

class _RangeSelection {
  const _RangeSelection.preset(this.period, this.range) : custom = false;
  const _RangeSelection.custom()
    : period = AnalyticsPeriod.custom,
      range = null,
      custom = true;

  final AnalyticsPeriod period;
  final AnalyticsDateRange? range;
  final bool custom;
}

class _RangeSheet extends StatelessWidget {
  const _RangeSheet({required this.current});

  final AnalyticsRangeState current;

  @override
  Widget build(BuildContext context) {
    final options = [
      (
        AnalyticsPeriod.realtime,
        context.tr('Realtime', '实时'),
        analyticsLastDays(1),
      ),
      (
        AnalyticsPeriod.last7Days,
        context.tr('Last 7 days', '最近 7 天'),
        analyticsLastDays(7),
      ),
      (AnalyticsPeriod.today, context.tr('Today', '今天'), analyticsLastDays(1)),
      (
        AnalyticsPeriod.last30Days,
        context.tr('Last 30 days', '最近 30 天'),
        analyticsLastDays(30),
      ),
    ];
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.tr('Reporting period', '统计周期'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            ...options.map(
              (option) => ListTile(
                leading: Icon(
                  current.period == option.$1
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                ),
                title: Text(option.$2),
                onTap: () => Navigator.pop(
                  context,
                  _RangeSelection.preset(option.$1, option.$3),
                ),
              ),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.date_range_outlined),
              title: Text(context.tr('Custom range', '自定义范围')),
              subtitle: Text(analyticsRangeLabel(context, current)),
              onTap: () =>
                  Navigator.pop(context, const _RangeSelection.custom()),
            ),
          ],
        ),
      ),
    );
  }
}
