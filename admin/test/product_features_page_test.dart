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

  testWidgets('edits tag drafts with graphical fields', (tester) async {
    final api = _GraphicalFeatureApi();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiProvider.overrideWithValue(api)],
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
    await tester.tap(find.byTooltip('Edit tags'));
    await tester.pumpAndSettle();

    expect(find.text('Edit container tags'), findsOneWidget);
    expect(find.text('Tags array'), findsNothing);
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'signup');
    await tester.enterText(fields.at(1), 'tag_signup');
    await tester.enterText(fields.at(2), 'signup_tag');
    await tester.tap(find.text('Save draft'));
    await tester.pumpAndSettle();

    expect(api.lastBody, [
      {
        'type': 'event',
        'trigger': 'signup',
        'eventType': 'tag_signup',
        'name': 'signup_tag',
      },
    ]);
    expect(find.byTooltip('Publish v1'), findsOneWidget);
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

class _GraphicalFeatureApi extends SeeRayApi {
  _GraphicalFeatureApi() : super(baseUrl: 'https://lens.example.test');

  Object? lastBody;

  @override
  Future<dynamic> request(
    String method,
    String path, {
    Object? body,
    bool retried = false,
  }) async {
    if (method == 'GET' && path.endsWith('/tag-manager/containers')) {
      return [
        {
          'id': 'container-1',
          'name': 'Production',
          'enabled': true,
          'publishedVersion': null,
        },
      ];
    }
    if (method == 'POST' && path.endsWith('/container-1/versions')) {
      lastBody = body;
      return {'version': 1, 'status': 'draft', 'tags': body};
    }
    return const <dynamic>[];
  }
}
