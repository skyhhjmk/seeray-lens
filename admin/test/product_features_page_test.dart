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
    await tester.enterText(
      find.bySemanticsLabel('Sent event type'),
      'tag_signup',
    );
    await tester.enterText(
      find.bySemanticsLabel('Display name (optional)'),
      'signup_tag',
    );
    await tester.tap(
      find
          .ancestor(
            of: find.text('Add custom event'),
            matching: find.byType(TextButton),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.bySemanticsLabel('Event name'), 'signup');
    await tester.tap(find.text('Save draft'));
    await tester.pumpAndSettle();

    expect(api.lastBody, [
      {
        'type': 'event',
        'eventType': 'tag_signup',
        'name': 'signup_tag',
        'triggers': [
          {'type': 'event', 'event': 'signup'},
        ],
      },
    ]);
    expect(find.byTooltip('Publish v1'), findsOneWidget);
  });

  testWidgets('edits custom code snippets with a graphical code field', (
    tester,
  ) async {
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
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Custom HTML / JavaScript').last);
    await tester.pumpAndSettle();

    expect(find.text('Injected code'), findsOneWidget);
    expect(find.byType(Scrollbar), findsNWidgets(3));
    await tester.ensureVisible(find.text('Add custom event'));
    await tester.tap(find.text('Add custom event'));
    await tester.pumpAndSettle();
    await tester.tap(
      find
          .ancestor(
            of: find.text('Add custom JS trigger'),
            matching: find.byType(TextButton),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.bySemanticsLabel('Event name', skipOffstage: false),
      'signup',
    );
    await tester.enterText(
      find.bySemanticsLabel('Display name', skipOffstage: false),
      'Signup pixel',
    );
    await tester.enterText(
      find.bySemanticsLabel('HTML / JavaScript snippet', skipOffstage: false),
      '<script>window.signupPixel = true;</script>',
    );
    await tester.enterText(
      find.bySemanticsLabel('window function name', skipOffstage: false),
      'shouldFireSignupPixel',
    );
    await tester.enterText(
      find.bySemanticsLabel(
        'Function expression (optional)',
        skipOffstage: false,
      ),
      '(event) => event.event === "signup"',
    );
    await tester.tap(find.text('Save draft'));
    await tester.pumpAndSettle();

    expect(api.lastBody, [
      {
        'type': 'custom_html',
        'name': 'Signup pixel',
        'triggers': [
          {'type': 'event', 'event': 'signup'},
          {
            'type': 'custom_js',
            'functionName': 'shouldFireSignupPixel',
            'code': '(event) => event.event === "signup"',
          },
        ],
        'code': '<script>window.signupPixel = true;</script>',
      },
    ]);
  });

  testWidgets('manages tags from the highlighted left list', (tester) async {
    final api = _GraphicalFeatureApi(
      initialTags: [
        {
          'type': 'event',
          'eventType': 'tag_first',
          'name': 'First tag',
          'triggers': [
            {'type': 'predefined', 'event': 'page_view'},
          ],
        },
        {
          'type': 'event',
          'eventType': 'tag_second',
          'name': 'Second tag',
          'triggers': [
            {'type': 'predefined', 'event': 'signup'},
          ],
        },
      ],
    );
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

    expect(find.text('First tag'), findsNWidgets(2));
    expect(find.text('Second tag'), findsOneWidget);
    await tester.tap(
      find
          .ancestor(of: find.text('Second tag'), matching: find.byType(InkWell))
          .first,
    );
    await tester.pumpAndSettle();

    final displayName = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.labelText == 'Display name (optional)',
    );
    expect(
      tester.widget<TextField>(displayName).controller!.text,
      'Second tag',
    );
    await tester.enterText(displayName, 'Second changed');
    await tester.pump();
    expect(find.text('Discard', skipOffstage: false), findsOneWidget);
    await tester.tap(find.text('Discard', skipOffstage: false));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(displayName).controller!.text,
      'Second tag',
    );

    await tester.enterText(displayName, 'Second saved');
    await tester.pump();
    await tester.tap(find.text('Save', skipOffstage: false).first);
    await tester.pumpAndSettle();
    expect(find.text('Discard', skipOffstage: false), findsNothing);
    expect(find.text('Second saved'), findsNWidgets(2));

    await tester.tap(find.text('Add tag'));
    await tester.pumpAndSettle();
    expect(find.text('Tag 3'), findsOneWidget);
    expect(find.text('Add tag'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
  });

  testWidgets('edits the tag container lifecycle separately from its tags', (
    tester,
  ) async {
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
    await tester.tap(find.byTooltip('Edit'));
    await tester.pumpAndSettle();
    expect(find.text('Edit container'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Production renamed');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(api.lastBody, {'name': 'Production renamed', 'enabled': true});
  });

  testWidgets('edits funnel steps with controls instead of line syntax', (
    tester,
  ) async {
    final api = _EditorFeatureApi.funnel();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiProvider.overrideWithValue(api)],
        child: const MaterialApp(
          home: ProductFeaturesPage(
            siteId: 'site-1',
            trackingId: 'srl_site_1',
            trackerUrl: 'https://lens.example.test/tracker.js',
            mode: ProductFeatureMode.funnels,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Edit'));
    await tester.pumpAndSettle();

    expect(find.text('Edit funnel'), findsOneWidget);
    expect(find.text('Ordered steps'), findsOneWidget);
    expect(find.text('Steps: Page: /path or Event: event_type'), findsNothing);
    await tester.enterText(find.byType(TextField).at(0), 'Checkout journey');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(api.lastMutationMethod, 'PUT');
    expect(api.lastMutationPath, '/api/v1/sites/site-1/funnels/funnel-1');
    expect((api.lastMutationBody as Map)['steps'], hasLength(2));
  });

  testWidgets('creates A/B variants as linked rows', (tester) async {
    final api = _EditorFeatureApi.experiment();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiProvider.overrideWithValue(api)],
        child: const MaterialApp(
          home: ProductFeaturesPage(
            siteId: 'site-1',
            trackingId: 'srl_site_1',
            trackerUrl: 'https://lens.example.test/tracker.js',
            mode: ProductFeatureMode.experiments,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    expect(find.text('Create A/B test'), findsOneWidget);
    expect(find.text('Variants (comma separated)'), findsNothing);
    expect(find.text('Add variant'), findsOneWidget);
    await tester.enterText(find.byType(TextField).at(0), 'Homepage hero');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(api.lastMutationMethod, 'POST');
    expect(api.lastMutationPath, '/api/v1/sites/site-1/experiments');
    expect((api.lastMutationBody as Map)['variants'], ['control', 'new_copy']);
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
  _GraphicalFeatureApi({this.initialTags = const []})
    : super(baseUrl: 'https://lens.example.test');

  final List<dynamic> initialTags;
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
    if (method == 'GET' && path.endsWith('/container-1/versions')) {
      return [
        {'version': 1, 'tags': initialTags},
      ];
    }
    if (method == 'POST' && path.endsWith('/container-1/versions')) {
      lastBody = body;
      return {'version': 1, 'status': 'draft', 'tags': body};
    }
    if (method == 'PUT' && path.endsWith('/container-1')) {
      lastBody = body;
      return {
        'id': 'container-1',
        'name': 'Production renamed',
        'enabled': true,
      };
    }
    return const <dynamic>[];
  }
}

class _EditorFeatureApi extends SeeRayApi {
  _EditorFeatureApi._(this.mode) : super(baseUrl: 'https://lens.example.test');

  factory _EditorFeatureApi.funnel() => _EditorFeatureApi._('funnel');

  factory _EditorFeatureApi.experiment() => _EditorFeatureApi._('experiment');

  final String mode;
  String? lastMutationMethod;
  String? lastMutationPath;
  Object? lastMutationBody;

  @override
  Future<dynamic> request(
    String method,
    String path, {
    Object? body,
    bool retried = false,
  }) async {
    if (method != 'GET') {
      lastMutationMethod = method;
      lastMutationPath = path;
      lastMutationBody = body;
    }
    if (method == 'GET' && mode == 'funnel') {
      return [
        {
          'id': 'funnel-1',
          'name': 'Checkout',
          'enabled': true,
          'steps': [
            {
              'name': 'Landing',
              'type': 'page_view',
              'path': '/landing',
              'matchMode': 'exact',
            },
            {'name': 'Signup', 'type': 'event', 'eventType': 'signup'},
          ],
        },
      ];
    }
    if (method == 'GET' && mode == 'experiment') return const <dynamic>[];
    return {'id': 'saved', 'name': 'saved', 'enabled': true};
  }
}
