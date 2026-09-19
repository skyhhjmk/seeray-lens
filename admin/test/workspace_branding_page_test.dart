import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seeray_lens_admin/core/network/seeray_api.dart';
import 'package:seeray_lens_admin/features/auth/application/auth_controller.dart';
import 'package:seeray_lens_admin/features/workspaces/application/workspace_controller.dart';
import 'package:seeray_lens_admin/features/workspaces/presentation/workspace_branding_page.dart';

void main() {
  testWidgets('edits workspace branding with a visual preview', (tester) async {
    tester.view.physicalSize = const Size(1000, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = _BrandingApi();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiProvider.overrideWithValue(api),
          workspaceProvider.overrideWith(_FakeWorkspaceController.new),
        ],
        child: const MaterialApp(
          locale: Locale('en'),
          supportedLocales: [Locale('en')],
          home: WorkspaceBrandingPage(workspaceId: 'workspace-1'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Brand identity'), findsOneWidget);
    expect(find.text('Live preview'), findsOneWidget);
    await tester.enterText(
      find.byType(TextFormField).at(0),
      'Northstar Analytics',
    );
    await tester.tap(find.text('#0F766E'));
    await tester.enterText(
      find.byType(TextFormField).at(2),
      'https://cdn.example.test/logo.svg',
    );
    await tester.ensureVisible(find.text('Save branding'));
    await tester.tap(find.text('Save branding'));
    await tester.pumpAndSettle();

    expect(api.lastMutationPath, '/api/v1/workspaces/workspace-1/branding');
    expect(api.lastBody, {
      'brandName': 'Northstar Analytics',
      'brandAccentColor': '#0F766E',
      'brandLogoUrl': 'https://cdn.example.test/logo.svg',
    });
    expect(find.text('Branding saved.'), findsOneWidget);
  });
}

class _FakeWorkspaceController extends WorkspaceController {
  @override
  Future<List<Workspace>> build() async => const [
    Workspace(id: 'workspace-1', name: 'Workspace', role: 'owner'),
  ];
}

class _BrandingApi extends SeeRayApi {
  _BrandingApi() : super(baseUrl: 'https://lens.example.test');

  String? lastPath;
  String? lastMutationPath;
  Object? lastBody;

  @override
  Future<dynamic> request(
    String method,
    String path, {
    Object? body,
    bool retried = false,
  }) async {
    lastPath = path;
    if (method == 'PATCH') {
      lastMutationPath = path;
      lastBody = body;
      return {'canManage': true, ...(body as Map).cast<String, dynamic>()};
    }
    if (path.endsWith('/branding')) {
      return {
        'canManage': true,
        'brandName': null,
        'brandAccentColor': null,
        'brandLogoUrl': null,
      };
    }
    if (path == '/api/v1/workspaces') {
      return [
        {'id': 'workspace-1', 'name': 'Workspace', 'role': 'owner'},
      ];
    }
    return null;
  }
}
