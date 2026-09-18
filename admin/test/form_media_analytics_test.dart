import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seeray_lens_admin/core/network/seeray_api.dart';
import 'package:seeray_lens_admin/features/analytics/application/analytics_controller.dart';
import 'package:seeray_lens_admin/features/analytics/application/form_analytics.dart';
import 'package:seeray_lens_admin/features/analytics/application/media_analytics.dart';
import 'package:seeray_lens_admin/features/auth/application/auth_controller.dart';

void main() {
  test('form and media report requests carry the selected segment', () async {
    final api = _AnalyticsApi();
    final container = ProviderContainer(
      overrides: [apiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);

    final range = AnalyticsDateRange(
      DateTime(2026, 9, 1),
      DateTime(2026, 9, 7),
    );
    await container.read(
      formAnalyticsProvider(
        FormAnalyticsQuery(
          siteId: 'site-1',
          range: range,
          segmentId: 'segment-1',
        ),
      ).future,
    );
    await container.read(
      mediaAnalyticsProvider(
        MediaAnalyticsQuery(
          siteId: 'site-1',
          range: range,
          segmentId: 'segment-1',
        ),
      ).future,
    );

    expect(api.uris, hasLength(2));
    expect(
      api.uris.map((uri) => uri.path),
      containsAll([
        '/api/v1/sites/site-1/analytics/forms',
        '/api/v1/sites/site-1/analytics/media',
      ]),
    );
    expect(
      api.uris.every(
        (uri) =>
            uri.queryParameters['from'] == '2026-09-01' &&
            uri.queryParameters['to'] == '2026-09-07' &&
            uri.queryParameters['segmentId'] == 'segment-1',
      ),
      isTrue,
    );
  });
}

class _AnalyticsApi extends SeeRayApi {
  _AnalyticsApi() : super(baseUrl: 'https://lens.example.test');

  final uris = <Uri>[];

  @override
  Future<dynamic> request(
    String method,
    String path, {
    Object? body,
    bool retried = false,
  }) async {
    uris.add(Uri.parse(path));
    return {
      'from': '2026-09-01',
      'to': '2026-09-07',
      'rows': const <dynamic>[],
      'hasMore': false,
    };
  }
}
