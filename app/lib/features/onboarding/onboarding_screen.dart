import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers.dart';
import '../../theme/app_theme.dart';

final onboardingCompletedProvider = FutureProvider<bool>(
  (ref) => ref.watch(appDatabaseProvider).settingsDao.onboardingCompleted(),
);

class OnboardingGate extends ConsumerStatefulWidget {
  final VoidCallback onOpenBudget;
  const OnboardingGate({super.key, required this.onOpenBudget});

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
        ),
      ),
    );
  }
}

class OnboardingScreen extends ConsumerStatefulWidget {
  final VoidCallback onComplete;
  final VoidCallback onOpenBudget;
  const OnboardingScreen({
    super.key,
    required this.onComplete,
    required this.onOpenBudget,
  });

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  int _step = 0;
  String? _usedPlanner;
  String? _shoppingHabits;
  final _setup = <bool>[false, false, false];

  bool get _canContinue => switch (_step) {
    1 => _usedPlanner != null,
    2 => _shoppingHabits != null,
    _ => true,
  };

  Future<void> _next() async {
    if (!_canContinue) return;
    if (_step < 3) {
      setState(() => _step++);
      return;
    }
    await ref
        .read(appDatabaseProvider)
        .settingsDao
        .completeOnboarding(
          usedPlanner: _usedPlanner ?? 'not_answered',
          shoppingHabits: _shoppingHabits ?? 'not_answered',
        );
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
          LinearProgressIndicator(value: (_step + 1) / 4),
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
                onPressed: _canContinue ? _next : null,
                icon: Icon(_step == 3 ? Icons.check : Icons.arrow_forward),
                label: Text(_step == 3 ? 'Start using Moneylock' : 'Continue'),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _content() => switch (_step) {
    0 => const _WelcomeStep(),
    1 => _ChoiceStep(
      title: 'Have you used a planner before?',
      options: const ['Yes, regularly', 'A little', 'Not yet'],
      value: _usedPlanner,
      onChanged: (v) => setState(() => _usedPlanner = v),
    ),
    2 => _ChoiceStep(
      title: 'What best describes your shopping habits?',
      options: const [
        'I plan most purchases',
        'I mix planned and spontaneous',
        'I often buy spontaneously',
      ],
      value: _shoppingHabits,
      onChanged: (v) => setState(() => _shoppingHabits = v),
    ),
    _ => _SetupStep(
      values: _setup,
      onOpenBudget: widget.onOpenBudget,
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
        'We will personalize Moneylock in a few quick steps, then show you how to set up your first budget and capture expenses offline.',
        style: AppTextStyles.bodyLg.copyWith(color: AppColors.onSurfaceVariant),
      ),
    ],
  );
}

class _ChoiceStep extends StatelessWidget {
  final String title;
  final List<String> options;
  final String? value;
  final ValueChanged<String> onChanged;
  const _ChoiceStep({
    required this.title,
    required this.options,
    required this.value,
    required this.onChanged,
  });
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: AppTextStyles.headlineLgMobile),
      const SizedBox(height: 20),
      for (final option in options)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: RadioListTile<String>(
            value: option,
            groupValue: value,
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
            title: Text(option),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.xl),
            ),
            tileColor: AppColors.surface,
          ),
        ),
    ],
  );
}

class _SetupStep extends StatelessWidget {
  final List<bool> values;
  final VoidCallback onOpenBudget;
  final void Function(int, bool) onChanged;
  const _SetupStep({
    required this.values,
    required this.onOpenBudget,
    required this.onChanged,
  });
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Your setup checklist', style: AppTextStyles.headlineLgMobile),
      const SizedBox(height: 10),
      Text(
        'You can do these now or revisit them anytime.',
        style: AppTextStyles.bodyMd.copyWith(color: AppColors.onSurfaceVariant),
      ),
      const SizedBox(height: 18),
      _check(
        0,
        Icons.account_balance_wallet_outlined,
        'Set your currency and budget',
        onOpenBudget,
      ),
      _check(1, Icons.add_circle_outline, 'Add your first expense', null),
      _check(2, Icons.smart_toy_outlined, 'Ask your Moneylock mentor', null),
    ],
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
