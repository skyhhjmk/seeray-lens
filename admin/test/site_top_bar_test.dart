import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seeray_lens_admin/shared/presentation/page_help_button.dart';
import 'package:seeray_lens_admin/shared/presentation/site_top_bar.dart';

void main() {
  testWidgets('groups site navigation into compact menus', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            appBar: SiteTopBar(
              siteId: 'site-1',
              selected: SiteTopTab.dashboard,
              help: const PageHelpButton(
                englishTitle: 'Help',
                chineseTitle: '帮助',
                englishBody: 'Help',
                chineseBody: '帮助',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Overview'), findsOneWidget);
    expect(find.text('Visitors'), findsOneWidget);
    expect(find.text('Acquisition'), findsOneWidget);
    expect(find.text('Behaviour'), findsOneWidget);
    expect(find.text('Configuration'), findsOneWidget);
    expect(find.text('Engagement'), findsNothing);

    await tester.tap(find.text('Visitors'));
    await tester.pumpAndSettle();

    expect(find.text('Engagement'), findsOneWidget);
    expect(find.text('Visit time'), findsOneWidget);
    expect(find.text('Locations'), findsOneWidget);
  });
}
