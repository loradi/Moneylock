class ParsedTransaction {
  final double? amount;
  final String currency;
  final String? merchant;
  final String? category;
  final double confidence;
  ParsedTransaction({this.amount, this.currency = 'USD', this.merchant,
      this.category, this.confidence = 0.4});
}

const _categoryCatalog = {
  'Coffee & Dining': ['starbucks', 'dunkin', 'chipotle', 'mcdonald', 'uber eats', 'doordash', 'grubhub', 'restaurant'],
  'Groceries': ['whole foods', 'trader joe', 'safeway', 'kroger', 'walmart'],
  'Transport': ['uber', 'lyft', 'shell', 'chevron', 'exxon'],
  'Entertainment': ['netflix', 'spotify', 'hulu', 'disney', 'movie'],
  'Shopping & E-commerce': ['amazon', 'apple.com', 'best buy', 'target', 'ebay', 'etsy'],
  'Bills & Utilities': ['comcast', 'xfinity', 'verizon', 'at&t', 'geico', 'progressive'],
  'Health': ['cvs', 'walgreens', 'pharmacy', 'doctor'],
  'Tech': ['icloud', 'google', 'dropbox', 'adobe', 'microsoft'],
  'Travel': ['airline', 'delta', 'united', 'american airlines', 'hotel', 'airbnb'],
};

String _normalize(String s) =>
    s.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');

double? _extractAmount(String raw) {
  final m = RegExp(r'\$\s?([0-9]+(?:\.[0-9]{1,2})?)').firstMatch(raw);
  if (m != null) return double.parse(m.group(1)!);
  final m2 = RegExp(r'([0-9]+(?:\.[0-9]{1,2})?)\s*(usd|cad|dollars|us|ca)\b', caseSensitive: false).firstMatch(raw);
  if (m2 != null) return double.parse(m2.group(1)!);
  final m3 = RegExp(r'(?<![\w$])([0-9]+(?:\.[0-9]{1,2})?)(?=$|\s)').firstMatch(raw);
  if (m3 != null) return double.parse(m3.group(1)!);
  return null;
}

String? _matchCategory(String normalized) {
  for (final entry in _categoryCatalog.entries) {
    for (final kw in entry.value) {
      if (normalized.contains(kw)) return entry.key;
    }
  }
  return null;
}

String? _cleanMerchant(String normalized) {
  final cleaned = normalized
      .replaceFirst(RegExp(r'\$?\s?[0-9]+(?:\.[0-9]{1,2})?\s*(usd|cad|dollars|us|ca)?.*$'), '')
      .replaceAll(RegExp(r'\b(usd|cad|dollars|us|ca)\b'), '')
      .trim();
  if (cleaned.isEmpty) return null;
  return cleaned.split(' ').map((w) => w.isEmpty ? w :
      '${w[0].toUpperCase()}${w.substring(1)}').join(' ');
}

ParsedTransaction? parseFallback(String rawText) {
  final normalized = _normalize(rawText);
  final amount = _extractAmount(rawText);
  if (amount == null) return null;
  final category = _matchCategory(normalized);
  final currency = RegExp(r'\bcad\b').hasMatch(normalized) ? 'CAD' : 'USD';
  return ParsedTransaction(
    amount: amount,
    currency: currency,
    merchant: _cleanMerchant(normalized),
    category: category ?? 'Other',
    confidence: category == null ? 0.3 : 0.5,
  );
}