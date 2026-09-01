import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneylock/theme/app_theme.dart';

void main() {
  test('tokens de color light matchean la spec', () {
    expect(AppColors.primary, const Color(0xFF075B63));
    expect(AppColors.primaryBright, const Color(0xFF0B737B));
    expect(AppColors.onSurface, const Color(0xFF17201F));
    expect(AppColors.background, const Color(0xFFF6F8F7));
  });

  test('texto mono-data usa Geist y label-caps usan +0.1em uppercase', () {
    final label = AppTextStyles.labelCaps;
    expect(label.fontFamily, 'Geist');
    expect(label.fontWeight, FontWeight.w600);
    expect(label.letterSpacing, 0.1);
  });

  test('buildAppTheme produce Material3 light con primary teal', () {
    final theme = buildAppTheme();
    expect(theme.brightness, Brightness.light);
    expect(theme.colorScheme.primary, AppColors.primary);
    expect(theme.textTheme.bodyMedium?.fontFamily, 'Inter');
  });
}
