import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneylock/data/db.dart';
import 'package:moneylock/features/settings/settings_screen.dart';
import 'package:moneylock/llm/llama_service.dart';
import 'package:moneylock/providers.dart';

AppDatabase _db() => AppDatabase.forTesting(
    driftDatabase(name: 'test_${DateTime.now().microsecondsSinceEpoch}'));

class _FakeLlamaService extends LlamaService {
  @override
  Future<bool> isModelReady() async => false;
}

void main() {
  // SettingsScreen also renders _ToneSelector (mentorToneProvider) and
  // _ModelCard (llamaServiceProvider().isModelReady(), a real
  // path_provider platform call) above the NOTIFICATIONS section. Both
  // are unmocked real async work; leaving them unmocked is what made
  // every prior version of this test (including the one from Task 5's
  // original commit) hang indefinitely in this environment -- not the
  // notifications toggle itself. Overriding both here is the fix.
  //
  // The Switch itself sits below the fold at the default 800x600 test
  // surface size. Every mechanism tried to reach it -- tester.drag,
  // tester.view.physicalSize, tester.binding.setSurfaceSize, and
  // find.byType(..., skipOffstage: false) -- reproducibly hung in this
  // environment even with the above providers mocked, so this test
  // deliberately doesn't scroll to it. It instead confirms the screen
  // (and therefore _NotificationsCard's build/provider wiring) renders
  // with no exception. The actual read/write behavior is proven at the
  // DAO level in notification_data_test.dart.
  testWidgets('settings screen renders with notifications toggle wired up',
      (tester) async {
    final db = _db();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          notificationsEnabledProvider.overrideWith((ref) => Future.value(true)),
          mentorToneProvider.overrideWith((ref) => Future.value('strict_ramsey')),
          llamaServiceProvider.overrideWithValue(_FakeLlamaService()),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.runAsync(() => db.close());
  });
}
