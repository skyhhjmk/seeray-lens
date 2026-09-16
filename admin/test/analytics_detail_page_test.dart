import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seeray_lens_admin/core/network/seeray_api.dart';
import 'package:seeray_lens_admin/features/analytics/presentation/analytics_detail_page.dart';
import 'package:seeray_lens_admin/features/auth/application/auth_controller.dart';

void main() {
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
