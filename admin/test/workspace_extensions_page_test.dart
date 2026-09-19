import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seeray_lens_admin/core/network/seeray_api.dart';
import 'package:seeray_lens_admin/features/auth/application/auth_controller.dart';
import 'package:seeray_lens_admin/features/workspaces/presentation/workspace_extensions_page.dart';

void main() {
  testWidgets(
    'renders extension lifecycle cards and creates a signed endpoint',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = _ExtensionsApi();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [apiProvider.overrideWithValue(api)],
          child: const MaterialApp(
            locale: Locale('en'),
            supportedLocales: [Locale('en')],
            home: WorkspaceExtensionsPage(workspaceId: 'workspace-1'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('CRM sync  v1.0.0'), findsOneWidget);
      expect(find.text('Enabled'), findsOneWidget);
      expect(find.text('Analytics events / 分析事件'), findsOneWidget);
      expect(find.text('Extension queue health'), findsOneWidget);
      expect(find.text('Total 3'), findsOneWidget);
      expect(find.text('Client plugin SDK'), findsOneWidget);
      await tester.tap(find.text('Client plugin SDK'));
      await tester.pumpAndSettle();
      expect(find.textContaining("tracker.use"), findsOneWidget);
      await tester.tap(find.text('Delivery activity'));
      await tester.pumpAndSettle();
      expect(find.text('Total 3'), findsNWidgets(2));
      expect(find.text('Delivered 2'), findsNWidgets(2));
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add extension'));
      await tester.pumpAndSettle();
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'warehouse.export');
      await tester.enterText(fields.at(1), 'Warehouse export');
      await tester.enterText(fields.at(2), '1.2.0');
      await tester.enterText(fields.at(3), 'https://hooks.example.test/export');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(api.lastMutationPath, '/api/v1/workspaces/workspace-1/extensions');
      expect((api.lastBody! as Map)['extensionKey'], 'warehouse.export');
      expect(find.text('Copy this secret now'), findsOneWidget);
    },
  );
}

class _ExtensionsApi extends SeeRayApi {
  _ExtensionsApi() : super(baseUrl: 'https://lens.example.test');

  String? lastMutationPath;
  Object? lastBody;

  @override
  Future<dynamic> request(
    String method,
    String path, {
    Object? body,
    bool retried = false,
  }) async {
    if (method == 'GET' && path.endsWith('/extensions/summary')) {
      return {
        'total': 3,
        'pending': 1,
        'sending': 0,
        'delivered': 2,
        'failed': 0,
      };
    }
    if (method == 'GET' && path.endsWith('/deliveries/summary')) {
      return {
        'total': 3,
        'pending': 1,
        'sending': 0,
        'delivered': 2,
        'failed': 0,
      };
    }
    if (method == 'GET' && path.contains('/deliveries?')) {
      return [
        {
          'id': 'delivery-1',
          'eventType': 'analytics.event',
          'status': 'delivered',
          'attempts': 1,
          'responseStatus': 204,
        },
      ];
    }
    if (method == 'POST' && path.endsWith('/extensions')) {
      lastMutationPath = path;
      lastBody = body;
      return {
        'extension': {
          'id': 'extension-2',
          'extensionKey': 'warehouse.export',
          'name': 'Warehouse export',
          'version': '1.2.0',
          'endpointUrl': 'https://hooks.example.test/export',
          'subscriptions': ['analytics.event'],
          'status': 'enabled',
          'secretConfigured': true,
        },
        'secret': 'test-secret',
      };
    }
    return [
      {
        'id': 'extension-1',
        'extensionKey': 'crm.sync',
        'name': 'CRM sync',
        'version': '1.0.0',
        'endpointUrl': 'https://extensions.example.test/hook',
        'subscriptions': ['analytics.event'],
        'status': 'enabled',
        'secretConfigured': true,
      },
    ];
  }
}
