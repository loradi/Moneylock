class ParsedTransaction {
  final double? amount;
  final String currency;
  final String? merchant;
  final String? category;
  final double confidence;
  ParsedTransaction({
    this.amount,
    this.currency = 'USD',
    this.merchant,
    this.category,
    this.confidence = 0.4,
  });
}

const _categoryCatalog = {
  'Coffee & Dining': [
    'starbucks',
    'dunkin',
    'chipotle',
    'mcdonald',
    'uber eats',
    'doordash',
    'grubhub',
    'restaurant',
    'coffee',
    'cafe',
    'café',
    'comida',
    'restaurante',
    'restaurantes',
  ],
  'Groceries': [
    'whole foods',
    'trader joe',
    'safeway',
    'kroger',
    'walmart',
    'grocery',
    'mercado',
    'supermercado',
    'alimentos',
  ],
  'Transport': [
    'uber',
    'lyft',
    'shell',
    'chevron',
    'exxon',
    'transporte',
    'gasolina',
  ],
  'Entertainment': ['netflix', 'spotify', 'hulu', 'disney', 'movie'],
  'Shopping & E-commerce': [
    'amazon',
    'apple.com',
    'best buy',
    'target',
    'ebay',
    'etsy',
  ],
  'Bills & Utilities': [
    'comcast',
    'xfinity',
    'verizon',
    'at&t',
    'geico',
    'progressive',
    'factura',
    'facturas',
    'servicios',
  ],
  'Health': ['cvs', 'walgreens', 'pharmacy', 'doctor', 'salud', 'farmacia'],
  'Tech': ['icloud', 'google', 'dropbox', 'adobe', 'microsoft'],
  'Travel': [
    'airline',
    'delta',
    'united',
    'american airlines',
    'hotel',
    'airbnb',
    'viaje',
    'viajes',
  ],
};

const _explicitCategoryNames = {
  'coffee & dining': 'Coffee & Dining',
  'coffee': 'Coffee & Dining',
  'cafe': 'Coffee & Dining',
  'café': 'Coffee & Dining',
  'comida': 'Coffee & Dining',
  'groceries': 'Groceries',
  'grocery': 'Groceries',
  'mercado': 'Groceries',
  'supermercado': 'Groceries',
  'transport': 'Transport',
  'transporte': 'Transport',
  'entertainment': 'Entertainment',
  'entretenimiento': 'Entertainment',
  'shopping & e-commerce': 'Shopping & E-commerce',
  'compras': 'Shopping & E-commerce',
  'bills & utilities': 'Bills & Utilities',
  'facturas': 'Bills & Utilities',
  'servicios': 'Bills & Utilities',
  'health': 'Health',
  'salud': 'Health',
  'tech': 'Tech',
  'travel': 'Travel',
  'viajes': 'Travel',
  'other': 'Other',
};

String _normalize(String s) =>
    s.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');

double? _extractAmount(String raw) {
  // OCR receipts contain store IDs, phone numbers, tax lines, and item
  // quantities. A labeled final total is the only reliable amount to record.
  // Use the last eligible total because receipts commonly show a preliminary
  // subtotal earlier in the text.
  final receiptTotals = RegExp(
    r'\b(?:grand\s*total|total\s*due|amount\s*due|balance\s*due|total)\b(?!\s+(?:items?|qty|quantity|savings?))[^0-9]{0,32}([0-9]{1,6}(?:[,.][0-9]{2})?)',
    caseSensitive: false,
  ).allMatches(raw).toList();
  if (receiptTotals.isNotEmpty) {
    final value = receiptTotals.last.group(1)!.replaceAll(',', '');
    final parsed = double.tryParse(value);
    if (parsed != null && parsed > 0) return parsed;
  }
  final m = RegExp(r'\$\s?([0-9]+(?:\.[0-9]{1,2})?)').firstMatch(raw);
  if (m != null) return double.parse(m.group(1)!);
  final m2 = RegExp(
    r'([0-9]+(?:\.[0-9]{1,2})?)\s*(usd|cad|dollars|us|ca)\b',
    caseSensitive: false,
  ).firstMatch(raw);
  if (m2 != null) return double.parse(m2.group(1)!);
  final m3 = RegExp(r'(?<![\w$])([0-9]+(?:\.[0-9]{1,2})?)(?=$|\s)')
      .firstMatch(raw);
  if (m3 != null) return double.parse(m3.group(1)!);
  return null;
}

String? _matchCategory(String normalized) {
  for (final entry in _explicitCategoryNames.entries) {
    if (normalized.contains(entry.key)) return entry.value;
  }
  for (final entry in _categoryCatalog.entries) {
    for (final kw in entry.value) {
      if (normalized.contains(kw)) return entry.key;
    }
  }
  return null;
}

String? _cleanMerchant(String normalized) {
  final labeledEntryTarget = RegExp(
    r'^\s*(?:add|log|record|agrega|agregar|a[nñ]ade|a[nñ]adir|registra|registrar)\s+(?:(?:a|an|new)\s+)*(?:entry|expense|purchase|transaction|registro|gasto|compra|transacci[oó]n)\s+(?:for\s+)?\$?\d+(?:\.\d{1,2})?(?:\s*(?:usd|cad|eur|dollars))?\s+(.+)$',
    caseSensitive: false,
  ).firstMatch(normalized)?.group(1)?.trim();
  if (labeledEntryTarget != null) {
    final target = labeledEntryTarget
        .replaceFirst(RegExp(r'^(?:to|at|in|on|a|al|en|para|por)\s+'), '')
        .trim();
    if (_matchCategory(target) != null) return null;
    return _titleCase(target);
  }
  final commandTarget = RegExp(
    r'\b(?:add|log|record|spent|bought|paid|agrega|agregar|a[nñ]ade|a[nñ]adir|registra|registrar|anota|anotar|gast[eé]|compra|compr[eé]|paga|pag[ué])\b.*?\b(?:to|at|in|on|a|al|en|para|por)\s+(.+)$',
    caseSensitive: false,
  ).firstMatch(normalized)?.group(1)?.trim();
  if (commandTarget != null) {
    // "Add 54 to groceries" names a category, not a merchant. Keeping
    // "Add" as the merchant made otherwise successful Vector entries look
    // broken in history and the dashboard.
    if (_matchCategory(commandTarget) != null) return null;
    return _titleCase(commandTarget);
  }
  final cleaned = normalized
      .replaceFirst(
        RegExp(r'\$?\s?[0-9]+(?:\.[0-9]{1,2})?\s*(usd|cad|dollars|us|ca)?.*$'),
        '',
      )
      .replaceAll(RegExp(r'\b(usd|cad|dollars|us|ca)\b'), '')
      .trim();
  if (cleaned.isEmpty) return null;
  return _titleCase(cleaned);
}

String _titleCase(String value) {
  return value
      .split(' ')
      .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');
}

/// A terse merchant-and-amount message is a transaction entry, not general
/// conversation: `meatloaf 23`, `Tim Hortons 10`, or `Metro $18.50`.
/// Keep the grammar deliberately narrow to avoid mistaking a normal sentence
/// such as “I have 5 dollars” for a purchase.
bool isCompactTransactionEntry(String rawText) {
  final normalized = _normalize(rawText);
  if (!RegExp(
    r"^[a-zà-ÿ][a-zà-ÿ&'.-]*(?:\s+[a-zà-ÿ][a-zà-ÿ&'.-]*){0,2}\s+\$?[0-9]+(?:\.[0-9]{1,2})?(?:\s*(?:usd|cad|eur|dollars))?$",
    caseSensitive: false,
  ).hasMatch(normalized)) {
    return false;
  }
  return !RegExp(
    r'\b(?:i|we|you|my|the|a|an|meet|have|show|list|delete|remove|can|could|please|what|how|add|for|to|at|in|on|from|para|en|de)\b',
    caseSensitive: false,
  ).hasMatch(normalized);
}

/// A clear add/spend command is safe to route locally. This bypasses the
/// small on-device model for the hottest Vector path and supports natural
/// English and Spanish phrasing.
bool isExplicitTransactionCommand(String rawText) {
  if (_extractAmount(rawText) == null) return false;
  // These are financial commands too, but must keep their dedicated flows.
  // In particular, “add Netflix for $30 recurring” is a subscription, not a
  // one-off expense. Avoid routing it into the instant transaction path.
  if (RegExp(
    r'\b(subscription|subscriptions|recurring|savings?|goal|meta)\b',
    caseSensitive: false,
  ).hasMatch(rawText)) {
    return false;
  }
  // “Add” is ambiguous (for example, “add Netflix for $30” can describe a
  // subscription). Treat it as an instant expense only when the destination
  // or an expense noun makes the intent clear. Record/spend/pay verbs are
  // already explicit enough to stay on the fast path.
  if (RegExp(
    r'\b(?:log|record|spent|bought|paid|registra|registrar|anota|anotar|gast[eé]|compra|compr[eé]|paga|pag[ué])\b',
    caseSensitive: false,
  ).hasMatch(rawText)) {
    return true;
  }
  if (!RegExp(
    r'\b(?:add|agrega|agregar|a[nñ]ade|a[nñ]adir)\b',
    caseSensitive: false,
  ).hasMatch(rawText)) {
    return false;
  }
  return RegExp(
    r'\b(?:to|at|in|on|a|al|en|para|por|expense|expenses|transaction|purchase|gasto|gastos|transacci[oó]n|compra)\b',
    caseSensitive: false,
  ).hasMatch(rawText);
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
