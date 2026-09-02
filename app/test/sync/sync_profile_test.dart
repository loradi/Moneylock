import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart';
import 'package:moneylock/data/db.dart';
import 'package:moneylock/sync/sync_profile.dart';

import '../helpers/test_database.dart';

void main() {
  test('profile includes and restores planning data', () async {
    final source = createTestDatabase();
    await source.settingsDao.setPlanCycle('weekly');
    await source.settingsDao.setPlanCurrency('2026-W36', 'USD');
    await source.budgetsDao.upsert(
      'Groceries',
      125,
      '2026-W36',
      cycle: 'weekly',
      cycleDays: 7,
      currency: 'USD',
    );
    await source.categoriesDao.add('Pets');
    await source.subscriptionsDao.add(
      SubscriptionsCompanion.insert(
        name: 'Music',
        amount: 12.99,
        currency: const Value('USD'),
        cycle: 'monthly',
        nextChargeDate: DateTime.utc(2026, 9, 15),
        createdAt: DateTime.utc(2026, 9, 1),
      ),
    );

    final profile = await SyncProfile.fromDatabase(source);
    expect(profile.settings['plan_cycle'], 'weekly');
    expect(profile.budgets, contains(containsPair('category', 'Groceries')));
    expect(profile.categories, contains(containsPair('name', 'Pets')));
    expect(profile.subscriptions, contains(containsPair('name', 'Music')));

    final target = createTestDatabase();
    await profile.applyTo(target);
    expect(await target.settingsDao.planCycle(), 'weekly');
    expect(
      await target.budgetsDao.forPeriod('2026-W36'),
      contains(predicate<Budget>((budget) => budget.category == 'Groceries')),
    );
    expect(
      await target.categoriesDao.allForSync(),
      contains(predicate<Category>((category) => category.name == 'Pets')),
    );
    expect(
      await target.subscriptionsDao.allForSync(),
      contains(
        predicate<Subscription>((subscription) => subscription.name == 'Music'),
      ),
    );

    await source.close();
    await target.close();
  });

  test('server profile remains authoritative on a conflicting budget', () {
    const server = SyncProfile(
      settings: {'plan_cycle': 'monthly'},
      budgets: [
        {'category': 'Groceries', 'period': '2026-09', 'limit': 400},
      ],
      categories: [],
      subscriptions: [],
    );
    const local = SyncProfile(
      settings: {'plan_cycle': 'weekly'},
      budgets: [
        {'category': 'Groceries', 'period': '2026-09', 'limit': 250},
      ],
      categories: [],
      subscriptions: [],
    );

    final result = local.mergeServer(server);

    expect(result.conflicts, 2);
    expect(result.profile.settings['plan_cycle'], 'monthly');
    expect(result.profile.budgets.single['limit'], 400);
  });
}
