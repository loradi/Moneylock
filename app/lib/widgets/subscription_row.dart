import 'package:flutter/material.dart';

import '../core/format.dart';
import '../data/subscription_summary.dart';
import '../theme/app_theme.dart';
import 'brand_icon.dart';
import 'kit.dart';

class SubscriptionRow extends StatelessWidget {
  final SubscriptionSummary s;
  const SubscriptionRow({super.key, required this.s});
  @override
  Widget build(BuildContext context) => AppCard(
    child: Row(
      children: [
        SubscriptionAvatar(brandKey: s.brandKey, name: s.name),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(s.name, style: AppTextStyles.bodyMd.copyWith(fontWeight: FontWeight.w600)),
              Text(
                'Renews ${fmtDate(s.nextChargeDate)}',
                style: AppTextStyles.bodyMd.copyWith(fontSize: 13, color: AppColors.onSurfaceVariant),
              ),
            ],
          ),
        ),
        Text(fmtCurrency(s.amount), style: AppTextStyles.bodyMd.copyWith(fontWeight: FontWeight.w600)),
      ],
    ),
  );
}
