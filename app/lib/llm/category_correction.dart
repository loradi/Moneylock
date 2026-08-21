import 'prompts.dart';

String _normalize(String value) => value
    .toLowerCase()
    .replaceAll('á', 'a')
    .replaceAll('é', 'e')
    .replaceAll('í', 'i')
    .replaceAll('ó', 'o')
    .replaceAll('ú', 'u');

String? parseCategoryCorrection(String request) {
  final normalized = _normalize(request);
  final hasCorrectionCue = RegExp(
    r'\b(change|camb|correct|reclassif|move|put)\w*\b',
  ).hasMatch(normalized);
  if (!hasCorrectionCue) return null;
  final isBudgetRequest = RegExp(r'\b(limit|budget|cap)\w*\b').hasMatch(normalized);
  if (isBudgetRequest) return null;
  for (final category in categoryCatalog) {
    if (normalized.contains(_normalize(category))) return category;
  }
  return null;
}
