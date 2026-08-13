import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this.tempDir);

  final String tempDir;

  @override
  Future<String?> getTemporaryPath() async => tempDir;

  @override
  Future<String?> getApplicationDocumentsPath() async => tempDir;

  @override
  Future<String?> getApplicationSupportPath() async => tempDir;
}

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();

  final tempDir = Directory.systemTemp.createTempSync('moneylock_test_');
  PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);

  await testMain();
}
