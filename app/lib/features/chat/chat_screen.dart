import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/transaction_summary.dart';
import '../../llm/category_correction.dart';
import '../../llm/mentor_guardrails.dart';
import '../../providers.dart';
import '../../theme/app_theme.dart';
import '../../receipt/receipt_ocr_service.dart';
import '../../widgets/transaction_row.dart';

final _amountRe = RegExp(r'\$\s?\d+(?:\.\d{1,2})?|\d+\.\d{2}');
bool hasMonetaryAmount(String text) => _amountRe.hasMatch(text);

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});
  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  bool _thinking = false;
  int _lastCount = -1;
  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(messagesStreamProvider).value ?? const [];
    if (messages.length != _lastCount) {
      _lastCount = messages.length;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients)
          _scroll.animateTo(
            _scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
          );
      });
    }
    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      body: SafeArea(
        child: Column(
          children: [
            const _ChatHeader(),
            Expanded(
              child: ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.all(AppSpacing.md),
                itemCount: messages.length + (_thinking ? 1 : 0),
                itemBuilder: (_, i) {
                  if (i == messages.length)
                    return const _Bubble(
                      role: 'mentor',
                      content: '',
                      thinking: true,
                    );
                  final m = messages[i];
                  return _Bubble(
                    role: m.role,
                    content: m.content,
                    kind: m.kind,
                    transactions: m.dataJson == null
                        ? const []
                        : decodeTransactionSummaries(m.dataJson!),
                  );
                },
              ),
            ),
            _Composer(
              controller: _controller,
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
    } else if (hasMonetaryAmount(text)) {
      final intent = await ref.read(mentorProvider).classify(text);
      if (intent.intent == 'chat') {
        final result = await ref
            .read(addFlowProvider)
            .run(rawText: text, source: 'manual');
        if (result.error != null)
          await db.messagesDao.add(
            'mentor',
            'Could not record that: ${result.error}',
          );
      } else {
        final result = await ref.read(mentorProvider).chat(text, preclassified: intent);
        await db.messagesDao.add(
          'mentor',
          result.content,
          kind: result.kind,
          transactions: result.transactions,
        );
      }
    } else {
      final result = await ref.read(mentorProvider).chat(text);
      await db.messagesDao.add(
        'mentor',
        result.content,
        kind: result.kind,
        transactions: result.transactions,
      );
    }
    if (mounted) setState(() => _thinking = false);
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

class _ChatHeader extends StatelessWidget {
  const _ChatHeader();
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
          onPressed: () => Navigator.of(context).maybePop(),
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
  final List<TransactionSummary> transactions;
  final bool thinking;
  const _Bubble({
    required this.role,
    required this.content,
    this.kind = 'text',
    this.transactions = const [],
    this.thinking = false,
  });

  @override
  ConsumerState<_Bubble> createState() => _BubbleState();
}

class _BubbleState extends ConsumerState<_Bubble> {
  bool _actionTaken = false;

  Future<void> _delete(int id) async {
    await ref.read(appDatabaseProvider).transactionsDao.remove(id);
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
                  if (widget.transactions.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    for (final t in widget.transactions)
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
                              onPressed: () => setState(() => _actionTaken = true),
                              style: TextButton.styleFrom(foregroundColor: AppColors.darkPrimary),
                              child: const Text('Cancel'),
                            ),
                            const SizedBox(width: 4),
                            FilledButton(
                              onPressed: () => _delete(widget.transactions.first.id),
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
                ],
              ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback onReceipt;
  const _Composer({
    required this.controller,
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
