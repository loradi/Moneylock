import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../theme/app_theme.dart';

Color budgetBarColor(double progress) {
  if (progress >= 1.0) return AppColors.primaryBright;
  if (progress >= 0.8) return const Color(0xFFE58B00);
  return const Color(0xFF258A56);
}

class BudgetBar extends StatelessWidget {
  final String category;
  final double spent;
  final double limit;
  const BudgetBar({
    super.key,
    required this.category,
    required this.spent,
    required this.limit,
  });
  @override
  Widget build(BuildContext context) {
    final progress = limit > 0 ? (spent / limit).clamp(0.0, 1.0) : 0.0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                category,
                style: AppTextStyles.bodyMd.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '${fmtCurrency(spent)} / ${fmtCurrency(limit)}',
                style: AppTextStyles.monoData.copyWith(
                  fontSize: 12,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: AppColors.surfaceContainerHigh,
              color: budgetBarColor(limit > 0 ? spent / limit : 0),
            ),
          ),
        ],
      ),
    );
  }
}
