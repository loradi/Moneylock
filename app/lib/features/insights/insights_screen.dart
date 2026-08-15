import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/kit.dart';
import '../../widgets/sparkline.dart';
import 'insights_agent.dart';

class InsightsScreen extends ConsumerWidget {
  const InsightsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final insights = ref.watch(insightsProvider);
    final summary = ref.watch(budgetSummaryProvider).valueOrNull;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            const SliverToBoxAdapter(
              child: AppGlassHeader(eyebrow: 'MONEYLOCK', title: 'Insights'),
            ),
            const SliverPadding(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.margin,
                22,
                AppSpacing.margin,
                6,
              ),
              sliver: SliverToBoxAdapter(
                child: Text(
                  'A clearer view of your spending patterns.',
                  style: AppTextStyles.bodyLg,
                ),
              ),
            ),
            if (summary != null)
              SliverPadding(
                padding: const EdgeInsets.all(AppSpacing.margin),
                sliver: SliverToBoxAdapter(child: _OverviewCard(summary)),
              ),
            insights.when(
              data: (capsules) => SliverList(
                delegate: SliverChildBuilderDelegate(
                  (_, i) => _CapsuleCard(capsules[i]),
                  childCount: capsules.length,
                ),
              ),
              loading: () => const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(40),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
              error: (e, _) => SliverToBoxAdapter(
                child: Text('Could not load insights: $e'),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 90)),
          ],
        ),
      ),
    );
  }
}

class _OverviewCard extends StatelessWidget {
  final BudgetSummary summary;
  const _OverviewCard(this.summary);
  @override
  Widget build(BuildContext context) => AppCard(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppSectionLabel('SPENDING PULSE'),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${summary.byCategory.length} active categories',
                  style: AppTextStyles.headlineMd,
                ),
              ),
              Text(
                fmtPercent(summary.totalSpent, summary.totalLimit),
                style: AppTextStyles.monoData.copyWith(
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Sparkline(
            series: summary.byCategory.values.isEmpty
                ? const [0]
                : summary.byCategory.values.toList(),
            color: AppColors.primary,
            height: 54,
          ),
        ],
      ),
    ),
  );
}

String fmtPercent(double spent, double limit) =>
    limit <= 0 ? 'NO CAP' : '${(spent / limit * 100).toStringAsFixed(0)}% USED';

class _CapsuleCard extends StatelessWidget {
  final InsightCapsule capsule;
  const _CapsuleCard(this.capsule);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.margin,
      8,
      AppSpacing.margin,
      8,
    ),
    child: AppCard(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(capsule.title, style: AppTextStyles.headlineMd),
            const SizedBox(height: 8),
            Text(
              capsule.body,
              style: AppTextStyles.bodyMd.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
