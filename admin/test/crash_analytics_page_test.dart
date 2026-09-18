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
    expect(find.text('No client errors in this period'), findsOneWidget);
    expect(find.textContaining('visitor/session IDs'), findsOneWidget);
    expect(find.text('View setup instructions'), findsOneWidget);
  });

  testWidgets('separates Android native errors from browser errors', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiProvider.overrideWithValue(
            _CrashAnalyticsApi(
              rows: [
                {
                  'fingerprint': '0123456789abcdef',
                  'errorName': 'IllegalStateException',
                  'message': 'failed safely',
                  'sourcePath': 'CheckoutActivity.kt',
                  'line': 48,
                  'column': null,
                  'functionName': 'CheckoutActivity.onCreate',
                  'occurrences': 3,
                  'affectedPages': 1,
                  'browsers': 'Other',
                  'platforms': 'android',
                  'firstSeen': '2026-09-19T01:00:00Z',
                  'lastSeen': '2026-09-19T02:00:00Z',
                },
              ],
            ),
          ),
        ],
        child: const MaterialApp(
          home: CrashAnalyticsPage(siteId: 'site-1', embedded: true),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Platforms'), findsOneWidget);
    expect(find.text('android'), findsOneWidget);
    expect(find.text('IllegalStateException'), findsOneWidget);
  });
}

class _CrashAnalyticsApi extends SeeRayApi {
  _CrashAnalyticsApi({this.rows = const []})
    : super(baseUrl: 'https://lens.example.test');

  final List<Map<String, dynamic>> rows;

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
      'occurrences': rows.fold<int>(
        0,
        (sum, row) => sum + (row['occurrences'] as int),
      ),
      'issueCount': rows.length,
      'rows': rows,
      'hasMore': false,
    };
  }
}
