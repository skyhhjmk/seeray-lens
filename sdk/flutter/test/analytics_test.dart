import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:seeray_analytics_flutter/seeray_analytics_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('requires consent before it creates identifiers or sends events', () async {
    var requests = 0;
    final analytics = await SeeRayAnalytics.create(
      const SeeRayAnalyticsOptions(
        siteId: 'srl_demo',
        apiOrigin: 'https://lens.example.test',
        requireConsent: true,
      ),
      client: MockClient((_) async {
        requests++;
        return http.Response('', 202);
      }),
    );

    analytics.trackScreen(name: 'Pricing', url: 'https://www.example.test/pricing');
    expect(analytics.pendingEventCount, 0);
    expect(await analytics.flush(), isFalse);
    expect(requests, 0);

    await analytics.setConsent(granted: true);
    analytics.trackScreen(name: 'Pricing', url: 'https://www.example.test/pricing?source=ad#top');
    expect(analytics.pendingEventCount, 1);
    await analytics.flush();
    expect(requests, 1);
    analytics.close();
  });

  test('sends a schema-v1 minimized explicit event with scalar properties', () async {
    Map<String, dynamic>? payload;
    final analytics = await SeeRayAnalytics.create(
      const SeeRayAnalyticsOptions(siteId: 'srl_demo', apiOrigin: 'https://lens.example.test'),
      client: MockClient((request) async {
        payload = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response('', 202);
      }),
    );

    analytics.trackEvent(
      type: 'signup',
      url: 'https://www.example.test/signup?email=private#done',
      properties: {'plan': 'pro', 'count': 2, 'nested': {'no': 'nested'}},
    );
    expect(await analytics.flush(), isTrue);

    final event = (payload!['events'] as List).single as Map<String, dynamic>;
    expect(payload!['schemaVersion'], 1);
    expect(event['url'], 'https://www.example.test/signup');
    expect(event['properties'], {'plan': 'pro', 'count': 2});
    expect(event['visitorId'], matches(RegExp(r'^[0-9a-f-]{36}$')));
    expect(event['sessionId'], matches(RegExp(r'^[0-9a-f-]{36}$')));
    analytics.close();
  });

  test('withdrawal clears the queued events and stored consented identity', () async {
    final analytics = await SeeRayAnalytics.create(
      const SeeRayAnalyticsOptions(siteId: 'srl_demo', apiOrigin: 'https://lens.example.test'),
      client: MockClient((_) async => http.Response('', 202)),
    );
    analytics.trackGoal(name: 'signup_completed', url: 'https://www.example.test/done');
    expect(analytics.pendingEventCount, 1);
    await analytics.optOut();

    expect(analytics.consentState, SeeRayConsentState.denied);
    expect(analytics.pendingEventCount, 0);
    expect(await analytics.flush(), isFalse);
    analytics.close();
  });

  test('rejects a plaintext collector origin', () async {
    await expectLater(
      SeeRayAnalytics.create(
        const SeeRayAnalyticsOptions(siteId: 'srl_demo', apiOrigin: 'http://localhost:8080'),
      ),
      throwsArgumentError,
    );
  });
}
