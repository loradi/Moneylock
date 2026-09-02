import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../theme/app_theme.dart';
import '../../widgets/kit.dart';

class PlanForeignCurrencyNotice extends StatelessWidget {
  const PlanForeignCurrencyNotice({super.key, required this.totals});

  final Map<String, double> totals;

  @override
  Widget build(BuildContext context) => AppCard(
    fill: AppColors.surfaceContainerLow,
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Text(
        'Other currencies in this period: ${totals.entries.map((entry) => fmtCurrency(entry.value, currency: entry.key)).join(', ')}. '
        'They are not included in this plan total.',
        style: AppTextStyles.bodyMd.copyWith(color: AppColors.onSurfaceVariant),
      ),
    ),
  );
}
