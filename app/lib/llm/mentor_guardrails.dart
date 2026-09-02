/// Deterministic boundaries around the local mentor model.
///
/// The model is a finance and Moneylock assistant, never a general assistant.
const mentorScopeRefusal =
    'I can only help with financial topics or using Moneylock.';

final _outOfScopePatterns = <RegExp>[
  RegExp(
    r'\b(code|coding|program|python|javascript|dart|flutter|sql|script)\b',
  ),
  RegExp(r'\b(vot(e|ing)|politic|president|election|party)\b'),
  RegExp(r'\b(poem|poetry|song|lyrics|story|recipe|joke|roleplay)\b'),
];

final _researchPattern = RegExp(
  r'\b(research|investigate|look up|find out|investiga|investigar|buscar|averigua)\b',
);

/// Broad enough to include both education (debt, investing, tax) and every
/// Moneylock command, while preventing unrelated research from reaching the
/// language model at all.
final _financialTopicPattern = RegExp(
  r'\b(finance|financial|money|budget|spend|spending|expense|transaction|purchase|subscription|saving|savings|income|salary|paycheck|debt|loan|credit|tax|taxes|stock|share|crypto|bitcoin|forex|invest|fund|index|portfolio|dividend|interest|apr|inflation|retirement|insurance|mortgage|currency|cash|moneylock|vector|receipt|goal|cap|limit|category|coffee|groceries|transport|entertainment|shopping|bills|utilities|finanzas|dinero|presupuesto|gasto|transacci[oó]n|compra|suscripci[oó]n|ahorro|ingreso|salario|deuda|pr[eé]stamo|cr[eé]dito|impuesto|inversi[oó]n|moneda|meta)\b',
);

bool mentorRequestAllowed(String request) {
  final normalized = request.trim().toLowerCase();
  if (normalized.isEmpty) return false;
  if (_outOfScopePatterns.any((pattern) => pattern.hasMatch(normalized))) {
    return false;
  }
  final isFinancial = _financialTopicPattern.hasMatch(normalized);
  if (_researchPattern.hasMatch(normalized) && !isFinancial) return false;
  return isFinancial;
}

String guardMentorResponse(String response) {
  final trimmed = response.trim();
  if (trimmed.isEmpty || trimmed.contains('```')) return mentorScopeRefusal;
  return trimmed;
}
