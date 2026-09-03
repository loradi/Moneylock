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
  final commandTarget = RegExp(
    r'\b(?:add|log|record|spent|bought|paid|agrega|agregar|a[nñ]ade|a[nñ]adir|registra|registrar|anota|anotar|gast[eé]|compra|compr[eé]|paga|pag[ué])\b.*?\b(?:to|at|in|on|a|al|en|para|por)\s+(.+)$',
    caseSensitive: false,
  ).firstMatch(normalized)?.group(1)?.trim();
  if (commandTarget != null) {
    // "Add 54 to groceries" names a category, not a merchant. Keeping
    // "Add" as the merchant made otherwise successful Vector entries look
    // broken in history and the dashboard.
    if (_matchCategory(commandTarget) != null) return null;
    return commandTarget
        .split(' ')
        .map(
          (word) => word.isEmpty
              ? word
              : '${word[0].toUpperCase()}${word.substring(1)}',
        )
        .join(' ');
  }
  final cleaned = normalized
      .replaceFirst(
        RegExp(r'\$?\s?[0-9]+(?:\.[0-9]{1,2})?\s*(usd|cad|dollars|us|ca)?.*$'),
        '',
      )
      .replaceAll(RegExp(r'\b(usd|cad|dollars|us|ca)\b'), '')
      .trim();
  if (cleaned.isEmpty) return null;
  return cleaned
      .split(' ')
      .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');
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
