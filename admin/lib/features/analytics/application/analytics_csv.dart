/// Parses comma-separated records with quoted fields and escaped double quotes.
///
/// Blank rows are ignored; whitespace after a closing quote is tolerated, but
/// other characters after a quoted field are rejected.
List<List<String>> parseAnalyticsCsvRecords(String source) {
  final records = <List<String>>[];
  final row = <String>[];
  final cell = StringBuffer();
  var inQuotes = false;
  var afterClosingQuote = false;
  for (var i = 0; i < source.length; i++) {
    final character = source[i];
    if (inQuotes) {
      if (character == '"') {
        if (i + 1 < source.length && source[i + 1] == '"') {
          cell.write('"');
          i++;
        } else {
          inQuotes = false;
          afterClosingQuote = true;
        }
      } else {
        cell.write(character);
      }
      continue;
    }
    if (afterClosingQuote &&
        character != ',' &&
        character != '\n' &&
        character != '\r') {
      if (character == ' ' || character == '\t') continue;
      throw const FormatException(
        'Unexpected characters follow a quoted CSV field.',
      );
    }
    if (character == '"') {
      if (cell.isNotEmpty) {
        throw const FormatException('CSV quotes must wrap a whole field.');
      }
      inQuotes = true;
      afterClosingQuote = false;
    } else if (character == ',') {
      afterClosingQuote = false;
      row.add(cell.toString());
      cell.clear();
    } else if (character == '\n' || character == '\r') {
      afterClosingQuote = false;
      row.add(cell.toString());
      cell.clear();
      if (row.any((value) => value.trim().isNotEmpty)) {
        records.add(List.of(row));
      }
      row.clear();
      if (character == '\r' && i + 1 < source.length && source[i + 1] == '\n') {
        i++;
      }
    } else {
      cell.write(character);
    }
  }
  if (inQuotes) {
    throw const FormatException('A quoted CSV field was not closed.');
  }
  row.add(cell.toString());
  if (row.any((value) => value.trim().isNotEmpty)) records.add(List.of(row));
  return records;
}
