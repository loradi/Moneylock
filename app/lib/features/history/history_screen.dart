import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../data/db.dart';
import '../../llm/prompts.dart';
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
  bool _thisMonthOnly = false;
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

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
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.margin,
                4,
                AppSpacing.margin,
                6,
              ),
              sliver: SliverToBoxAdapter(
                child: TextField(
                  controller: _searchController,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Search merchant or category',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchController.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear search',
                            icon: const Icon(Icons.close),
                            onPressed: () {
                              _searchController.clear();
                              setState(() {});
                            },
                          ),
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.margin,
              ),
              sliver: SliverToBoxAdapter(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FilterChip(
                    label: const Text('This month'),
                    selected: _thisMonthOnly,
                    onSelected: (selected) =>
                        setState(() => _thisMonthOnly = selected),
                  ),
                ),
              ),
            ),
            ...txs.when(
              data: (items) {
                final query = _searchController.text.trim().toLowerCase();
                final now = DateTime.now();
                final filtered = items.where((transaction) {
                  final matchesSource =
                      _filter == 'All' || transaction.source == _filter;
                  final matchesSearch =
                      query.isEmpty ||
                      transaction.merchant.toLowerCase().contains(query) ||
                      transaction.category.toLowerCase().contains(query);
                  final matchesMonth =
                      !_thisMonthOnly ||
                      (transaction.timestamp.year == now.year &&
                          transaction.timestamp.month == now.month);
                  return matchesSource && matchesSearch && matchesMonth;
                }).toList();
                if (filtered.isEmpty) {
                  return [
                    const SliverToBoxAdapter(
                      child: AppEmptyState(
                        icon: Icons.history,
                        title: 'Nothing here yet',
                        body: 'Your recorded transactions will appear here.',
                      ),
                    ),
                  ];
                }
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
                        (_, i) => _HistoryRow(
                          entry.value[i],
                          onEdit: () => _editTransaction(entry.value[i]),
                          onDelete: () => _deleteTransaction(entry.value[i]),
                        ),
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

  Future<void> _editTransaction(Transaction transaction) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _EditTransactionSheet(transaction: transaction),
    );
  }

  Future<bool> _deleteTransaction(Transaction transaction) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Delete ${transaction.merchant.isEmpty ? transaction.category : transaction.merchant}?',
        ),
        content: const Text('This transaction will be permanently deleted.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return false;
    await ref.read(appDatabaseProvider).transactionsDao.remove(transaction.id);
    return true;
  }
}

class _HistoryRow extends StatelessWidget {
  final Transaction transaction;
  final VoidCallback onEdit;
  final Future<bool> Function() onDelete;

  const _HistoryRow(
    this.transaction, {
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) => Dismissible(
    key: ValueKey(transaction.id),
    direction: DismissDirection.endToStart,
    confirmDismiss: (_) => onDelete(),
    background: Container(
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpacing.margin,
        vertical: 7,
      ),
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 20),
      decoration: BoxDecoration(
        color: AppColors.error,
        borderRadius: BorderRadius.circular(AppRadii.xl),
      ),
      child: const Icon(Icons.delete_outline, color: Colors.white),
    ),
    child: InkWell(
      onTap: onEdit,
      child: Padding(
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
            Text(
              fmtCurrency(transaction.amount, currency: transaction.currency),
              style: AppTextStyles.monoData,
            ),
          ],
        ),
      ),
    ),
  );
}

class _EditTransactionSheet extends ConsumerStatefulWidget {
  const _EditTransactionSheet({required this.transaction});

  final Transaction transaction;

  @override
  ConsumerState<_EditTransactionSheet> createState() =>
      _EditTransactionSheetState();
}

class _EditTransactionSheetState extends ConsumerState<_EditTransactionSheet> {
  late final _merchant = TextEditingController(
    text: widget.transaction.merchant,
  );
  late final _amount = TextEditingController(
    text: widget.transaction.amount.toStringAsFixed(2),
  );
  late String _category = widget.transaction.category;

  @override
  void dispose() {
    _merchant.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = double.tryParse(_amount.text.trim());
    if (amount == null || amount <= 0) return;
    await ref
        .read(appDatabaseProvider)
        .transactionsDao
        .updateFields(
          widget.transaction.id,
          amount: amount,
          merchant: _merchant.text.trim(),
          category: _category,
        );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.margin,
        20,
        AppSpacing.margin,
        MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Edit transaction', style: AppTextStyles.headlineMd),
          const SizedBox(height: 16),
          TextField(
            controller: _merchant,
            decoration: const InputDecoration(labelText: 'Merchant'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Amount (${widget.transaction.currency})',
            ),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: _category,
            decoration: const InputDecoration(labelText: 'Category'),
            items: categoryCatalog
                .map(
                  (category) =>
                      DropdownMenuItem(value: category, child: Text(category)),
                )
                .toList(),
            onChanged: (value) {
              if (value != null) setState(() => _category = value);
            },
          ),
          const SizedBox(height: 18),
          FilledButton(onPressed: _save, child: const Text('Save changes')),
        ],
      ),
    ),
  );
}
