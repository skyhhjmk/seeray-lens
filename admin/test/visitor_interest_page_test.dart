import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seeray_lens_admin/core/network/seeray_api.dart';
import 'package:seeray_lens_admin/features/analytics/presentation/visitor_interest_page.dart';
import 'package:seeray_lens_admin/features/auth/application/auth_controller.dart';

void main() {
  testWidgets('explains period frequency and shows engagement distributions', (
    tester,
  ) async {
    final api = _VisitorInterestApi();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiProvider.overrideWithValue(api)],
        child: const MaterialApp(home: VisitorInterestPage(siteId: 'site-1')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Visitor engagement'), findsOneWidget);
    expect(find.text('Visits per visitor'), findsOneWidget);
    expect(find.text('Pages per visit'), findsWidgets);
    expect(find.text('Tracker records per visit'), findsOneWidget);
    expect(find.text('Visit duration'), findsOneWidget);
    expect(find.textContaining('only one of their visits'), findsOneWidget);
    expect(find.text('42s'), findsOneWidget);
    expect(
      api.paths.any((path) => path.contains('/analytics/visitor-interest?')),
      isTrue,
    );
  });
}

class _VisitorInterestApi extends SeeRayApi {
  _VisitorInterestApi() : super(baseUrl: 'https://lens.example.test');

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
    if (path.contains('/analytics/visitor-interest')) {
      return {
        'visitors': 2,
        'sessions': 3,
        'pageViews': 5,
        'events': 7,
        'averageSessionDurationMs': 42000,
        'frequency': [
          {'visits': '1', 'visitors': 1, 'sessions': 1},
          {'visits': '2', 'visitors': 1, 'sessions': 2},
        ],
        'pageViewsPerSession': [
          {'metric': 'page_views', 'band': '1', 'sessions': 2},
          {'metric': 'page_views', 'band': '3–5', 'sessions': 1},
        ],
        'eventsPerSession': [
          {'metric': 'events', 'band': '1–2', 'sessions': 2},
          {'metric': 'events', 'band': '3–5', 'sessions': 1},
        ],
        'durationPerSession': [
          {'metric': 'duration', 'band': '<10s', 'sessions': 1},
          {'metric': 'duration', 'band': '30–<60s', 'sessions': 2},
        ],
      };
    }
    return const <dynamic>[];
  }
}
