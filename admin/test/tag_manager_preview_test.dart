import 'package:flutter_test/flutter_test.dart';
import 'package:seeray_lens_admin/features/integration/application/tag_manager_preview.dart';

void main() {
  test('previews OR triggers and resolves the same runtime variables', () {
    final results = TagManagerPreview.evaluate(
      [
        {
          'type': 'event',
          'eventType': 'tag_signup',
          'triggers': [
            {'type': 'predefined', 'event': 'purchase'},
            {'type': 'event', 'event': 'signup'},
          ],
          'properties': {
            'page': '{{Page URL}}',
            'page_title': '{{Page Title}}',
            'plan': '{{Event Property: plan}}',
            'browser': '{{Browser}}',
            'missing': '{{Not Registered}}',
          },
        },
        {'type': 'page_view', 'eventType': 'tag_page_view'},
      ],
      event: 'signup',
      url: 'https://example.test/signup',
      title: 'Sign up',
      eventProperties: {'plan': 'pro'},
      context: {'Browser': 'Firefox'},
    );

    expect(results[0].status, TagPreviewStatus.fires);
    expect(results[0].eventType, 'tag_signup');
    expect(results[0].properties, {
      'plan': 'pro',
      'page': 'https://example.test/signup',
      'page_title': 'Sign up',
      'browser': 'Firefox',
      'missing': '{{Not Registered}}',
    });
    expect(results[1].status, TagPreviewStatus.notFired);
  });

  test('does not pretend to evaluate custom JavaScript triggers', () {
    final result = TagManagerPreview.evaluate([
      {
        'type': 'event',
        'eventType': 'tag_purchase',
        'triggers': [
          {
            'type': 'custom_js',
            'functionName': 'shouldSendPurchase',
            'code': '(event) => event.event === "purchase"',
          },
        ],
      },
    ], event: 'purchase').single;

    expect(result.status, TagPreviewStatus.needsBrowserCheck);
  });

  test(
    'requires all event-property filters and fails closed for missing data',
    () {
      final tags = [
        {
          'type': 'event',
          'eventType': 'qualified_signup',
          'triggers': [
            {
              'type': 'event',
              'event': 'signup',
              'conditions': [
                {'property': 'plan', 'operator': 'equals', 'value': 'pro'},
                {
                  'property': 'campaign',
                  'operator': 'starts_with',
                  'value': 'spring_',
                },
              ],
            },
          ],
        },
      ];

      final matching = TagManagerPreview.evaluate(
        tags,
        event: 'signup',
        eventProperties: {'plan': 'pro', 'campaign': 'spring_launch'},
      ).single;
      final missing = TagManagerPreview.evaluate(
        tags,
        event: 'signup',
        eventProperties: {'plan': 'pro'},
      ).single;

      expect(matching.status, TagPreviewStatus.fires);
      expect(missing.status, TagPreviewStatus.notFired);
    },
  );
}
