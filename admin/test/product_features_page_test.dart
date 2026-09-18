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
    expect(find.byType(SelectableText), findsNWidgets(2));
    expect(
      find.textContaining('data-tag-manager-environment="staging"'),
      findsOneWidget,
    );
  });

  testWidgets('deploys a selected immutable version to staging', (
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
    await tester.tap(find.byTooltip('Deploy version'));
    await tester.pumpAndSettle();
    expect(find.text('Deploy a version'), findsOneWidget);
    await tester.tap(find.text('Deploy'));
    await tester.pumpAndSettle();
    expect(
      api.lastMutationPath,
      '/api/v1/sites/site-1/tag-manager/containers/container-1/versions/1/environments/staging/publish',
    );
  });

  testWidgets('inserts a shared template into a container as a new draft', (
    tester,
  ) async {
    final api = _GraphicalFeatureApi(
      templates: [
        {
          'id': 'template-1',
          'name': 'CTA click',
          'description': 'Record primary CTA clicks',
          'tags': [
            {
              'type': 'event',
              'trigger': 'cta_click',
              'eventType': 'tag_cta_click',
              'name': 'cta_click',
            },
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
    await tester.tap(find.text('Templates'));
    await tester.pumpAndSettle();
    expect(find.text('CTA click'), findsOneWidget);
    await tester.tap(find.text('Use'));
    await tester.pumpAndSettle();
    expect(find.text('Add template to container'), findsOneWidget);
    await tester.tap(find.text('Add as draft'));
    await tester.pumpAndSettle();
    expect(
      api.lastMutationPath,
      '/api/v1/sites/site-1/tag-manager/containers/container-1/versions',
    );
    expect(api.lastBody, [
      {
        'type': 'event',
        'trigger': 'cta_click',
        'eventType': 'tag_cta_click',
        'name': 'cta_click',
      },
    ]);
  });

  testWidgets('creates a reusable template through the visual tag editor', (
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
    await tester.tap(find.text('Templates'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create template'));
    await tester.pumpAndSettle();
    expect(find.text('Configure reusable template tags'), findsOneWidget);
    await tester.enterText(
      find.bySemanticsLabel('Sent event type'),
      'tag_signup',
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
    await tester.tap(find.text('Save template tags'));
    await tester.pumpAndSettle();
    await tester.enterText(find.bySemanticsLabel('Name'), 'Signup tracking');
    await tester.enterText(
      find.bySemanticsLabel('When to use it (optional)'),
      'Use on the registration form',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Signup tracking'), findsOneWidget);
    expect(api.lastMutationPath, '/api/v1/sites/site-1/tag-manager/templates');
    expect(api.lastBody, isA<Map>());
    expect((api.lastBody as Map)['tags'], hasLength(1));
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
    await tester.ensureVisible(find.text('Add filter'));
    await tester.tap(find.text('Add filter'));
    await tester.pumpAndSettle();
    final conditionProperty = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.labelText == 'Event property key',
    );
    await tester.enterText(conditionProperty, 'plan');
    final conditionValue = find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.hintText == 'pro',
    );
    await tester.enterText(conditionValue, 'pro');
    await tester.ensureVisible(find.text('Add property'));
    await tester.tap(find.text('Add property'));
    await tester.pumpAndSettle();
    final propertyKey = find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.labelText == 'Key',
    );
    await tester.enterText(propertyKey, 'landing_page');
    await tester.tap(find.byTooltip('Insert variable'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Page URL'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save draft'));
    await tester.pumpAndSettle();

    expect(api.lastBody, [
      {
        'type': 'event',
        'eventType': 'tag_signup',
        'name': 'signup_tag',
        'triggers': [
          {
            'type': 'event',
            'event': 'signup',
            'conditions': [
              {'property': 'plan', 'operator': 'equals', 'value': 'pro'},
            ],
          },
        ],
        'properties': {'landing_page': '{{Page URL}}'},
      },
    ]);
    expect(find.byTooltip('Publish v1'), findsOneWidget);
  });

  testWidgets('previews draft matches and resolved event properties', (
    tester,
  ) async {
    final api = _GraphicalFeatureApi(
      initialTags: [
        {
          'type': 'event',
          'triggers': [
            {
              'type': 'event',
              'event': 'signup',
              'conditions': [
                {'property': 'plan', 'operator': 'equals', 'value': 'pro'},
              ],
            },
          ],
          'eventType': 'tag_signup',
          'name': 'Signup tag',
          'properties': {'landing_page': '{{Page URL}}'},
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
    await tester.tap(find.text('Preview draft'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'No tracking request is sent and no custom code runs here. Custom JavaScript triggers need a live browser check.',
      ),
      findsOneWidget,
    );
    final signupChip = find.byWidgetPredicate(
      (widget) =>
          widget is ChoiceChip &&
          widget.label is Text &&
          (widget.label as Text).data == 'signup',
    );
    await tester.tap(signupChip);
    await tester.pumpAndSettle();
    expect(find.text('Not matched'), findsOneWidget);
    await tester.ensureVisible(find.text('Event details and properties'));
    await tester.tap(find.text('Event details and properties'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Add event property'));
    await tester.tap(find.text('Add event property'));
    await tester.pumpAndSettle();
    final previewPropertyKey = find.byWidgetPredicate(
      (widget) =>
          widget is TextField && widget.decoration?.labelText == 'Property key',
    );
    final previewPropertyValue = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.labelText == 'Property value',
    );
    await tester.enterText(previewPropertyKey, 'plan');
    await tester.enterText(previewPropertyValue, 'pro');
    await tester.pumpAndSettle();

    expect(find.text('Would emit event: tag_signup'), findsOneWidget);
    expect(find.text('https://example.test/'), findsNWidgets(2));
    expect(api.lastBody, isNull);
  });

  testWidgets('creates, monitors and stops a live preview session', (
    tester,
  ) async {
    final initialTags = [
      {
        'type': 'event',
        'eventType': 'tag_signup',
        'name': 'Signup tag',
        'triggers': [
          {'type': 'event', 'event': 'signup'},
        ],
      },
    ];
    final api = _GraphicalFeatureApi(
      initialTags: initialTags,
      previewEvents: [
        {
          'id': 'event-1',
          'tagIndex': 0,
          'tagName': 'Signup tag',
          'triggerEvent': 'signup',
          'outcome': 'fired',
          'pagePath': '/signup',
          'occurredAt': '2026-09-18T04:00:00Z',
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
    await tester.tap(find.text('Test on live site'));
    await tester.pumpAndSettle();

    expect(find.text('Start a live-site test?'), findsOneWidget);
    expect(
      find.textContaining(
        'Custom HTML and JavaScript can make external requests',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Create test session'));
    await tester.pumpAndSettle();

    expect(find.text('Live site preview'), findsOneWidget);
    expect(find.text('Signup tag').last, findsOneWidget);
    expect(find.text('Fired'), findsOneWidget);
    expect(find.textContaining('/signup'), findsOneWidget);
    expect(
      find.textContaining('data-tag-manager-preview-session="preview-1"'),
      findsOneWidget,
    );
    expect(
      find.textContaining('data-tag-manager-preview-token="one-time-secret"'),
      findsOneWidget,
    );
    expect(
      api.lastMutationPath,
      '/api/v1/sites/site-1/tag-manager/containers/container-1/preview-sessions',
    );
    expect(api.lastBody, {'tags': initialTags, 'executeCustomCode': false});

    await tester.tap(find.text('Stop preview and close'));
    await tester.pumpAndSettle();
    expect(
      api.lastMutationPath,
      '/api/v1/sites/site-1/tag-manager/containers/container-1/preview-sessions/preview-1',
    );
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
    await tester.ensureVisible(find.text('Second tag'));
    await tester.pumpAndSettle();
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
    await tester.ensureVisible(find.text('Discard', skipOffstage: false));
    await tester.pumpAndSettle();
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

    await tester.ensureVisible(find.text('Add tag'));
    await tester.pumpAndSettle();
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
    expect(find.text('Audience targeting'), findsOneWidget);
    expect(find.text('Sample size estimate'), findsOneWidget);
    expect(find.textContaining('exposures needed per variant'), findsOneWidget);
    expect(find.text('Devices'), findsOneWidget);
    await tester.enterText(find.byType(TextField).at(0), 'Homepage hero');
    await tester.ensureVisible(find.text('Add page path'));
    await tester.tap(find.text('Add page path'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '/pricing');
    await tester.ensureVisible(find.widgetWithText(FilterChip, 'Desktop'));
    await tester.tap(find.widgetWithText(FilterChip, 'Desktop'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(api.lastMutationMethod, 'POST');
    expect(api.lastMutationPath, '/api/v1/sites/site-1/experiments');
    expect((api.lastMutationBody as Map)['variants'], ['control', 'new_copy']);
    expect((api.lastMutationBody as Map)['targeting'], {
      'pathPrefixes': ['/pricing'],
      'deviceTypes': ['desktop'],
      'segmentId': null,
      'segmentLookbackDays': 30,
    });
    expect((api.lastMutationBody as Map)['status'], 'draft');
    expect((api.lastMutationBody as Map)['enabled'], isFalse);
    expect((api.lastMutationBody as Map)['allocationGroup'], isNull);
  });

  testWidgets('places experiments in a reusable shared traffic layer', (
    tester,
  ) async {
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
    await tester.enterText(find.byType(TextField).first, 'Checkout copy');
    await tester.ensureVisible(
      find.byKey(const ValueKey('experiment-use-allocation-group')),
    );
    await tester.tap(
      find.byKey(const ValueKey('experiment-use-allocation-group')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('experiment-allocation-group')),
      'Checkout',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final body = api.lastMutationBody as Map;
    expect(body['allocationGroup'], 'checkout');
    expect(body['status'], 'draft');
  });

  testWidgets('starts a draft through the lifecycle menu with confirmation', (
    tester,
  ) async {
    final api = _EditorFeatureApi.experiment(
      items: [
        {
          'id': 'experiment-1',
          'name': 'Checkout hero',
          'status': 'draft',
          'enabled': false,
          'configurationLocked': false,
          'allocationGroup': 'checkout',
          'variants': ['control', 'variant'],
          'targeting': {
            'pathPrefixes': <String>[],
            'deviceTypes': <String>[],
            'segmentId': null,
            'segmentLookbackDays': 30,
          },
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
            mode: ProductFeatureMode.experiments,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Draft'), findsOneWidget);
    expect(find.text('Layer: checkout'), findsOneWidget);
    expect(find.byTooltip('Install snippet'), findsNothing);
    expect(find.byTooltip('Delete'), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('experiment-lifecycle-menu-experiment-1')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'New eligible visitors will be assigned and exposed to this experiment.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Start'));
    await tester.pumpAndSettle();

    final body = api.lastMutationBody as Map;
    expect(api.lastMutationMethod, 'PUT');
    expect(body['status'], 'running');
    expect(body['enabled'], isTrue);
    expect(body['allocationGroup'], 'checkout');
  });

  testWidgets('keeps exposed experiment configuration locked in the list', (
    tester,
  ) async {
    final api = _EditorFeatureApi.experiment(
      items: [
        {
          'id': 'experiment-locked',
          'name': 'Pricing test',
          'status': 'running',
          'enabled': true,
          'configurationLocked': true,
          'variants': ['control', 'variant'],
          'targeting': {'pathPrefixes': <String>[], 'deviceTypes': <String>[]},
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
            mode: ProductFeatureMode.experiments,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Setup locked'), findsOneWidget);
    expect(
      find.textContaining('locked after the first exposure'),
      findsOneWidget,
    );
    expect(find.byTooltip('Edit'), findsNothing);
    expect(find.byTooltip('Delete'), findsNothing);
  });

  testWidgets('targets an experiment with a saved audience and lookback', (
    tester,
  ) async {
    final api = _EditorFeatureApi.experiment(
      segments: [
        {
          'id': 'segment-returning',
          'name': 'Returning readers',
          'enabled': true,
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
            mode: ProductFeatureMode.experiments,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    expect(find.text('Saved audience segment'), findsOneWidget);
    await tester.enterText(
      find.byType(TextField).first,
      'Segment targeted hero',
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('experiment-segment-all')),
    );
    await tester.tap(find.byKey(const ValueKey('experiment-segment-all')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Returning readers').last);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('New or unknown visitors are excluded'),
      findsOneWidget,
    );
    final lookbackDropdown = find.byKey(
      const ValueKey('experiment-segment-lookback'),
    );
    await tester.ensureVisible(lookbackDropdown);
    await tester.tap(lookbackDropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Last 90 days').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect((api.lastMutationBody as Map)['targeting'], {
      'pathPrefixes': <String>[],
      'deviceTypes': <String>[],
      'segmentId': 'segment-returning',
      'segmentLookbackDays': 90,
    });
  });

  testWidgets('edits saved experiment targeting with visual controls', (
    tester,
  ) async {
    final api = _EditorFeatureApi.experiment(
      items: [
        {
          'id': 'experiment-1',
          'name': 'Checkout hero',
          'enabled': true,
          'variants': ['control', 'variant'],
          'targeting': {
            'pathPrefixes': ['/pricing'],
            'deviceTypes': ['mobile'],
          },
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
            mode: ProductFeatureMode.experiments,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Edit').first);
    await tester.pumpAndSettle();

    expect(find.text('Edit A/B test'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField).last).controller?.text,
      '/pricing',
    );
    expect(
      tester
          .widget<FilterChip>(find.widgetWithText(FilterChip, 'Mobile'))
          .selected,
      isTrue,
    );
    await tester.enterText(find.byType(TextField).last, '/checkout');
    await tester.ensureVisible(find.widgetWithText(FilterChip, 'Desktop'));
    await tester.tap(find.widgetWithText(FilterChip, 'Desktop'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(api.lastMutationMethod, 'PUT');
    expect(
      api.lastMutationPath,
      '/api/v1/sites/site-1/experiments/experiment-1',
    );
    expect((api.lastMutationBody as Map)['targeting'], {
      'pathPrefixes': ['/checkout'],
      'deviceTypes': ['desktop', 'mobile'],
      'segmentId': null,
      'segmentLookbackDays': 30,
    });
  });

  testWidgets('shows experiment confidence intervals as visual variant cards', (
    tester,
  ) async {
    final api = _EditorFeatureApi.experiment(
      items: [
        {
          'id': 'experiment-1',
          'name': 'Pricing hero',
          'enabled': true,
          'variants': ['control', 'new_copy'],
        },
      ],
      report: {
        'id': 'experiment-1',
        'name': 'Pricing hero',
        'from': '2026-09-01',
        'to': '2026-09-30',
        'variants': [
          {
            'variant': 'control',
            'exposures': 100,
            'conversions': 10,
            'conversionRate': 0.1,
            'conversionRateCiLower': 0.055,
            'conversionRateCiUpper': 0.174,
            'statisticallySignificant': false,
          },
          {
            'variant': 'new_copy',
            'exposures': 100,
            'conversions': 15,
            'conversionRate': 0.15,
            'conversionRateCiLower': 0.093,
            'conversionRateCiUpper': 0.233,
            'relativeLift': 0.5,
            'pValue': 0.2,
            'statisticallySignificant': false,
            'conversionRateDifference': 0.05,
            'conversionRateDifferenceCiLower': -0.04,
            'conversionRateDifferenceCiUpper': 0.14,
          },
        ],
      },
    );
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
    await tester.tap(find.byTooltip('Report'));
    await tester.pumpAndSettle();

    expect(find.text('Control'), findsOneWidget);
    expect(find.text('Variant'), findsOneWidget);
    expect(find.text('2026-09-01 – 2026-09-30'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('experiment-rate-confidence-interval')),
      findsNWidgets(2),
    );
    expect(find.text('95% rate interval: 5.5% – 17.4%'), findsOneWidget);
    expect(
      find.text('95% difference interval: -4.0 pp – +14.0 pp'),
      findsOneWidget,
    );
    expect(find.text('Not conclusive · p=0.200'), findsOneWidget);
    expect(find.textContaining('Newcombe-Wilson'), findsOneWidget);
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
  _GraphicalFeatureApi({
    this.initialTags = const [],
    List<dynamic> templates = const [],
    this.previewEvents = const [],
  }) : templates = List.of(templates),
       super(baseUrl: 'https://lens.example.test');

  final List<dynamic> initialTags;
  final List<dynamic> templates;
  final List<dynamic> previewEvents;
  Object? lastBody;
  String? lastMutationPath;

  @override
  Future<dynamic> request(
    String method,
    String path, {
    Object? body,
    bool retried = false,
  }) async {
    if (method != 'GET') lastMutationPath = path;
    if (method == 'POST' && path.endsWith('/preview-sessions')) {
      lastBody = body;
      return {
        'sessionId': 'preview-1',
        'token': 'one-time-secret',
        'expiresAt': '2026-09-18T04:15:00Z',
        'executeCustomCode': (body as Map)['executeCustomCode'],
      };
    }
    if (method == 'GET' && path.endsWith('/preview-1/events')) {
      return previewEvents;
    }
    if (method == 'DELETE' && path.endsWith('/preview-1')) return null;
    if (method == 'GET' && path.endsWith('/tag-manager/templates')) {
      return templates;
    }
    if (method == 'POST' && path.endsWith('/tag-manager/templates')) {
      lastBody = body;
      final created = Map<String, dynamic>.from(body as Map)
        ..['id'] = 'template-new';
      templates.add(created);
      return created;
    }
    if (method == 'GET' && path.endsWith('/tag-manager/containers')) {
      return [
        {
          'id': 'container-1',
          'name': 'Production',
          'enabled': true,
          'publishedVersion': null,
          'environmentVersions': {'production': 2, 'staging': 1},
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
  _EditorFeatureApi._(
    this.mode, {
    this.items = const [],
    this.segments = const [],
    this.report = const {},
  }) : super(baseUrl: 'https://lens.example.test');

  factory _EditorFeatureApi.funnel() => _EditorFeatureApi._('funnel');

  factory _EditorFeatureApi.experiment({
    List<dynamic> items = const [],
    List<dynamic> segments = const [],
    Map<String, dynamic> report = const {},
  }) => _EditorFeatureApi._(
    'experiment',
    items: items,
    segments: segments,
    report: report,
  );

  final String mode;
  final List<dynamic> items;
  final List<dynamic> segments;
  final Map<String, dynamic> report;
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
    if (method == 'GET' && path.endsWith('/segments')) return segments;
    if (method == 'GET' && mode == 'experiment' && path.contains('/report?')) {
      return report;
    }
    if (method == 'GET' && mode == 'experiment') return items;
    return {'id': 'saved', 'name': 'saved', 'enabled': true};
  }
}
