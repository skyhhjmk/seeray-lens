import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seeray_lens_admin/core/network/seeray_api.dart';
import 'package:seeray_lens_admin/features/analytics/presentation/custom_dimensions_page.dart';
import 'package:seeray_lens_admin/features/auth/application/auth_controller.dart';

void main() {
  testWidgets('creates a named dimension and shows its property report', (
    tester,
  ) async {
    final api = _DimensionApi();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiProvider.overrideWithValue(api)],
        child: const MaterialApp(
          home: CustomDimensionsPage(siteId: 'site-1', embedded: true),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Make important product context reportable'),
      findsOneWidget,
    );
    await tester.tap(find.text('Create your first dimension'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'Subscription plan');
    await tester.enterText(find.byType(TextField).at(1), 'subscription_plan');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(api.lastMethod, 'POST');
    expect(api.lastPath, '/api/v1/sites/site-1/custom-dimensions');
    expect((api.lastBody as Map)['key'], 'subscription_plan');
    expect(find.text('Subscription plan'), findsNWidgets(2));
    expect(find.text('pro'), findsOneWidget);
    expect(
      find.textContaining("SeeRay.track('product_interaction'"),
      findsOneWidget,
    );
    expect(find.textContaining('"subscription_plan"'), findsNothing);
  });
}

class _DimensionApi extends SeeRayApi {
  _DimensionApi() : super(baseUrl: 'https://lens.example.test');

  final List<Map<String, dynamic>> dimensions = [];
  String? lastMethod;
  String? lastPath;
  Object? lastBody;

  @override
  Future<dynamic> request(
    String method,
    String path, {
    Object? body,
    bool retried = false,
  }) async {
    if (path.contains('/analytics/')) {
      if (path.contains('/overview')) {
        return {
          'pageViews': 0,
          'uniqueVisitors': 0,
          'sessions': 0,
          'bounceRate': 0,
          'averageSessionDurationMs': 0,
        };
      }
      if (path.contains('/visitors')) {
        return {
          'uniqueVisitors': 0,
          'sessions': 0,
          'newSessions': 0,
          'returningSessions': 0,
          'bounceRate': 0,
          'averageSessionDurationMs': 0,
        };
      }
      return const <dynamic>[];
    }
    if (method == 'POST' || method == 'PUT') {
      lastMethod = method;
      lastPath = path;
      lastBody = body;
      final definition = Map<String, dynamic>.from(body! as Map);
      if (method == 'POST') definition['id'] = 'dimension-1';
      if (!dimensions.any((item) => item['id'] == definition['id'])) {
        dimensions.add(definition);
      }
      return definition;
    }
    if (path.contains('/report?')) {
      return [
        {'value': 'pro', 'events': 12, 'sessions': 8, 'visitors': 7},
      ];
    }
    return dimensions;
  }
}
