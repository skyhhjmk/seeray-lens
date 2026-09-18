import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seeray_lens_admin/core/network/seeray_api.dart';
import 'package:seeray_lens_admin/features/analytics/presentation/yandex_webmaster_page.dart';
import 'package:seeray_lens_admin/features/auth/application/auth_controller.dart';

void main() {
  testWidgets(
    'shows Yandex search queries, verifies access and rotates token',
    (tester) async {
      tester.view.physicalSize = const Size(1500, 1900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = _YandexWebmasterApi();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [apiProvider.overrideWithValue(api)],
          child: const MaterialApp(
            locale: Locale('en'),
            supportedLocales: [Locale('en')],
            home: YandexWebmasterPage(siteId: 'site-1', embedded: true),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final layoutFailure = tester.takeException();
      expect(layoutFailure, isNull);
      expect(find.text('Yandex organic search performance'), findsOneWidget);
      expect(api.lastDeviceType, 'ALL');
      expect(find.text('privacy analytics'), findsOneWidget);
      expect(find.textContaining('top 3,000 popular queries'), findsOneWidget);

      await tester.tap(find.text('Test access'));
      await tester.pumpAndSettle();
      expect(find.text('Access verified'), findsOneWidget);

      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'https://www.example.com/');
      await tester.enterText(fields.at(1), 'yandex-client-id');
      await tester.tap(find.text('Copy authorization link'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.enterText(fields.at(2), 'replacement-yandex-token');
      await tester.tap(find.text('Save & verify'));
      await tester.pumpAndSettle();
      expect(api.savedSiteUrl, 'https://www.example.com/');
      expect(api.savedOAuthToken, 'replacement-yandex-token');
      expect(find.text('replacement-yandex-token'), findsNothing);
      expect(find.text('Connection saved and verified.'), findsOneWidget);

      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Computers').last);
      await tester.pumpAndSettle();
      expect(api.lastDeviceType, 'DESKTOP');
    },
  );
}

class _YandexWebmasterApi extends SeeRayApi {
  _YandexWebmasterApi() : super(baseUrl: 'https://lens.example.test');

  String? lastDeviceType;
  String? savedSiteUrl;
  String? savedOAuthToken;

  @override
  Future<dynamic> request(
    String method,
    String path, {
    Object? body,
    bool retried = false,
  }) async {
    final uri = Uri.parse(path);
    if (uri.path.endsWith('/yandex-webmaster/property') && method == 'GET') {
      return {
        'configured': true,
        'siteUrl': 'https://www.example.com/',
        'updatedAt': '2026-09-19T00:00:00Z',
        'credentialConfigured': true,
        'canManage': true,
      };
    }
    if (uri.path.endsWith('/yandex-webmaster/property') && method == 'PUT') {
      final value = Map<String, dynamic>.from(body! as Map);
      savedSiteUrl = value['siteUrl'] as String;
      savedOAuthToken = value['oauthToken'] as String;
      return {
        'configured': true,
        'siteUrl': savedSiteUrl,
        'credentialConfigured': true,
        'canManage': true,
      };
    }
    if (uri.path.endsWith('/yandex-webmaster/validate')) {
      return {
        'accessible': true,
        'verified': true,
        'siteUrl': 'https://www.example.com/',
        'message': 'Yandex Webmaster site access verified.',
      };
    }
    if (uri.path.endsWith('/yandex-webmaster/report')) {
      lastDeviceType = uri.queryParameters['deviceType'];
      return {
        'siteUrl': 'https://www.example.com/',
        'from': uri.queryParameters['from'],
        'to': uri.queryParameters['to'],
        'deviceType': lastDeviceType,
        'clicks': 240,
        'impressions': 3200,
        'ctr': 0.075,
        'averagePosition': 3.4,
        'totalQueries': 2,
        'rows': [
          {
            'query': 'privacy analytics',
            'clicks': 150,
            'impressions': 2000,
            'ctr': 0.075,
            'averagePosition': 3.1,
          },
          {
            'query': 'web analytics',
            'clicks': 90,
            'impressions': 1200,
            'ctr': 0.075,
            'averagePosition': 3.9,
          },
        ],
        'mayBeTruncated': false,
        'dataLimitNote': 'Yandex returns top 3,000 popular queries.',
      };
    }
    fail('Unexpected request: $method $path');
  }
}
