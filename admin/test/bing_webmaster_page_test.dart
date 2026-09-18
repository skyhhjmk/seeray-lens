import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seeray_lens_admin/core/network/seeray_api.dart';
import 'package:seeray_lens_admin/features/analytics/presentation/bing_webmaster_page.dart';
import 'package:seeray_lens_admin/features/auth/application/auth_controller.dart';

void main() {
  testWidgets('shows Bing reports, tests access and saves a rotated key', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = _BingWebmasterApi();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiProvider.overrideWithValue(api)],
        child: const MaterialApp(
          locale: Locale('en'),
          supportedLocales: [Locale('en')],
          home: BingWebmasterPage(siteId: 'site-1', embedded: true),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Bing organic search performance'), findsOneWidget);
    expect(api.lastDimension, 'query');
    expect(find.text('privacy analytics'), findsOneWidget);
    expect(find.text('Access verified'), findsNothing);

    await tester.tap(find.text('Test access'));
    await tester.pumpAndSettle();
    expect(find.text('Access verified'), findsOneWidget);

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'https://www.example.com/');
    await tester.enterText(fields.at(1), 'replacement-private-key');
    await tester.tap(find.text('Save connection'));
    await tester.pumpAndSettle();
    expect(api.savedSiteUrl, 'https://www.example.com/');
    expect(api.savedApiKey, 'replacement-private-key');
    expect(find.text('replacement-private-key'), findsNothing);
    expect(find.text('Connection saved.'), findsOneWidget);

    await tester.ensureVisible(find.text('Daily trend'));
    await tester.tap(find.text('Daily trend'));
    await tester.pumpAndSettle();
    expect(api.lastDimension, 'date');
    expect(find.text('Avg. position'), findsNothing);
  });
}

class _BingWebmasterApi extends SeeRayApi {
  _BingWebmasterApi() : super(baseUrl: 'https://lens.example.test');

  String? lastDimension;
  String? savedSiteUrl;
  String? savedApiKey;

  @override
  Future<dynamic> request(
    String method,
    String path, {
    Object? body,
    bool retried = false,
  }) async {
    final uri = Uri.parse(path);
    if (uri.path.endsWith('/bing-webmaster/property') && method == 'GET') {
      return {
        'configured': true,
        'siteUrl': 'https://www.example.com/',
        'updatedAt': '2026-09-18T00:00:00Z',
        'credentialConfigured': true,
        'canManage': true,
      };
    }
    if (uri.path.endsWith('/bing-webmaster/property') && method == 'PUT') {
      final value = Map<String, dynamic>.from(body! as Map);
      savedSiteUrl = value['siteUrl'] as String;
      savedApiKey = value['apiKey'] as String;
      return {
        'configured': true,
        'siteUrl': savedSiteUrl,
        'credentialConfigured': true,
        'canManage': true,
      };
    }
    if (uri.path.endsWith('/bing-webmaster/validate')) {
      return {
        'accessible': true,
        'verified': true,
        'siteUrl': 'https://www.example.com/',
        'message': 'Bing Webmaster Tools access verified.',
      };
    }
    if (uri.path.endsWith('/bing-webmaster/report')) {
      lastDimension = uri.queryParameters['dimension'];
      final dimension = lastDimension!;
      return {
        'siteUrl': 'https://www.example.com/',
        'from': uri.queryParameters['from'],
        'to': uri.queryParameters['to'],
        'dimension': dimension,
        'clicks': 350,
        'impressions': 7000,
        'ctr': 0.05,
        'rows': [
          {
            'key': dimension == 'date' ? '2026-09-15' : 'privacy analytics',
            'clicks': 35,
            'impressions': 700,
            'ctr': 0.05,
            'averagePosition': 4.2,
          },
        ],
        'mayBeTruncated': dimension != 'date',
        'dataLimitNote': 'Query/page data is updated weekly.',
      };
    }
    fail('Unexpected request: $method $path');
  }
}
