import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Spreadsheet-safe export encoders for the rows already visible in analytics reports.
class AnalyticsReportExport {
  const AnalyticsReportExport._();

  static String csv(List<String> columns, List<List<Object?>> rows) {
    for (final row in rows) {
      if (row.length != columns.length) {
        throw ArgumentError('Every exported row must match the column count.');
      }
    }
    final lines = <String>[
      columns.map(_csvCell).join(','),
      ...rows.map((row) => row.map(_csvCell).join(',')),
    ];
    return '\uFEFF${lines.join('\r\n')}\r\n';
  }

  static String json({
    required Map<String, Object?> metadata,
    required List<String> columns,
    required List<List<Object?>> rows,
  }) {
    for (final row in rows) {
      if (row.length != columns.length) {
        throw ArgumentError('Every exported row must match the column count.');
      }
    }
    return const JsonEncoder.withIndent('  ').convert({
      ...metadata,
      'columns': columns,
      'rows': [
        for (final row in rows)
          Map<String, Object?>.fromIterables(columns, row),
      ],
    });
  }

  static Future<Uint8List> pdf({
    required Map<String, Object?> metadata,
    required List<String> columns,
    required List<List<Object?>> rows,
  }) async {
    for (final row in rows) {
      if (row.length != columns.length) {
        throw ArgumentError('Every exported row must match the column count.');
      }
    }

    final fontDataFuture = rootBundle.load(
      'assets/fonts/seeray-reports-cjk.ttf',
    );
    final codepointsFuture = rootBundle.loadString(
      'assets/fonts/seeray-reports-cjk-codepoints.txt',
    );
    final fontData = await fontDataFuture;
    final supportedRanges = _parseCodepointRanges(await codepointsFuture);
    String pdfText(String? value) => _pdfText(value, supportedRanges);
    final font = pw.Font.ttf(fontData);
    final title = pdfText(metadata['reportTitle']?.toString()).trim().isEmpty
        ? 'Analytics report'
        : pdfText(metadata['reportTitle']?.toString());
    final from = metadata['from']?.toString();
    final to = metadata['to']?.toString();
    final period = from != null && to != null ? '$from to $to' : null;
    final dimension = metadata['dimension']?.toString();
    final metric = metadata['metric']?.toString();
    final visualization = metadata['visualization']?.toString();
    final hasSegment = metadata['segmentId'] != null;
    final matchMode = metadata['matchMode']?.toString();
    final rawFilters = metadata['filters'];
    final filters = rawFilters is List
        ? rawFilters.whereType<Map>().map(_filterDescription).toList()
        : <String>[];
    final generatedAt = DateTime.now().toLocal().toString().substring(0, 19);
    final tableRows = rows
        .map((row) => row.map((cell) => pdfText(cell?.toString())).toList())
        .toList(growable: false);

    final document = pw.Document();
    final theme = pw.ThemeData.withFont(
      base: font,
      bold: font,
      italic: font,
      boldItalic: font,
      fontFallback: [pw.Font.helvetica()],
    );
    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(36, 38, 36, 42),
        maxPages: 20,
        theme: theme,
        header: (context) => pw.Container(
          margin: const pw.EdgeInsets.only(bottom: 20),
          child: pw.Row(
            children: [
              pw.Container(width: 8, height: 22, color: PdfColors.blue700),
              pw.SizedBox(width: 9),
              pw.Text(
                'SEERAY LENS  /  ANALYTICS',
                style: pw.TextStyle(
                  font: font,
                  fontSize: 9,
                  color: PdfColors.blueGrey700,
                  letterSpacing: 0.7,
                ),
              ),
            ],
          ),
        ),
        footer: (context) => pw.Container(
          alignment: pw.Alignment.centerRight,
          margin: const pw.EdgeInsets.only(top: 16),
          child: pw.Text(
            'Page ${context.pageNumber} of ${context.pagesCount}',
            style: pw.TextStyle(
              font: font,
              fontSize: 8,
              color: PdfColors.grey600,
            ),
          ),
        ),
        build: (context) => [
          pw.Text(
            title,
            style: pw.TextStyle(
              font: font,
              fontSize: 22,
              color: PdfColors.blueGrey900,
            ),
          ),
          if (period != null) ...[
            pw.SizedBox(height: 6),
            pw.Text(
              'Reporting period  $period',
              style: pw.TextStyle(
                font: font,
                fontSize: 10,
                color: PdfColors.grey700,
              ),
            ),
          ],
          pw.SizedBox(height: 4),
          pw.Text(
            'Generated $generatedAt',
            style: pw.TextStyle(
              font: font,
              fontSize: 8,
              color: PdfColors.grey600,
            ),
          ),
          if (dimension != null ||
              metric != null ||
              visualization != null ||
              hasSegment) ...[
            pw.SizedBox(height: 14),
            pw.Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                if (dimension != null)
                  _metadataChip('Breakdown', dimension, font, pdfText),
                if (metric != null)
                  _metadataChip('Measure', metric, font, pdfText),
                if (visualization != null)
                  _metadataChip('View', visualization, font, pdfText),
                if (hasSegment)
                  _metadataChip('Saved segment', 'Applied', font, pdfText),
              ],
            ),
          ],
          if (filters.isNotEmpty) ...[
            pw.SizedBox(height: 10),
            pw.Text(
              pdfText(
                'Audience filters (${matchMode == 'any' ? 'match any' : 'match all'}): ${filters.join('  ·  ')}',
              ),
              style: pw.TextStyle(
                font: font,
                fontSize: 8,
                color: PdfColors.grey700,
              ),
            ),
          ],
          pw.SizedBox(height: 20),
          if (rows.isEmpty)
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(18),
              decoration: const pw.BoxDecoration(
                color: PdfColors.grey100,
                borderRadius: pw.BorderRadius.all(pw.Radius.circular(5)),
              ),
              child: pw.Text(
                'No data for this report and filter selection.',
                style: pw.TextStyle(
                  font: font,
                  fontSize: 10,
                  color: PdfColors.grey700,
                ),
              ),
            )
          else
            pw.TableHelper.fromTextArray(
              headers: columns.map(pdfText).toList(growable: false),
              data: tableRows,
              border: pw.TableBorder(
                horizontalInside: const pw.BorderSide(
                  color: PdfColors.grey300,
                  width: 0.45,
                ),
                bottom: const pw.BorderSide(
                  color: PdfColors.grey400,
                  width: 0.65,
                ),
              ),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.blue50),
              headerStyle: pw.TextStyle(
                font: font,
                fontSize: 9,
                color: PdfColors.blueGrey900,
              ),
              cellStyle: pw.TextStyle(font: font, fontSize: 8.5),
              oddCellStyle: pw.TextStyle(
                font: font,
                fontSize: 8.5,
                color: PdfColors.blueGrey900,
              ),
              cellPadding: const pw.EdgeInsets.symmetric(
                horizontal: 7,
                vertical: 6,
              ),
              headerPadding: const pw.EdgeInsets.symmetric(
                horizontal: 7,
                vertical: 8,
              ),
              defaultColumnWidth: const pw.FlexColumnWidth(1.4),
              columnWidths: columns.isEmpty
                  ? const {}
                  : {
                      0: const pw.FlexColumnWidth(3),
                      for (var index = 1; index < columns.length; index++)
                        index: const pw.FlexColumnWidth(1.4),
                    },
              tableWidth: pw.TableWidth.max,
            ),
        ],
      ),
    );
    return Uint8List.fromList(await document.save());
  }

  static pw.Widget _metadataChip(
    String label,
    String value,
    pw.Font font,
    String Function(String?) pdfText,
  ) => pw.Container(
    padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: const pw.BoxDecoration(
      color: PdfColors.grey100,
      borderRadius: pw.BorderRadius.all(pw.Radius.circular(4)),
    ),
    child: pw.Text(
      pdfText('$label  ${_plainText(value).replaceAll('_', ' ')}'),
      style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey800),
    ),
  );

  static String _filterDescription(Map filter) {
    final field = filter['dimensionKey'] ?? filter['field'] ?? 'condition';
    final operator = switch (filter['operator']?.toString()) {
      'equals' => '=',
      'does_not_equal' => '!=',
      'greater_than' => '>',
      'at_least' => '>=',
      'less_than' => '<',
      'at_most' => '<=',
      final value => (value ?? '').toString().replaceAll('_', ' '),
    };
    final value = _plainText(filter['value']?.toString());
    return value.isEmpty
        ? '${_plainText(field.toString()).replaceAll('_', ' ')} $operator'
        : '${_plainText(field.toString()).replaceAll('_', ' ')} $operator "$value"';
  }

  static String _plainText(String? value) => (value ?? '')
      .replaceAll(RegExp(r'[\u0000-\u0008\u000B\u000C\u000E-\u001F]'), ' ')
      .trim();

  static String _pdfText(String? value, List<_CodepointRange> ranges) =>
      String.fromCharCodes(
        _plainText(
          value,
        ).runes.map((rune) => _supportsRune(rune, ranges) ? rune : 0x3F),
      );

  static bool _supportsRune(int rune, List<_CodepointRange> ranges) {
    var low = 0;
    var high = ranges.length - 1;
    while (low <= high) {
      final middle = low + ((high - low) >> 1);
      final range = ranges[middle];
      if (rune < range.start) {
        high = middle - 1;
      } else if (rune > range.end) {
        low = middle + 1;
      } else {
        return true;
      }
    }
    return false;
  }

  static List<_CodepointRange> _parseCodepointRanges(String source) => source
      .split(',')
      .where((range) => range.isNotEmpty)
      .map((range) {
        final values = range.split('-');
        return _CodepointRange(
          int.parse(values.first, radix: 16),
          int.parse(values.last, radix: 16),
        );
      })
      .toList(growable: false);

  static String _csvCell(Object? value) {
    var text = value?.toString() ?? '';
    if (RegExp(r'^[\s]*[=+@\-\t\r]').hasMatch(text)) text = "'$text";
    return '"${text.replaceAll('"', '""')}"';
  }
}

class _CodepointRange {
  const _CodepointRange(this.start, this.end);

  final int start;
  final int end;
}
