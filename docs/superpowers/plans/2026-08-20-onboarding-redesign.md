# Onboarding redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace onboarding's two dead survey questions with a "Meet Vector" step describing the mentor's real capabilities, and expand the setup checklist to include Subscriptions and a working link to chat.

**Architecture:** `SettingsDao.completeOnboarding()` drops its two unused parameters and writes only the completion flag. `onboarding_screen.dart`'s 4-step flow becomes 3 steps (Welcome → Meet Vector → Setup checklist); the setup checklist grows from 3 to 4 items with two new navigation callbacks threaded from `router.dart`'s `AppShell`.

**Tech Stack:** Flutter, Riverpod, Drift/SQLite, go_router — no new dependencies.

## Global Constraints

- All UI copy is in English — no Spanish anywhere in user-facing text.
- No schema migration: `Settings` is a generic key-value table; dropping two keys nobody reads is a pure code deletion.
- `SettingsDao.completeOnboarding()`'s DB write only happens on the final "Start using Moneylock" tap (`_step == 2` after this change) — the widget test for step navigation must never trigger it, so it needs no `appDatabaseProvider` override.

---

### Task 1: `SettingsDao.completeOnboarding()` → no-arg, drop dead survey keys

**Files:**
- Modify: `app/lib/data/db.dart:87-114`
- Modify: `app/lib/features/onboarding/onboarding_screen.dart:74-80` (call site only — leave `_usedPlanner`/`_shoppingHabits` state and steps 1/2 untouched here; Task 2 removes them)
- Test: `app/test/settings_dao_onboarding_test.dart`

**Interfaces:**
- Produces: `SettingsDao.completeOnboarding()` — no arguments, `Future<void>`, writes only `onboarding_completed = 'true'`. Task 2's UI rewrite calls this exact signature.

- [ ] **Step 1: Write the failing test**

Create `app/test/settings_dao_onboarding_test.dart`:

```dart
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneylock/data/db.dart';

AppDatabase _db() => AppDatabase.forTesting(
  driftDatabase(name: 'test_${DateTime.now().microsecondsSinceEpoch}'),
);

void main() {
  test('completeOnboarding writes only onboarding_completed', () async {
    final db = _db();

    await db.settingsDao.completeOnboarding();

    expect(await db.settingsDao.onboardingCompleted(), true);
    final rows = await db.select(db.settings).get();
    expect(rows.map((r) => r.key), ['onboarding_completed']);
    await db.close();
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/settings_dao_onboarding_test.dart`
Expected: FAIL — `completeOnboarding` still requires `usedPlanner`/`shoppingHabits` named arguments, so this is a compile error at the call site in the test.

- [ ] **Step 3: Change `completeOnboarding()` to a no-arg method**

In `app/lib/data/db.dart`, replace the `completeOnboarding` method (currently lines 87-114):

```dart
  Future<void> completeOnboarding() => db
      .into(db.settings)
      .insertOnConflictUpdate(
        SettingsCompanion.insert(key: 'onboarding_completed', value: 'true'),
      );
```

This replaces the whole method body — the `batch()` call and the two
`onboarding_used_planner`/`onboarding_shopping_habits` inserts are deleted
entirely, not just made optional.

- [ ] **Step 4: Fix the call site in `onboarding_screen.dart`**

In `app/lib/features/onboarding/onboarding_screen.dart`, the `_next()` method
currently (lines 68-82) calls:

```dart
    await ref
        .read(appDatabaseProvider)
        .settingsDao
        .completeOnboarding(
          usedPlanner: _usedPlanner ?? 'not_answered',
          shoppingHabits: _shoppingHabits ?? 'not_answered',
        );
```

Change only this call to:

```dart
    await ref.read(appDatabaseProvider).settingsDao.completeOnboarding();
```

Leave every other line in this file untouched — `_usedPlanner`,
`_shoppingHabits`, and the two `_ChoiceStep` usages still exist after this
task (Task 2 removes them). This task's only job is making the DAO
signature change compile.

- [ ] **Step 5: Run test to verify it passes**

Run: `cd app && flutter test test/settings_dao_onboarding_test.dart`
Expected: PASS

- [ ] **Step 6: Run the full analyzer to confirm no other call sites broke**

Run: `cd app && flutter analyze lib/data/db.dart lib/features/onboarding/onboarding_screen.dart`
Expected: no errors (there is exactly one call site for `completeOnboarding`, fixed in Step 4).

- [ ] **Step 7: Commit**

```bash
git add app/lib/data/db.dart app/lib/features/onboarding/onboarding_screen.dart app/test/settings_dao_onboarding_test.dart
git commit -m "refactor: drop unused onboarding survey keys from completeOnboarding"
```

---

### Task 2: "Meet Vector" step, expanded setup checklist, navigation wiring

**Files:**
- Modify: `app/lib/features/onboarding/onboarding_screen.dart` (full rewrite of `_OnboardingScreenState`, `_content()`, removal of `_ChoiceStep` usages and the class itself, new `_MeetVectorStep`, expanded `_SetupStep`, `OnboardingGate`/`OnboardingScreen` constructors)
- Modify: `app/lib/core/router.dart:94` (`OnboardingGate` instantiation in `AppShell`)
- Test: `app/test/onboarding_screen_test.dart`

**Interfaces:**
- Consumes: `SettingsDao.completeOnboarding()` (no-arg, from Task 1), `AppDatabase` via `appDatabaseProvider` (existing), `AppColors`/`AppTextStyles`/`AppSpacing`/`AppRadii` (existing, from `theme/app_theme.dart`).
- Produces: `OnboardingGate({required onOpenBudget, required onOpenSubscriptions, required onOpenChat})`, `OnboardingScreen({required onComplete, required onOpenBudget, required onOpenSubscriptions, required onOpenChat})` — `router.dart`'s `AppShell` is the only other caller and is updated in this same task.

- [ ] **Step 1: Write the failing widget test**

Create `app/test/onboarding_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneylock/features/onboarding/onboarding_screen.dart';

Future<void> _pump(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: OnboardingScreen(
          onComplete: () {},
          onOpenBudget: () {},
          onOpenSubscriptions: () {},
          onOpenChat: () {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('steps through Welcome -> Meet Vector -> Setup checklist -> Back', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.text('Build a clearer relationship with your money.'), findsOneWidget);
    expect(find.text('Back'), findsNothing);

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Meet Vector'), findsOneWidget);

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Your setup checklist'), findsOneWidget);
    expect(find.text('Add your first subscription'), findsOneWidget);
    expect(find.text('Start using Moneylock'), findsOneWidget);

    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Meet Vector'), findsOneWidget);
  });

  testWidgets('tapping a checklist item invokes its callback without touching the DB', (
    tester,
  ) async {
    var subscriptionsOpened = false;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: OnboardingScreen(
            onComplete: () {},
            onOpenBudget: () {},
            onOpenSubscriptions: () => subscriptionsOpened = true,
            onOpenChat: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add your first subscription'));
    await tester.pumpAndSettle();

    expect(subscriptionsOpened, true);
  });
}
```

Neither test ever taps "Start using Moneylock", so `_next()` never reaches
its `completeOnboarding()` DB write and this file needs no
`appDatabaseProvider` override — this sidesteps the `driftDatabase()`
native-isolate-round-trip hang documented in this codebase's other widget
tests (see `budget_screen_test.dart`'s comment on `categoriesProvider`).

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/onboarding_screen_test.dart`
Expected: FAIL — `OnboardingScreen` doesn't yet accept `onOpenSubscriptions`/`onOpenChat`, and there is no "Meet Vector" step or "Add your first subscription" item.

- [ ] **Step 3: Rewrite `onboarding_screen.dart`**

Replace the full contents of `app/lib/features/onboarding/onboarding_screen.dart` with:

```dart
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
        'We will personalize Moneylock in a few quick steps, then show you how to set up your first budget and capture expenses offline.',
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
```

This deletes `_usedPlanner`, `_shoppingHabits`, `_canContinue`, and the
`_ChoiceStep` class entirely — nothing else in the codebase references
`_ChoiceStep` (it was private to this file).

- [ ] **Step 4: Update `router.dart`'s `AppShell`**

In `app/lib/core/router.dart`, replace line 94:

```dart
        OnboardingGate(onOpenBudget: () => navigationShell.goBranch(1)),
```

with:

```dart
        OnboardingGate(
          onOpenBudget: () => navigationShell.goBranch(1),
          onOpenSubscriptions: () => context.push('/subscriptions'),
          onOpenChat: () => context.push('/chat'),
        ),
```

`context.push` is already imported and used two lines above (line 92, the
mentor FAB) and `/subscriptions` is already a registered route (line 60-65
of this same file) — no new imports needed.

- [ ] **Step 5: Run test to verify it passes**

Run: `cd app && flutter test test/onboarding_screen_test.dart`
Expected: PASS

- [ ] **Step 6: Run the full analyzer**

Run: `cd app && flutter analyze`
Expected: clean (only the same pre-existing info-level lints noted in the PR's test plan, none new).

- [ ] **Step 7: Commit**

```bash
git add app/lib/features/onboarding/onboarding_screen.dart app/lib/core/router.dart app/test/onboarding_screen_test.dart
git commit -m "feat: redesign onboarding with Meet Vector step and expanded checklist"
```
