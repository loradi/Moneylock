import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/notification_scheduler.dart';
import '../../data/db.dart';
import '../../providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/brand_icon.dart';
import '../../widgets/kit.dart';
import 'subscription_suggestions.dart';

final dismissedSubscriptionSuggestionsProvider = FutureProvider<Set<String>>(
  (ref) => ref.watch(appDatabaseProvider).settingsDao.dismissedSubscriptionSuggestions(),
);

final subscriptionSuggestionsProvider = Provider<List<SuggestedSubscription>>((ref) {
  final transactions = ref.watch(transactionsStreamProvider).valueOrNull ?? const [];
  final subscriptions = ref.watch(subscriptionsProvider).valueOrNull ?? const [];
  final dismissed = ref.watch(dismissedSubscriptionSuggestionsProvider).valueOrNull ?? const {};
  return detectSuggestions(
    transactions: transactions,
    existingSubscriptions: subscriptions,
    dismissedMerchants: dismissed,
  );
});

class SubscriptionsScreen extends ConsumerWidget {
  const SubscriptionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subscriptions = ref.watch(subscriptionsProvider).valueOrNull ?? const [];
    final suggestions = ref.watch(subscriptionSuggestionsProvider);
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 12, AppSpacing.margin, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.arrow_back),
                  ),
                  const Expanded(
                    child: Text('Subscriptions', style: AppTextStyles.headlineLgMobile),
                  ),
                  IconButton(
                    onPressed: () => _openAddSheet(context, ref),
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
            ),
            if (suggestions.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.margin, 12, AppSpacing.margin, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const AppSectionLabel('SUGGESTED'),
                    const SizedBox(height: 8),
                    for (final s in suggestions)
                      _SuggestionCard(
                        suggestion: s,
                        onAdd: () => _openAddSheet(
                          context,
                          ref,
                          prefill: SubscriptionsCompanion.insert(
                            name: s.merchant,
                            amount: s.averageAmount,
                            cycle: 'monthly',
                            nextChargeDate: DateTime(
                              s.mostRecentDate.year,
                              s.mostRecentDate.month + 1,
                              s.mostRecentDate.day,
                            ),
                            source: const Value('suggested'),
                            createdAt: DateTime.now(),
                          ),
                        ),
                        onDismiss: () async {
                          await ref.read(appDatabaseProvider).settingsDao.dismissSubscriptionSuggestion(s.merchant);
                          ref.invalidate(dismissedSubscriptionSuggestionsProvider);
                        },
                      ),
                  ],
                ),
              ),
            Expanded(
              child: subscriptions.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(AppSpacing.margin),
                        child: Text(
                          'No subscriptions tracked yet. Tap + to add one.',
                          textAlign: TextAlign.center,
                          style: AppTextStyles.bodyMd,
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.margin,
                        12,
                        AppSpacing.margin,
                        40,
                      ),
                      itemCount: subscriptions.length,
                      itemBuilder: (_, i) => _SubscriptionRow(
                        subscription: subscriptions[i],
                        onConfirmRemove: () => _confirmRemove(context, ref, subscriptions[i]),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openAddSheet(BuildContext context, WidgetRef ref, {SubscriptionsCompanion? prefill}) async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AddSubscriptionSheet(prefill: prefill),
    );
    if (created == true) ref.invalidate(subscriptionsProvider);
  }

  Future<bool> _confirmRemove(BuildContext context, WidgetRef ref, Subscription subscription) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${subscription.name}?'),
        content: const Text('This only stops tracking it here -- it does not cancel the actual subscription.'),
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
    await ref.read(notificationSchedulerProvider).cancel(subscriptionNotificationId(subscription.id));
    await ref.read(appDatabaseProvider).subscriptionsDao.remove(subscription.id);
    return true;
  }
}

class _SubscriptionRow extends StatelessWidget {
  final Subscription subscription;
  final Future<bool> Function() onConfirmRemove;
  const _SubscriptionRow({required this.subscription, required this.onConfirmRemove});

  @override
  Widget build(BuildContext context) => Dismissible(
    key: ValueKey(subscription.id),
    direction: DismissDirection.endToStart,
    confirmDismiss: (_) => onConfirmRemove(),
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
        child: Row(
          children: [
            SubscriptionAvatar(brandKey: subscription.brandKey, name: subscription.name),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(subscription.name, style: AppTextStyles.bodyMd.copyWith(fontWeight: FontWeight.w600)),
                  Text(
                    'Renews ${fmtDate(subscription.nextChargeDate)}',
                    style: AppTextStyles.bodyMd.copyWith(fontSize: 13, color: AppColors.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            Text(fmtCurrency(subscription.amount), style: AppTextStyles.bodyMd.copyWith(fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    ),
  );
}

class _SuggestionCard extends StatelessWidget {
  final SuggestedSubscription suggestion;
  final VoidCallback onAdd;
  final VoidCallback onDismiss;
  const _SuggestionCard({required this.suggestion, required this.onAdd, required this.onDismiss});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: AppCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(suggestion.merchant, style: AppTextStyles.bodyMd.copyWith(fontWeight: FontWeight.w600)),
                Text(
                  '${suggestion.occurrenceCount}x seen, ~${fmtCurrency(suggestion.averageAmount)}',
                  style: AppTextStyles.bodyMd.copyWith(fontSize: 13, color: AppColors.onSurfaceVariant),
                ),
              ],
            ),
          ),
          TextButton(onPressed: onDismiss, child: const Text('Dismiss')),
          FilledButton(onPressed: onAdd, child: const Text('Add')),
        ],
      ),
    ),
  );
}

class _AddSubscriptionSheet extends ConsumerStatefulWidget {
  final SubscriptionsCompanion? prefill;
  const _AddSubscriptionSheet({this.prefill});

  @override
  ConsumerState<_AddSubscriptionSheet> createState() => _AddSubscriptionSheetState();
}

class _AddSubscriptionSheetState extends ConsumerState<_AddSubscriptionSheet> {
  late final _nameController = TextEditingController(
    text: widget.prefill?.name.present == true ? widget.prefill!.name.value : '',
  );
  late final _amountController = TextEditingController(
    text: widget.prefill?.amount.present == true ? widget.prefill!.amount.value.toStringAsFixed(2) : '',
  );
  String _cycle = 'monthly';
  DateTime _nextChargeDate = DateTime.now();
  String? _brandKey;

  @override
  void initState() {
    super.initState();
    _nextChargeDate = widget.prefill?.nextChargeDate.present == true
        ? widget.prefill!.nextChargeDate.value
        : DateTime.now();
    _brandKey = widget.prefill?.brandKey.value;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _nextChargeDate,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (picked != null) setState(() => _nextChargeDate = picked);
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    final amount = double.tryParse(_amountController.text.trim());
    if (name.isEmpty || amount == null || amount <= 0) return;
    await ref.read(appDatabaseProvider).subscriptionsDao.add(
          SubscriptionsCompanion.insert(
            name: name,
            brandKey: Value(_brandKey),
            amount: amount,
            cycle: _cycle,
            nextChargeDate: _nextChargeDate,
            source: widget.prefill?.source ?? const Value('manual'),
            createdAt: DateTime.now(),
          ),
        );
    await ref.read(notificationSchedulerProvider).refresh();
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      AppSpacing.margin,
      AppSpacing.margin,
      AppSpacing.margin,
      MediaQuery.of(context).viewInsets.bottom + AppSpacing.margin,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('New subscription', style: AppTextStyles.headlineLgMobile),
        const SizedBox(height: 16),
        TextField(
          controller: _nameController,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Name', hintText: 'e.g. Netflix'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _amountController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Amount', suffixText: 'USD'),
        ),
        const SizedBox(height: 12),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'monthly', label: Text('Monthly')),
            ButtonSegment(value: 'yearly', label: Text('Yearly')),
          ],
          selected: {_cycle},
          onSelectionChanged: (v) => setState(() => _cycle = v.first),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: _pickDate,
          child: Text('Next charge: ${fmtDate(_nextChargeDate)}'),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 56,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final key in brandIcons.keys)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => setState(() => _brandKey = key),
                    child: CircleAvatar(
                      radius: 22,
                      backgroundColor: brandIcons[key]!.color,
                      child: Icon(
                        brandIcons[key]!.icon,
                        color: Colors.white,
                        size: _brandKey == key ? 26 : 20,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(onPressed: _save, child: const Text('Add subscription')),
      ],
    ),
  );
}
