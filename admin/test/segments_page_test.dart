import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seeray_lens_admin/core/network/seeray_api.dart';
import 'package:seeray_lens_admin/features/analytics/presentation/segments_page.dart';
import 'package:seeray_lens_admin/features/auth/application/auth_controller.dart';

void main() {
  testWidgets('creates a reusable segment and shows its audience preview', (
    tester,
  ) async {
    final api = _SegmentApi();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiProvider.overrideWithValue(api)],
        child: const MaterialApp(
          home: SegmentsPage(siteId: 'site-1', embedded: true),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Build your first audience'), findsOneWidget);
    await tester.tap(find.text('Create a segment'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'New visitors');
    final fieldSelector = tester.widget<DropdownButtonFormField<String>>(
      find.byKey(const ValueKey('field-visitor_type')),
    );
    fieldSelector.onChanged?.call('screen_width');
    await tester.pumpAndSettle();
    expect(find.text('Screen width (px)'), findsOneWidget);
    final operatorSelector = tester.widget<DropdownButtonFormField<String>>(
      find.byKey(const ValueKey('operator-screen_width-equals')),
    );
    operatorSelector.onChanged?.call('at_least');
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('value-screen_width-at_least')),
      '1024',
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      'New visitors',
    );
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'))
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.text('Preview matches'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Preview: 8 sessions'), findsOneWidget);
    expect((api.lastPreviewBody as Map)['rules'], [
      {'field': 'screen_width', 'operator': 'at_least', 'value': '1024'},
    ]);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(api.lastMethod, 'POST');
    expect(api.lastPath, '/api/v1/sites/site-1/segments');
    expect((api.lastBody as Map)['matchMode'], 'all');
    final rules = (api.lastBody as Map)['rules'] as List;
    expect((rules.single as Map)['field'], 'screen_width');
    expect((rules.single as Map)['operator'], 'at_least');
    expect((rules.single as Map)['value'], '1024');
    expect(find.text('New visitors'), findsNWidgets(2));
    expect(find.text('12'), findsOneWidget);
    expect(find.text('/pricing'), findsOneWidget);
  });
}

class _SegmentApi extends SeeRayApi {
  _SegmentApi() : super(baseUrl: 'https://lens.example.test');

  Map<String, dynamic>? segment;
  String? lastMethod;
  String? lastPath;
  Object? lastBody;
  Object? lastPreviewBody;

  @override
  Future<dynamic> request(
    String method,
    String path, {
    Object? body,
    bool retried = false,
  }) async {
    if (path.endsWith('/custom-dimensions')) return const <dynamic>[];
    if (path.contains('/preview')) {
      lastPreviewBody = body;
      return {
        'sessions': 8,
        'visitors': 6,
        'pageViews': 12,
        'bounceRate': 0.25,
        'averageSessionDurationMs': 45000,
        'topPages': [
          {'path': '/pricing', 'pageViews': 7},
        ],
      };
    }
    if (method == 'POST' || method == 'PUT') {
      lastMethod = method;
      lastPath = path;
      lastBody = body;
      segment = Map<String, dynamic>.from(body! as Map)..['id'] = 'segment-1';
      return segment;
    }
    return segment == null ? const <dynamic>[] : [segment!];
  }
}
