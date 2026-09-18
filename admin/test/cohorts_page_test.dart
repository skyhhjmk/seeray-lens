import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seeray_lens_admin/core/network/seeray_api.dart';
import 'package:seeray_lens_admin/features/analytics/application/analytics_segment.dart';
import 'package:seeray_lens_admin/features/analytics/presentation/cohorts_page.dart';
import 'package:seeray_lens_admin/features/auth/application/auth_controller.dart';

void main() {
  testWidgets('shows a retention matrix and offers a practical window switch', (
    tester,
  ) async {
    final api = _CohortApi();
    final container = ProviderContainer(
      overrides: [apiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: CohortsPage(siteId: 'site-1', embedded: true),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Cohort analysis'), findsOneWidget);
    expect(find.text('Measure'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Weighted by cohort size; incomplete periods are excluded.'),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const ValueKey('cohort-trend-chart')), findsOneWidget);
    expect(find.text('P0 · 100.0%'), findsOneWidget);
    expect(find.text('P1 · 60.0%'), findsOneWidget);
    expect(api.paths.last, contains('period=week'));
    expect(api.paths.last, contains('periods=8'));

    await tester.tap(find.text('4 weeks'));
    await tester.pumpAndSettle();
    expect(api.paths.last, contains('periods=4'));

    await tester.tap(find.byType(DropdownButtonFormField<String>).at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Monthly').last);
    await tester.pumpAndSettle();
    expect(api.paths.last, contains('period=month'));
    expect(api.paths.last, contains('periods=6'));

    await tester.tap(find.byType(DropdownButtonFormField<String>).at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yearly').last);
    await tester.pumpAndSettle();
    expect(api.paths.last, contains('period=year'));
    expect(api.paths.last, contains('periods=5'));

    container
        .read(analyticsSegmentSelectionProvider('site-1').notifier)
        .select('segment-1');
    await tester.pumpAndSettle();
    expect(api.paths.last, contains('segmentId=segment-1'));
    expect(
      find.text('Filtered by the site segment selected above.'),
      findsOneWidget,
    );

    await tester.tap(find.byType(DropdownButtonFormField<String>).at(2));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Goal conversions').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>).at(3));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Signup goal').last);
    await tester.pumpAndSettle();
    expect(api.lastCohortQuery?.queryParameters['metric'], 'goal_conversions');
    expect(api.lastCohortQuery?.queryParameters['metricGoalId'], 'goal-1');
    expect(api.lastCohortQuery?.queryParameters['basis'], 'first_visit');
    await tester.scrollUntilVisible(
      find.byType(DataTable),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('20%'), findsOneWidget);
    expect(find.text('1 次'), findsOneWidget);
  });

  testWidgets('applies exact custom cohort lengths through 3660 days', (
    tester,
  ) async {
    final api = _CohortApi();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiProvider.overrideWithValue(api)],
        child: const MaterialApp(
          home: CohortsPage(siteId: 'site-1', embedded: true),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButtonFormField<String>).at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Custom length').last);
    await tester.pumpAndSettle();
    expect(find.text('Days per cohort period'), findsOneWidget);

    await tester.ensureVisible(find.text('730 d'));
    await tester.tap(find.text('730 d'));
    await tester.pumpAndSettle();
    expect(api.lastCohortQuery!.queryParameters['periodDays'], '730');

    await tester.enterText(
      find.byKey(const ValueKey('cohort-period-days-input')),
      '3660',
    );
    await tester.tap(find.byKey(const ValueKey('apply-cohort-period-days')));
    await tester.pumpAndSettle();
    expect(api.lastCohortQuery!.queryParameters['periodDays'], '3660');

    await tester.enterText(
      find.byKey(const ValueKey('cohort-period-days-input')),
      '3661',
    );
    await tester.tap(find.byKey(const ValueKey('apply-cohort-period-days')));
    await tester.pumpAndSettle();
    expect(find.text('Enter a whole number from 1 to 3660.'), findsOneWidget);
    expect(api.lastCohortQuery!.queryParameters['periodDays'], '3660');
  });

  testWidgets('builds a cohort around a configured goal conversion', (
    tester,
  ) async {
    final api = _CohortApi();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiProvider.overrideWithValue(api)],
        child: const MaterialApp(
          home: CohortsPage(siteId: 'site-1', embedded: true),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('First goal conversion').last);
    await tester.pumpAndSettle();
    expect(find.text('Conversion goal'), findsOneWidget);

    await tester.tap(find.byType(DropdownButtonFormField<String>).at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Monthly').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Signup goal').last);
    await tester.pumpAndSettle();

    expect(api.lastCohortQuery?.queryParameters['basis'], 'goal_conversion');
    expect(api.lastCohortQuery?.queryParameters['goalId'], 'goal-1');
    expect(api.lastCohortQuery?.queryParameters['period'], 'month');
    expect(api.lastCohortQuery?.queryParameters['periods'], '6');

    await tester.tap(find.byType(DropdownButtonFormField<String>).at(2));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Visits').last);
    await tester.pumpAndSettle();
    expect(api.lastCohortQuery?.queryParameters['basis'], 'goal_conversion');
    expect(api.lastCohortQuery?.queryParameters['metric'], 'visits');
    expect(api.lastCohortQuery?.queryParameters['goalId'], 'goal-1');
    await tester.scrollUntilVisible(
      find.text('9'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('9'), findsOneWidget);

    await tester.drag(find.byType(ListView).first, const Offset(0, 1200));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>).at(2));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Goal value').last);
    await tester.pumpAndSettle();
    expect(api.lastCohortQuery?.queryParameters['metric'], 'goal_value');
    expect(
      api.lastCohortQuery?.queryParameters.containsKey('metricGoalId'),
      isFalse,
    );
    await tester.scrollUntilVisible(
      find.text('12.5'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('12.5'), findsOneWidget);
  });
}

class _CohortApi extends SeeRayApi {
  _CohortApi() : super(baseUrl: 'https://lens.example.test');

  final paths = <String>[];
  Uri? lastCohortQuery;

  @override
  Future<dynamic> request(
    String method,
    String path, {
    Object? body,
    bool retried = false,
  }) async {
    paths.add(path);
    final uri = Uri.parse(path);
    if (uri.path.endsWith('/goals')) {
      return [
        {
          'id': 'goal-1',
          'name': 'Signup goal',
          'enabled': true,
          'fixedValue': 0,
        },
      ];
    }
    if (uri.path.endsWith('/analytics/cohorts')) lastCohortQuery = uri;
    return [
      {
        'cohortPeriod': '2026-07-06',
        'periodIndex': 0,
        'cohortSize': 5,
        'retainedVisitors': 5,
        'retentionRate': 1.0,
        'goalConversions': 1,
        'goalConvertedVisitors': 1,
        'goalValue': 12.5,
        'visits': 9,
        'complete': true,
      },
      {
        'cohortPeriod': '2026-07-06',
        'periodIndex': 1,
        'cohortSize': 5,
        'retainedVisitors': 3,
        'retentionRate': 0.6,
        'goalConversions': 2,
        'goalConvertedVisitors': 2,
        'goalValue': 25.0,
        'visits': 6,
        'complete': true,
      },
      {
        'cohortPeriod': '2026-07-06',
        'periodIndex': 2,
        'cohortSize': 5,
        'retainedVisitors': 0,
        'retentionRate': 0,
        'goalConversions': 0,
        'goalConvertedVisitors': 0,
        'goalValue': 0,
        'visits': 0,
        'complete': false,
      },
    ];
  }
}
