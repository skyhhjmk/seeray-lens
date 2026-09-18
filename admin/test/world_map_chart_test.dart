import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seeray_lens_admin/features/analytics/presentation/world_map_chart.dart';

void main() {
  testWidgets('loads bundled boundaries and selects a country with visits', (
    tester,
  ) async {
    String? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 720,
            child: WorldMapChart(
              sessionsByCountry: const {'US': 14, 'JP': 5},
              onCountrySelected: (code) => selected = code,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final map = find.byKey(const Key('world-country-map'));
    expect(map, findsOneWidget);
    final origin = tester.getTopLeft(map);
    final size = tester.getSize(map);
    await tester.tapAt(
      origin + Offset(size.width * (80 / 360), size.height * (50 / 180)),
    );

    expect(selected, 'US');
  });
}
