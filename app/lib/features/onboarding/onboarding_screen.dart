import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers.dart';
import '../../theme/app_theme.dart';

final onboardingCompletedProvider = FutureProvider<bool>(
  (ref) => ref.watch(appDatabaseProvider).settingsDao.onboardingCompleted(),
);

class OnboardingGate extends ConsumerStatefulWidget {
  final VoidCallback onOpenBudget;
  final VoidCallback onOpenSubscriptions;
  final VoidCallback onOpenChat;
  const OnboardingGate({
    super.key,
    required this.onOpenBudget,
    required this.onOpenSubscriptions,
    required this.onOpenChat,
  });

  @override
  ConsumerState<OnboardingGate> createState() => _OnboardingGateState();
}

class _OnboardingGateState extends ConsumerState<OnboardingGate> {
  bool? _completed;

  @override
  Widget build(BuildContext context) {
    final completed = ref.watch(onboardingCompletedProvider).valueOrNull;
    if (completed == null || completed || _completed == true) {
      return const SizedBox.shrink();
    }
    return Positioned.fill(
      child: Material(
        color: AppColors.background,
        child: OnboardingScreen(
          onComplete: () => setState(() => _completed = true),
          onOpenBudget: () {
            setState(() => _completed = true);
            widget.onOpenBudget();
          },
          onOpenSubscriptions: () {
            setState(() => _completed = true);
            widget.onOpenSubscriptions();
          },
          onOpenChat: () {
            setState(() => _completed = true);
            widget.onOpenChat();
          },
        ),
      ),
    );
  }
}

class OnboardingScreen extends ConsumerStatefulWidget {
  final VoidCallback onComplete;
  final VoidCallback onOpenBudget;
  final VoidCallback onOpenSubscriptions;
  final VoidCallback onOpenChat;
  const OnboardingScreen({
    super.key,
    required this.onComplete,
    required this.onOpenBudget,
    required this.onOpenSubscriptions,
    required this.onOpenChat,
  });

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  int _step = 0;
  final _setup = <bool>[false, false, false, false];

  Future<void> _next() async {
    if (_step < 2) {
      setState(() => _step++);
      return;
    }
    await ref.read(appDatabaseProvider).settingsDao.completeOnboarding();
    if (mounted) widget.onComplete();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.margin,
        36,
        AppSpacing.margin,
        20,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(AppRadii.xl),
                ),
                child: const Icon(Icons.lock_outline, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Text(
                'MONEYLOCK',
                style: AppTextStyles.labelCaps.copyWith(
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 36),
          LinearProgressIndicator(value: (_step + 1) / 3),
          const SizedBox(height: 32),
          Expanded(child: _content()),
          Row(
            children: [
              if (_step > 0)
                TextButton(
                  onPressed: () => setState(() => _step--),
                  child: const Text('Back'),
                ),
              const Spacer(),
              FilledButton.icon(
                onPressed: _next,
                icon: Icon(_step == 2 ? Icons.check : Icons.arrow_forward),
                label: Text(_step == 2 ? 'Start using Moneylock' : 'Continue'),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _content() => switch (_step) {
    0 => const _WelcomeStep(),
    1 => const _MeetVectorStep(),
    _ => _SetupStep(
      values: _setup,
      onOpenBudget: widget.onOpenBudget,
      onOpenSubscriptions: widget.onOpenSubscriptions,
      onOpenChat: widget.onOpenChat,
      onChanged: (i, value) => setState(() => _setup[i] = value),
    ),
  };
}

class _WelcomeStep extends StatelessWidget {
  const _WelcomeStep();
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Build a clearer relationship with your money.',
        style: AppTextStyles.display,
      ),
      const SizedBox(height: 16),
      Text(
        'A few quick steps to show you what Moneylock can do, then you will set up your first budget and start capturing expenses offline.',
        style: AppTextStyles.bodyLg.copyWith(color: AppColors.onSurfaceVariant),
      ),
    ],
  );
}

class _MeetVectorStep extends StatelessWidget {
  const _MeetVectorStep();

  static const _capabilities = [
    'Find and answer questions about your transactions and subscriptions.',
    'Add, edit, or delete a transaction or subscription — always with a real Confirm button, never from a typed "yes".',
    'Change a budget limit on request.',
    'Give advice grounded in your actual spending data.',
  ];

  static const _examples = [
    '"add Netflix for \$15, recurring the 20th"',
    '"what am I spending the most on?"',
    '"raise my groceries budget to \$400"',
  ];

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.smart_toy_outlined, color: AppColors.primary, size: 28),
            const SizedBox(width: 10),
            Text('Meet Vector', style: AppTextStyles.headlineLgMobile),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          'Your on-device finance mentor. Here is what it can actually do:',
          style: AppTextStyles.bodyLg.copyWith(color: AppColors.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        for (final line in _capabilities)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.check_circle_outline,
                  size: 18,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(line, style: AppTextStyles.bodyMd)),
              ],
            ),
          ),
        const SizedBox(height: 8),
        Text(
          'Try asking things like:',
          style: AppTextStyles.bodyMd.copyWith(color: AppColors.onSurfaceVariant),
        ),
        const SizedBox(height: 10),
        for (final example in _examples)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadii.xl),
              ),
              child: Text(example, style: AppTextStyles.bodyMd),
            ),
          ),
      ],
    ),
  );
}

class _SetupStep extends StatelessWidget {
  final List<bool> values;
  final VoidCallback onOpenBudget;
  final VoidCallback onOpenSubscriptions;
  final VoidCallback onOpenChat;
  final void Function(int, bool) onChanged;
  const _SetupStep({
    required this.values,
    required this.onOpenBudget,
    required this.onOpenSubscriptions,
    required this.onOpenChat,
    required this.onChanged,
  });
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Your setup checklist', style: AppTextStyles.headlineLgMobile),
        const SizedBox(height: 10),
        Text(
          'You can do these now or revisit them anytime.',
          style: AppTextStyles.bodyMd.copyWith(
            color: AppColors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 18),
        _check(
          0,
          Icons.account_balance_wallet_outlined,
          'Set your currency and budget',
          onOpenBudget,
        ),
        _check(
          1,
          Icons.repeat,
          'Add your first subscription',
          onOpenSubscriptions,
        ),
        _check(2, Icons.add_circle_outline, 'Add your first expense', null),
        _check(
          3,
          Icons.smart_toy_outlined,
          'Ask your Moneylock mentor',
          onOpenChat,
        ),
      ],
    ),
  );

  Widget _check(int index, IconData icon, String title, VoidCallback? action) =>
      Card(
        child: ListTile(
          leading: Icon(icon, color: AppColors.primary),
          title: Text(title),
          trailing: Checkbox(
            value: values[index],
            onChanged: (v) => onChanged(index, v ?? false),
          ),
          onTap: action,
        ),
      );
}
