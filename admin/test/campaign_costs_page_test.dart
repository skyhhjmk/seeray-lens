import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seeray_lens_admin/core/network/seeray_api.dart';
import 'package:seeray_lens_admin/features/analytics/presentation/campaign_costs_page.dart';
import 'package:seeray_lens_admin/features/auth/application/auth_controller.dart';

void main() {
  testWidgets(
    'shows campaign performance, import history, and the CSV workflow',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [apiProvider.overrideWithValue(_CampaignCostsApi())],
          child: const MaterialApp(
            locale: Locale('en'),
            supportedLocales: [Locale('en')],
            home: CampaignCostsPage(siteId: 'site-1', embedded: true),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      expect(find.text('Campaign costs'), findsOneWidget);
      expect(find.text('Campaign performance'), findsOneWidget);
      expect(find.textContaining('Summer Search'), findsOneWidget);
      expect(find.textContaining('google / paid_search'), findsOneWidget);
      await tester.tap(find.text('Import campaign CSV'));
      await tester.pumpAndSettle();
      expect(find.text('Download CSV template'), findsOneWidget);
      expect(find.text('Choose CSV file'), findsOneWidget);
      expect(
        find.textContaining('Matching source/medium/campaign values'),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(
        find.text('Recent imports'),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text('Recent imports'), findsOneWidget);
      expect(find.text('google-costs.csv'), findsOneWidget);
    },
  );
}

class _CampaignCostsApi extends SeeRayApi {
  _CampaignCostsApi() : super(baseUrl: 'https://lens.example.test');

  @override
  Future<dynamic> request(
    String method,
    String path, {
    Object? body,
    bool retried = false,
  }) async {
    final uri = Uri.parse(path);
    if (uri.path.endsWith('/goals')) return const [];
    if (uri.path.endsWith('/campaign-costs/imports')) {
      return {
        'canManage': true,
        'timezone': 'UTC',
        'imports': [
          {
            'id': 'import-1',
            'fileName': 'google-costs.csv',
            'rowCount': 1,
            'importedAt': '2026-09-18T00:00:00Z',
          },
        ],
      };
    }
    if (uri.path.endsWith('/campaign-costs')) {
      return {
        'from': '2026-09-17',
        'to': '2026-09-17',
        'model': 'last_touch',
        'lookbackDays': 30,
        'rows': [
          {
            'platform': 'google_ads',
            'source': 'google',
            'medium': 'paid_search',
            'campaign': 'Summer Search',
            'currency': 'USD',
            'impressions': 3200,
            'clicks': 87,
            'cost': 125.5,
            'sessions': 72,
            'attributedConversions': 4.5,
            'attributedGoalValue': 450,
            'costPerClick': 1.442529,
            'costPerAttributedConversion': 27.888889,
            'goalValuePerSpend': 3.585657,
          },
        ],
      };
    }
    fail('Unexpected request: $method $path');
  }
}
