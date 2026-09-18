import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seeray_lens_admin/core/network/seeray_api.dart';
import 'package:seeray_lens_admin/features/analytics/presentation/attribution_page.dart';
import 'package:seeray_lens_admin/features/analytics/application/analytics_segment.dart';
import 'package:seeray_lens_admin/features/auth/application/auth_controller.dart';

void main() {
  testWidgets('compares attribution models with goal and lookback controls', (
    tester,
  ) async {
    final api = _AttributionApi();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiProvider.overrideWithValue(api),
          analyticsSegmentSelectionProvider(
            'site-1',
          ).overrideWith(_SegmentSelection.new),
        ],
        child: const MaterialApp(
          home: AttributionPage(siteId: 'site-1', embedded: true),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Conversion attribution'), findsOneWidget);
    expect(find.text('Attributed conversions'), findsOneWidget);
    expect(find.text('0.33'), findsOneWidget);
    expect(find.text('Social · Signup completed'), findsOneWidget);
    expect(find.textContaining('newsletter'), findsOneWidget);

    await tester.tap(find.text('Last touch').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Linear').last);
    await tester.pumpAndSettle();

    expect(api.lastReportQuery?.queryParameters['model'], 'linear');
    expect(api.lastReportQuery?.queryParameters['lookbackDays'], '30');
    expect(api.lastReportQuery?.queryParameters['segmentId'], 'segment-1');
  });
}

class _AttributionApi extends SeeRayApi {
  _AttributionApi() : super(baseUrl: 'https://lens.example.test');

  Uri? get lastReportQuery => _lastReportQuery;
  Uri? _lastReportQuery;

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
          'name': 'Signup completed',
          'enabled': true,
          'fixedValue': 100,
        },
      ];
    }
    if (uri.path.endsWith('/analytics/attribution')) {
      _lastReportQuery = uri;
      return {
        'model': uri.queryParameters['model'],
        'lookbackDays': int.parse(uri.queryParameters['lookbackDays']!),
        'attributedConversions': 1,
        'attributedValue': 100,
        'rows': [
          {
            'goalId': 'goal-1',
            'goalName': 'Signup completed',
            'channel': 'social',
            'source': 'newsletter',
            'medium': 'email',
            'campaign': 'spring',
            'attributedConversions': 0.33,
            'attributedValue': 33.33,
          },
        ],
      };
    }
    throw StateError('Unexpected request $method $path');
  }
}

class _SegmentSelection extends AnalyticsSegmentSelectionNotifier {
  _SegmentSelection() : super('site-1');

  @override
  String? build() => 'segment-1';
}
