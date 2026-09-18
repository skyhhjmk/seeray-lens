import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:seeray_lens_admin/features/analytics/application/analytics_export.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('exports Excel-friendly CSV with quoting and formula protection', () {
    final csv = AnalyticsReportExport.csv(
      const ['Page', 'Views'],
      const [
        ['A page, "quoted"', 12],
        ['  =HYPERLINK("https://bad.test")', 1],
      ],
    );

    expect(csv.startsWith('\uFEFF'), isTrue);
    expect(csv, contains('"A page, ""quoted""","12"'));
    expect(csv, contains('"\'  =HYPERLINK(""https://bad.test"")","1"'));
    expect(csv, endsWith('\r\n'));
  });

  test('exports JSON as named columns with report metadata', () {
    final json =
        jsonDecode(
              AnalyticsReportExport.json(
                metadata: const {'report': 'Pages', 'from': '2026-09-01'},
                columns: const ['Page', 'Views'],
                rows: const [
                  ['/pricing', 7],
                ],
              ),
            )
            as Map<String, dynamic>;

    expect(json['report'], 'Pages');
    expect(json['from'], '2026-09-01');
    expect(json['rows'], [
      {'Page': '/pricing', 'Views': 7},
    ]);
  });

  test('creates a paginated, Unicode-capable PDF report', () async {
    final pdf = await AnalyticsReportExport.pdf(
      metadata: const {
        'reportTitle': '页面浏览报告',
        'from': '2026-09-01',
        'to': '2026-09-16',
        'dimension': 'page_title',
        'metric': 'page_views',
        'visualization': 'table',
        'segmentId': 'segment-1',
        'matchMode': 'any',
        'filters': [
          {'field': 'source', 'operator': 'contains', 'value': '春季'},
        ],
      },
      columns: const ['页面标题', '浏览量'],
      rows: List<List<Object?>>.generate(
        90,
        (index) => [
          index == 4
              ? '稀有字𠮷 emoji 🎉'
              : '中文页面 ${index + 1} /articles/${index + 1}',
          index + 1,
        ],
      ),
    );

    expect(String.fromCharCodes(pdf.take(5)), '%PDF-');
    expect(pdf.length, greaterThan(5 * 1024));

    final previewPath = Platform.environment['SEERAY_PDF_RENDER_FIXTURE'];
    if (previewPath != null) {
      await File(previewPath).writeAsBytes(pdf);
    }
  });
}
