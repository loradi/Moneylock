import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../data/db.dart';
import '../../providers.dart';
import '../../theme/app_theme.dart';
import '../../theme/category_style.dart';
import '../../widgets/kit.dart';

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});
  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  String _filter = 'All';
  @override
  Widget build(BuildContext context) {
    final txs = ref.watch(transactionsStreamProvider);
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            const SliverToBoxAdapter(
              child: AppGlassHeader(eyebrow: 'MONEYLOCK', title: 'History'),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 62,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.margin,
                    vertical: 12,
                  ),
                  children: [
                    for (final f in ['All', 'manual', 'voice'])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: AppPill(
                          label: f == 'All' ? f : f.toUpperCase(),
                          active: _filter == f,
                          onTap: () => setState(() => _filter = f),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            ...txs.when(
              data: (items) {
                final filtered = _filter == 'All'
                    ? items
                    : items.where((t) => t.source == _filter).toList();
                if (filtered.isEmpty)
                  return [
                    const SliverToBoxAdapter(
                      child: AppEmptyState(
                        icon: Icons.history,
                        title: 'Nothing here yet',
                        body: 'Your recorded transactions will appear here.',
                      ),
                    ),
                  ];
                final grouped = <String, List<Transaction>>{};
                for (final t in filtered) {
                  grouped
                      .putIfAbsent(fmtDayGroup(t.timestamp), () => [])
                      .add(t);
                }
                return [
                  for (final entry in grouped.entries) ...[
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.margin,
                        18,
                        AppSpacing.margin,
                        8,
                      ),
                      sliver: SliverToBoxAdapter(
                        child: Text(
                          entry.key,
                          style: AppTextStyles.labelCaps.copyWith(
                            color: AppColors.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (_, i) => _HistoryRow(entry.value[i]),
                        childCount: entry.value.length,
                      ),
                    ),
                  ],
                ];
              },
              loading: () => [
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(40),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ),
              ],
              error: (e, _) => [
                SliverToBoxAdapter(child: Text('Could not load history: $e')),
              ],
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 90)),
          ],
        ),
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  final Transaction transaction;
  const _HistoryRow(this.transaction);
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
            color: categoryContainerColor(transaction.category),
            borderRadius: BorderRadius.circular(AppRadii.xl),
          ),
          child: Icon(categoryIcon(transaction.category), size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                transaction.merchant.isEmpty
                    ? transaction.category
                    : transaction.merchant,
                style: AppTextStyles.bodyMd.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '${fmtTime(transaction.timestamp)} · ${transaction.source}',
                style: AppTextStyles.bodyMd.copyWith(
                  fontSize: 12,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        Text(fmtCurrency(transaction.amount), style: AppTextStyles.monoData),
      ],
    ),
  );
}
