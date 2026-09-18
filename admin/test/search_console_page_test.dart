import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seeray_lens_admin/core/network/seeray_api.dart';
import 'package:seeray_lens_admin/features/analytics/presentation/search_console_page.dart';
import 'package:seeray_lens_admin/features/auth/application/auth_controller.dart';

void main() {
  testWidgets(
    'shows live Search Console reports and verifies property access',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = _SearchConsoleApi();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [apiProvider.overrideWithValue(api)],
          child: const MaterialApp(
            locale: Locale('en'),
            supportedLocales: [Locale('en')],
            home: SearchConsolePage(siteId: 'site-1', embedded: true),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      expect(find.text('Google Search performance'), findsOneWidget);
      expect(api.lastDimension, 'query');
      expect(find.text('Access verified'), findsNothing);
      await tester.tap(find.text('Test access'));
      await tester.pumpAndSettle();
      expect(find.text('Access verified'), findsOneWidget);
      expect(find.textContaining('siteOwner'), findsOneWidget);

      await tester.ensureVisible(find.text('privacy analytics'));
      await tester.pumpAndSettle();
      expect(find.text('privacy analytics'), findsOneWidget);
      expect(find.text('1250'), findsOneWidget);

      await tester.drag(find.byType(Scrollable).first, const Offset(0, 1000));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Daily trend'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Daily trend'));
      await tester.pumpAndSettle();
      expect(api.lastDimension, 'date');
      expect(find.byType(CustomPaint), findsWidgets);
    },
  );

  testWidgets('saves an edited property using the typed property API', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = _SearchConsoleApi();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiProvider.overrideWithValue(api)],
        child: const MaterialApp(
          locale: Locale('en'),
          supportedLocales: [Locale('en')],
          home: SearchConsolePage(siteId: 'site-1', embedded: true),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'https://www.example.com/');
    await tester.tap(find.text('Save property'));
    await tester.pumpAndSettle();

    expect(api.savedProperty, 'https://www.example.com/');
    expect(find.text('Property saved.'), findsOneWidget);
  });
}

class _SearchConsoleApi extends SeeRayApi {
  _SearchConsoleApi() : super(baseUrl: 'https://lens.example.test');

  String? lastDimension;
  String? savedProperty;

  @override
  Future<dynamic> request(
    String method,
    String path, {
    Object? body,
    bool retried = false,
  }) async {
    final uri = Uri.parse(path);
    if (uri.path.endsWith('/search-console/property') && method == 'GET') {
      return {
        'configured': true,
        'propertyUrl': 'sc-domain:example.com',
        'updatedAt': '2026-09-18T00:00:00Z',
        'credentialMode': 'Credentials are supplied by server ADC.',
        'canManage': true,
      };
    }
    if (uri.path.endsWith('/search-console/property') && method == 'PUT') {
      savedProperty = (body as Map)['propertyUrl'] as String;
      return {
        'configured': true,
        'propertyUrl': savedProperty,
        'credentialMode': 'Credentials are supplied by server ADC.',
        'canManage': true,
      };
    }
    if (uri.path.endsWith('/search-console/validate')) {
      return {
        'accessible': true,
        'propertyUrl': 'sc-domain:example.com',
        'permissionLevel': 'siteOwner',
        'message': 'Search Console access verified.',
      };
    }
    if (uri.path.endsWith('/search-console/report')) {
      lastDimension = uri.queryParameters['dimension'];
      final dimension = lastDimension!;
      return {
        'propertyUrl': 'sc-domain:example.com',
        'from': uri.queryParameters['from'],
        'to': uri.queryParameters['to'],
        'dimension': dimension,
        'clicks': 1250,
        'impressions': 24000,
        'ctr': 0.052,
        'averagePosition': 7.3,
        'aggregationType': 'byProperty',
        'rows': [
          {
            'key': dimension == 'date' ? '2026-09-15' : 'privacy analytics',
            'clicks': 81,
            'impressions': 1840,
            'ctr': 0.044,
            'position': 7.3,
          },
        ],
        'mayBeTruncated': false,
        'dataLimitNote':
            'Search Analytics API results may omit lower-ranked rows.',
      };
    }
    fail('Unexpected request: $method $path');
  }
}
