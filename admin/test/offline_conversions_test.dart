import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seeray_lens_admin/core/network/seeray_api.dart';
import 'package:seeray_lens_admin/features/analytics/application/offline_conversions.dart';
import 'package:seeray_lens_admin/features/analytics/presentation/offline_conversions_page.dart';
import 'package:seeray_lens_admin/features/auth/application/auth_controller.dart';

void main() {
  group('OfflineConversionImportPreview', () {
    test(
      'parses quoted fields and preserves timezone-qualified timestamps',
      () {
        final preview = OfflineConversionImportPreview.parse(
          '\uFEFFconversion_id,platform,click_id,converted_at\r\n'
          'crm-001,google_ads,"opaque,click-id",2026-09-17T10:30:00+08:00\r\n',
        );

        expect(preview.rows, hasLength(1));
        expect(preview.rows.single.clickId, 'opaque,click-id');
        expect(preview.rows.single.convertedAt, '2026-09-17T10:30:00+08:00');
        expect(preview.rows.single.toJson()['conversionId'], 'crm-001');
      },
    );

    test(
      'rejects duplicate IDs, unsupported platforms, and timestamps without offsets',
      () {
        const header = 'conversion_id,platform,click_id,converted_at\n';
        expect(
          () => OfflineConversionImportPreview.parse(
            '${header}crm-1,google_ads,click-a,2026-09-17T10:00:00Z\n'
            'crm-1,google_ads,click-b,2026-09-17T11:00:00Z',
          ),
          throwsFormatException,
        );
        expect(
          () => OfflineConversionImportPreview.parse(
            '${header}crm-1,other,click-a,2026-09-17T10:00:00Z',
          ),
          throwsFormatException,
        );
        expect(
          () => OfflineConversionImportPreview.parse(
            '${header}crm-1,google_ads,click-a,2026-09-17T10:00:00',
          ),
          throwsFormatException,
        );
      },
    );
  });

  testWidgets(
    'shows matched report, masked-import guidance, and import history',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [apiProvider.overrideWithValue(_OfflineConversionsApi())],
          child: const MaterialApp(
            locale: Locale('en'),
            supportedLocales: [Locale('en')],
            home: OfflineConversionsPage(siteId: 'site-1', embedded: true),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      expect(find.text('Offline conversion attribution'), findsOneWidget);
      expect(find.text('Matched click IDs'), findsOneWidget);
      expect(find.text('3.00'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('Recent imports'),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text('Qualified lead'), findsWidgets);
      expect(find.text('Recent imports'), findsOneWidget);
      expect(find.textContaining('4 conversions'), findsOneWidget);

      await tester.drag(find.byType(ListView).first, const Offset(0, 1000));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Import offline conversions'));
      await tester.pumpAndSettle();
      expect(find.text('Download CSV template'), findsOneWidget);
      expect(find.text('Choose CSV file'), findsOneWidget);
      expect(
        find.textContaining('raw identifiers are not retained'),
        findsOneWidget,
      );
    },
  );
}

class _OfflineConversionsApi extends SeeRayApi {
  _OfflineConversionsApi() : super(baseUrl: 'https://lens.example.test');

  @override
  Future<dynamic> request(
    String method,
    String path, {
    Object? body,
    bool retried = false,
  }) async {
    final uri = Uri.parse(path);
    if (uri.path.endsWith('/goals')) {
      return [
        {
          'id': 'goal-1',
          'name': 'Qualified lead',
          'enabled': true,
          'fixedValue': 25,
        },
      ];
    }
    if (uri.path.endsWith('/segments')) return const [];
    if (uri.path.endsWith('/offline-conversions/imports')) {
      return {
        'canManage': true,
        'timezone': 'UTC',
        'imports': [
          {
            'id': 'import-1',
            'goalId': 'goal-1',
            'goalName': 'Qualified lead',
            'rowCount': 4,
            'importedAt': '2026-09-18T00:00:00Z',
          },
        ],
      };
    }
    if (uri.path.endsWith('/analytics/offline-conversions')) {
      return {
        'from': '2026-09-17',
        'to': '2026-09-17',
        'model': 'last_touch',
        'lookbackDays': 30,
        'totalImported': 4,
        'matchedConversions': 3,
        'unmatchedConversions': 1,
        'attributedConversions': 3,
        'attributedValue': 75,
        'rows': [
          {
            'goalId': 'goal-1',
            'goalName': 'Qualified lead',
            'platform': 'google_ads',
            'channel': 'campaign',
            'source': 'google',
            'medium': 'paid_search',
            'campaign': 'spring-launch',
            'attributedConversions': 3,
            'attributedValue': 75,
          },
        ],
      };
    }
    fail('Unexpected request: $method $path');
  }
}
