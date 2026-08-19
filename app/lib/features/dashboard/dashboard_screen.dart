import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../data/transaction_summary.dart';
import '../../providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/kit.dart';
import '../../widgets/transaction_row.dart';
import '../insights/insights_agent.dart';
import '../add/manual_form.dart';
import '../add/voice_button.dart';
import '../../receipt/receipt_ocr_service.dart';
import '../../data/db.dart';
import 'budget_bar.dart';

List<Transaction> recentWithinLastWeek(List<Transaction> txs, {DateTime? now}) {
  final cutoff = (now ?? DateTime.now()).subtract(const Duration(days: 7));
  return txs.where((t) => !t.timestamp.isBefore(cutoff)).toList();
}

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(budgetSummaryProvider);
    final txs = ref.watch(transactionsStreamProvider).value ?? const [];
    final recentTxs = recentWithinLastWeek(txs);
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
                (context, i) => Dismissible(
                  key: ValueKey(recentTxs[i].id),
                  direction: DismissDirection.endToStart,
                  confirmDismiss: (_) => _confirmRemoveTransaction(context, ref, recentTxs[i]),
                  background: Container(
                    margin: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.margin,
                      vertical: 2,
                    ),
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    decoration: BoxDecoration(
                      color: AppColors.error,
                      borderRadius: BorderRadius.circular(AppRadii.xl),
                    ),
                    child: const Icon(Icons.delete_outline, color: Colors.white),
                  ),
                  child: TransactionRow(t: TransactionSummary.fromTransaction(recentTxs[i])),
                ),
                childCount: recentTxs.length > 20 ? 20 : recentTxs.length,
              ),
            ),
            if (txs.isEmpty)
              const SliverToBoxAdapter(
                child: AppEmptyState(
                  icon: Icons.receipt_long_outlined,
                  title: 'No transactions yet',
                  body: 'Add your first expense to start seeing your money clearly.',
                ),
              )
            else if (recentTxs.isEmpty)
              const SliverToBoxAdapter(
                child: AppEmptyState(
                  icon: Icons.receipt_long_outlined,
                  title: 'Nothing this week',
                  body: 'Your recent activity will show up here.',
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

  Future<bool> _confirmRemoveTransaction(BuildContext context, WidgetRef ref, Transaction t) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${t.merchant.isEmpty ? t.category : t.merchant}?'),
        content: const Text('This transaction will be permanently deleted.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return false;
    await ref.read(appDatabaseProvider).transactionsDao.remove(t.id);
    return true;
  }
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

class _AddSheet extends ConsumerStatefulWidget {
  const _AddSheet();
  @override
  ConsumerState<_AddSheet> createState() => _AddSheetState();
}

class _AddSheetState extends ConsumerState<_AddSheet> {
  String? _status;
  final _receipt = ReceiptOcrService();
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const AppSectionLabel('MANUALLY'),
              OutlinedButton.icon(
                onPressed: _scanReceipt,
                icon: const Icon(Icons.camera_alt_outlined),
                label: const Text('Receipt'),
              ),
            ],
          ),
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

  Future<void> _scanReceipt() async {
    _setStatus('Scanning receipt on-device…');
    try {
      final text = await _receipt.scanReceipt();
      if (text == null) {
        _setStatus('No receipt text detected.');
        return;
      }
      final result = await ref
          .read(addFlowProvider)
          .run(rawText: text, source: 'receipt');
      _setStatus(
        result.inserted
            ? 'Receipt recorded.'
            : result.error ?? 'Could not record receipt.',
      );
    } catch (error) {
      _setStatus('Receipt scan failed: $error');
    }
  }
}
