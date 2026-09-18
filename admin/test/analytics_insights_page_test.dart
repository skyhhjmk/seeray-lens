import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seeray_lens_admin/core/network/seeray_api.dart';
import 'package:seeray_lens_admin/features/analytics/presentation/analytics_insights_page.dart';
import 'package:seeray_lens_admin/features/auth/application/auth_controller.dart';

void main() {
  testWidgets('shows period context, key metrics, and ranked insight changes', (
    tester,
  ) async {
    final api = _InsightsApi();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiProvider.overrideWithValue(api)],
        child: const MaterialApp(
          home: AnalyticsInsightsPage(siteId: 'site-1', embedded: true),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Insights'), findsOneWidget);
    expect(find.textContaining('Compared with:'), findsOneWidget);
    expect(find.text('Pages'), findsOneWidget);
    expect(find.text('/pricing'), findsOneWidget);
    expect(find.textContaining('30 → 45'), findsOneWidget);
    expect(find.text('Acquisition'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Events'),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Events'), findsOneWidget);
    expect(find.text('Signup'), findsOneWidget);
    expect(
      api.paths.any((path) => path.contains('/analytics/insights?')),
      isTrue,
    );
  });

  testWidgets('explains when changes do not meet volume thresholds', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiProvider.overrideWithValue(_InsightsApi(empty: true))],
        child: const MaterialApp(
          home: AnalyticsInsightsPage(siteId: 'site-1', embedded: true),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text(
        'No changes met the volume and change thresholds for this period.',
      ),
      findsOneWidget,
    );
  });
}

class _InsightsApi extends SeeRayApi {
  _InsightsApi({this.empty = false})
    : super(baseUrl: 'https://lens.example.test');

  final bool empty;
  final paths = <String>[];

  @override
  Future<dynamic> request(
    String method,
    String path, {
    Object? body,
    bool retried = false,
  }) async {
    paths.add(path);
    if (path.endsWith('/segments')) return const <dynamic>[];
    final uri = Uri.parse(path);
    expect(uri.path, '/api/v1/sites/site-1/analytics/insights');
    final from = uri.queryParameters['from']!;
    final to = uri.queryParameters['to']!;
    final currentStart = DateTime.parse(from);
    final currentEnd = DateTime.parse(to);
    final periodDays = currentEnd.difference(currentStart).inDays + 1;
    String date(DateTime value) =>
        '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
    return {
      'from': from,
      'to': to,
      'previousFrom': date(currentStart.subtract(Duration(days: periodDays))),
      'previousTo': date(currentStart.subtract(const Duration(days: 1))),
      'metrics': [
        {
          'key': 'page_views',
          'label': 'Page views',
          'current': 45,
          'previous': 30,
          'delta': 15,
          'percentChange': 50,
        },
        {
          'key': 'unique_visitors',
          'label': 'Unique visitors',
          'current': 40,
          'previous': 30,
          'delta': 10,
          'percentChange': 33.3,
        },
        {
          'key': 'sessions',
          'label': 'Sessions',
          'current': 40,
          'previous': 30,
          'delta': 10,
          'percentChange': 33.3,
        },
      ],
      'changes': empty
          ? <Map<String, dynamic>>[]
          : [
              {
                'category': 'page',
                'label': '/pricing',
                'metric': 'Page views',
                'current': 45,
                'previous': 30,
                'delta': 15,
                'percentChange': 50,
                'direction': 'increase',
              },
              {
                'category': 'acquisition',
                'label': 'launch',
                'detail': 'campaign · newsletter / email · launch',
                'metric': 'Sessions',
                'current': 30,
                'previous': 15,
                'delta': 15,
                'percentChange': 100,
                'direction': 'increase',
              },
              {
                'category': 'event',
                'label': 'Signup',
                'metric': 'Events',
                'current': 30,
                'previous': 15,
                'delta': 15,
                'percentChange': 100,
                'direction': 'increase',
              },
            ],
    };
  }
}
