import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seeray_lens_admin/core/network/seeray_api.dart';
import 'package:seeray_lens_admin/features/analytics/presentation/locations_page.dart';
import 'package:seeray_lens_admin/features/auth/application/auth_controller.dart';

void main() {
  testWidgets('country map selection shows visit and visitor totals', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiProvider.overrideWithValue(_LocationApi())],
        child: const MaterialApp(
          home: LocationsPage(siteId: 'site-1', embedded: true),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('world-country-map')), findsOneWidget);
    expect(find.text('Visits by country'), findsOneWidget);
    final map = find.byKey(const Key('world-country-map'));
    final origin = tester.getTopLeft(map);
    final size = tester.getSize(map);
    await tester.tapAt(
      origin + Offset(size.width * (80 / 360), size.height * (50 / 180)),
    );
    await tester.pumpAndSettle();

    expect(find.text('United States · US'), findsOneWidget);
    expect(find.text('14 visits · 9 visitors'), findsOneWidget);
  });
}

class _LocationApi extends SeeRayApi {
  _LocationApi() : super(baseUrl: 'https://lens.example.test');

  @override
  Future<dynamic> request(
    String method,
    String path, {
    Object? body,
    bool retried = false,
  }) async {
    if (path.contains('/analytics/locations')) {
      return {
        'sourceConfigured': true,
        'rows': [
          {
            'level': 'country',
            'label': 'United States',
            'countryCode': 'US',
            'continentCode': 'NA',
            'sessions': 14,
            'visitors': 9,
          },
        ],
      };
    }
    throw StateError('Unexpected request $method $path');
  }
}
