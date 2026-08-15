import 'package:flutter_test/flutter_test.dart';
import 'package:moneylock/core/format.dart';
import 'package:moneylock/theme/category_style.dart';

void main() {
  test('cada categoria del catalogo tiene icono y color', () {
    const catalog = [
      'Coffee & Dining',
      'Groceries',
      'Transport',
      'Entertainment',
      'Shopping & E-commerce',
      'Bills & Utilities',
      'Health',
      'Tech',
      'Travel',
      'Other',
    ];

    for (final category in catalog) {
      expect(categoryIcon(category), isNotNull, reason: category);
      expect(categoryContainerColor(category), isNotNull, reason: category);
    }
  });

  test('desconocida cae en Other', () {
    expect(categoryIcon('Unknown'), categoryIcon('Other'));
    expect(categoryContainerColor('Unknown'), categoryContainerColor('Other'));
  });

  test('los helpers de tiempo usan el formato de la UI', () {
    final now = DateTime.now();
    expect(fmtTime(DateTime(2026, 8, 15, 9, 5)), '09:05 AM');
    expect(fmtTimeAgo(now.subtract(const Duration(minutes: 5))), '5m ago');
    expect(fmtDayGroup(now), 'TODAY');
  });
}
