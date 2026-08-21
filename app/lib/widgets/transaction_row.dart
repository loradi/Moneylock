import 'package:flutter/material.dart';

import '../core/format.dart';
import '../data/transaction_summary.dart';
import '../theme/app_theme.dart';
import '../theme/category_style.dart';

class TransactionRow extends StatelessWidget {
  final TransactionSummary t;
  const TransactionRow({super.key, required this.t});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.margin,
      vertical: 7,
    ),
    child: Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: categoryContainerColor(t.category),
            borderRadius: BorderRadius.circular(AppRadii.xl),
          ),
          child: Icon(
            categoryIcon(t.category),
            color: AppColors.onSurface,
            size: 20,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t.merchant.isEmpty ? t.category : t.merchant,
                style: AppTextStyles.bodyMd.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                '${t.category} · ${fmtDate(t.timestamp)}',
                style: AppTextStyles.bodyMd.copyWith(
                  fontSize: 12,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        Text(fmtCurrency(t.amount), style: AppTextStyles.monoData),
      ],
    ),
  );
}
