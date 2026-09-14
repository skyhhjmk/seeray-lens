import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:seeray_lens_admin/app.dart';

void main() {
  testWidgets('shows the public landing page', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: SeeRayLensAdminApp()));
    await tester.pumpAndSettle();

    expect(find.text('SeeRay Lens'), findsOneWidget);
    expect(find.text('进入管理台'), findsOneWidget);
  });

  testWidgets('validates login form before sending a request', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: SeeRayLensAdminApp()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('进入管理台'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '登录'));
    await tester.pump();
    expect(find.text('请输入有效邮箱'), findsOneWidget);
    expect(find.text('密码至少需要 12 个字符'), findsOneWidget);
  });
}
