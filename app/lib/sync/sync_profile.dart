import '../data/db.dart';

class ProfileSyncResult {
  const ProfileSyncResult({required this.profile, required this.conflicts});

  final SyncProfile profile;
  final int conflicts;
}

/// Non-transactional user data that should follow the user across devices.
class SyncProfile {
  const SyncProfile({
    required this.settings,
    required this.budgets,
    required this.categories,
    required this.subscriptions,
  });

  final Map<String, String> settings;
  final List<Map<String, dynamic>> budgets;
  final List<Map<String, dynamic>> categories;
  final List<Map<String, dynamic>> subscriptions;

  factory SyncProfile.fromJson(Map<String, dynamic> json) => SyncProfile(
    settings: {
      for (final entry
          in (json['settings'] as Map<String, dynamic>? ?? {}).entries)
        entry.key: entry.value.toString(),
    },
    budgets: _maps(json['budgets']),
    categories: _maps(json['categories']),
    subscriptions: _maps(json['subscriptions']),
  );

  Map<String, dynamic> toJson() => {
    'settings': settings,
    'budgets': budgets,
    'categories': categories,
    'subscriptions': subscriptions,
  };

  static Future<SyncProfile> fromDatabase(AppDatabase db) async {
    final (settings, budgets, categories, subscriptions) = await (
      db.settingsDao.syncValues(),
      db.budgetsDao.all(),
      db.categoriesDao.allForSync(),
      db.subscriptionsDao.allForSync(),
    ).wait;

    return SyncProfile(
      settings: settings,
      budgets: [
        for (final budget in budgets)
          {
            'category': budget.category,
            'limit': budget.monthlyLimit,
            'period': budget.period,
            'cycle': budget.cycle,
            'cycle_days': budget.cycleDays,
            'currency': budget.currency,
            'enabled': budget.enabled,
          },
      ],
      categories: [
        for (final category in categories)
          {
            'name': category.name,
            'is_active': category.isActive,
            'is_default': category.isDefault,
          },
      ],
      subscriptions: [
        for (final subscription in subscriptions)
          {
            'name': subscription.name,
            'brand_key': subscription.brandKey,
            'amount': subscription.amount,
            'currency': subscription.currency,
            'cycle': subscription.cycle,
            'next_charge_date': subscription.nextChargeDate
                .toUtc()
                .toIso8601String(),
            'source': subscription.source,
            'created_at': subscription.createdAt.toUtc().toIso8601String(),
            'is_active': subscription.isActive,
          },
      ],
    );
  }

  ProfileSyncResult mergeServer(SyncProfile? server) {
    if (server == null) return ProfileSyncResult(profile: this, conflicts: 0);

    var conflicts = 0;
    final mergedSettings = Map<String, String>.from(server.settings);
    for (final entry in settings.entries) {
      final remote = mergedSettings[entry.key];
      if (remote == null) {
        mergedSettings[entry.key] = entry.value;
      } else if (remote != entry.value) {
        conflicts++;
      }
    }

    final mergedBudgets = _mergeItems(
      server.budgets,
      budgets,
      (item) => '${item['period']}\u0000${item['category']}',
      onConflict: () => conflicts++,
    );
    final mergedCategories = _mergeItems(
      server.categories,
      categories,
      (item) => item['name'].toString(),
      onConflict: () => conflicts++,
    );
    final mergedSubscriptions = _mergeItems(
      server.subscriptions,
      subscriptions,
      (item) =>
          '${item['name'].toString().toLowerCase()}\u0000${item['cycle']}',
      onConflict: () => conflicts++,
    );

    return ProfileSyncResult(
      profile: SyncProfile(
        settings: mergedSettings,
        budgets: mergedBudgets,
        categories: mergedCategories,
        subscriptions: mergedSubscriptions,
      ),
      conflicts: conflicts,
    );
  }

  Future<void> applyTo(AppDatabase db) => db.transaction(() async {
    await db.settingsDao.applySyncValues(settings);

    for (final category in categories) {
      final name = category['name'] as String?;
      if (name == null || name.isEmpty) continue;
      await db.categoriesDao.upsertForSync(
        name: name,
        isActive: category['is_active'] as bool? ?? true,
        isDefault: category['is_default'] as bool? ?? false,
      );
    }

    for (final budget in budgets) {
      final category = budget['category'] as String?;
      final period = budget['period'] as String?;
      final limit = (budget['limit'] as num?)?.toDouble();
      if (category == null || period == null || limit == null || limit < 0) {
        continue;
      }
      await db.budgetsDao.upsert(
        category,
        limit,
        period,
        cycle: budget['cycle'] as String? ?? 'monthly',
        cycleDays: (budget['cycle_days'] as num?)?.toInt() ?? 30,
        currency: budget['currency'] as String? ?? 'USD',
      );
    }

    for (final subscription in subscriptions) {
      final name = subscription['name'] as String?;
      final amount = (subscription['amount'] as num?)?.toDouble();
      final next = DateTime.tryParse(
        subscription['next_charge_date'] as String? ?? '',
      );
      final created = DateTime.tryParse(
        subscription['created_at'] as String? ?? '',
      );
      if (name == null ||
          name.isEmpty ||
          amount == null ||
          amount <= 0 ||
          next == null ||
          created == null) {
        continue;
      }
      await db.subscriptionsDao.upsertForSync(
        name: name,
        brandKey: subscription['brand_key'] as String?,
        amount: amount,
        currency: subscription['currency'] as String? ?? 'USD',
        cycle: subscription['cycle'] as String? ?? 'monthly',
        nextChargeDate: next,
        source: subscription['source'] as String? ?? 'manual',
        createdAt: created,
        isActive: subscription['is_active'] as bool? ?? true,
      );
    }
  });
}

List<Map<String, dynamic>> _maps(Object? value) =>
    (value as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(Map<String, dynamic>.from)
        .toList();

List<Map<String, dynamic>> _mergeItems(
  List<Map<String, dynamic>> remote,
  List<Map<String, dynamic>> local,
  String Function(Map<String, dynamic>) key, {
  required void Function() onConflict,
}) {
  final merged = {for (final item in remote) key(item): item};
  for (final item in local) {
    final itemKey = key(item);
    final existing = merged[itemKey];
    if (existing == null) {
      merged[itemKey] = item;
    } else if (existing.toString() != item.toString()) {
      onConflict();
    }
  }
  return merged.values.toList();
}
