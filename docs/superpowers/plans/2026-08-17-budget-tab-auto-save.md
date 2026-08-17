# Budget Tab Auto-Save + Swipe-to-Delete Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Budget tab's manual save/remove icon buttons with auto-save-on-edit and swipe-to-delete, and fix a hidden bug where saving a category's cap a second time in the same period throws instead of updating it.

**Architecture:** `_BudgetRow` becomes a `StatefulWidget` that owns a debounce `Timer` and a `FocusNode` to trigger saves without a button; it wraps its card in a `Dismissible` for swipe-to-delete, reusing the existing confirm dialog. `_BudgetScreenState` gains a global tap-to-unfocus wrapper and adjusts its `_save`/`_removeCategory` methods to match the new interaction model. `BudgetsDao.upsert` gets an explicit `DoUpdate` conflict target so repeated saves for the same category+period update instead of throwing.

**Tech Stack:** Flutter, Riverpod, Drift (SQLite), `flutter_test` widget tests.

## Global Constraints

- All UI copy is in English. No Spanish (or any other language) strings in any user-facing text.
- This plan covers `app/lib/data/budgets_dao.dart` and `app/lib/features/budget/budget_screen.dart` only — no other files, no DB schema changes.

---

### Task 1: Fix `BudgetsDao.upsert` unique-conflict bug

**Files:**
- Modify: `app/lib/data/budgets_dao.dart:9-27`
- Test: Create `app/test/budgets_dao_test.dart`

**Interfaces:**
- Consumes: `db.budgets` table (columns: `category` text, `period` text, `monthlyLimit` real, `cycle` text, `cycleDays` int, `currency` text; composite unique key `{category, period}` per `app/lib/data/tables.dart:25-27`).
- Produces: `BudgetsDao.upsert(String category, double limit, String period, {String cycle, int cycleDays, String currency}) → Future<void>` — same signature as before, now safe to call repeatedly for the same category+period.

**Context:** `insertOnConflictUpdate` in this drift version only guards against *primary key* conflicts by default, not other unique constraints (drift's own doc comment on the method: "By default, only the primary key is used to detect uniqueness violations. If you have further uniqueness constraints, please use the general `insert` method with a `DoUpdate` including those columns in its `DoUpdate.target`."). `Budgets` has no natural primary-key conflict (its `id` autoincrements), so the second upsert for the same `{category, period}` throws `SqliteException: UNIQUE constraint failed: budgets.category, budgets.period` instead of updating. This is the exact bug already fixed for `CategoriesDao` in a prior change — the same fix applies here.

- [ ] **Step 1: Write the failing test**

Create `app/test/budgets_dao_test.dart`:

```dart
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneylock/data/db.dart';

void main() {
  test('upsert overwrites the limit for the same category and period instead of throwing', () async {
    final db = AppDatabase.forTesting(
        driftDatabase(name: 'test_${DateTime.now().microsecondsSinceEpoch}'));
    await db.budgetsDao.upsert('Coffee & Dining', 50.0, '2026-08');
    await db.budgetsDao.upsert('Coffee & Dining', 75.0, '2026-08');
    final rows = await db.budgetsDao.all();
    expect(rows.length, 1);
    expect(rows.first.monthlyLimit, 75.0);
    await db.close();
  });

  test('upsert keeps separate rows for different periods of the same category', () async {
    final db = AppDatabase.forTesting(
        driftDatabase(name: 'test_${DateTime.now().microsecondsSinceEpoch}'));
    await db.budgetsDao.upsert('Coffee & Dining', 50.0, '2026-08');
    await db.budgetsDao.upsert('Coffee & Dining', 60.0, '2026-09');
    final rows = await db.budgetsDao.all();
    expect(rows.length, 2);
    await db.close();
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/budgets_dao_test.dart`
Expected: the first test FAILs with a `SqliteException` containing `UNIQUE constraint failed: budgets.category, budgets.period`. The second test passes (different periods never conflicted).

- [ ] **Step 3: Fix `BudgetsDao.upsert`**

In `app/lib/data/budgets_dao.dart`, replace the `upsert` method (lines 9-27):

```dart
  Future<void> upsert(
    String category,
    double limit,
    String period, {
    String cycle = 'monthly',
    int cycleDays = 30,
    String currency = 'USD',
  }) {
    final companion = BudgetsCompanion.insert(
      category: category,
      monthlyLimit: limit,
      period: period,
      cycle: Value(cycle),
      cycleDays: Value(cycleDays),
      currency: Value(currency),
    );
    return db.into(db.budgets).insert(
          companion,
          onConflict: DoUpdate(
            (_) => companion,
            target: [db.budgets.category, db.budgets.period],
          ),
        );
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd app && flutter test test/budgets_dao_test.dart`
Expected: PASS (both tests).

- [ ] **Step 5: Commit**

```bash
cd app && git add lib/data/budgets_dao.dart test/budgets_dao_test.dart
git commit -m "fix: budgets upsert now targets the category+period unique key

insertOnConflictUpdate only guards primary-key conflicts by default;
Budgets has no PK conflict path, so re-saving a cap for the same
category in the same period threw a UNIQUE constraint error instead
of updating it. Same class of bug already fixed for categories."
```

---

### Task 2: Global keyboard dismiss

**Files:**
- Modify: `app/lib/features/budget/budget_screen.dart:42-46` (Scaffold body wrapper)
- Modify: `app/lib/features/budget/budget_screen.dart:326-334` (`_PeriodCard`'s custom-days field)
- Test: Create `app/test/budget_screen_test.dart`

**Interfaces:**
- Consumes: nothing new.
- Produces: nothing new consumed by later tasks — this is purely a UX wrapper, independent of Task 3.

**Context:** Tapping outside a focused `TextField` on this screen currently does nothing — the only way to dismiss the keyboard today is tapping the currency dropdown, which was reported as a bug blocking the row below the keyboard from being reachable.

- [ ] **Step 1: Write the failing test**

Create `app/test/budget_screen_test.dart`:

```dart
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneylock/data/db.dart';
import 'package:moneylock/features/budget/budget_screen.dart';
import 'package:moneylock/providers.dart';

AppDatabase _db() => AppDatabase.forTesting(
    driftDatabase(name: 'test_${DateTime.now().microsecondsSinceEpoch}'));

Future<AppDatabase> _pumpBudgetScreen(WidgetTester tester) async {
  final db = _db();
  await db.categoriesDao.ensureDefaults();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
      child: const MaterialApp(home: BudgetScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return db;
}

void main() {
  testWidgets('tapping outside a focused field dismisses the keyboard',
      (tester) async {
    final db = await _pumpBudgetScreen(tester);

    await tester.tap(find.widgetWithText(TextField, 'No cap').first);
    await tester.pump();
    expect(tester.testTextInput.isVisible, isTrue);

    await tester.tap(find.text('CATEGORY CAPS'));
    await tester.pump();
    expect(tester.testTextInput.isVisible, isFalse);

    await db.close();
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/budget_screen_test.dart`
Expected: FAIL — `tester.testTextInput.isVisible` is still `true` after the second tap.

- [ ] **Step 3: Wrap the Scaffold body in a tap-to-unfocus `GestureDetector`**

In `app/lib/features/budget/budget_screen.dart`, replace lines 42-46:

```dart
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
```

with:

```dart
    return Scaffold(
      backgroundColor: AppColors.background,
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusScope.of(context).unfocus(),
        child: SafeArea(
          bottom: false,
          child: CustomScrollView(
```

This opens one extra level of nesting; close it by adding a matching `),` right before the final `);` that currently closes the `Scaffold(` call (originally line 117, now shifted down by 3 lines to account for the new `GestureDetector(` and `child: SafeArea(` wrapper lines). After this edit the tail of `build()` should read:

```dart
          ],
        ),
      ),
        ),
      ),
    );
  }
```

Run `dart format app/lib/features/budget/budget_screen.dart` after this step to fix indentation — don't hand-indent the nested nesting yourself.

- [ ] **Step 4: Add `textInputAction: TextInputAction.done` to the custom cycle-days field**

In `app/lib/features/budget/budget_screen.dart`, in `_PeriodCard.build()`, find the custom-days `TextFormField` (originally lines 328-333):

```dart
              child: TextFormField(
                initialValue: '$cycleDays',
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Days per cycle'),
                onChanged: onDaysChanged,
              ),
```

Add `textInputAction: TextInputAction.done,`:

```dart
              child: TextFormField(
                initialValue: '$cycleDays',
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(labelText: 'Days per cycle'),
                onChanged: onDaysChanged,
              ),
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd app && flutter test test/budget_screen_test.dart`
Expected: PASS.

- [ ] **Step 6: Run the full test suite and analyzer to check for regressions**

Run: `cd app && flutter analyze && flutter test`
Expected: no new analyzer issues, all tests pass.

- [ ] **Step 7: Commit**

```bash
cd app && git add lib/features/budget/budget_screen.dart test/budget_screen_test.dart
git commit -m "fix: dismiss keyboard when tapping outside a field on Budget tab

Previously the only way to close the keyboard was tapping the
currency dropdown, which could hide rows below it."
```

---

### Task 3: Auto-save + swipe-to-delete on category rows

**Files:**
- Modify: `app/lib/features/budget/budget_screen.dart` (`_BudgetRow`, and its call site + `_save`/`_removeCategory` in `_BudgetScreenState`)
- Test: Modify `app/test/budget_screen_test.dart` (append two tests)

**Interfaces:**
- Consumes: `BudgetsDao.upsert` (Task 1, now conflict-safe), `CategoriesDao.remove(String) → Future<void>` (existing, unchanged).
- Produces: `_BudgetRow` constructor gains `onConfirmRemove: Future<bool> Function()` in place of `onRemove: VoidCallback`. `_BudgetScreenState._removeCategory(String category) → Future<bool>` (was `Future<void>`) — `true` if the category was actually removed, `false` if the user canceled the confirm dialog.

**Context:** Today `_BudgetRow` is `StatelessWidget` with a checkmark button (`onSave`) and a remove-circle button (`onRemove: VoidCallback`) that triggers `_removeCategory`'s confirm dialog. This task removes both buttons: the cap field auto-saves via a 600ms debounce and on focus loss, and swiping the row left reveals a delete affordance that still runs through the existing confirm dialog before actually removing anything.

- [ ] **Step 1: Write the failing tests**

Append to `app/test/budget_screen_test.dart` (inside `main()`, after the existing test):

```dart
  testWidgets(
      'typing a cap amount auto-saves after the debounce without tapping a button',
      (tester) async {
    final db = await _pumpBudgetScreen(tester);

    // Categories are listed alphabetically; "Bills & Utilities" is first.
    final capField = find.widgetWithText(TextField, 'No cap').first;
    await tester.enterText(capField, '50');
    await tester.pump(const Duration(milliseconds: 700));

    final rows = await db.budgetsDao.all();
    expect(rows.any((b) => b.category == 'Bills & Utilities' && b.monthlyLimit == 50.0),
        isTrue);
    expect(find.byIcon(Icons.check), findsWidgets);

    await db.close();
  });

  testWidgets('swiping a row left and confirming removes the category',
      (tester) async {
    final db = await _pumpBudgetScreen(tester);

    expect(find.text('Bills & Utilities'), findsOneWidget);
    await tester.drag(find.text('Bills & Utilities'), const Offset(-500, 0));
    await tester.pumpAndSettle();

    expect(find.text('Remove Bills & Utilities?'), findsOneWidget);
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();

    expect(find.text('Bills & Utilities'), findsNothing);
    final categories = await db.categoriesDao.all();
    expect(categories.any((c) => c.name == 'Bills & Utilities'), isFalse);

    await db.close();
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd app && flutter test test/budget_screen_test.dart`
Expected: both new tests FAIL — no `Icons.check` widget exists yet for the auto-save confirmation, and dragging the row does nothing because there's no `Dismissible`.

- [ ] **Step 3: Rewrite `_BudgetRow` as a `StatefulWidget`**

In `app/lib/features/budget/budget_screen.dart`, add `import 'dart:async';` to the top of the file (with the other imports, alphabetically first).

Replace the entire `_BudgetRow` class (originally lines 225-287) with:

```dart
class _BudgetRow extends StatefulWidget {
  final String category;
  final TextEditingController controller;
  final String currency;
  final Future<void> Function(String, String) onSave;
  final Future<bool> Function() onConfirmRemove;
  final bool isDefault;
  const _BudgetRow({
    required this.category,
    required this.controller,
    required this.currency,
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
                  decoration: InputDecoration(
                    hintText: 'No cap',
                    suffixText: widget.currency,
                  ),
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
```

- [ ] **Step 4: Update `_save` in `_BudgetScreenState`**

Replace `_save` (originally lines 120-138):

```dart
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
```

with:

```dart
  Future<void> _save(String category, String raw) async {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return;
    final amount = double.tryParse(trimmed);
    if (amount == null || amount <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter a valid amount')),
        );
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
            cycle: _cycle,
            cycleDays: _cycleDays,
            currency: _currency,
          );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save $category cap: $error')),
        );
      }
    }
  }
```

`fmtCurrency` is no longer used by this method; leave its import in place since `_PeriodCard` and other parts of the file don't use it either — check with `flutter analyze` in Step 6 and remove the import only if it flags as unused.

- [ ] **Step 5: Update `_removeCategory` to return `Future<bool>` and update the `_BudgetRow` call site**

Replace `_removeCategory` (originally lines 140-163):

```dart
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
```

with:

```dart
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
```

Then update the `_BudgetRow(...)` construction inside `build()`'s `SliverChildBuilderDelegate` (originally lines 101-108):

```dart
                  (_, i) => _BudgetRow(
                    category: names[i],
                    controller: _controllers[names[i]]!,
                    currency: _currency,
                    onSave: _save,
                    onRemove: () => _removeCategory(names[i]),
                    isDefault: records[names[i]]?.isDefault ?? false,
                  ),
```

to:

```dart
                  (_, i) => _BudgetRow(
                    category: names[i],
                    controller: _controllers[names[i]]!,
                    currency: _currency,
                    onSave: _save,
                    onConfirmRemove: () => _removeCategory(names[i]),
                    isDefault: records[names[i]]?.isDefault ?? false,
                  ),
```

- [ ] **Step 6: Run the full test suite and analyzer**

Run: `cd app && dart format lib/features/budget/budget_screen.dart && flutter analyze && flutter test`
Expected: no new analyzer issues (if `fmtCurrency`'s import is now flagged unused, remove the `import '../../core/format.dart';` line), all tests pass including the two new ones from Step 1.

- [ ] **Step 7: Manual verification in the simulator**

Boot the iOS Simulator, run the app (`flutter run`), navigate to the Budget tab, and confirm: (a) typing a cap amount and waiting briefly shows a fading checkmark with no manual save tap, (b) tapping away from a focused field dismisses the keyboard, (c) swiping a category row left reveals a red delete background and the existing confirm dialog, and confirming removes it from the list.

- [ ] **Step 8: Commit**

```bash
cd app && git add lib/features/budget/budget_screen.dart test/budget_screen_test.dart
git commit -m "feat: auto-save budget caps and swipe-to-delete categories

Removes the manual checkmark/remove-circle buttons from budget rows.
Caps now save via a 600ms debounce plus on-blur; categories are
removed via swipe-left with the existing confirm dialog."
```

---

## Self-Review Notes

- **Spec coverage:** keyboard-dismiss (Task 2), auto-save debounce+blur with silent success/error-only snackbar (Task 3 Steps 3-4), swipe-to-delete with confirm dialog reused (Task 3 Steps 3, 5), English-only copy (all new strings — "Enter a valid amount", "Could not save $category cap: $error" — are English) — all covered.
- **Prerequisite bug:** `BudgetsDao.upsert`'s conflict-target bug (Task 1) was discovered while designing the auto-save flow — without it, the *second* auto-save of any category in the same period would throw. Fixed first so Task 3 builds on a correct foundation, mirroring the same fix already applied to `CategoriesDao`.
- **Type consistency:** `onRemove: VoidCallback` → `onConfirmRemove: Future<bool> Function()` is renamed and retyped consistently between `_BudgetRow`'s constructor (Task 3 Step 3) and its call site (Task 3 Step 5). `_removeCategory`'s return type change from `Future<void>` to `Future<bool>` is consistent everywhere it's referenced.
