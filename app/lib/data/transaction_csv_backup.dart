import 'db.dart';
import 'transactions_dao.dart';

class CsvImportResult {
  const CsvImportResult({
    required this.imported,
    required this.duplicates,
    required this.rejected,
  });

  final int imported;
  final int duplicates;
  final int rejected;
}

/// A portable, user-controlled backup of transaction records.
///
/// This deliberately has no filesystem or network dependency: callers can
/// copy the CSV into their preferred encrypted storage, then paste it back on
/// another installation. The stable transaction deduplication prevents an
/// import from creating duplicate records.
class TransactionCsvBackup {
  static const header =
      'timestamp,amount,currency,merchant,category,source,raw_text';

  String exportRows(Iterable<Transaction> transactions) {
    final rows = [...transactions]
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return [
      header,
      for (final transaction in rows)
        _encodeRow([
          transaction.timestamp.toUtc().toIso8601String(),
          transaction.amount.toString(),
          transaction.currency,
          transaction.merchant,
          transaction.category,
          transaction.source,
          transaction.rawText,
        ]),
    ].join('\n');
  }

  Future<CsvImportResult> importRows(TransactionsDao dao, String csv) async {
    final rows = _parseRows(csv);
    if (rows.isEmpty || _normalizedHeader(rows.first) != header) {
      throw const FormatException(
        'This is not a Moneylock transaction CSV backup.',
      );
    }
    var imported = 0;
    var duplicates = 0;
    var rejected = 0;
    for (final fields in rows.skip(1)) {
      final transaction = _readTransaction(fields);
      if (transaction == null) {
        rejected++;
        continue;
      }
      final outcome = await dao.insertWithDedup(transaction);
      if (outcome.inserted) {
        imported++;
      } else {
        duplicates++;
      }
    }
    return CsvImportResult(
      imported: imported,
      duplicates: duplicates,
      rejected: rejected,
    );
  }

  NewTransaction? _readTransaction(List<String> fields) {
    if (fields.length != 7) return null;
    final timestamp = DateTime.tryParse(fields[0].trim());
    final amount = double.tryParse(fields[1].trim());
    final currency = fields[2].trim().toUpperCase();
    final merchant = fields[3].trim();
    final category = fields[4].trim();
    final source = fields[5].trim();
    final rawText = fields[6].trim();
    if (timestamp == null ||
        amount == null ||
        !amount.isFinite ||
        amount <= 0 ||
        !RegExp(r'^[A-Z]{3}$').hasMatch(currency) ||
        merchant.isEmpty ||
        category.isEmpty ||
        source.isEmpty ||
        rawText.isEmpty) {
      return null;
    }
    return NewTransaction(
      amount: amount,
      currency: currency,
      merchant: merchant,
      category: category,
      source: source,
      rawText: rawText,
      timestamp: timestamp,
    );
  }

  List<List<String>> _parseRows(String value) {
    final rows = <List<String>>[];
    var row = <String>[];
    final field = StringBuffer();
    var quoted = false;
    for (var index = 0; index < value.length; index++) {
      final char = value[index];
      if (char == '"') {
        if (quoted && index + 1 < value.length && value[index + 1] == '"') {
          field.write('"');
          index++;
        } else {
          quoted = !quoted;
        }
      } else if (char == ',' && !quoted) {
        row.add(field.toString());
        field.clear();
      } else if ((char == '\n' || char == '\r') && !quoted) {
        if (char == '\r' &&
            index + 1 < value.length &&
            value[index + 1] == '\n') {
          index++;
        }
        row.add(field.toString());
        field.clear();
        if (row.any((item) => item.isNotEmpty)) rows.add(row);
        row = <String>[];
      } else {
        field.write(char);
      }
    }
    if (quoted) throw const FormatException('The CSV has an unclosed quote.');
    row.add(field.toString());
    if (row.any((item) => item.isNotEmpty)) rows.add(row);
    return rows;
  }

  String _normalizedHeader(List<String> fields) =>
      fields.map((field) => field.trim().toLowerCase()).join(',');

  String _encodeRow(List<String> fields) =>
      fields.map((field) => '"${field.replaceAll('"', '""')}"').join(',');
}
