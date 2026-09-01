import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

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

class MonthlyPlanData {
  final double? income;
  final Map<String, double> limits;

  const MonthlyPlanData({required this.income, required this.limits});
}

final monthlyPlanProvider = FutureProvider.family<MonthlyPlanData, String>((
  ref,
  period,
) async {
  final db = ref.watch(appDatabaseProvider);
  final income = await db.settingsDao.monthlyIncome(period);
  final limits = await db.budgetsDao.limitsForPeriod(period);
  return MonthlyPlanData(income: income, limits: limits);
});

class BudgetScreen extends ConsumerStatefulWidget {
  const BudgetScreen({super.key});
  @override
  ConsumerState<BudgetScreen> createState() => _BudgetScreenState();
}

class _BudgetScreenState extends ConsumerState<BudgetScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  String _currency = 'USD';
  bool _currencyInitialized = false;
  String _hydratedPeriod = '';
  final _controllers = <String, TextEditingController>{};
  final _editedCategories = <String>{};

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final defaultCurrency = ref.watch(defaultCurrencyProvider).valueOrNull;
    if (!_currencyInitialized && defaultCurrency != null) {
      _currency = defaultCurrency;
      _currencyInitialized = true;
    }
    final categories = ref.watch(categoriesProvider).valueOrNull ?? const [];
    final names = categories.map((c) => c.name).toList();
    final records = {for (final c in categories) c.name: c};
    for (final name in names) {
      _controllers.putIfAbsent(name, TextEditingController.new);
    }
    final period = _periodKey();
    final plan = ref.watch(monthlyPlanProvider(period));
    final planData = plan.valueOrNull;
    if (planData != null && _hydratedPeriod != period) {
      _hydrateControllers(period, planData.limits);
    }
    final monthTransactions =
        ref
            .watch(transactionsStreamProvider)
            .valueOrNull
            ?.where((t) => _isInSelectedMonth(t.timestamp))
            .toList() ??
        const [];
    final spent = monthTransactions.fold<double>(0, (sum, t) => sum + t.amount);
    final planned =
        planData?.limits.values.fold<double>(0, (sum, v) => sum + v) ?? 0;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusScope.of(context).unfocus(),
        child: SafeArea(
          bottom: false,
          child: CustomScrollView(
            slivers: [
              const SliverToBoxAdapter(
                child: AppGlassHeader(eyebrow: 'MONEYLOCK', title: 'Plan'),
              ),
              SliverPadding(
                padding: const EdgeInsets.all(AppSpacing.margin),
                sliver: SliverToBoxAdapter(
                  child: _PlanOverview(
                    monthLabel: DateFormat('MMMM yyyy').format(_month),
                    income: planData?.income,
                    planned: planned,
                    spent: spent,
                    categoryCount: planData?.limits.length ?? 0,
                    isLoading: plan.isLoading,
                    onPreviousMonth: () => _changeMonth(-1),
                    onNextMonth: () => _changeMonth(1),
                    onEditIncome: () => _editIncome(planData?.income),
                    currency: _currency,
                    onCurrencyChanged: (value) {
                      setState(() => _currency = value);
                      ref
                          .read(appDatabaseProvider)
                          .settingsDao
                          .setDefaultCurrency(value);
                    },
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
                      const AppSectionLabel('MONTHLY ALLOCATION'),
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
                      onEdited: () => _editedCategories.add(names[i]),
                      onSave: _save,
                      onConfirmRemove: () => _removeCategory(names[i]),
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
      ),
    );
  }

  Future<void> _save(String category, String raw) async {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return;
    final amount = double.tryParse(trimmed);
    if (amount == null || amount <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Enter a valid amount')));
      }
      return;
    }
    try {
      await ref
          .read(appDatabaseProvider)
          .budgetsDao
          .upsert(
            category,
            amount,
            _periodKey(),
            cycle: 'monthly',
            cycleDays: DateUtils.getDaysInMonth(_month.year, _month.month),
            currency: _currency,
          );
      ref.invalidate(monthlyPlanProvider(_periodKey()));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save $category cap: $error')),
        );
      }
    }
  }

  Future<bool> _removeCategory(String category) async {
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
    if (confirmed != true) return false;
    await ref.read(appDatabaseProvider).categoriesDao.remove(category);
    if (mounted) setState(() {});
    return true;
  }

  Future<void> _addCategory() async {
    final created = await showDialog<String>(
      context: context,
      builder: (dialogContext) => const _AddCategoryDialog(),
    );
    if (created == null || created.isEmpty || !mounted) return;
    try {
      await ref.read(appDatabaseProvider).categoriesDao.add(created);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not add category: $error')));
    }
  }

  void _hydrateControllers(String period, Map<String, double> limits) {
    for (final entry in _controllers.entries) {
      // A user can start typing before the async plan query returns. Never
      // replace that in-progress value with the older value from storage.
      if (_editedCategories.contains(entry.key)) continue;
      final controller = entry.value;
      controller.value = controller.value.copyWith(
        text: limits[entry.key]?.toStringAsFixed(0) ?? '',
        selection: const TextSelection.collapsed(offset: -1),
        composing: TextRange.empty,
      );
    }
    _hydratedPeriod = period;
  }

  bool _isInSelectedMonth(DateTime value) =>
      value.year == _month.year && value.month == _month.month;

  void _changeMonth(int offset) => setState(() {
    _month = DateTime(_month.year, _month.month + offset);
    _hydratedPeriod = '';
    _editedCategories.clear();
  });

  Future<void> _editIncome(double? current) async {
    final controller = TextEditingController(
      text: current == null ? '' : current.toStringAsFixed(0),
    );
    final amount = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Income for ${DateFormat('MMMM').format(_month)}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Take-home income',
            prefixText: '$_currency ',
          ),
          onSubmitted: (value) =>
              Navigator.pop(context, double.tryParse(value.trim())),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, double.tryParse(controller.text.trim())),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (amount == null || amount <= 0) return;
    await ref
        .read(appDatabaseProvider)
        .settingsDao
        .setMonthlyIncome(_periodKey(), amount);
    ref.invalidate(monthlyPlanProvider(_periodKey()));
  }

  String _periodKey() =>
      '${_month.year.toString().padLeft(4, '0')}-${_month.month.toString().padLeft(2, '0')}';
}

class _AddCategoryDialog extends StatefulWidget {
  const _AddCategoryDialog();
  @override
  State<_AddCategoryDialog> createState() => _AddCategoryDialogState();
}

class _AddCategoryDialogState extends State<_AddCategoryDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('New category'),
    content: TextField(
      controller: _controller,
      autofocus: true,
      decoration: const InputDecoration(hintText: 'e.g. Pets'),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _controller.text.trim()),
        child: const Text('Add'),
      ),
    ],
  );
}

class _BudgetRow extends StatefulWidget {
  final String category;
  final TextEditingController controller;
  final String currency;
  final VoidCallback onEdited;
  final Future<void> Function(String, String) onSave;
  final Future<bool> Function() onConfirmRemove;
  final bool isDefault;
  const _BudgetRow({
    required this.category,
    required this.controller,
    required this.currency,
    required this.onEdited,
    required this.onSave,
    required this.onConfirmRemove,
    required this.isDefault,
  });

  @override
  State<_BudgetRow> createState() => _BudgetRowState();
}

class _BudgetRowState extends State<_BudgetRow> {
  Timer? _debounce;
  final _focusNode = FocusNode();
  bool _showSaved = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (!_focusNode.hasFocus) {
      _debounce?.cancel();
      _triggerSave();
    }
  }

  void _onChanged(String _) {
    widget.onEdited();
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), _triggerSave);
  }

  void _triggerSave() {
    final text = widget.controller.text;
    final parsed = double.tryParse(text.trim());
    widget.onSave(widget.category, text);
    if (parsed != null && parsed > 0 && mounted) {
      setState(() => _showSaved = true);
      Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted) setState(() => _showSaved = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) => Dismissible(
    key: ValueKey(widget.category),
    direction: DismissDirection.endToStart,
    confirmDismiss: (_) => widget.onConfirmRemove(),
    background: Container(
      margin: const EdgeInsets.only(bottom: 10),
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 20),
      decoration: BoxDecoration(
        color: AppColors.error,
        borderRadius: BorderRadius.circular(AppRadii.full),
      ),
      child: const Icon(Icons.delete_outline, color: Colors.white),
    ),
    child: Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 4, 6, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.category,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodyMd.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              SizedBox(
                width: 112,
                child: TextField(
                  controller: widget.controller,
                  focusNode: _focusNode,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  textInputAction: TextInputAction.done,
                  onChanged: _onChanged,
                  decoration: InputDecoration(hintText: 'No cap'),
                ),
              ),
              const SizedBox(width: 8),
              AnimatedOpacity(
                opacity: _showSaved ? 1 : 0,
                duration: const Duration(milliseconds: 200),
                child: const Icon(
                  Icons.check,
                  color: AppColors.primary,
                  size: 20,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _PlanOverview extends StatelessWidget {
  final String monthLabel;
  final double? income;
  final double planned;
  final double spent;
  final int categoryCount;
  final bool isLoading;
  final VoidCallback onPreviousMonth;
  final VoidCallback onNextMonth;
  final VoidCallback onEditIncome;
  final String currency;
  final ValueChanged<String> onCurrencyChanged;

  const _PlanOverview({
    required this.monthLabel,
    required this.income,
    required this.planned,
    required this.spent,
    required this.categoryCount,
    required this.isLoading,
    required this.onPreviousMonth,
    required this.onNextMonth,
    required this.onEditIncome,
    required this.currency,
    required this.onCurrencyChanged,
  });

  @override
  Widget build(BuildContext context) => AppCard(
    glowOrb: true,
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.calendar_month_outlined,
                color: AppColors.primary,
              ),
              const SizedBox(width: 8),
              const Expanded(child: AppSectionLabel('MONTHLY PLAN')),
              Text(currency, style: AppTextStyles.labelCaps),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              IconButton(
                tooltip: 'Previous month',
                onPressed: onPreviousMonth,
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Text(
                  monthLabel,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.headlineMd,
                ),
              ),
              IconButton(
                tooltip: 'Next month',
                onPressed: onNextMonth,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          if (isLoading) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
          ] else ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _PlanMetric(
                    label: 'INCOME',
                    value: income == null ? 'Set income' : fmtCurrency(income!),
                    onTap: onEditIncome,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _PlanMetric(
                    label: 'PLANNED',
                    value: fmtCurrency(planned),
                    detail:
                        '$categoryCount ${categoryCount == 1 ? 'category' : 'categories'}',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _PlanStatus(income: income, planned: planned, spent: spent),
          ],
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            initialValue: currency,
            decoration: const InputDecoration(labelText: 'Plan currency'),
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

class _PlanMetric extends StatelessWidget {
  final String label;
  final String value;
  final String? detail;
  final VoidCallback? onTap;

  const _PlanMetric({
    required this.label,
    required this.value,
    this.detail,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.surfaceContainerLow,
    borderRadius: BorderRadius.circular(AppRadii.xl),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.xl),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: AppTextStyles.labelCaps.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            Text(value, style: AppTextStyles.headlineMd),
            if (detail != null) ...[
              const SizedBox(height: 2),
              Text(
                detail!,
                style: AppTextStyles.bodyMd.copyWith(
                  fontSize: 12,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

class _PlanStatus extends StatelessWidget {
  final double? income;
  final double planned;
  final double spent;

  const _PlanStatus({
    required this.income,
    required this.planned,
    required this.spent,
  });

  @override
  Widget build(BuildContext context) {
    final remaining = planned - spent;
    final unassigned = income == null ? null : income! - planned;
    final isOverPlan = remaining < 0;
    final message = income == null
        ? 'Set your take-home income to see what is left to assign.'
        : unassigned! >= 0
        ? '${fmtCurrency(unassigned)} left to assign to your month.'
        : '${fmtCurrency(unassigned.abs())} over your planned income.';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isOverPlan || (unassigned != null && unassigned < 0)
            ? AppColors.errorContainer
            : AppColors.accentContainer,
        borderRadius: BorderRadius.circular(AppRadii.xl),
      ),
      child: Row(
        children: [
          Icon(
            isOverPlan || (unassigned != null && unassigned < 0)
                ? Icons.priority_high_rounded
                : Icons.check_circle_outline,
            color: isOverPlan || (unassigned != null && unassigned < 0)
                ? AppColors.error
                : AppColors.accent,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: AppTextStyles.bodyMd.copyWith(fontSize: 14),
            ),
          ),
          if (planned > 0)
            Text(
              '${fmtCurrency(spent)} spent',
              style: AppTextStyles.monoData.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}
