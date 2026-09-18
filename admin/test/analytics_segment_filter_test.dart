import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seeray_lens_admin/core/network/seeray_api.dart';
import 'package:seeray_lens_admin/features/analytics/application/analytics_controller.dart';
import 'package:seeray_lens_admin/features/analytics/application/analytics_segment.dart';
import 'package:seeray_lens_admin/features/analytics/presentation/segment_filter_selector.dart';
import 'package:seeray_lens_admin/features/auth/application/auth_controller.dart';

void main() {
  testWidgets('selects a named audience from the report filter menu', (
    tester,
  ) async {
    final api = _AnalyticsApi();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiProvider.overrideWithValue(api)],
        child: MaterialApp(
          home: Scaffold(
            appBar: AppBar(actions: [SegmentFilterSelector(siteId: 'site-1')]),
            body: Consumer(
              builder: (context, ref, child) => Text(
                ref.watch(analyticsSegmentSelectionProvider('site-1')) ??
                    'no-segment',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('All visitors').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pro visitors').last);
    await tester.pumpAndSettle();

    expect(find.text('segment-1'), findsOneWidget);
  });

  test('passes the selected segment to every dashboard report query', () async {
    final api = _AnalyticsApi();
    final container = ProviderContainer(
      overrides: [apiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);

    container
        .read(analyticsSegmentSelectionProvider('site-1').notifier)
        .select('segment-1');
    final query = AnalyticsDashboardQuery(
      'site-1',
      AnalyticsDateRange(DateTime(2026, 9, 1), DateTime(2026, 9, 7)),
      segmentId: 'segment-1',
    );
    await container.read(analyticsDashboardRangeProvider(query).future);

    expect(api.paths, hasLength(7));
    expect(
      api.paths.every((path) => path.contains('segmentId=segment-1')),
      isTrue,
    );
    expect(api.paths.every((path) => path.contains('from=2026-09-01')), isTrue);
    expect(api.paths.every((path) => path.contains('to=2026-09-07')), isTrue);
  });

  test('passes the selected segment to every behaviour report query', () async {
    final api = _AnalyticsApi();
    final container = ProviderContainer(
      overrides: [apiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);

    final query = AnalyticsDashboardQuery(
      'site-1',
      AnalyticsDateRange(DateTime(2026, 9, 1), DateTime(2026, 9, 7)),
      segmentId: 'segment-1',
    );
    await container.read(analyticsBehaviourProvider(query).future);

    expect(api.paths, hasLength(7));
    expect(
      api.paths.every((path) => path.contains('segmentId=segment-1')),
      isTrue,
    );
    expect(api.paths.every((path) => path.contains('from=2026-09-01')), isTrue);
    expect(api.paths.any((path) => path.contains('/site-search?')), isTrue);
    expect(api.paths.any((path) => path.contains('/content?')), isTrue);
    expect(api.paths.any((path) => path.contains('/web-vitals?')), isTrue);
  });

  test('visit-time report carries the selected range and segment', () async {
    final api = _AnalyticsApi();
    final container = ProviderContainer(
      overrides: [apiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);

    final query = AnalyticsDashboardQuery(
      'site-1',
      AnalyticsDateRange(DateTime(2026, 9, 1), DateTime(2026, 9, 7)),
      segmentId: 'segment-1',
    );
    final cells = await container.read(
      analyticsVisitTimeProvider(query).future,
    );

    expect(cells, isEmpty);
    expect(api.paths.single, contains('/analytics/visit-time?'));
    expect(api.paths.single, contains('from=2026-09-01'));
    expect(api.paths.single, contains('to=2026-09-07'));
    expect(api.paths.single, contains('segmentId=segment-1'));
  });
}

class _AnalyticsApi extends SeeRayApi {
  _AnalyticsApi() : super(baseUrl: 'https://lens.example.test');

  final paths = <String>[];

  @override
  Future<dynamic> request(
    String method,
    String path, {
    Object? body,
    bool retried = false,
  }) async {
    paths.add(path);
    if (path.endsWith('/segments')) {
      return [
        {'id': 'segment-1', 'name': 'Pro visitors', 'enabled': true},
      ];
    }
    if (path.contains('/overview')) {
      return {
        'pageViews': 4,
        'uniqueVisitors': 2,
        'sessions': 3,
        'bounceRate': 0.25,
        'averageSessionDurationMs': 12000,
      };
    }
    if (path.contains('/visitors')) {
      return {
        'uniqueVisitors': 2,
        'sessions': 3,
        'newSessions': 2,
        'returningSessions': 1,
        'bounceRate': 0.25,
        'averageSessionDurationMs': 12000,
      };
    }
    if (path.contains('/site-search')) {
      return {
        'searches': 0,
        'uniqueVisitors': 0,
        'sessions': 0,
        'zeroResultSearches': 0,
        'measuredResultSearches': 0,
        'terms': <dynamic>[],
      };
    }
    if (path.contains('/content')) {
      return {
        'impressions': 0,
        'interactions': 0,
        'uniqueVisitors': 0,
        'sessions': 0,
        'interactionRate': 0,
        'entries': <dynamic>[],
      };
    }
    if (path.contains('/web-vitals')) {
      return {'metrics': <dynamic>[], 'pages': <dynamic>[]};
    }
    return const <dynamic>[];
  }
}
