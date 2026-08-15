import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../data/db.dart';
import '../../providers.dart';
import '../../theme/app_theme.dart';
import '../../theme/category_style.dart';
import '../../widgets/kit.dart';
import '../insights/insights_agent.dart';
import '../add/manual_form.dart';
import '../add/voice_button.dart';
import 'budget_bar.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(budgetSummaryProvider);
    final txs = ref.watch(transactionsStreamProvider).value ?? const [];
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: AppGlassHeader(
                eyebrow: 'MONEYLOCK',
                title: 'Dashboard',
                leading: IconButton(
                  onPressed: () => _showAddSheet(context),
                  icon: const Icon(Icons.add_circle_outline),
                  color: AppColors.primary,
                ),
                onAvatarTap: () => context.push('/settings'),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.margin,
                20,
                AppSpacing.margin,
                0,
              ),
              sliver: SliverToBoxAdapter(child: _TotalCard(summary: summary)),
            ),
            const SliverPadding(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.margin,
                28,
                AppSpacing.margin,
                8,
              ),
              sliver: SliverToBoxAdapter(
                child: AppSectionLabel('BUDGET HEALTH'),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.margin,
              ),
              sliver: SliverToBoxAdapter(child: _BudgetList(summary: summary)),
            ),
            const SliverPadding(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.margin,
                28,
                AppSpacing.margin,
                8,
              ),
              sliver: SliverToBoxAdapter(
                child: AppSectionLabel('RECENT TRANSACTIONS'),
              ),
            ),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) => _TransactionRow(t: txs[i]),
                childCount: txs.length > 20 ? 20 : txs.length,
              ),
            ),
            if (txs.isEmpty)
              const SliverToBoxAdapter(
                child: AppEmptyState(
                  icon: Icons.receipt_long_outlined,
                  title: 'No transactions yet',
                  body: 'Add your first expense to start seeing your money clearly.',
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 90)),
          ],
        ),
      ),
    );
  }

  void _showAddSheet(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    builder: (_) => const _AddSheet(),
  );
}

class _TotalCard extends StatelessWidget {
  final AsyncValue<BudgetSummary> summary;
  const _TotalCard({required this.summary});
  @override
  Widget build(BuildContext context) => AppCard(
    glowOrb: true,
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: summary.when(
        data: (s) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'THIS MONTH',
              style: AppTextStyles.labelCaps.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              fmtCurrency(s.totalSpent),
              style: AppTextStyles.display.copyWith(fontSize: 38),
            ),
            if (s.totalLimit > 0)
              Text(
                'of ${fmtCurrency(s.totalLimit)} budget',
                style: AppTextStyles.bodyMd.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
              ),
          ],
        ),
        loading: () => const LinearProgressIndicator(),
        error: (e, _) => Text('Could not load summary: $e'),
      ),
    ),
  );
}

class _BudgetList extends StatelessWidget {
  final AsyncValue<BudgetSummary> summary;
  const _BudgetList({required this.summary});
  @override
  Widget build(BuildContext context) => summary.when(
    data: (s) {
      final entries =
          s.byCategory.entries
              .where((e) => (s.byCategoryLimits[e.key] ?? 0) > 0)
              .toList()
            ..sort((a, b) => b.value.compareTo(a.value));
      if (entries.isEmpty)
        return const AppEmptyState(
          icon: Icons.tune,
          title: 'No budgets set',
          body: 'Set monthly caps in Settings to track your limits.',
        );
      return Column(
        children: [
          for (final e in entries)
            BudgetBar(
              category: e.key,
              spent: e.value,
              limit: s.byCategoryLimits[e.key]!,
            ),
        ],
      );
    },
    loading: () => const LinearProgressIndicator(),
    error: (e, _) => Text('Could not load budgets: $e'),
  );
}

class _TransactionRow extends StatelessWidget {
  final Transaction t;
  const _TransactionRow({required this.t});
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

class _AddSheet extends ConsumerStatefulWidget {
  const _AddSheet();
  @override
  ConsumerState<_AddSheet> createState() => _AddSheetState();
}

class _AddSheetState extends ConsumerState<_AddSheet> {
  String? _status;
  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.margin,
        12,
        AppSpacing.margin,
        MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.borderSubtle,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text('Add transaction', style: AppTextStyles.headlineMd),
          const SizedBox(height: 20),
          const AppSectionLabel('MANUALLY'),
          const SizedBox(height: 8),
          ManualForm(onStatus: _setStatus),
          const SizedBox(height: 12),
          const AppSectionLabel('OR SPEAK'),
          const SizedBox(height: 8),
          VoiceButton(onStatus: _setStatus),
          if (_status != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                _status!,
                textAlign: TextAlign.center,
                style: AppTextStyles.bodyMd.copyWith(color: AppColors.primary),
              ),
            ),
        ],
      ),
    ),
  );
  void _setStatus(String status) => setState(() => _status = status);
}
