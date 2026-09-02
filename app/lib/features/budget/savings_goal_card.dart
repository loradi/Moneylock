import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../data/savings_goal.dart';
import '../../theme/app_theme.dart';
import '../../widgets/kit.dart';

class SavingsGoalCard extends StatelessWidget {
  const SavingsGoalCard({
    super.key,
    required this.goal,
    required this.planCurrency,
    required this.contributionPerCycle,
    required this.cycleDays,
    required this.onEdit,
  });

  final SavingsGoal? goal;
  final String planCurrency;
  final double contributionPerCycle;
  final int cycleDays;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final currentGoal = goal;
    if (currentGoal == null) {
      return AppCard(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              const Icon(Icons.savings_outlined, color: AppColors.primary),
              const SizedBox(width: 10),
              const Expanded(
                child: Text('Turn unassigned income into a savings goal.'),
              ),
              Semantics(
                button: true,
                label: 'Add a savings goal',
                child: TextButton(
                  onPressed: onEdit,
                  child: const Text('Add goal'),
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (currentGoal.currency != planCurrency) {
      return AppCard(
        fill: AppColors.surfaceContainerLow,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Text(
            '${currentGoal.name} is tracked in ${currentGoal.currency}. Switch back to that plan currency before updating this goal.',
            style: AppTextStyles.bodyMd.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
          ),
        ),
      );
    }
    final projection = projectSavingsGoal(
      goal: currentGoal,
      contributionPerCycle: contributionPerCycle,
      cycleDays: cycleDays,
    );
    final progress = currentGoal.targetAmount == 0
        ? 0.0
        : (currentGoal.savedAmount / currentGoal.targetAmount)
              .clamp(0, 1)
              .toDouble();
    final schedule = projection.cyclesRemaining == null
        ? 'Assign money in this plan to forecast a finish date.'
        : projection.cyclesRemaining == 0
        ? 'Goal reached.'
        : '${projection.cyclesRemaining} cycle${projection.cyclesRemaining == 1 ? '' : 's'} left · ${fmtDate(projection.targetDate!)}';
    return AppCard(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.savings_outlined, color: AppColors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: AppSectionLabel(currentGoal.name.toUpperCase()),
                ),
                Semantics(
                  button: true,
                  label: 'Edit ${currentGoal.name} savings goal',
                  child: TextButton(
                    onPressed: onEdit,
                    child: const Text('Edit'),
                  ),
                ),
              ],
            ),
            Text(
              '${fmtCurrency(currentGoal.savedAmount, currency: planCurrency)} of ${fmtCurrency(currentGoal.targetAmount, currency: planCurrency)}',
              style: AppTextStyles.headlineMd,
            ),
            const SizedBox(height: 8),
            Semantics(
              label:
                  '${(progress * 100).round()} percent of ${currentGoal.name} saved',
              value: '${(progress * 100).round()} percent',
              child: LinearProgressIndicator(value: progress),
            ),
            const SizedBox(height: 8),
            Text(
              schedule,
              style: AppTextStyles.bodyMd.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
            ),
            if (projection.cyclesRemaining != null &&
                projection.cyclesRemaining! > 0)
              Text(
                '${fmtCurrency(projection.contributionPerCycle, currency: planCurrency)} available per cycle · ${fmtCurrency(projection.remaining, currency: planCurrency)} remaining',
                style: AppTextStyles.bodyMd.copyWith(
                  fontSize: 12,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
