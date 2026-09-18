import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:seeray_lens_admin/core/network/seeray_api.dart';
import 'package:seeray_lens_admin/features/analytics/presentation/visitor_log_panel.dart';
import 'package:seeray_lens_admin/features/analytics/presentation/visitor_profile_page.dart';
import 'package:seeray_lens_admin/features/auth/application/auth_controller.dart';

void main() {
  testWidgets('opens an anonymous visitor profile from recent visits', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = _VisitorApi();
    final router = GoRouter(
      initialLocation: '/sites/site-1/visitors',
      routes: [
        GoRoute(
          path: '/sites/:siteId/visitors',
          builder: (context, state) => Scaffold(
            body: ListView(
              children: [
                VisitorLogPanel(siteId: state.pathParameters['siteId']!),
              ],
            ),
          ),
        ),
        GoRoute(
          path: '/sites/:siteId/visitors/:visitorId',
          builder: (context, state) => VisitorProfilePage(
            siteId: state.pathParameters['siteId']!,
            visitorId: state.pathParameters['visitorId']!,
            embedded: true,
          ),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiProvider.overrideWithValue(api)],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('3456'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'no-match');
    await tester.pumpAndSettle();
    expect(find.textContaining('3456'), findsNothing);
    await tester.enterText(find.byType(TextField), 'visitor-123456');
    await tester.pumpAndSettle();
    expect(find.text('Visitor visitor-…3456'), findsOneWidget);
    await tester.tap(find.text('Visitor visitor-…3456'));
    await tester.pumpAndSettle();

    expect(find.text('Anonymous visitor'), findsOneWidget);
    expect(find.textContaining('/pricing'), findsWidgets);
    expect(find.text('Chrome'), findsOneWidget);
    expect(find.textContaining('product_interaction'), findsOneWidget);
    expect(api.profilePath, contains('/visitors/visitor-123456'));

    router.dispose();
  });
}

class _VisitorApi extends SeeRayApi {
  _VisitorApi();

  String? profilePath;

  @override
  Future<dynamic> request(
    String method,
    String path, {
    Object? body,
    bool retried = false,
  }) async {
    final route = Uri.parse(path).path;
    if (route.endsWith('/analytics/visitor-log')) {
      return [
        {
          'visitorId': 'visitor-123456',
          'startedAt': '2026-09-18T10:00:00Z',
          'lastActivityAt': '2026-09-18T10:03:00Z',
          'entryPage': '/pricing',
          'exitPage': '/checkout',
          'pageViews': 2,
          'events': 3,
          'durationMs': 180000,
          'bounce': false,
          'visitorType': 'returning',
        },
      ];
    }
    if (route.endsWith('/analytics/visitors/visitor-123456')) {
      profilePath = path;
      return {
        'visitorId': 'visitor-123456',
        'firstSeenAt': '2026-07-01T10:00:00Z',
        'lastSeenAt': '2026-09-18T10:03:00Z',
        'lifetimeSessions': 8,
        'rangeSessions': 1,
        'rangePageViews': 2,
        'rangeEvents': 3,
        'rangeBouncedSessions': 0,
        'averageSessionDurationMs': 180000,
        'sessions': [
          {
            'sessionId': 'session-abc123',
            'startedAt': '2026-09-18T10:00:00Z',
            'lastActivityAt': '2026-09-18T10:03:00Z',
            'entryPage': '/pricing',
            'exitPage': '/checkout',
            'pageViews': 2,
            'events': 3,
            'durationMs': 180000,
            'bounce': false,
            'visitorType': 'returning',
            'browser': 'Chrome',
            'operatingSystem': 'Linux',
            'deviceType': 'desktop',
            'language': 'en-US',
            'countryCode': 'US',
            'region': 'California',
            'city': 'San Francisco',
            'referrerHost': 'search.example',
            'campaignSource': 'newsletter',
            'campaignMedium': 'email',
            'campaignName': 'September',
          },
        ],
        'hasMoreSessions': false,
        'actions': [
          {
            'at': '2026-09-18T10:02:00Z',
            'eventType': 'product_interaction',
            'path': '/checkout',
            'title': 'Checkout',
            'sessionId': 'session-abc123',
          },
          {
            'at': '2026-09-18T10:00:00Z',
            'eventType': 'page_view',
            'path': '/pricing',
            'title': 'Pricing',
            'sessionId': 'session-abc123',
          },
        ],
        'hasMoreActions': false,
      };
    }
    throw StateError('Unexpected API request: $method $path');
  }
}
