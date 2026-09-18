import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:seeray_lens_admin/features/integration/presentation/integration_page.dart';
import 'package:seeray_lens_admin/features/sites/application/site_controller.dart';

void main() {
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
    final snippet = tester.widget<SelectableText>(find.byType(SelectableText));
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
    final snippet = tester.widget<SelectableText>(find.byType(SelectableText));
    expect(snippet.data, contains('data-require-consent="true"'));
    expect(snippet.data, contains('data-seeray-consent-accept'));
    expect(snippet.data, contains('SeeRay.optOut'));
    expect(snippet.data, contains('seeray-consent-manage-srl_demo'));

    await tester.ensureVisible(find.text('Image fallback'));
    await tester.tap(find.text('Image fallback'));
    await tester.pumpAndSettle();
    final pixelSnippet = tester.widget<SelectableText>(
      find.byType(SelectableText),
    );
    expect(pixelSnippet.data, contains('Pixel fallback is disabled'));
    expect(pixelSnippet.data, isNot(contains('<img src=')));
  });

  testWidgets('provides an explicit opt-in browser crash setup', (
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

    await tester.ensureVisible(find.text('Crash analytics'));
    await tester.tap(find.text('Crash analytics'));
    await tester.pumpAndSettle();

    expect(find.text('Measure browser JavaScript crashes'), findsOneWidget);
    final snippet = tester.widget<SelectableText>(find.byType(SelectableText));
    expect(snippet.data, contains('data-track-errors'));
    expect(snippet.data, contains('data-require-consent="true"'));
    expect(find.textContaining('never sends stack traces'), findsOneWidget);
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
