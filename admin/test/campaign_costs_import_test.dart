import 'package:flutter_test/flutter_test.dart';
import 'package:seeray_lens_admin/features/analytics/application/campaign_costs.dart';

void main() {
  test('parses quoted campaign names and header order into normalized rows', () {
    final preview = CampaignCostImportPreview.parse(
      'campaign,source,date,medium,platform,currency,cost,clicks,impressions\r\n'
      '"Summer, brand",google,2026-09-17,paid_search,google_ads,USD,125.500000,87,3200\r\n',
    );

    expect(preview.rows, hasLength(1));
    expect(preview.rows.single.campaign, 'Summer, brand');
    expect(preview.rows.single.cost, '125.500000');
    expect(preview.rows.single.toJson()['platform'], 'google_ads');
    expect(preview.clicks, 87);
    expect(preview.impressions, 3200);
    expect(preview.firstDate, '2026-09-17');
  });

  test('rejects an invalid calendar date before preview can be imported', () {
    expect(
      () => CampaignCostImportPreview.parse(_csv(date: '2026-02-30')),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('Row 2'),
        ),
      ),
    );
  });

  test('rejects negative or malformed costs', () {
    expect(
      () => CampaignCostImportPreview.parse(_csv(cost: '-3.00')),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('cost'),
        ),
      ),
    );
    expect(
      () => CampaignCostImportPreview.parse(_csv(cost: '2.1234567')),
      throwsA(isA<FormatException>()),
    );
  });

  test(
    'rejects repeated daily campaign dimensions and unsupported platform names',
    () {
      final row =
          '2026-09-17,google_ads,google,paid_search,summer,USD,2.00,1,10';
      expect(
        () => CampaignCostImportPreview.parse(
          '${campaignCostCsvHeaders.join(',')}\n$row\n$row\n',
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('repeats'),
          ),
        ),
      );
      expect(
        () => CampaignCostImportPreview.parse(_csv(platform: 'unknown')),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('platform'),
          ),
        ),
      );
    },
  );

  test('rejects malformed quoting and empty templates', () {
    expect(
      () => CampaignCostImportPreview.parse(
        '${campaignCostCsvHeaders.join(',')}\n2026-09-17,google_ads,google,paid_search,"unfinished,USD,2.00,1,10',
      ),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => CampaignCostImportPreview.parse(
        '${campaignCostCsvHeaders.join(',')}\n',
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('at least one'),
        ),
      ),
    );
    expect(
      () => CampaignCostImportPreview.parse(
        '${campaignCostCsvHeaders.join(',')}\n'
        '2026-09-17,google_ads,google,paid_search,"summer"suffix,USD,2.00,1,10',
      ),
      throwsA(isA<FormatException>()),
    );
  });
}

String _csv({
  String date = '2026-09-17',
  String platform = 'google_ads',
  String cost = '12.50',
}) =>
    '${campaignCostCsvHeaders.join(',')}\n'
    '$date,$platform,google,paid_search,summer,USD,$cost,7,100\n';
