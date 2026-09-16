import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seeray_lens_admin/core/network/seeray_api.dart';
import 'package:seeray_lens_admin/features/auth/application/auth_controller.dart';
import 'package:seeray_lens_admin/features/integration/presentation/product_features_page.dart';

void main() {
  testWidgets('loads an empty tag manager panel', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiProvider.overrideWithValue(_EmptyFeatureApi())],
        child: const MaterialApp(
          home: ProductFeaturesPage(
            siteId: 'site-1',
            trackingId: 'srl_site_1',
            trackerUrl: 'https://lens.example.test/tracker.js',
            mode: ProductFeatureMode.tagManager,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Nothing configured yet.'), findsOneWidget);
    expect(find.text('Install the published container'), findsOneWidget);
    expect(find.byType(SelectableText), findsOneWidget);
  });
}

class _EmptyFeatureApi extends SeeRayApi {
  _EmptyFeatureApi() : super(baseUrl: 'https://lens.example.test');

  @override
  Future<dynamic> request(
    String method,
    String path, {
    Object? body,
    bool retried = false,
  }) async => const <dynamic>[];
}
