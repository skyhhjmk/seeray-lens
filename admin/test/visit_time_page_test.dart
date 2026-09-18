import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seeray_lens_admin/core/network/seeray_api.dart';
import 'package:seeray_lens_admin/features/analytics/presentation/visit_time_page.dart';
import 'package:seeray_lens_admin/features/auth/application/auth_controller.dart';

void main() {
  testWidgets('shows visit totals and the busiest local-time cell', (
    tester,
  ) async {
    final api = _VisitTimeApi();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiProvider.overrideWithValue(api)],
        child: const MaterialApp(home: VisitTimePage(siteId: 'site-1')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Visits by weekday and hour'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('Monday at 09:00 · 3 visits'), findsOneWidget);
    expect(find.byTooltip('Mon 09:00 · 3 visits'), findsOneWidget);
    expect(
      api.paths.any((path) => path.contains('/analytics/visit-time?')),
      isTrue,
    );
  });
}

class _VisitTimeApi extends SeeRayApi {
  _VisitTimeApi() : super(baseUrl: 'https://lens.example.test');

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
    if (path.contains('/analytics/visit-time')) {
      return [
        {'dayOfWeek': 0, 'hour': 9, 'sessions': 3},
      ];
    }
    return const <dynamic>[];
  }
}
