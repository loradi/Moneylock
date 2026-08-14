import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../data/db.dart';
import '../../providers.dart';
import '../add/manual_form.dart';
import '../add/voice_button.dart';
import '../insights/insights_agent.dart';
import 'budget_bar.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(budgetSummaryProvider);
    final txs = ref.watch(transactionsStreamProvider).value ?? const [];
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('Moneylock'),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          child: const Icon(CupertinoIcons.add_circled_solid,
              color: CupertinoColors.activeBlue, size: 28),
          onPressed: () => _showAddSheet(context),
        ),
      ),
      child: CustomScrollView(
        slivers: [
          CupertinoSliverNavigationBar(largeTitle: const Text('Dashboard')),
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _TotalCard(summary: summary),
                  const SizedBox(height: 20),
                  const Text('This month by category',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  _BudgetList(summary: summary),
                  const SizedBox(height: 20),
                  const Text('Recent transactions',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                ],
              ),
            ),
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, i) => _TransactionRow(t: txs[i]),
              childCount: txs.length > 20 ? 20 : txs.length,
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 90)),
        ],
      ),
    );
  }

  void _showAddSheet(BuildContext context) {
    showCupertinoModalPopup<void>(
      context: context,
      builder: (context) => const _AddSheet(),
    );
  }
}

class _TotalCard extends StatelessWidget {
  final AsyncValue<BudgetSummary> summary;
  const _TotalCard({required this.summary});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: CupertinoColors.systemBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: CupertinoColors.separator),
      ),
      child: summary.when(
        data: (s) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('This month',
                style: TextStyle(color: CupertinoColors.secondaryLabel)),
            const SizedBox(height: 4),
            Text(fmtCurrency(s.totalSpent),
                style: const TextStyle(
                    fontSize: 30, fontWeight: FontWeight.bold)),
            if (s.totalLimit > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('of ${fmtCurrency(s.totalLimit)} budget',
                    style: const TextStyle(
                        fontSize: 13, color: CupertinoColors.secondaryLabel)),
              ),
          ],
        ),
        loading: () => const CupertinoActivityIndicator(),
        error: (e, _) => Text('Could not load summary: $e'),
      ),
    );
  }
}

class _BudgetList extends StatelessWidget {
  final AsyncValue<BudgetSummary> summary;
  const _BudgetList({required this.summary});

  @override
  Widget build(BuildContext context) {
    return summary.when(
      data: (s) {
        final withLimits = s.byCategory.entries
            .where((e) => (s.byCategoryLimits[e.key] ?? 0) > 0)
            .toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        if (withLimits.isEmpty) {
          return const Text('No budgets set yet — add them in Settings.',
              style: TextStyle(
                  fontSize: 13, color: CupertinoColors.secondaryLabel));
        }
        return Column(
          children: [
            for (final e in withLimits)
              BudgetBar(
                category: e.key,
                spent: e.value,
                limit: s.byCategoryLimits[e.key]!,
              ),
          ],
        );
      },
      loading: () => const CupertinoActivityIndicator(),
      error: (e, _) => Text('Could not load budgets: $e'),
    );
  }
}

class _TransactionRow extends StatelessWidget {
  final Transaction t;
  const _TransactionRow({required this.t});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.merchant.isEmpty ? t.category : t.merchant,
                    style: const TextStyle(fontSize: 15),
                    overflow: TextOverflow.ellipsis),
                Text('${t.category} · ${fmtDate(t.timestamp)}',
                    style: const TextStyle(
                        fontSize: 12, color: CupertinoColors.secondaryLabel)),
              ],
            ),
          ),
          Text(fmtCurrency(t.amount),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

class _AddSheet extends ConsumerStatefulWidget {
  const _AddSheet();

  @override
  ConsumerState<_AddSheet> createState() => _AddSheetState();
}

class _AddSheetState extends ConsumerState<_AddSheet> {
  String? _status;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Add transaction',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            const SizedBox(height: 20),
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text('Manually',
                  style: TextStyle(
                      fontSize: 13, color: CupertinoColors.secondaryLabel)),
            ),
            ManualForm(onStatus: (s) => _setStatus(s)),
            const SizedBox(height: 20),
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text('Or speak',
                  style: TextStyle(
                      fontSize: 13, color: CupertinoColors.secondaryLabel)),
            ),
            VoiceButton(onStatus: (s) => _setStatus(s)),
            if (_status != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_status!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 12, color: CupertinoColors.activeGreen)),
              ),
          ],
        ),
      ),
    );
  }

  void _setStatus(String s) => setState(() => _status = s);
}