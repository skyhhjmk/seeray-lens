import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:seeray_lens_admin/app.dart';

void main() {
  testWidgets('shows the login page', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: SeeRayLensAdminApp()));
    await tester.pumpAndSettle();

    expect(find.text('SeeRay Lens'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
  });

  testWidgets('validates login form before sending a request', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: SeeRayLensAdminApp()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign in'));
    await tester.pump();
    expect(find.text('Enter a valid email'), findsOneWidget);
    expect(
      find.text('Password must be at least 12 characters'),
      findsOneWidget,
    );
  });
}
