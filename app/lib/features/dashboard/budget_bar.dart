import 'package:flutter/cupertino.dart';

import '../../core/format.dart';

Color budgetBarColor(double progress) {
  if (progress >= 1.0) return CupertinoColors.systemRed;
  if (progress >= 0.8) return CupertinoColors.systemOrange;
  return CupertinoColors.systemGreen;
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
    final color = limit > 0 ? budgetBarColor(spent / limit) : CupertinoColors.systemGrey;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(category, style: const TextStyle(fontSize: 14)),
              Text('${fmtCurrency(spent)} / ${fmtCurrency(limit)}',
                  style: const TextStyle(fontSize: 13, color: CupertinoColors.secondaryLabel)),
            ],
          ),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: SizedBox(
              height: 6,
              child: Row(
                children: [
                  Expanded(
                    flex: (progress * 1000).round().clamp(0, 1000),
                    child: ColoredBox(color: color),
                  ),
                  Expanded(
                    flex: 1000 - (progress * 1000).round().clamp(0, 1000),
                    child: const ColoredBox(color: CupertinoColors.systemFill),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}