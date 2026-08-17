import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../data/db.dart';
import '../../providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/kit.dart';

final categoriesProvider = StreamProvider<List<Category>>((ref) async* {
  final dao = ref.watch(appDatabaseProvider).categoriesDao;
  await dao.ensureDefaults();
  yield* dao.watchAll();
});

class BudgetScreen extends ConsumerStatefulWidget {
  const BudgetScreen({super.key});
  @override
  ConsumerState<BudgetScreen> createState() => _BudgetScreenState();
}

class _BudgetScreenState extends ConsumerState<BudgetScreen> {
  String _cycle = 'monthly';
  int _cycleDays = 30;
  String _currency = 'USD';
  final _controllers = <String, TextEditingController>{};
  final _customController = TextEditingController();

  @override
  void dispose() {
    for (final c in _controllers.values) c.dispose();
    _customController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(categoriesProvider).valueOrNull ?? const [];
    final names = categories.map((c) => c.name).toList();
    final records = {for (final c in categories) c.name: c};
    for (final name in names) {
      _controllers.putIfAbsent(name, TextEditingController.new);
    }
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            const SliverToBoxAdapter(
              child: AppGlassHeader(eyebrow: 'MONEYLOCK', title: 'Budget'),
            ),
            SliverPadding(
              padding: const EdgeInsets.all(AppSpacing.margin),
              sliver: SliverToBoxAdapter(
                child: _PeriodCard(
                  cycle: _cycle,
                  cycleDays: _cycleDays,
                  currency: _currency,
                  onCycleChanged: (value) => setState(() {
                    _cycle = value;
                    _cycleDays = switch (value) {
                      'weekly' => 7,
                      'biweekly' => 14,
                      'monthly' => 30,
                      _ => _cycleDays,
                    };
                  }),
                  onDaysChanged: (value) =>
                      _cycleDays = int.tryParse(value) ?? 30,
                  onCurrencyChanged: (value) =>
                      setState(() => _currency = value),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.margin,
                8,
                AppSpacing.margin,
                8,
              ),
              sliver: SliverToBoxAdapter(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const AppSectionLabel('CATEGORY CAPS'),
                    OutlinedButton.icon(
                      onPressed: _addCategory,
                      icon: const Icon(Icons.add),
                      label: const Text('Add category'),
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.margin,
              ),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (_, i) => _BudgetRow(
                    category: names[i],
                    controller: _controllers[names[i]]!,
                    currency: _currency,
                    onSave: _save,
                    onRemove: () => _removeCategory(names[i]),
                    isDefault: records[names[i]]?.isDefault ?? false,
                  ),
                  childCount: names.length,
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 90)),
          ],
        ),
      ),
    );
  }

  Future<void> _save(String category, String raw) async {
    final amount = double.tryParse(raw);
    if (amount == null || amount <= 0) return;
    await ref
        .read(appDatabaseProvider)
        .budgetsDao
        .upsert(
          category,
          amount,
          _periodKey(),
          cycle: _cycle,
          cycleDays: _cycleDays,
          currency: _currency,
        );
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${fmtCurrency(amount)} $category cap saved')),
      );
  }

  Future<void> _removeCategory(String category) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove $category?'),
        content: const Text(
          'It will disappear from your category list. Existing transactions will remain unchanged.',
        ),
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
    if (confirmed != true) return;
    await ref.read(appDatabaseProvider).categoriesDao.remove(category);
    setState(() {});
  }

  Future<void> _addCategory() async {
    _customController.clear();
    final created = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('New category'),
        content: TextField(
          controller: _customController,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'e.g. Pets'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, _customController.text.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (created != null && created.isNotEmpty)
      await ref.read(appDatabaseProvider).categoriesDao.add(created);
  }

  String _periodKey() {
    final now = DateTime.now();
    return _cycle == 'monthly'
        ? '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}'
        : _cycle;
  }
}

class _BudgetRow extends StatelessWidget {
  final String category;
  final TextEditingController controller;
  final String currency;
  final Future<void> Function(String, String) onSave;
  final VoidCallback onRemove;
  final bool isDefault;
  const _BudgetRow({
    required this.category,
    required this.controller,
    required this.currency,
    required this.onSave,
    required this.onRemove,
    required this.isDefault,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: AppCard(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 4, 6, 4),
        child: Row(
          children: [
            Expanded(
              child: Text(
                category,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.bodyMd.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            SizedBox(
              width: 112,
              child: TextField(
                controller: controller,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  hintText: 'No cap',
                  suffixText: currency,
                ),
              ),
            ),
            IconButton(
              onPressed: () => onSave(category, controller.text),
              icon: const Icon(Icons.check, color: AppColors.primary),
            ),
            IconButton(
              tooltip: isDefault ? 'Remove system category' : 'Remove category',
              onPressed: onRemove,
              icon: const Icon(
                Icons.remove_circle_outline,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _PeriodCard extends StatelessWidget {
  final String cycle;
  final int cycleDays;
  final String currency;
  final ValueChanged<String> onCycleChanged;
  final ValueChanged<String> onDaysChanged;
  final ValueChanged<String> onCurrencyChanged;

  const _PeriodCard({
    required this.cycle,
    required this.cycleDays,
    required this.currency,
    required this.onCycleChanged,
    required this.onDaysChanged,
    required this.onCurrencyChanged,
  });

  @override
  Widget build(BuildContext context) => AppCard(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppSectionLabel('BUDGET PERIOD'),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'weekly', label: Text('Weekly')),
              ButtonSegment(value: 'biweekly', label: Text('Biweekly')),
              ButtonSegment(value: 'monthly', label: Text('Monthly')),
              ButtonSegment(value: 'custom', label: Text('Custom')),
            ],
            selected: {cycle},
            onSelectionChanged: (v) => onCycleChanged(v.first),
          ),
          if (cycle == 'custom')
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: TextFormField(
                initialValue: '$cycleDays',
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Days per cycle'),
                onChanged: onDaysChanged,
              ),
            ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            value: currency,
            decoration: const InputDecoration(labelText: 'Currency'),
            items: const [
              DropdownMenuItem(value: 'USD', child: Text('USD — US Dollar')),
              DropdownMenuItem(
                value: 'CAD',
                child: Text('CAD — Canadian Dollar'),
              ),
              DropdownMenuItem(value: 'EUR', child: Text('EUR — Euro')),
            ],
            onChanged: (v) {
              if (v != null) onCurrencyChanged(v);
            },
          ),
        ],
      ),
    ),
  );
}
