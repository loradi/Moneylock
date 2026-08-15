/// Deterministic boundaries around the local mentor model.
///
/// The model remains useful for spending and budgeting questions, but these
/// checks prevent the free-form chat from becoming a general assistant.
const mentorScopeRefusal =
    'I can only help with your Moneylock finances, spending, and budgets.';

final _outOfScopePatterns = <RegExp>[
  RegExp(
    r'\b(code|coding|program|python|javascript|dart|flutter|sql|script)\b',
  ),
  RegExp(r'\b(vot(e|ing)|politic|president|election|party)\b'),
  RegExp(r'\b(poem|poetry|song|lyrics|story|recipe|joke|roleplay)\b'),
  RegExp(r'\b(stock|shares|crypto|bitcoin|forex|investment|investing)\b'),
  RegExp(r'\b(tax|taxes|legal|lawyer|lawsuit|court)\b'),
  RegExp(r'\b(mortgage|loan approval|credit score|insurance policy)\b'),
];

bool mentorRequestAllowed(String request) {
  final normalized = request.trim().toLowerCase();
  if (normalized.isEmpty) return false;
  return !_outOfScopePatterns.any((pattern) => pattern.hasMatch(normalized));
}

String guardMentorResponse(String response) {
  final trimmed = response.trim();
  if (trimmed.isEmpty || trimmed.contains('```')) return mentorScopeRefusal;
  return trimmed;
}
