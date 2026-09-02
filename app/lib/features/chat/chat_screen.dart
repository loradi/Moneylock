import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/budget_change_summary.dart';
import '../../data/db.dart';
import '../../data/new_subscription_summary.dart';
import '../../data/plan_action_summary.dart';
import '../../data/savings_goal.dart';
import '../../data/subscription_edit_summary.dart';
import '../../data/subscription_summary.dart';
import '../../data/transaction_edit_summary.dart';
import '../../data/transaction_summary.dart';
import '../../llm/category_correction.dart';
import '../../llm/mentor_guardrails.dart';
import '../../providers.dart';
import '../../theme/app_theme.dart';
import '../../receipt/receipt_ocr_service.dart';
import '../../widgets/subscription_row.dart';
import '../../widgets/transaction_row.dart';

final _amountRe = RegExp(r'\$\s?\d+(?:\.\d{1,2})?|\d+\.\d{2}');
bool hasMonetaryAmount(String text) => _amountRe.hasMatch(text);

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, this.quickAction});

  final String? quickAction;
  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  final _composerFocus = FocusNode();
  bool _thinking = false;
  int _lastCount = -1;

  @override
  void initState() {
    super.initState();
    if (widget.quickAction == 'addPurchase') {
      _controller.text = 'Add a purchase: ';
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _composerFocus.requestFocus(),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    _composerFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(messagesStreamProvider).value ?? const [];
    if (messages.length != _lastCount) {
      _lastCount = messages.length;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(
            _scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
          );
        }
      });
    }
    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      body: SafeArea(
        child: Column(
          children: [
            const _ChatHeader(),
            Expanded(
              child: messages.isEmpty && !_thinking
                  ? _VectorWelcome(onPrompt: _sendPrompt)
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.all(AppSpacing.md),
                      itemCount: messages.length + (_thinking ? 1 : 0),
                      itemBuilder: (_, i) {
                        if (i == messages.length) {
                          return const _Bubble(
                            role: 'mentor',
                            content: '',
                            thinking: true,
                          );
                        }
                        final m = messages[i];
                        return _Bubble(
                          role: m.role,
                          content: m.content,
                          kind: m.kind,
                          dataJson: m.dataJson,
                        );
                      },
                    ),
            ),
            _Composer(
              controller: _controller,
              focusNode: _composerFocus,
              onSend: _send,
              onReceipt: _scanReceipt,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _thinking) return;
    _controller.clear();
    final db = ref.read(appDatabaseProvider);
    await db.messagesDao.add('user', text);
    if (mounted) setState(() => _thinking = true);
    final correction = parseCategoryCorrection(text);
    if (correction != null) {
      final updated = await db.transactionsDao.updateMostRecentCategory(
        correction,
      );
      await db.messagesDao.add(
        'mentor',
        updated == null
            ? 'I could not find a recent transaction to recategorize.'
            : 'Updated ${updated.merchant.isEmpty ? updated.category : updated.merchant} to $correction.',
      );
    } else if (!mentorRequestAllowed(text)) {
      await db.messagesDao.add('mentor', mentorScopeRefusal);
    } else {
      final intent = await ref.read(mentorProvider).classify(text);
      // The classifier recognizes "record_transaction" explicitly; the
      // regex is kept as a safety net for confident cases where the
      // classifier fell back to "chat" (e.g. an LLM failure) but the text
      // still obviously names a dollar amount.
      final shouldRecord =
          intent.intent == 'record_transaction' ||
          (intent.intent == 'chat' &&
              !intent.degraded &&
              hasMonetaryAmount(text));
      if (shouldRecord) {
        final result = await ref
            .read(addFlowProvider)
            .run(rawText: text, source: 'manual', includeMentorFeedback: false);
        if (result.error != null) {
          await db.messagesDao.add(
            'mentor',
            'Could not record that: ${result.error}',
          );
        } else if (result.inserted) {
          final transaction = result.transaction;
          final label = transaction == null || transaction.merchant.isEmpty
              ? transaction?.category ?? 'your transaction'
              : transaction.merchant;
          final amount = transaction == null
              ? ''
              : ' ${transaction.currency} ${transaction.amount.toStringAsFixed(2)}';
          await db.messagesDao.add(
            'mentor',
            'Done — recorded$amount for $label.',
          );
        } else {
          await db.messagesDao.add(
            'mentor',
            'That transaction was already recorded.',
          );
        }
      } else {
        final result = await ref
            .read(mentorProvider)
            .chat(text, preclassified: intent);
        await db.messagesDao.add(
          'mentor',
          result.content,
          kind: result.kind,
          dataJson: result.dataJson,
        );
      }
    }
    if (mounted) setState(() => _thinking = false);
  }

  void _sendPrompt(String prompt) {
    _controller.text = prompt;
    _send();
  }

  Future<void> _scanReceipt() async {
    if (_thinking) return;
    if (mounted) setState(() => _thinking = true);
    try {
      final text = await ReceiptOcrService().scanReceipt();
      if (text == null) {
        await ref
            .read(appDatabaseProvider)
            .messagesDao
            .add('mentor', 'No receipt text detected.');
      } else {
        final result = await ref
            .read(addFlowProvider)
            .run(rawText: text, source: 'receipt');
        await ref
            .read(appDatabaseProvider)
            .messagesDao
            .add(
              'mentor',
              result.inserted
                  ? 'Receipt recorded successfully.'
                  : result.error ?? 'Could not record that receipt.',
            );
      }
    } catch (_) {
      await ref
          .read(appDatabaseProvider)
          .messagesDao
          .add('mentor', 'I could not read that receipt.');
    } finally {
      if (mounted) setState(() => _thinking = false);
    }
  }
}

class _VectorWelcome extends StatelessWidget {
  const _VectorWelcome({required this.onPrompt});

  final ValueChanged<String> onPrompt;

  static const _prompts = [
    'Give me a money check-in',
    'What can I safely spend today?',
    'Show my recent transactions',
    'Show my subscriptions',
    'Create a savings goal for Emergency fund of 1000',
  ];

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(AppSpacing.margin),
    children: [
      const SizedBox(height: 32),
      const Icon(Icons.auto_awesome, color: AppColors.primary, size: 34),
      const SizedBox(height: 16),
      const Text(
        'Your financial command center',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: AppColors.darkOnSurface,
          fontSize: 22,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 8),
      const Text(
        'Record, find, correct, and delete entries. Manage subscriptions, caps, plan settings, and savings goals with a confirmation before changes.',
        textAlign: TextAlign.center,
        style: TextStyle(color: AppColors.darkOnSurfaceVariant, height: 1.4),
      ),
      const SizedBox(height: 28),
      for (final prompt in _prompts)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: OutlinedButton(
            onPressed: () => onPrompt(prompt),
            style: OutlinedButton.styleFrom(
              alignment: Alignment.centerLeft,
              foregroundColor: AppColors.darkOnSurface,
              side: const BorderSide(
                color: AppColors.darkSurfaceContainerHighest,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
            child: Text(prompt),
          ),
        ),
    ],
  );
}

class _ChatHeader extends StatelessWidget {
  const _ChatHeader();

  void _close(BuildContext context) {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/');
    }
  }

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.margin,
      16,
      AppSpacing.margin,
      14,
    ),
    decoration: const BoxDecoration(
      color: AppColors.darkSurface,
      border: Border(
        bottom: BorderSide(color: AppColors.darkSurfaceContainerHighest),
      ),
    ),
    child: Row(
      children: [
        IconButton(
          onPressed: () => _close(context),
          icon: const Icon(Icons.close, color: AppColors.darkOnSurface),
        ),
        const SizedBox(width: 8),
        Container(
          width: 34,
          height: 34,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.primary,
          ),
          child: const Icon(Icons.smart_toy, color: Colors.white, size: 18),
        ),
        const SizedBox(width: 10),
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'VECTOR',
              style: TextStyle(
                color: AppColors.darkOnSurface,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
              ),
            ),
            Text(
              'Your money mentor',
              style: TextStyle(
                color: AppColors.darkOnSurfaceVariant,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class _Bubble extends ConsumerStatefulWidget {
  final String role;
  final String content;
  final String kind;
  final String? dataJson;
  final bool thinking;
  const _Bubble({
    required this.role,
    required this.content,
    this.kind = 'text',
    this.dataJson,
    this.thinking = false,
  });

  @override
  ConsumerState<_Bubble> createState() => _BubbleState();
}

class _BubbleState extends ConsumerState<_Bubble> {
  bool _actionTaken = false;

  List<TransactionSummary> get _transactions =>
      (widget.kind == 'transaction_list' || widget.kind == 'delete_confirm') &&
          widget.dataJson != null
      ? decodeTransactionSummaries(widget.dataJson!)
      : const [];

  Future<void> _delete(int id) async {
    await ref.read(appDatabaseProvider).transactionsDao.remove(id);
    if (mounted) setState(() => _actionTaken = true);
  }

  List<SubscriptionSummary> get _subscriptions =>
      (widget.kind == 'subscription_list' || widget.kind == 'cancel_confirm') &&
          widget.dataJson != null
      ? decodeSubscriptionSummaries(widget.dataJson!)
      : const [];

  Future<void> _cancelSubscription(int id) async {
    await ref.read(appDatabaseProvider).subscriptionsDao.remove(id);
    if (mounted) setState(() => _actionTaken = true);
  }

  BudgetChangeSummary? get _budgetChange =>
      widget.kind == 'budget_confirm' && widget.dataJson != null
      ? decodeBudgetChangeSummary(widget.dataJson!)
      : null;

  Future<void> _confirmBudgetChange(BudgetChangeSummary change) async {
    final db = ref.read(appDatabaseProvider);
    final existing = await db.budgetsDao.forPeriod(change.period);
    final matching = existing.where((row) => row.category == change.category);
    final current = matching.isEmpty ? null : matching.first;
    final currency =
        await db.settingsDao.planCurrency(change.period) ??
        current?.currency ??
        await db.settingsDao.defaultCurrency();
    await db.budgetsDao.upsert(
      change.category,
      change.proposedLimit,
      change.period,
      cycle: current?.cycle ?? 'monthly',
      cycleDays: current?.cycleDays ?? 30,
      currency: currency,
    );
    if (mounted) setState(() => _actionTaken = true);
  }

  NewSubscriptionSummary? get _newSubscription =>
      widget.kind == 'add_subscription_confirm' && widget.dataJson != null
      ? decodeNewSubscriptionSummary(widget.dataJson!)
      : null;

  Future<void> _confirmAddSubscription(NewSubscriptionSummary s) async {
    final db = ref.read(appDatabaseProvider);
    final existing = await db.subscriptionsDao.search(nameKeyword: s.name);
    final alreadyAdded = existing.any(
      (row) => row.name == s.name && row.amount == s.amount,
    );
    if (!alreadyAdded) {
      await db.subscriptionsDao.add(
        SubscriptionsCompanion.insert(
          name: s.name,
          amount: s.amount,
          cycle: 'monthly',
          nextChargeDate: s.nextChargeDate,
          createdAt: DateTime.now(),
        ),
      );
    }
    if (mounted) setState(() => _actionTaken = true);
  }

  TransactionEditSummary? get _transactionEdit =>
      widget.kind == 'edit_transaction_confirm' && widget.dataJson != null
      ? decodeTransactionEditSummary(widget.dataJson!)
      : null;

  Future<void> _confirmTransactionEdit(TransactionEditSummary edit) async {
    await ref
        .read(appDatabaseProvider)
        .transactionsDao
        .updateFields(
          edit.transaction.id,
          amount: edit.newAmount,
          merchant: edit.newMerchant,
          category: edit.newCategory,
        );
    if (mounted) setState(() => _actionTaken = true);
  }

  SubscriptionEditSummary? get _subscriptionEdit =>
      widget.kind == 'edit_subscription_confirm' && widget.dataJson != null
      ? decodeSubscriptionEditSummary(widget.dataJson!)
      : null;

  Future<void> _confirmSubscriptionEdit(SubscriptionEditSummary edit) async {
    await ref
        .read(appDatabaseProvider)
        .subscriptionsDao
        .update(
          edit.subscription.id,
          SubscriptionsCompanion(amount: Value(edit.newAmount)),
        );
    if (mounted) setState(() => _actionTaken = true);
  }

  PlanActionSummary? get _planAction =>
      widget.kind == 'plan_action_confirm' && widget.dataJson != null
      ? decodePlanActionSummary(widget.dataJson!)
      : null;

  Future<void> _confirmPlanAction(PlanActionSummary action) async {
    final db = ref.read(appDatabaseProvider);
    switch (action.action) {
      case 'set_income':
        await db.settingsDao.setMonthlyIncome(action.period!, action.amount!);
        break;
      case 'set_cycle':
        await db.settingsDao.setPlanCycle(action.cycle!);
        break;
      case 'convert_currency':
        final income = await db.settingsDao.monthlyIncome(action.period!);
        await db.budgetsDao.convertPeriodCurrency(
          action.period!,
          targetCurrency: action.targetCurrency!,
          rate: action.rate!,
          income: income,
        );
        break;
      case 'add_category':
        await db.categoriesDao.add(action.category!);
        break;
      case 'remove_category':
        await db.categoriesDao.remove(action.category!);
        break;
      case 'set_savings_goal':
        await db.settingsDao.setSavingsGoal(
          SavingsGoal(
            name: action.goalName!,
            targetAmount: action.amount!,
            savedAmount: action.savedAmount ?? 0,
            currency: action.targetCurrency!,
          ),
        );
        ref.invalidate(savingsGoalProvider);
        break;
      case 'clear_savings_goal':
        await db.settingsDao.clearSavingsGoal();
        ref.invalidate(savingsGoalProvider);
        break;
      default:
        throw StateError('Unknown plan action: ${action.action}');
    }
    if (mounted) setState(() => _actionTaken = true);
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.role == 'user';
    return Align(
      alignment: user ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * .78,
        ),
        decoration: BoxDecoration(
          color: user ? AppColors.primary : AppColors.darkSurfaceContainerHigh,
          borderRadius: BorderRadius.circular(16),
        ),
        child: widget.thinking
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.darkOnSurfaceVariant,
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.content.isNotEmpty)
                    Text(
                      widget.content,
                      style: TextStyle(
                        color: user ? Colors.white : AppColors.darkOnSurface,
                        height: 1.35,
                      ),
                    ),
                  if (_transactions.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    for (final t in _transactions)
                      Container(
                        margin: const EdgeInsets.only(bottom: 4),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(AppRadii.xl),
                        ),
                        child: TransactionRow(t: t),
                      ),
                    if (widget.kind == 'delete_confirm' && !_actionTaken)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextButton(
                              onPressed: () =>
                                  setState(() => _actionTaken = true),
                              style: TextButton.styleFrom(
                                foregroundColor: AppColors.darkPrimary,
                              ),
                              child: const Text('Cancel'),
                            ),
                            const SizedBox(width: 4),
                            FilledButton(
                              onPressed: () => _delete(_transactions.first.id),
                              child: const Text('Delete'),
                            ),
                          ],
                        ),
                      ),
                    if (widget.kind == 'delete_confirm' && _actionTaken)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Done.',
                          style: TextStyle(
                            color: AppColors.darkOnSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ),
                  ],
                  if (_subscriptions.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    for (final s in _subscriptions)
                      Container(
                        margin: const EdgeInsets.only(bottom: 4),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(AppRadii.xl),
                        ),
                        child: SubscriptionRow(s: s),
                      ),
                    if (widget.kind == 'cancel_confirm' && !_actionTaken)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextButton(
                              onPressed: () =>
                                  setState(() => _actionTaken = true),
                              style: TextButton.styleFrom(
                                foregroundColor: AppColors.darkPrimary,
                              ),
                              child: const Text('Keep It'),
                            ),
                            const SizedBox(width: 4),
                            FilledButton(
                              onPressed: () =>
                                  _cancelSubscription(_subscriptions.first.id),
                              child: const Text('Cancel Subscription'),
                            ),
                          ],
                        ),
                      ),
                    if (widget.kind == 'cancel_confirm' && _actionTaken)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Done.',
                          style: TextStyle(
                            color: AppColors.darkOnSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ),
                  ],
                  if (_budgetChange != null) ...[
                    const SizedBox(height: 8),
                    if (!_actionTaken)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextButton(
                              onPressed: () =>
                                  setState(() => _actionTaken = true),
                              style: TextButton.styleFrom(
                                foregroundColor: AppColors.darkPrimary,
                              ),
                              child: const Text('Cancel'),
                            ),
                            const SizedBox(width: 4),
                            FilledButton(
                              onPressed: () =>
                                  _confirmBudgetChange(_budgetChange!),
                              child: const Text('Confirm'),
                            ),
                          ],
                        ),
                      ),
                    if (_actionTaken)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Done.',
                          style: TextStyle(
                            color: AppColors.darkOnSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ),
                  ],
                  if (_newSubscription != null) ...[
                    const SizedBox(height: 8),
                    if (!_actionTaken)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextButton(
                              onPressed: () =>
                                  setState(() => _actionTaken = true),
                              style: TextButton.styleFrom(
                                foregroundColor: AppColors.darkPrimary,
                              ),
                              child: const Text('Cancel'),
                            ),
                            const SizedBox(width: 4),
                            FilledButton(
                              onPressed: () =>
                                  _confirmAddSubscription(_newSubscription!),
                              child: const Text('Confirm'),
                            ),
                          ],
                        ),
                      ),
                    if (_actionTaken)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Done.',
                          style: TextStyle(
                            color: AppColors.darkOnSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ),
                  ],
                  if (_transactionEdit != null) ...[
                    const SizedBox(height: 8),
                    if (!_actionTaken)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextButton(
                              onPressed: () =>
                                  setState(() => _actionTaken = true),
                              style: TextButton.styleFrom(
                                foregroundColor: AppColors.darkPrimary,
                              ),
                              child: const Text('Cancel'),
                            ),
                            const SizedBox(width: 4),
                            FilledButton(
                              onPressed: () =>
                                  _confirmTransactionEdit(_transactionEdit!),
                              child: const Text('Confirm'),
                            ),
                          ],
                        ),
                      ),
                    if (_actionTaken)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Done.',
                          style: TextStyle(
                            color: AppColors.darkOnSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ),
                  ],
                  if (_subscriptionEdit != null) ...[
                    const SizedBox(height: 8),
                    if (!_actionTaken)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextButton(
                              onPressed: () =>
                                  setState(() => _actionTaken = true),
                              style: TextButton.styleFrom(
                                foregroundColor: AppColors.darkPrimary,
                              ),
                              child: const Text('Cancel'),
                            ),
                            const SizedBox(width: 4),
                            FilledButton(
                              onPressed: () =>
                                  _confirmSubscriptionEdit(_subscriptionEdit!),
                              child: const Text('Confirm'),
                            ),
                          ],
                        ),
                      ),
                    if (_actionTaken)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Done.',
                          style: TextStyle(
                            color: AppColors.darkOnSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ),
                  ],
                  if (_planAction != null) ...[
                    const SizedBox(height: 8),
                    if (!_actionTaken)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextButton(
                              onPressed: () =>
                                  setState(() => _actionTaken = true),
                              style: TextButton.styleFrom(
                                foregroundColor: AppColors.darkPrimary,
                              ),
                              child: const Text('Cancel'),
                            ),
                            const SizedBox(width: 4),
                            FilledButton(
                              onPressed: () => _confirmPlanAction(_planAction!),
                              child: const Text('Confirm'),
                            ),
                          ],
                        ),
                      ),
                    if (_actionTaken)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Done.',
                          style: TextStyle(
                            color: AppColors.darkOnSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ),
                  ],
                ],
              ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onSend;
  final VoidCallback onReceipt;
  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.onSend,
    required this.onReceipt,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
    child: Row(
      children: [
        IconButton(
          onPressed: onReceipt,
          icon: const Icon(
            Icons.camera_alt_outlined,
            color: AppColors.darkOnSurfaceVariant,
          ),
        ),
        Expanded(
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            style: const TextStyle(color: AppColors.darkOnSurface),
            decoration: InputDecoration(
              hintText: 'Ask Vector anything…',
              hintStyle: const TextStyle(color: AppColors.darkOnSurfaceVariant),
              filled: true,
              fillColor: AppColors.darkSurfaceContainerHigh,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
            ),
            onSubmitted: (_) => onSend(),
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          onPressed: onSend,
          icon: const Icon(
            Icons.arrow_upward_rounded,
            color: AppColors.primaryBright,
            size: 28,
          ),
        ),
      ],
    ),
  );
}
