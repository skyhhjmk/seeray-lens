import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seeray_lens_admin/core/network/seeray_api.dart';
import 'package:seeray_lens_admin/features/analytics/presentation/analytics_detail_page.dart';
import 'package:seeray_lens_admin/features/auth/application/auth_controller.dart';

void main() {
  testWidgets('shows acquisition channels and campaign parameters', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiProvider.overrideWithValue(_AcquisitionApi())],
        child: const MaterialApp(
          home: AnalyticsDetailPage(
            siteId: 'site-1',
            view: AnalyticsView.acquisition,
            embedded: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Acquisition'), findsOneWidget);
    expect(find.text('Campaign'), findsOneWidget);
    expect(find.textContaining('Source: newsletter'), findsOneWidget);
    expect(find.textContaining('Term: buy'), findsOneWidget);
    expect(find.textContaining('Content: hero-card'), findsOneWidget);
    expect(find.text('Search engine'), findsOneWidget);
  });

  testWidgets('shows page, entry-exit, and drillable flow reports', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiProvider.overrideWithValue(_BehaviourApi())],
        child: const MaterialApp(
          home: AnalyticsDetailPage(
            siteId: 'site-1',
            view: AnalyticsView.behaviour,
            embedded: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Behaviour'), findsOneWidget);
    expect(find.text('Page titles'), findsOneWidget);
    expect(find.text('Pricing overview'), findsWidgets);
    expect(find.text('/pricing'), findsWidgets);
    await tester.scrollUntilVisible(
      find.text('Site search'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Site search'), findsOneWidget);
    expect(find.text('site_search'), findsNothing);
    expect(find.text('red shoes'), findsOneWidget);
    expect(find.text('No-result rate'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Content performance'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Content performance'), findsOneWidget);
    expect(find.text('home hero'), findsOneWidget);
    expect(find.text('summer campaign'), findsOneWidget);
    expect(find.text('Interaction rate'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Page performance · Web Vitals'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Page performance · Web Vitals'), findsOneWidget);
    expect(find.text('LCP p75'), findsOneWidget);
    expect(find.text('2.30 s'), findsNWidgets(2));
    expect(find.text('Entry pages'), findsOneWidget);
    expect(find.text('Exit pages'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Tracked events'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Tracked events'), findsOneWidget);
    expect(find.text('download'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('User flow'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('User flow'), findsOneWidget);
    expect(find.text('/landing'), findsWidgets);
    await tester.tap(find.text('/pricing').last);
    await tester.pumpAndSettle();
    expect(find.text('/checkout'), findsWidgets);
    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Step 2'))
          .selected,
      isTrue,
    );
  });

  testWidgets('configures goals from the goals report page', (tester) async {
    final api = _GoalApi();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiProvider.overrideWithValue(api)],
        child: const MaterialApp(
          home: AnalyticsDetailPage(
            siteId: 'site-1',
            view: AnalyticsView.goals,
            embedded: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Configured goals'), findsOneWidget);
    expect(find.text('No configured goals.'), findsOneWidget);
    await tester.tap(find.text('Create goal'));
    await tester.pumpAndSettle();

    expect(find.text('Create goal'), findsNWidgets(2));
    expect(find.text('Goal trigger'), findsOneWidget);
    expect(find.text('Event type'), findsOneWidget);
    await tester.enterText(find.byType(TextField).at(0), 'Signup completed');
    await tester.enterText(find.byType(TextField).at(1), 'signup');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(api.lastMethod, 'POST');
    expect(api.lastPath, '/api/v1/sites/site-1/goals');
    expect((api.lastBody as Map)['name'], 'Signup completed');
    expect((api.lastBody as Map)['triggerType'], 'event');
    expect((api.lastBody as Map)['eventType'], 'signup');
  });
}

class _AcquisitionApi extends SeeRayApi {
  _AcquisitionApi() : super(baseUrl: 'https://lens.example.test');

  @override
  Future<dynamic> request(
    String method,
    String path, {
    Object? body,
    bool retried = false,
  }) async {
    if (path.contains('/overview')) {
      return {
        'pageViews': 5,
        'uniqueVisitors': 4,
        'sessions': 5,
        'bounceRate': 0.4,
        'averageSessionDurationMs': 12000,
      };
    }
    if (path.contains('/timeseries') ||
        path.contains('/pages') ||
        path.contains('/events') ||
        path.contains('/goals')) {
      return [];
    }
    if (path.contains('/traffic')) {
      return [
        {
          'channel': 'campaign',
          'source': 'newsletter',
          'medium': 'email',
          'campaign': 'launch',
          'term': 'buy',
          'content': 'hero-card',
          'sessions': 3,
        },
        {'channel': 'search_engine', 'source': 'www.google.com', 'sessions': 2},
      ];
    }
    if (path.contains('/visitors')) {
      return {
        'uniqueVisitors': 4,
        'sessions': 5,
        'newSessions': 3,
        'returningSessions': 2,
        'bounceRate': 0.4,
        'averageSessionDurationMs': 12000,
      };
    }
    throw StateError('Unexpected request: $path');
  }
}

class _BehaviourApi extends SeeRayApi {
  _BehaviourApi() : super(baseUrl: 'https://lens.example.test');

  @override
  Future<dynamic> request(
    String method,
    String path, {
    Object? body,
    bool retried = false,
  }) async {
    if (path.contains('/page-titles')) {
      return [
        {'path': '/pricing', 'title': 'Pricing overview', 'pageViews': 17},
      ];
    }
    if (path.contains('/entry-exit')) {
      return [
        {
          'flow': 'entry',
          'path': '/pricing',
          'title': 'Pricing overview',
          'sessions': 8,
        },
        {
          'flow': 'exit',
          'path': '/pricing',
          'title': 'Pricing overview',
          'sessions': 3,
        },
      ];
    }
    if (path.contains('/events')) {
      return [
        {'eventType': 'download', 'count': 2},
      ];
    }
    if (path.contains('/site-search')) {
      return {
        'searches': 5,
        'uniqueVisitors': 3,
        'sessions': 4,
        'zeroResultSearches': 1,
        'measuredResultSearches': 4,
        'averageResultsCount': 8.5,
        'terms': [
          {
            'keyword': 'red shoes',
            'category': 'catalog',
            'searches': 2,
            'uniqueVisitors': 2,
            'sessions': 2,
            'zeroResultSearches': 1,
            'measuredResultSearches': 2,
            'averageResultsCount': 3.0,
          },
        ],
      };
    }
    if (path.contains('/content')) {
      return {
        'impressions': 20,
        'interactions': 4,
        'uniqueVisitors': 12,
        'sessions': 14,
        'interactionRate': 0.2,
        'entries': [
          {
            'name': 'home hero',
            'piece': 'summer campaign',
            'target': '/summer',
            'impressions': 20,
            'interactions': 4,
            'uniqueVisitors': 12,
            'sessions': 14,
            'interactionRate': 0.2,
          },
        ],
      };
    }
    if (path.contains('/web-vitals')) {
      return {
        'metrics': [
          {
            'metric': 'LCP',
            'samples': 3,
            'uniqueVisitors': 3,
            'sessions': 3,
            'p75': 2300,
            'good': 2,
            'needsImprovement': 1,
            'poor': 0,
          },
        ],
        'pages': [
          {
            'metric': 'LCP',
            'pagePath': '/pricing',
            'samples': 3,
            'uniqueVisitors': 3,
            'sessions': 3,
            'p75': 2300,
            'good': 2,
            'needsImprovement': 1,
            'poor': 0,
          },
        ],
      };
    }
    if (path.contains('/user-flow')) {
      return [
        {
          'step': 1,
          'sourcePath': '/landing',
          'targetPath': '/pricing',
          'sessions': 8,
        },
        {
          'step': 2,
          'sourcePath': '/pricing',
          'targetPath': '/checkout',
          'sessions': 5,
        },
        {
          'step': 3,
          'sourcePath': '/checkout',
          'targetPath': null,
          'sessions': 3,
        },
      ];
    }
    return const <dynamic>[];
  }
}

class _GoalApi extends SeeRayApi {
  _GoalApi() : super(baseUrl: 'https://lens.example.test');

  String? lastMethod;
  String? lastPath;
  Object? lastBody;

  @override
  Future<dynamic> request(
    String method,
    String path, {
    Object? body,
    bool retried = false,
  }) async {
    if (method != 'GET') {
      lastMethod = method;
      lastPath = path;
      lastBody = body;
    }
    if (path.endsWith('/goals')) return const <dynamic>[];
    if (path.contains('/analytics/overview')) {
      return {
        'pageViews': 0,
        'uniqueVisitors': 0,
        'sessions': 0,
        'bounceRate': 0,
        'averageSessionDurationMs': 0,
      };
    }
    if (path.contains('/analytics/visitors')) {
      return {
        'uniqueVisitors': 0,
        'sessions': 0,
        'newSessions': 0,
        'returningSessions': 0,
        'bounceRate': 0,
        'averageSessionDurationMs': 0,
      };
    }
    return const <dynamic>[];
  }
}
