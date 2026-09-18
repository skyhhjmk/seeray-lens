import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:seeray_lens_admin/core/network/seeray_api.dart';
import 'package:seeray_lens_admin/features/auth/application/auth_controller.dart';
import 'package:seeray_lens_admin/features/integration/presentation/integration_page.dart';
import 'package:seeray_lens_admin/features/sites/application/site_controller.dart';

void main() {
  testWidgets('provides a site-specific native Android SDK setup flow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sitesProvider.overrideWith(_SitesController.new),
          apiProvider.overrideWithValue(_IntegrationApi()),
        ],
        child: const MaterialApp(
          home: IntegrationPage(siteId: 'site-1', embedded: true),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Android SDK'));
    await tester.tap(find.text('Android SDK'));
    await tester.pumpAndSettle();

    expect(find.text('Connect an Android app'), findsOneWidget);
    expect(find.text('Source build only · v0.1.0'), findsOneWidget);
    expect(find.text('HTTPS required for Android'), findsNothing);
    expect(
      find.textContaining('publishReleasePublicationToMavenLocal'),
      findsOneWidget,
    );
    expect(find.textContaining('srl_demo'), findsWidgets);
    expect(find.textContaining('https://lens.example.test'), findsWidgets);
    expect(find.text('Copy initialization code'), findsOneWidget);
    expect(find.textContaining('This site requires consent.'), findsOneWidget);
    expect(find.text('Copy tracking examples'), findsOneWidget);
  });

  testWidgets('blocks generated Android configuration over plaintext HTTP', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sitesProvider.overrideWith(_SitesController.new),
          apiProvider.overrideWithValue(
            SeeRayApi(baseUrl: 'http://localhost:8080'),
          ),
        ],
        child: const MaterialApp(
          home: IntegrationPage(siteId: 'site-1', embedded: true),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Android SDK'));
    await tester.tap(find.text('Android SDK'));
    await tester.pumpAndSettle();

    expect(find.text('HTTPS required for Android'), findsOneWidget);
    expect(find.text('Copy initialization code'), findsNothing);
    expect(find.text('Copy tracking examples'), findsOneWidget);
  });

  testWidgets('provides a site-specific native iOS SwiftPM setup flow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sitesProvider.overrideWith(_SitesController.new),
          apiProvider.overrideWithValue(_IntegrationApi()),
        ],
        child: const MaterialApp(
          home: IntegrationPage(siteId: 'site-1', embedded: true),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('iOS SDK'));
    await tester.tap(find.text('iOS SDK'));
    await tester.pumpAndSettle();

    expect(find.text('Connect an iOS app'), findsOneWidget);
    expect(find.text('Public source package · master branch'), findsOneWidget);
    expect(find.text('HTTPS required for iOS'), findsNothing);
    expect(find.textContaining('requires consent.'), findsOneWidget);
    expect(find.textContaining('skyhhjmk/seeray-lens.git'), findsWidgets);
    expect(find.textContaining('srl_demo'), findsWidgets);
    expect(find.textContaining('https://lens.example.test'), findsWidgets);
    expect(find.text('Copy initialization code'), findsOneWidget);
    expect(find.text('Copy consent call'), findsOneWidget);
    expect(find.text('Copy tracking examples'), findsOneWidget);
  });

  testWidgets('blocks generated iOS initialization over plaintext HTTP', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 1500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sitesProvider.overrideWith(_SitesController.new),
          apiProvider.overrideWithValue(
            SeeRayApi(baseUrl: 'http://localhost:8080'),
          ),
        ],
        child: const MaterialApp(
          home: IntegrationPage(siteId: 'site-1', embedded: true),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('iOS SDK'));
    await tester.tap(find.text('iOS SDK'));
    await tester.pumpAndSettle();

    expect(find.text('HTTPS required for iOS'), findsOneWidget);
    expect(find.text('Copy initialization code'), findsNothing);
    expect(find.text('Copy tracking examples'), findsOneWidget);
  });

  testWidgets('provides an opt-in Core Web Vitals snippet', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sitesProvider.overrideWith(_SitesController.new)],
        child: const MaterialApp(
          home: IntegrationPage(siteId: 'site-1', embedded: true),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Web Vitals'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Web Vitals'));
    await tester.pumpAndSettle();

    expect(find.text('Measure Core Web Vitals'), findsOneWidget);
    final snippet = tester.widget<SelectableText>(
      find.byType(SelectableText).first,
    );
    expect(snippet.data, contains('data-web-vitals'));
    expect(snippet.data, contains('data-require-consent="true"'));
    expect(find.textContaining('does not read page text'), findsOneWidget);
  });

  testWidgets('provides a usable content tracking setup snippet', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sitesProvider.overrideWith(_SitesController.new)],
        child: const MaterialApp(
          home: IntegrationPage(siteId: 'site-1', embedded: true),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Content analytics'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Content analytics'));
    await tester.pumpAndSettle();

    expect(
      find.text('Measure content impressions and interactions'),
      findsOneWidget,
    );
    final snippet = tester.widget<SelectableText>(find.byType(SelectableText));
    expect(snippet.data, contains('data-seeray-content-name'));
    expect(snippet.data, contains('data-seeray-content-action'));
    expect(find.textContaining('never visible text or HTML'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Copy code'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    expect(find.text('Copy code'), findsOneWidget);
  });

  testWidgets('provides an accessible consent and withdrawal setup', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sitesProvider.overrideWith(_SitesController.new)],
        child: const MaterialApp(
          home: IntegrationPage(siteId: 'site-1', embedded: true),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Consent & privacy'));
    await tester.tap(find.text('Consent & privacy'));
    await tester.pumpAndSettle();

    expect(find.text('Visitor consent setup'), findsOneWidget);
    expect(find.text('Consent required for this site'), findsOneWidget);
    final snippet = tester.widget<SelectableText>(
      find.byType(SelectableText).first,
    );
    expect(snippet.data, contains('data-require-consent="true"'));
    expect(snippet.data, contains('data-seeray-consent-accept'));
    expect(snippet.data, contains('SeeRay.optOut'));
    expect(snippet.data, contains('seeray-consent-manage-srl_demo'));

    await tester.ensureVisible(find.text('Hosted privacy'));
    await tester.tap(find.text('Hosted privacy'));
    await tester.pumpAndSettle();
    expect(find.text('Hosted privacy preferences'), findsOneWidget);
    final hostedSnippet = tester.widget<SelectableText>(
      find.byType(SelectableText),
    );
    expect(hostedSnippet.data, contains('data-seeray-privacy'));
    expect(
      hostedSnippet.data,
      contains('/privacy/preferences?siteId=srl_demo'),
    );
    await tester.ensureVisible(find.text('Copy hosted privacy setup'));
    expect(find.text('Copy hosted privacy setup'), findsOneWidget);

    await tester.ensureVisible(find.text('Image fallback'));
    await tester.tap(find.text('Image fallback'));
    await tester.pumpAndSettle();
    final pixelSnippet = tester.widget<SelectableText>(
      find.byType(SelectableText),
    );
    expect(pixelSnippet.data, contains('Pixel fallback is disabled'));
    expect(pixelSnippet.data, isNot(contains('<img src=')));
  });

  testWidgets('provides a consent-aware opaque User ID setup', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sitesProvider.overrideWith(_SitesController.new)],
        child: const MaterialApp(
          home: IntegrationPage(siteId: 'site-1', embedded: true),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('User identity'));
    await tester.tap(find.text('User identity'));
    await tester.pumpAndSettle();

    expect(
      find.text('Link authenticated visits across devices'),
      findsOneWidget,
    );
    final snippet = tester.widget<SelectableText>(find.byType(SelectableText));
    expect(snippet.data, contains('SeeRay.setUserId(user.analyticsId'));
    expect(snippet.data, contains('srl_demo'));
    expect(snippet.data, contains('SeeRay.setUserId(null'));
    expect(find.textContaining('never an email'), findsOneWidget);
  });

  testWidgets('provides an explicit opt-in browser crash setup', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sitesProvider.overrideWith(_SitesController.new),
          apiProvider.overrideWithValue(_IntegrationApi()),
        ],
        child: const MaterialApp(
          home: IntegrationPage(siteId: 'site-1', embedded: true),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Crash analytics'));
    await tester.tap(find.text('Crash analytics'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();

    expect(find.text('Measure browser JavaScript crashes'), findsOneWidget);
    final snippet = tester.widget<SelectableText>(
      find.byType(SelectableText).first,
    );
    expect(snippet.data, contains('data-track-errors'));
    expect(snippet.data, contains('data-require-consent="true"'));
    expect(find.textContaining('never sends stack traces'), findsOneWidget);
    expect(find.text('Release identifier'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Android native crash diagnostics'),
      180,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    expect(find.text('Android native crash diagnostics'), findsOneWidget);
    expect(find.text('Immutable Android release ID'), findsOneWidget);
    expect(find.textContaining('captureNativeCrashes = true'), findsOneWidget);
    expect(find.textContaining('https://www.example.test/'), findsWidgets);
    expect(
      find.textContaining('R8/ProGuard mapping upload is not yet supported.'),
      findsOneWidget,
    );
    expect(find.textContaining('setNativeCrashConsent(true)'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('iOS native exception diagnostics'),
      180,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    expect(find.text('iOS native exception diagnostics'), findsOneWidget);
    expect(find.text('Immutable iOS release ID'), findsOneWidget);
    expect(find.textContaining('captureNativeCrashes: true'), findsOneWidget);
    expect(
      find.textContaining('crashContextURL: "https://www.example.test/"'),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is SelectableText &&
            widget.data?.contains('await analytics.setNativeCrashConsent') ==
                true,
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('Swift fatalError, POSIX signals'),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.text('Upload a JavaScript source map'),
      180,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    expect(find.text('Upload a JavaScript source map'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Uploaded source maps'),
      180,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    expect(find.text('Uploaded source maps'), findsOneWidget);
  });
}

class _SitesController extends SitesController {
  @override
  Future<List<Site>> build() async => const [
    Site(
      id: 'site-1',
      workspaceId: 'workspace-1',
      name: 'Demo site',
      trackingId: 'srl_demo',
      timezone: 'UTC',
      defaultLanguage: 'en',
      trackingEnabled: true,
      requireConsent: true,
      rawRetentionDays: 30,
      aggregateRetentionDays: 730,
    ),
  ];
}

class _IntegrationApi extends SeeRayApi {
  _IntegrationApi() : super(baseUrl: 'https://lens.example.test');

  @override
  Future<dynamic> request(
    String method,
    String path, {
    Object? body,
    bool retried = false,
  }) async {
    expect(method, 'GET');
    if (path == '/api/v1/sites/site-1/crash-source-maps') {
      return {'canManage': true, 'maps': <Map<String, dynamic>>[]};
    }
    expect(path, '/api/v1/sites/site-1/domains');
    return [
      {
        'id': 'domain-1',
        'host': 'www.example.test',
        'allowSubdomains': false,
        'enabled': true,
      },
    ];
  }
}
