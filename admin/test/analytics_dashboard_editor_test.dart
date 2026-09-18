import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seeray_lens_admin/core/network/seeray_api.dart';
import 'package:seeray_lens_admin/features/analytics/application/analytics_controller.dart';
import 'package:seeray_lens_admin/features/analytics/application/custom_report_formula.dart';
import 'package:seeray_lens_admin/features/analytics/presentation/analytics_dashboard_page.dart';
import 'package:seeray_lens_admin/features/auth/application/auth_controller.dart';

void main() {
  test('queries and parses a two-dimension custom report', () async {
    final api = _DashboardApi();
    final container = ProviderContainer(
      overrides: [apiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);

    final report = await container.read(
      customReportProvider(
        CustomReportQuery(
          siteId: 'site-1',
          range: AnalyticsDateRange(
            DateTime.utc(2026, 9, 17),
            DateTime.utc(2026, 9, 17),
          ),
          dimension: 'entry_page',
          secondaryDimension: 'exit_page',
          metric: 'sessions',
          limit: 10,
          matchMode: 'all',
          filters: const [],
        ),
      ).future,
    );

    expect(api.customReportBody!['secondaryDimension'], 'exit_page');
    expect(report.secondaryDimension, 'exit_page');
    expect(report.rows.single.secondaryDimensionValue, '/pricing');
  });

  test('queries and parses a three-dimension custom report', () async {
    final api = _DashboardApi();
    final container = ProviderContainer(
      overrides: [apiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);

    final report = await container.read(
      customReportProvider(
        CustomReportQuery(
          siteId: 'site-1',
          range: AnalyticsDateRange(
            DateTime.utc(2026, 9, 17),
            DateTime.utc(2026, 9, 17),
          ),
          dimension: 'event_type',
          secondaryDimension: 'country',
          tertiaryDimension: 'custom:11111111-1111-4111-8111-111111111111',
          metric: 'events',
          limit: 10,
          matchMode: 'all',
          filters: const [],
        ),
      ).future,
    );

    expect(
      api.customReportBody!['tertiaryDimension'],
      'custom:11111111-1111-4111-8111-111111111111',
    );
    expect(
      report.tertiaryDimension,
      'custom:11111111-1111-4111-8111-111111111111',
    );
    expect(report.tertiaryCustomDimensionName, 'Plan');
    expect(report.rows.single.tertiaryDimensionValue, 'pro');
  });

  test('queries and parses a four-dimension custom report', () async {
    final api = _DashboardApi();
    final container = ProviderContainer(
      overrides: [apiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);

    final report = await container.read(
      customReportProvider(
        CustomReportQuery(
          siteId: 'site-1',
          range: AnalyticsDateRange(
            DateTime.utc(2026, 9, 17),
            DateTime.utc(2026, 9, 17),
          ),
          dimension: 'event_type',
          secondaryDimension: 'country',
          tertiaryDimension: 'custom:11111111-1111-4111-8111-111111111111',
          quaternaryDimension: 'browser',
          metric: 'events',
          limit: 10,
          matchMode: 'all',
          filters: const [],
        ),
      ).future,
    );

    expect(api.customReportBody!['quaternaryDimension'], 'browser');
    expect(report.quaternaryDimension, 'browser');
    expect(report.rows.single.quaternaryDimensionValue, 'Chrome');
  });

  test('parses the name for a custom secondary dimension', () async {
    final api = _DashboardApi();
    final container = ProviderContainer(
      overrides: [apiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);

    final report = await container.read(
      customReportProvider(
        CustomReportQuery(
          siteId: 'site-1',
          range: AnalyticsDateRange(
            DateTime.utc(2026, 9, 17),
            DateTime.utc(2026, 9, 17),
          ),
          dimension: 'event_type',
          secondaryDimension: 'custom:11111111-1111-4111-8111-111111111111',
          metric: 'events',
          limit: 10,
          matchMode: 'all',
          filters: const [],
        ),
      ).future,
    );

    expect(
      api.customReportBody!['secondaryDimension'],
      'custom:11111111-1111-4111-8111-111111111111',
    );
    expect(report.secondaryCustomDimensionName, 'Subscription plan');
  });

  test('sends a typed calculated metric and reads its name', () async {
    final api = _DashboardApi();
    final container = ProviderContainer(
      overrides: [apiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);
    const formula = CustomReportFormula(
      name: 'Events per visit',
      leftMetric: 'events',
      operator: 'divide',
      rightMetric: 'sessions',
      format: 'percent',
    );

    final report = await container.read(
      customReportProvider(
        CustomReportQuery(
          siteId: 'site-1',
          range: AnalyticsDateRange(
            DateTime.utc(2026, 9, 17),
            DateTime.utc(2026, 9, 17),
          ),
          dimension: 'event_type',
          metric: 'formula',
          formula: formula,
          limit: 10,
          matchMode: 'all',
          filters: const [],
        ),
      ).future,
    );

    expect(api.customReportBody!['formula'], formula.toJson());
    expect(report.formulaName, 'Events per visit');
  });

  testWidgets('uses event type as a visual custom report breakdown', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = _DashboardApi();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiProvider.overrideWithValue(api)],
        child: const MaterialApp(
          home: AnalyticsDashboardPage(siteId: 'site-1', embedded: true),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Customize'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add widget'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Custom report').last);
    await tester.tap(find.text('Custom report').last);
    await tester.pumpAndSettle();

    final dimensionDropdown = find.byWidgetPredicate(
      (widget) =>
          widget is DropdownButtonFormField<String> &&
          widget.decoration.labelText == 'Break down by',
    );
    await tester.tap(dimensionDropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Event type').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('rows are not additive'), findsOneWidget);
    await tester.ensureVisible(find.text('Apply'));
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final widget = (api.savedBody!['widgets'] as List).cast<Map>().singleWhere(
      (item) => item['type'] == 'custom_report',
    );
    expect(widget['dimension'], 'event_type');
    expect(widget['metric'], 'sessions');
  });

  testWidgets('searches and selects a nested event property visually', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = _DashboardApi();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiProvider.overrideWithValue(api)],
        child: const MaterialApp(
          home: AnalyticsDashboardPage(siteId: 'site-1', embedded: true),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Customize'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add widget'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Custom report').last);
    await tester.tap(find.text('Custom report').last);
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Browse event properties (1)'));
    await tester.tap(find.text('Browse event properties (1)'));
    await tester.pumpAndSettle();
    expect(find.text('Choose an event property'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'category');
    await tester.pumpAndSettle();
    await tester.tap(find.text('product › category › name'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Apply'));
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final widget = (api.savedBody!['widgets'] as List).cast<Map>().singleWhere(
      (item) => item['type'] == 'custom_report',
    );
    expect(widget['dimension'], _eventPropertyId);
  });

  testWidgets('adds a second built-in session breakdown visually', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = _DashboardApi();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiProvider.overrideWithValue(api)],
        child: const MaterialApp(
          home: AnalyticsDashboardPage(siteId: 'site-1', embedded: true),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Customize'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add widget'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Custom report').last);
    await tester.tap(find.text('Custom report').last);
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Add a second breakdown'));
    await tester.tap(find.text('Add a second breakdown'));
    await tester.pumpAndSettle();
    expect(find.text('Then break down by'), findsOneWidget);
    await tester.ensureVisible(find.text('Add a third breakdown'));
    await tester.tap(find.text('Add a third breakdown'));
    await tester.pumpAndSettle();
    expect(find.text('And then by'), findsOneWidget);
    await tester.ensureVisible(find.text('Add a fourth breakdown'));
    await tester.tap(find.text('Add a fourth breakdown'));
    await tester.pumpAndSettle();
    expect(find.text('And finally by'), findsOneWidget);
    await tester.ensureVisible(find.text('Apply'));
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final widget = (api.savedBody!['widgets'] as List).cast<Map>().singleWhere(
      (item) => item['type'] == 'custom_report',
    );
    expect(widget['dimension'], 'browser');
    expect(widget['secondaryDimension'], 'country');
    expect(widget['tertiaryDimension'], 'device_type');
    expect(widget['quaternaryDimension'], 'entry_page');
    expect(find.text('Breakdown combination'), findsOneWidget);
    expect(find.textContaining('Device type: pro'), findsOneWidget);
  });

  testWidgets('adds a registered event dimension as a second breakdown', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = _DashboardApi();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiProvider.overrideWithValue(api)],
        child: const MaterialApp(
          home: AnalyticsDashboardPage(siteId: 'site-1', embedded: true),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Customize'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add widget'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Custom report').last);
    await tester.tap(find.text('Custom report').last);
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Add a second breakdown'));
    await tester.tap(find.text('Add a second breakdown'));
    await tester.pumpAndSettle();
    final secondDimensionDropdown = find.byWidgetPredicate(
      (widget) =>
          widget is DropdownButtonFormField<String> &&
          widget.decoration.labelText == 'Then break down by',
    );
    await tester.tap(secondDimensionDropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Subscription plan (subscription_plan)').last);
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Apply'));
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final widget = (api.savedBody!['widgets'] as List).cast<Map>().singleWhere(
      (item) => item['type'] == 'custom_report',
    );
    expect(widget['dimension'], 'browser');
    expect(
      widget['secondaryDimension'],
      'custom:11111111-1111-4111-8111-111111111111',
    );
    expect(find.text('Subscription plan'), findsOneWidget);
  });

  testWidgets('uses named custom dimensions in saved report widgets', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = _DashboardApi();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiProvider.overrideWithValue(api)],
        child: const MaterialApp(
          home: AnalyticsDashboardPage(siteId: 'site-1', embedded: true),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Customize'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add widget'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Custom report').last);
    await tester.tap(find.text('Custom report').last);
    await tester.pumpAndSettle();

    final dimensionDropdown = find.byWidgetPredicate(
      (widget) =>
          widget is DropdownButtonFormField<String> &&
          widget.decoration.labelText == 'Break down by',
    );
    await tester.tap(dimensionDropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Subscription plan (subscription_plan)').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Apply'));
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final widget = (api.savedBody!['widgets'] as List).cast<Map>().singleWhere(
      (item) => item['type'] == 'custom_report',
    );
    expect(widget['dimension'], 'custom:11111111-1111-4111-8111-111111111111');
  });

  testWidgets(
    'builds a custom report from visible controls and saves its filters',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final api = _DashboardApi();
      final filePicker = _DashboardFilePicker();
      FilePicker.platform = filePicker;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [apiProvider.overrideWithValue(api)],
          child: const MaterialApp(
            home: AnalyticsDashboardPage(siteId: 'site-1', embedded: true),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Customize'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add widget'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Custom report').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Custom report').last);
      await tester.pumpAndSettle();

      expect(find.text('Break down by'), findsOneWidget);
      expect(find.text('Audience filters'), findsOneWidget);
      await tester.ensureVisible(find.text('Add filter'));
      await tester.tap(find.text('Add filter'));
      await tester.pumpAndSettle();
      expect(find.text('Filter dimension'), findsOneWidget);
      await tester.ensureVisible(find.text('Apply'));
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final widget = (api.savedBody!['widgets'] as List)
          .cast<Map>()
          .singleWhere((item) => item['type'] == 'custom_report');
      expect(widget['dimension'], 'browser');
      expect(widget['metric'], 'sessions');
      expect(widget['chartType'], 'table');
      expect(widget['matchMode'], 'all');
      expect(widget['filters'], [
        {'field': 'source', 'operator': 'contains', 'value': 'newsletter'},
      ]);
      expect(find.textContaining('Raw JSON'), findsNothing);
      final exportButton = find.byTooltip('Export report data').last;
      await tester.ensureVisible(exportButton);
      await tester.tap(exportButton);
      await tester.pumpAndSettle();
      expect(find.text('Download CSV'), findsOneWidget);
      expect(find.text('Download JSON'), findsOneWidget);
      expect(find.text('Download PDF'), findsOneWidget);
      await tester.tap(find.text('Download CSV'));
      await tester.pumpAndSettle();
      expect(filePicker.fileName, endsWith('.csv'));
      expect(utf8.decode(filePicker.bytes!), contains('Browser'));
      expect(utf8.decode(filePicker.bytes!), contains('Chrome'));
      await tester.tap(find.byTooltip('Export report data').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Download JSON'));
      await tester.pumpAndSettle();
      final jsonExport = utf8.decode(filePicker.bytes!);
      expect(filePicker.fileName, endsWith('.json'));
      expect(jsonExport, contains('newsletter'));
      expect(jsonExport, contains('"Chrome"'));
      await tester.tap(find.byTooltip('Export report data').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Download PDF'));
      await tester.pumpAndSettle();
      expect(filePicker.fileName, endsWith('.pdf'));
      expect(String.fromCharCodes(filePicker.bytes!.take(5)), '%PDF-');
    },
  );

  testWidgets('builds and persists a calculated metric in the visual editor', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = _DashboardApi();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiProvider.overrideWithValue(api)],
        child: const MaterialApp(
          home: AnalyticsDashboardPage(siteId: 'site-1', embedded: true),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Customize'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add widget'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Custom report').last);
    await tester.tap(find.text('Custom report').last);
    await tester.pumpAndSettle();

    final measureDropdown = find.byWidgetPredicate(
      (widget) =>
          widget is DropdownButtonFormField<String> &&
          widget.decoration.labelText == 'Measure',
    );
    await tester.ensureVisible(measureDropdown);
    await tester.tap(measureDropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Calculated metric').last);
    await tester.pumpAndSettle();
    expect(find.text('First measure'), findsOneWidget);
    expect(find.text('Second measure'), findsOneWidget);

    await tester.ensureVisible(find.text('Apply'));
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final widget = (api.savedBody!['widgets'] as List).cast<Map>().singleWhere(
      (item) => item['type'] == 'custom_report',
    );
    expect(widget['metric'], 'formula');
    expect(widget['formula'], {
      'name': 'Events per visit',
      'leftMetric': 'events',
      'operator': 'divide',
      'rightMetric': 'sessions',
      'format': 'number',
    });
    expect(find.textContaining('Raw JSON'), findsNothing);
  });

  testWidgets('builds and saves a dashboard through the visual widget editor', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = _DashboardApi();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiProvider.overrideWithValue(api)],
        child: const MaterialApp(
          home: AnalyticsDashboardPage(siteId: 'site-1', embedded: true),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Overview'), findsOneWidget);
    await tester.tap(find.text('Customize'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add widget'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Events').last);
    await tester.pumpAndSettle();

    expect(find.byTooltip('Configure widget'), findsNWidgets(5));
    await tester.ensureVisible(find.byTooltip('Configure widget').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Configure widget').last);
    await tester.pumpAndSettle();
    expect(find.text('Widget settings'), findsOneWidget);
    final titleField = find.byWidgetPredicate(
      (widget) => widget is TextField && widget.controller?.text == 'Events',
    );
    expect(titleField, findsOneWidget);
    await tester.enterText(titleField, 'Signup events');
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Raw JSON'), findsNothing);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(api.savedBody, isNotNull);
    expect(api.savedBody!['name'], 'Overview');
    expect(api.savedBody!['isDefault'], true);
    final widgets = api.savedBody!['widgets'] as List;
    expect(widgets.map((item) => item['type']), contains('events'));
    final eventWidget = widgets.singleWhere((item) => item['type'] == 'events');
    expect(eventWidget['title'], 'Signup events');
    expect(eventWidget['limit'], 5);
    expect(find.text('Dashboard saved.'), findsOneWidget);
  });
}

final _eventPropertyId =
    'event_property:${base64Url.encode(utf8.encode('product\u001fcategory\u001fname')).replaceAll('=', '')}';

class _DashboardApi extends SeeRayApi {
  _DashboardApi() : super(baseUrl: 'https://lens.example.test');

  final List<Map<String, dynamic>> _dashboards = [];
  Map<String, dynamic>? savedBody;
  Map<String, dynamic>? customReportBody;

  @override
  Future<dynamic> request(
    String method,
    String path, {
    Object? body,
    bool retried = false,
  }) async {
    final route = Uri.parse(path).path;
    if (route.endsWith('/custom-dimensions')) {
      return [
        {
          'id': '11111111-1111-4111-8111-111111111111',
          'key': 'subscription_plan',
          'name': 'Subscription plan',
          'enabled': true,
        },
      ];
    }
    if (route.endsWith('/analytics/custom-report/event-properties')) {
      return [
        {
          'id': _eventPropertyId,
          'label': 'product › category › name',
          'eventCount': 12,
          'sessionCount': 7,
        },
      ];
    }
    if (route.endsWith('/dashboards')) {
      if (method == 'GET') return List<Map<String, dynamic>>.of(_dashboards);
      if (method == 'POST') {
        savedBody = Map<String, dynamic>.from(body! as Map);
        final now = DateTime.now().toUtc().toIso8601String();
        final dashboard = <String, dynamic>{
          ...savedBody!,
          'id': 'dashboard-1',
          'createdAt': now,
          'updatedAt': now,
        };
        _dashboards.add(dashboard);
        return dashboard;
      }
    }
    if (route.endsWith('/analytics/overview')) {
      return {
        'pageViews': 31,
        'uniqueVisitors': 18,
        'sessions': 24,
        'bounceRate': 0.25,
        'averageSessionDurationMs': 64000,
      };
    }
    if (route.endsWith('/analytics/timeseries')) {
      return [
        {
          'date': '2026-09-17',
          'pageViews': 31,
          'uniqueVisitors': 18,
          'sessions': 24,
        },
      ];
    }
    if (route.endsWith('/analytics/pages')) {
      return [
        {'path': '/pricing', 'pageViews': 12},
      ];
    }
    if (route.endsWith('/analytics/traffic')) {
      return [
        {'channel': 'direct', 'sessions': 14},
      ];
    }
    if (route.endsWith('/analytics/visitors')) {
      return {
        'uniqueVisitors': 18,
        'sessions': 24,
        'newSessions': 16,
        'returningSessions': 8,
        'bounceRate': 0.25,
        'averageSessionDurationMs': 64000,
      };
    }
    if (route.endsWith('/analytics/events') ||
        route.endsWith('/analytics/goals')) {
      return <Object>[];
    }
    if (route.endsWith('/analytics/custom-report/query')) {
      customReportBody = Map<String, dynamic>.from(body! as Map);
      final hasSecondary = customReportBody!.containsKey('secondaryDimension');
      return {
        'dimension': customReportBody!['dimension'],
        'secondaryDimension': customReportBody!['secondaryDimension'],
        'tertiaryDimension': customReportBody!['tertiaryDimension'],
        'quaternaryDimension': customReportBody!['quaternaryDimension'],
        'secondaryCustomDimensionName':
            (customReportBody!['secondaryDimension'] as String?)?.startsWith(
                  'custom:',
                ) ==
                true
            ? 'Subscription plan'
            : null,
        'tertiaryCustomDimensionName':
            (customReportBody!['tertiaryDimension'] as String?)?.startsWith(
                  'custom:',
                ) ==
                true
            ? 'Plan'
            : null,
        'quaternaryCustomDimensionName': null,
        'metric': customReportBody!['metric'],
        'formulaName': (customReportBody!['formula'] as Map?)?['name'],
        'customDimensionName': null,
        'rows': [
          {
            'dimensionValue': hasSecondary ? '/pricing' : 'Chrome',
            if (hasSecondary) 'secondaryDimensionValue': '/pricing',
            if (customReportBody!.containsKey('tertiaryDimension'))
              'tertiaryDimensionValue': 'pro',
            if (customReportBody!.containsKey('quaternaryDimension'))
              'quaternaryDimensionValue': 'Chrome',
            'metricValue': 8,
          },
        ],
      };
    }
    throw StateError('Unexpected API request: $method $path');
  }
}

class _DashboardFilePicker extends FilePicker {
  Uint8List? bytes;
  String? fileName;

  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) async {
    this.fileName = fileName;
    this.bytes = bytes;
    return '/exports/${fileName ?? 'analytics-export'}';
  }
}
