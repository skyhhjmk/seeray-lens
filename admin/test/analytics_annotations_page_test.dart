import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seeray_lens_admin/core/network/seeray_api.dart';
import 'package:seeray_lens_admin/features/analytics/presentation/analytics_annotations_page.dart';
import 'package:seeray_lens_admin/features/auth/application/auth_controller.dart';

void main() {
  testWidgets('creates, edits, and deletes a dated analytics annotation', (
    tester,
  ) async {
    final api = _AnnotationsApi();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiProvider.overrideWithValue(api)],
        child: const MaterialApp(
          home: AnalyticsAnnotationsPage(siteId: 'site-1', embedded: true),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('No notes in this reporting range.'), findsOneWidget);

    await tester.tap(find.text('Add note'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.labelText == 'What happened?',
      ),
      'Campaign launch',
    );
    await tester.pump();
    await tester.tap(find.text('Save note'));
    await tester.pumpAndSettle();
    expect(find.text('Campaign launch'), findsOneWidget);
    expect(api.lastMutationMethod, 'POST');

    await tester.tap(find.byTooltip('Note actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.labelText == 'What happened?',
      ),
      'Campaign launch moved',
    );
    await tester.pump();
    await tester.tap(find.text('Save note'));
    await tester.pumpAndSettle();
    expect(find.text('Campaign launch moved'), findsOneWidget);
    expect(api.lastMutationMethod, 'PUT');

    await tester.tap(find.byTooltip('Note actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();
    expect(find.text('No notes in this reporting range.'), findsOneWidget);
    expect(api.lastMutationMethod, 'DELETE');
  });
}

class _AnnotationsApi extends SeeRayApi {
  _AnnotationsApi() : super(baseUrl: 'https://lens.example.test');

  final List<Map<String, dynamic>> notes = [];
  String? lastMutationMethod;
  int _nextId = 0;

  @override
  Future<dynamic> request(
    String method,
    String path, {
    Object? body,
    bool retried = false,
  }) async {
    final uri = Uri.parse(path);
    expect(uri.path, startsWith('/api/v1/sites/site-1/annotations'));
    if (method != 'GET') lastMutationMethod = method;
    if (method == 'GET') {
      final from = uri.queryParameters['from']!;
      final to = uri.queryParameters['to']!;
      return {
        'from': from,
        'to': to,
        'canManage': true,
        'annotations': notes
            .where((note) {
              final date = note['date'] as String;
              return date.compareTo(from) >= 0 && date.compareTo(to) <= 0;
            })
            .toList(growable: false),
      };
    }
    if (method == 'POST') {
      final values = Map<String, dynamic>.from(body! as Map);
      final note = {'id': 'annotation-${++_nextId}', ...values};
      notes.add(note);
      return note;
    }
    final id = uri.pathSegments.last;
    if (method == 'PUT') {
      final values = Map<String, dynamic>.from(body! as Map);
      final index = notes.indexWhere((note) => note['id'] == id);
      notes[index] = {'id': id, ...values};
      return notes[index];
    }
    if (method == 'DELETE') {
      notes.removeWhere((note) => note['id'] == id);
      return null;
    }
    fail('Unexpected request $method $path');
  }
}
