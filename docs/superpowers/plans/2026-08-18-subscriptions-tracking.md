# Subscriptions Tracking Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a standalone Subscriptions tracking feature: manual entry, auto-detected suggestions from transaction history, curated brand-color icons, and renewal reminders via the existing `NotificationScheduler`.

**Architecture:** New `Subscriptions` Drift table + `SubscriptionsDao`, a new `lib/features/subscriptions/` screen reachable from Settings, a pure suggestion-detection function fed by the existing `transactionsStreamProvider`, and an extension to `NotificationScheduler.refresh()` for per-subscription renewal reminders.

**Tech Stack:** Flutter/Dart, Riverpod, Drift/SQLite (same stack as the rest of the app — no new dependencies).

## Deviation from the approved spec

The spec ([2026-08-18-subscriptions-tracking-design.md](../specs/2026-08-18-subscriptions-tracking-design.md))
listed `isActive`/`setActive` (pause without deleting) as a DAO capability,
but never actually specified a pause *interaction* in the screen — only
swipe-to-delete-style removal is described. Since nothing else in the
design (suggestions, notifications) needs a distinct "paused" state, and an
unused `setActive` method would be dead code the moment it shipped, this
plan drops `isActive`/`setActive` entirely: subscriptions are either
tracked (in the table) or removed (deleted), matching the Budget tab's
existing category-removal UX exactly. If pausing turns out to be wanted
later, it's a small additive change.

## Global Constraints

- All UI copy is in English. No Spanish (or any other language) strings in any user-facing text.
- Subscriptions do not generate transactions, do not affect Budget/Insights/Dashboard spend totals, and do not touch `TransactionsDao`'s write path.
- Notification IDs `9001`-`9004` are already used by the existing daily reminders (`lib/core/notification_scheduler.dart`) — subscription reminder IDs must never collide with them.
- `DateTime` month/year rollover must always use the `DateTime(y, m+1, d)` constructor-arithmetic pattern, never `Duration`-based addition (the codebase already hit and fixed a DST bug from the latter — see `notification_scheduler_test.dart`'s DST regression test).

---

### Task 1: Data model — `Subscriptions` table and `SubscriptionsDao`

**Files:**
- Modify: `app/lib/data/tables.dart`
- Modify: `app/lib/data/db.dart`
- Create: `app/lib/data/subscriptions_dao.dart`
- Test: `app/test/subscriptions_dao_test.dart`

**Interfaces:**
- Produces: `Subscriptions` table (Drift-generated `Subscription` row class,
  `SubscriptionsCompanion`), `SubscriptionsDao` with `watchAll()`, `add()`,
  `update()`, `remove()`, `allForScheduling()`, `rollForwardTo()`. Later
  tasks read/write through these exact names.

- [ ] **Step 1: Add the `Subscriptions` table**

In `app/lib/data/tables.dart`, add at the end of the file:

```dart
class Subscriptions extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get brandKey => text().nullable()();
  RealColumn get amount => real()();
  TextColumn get currency => text().withDefault(const Constant('USD'))();
  TextColumn get cycle => text()(); // 'monthly' | 'yearly'
  DateTimeColumn get nextChargeDate => dateTime()();
  TextColumn get source => text().withDefault(const Constant('manual'))(); // 'manual' | 'suggested'
  DateTimeColumn get createdAt => dateTime()();
}
```

- [ ] **Step 2: Register the table and bump the schema version**

In `app/lib/data/db.dart`:

1. Add `import 'subscriptions_dao.dart';` alongside the other DAO imports.
2. Add `Subscriptions` to the `@DriftDatabase(tables: [...])` list.
3. Bump `schemaVersion` from `4` to `5`.
4. Add a migration step and a DAO field:

```dart
  @override
  int get schemaVersion => 5;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      for (final name in defaultCategoryNames) {
        await into(categories).insert(
          CategoriesCompanion.insert(name: name, isDefault: const Value(true)),
        );
      }
    },
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.addColumn(mentorMessages, mentorMessages.severity);
      }
      if (from < 3) {
        await m.createTable(categories);
        await m.addColumn(budgets, budgets.cycle);
        await m.addColumn(budgets, budgets.cycleDays);
        await m.addColumn(budgets, budgets.currency);
        await m.addColumn(budgets, budgets.enabled);
      }
      if (from < 4) {
        await categoriesDao.ensureDefaults();
      }
      if (from < 5) {
        await m.createTable(subscriptions);
      }
    },
  );

  late final SettingsDao settingsDao = SettingsDao(this);
  late final TransactionsDao transactionsDao = TransactionsDao(this);
  late final BudgetsDao budgetsDao = BudgetsDao(this);
  late final CategoriesDao categoriesDao = CategoriesDao(this);
  late final MessagesDao messagesDao = MessagesDao(this);
  late final MemoriesDao memoriesDao = MemoriesDao(this);
  late final SubscriptionsDao subscriptionsDao = SubscriptionsDao(this);
```

- [ ] **Step 3: Write `SubscriptionsDao`**

Create `app/lib/data/subscriptions_dao.dart`:

```dart
import 'package:drift/drift.dart';

import 'db.dart';

class SubscriptionsDao {
  final AppDatabase db;
  SubscriptionsDao(this.db);

  Stream<List<Subscription>> watchAll() =>
      (db.select(db.subscriptions)
            ..orderBy([(s) => OrderingTerm.asc(s.nextChargeDate)]))
          .watch();

  Future<int> add(SubscriptionsCompanion entry) =>
      db.into(db.subscriptions).insert(entry);

  Future<void> update(int id, SubscriptionsCompanion changes) =>
      (db.update(db.subscriptions)..where((s) => s.id.equals(id)))
          .write(changes);

  Future<void> remove(int id) =>
      (db.delete(db.subscriptions)..where((s) => s.id.equals(id))).go();

  Future<List<Subscription>> allForScheduling() =>
      db.select(db.subscriptions).get();

  Future<void> rollForwardTo(int id, DateTime newNextChargeDate) => update(
        id,
        SubscriptionsCompanion(nextChargeDate: Value(newNextChargeDate)),
      );
}
```

- [ ] **Step 4: Regenerate Drift's generated code**

Run: `cd app && dart run build_runner build --delete-conflicting-outputs`
Expected: completes without errors; `lib/data/db.g.dart` now contains
generated `Subscription`, `SubscriptionsCompanion`, and `$SubscriptionsTable`
classes.

- [ ] **Step 5: Write the failing tests**

Create `app/test/subscriptions_dao_test.dart`:

```dart
import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneylock/data/db.dart';

AppDatabase _db() => AppDatabase.forTesting(
    driftDatabase(name: 'test_${DateTime.now().microsecondsSinceEpoch}'));

SubscriptionsCompanion _entry({
  String name = 'Netflix',
  String? brandKey = 'netflix',
  double amount = 15.99,
  String cycle = 'monthly',
  required DateTime nextChargeDate,
  String source = 'manual',
}) =>
    SubscriptionsCompanion.insert(
      name: name,
      brandKey: Value(brandKey),
      amount: amount,
      cycle: cycle,
      nextChargeDate: nextChargeDate,
      source: Value(source),
      createdAt: DateTime(2026, 1, 1),
    );

void main() {
  test('add + watchAll returns the inserted subscription', () async {
    final db = _db();
    await db.subscriptionsDao
        .add(_entry(nextChargeDate: DateTime(2026, 9, 1)));

    final rows = await db.subscriptionsDao.watchAll().first;

    expect(rows, hasLength(1));
    expect(rows.first.name, 'Netflix');
    expect(rows.first.brandKey, 'netflix');
    await db.close();
  });

  test('watchAll orders by nextChargeDate ascending', () async {
    final db = _db();
    await db.subscriptionsDao.add(
        _entry(name: 'Later', nextChargeDate: DateTime(2026, 10, 1)));
    await db.subscriptionsDao.add(
        _entry(name: 'Sooner', nextChargeDate: DateTime(2026, 9, 1)));

    final rows = await db.subscriptionsDao.watchAll().first;

    expect(rows.map((r) => r.name).toList(), ['Sooner', 'Later']);
    await db.close();
  });

  test('remove deletes the subscription', () async {
    final db = _db();
    final id = await db.subscriptionsDao
        .add(_entry(nextChargeDate: DateTime(2026, 9, 1)));

    await db.subscriptionsDao.remove(id);

    final rows = await db.subscriptionsDao.watchAll().first;
    expect(rows, isEmpty);
    await db.close();
  });

  test('allForScheduling returns every subscription for the scheduler',
      () async {
    final db = _db();
    await db.subscriptionsDao
        .add(_entry(nextChargeDate: DateTime(2026, 9, 1)));
    await db.subscriptionsDao
        .add(_entry(name: 'Spotify', nextChargeDate: DateTime(2026, 9, 5)));

    final rows = await db.subscriptionsDao.allForScheduling();

    expect(rows, hasLength(2));
    await db.close();
  });

  test('rollForwardTo updates nextChargeDate', () async {
    final db = _db();
    final id = await db.subscriptionsDao
        .add(_entry(nextChargeDate: DateTime(2026, 9, 1)));

    await db.subscriptionsDao.rollForwardTo(id, DateTime(2026, 10, 1));

    final rows = await db.subscriptionsDao.allForScheduling();
    expect(rows.single.nextChargeDate, DateTime(2026, 10, 1));
    await db.close();
  });
}
```

- [ ] **Step 6: Run the tests**

Run: `cd app && flutter test test/subscriptions_dao_test.dart -r expanded`
Expected: 5 tests pass.

- [ ] **Step 7: Write the migration regression test**

Create `app/test/subscriptions_migration_test.dart` (same pattern as the
existing `test/db_migration_test.dart`):

```dart
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneylock/data/db.dart';

void main() {
  test('upgrading from schema v4 creates the subscriptions table', () async {
    final file = File(
      '${Directory.systemTemp.path}/subs_migration_test_${DateTime.now().microsecondsSinceEpoch}.sqlite',
    );

    final seedDb = AppDatabase.forTesting(NativeDatabase(file));
    await seedDb.categoriesDao.all(); // forces onCreate to run at schemaVersion 5
    await seedDb.customStatement('PRAGMA user_version = 4');
    await seedDb.close();

    final upgradedDb = AppDatabase.forTesting(NativeDatabase(file));
    final rows = await upgradedDb.subscriptionsDao.allForScheduling();
    expect(rows, isEmpty); // does not throw -- table exists

    await upgradedDb.close();
    await file.delete();
  });
}
```

- [ ] **Step 8: Run the migration test**

Run: `cd app && flutter test test/subscriptions_migration_test.dart -r expanded`
Expected: 1 test passes.

- [ ] **Step 9: Commit**

```bash
cd app
git add lib/data/tables.dart lib/data/db.dart lib/data/db.g.dart lib/data/subscriptions_dao.dart test/subscriptions_dao_test.dart test/subscriptions_migration_test.dart
git commit -m "feat: add Subscriptions table and SubscriptionsDao"
```

---

### Task 2: Curated brand icon set

**Files:**
- Create: `app/lib/widgets/brand_icon.dart`
- Test: `app/test/brand_icon_test.dart`

**Interfaces:**
- Consumes: nothing (pure widget + static data, no DB, no providers).
- Produces: `const Map<String, BrandIcon> brandIcons` (keyed by brand key,
  e.g. `'netflix'`), `class BrandIcon { final Color color; final IconData
  icon; }`, `class SubscriptionAvatar extends StatelessWidget` with
  constructor `SubscriptionAvatar({String? brandKey, required String
  name})`. Task 3's list rows and add-sheet icon picker consume these
  exact names.

- [ ] **Step 1: Write the failing test**

Create `app/test/brand_icon_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneylock/widgets/brand_icon.dart';

void main() {
  testWidgets('known brandKey renders the curated icon', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: SubscriptionAvatar(brandKey: 'netflix', name: 'Netflix'),
    ));

    expect(find.byIcon(brandIcons['netflix']!.icon), findsOneWidget);
  });

  testWidgets('unknown brandKey falls back to an initial avatar',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: SubscriptionAvatar(brandKey: null, name: 'Gym Membership'),
    ));

    expect(find.text('G'), findsOneWidget);
  });

  testWidgets('brandKey not present in the curated set also falls back',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: SubscriptionAvatar(brandKey: 'not-a-real-brand', name: 'Zed'),
    ));

    expect(find.text('Z'), findsOneWidget);
  });

  test('curated set has at least 15 brands', () {
    expect(brandIcons.length, greaterThanOrEqualTo(15));
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd app && flutter test test/brand_icon_test.dart -r expanded`
Expected: FAIL with "Target of URI doesn't exist: 'package:moneylock/widgets/brand_icon.dart'".

- [ ] **Step 3: Implement the brand icon set and avatar widget**

Create `app/lib/widgets/brand_icon.dart`:

```dart
import 'package:flutter/material.dart';

class BrandIcon {
  final Color color;
  final IconData icon;
  const BrandIcon(this.color, this.icon);
}

/// Simplified, hand-drawn vector representations (color + a recognizable
/// glyph) for common subscription services -- not reproductions of the
/// official logos.
const brandIcons = <String, BrandIcon>{
  'netflix': BrandIcon(Color(0xFFE50914), Icons.play_arrow),
  'spotify': BrandIcon(Color(0xFF1DB954), Icons.graphic_eq),
  'disney_plus': BrandIcon(Color(0xFF113CCF), Icons.castle),
  'youtube_premium': BrandIcon(Color(0xFFFF0000), Icons.smart_display),
  'amazon_prime': BrandIcon(Color(0xFF00A8E1), Icons.shopping_bag),
  'apple_music': BrandIcon(Color(0xFFFA243C), Icons.music_note),
  'apple_tv_plus': BrandIcon(Color(0xFF000000), Icons.tv),
  'hbo_max': BrandIcon(Color(0xFF5822B4), Icons.theaters),
  'icloud_plus': BrandIcon(Color(0xFF3693F3), Icons.cloud),
  'hulu': BrandIcon(Color(0xFF1CE783), Icons.live_tv),
  'playstation_plus': BrandIcon(Color(0xFF0070D1), Icons.sports_esports),
  'xbox_game_pass': BrandIcon(Color(0xFF107C10), Icons.videogame_asset),
  'adobe_creative_cloud': BrandIcon(Color(0xFFDA1F26), Icons.brush),
  'dropbox': BrandIcon(Color(0xFF0061FF), Icons.folder),
  'onepassword': BrandIcon(Color(0xFF1A8CFF), Icons.key),
  'chatgpt_plus': BrandIcon(Color(0xFF10A37F), Icons.chat_bubble),
  'notion': BrandIcon(Color(0xFF000000), Icons.description),
};

Color _colorForName(String name) {
  const palette = [
    Color(0xFFBA1A1A),
    Color(0xFF6750A4),
    Color(0xFF006A6A),
    Color(0xFF7D5260),
    Color(0xFF386A20),
    Color(0xFF984061),
  ];
  return palette[name.codeUnits.fold(0, (a, b) => a + b) % palette.length];
}

class SubscriptionAvatar extends StatelessWidget {
  final String? brandKey;
  final String name;
  const SubscriptionAvatar({super.key, this.brandKey, required this.name});

  @override
  Widget build(BuildContext context) {
    final brand = brandKey == null ? null : brandIcons[brandKey];
    if (brand != null) {
      return CircleAvatar(
        backgroundColor: brand.color,
        child: Icon(brand.icon, color: Colors.white),
      );
    }
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    return CircleAvatar(
      backgroundColor: _colorForName(name),
      child: Text(initial, style: const TextStyle(color: Colors.white)),
    );
  }
}
```

- [ ] **Step 4: Run the tests**

Run: `cd app && flutter test test/brand_icon_test.dart -r expanded`
Expected: 4 tests pass.

- [ ] **Step 5: Commit**

```bash
cd app
git add lib/widgets/brand_icon.dart test/brand_icon_test.dart
git commit -m "feat: add curated brand icon set for subscriptions"
```

---

### Task 3: Subscriptions screen, add form, Settings entry point

**Files:**
- Create: `app/lib/features/subscriptions/subscriptions_screen.dart`
- Modify: `app/lib/providers.dart`
- Modify: `app/lib/core/router.dart`
- Modify: `app/lib/features/settings/settings_screen.dart`
- Test: `app/test/subscriptions_screen_test.dart`

**Interfaces:**
- Consumes: `SubscriptionsDao` (Task 1), `SubscriptionAvatar`/`brandIcons`
  (Task 2).
- Produces: `subscriptionsProvider` (`StreamProvider<List<Subscription>>`),
  `SubscriptionsScreen` widget, `/subscriptions` route. Task 4 adds the
  "Suggested" section into this same screen file; Task 5 adds
  notification-cancel calls into this same screen's remove handler.

- [ ] **Step 1: Add the subscriptions stream provider**

In `app/lib/providers.dart`, add after `messagesStreamProvider`:

```dart
final subscriptionsProvider = StreamProvider<List<Subscription>>(
  (ref) => ref.watch(appDatabaseProvider).subscriptionsDao.watchAll(),
);
```

- [ ] **Step 2: Add the `/subscriptions` route**

In `app/lib/core/router.dart`:

1. Add `import '../features/subscriptions/subscriptions_screen.dart';`
   alongside the other feature imports.
2. Add a new `GoRoute` after the `/settings` route:

```dart
    GoRoute(
      path: '/subscriptions',
      parentNavigatorKey: _rootNavigatorKey,
      pageBuilder: (_, _) =>
          const NoTransitionPage(child: SubscriptionsScreen()),
    ),
```

- [ ] **Step 3: Add the Settings entry point**

In `app/lib/features/settings/settings_screen.dart`, add
`import 'package:go_router/go_router.dart';` at the top, and add a new
section after the existing `NOTIFICATIONS` section (inside the `ListView`'s
`children`, right after `const _NotificationsCard(),`):

```dart
            const SizedBox(height: 28),
            const _Section('SUBSCRIPTIONS'),
            _SubscriptionsEntry(onTap: () => context.push('/subscriptions')),
```

And add the new widget class near `_NotificationsCard`:

```dart
class _SubscriptionsEntry extends StatelessWidget {
  final VoidCallback onTap;
  const _SubscriptionsEntry({required this.onTap});
  @override
  Widget build(BuildContext context) => _Card(
    child: InkWell(
      onTap: onTap,
      child: Row(
        children: [
          const Expanded(
            child: Text('Manage subscriptions', style: AppTextStyles.bodyMd),
          ),
          Icon(Icons.chevron_right, color: AppColors.onSurfaceVariant),
        ],
      ),
    ),
  );
}
```

- [ ] **Step 4: Write the subscriptions screen**

Create `app/lib/features/subscriptions/subscriptions_screen.dart`:

```dart
import 'package:drift/drift.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../data/db.dart';
import '../../providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/brand_icon.dart';
import '../../widgets/kit.dart';

class SubscriptionsScreen extends ConsumerWidget {
  const SubscriptionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subscriptions = ref.watch(subscriptionsProvider).valueOrNull ?? const [];
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

class _AddSubscriptionSheet extends ConsumerStatefulWidget {
  final SubscriptionsCompanion? prefill;
  const _AddSubscriptionSheet({this.prefill});

  @override
  ConsumerState<_AddSubscriptionSheet> createState() => _AddSubscriptionSheetState();
}

class _AddSubscriptionSheetState extends ConsumerState<_AddSubscriptionSheet> {
  late final _nameController = TextEditingController(text: widget.prefill?.name.value ?? '');
  late final _amountController = TextEditingController(
    text: widget.prefill?.amount.value == null ? '' : widget.prefill!.amount.value.toStringAsFixed(2),
  );
  String _cycle = 'monthly';
  DateTime _nextChargeDate = DateTime.now();
  String? _brandKey;

  @override
  void initState() {
    super.initState();
    _nextChargeDate = widget.prefill?.nextChargeDate.value ?? DateTime.now();
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
            createdAt: DateTime.now(),
          ),
        );
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
```

- [ ] **Step 5: Write the render-only screen test**

Create `app/test/subscriptions_screen_test.dart`. This follows the
render-only pattern established in `test/settings_notifications_test.dart`
(sub-project 2): mock every DB-backed provider the screen reads for its
initial build, since a real native-isolate Drift read inside `testWidgets`
is unreliable in this environment even with `tester.runAsync()`.

```dart
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneylock/data/db.dart';
import 'package:moneylock/features/subscriptions/subscriptions_screen.dart';
import 'package:moneylock/providers.dart';

AppDatabase _db() => AppDatabase.forTesting(
    driftDatabase(name: 'test_${DateTime.now().microsecondsSinceEpoch}'));

void main() {
  testWidgets('renders the empty state with no subscriptions', (tester) async {
    final db = _db();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          subscriptionsProvider.overrideWith((ref) => Stream.value(const [])),
        ],
        child: const MaterialApp(home: SubscriptionsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Subscriptions'), findsOneWidget);
    expect(find.text('No subscriptions tracked yet. Tap + to add one.'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.runAsync(() => db.close());
  });
}
```

- [ ] **Step 6: Run the test**

Run: `cd app && flutter test test/subscriptions_screen_test.dart -r expanded`
Expected: 1 test passes.

- [ ] **Step 7: Run `flutter analyze`**

Run: `cd app && flutter analyze`
Expected: only the pre-existing 11 info-level issues, nothing new.

- [ ] **Step 8: Commit**

```bash
cd app
git add lib/providers.dart lib/core/router.dart lib/features/settings/settings_screen.dart lib/features/subscriptions/subscriptions_screen.dart test/subscriptions_screen_test.dart
git commit -m "feat: add subscriptions screen, add form, and Settings entry point"
```

---

### Task 4: Suggested subscriptions

**Files:**
- Create: `app/lib/features/subscriptions/subscription_suggestions.dart`
- Modify: `app/lib/data/db.dart` (`SettingsDao`)
- Modify: `app/lib/features/subscriptions/subscriptions_screen.dart`
- Test: `app/test/subscription_suggestions_test.dart`
- Test: `app/test/dismissed_suggestions_test.dart`

**Interfaces:**
- Consumes: `Transaction` (existing, from `transactionsStreamProvider`),
  `Subscription` (Task 1).
- Produces: `SuggestedSubscription {merchant, averageAmount,
  occurrenceCount, mostRecentDate}`, `List<SuggestedSubscription>
  detectSuggestions({required transactions, required existingSubscriptions,
  required dismissedMerchants})`, `SettingsDao.dismissedSubscriptionSuggestions()`,
  `SettingsDao.dismissSubscriptionSuggestion(String merchant)`.

- [ ] **Step 1: Write the failing suggestion-detection tests**

Create `app/test/subscription_suggestions_test.dart`:

```dart
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneylock/data/db.dart';
import 'package:moneylock/data/transactions_dao.dart';
import 'package:moneylock/features/subscriptions/subscription_suggestions.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(driftDatabase(name: 'test_${DateTime.now().microsecondsSinceEpoch}'));
  });

  tearDown(() => db.close());

  Future<Transaction> insertTx(String merchant, double amount, DateTime timestamp) async {
    final outcome = await db.transactionsDao.insertWithDedup(NewTransaction(
      amount: amount,
      currency: 'USD',
      merchant: merchant,
      category: 'Entertainment',
      source: 'manual',
      rawText: '$merchant $amount',
      timestamp: timestamp,
    ));
    return outcome.transaction!;
  }

  test('same merchant 2+ times within 10% amount band is suggested', () async {
    final txs = [
      await insertTx('Netflix', 15.99, DateTime(2026, 7, 1)),
      await insertTx('Netflix', 15.99, DateTime(2026, 8, 1)),
    ];

    final suggestions = detectSuggestions(
      transactions: txs,
      existingSubscriptions: const [],
      dismissedMerchants: const {},
    );

    expect(suggestions, hasLength(1));
    expect(suggestions.single.merchant, 'Netflix');
    expect(suggestions.single.occurrenceCount, 2);
  });

  test('a single occurrence is not suggested', () async {
    final txs = [await insertTx('Netflix', 15.99, DateTime(2026, 7, 1))];

    final suggestions = detectSuggestions(
      transactions: txs,
      existingSubscriptions: const [],
      dismissedMerchants: const {},
    );

    expect(suggestions, isEmpty);
  });

  test('amounts more than 10% apart are not suggested', () async {
    final txs = [
      await insertTx('Uber', 8.00, DateTime(2026, 7, 1)),
      await insertTx('Uber', 40.00, DateTime(2026, 8, 1)),
    ];

    final suggestions = detectSuggestions(
      transactions: txs,
      existingSubscriptions: const [],
      dismissedMerchants: const {},
    );

    expect(suggestions, isEmpty);
  });

  test('a merchant matching an existing subscription (case-insensitive) is excluded', () async {
    final txs = [
      await insertTx('netflix', 15.99, DateTime(2026, 7, 1)),
      await insertTx('netflix', 15.99, DateTime(2026, 8, 1)),
    ];
    final subId = await db.subscriptionsDao.add(SubscriptionsCompanion.insert(
      name: 'Netflix',
      amount: 15.99,
      cycle: 'monthly',
      nextChargeDate: DateTime(2026, 9, 1),
      createdAt: DateTime(2026, 1, 1),
    ));
    final existing = await db.subscriptionsDao.allForScheduling();

    final suggestions = detectSuggestions(
      transactions: txs,
      existingSubscriptions: existing,
      dismissedMerchants: const {},
    );

    expect(suggestions, isEmpty);
    expect(subId, isNotNull);
  });

  test('a dismissed merchant is excluded', () async {
    final txs = [
      await insertTx('Spotify', 9.99, DateTime(2026, 7, 1)),
      await insertTx('Spotify', 9.99, DateTime(2026, 8, 1)),
    ];

    final suggestions = detectSuggestions(
      transactions: txs,
      existingSubscriptions: const [],
      dismissedMerchants: {'spotify'},
    );

    expect(suggestions, isEmpty);
  });
}
```

The exclusion test above references `SubscriptionsCompanion`, which comes
from `db.dart` (already imported) — Drift generates that class into
`db.g.dart`, included via `db.dart`'s `part` directive, so no separate
`subscriptions_dao.dart` import is needed in this test file.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd app && flutter test test/subscription_suggestions_test.dart -r expanded`
Expected: FAIL with "Target of URI doesn't exist:
'package:moneylock/features/subscriptions/subscription_suggestions.dart'".

- [ ] **Step 3: Implement the detection function**

Create `app/lib/features/subscriptions/subscription_suggestions.dart`:

```dart
import '../../data/db.dart';

class SuggestedSubscription {
  final String merchant;
  final double averageAmount;
  final int occurrenceCount;
  final DateTime mostRecentDate;
  SuggestedSubscription({
    required this.merchant,
    required this.averageAmount,
    required this.occurrenceCount,
    required this.mostRecentDate,
  });
}

List<SuggestedSubscription> detectSuggestions({
  required List<Transaction> transactions,
  required List<Subscription> existingSubscriptions,
  required Set<String> dismissedMerchants,
}) {
  final existingNames = existingSubscriptions.map((s) => s.name.toLowerCase()).toSet();
  final byMerchant = <String, List<Transaction>>{};
  for (final t in transactions) {
    final key = t.merchant.trim().toLowerCase();
    if (key.isEmpty) continue;
    byMerchant.putIfAbsent(key, () => []).add(t);
  }

  final suggestions = <SuggestedSubscription>[];
  for (final entry in byMerchant.entries) {
    final key = entry.key;
    final group = entry.value;
    if (group.length < 2) continue;
    if (existingNames.contains(key)) continue;
    if (dismissedMerchants.contains(key)) continue;

    final average = group.fold<double>(0, (a, t) => a + t.amount) / group.length;
    final withinBand = group.every((t) => (t.amount - average).abs() <= average * 0.10);
    if (!withinBand) continue;

    group.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    suggestions.add(SuggestedSubscription(
      merchant: group.first.merchant,
      averageAmount: average,
      occurrenceCount: group.length,
      mostRecentDate: group.first.timestamp,
    ));
  }
  return suggestions;
}
```

- [ ] **Step 4: Run the tests**

Run: `cd app && flutter test test/subscription_suggestions_test.dart -r expanded`
Expected: 5 tests pass.

- [ ] **Step 5: Write the failing `SettingsDao` dismissal tests**

Create `app/test/dismissed_suggestions_test.dart`:

```dart
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneylock/data/db.dart';

AppDatabase _db() => AppDatabase.forTesting(
    driftDatabase(name: 'test_${DateTime.now().microsecondsSinceEpoch}'));

void main() {
  test('dismissedSubscriptionSuggestions defaults to empty', () async {
    final db = _db();
    expect(await db.settingsDao.dismissedSubscriptionSuggestions(), isEmpty);
    await db.close();
  });

  test('dismissSubscriptionSuggestion adds a lowercased entry', () async {
    final db = _db();
    await db.settingsDao.dismissSubscriptionSuggestion('Netflix');

    final dismissed = await db.settingsDao.dismissedSubscriptionSuggestions();

    expect(dismissed, {'netflix'});
    await db.close();
  });

  test('dismissing the same merchant twice does not duplicate it', () async {
    final db = _db();
    await db.settingsDao.dismissSubscriptionSuggestion('Spotify');
    await db.settingsDao.dismissSubscriptionSuggestion('Spotify');

    final dismissed = await db.settingsDao.dismissedSubscriptionSuggestions();

    expect(dismissed, {'spotify'});
    await db.close();
  });

  test('dismissing multiple merchants accumulates them', () async {
    final db = _db();
    await db.settingsDao.dismissSubscriptionSuggestion('Netflix');
    await db.settingsDao.dismissSubscriptionSuggestion('Spotify');

    final dismissed = await db.settingsDao.dismissedSubscriptionSuggestions();

    expect(dismissed, {'netflix', 'spotify'});
    await db.close();
  });
}
```

- [ ] **Step 6: Run the tests to verify they fail**

Run: `cd app && flutter test test/dismissed_suggestions_test.dart -r expanded`
Expected: FAIL — `dismissedSubscriptionSuggestions` is not a method on `SettingsDao`.

- [ ] **Step 7: Implement the two `SettingsDao` methods**

In `app/lib/data/db.dart`'s `SettingsDao` class, add after
`setNotificationsEnabled`:

```dart
  Future<Set<String>> dismissedSubscriptionSuggestions() async {
    final row = await (db.select(
      db.settings,
    )..where((s) => s.key.equals('dismissed_subscription_suggestions'))).getSingleOrNull();
    if (row == null || row.value.isEmpty) return {};
    return row.value.split(',').toSet();
  }

  Future<void> dismissSubscriptionSuggestion(String merchant) async {
    final current = await dismissedSubscriptionSuggestions();
    final updated = {...current, merchant.trim().toLowerCase()};
    await db
        .into(db.settings)
        .insertOnConflictUpdate(
          SettingsCompanion.insert(
            key: 'dismissed_subscription_suggestions',
            value: updated.join(','),
          ),
        );
  }
```

- [ ] **Step 8: Run the tests**

Run: `cd app && flutter test test/dismissed_suggestions_test.dart -r expanded`
Expected: 4 tests pass.

- [ ] **Step 9: Wire the "Suggested" section into the screen**

In `app/lib/features/subscriptions/subscriptions_screen.dart`:

1. Add `import 'subscription_suggestions.dart';`.
2. Add a `FutureProvider<Set<String>>` for the dismissed set, and a
   derived provider combining transactions + subscriptions + dismissals,
   both above the `SubscriptionsScreen` class. The dismissed-set provider
   is deliberately **not** private (no leading underscore): sub-project
   2's `settings_notifications_test.dart` hit repeated real hangs from an
   *unmocked* real-DB `FutureProvider` reachable from a widget's initial
   build, even though nothing in the widget ever awaited its result
   directly — only overriding it in the test's `ProviderScope` fixed it.
   This provider is the same shape, so it must be overridable the same
   way:

```dart
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
```

3. In `SubscriptionsScreen.build`, read `final suggestions =
   ref.watch(subscriptionSuggestionsProvider);` and insert a suggestions
   section above the list (right after the header `Padding`, before the
   `Expanded(child: subscriptions.isEmpty ? ... )` block):

```dart
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
```

4. Add the `_SuggestionCard` widget near `_SubscriptionRow`:

```dart
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
```

5. `_openAddSheet` already accepts an optional `prefill` parameter from
   Task 3 — no change needed there.

- [ ] **Step 10: Update the screen test's provider overrides**

`SubscriptionsScreen` now also watches `subscriptionSuggestionsProvider`,
which pulls from `transactionsStreamProvider` and
`dismissedSubscriptionSuggestionsProvider` in addition to
`subscriptionsProvider`. Update the existing test's `overrides` list to
mock all three DB-backed providers the screen's initial build reaches —
leaving any one unmocked risks the exact class of hang sub-project 2 hit
repeatedly (a real native-isolate Drift read inside `testWidgets`,
unreliable in this environment even when nothing awaits its result
directly):

```dart
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          subscriptionsProvider.overrideWith((ref) => Stream.value(const [])),
          transactionsStreamProvider.overrideWith((ref) => Stream.value(const [])),
          dismissedSubscriptionSuggestionsProvider.overrideWith((ref) => Future.value(const {})),
        ],
```

Run: `cd app && flutter test test/subscriptions_screen_test.dart -r expanded`
Expected: 1 test passes.

- [ ] **Step 11: Run `flutter analyze`**

Run: `cd app && flutter analyze`
Expected: only the pre-existing 11 info-level issues, nothing new.

- [ ] **Step 12: Commit**

```bash
cd app
git add lib/data/db.dart lib/features/subscriptions/subscription_suggestions.dart lib/features/subscriptions/subscriptions_screen.dart test/subscription_suggestions_test.dart test/dismissed_suggestions_test.dart test/subscriptions_screen_test.dart
git commit -m "feat: detect and surface suggested subscriptions from transaction history"
```

---

### Task 5: Notification integration

**Files:**
- Modify: `app/lib/core/notification_scheduler.dart`
- Modify: `app/lib/features/subscriptions/subscriptions_screen.dart`
- Test: `app/test/notification_scheduler_test.dart`

**Interfaces:**
- Consumes: `SubscriptionsDao.allForScheduling()`, `.rollForwardTo()` (Task 1).
- Produces: `int subscriptionNotificationId(int id)`,
  `NotificationScheduler.cancel(int id)` (thin passthrough used by the
  screen's remove handler).

- [ ] **Step 1: Write the failing scheduler tests**

Append to `app/test/notification_scheduler_test.dart`. No new imports are
needed — `SubscriptionsCompanion` comes through the file's existing
`import 'package:moneylock/data/db.dart';`, `subscriptionNotificationId`
through its existing `import 'package:moneylock/core/notification_scheduler.dart';`,
and none of these 4 tests set an optional/nullable field, so no `Value(...)`
wrapper is needed anywhere in them:

```dart
  test('a subscription 1 day out gets a reminder scheduled', () async {
    final db = _db();
    await db.subscriptionsDao.add(SubscriptionsCompanion.insert(
      name: 'Netflix',
      amount: 15.99,
      cycle: 'monthly',
      nextChargeDate: DateTime(2026, 8, 18),
      createdAt: DateTime(2026, 1, 1),
    ));
    final fake = _FakeNotifications();
    final scheduler = NotificationScheduler(db, fake, now: () => DateTime(2026, 8, 17, 7, 0));

    await scheduler.refresh();

    final rows = await db.subscriptionsDao.allForScheduling();
    final id = subscriptionNotificationId(rows.single.id);
    expect(fake.scheduled[id]?.$2, contains('Netflix'));
    await db.close();
  });

  test('a subscription 5 days out gets no reminder', () async {
    final db = _db();
    await db.subscriptionsDao.add(SubscriptionsCompanion.insert(
      name: 'Netflix',
      amount: 15.99,
      cycle: 'monthly',
      nextChargeDate: DateTime(2026, 8, 22),
      createdAt: DateTime(2026, 1, 1),
    ));
    final fake = _FakeNotifications();
    final scheduler = NotificationScheduler(db, fake, now: () => DateTime(2026, 8, 17, 7, 0));

    await scheduler.refresh();

    final rows = await db.subscriptionsDao.allForScheduling();
    final id = subscriptionNotificationId(rows.single.id);
    expect(fake.scheduled.containsKey(id), isFalse);
    await db.close();
  });

  test('a past-due monthly subscription rolls forward to next month', () async {
    final db = _db();
    final id = await db.subscriptionsDao.add(SubscriptionsCompanion.insert(
      name: 'Netflix',
      amount: 15.99,
      cycle: 'monthly',
      nextChargeDate: DateTime(2026, 7, 1),
      createdAt: DateTime(2026, 1, 1),
    ));
    final fake = _FakeNotifications();
    final scheduler = NotificationScheduler(db, fake, now: () => DateTime(2026, 8, 17, 7, 0));

    await scheduler.refresh();

    final rows = await db.subscriptionsDao.allForScheduling();
    expect(rows.single.nextChargeDate, DateTime(2026, 9, 1));
    expect(id, isNotNull);
    await db.close();
  });

  test('a past-due yearly subscription rolls forward by a year', () async {
    final db = _db();
    await db.subscriptionsDao.add(SubscriptionsCompanion.insert(
      name: 'iCloud+',
      amount: 99.0,
      cycle: 'yearly',
      nextChargeDate: DateTime(2025, 8, 1),
      createdAt: DateTime(2026, 1, 1),
    ));
    final fake = _FakeNotifications();
    final scheduler = NotificationScheduler(db, fake, now: () => DateTime(2026, 8, 17, 7, 0));

    await scheduler.refresh();

    final rows = await db.subscriptionsDao.allForScheduling();
    expect(rows.single.nextChargeDate, DateTime(2027, 8, 1));
    await db.close();
  });
```

The 4th test's expected date reflects that a subscription due `2025-08-01`
rolled forward one year lands on `2026-08-01`, which is itself still
on-or-before `now()` (`2026-08-17`) — the rollover loop must keep advancing
until the date is strictly after `now()`, landing on `2027-08-01` after two
iterations.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd app && flutter test test/notification_scheduler_test.dart -r expanded`
Expected: FAIL — `subscriptionNotificationId` is not defined.

- [ ] **Step 3: Extend `NotificationScheduler`**

In `app/lib/core/notification_scheduler.dart`:

1. Add near the top, alongside the other ID constants:

```dart
int subscriptionNotificationId(int subscriptionId) => 10000 + subscriptionId;
```

2. Add a thin passthrough method to the class (used by the screen's
   remove handler in Step 5 below):

```dart
  Future<void> cancel(int id) => notifications.cancel(id);
```

3. At the end of `refresh()`, after the existing
   `await notifications.scheduleAt(nextMorningReminderId, ...)` call, add:

```dart
    final subscriptions = await db.subscriptionsDao.allForScheduling();
    for (final subscription in subscriptions) {
      var nextCharge = subscription.nextChargeDate;
      while (nextCharge.isBefore(startOfToday)) {
        nextCharge = subscription.cycle == 'yearly'
            ? DateTime(nextCharge.year + 1, nextCharge.month, nextCharge.day)
            : DateTime(nextCharge.year, nextCharge.month + 1, nextCharge.day);
      }
      if (nextCharge != subscription.nextChargeDate) {
        await db.subscriptionsDao.rollForwardTo(subscription.id, nextCharge);
      }

      final id = subscriptionNotificationId(subscription.id);
      await notifications.cancel(id);
      final daysOut = DateTime(nextCharge.year, nextCharge.month, nextCharge.day)
          .difference(startOfToday)
          .inDays;
      final reminderTime = DateTime(today.year, today.month, today.day, 10);
      if (daysOut >= 1 && daysOut <= 2 && today.isBefore(reminderTime)) {
        await notifications.scheduleAt(
          id,
          reminderTime,
          '${subscription.name} renews soon',
          '${subscription.name} charges ${fmtCurrency(subscription.amount)} on ${fmtDate(nextCharge)}.',
        );
      }
    }
```

The rollover loop compares against `startOfToday` (already defined earlier
in `refresh()`, date-only) rather than `today` (which carries a
time-of-day) — otherwise a subscription charging *today* would look
"already past" the moment `now()` reports any time after midnight, and get
prematurely rolled forward a full cycle before the day's own charge ever
happens.

4. No new imports needed: `fmtCurrency` and `fmtDate` both live in
   `format.dart`, already imported at the top of this file (`import
   '../core/format.dart';`), and `Subscription`/`SubscriptionsDao` are
   used here only through inferred types flowing from
   `db.subscriptionsDao.allForScheduling()` — `db.dart` is already
   imported, and Dart doesn't require a direct import for a type you never
   write out as an explicit annotation.

- [ ] **Step 4: Run the scheduler tests**

Run: `cd app && flutter test test/notification_scheduler_test.dart -r expanded`
Expected: all tests pass (the original 8 plus the 4 new ones).

- [ ] **Step 5: Wire notification cancellation into the screen's remove handler**

In `app/lib/features/subscriptions/subscriptions_screen.dart`,
`SubscriptionsScreen._confirmRemove`, change:

```dart
    if (confirmed != true) return false;
    await ref.read(appDatabaseProvider).subscriptionsDao.remove(subscription.id);
    return true;
```

to:

```dart
    if (confirmed != true) return false;
    await ref.read(notificationSchedulerProvider).cancel(subscriptionNotificationId(subscription.id));
    await ref.read(appDatabaseProvider).subscriptionsDao.remove(subscription.id);
    return true;
```

And add `import '../../core/notification_scheduler.dart';` at the top of
the file (for `subscriptionNotificationId`).

Also, in `_AddSubscriptionSheetState._save`, after the successful insert
and before `Navigator.of(context).pop(true)`, add a call so a newly-added
subscription's reminder gets scheduled without waiting for the next
app-level `refresh()` opportunity:

```dart
    await ref.read(notificationSchedulerProvider).refresh();
    if (mounted) Navigator.of(context).pop(true);
```

(replacing the bare `if (mounted) Navigator.of(context).pop(true);` line).

- [ ] **Step 6: Run the full test suite**

Run: `cd app && flutter test` (the known-flaky `settings_notifications_test.dart`
may hang regardless of this branch's changes — if it does, set it aside per
the established workaround: `mv test/settings_notifications_test.dart /tmp/
&& flutter test && mv /tmp/settings_notifications_test.dart test/`)
Expected: all tests pass.

- [ ] **Step 7: Run `flutter analyze`**

Run: `cd app && flutter analyze`
Expected: only the pre-existing 11 info-level issues, nothing new.

- [ ] **Step 8: Commit**

```bash
cd app
git add lib/core/notification_scheduler.dart lib/features/subscriptions/subscriptions_screen.dart test/notification_scheduler_test.dart
git commit -m "feat: schedule renewal reminders for tracked subscriptions"
```
