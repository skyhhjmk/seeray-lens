import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seeray_lens_admin/core/network/seeray_api.dart';
import 'package:seeray_lens_admin/features/analytics/presentation/crash_analytics_page.dart';
import 'package:seeray_lens_admin/features/auth/application/auth_controller.dart';

void main() {
  testWidgets('shows privacy-safe empty state and links to the setup surface', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiProvider.overrideWithValue(_CrashAnalyticsApi())],
        child: const MaterialApp(
          home: CrashAnalyticsPage(siteId: 'site-1', embedded: true),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Crash analytics'), findsOneWidget);
    expect(find.text('No browser errors in this period'), findsOneWidget);
    expect(find.textContaining('visitor/session IDs'), findsOneWidget);
    expect(find.text('View setup instructions'), findsOneWidget);
  });
}

class _CrashAnalyticsApi extends SeeRayApi {
  _CrashAnalyticsApi() : super(baseUrl: 'https://lens.example.test');

  @override
  Future<dynamic> request(
    String method,
    String path, {
    Object? body,
    bool retried = false,
  }) async {
    expect(method, 'GET');
    final uri = Uri.parse(path);
    expect(uri.path, '/api/v1/sites/site-1/analytics/crashes');
    return {
      'from': uri.queryParameters['from'],
      'to': uri.queryParameters['to'],
      'occurrences': 0,
      'issueCount': 0,
      'rows': <Map<String, dynamic>>[],
      'hasMore': false,
    };
  }
}
