import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seeray_lens_admin/core/network/seeray_api.dart';
import 'package:seeray_lens_admin/features/analytics/presentation/realtime_page.dart';
import 'package:seeray_lens_admin/features/auth/application/auth_controller.dart';

void main() {
  testWidgets('shows active visits and expands their recent action trail', (
    tester,
  ) async {
    final api = _LiveApi();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiProvider.overrideWithValue(api)],
        child: const MaterialApp(
          home: RealtimePage(siteId: 'site-1', embedded: true),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(api.lastPath, contains('/analytics/realtime?windowMinutes=30'));
    expect(find.text('Live visitors'), findsOneWidget);
    expect(find.text('Active visitors'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.textContaining('Visitor 12345678'), findsOneWidget);
    expect(find.text('Pricing overview'), findsNWidgets(2));

    await tester.tap(find.byType(ExpansionTile).first);
    await tester.pumpAndSettle();

    expect(find.text('Recent activity'), findsOneWidget);
    expect(find.textContaining('page_view ·'), findsOneWidget);
    expect(find.textContaining('Entry: /pricing'), findsOneWidget);
  });
}

class _LiveApi extends SeeRayApi {
  _LiveApi() : super(baseUrl: 'https://lens.example.test');

  String? lastPath;

  @override
  Future<dynamic> request(
    String method,
    String path, {
    Object? body,
    bool retried = false,
  }) async {
    lastPath = path;
    final now = DateTime.now().toUtc().toIso8601String();
    final sharedVisit = <String, dynamic>{
      'visitorId': '12345678-1234-4234-8234-123456789012',
      'sessionId': '22345678-1234-4234-8234-123456789012',
      'startedAt': now,
      'lastActivityAt': now,
      'events': 2,
      'pageViews': 1,
      'entryPage': '/pricing',
      'lastEventType': 'page_view',
      'currentPage': '/pricing',
      'currentTitle': 'Pricing overview',
      'countryCode': 'US',
      'region': 'California',
      'city': 'San Francisco',
      'browser': 'Chrome',
      'operatingSystem': 'Linux',
      'deviceType': 'desktop',
      'language': 'en-US',
      'durationMs': 1800,
      'uniqueIdentity': true,
      'actions': [
        {
          'at': now,
          'eventType': 'page_view',
          'path': '/pricing',
          'title': 'Pricing overview',
        },
      ],
    };
    return [
      sharedVisit,
      {
        ...sharedVisit,
        'visitorId': '32345678-1234-4234-8234-123456789012',
        'sessionId': '42345678-1234-4234-8234-123456789012',
        'uniqueIdentity': false,
      },
    ];
  }
}
