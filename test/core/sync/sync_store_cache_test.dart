import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/sync/sync_base_storage.dart';
import 'package:night_reader/core/sync/sync_service.dart';
import 'package:night_reader/core/sync/sync_settings.dart';
import 'package:night_reader/core/sync/sync_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 只拿來數建了幾個；沒有種類要同步時不會用到它的方法。
class _Store extends Fake implements SyncStore {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory baseDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'sync.space': 'webdav',
      'sync.webdav.url': 'https://one.example/dav',
      'sync.webdav.user': 'reader',
      'sync.webdav.password': 'secret',
    });
    baseDir = await Directory.systemTemp.createTemp('nr-sync-store-cache');
    addTearDown(() => baseDir.delete(recursive: true));
  });

  test('the same sync space reuses one store; changing it or turning sync '
      'off builds a new one', () async {
    final prefs = await SharedPreferences.getInstance();
    final created = <SyncStore>[];
    final service = SyncService(
      settings: SyncSettings(prefs),
      bases: SyncBaseStorage(directory: () async => baseDir),
      storeFactory: (space, webDav, googleAccount) {
        final store = _Store();
        created.add(store);
        return store;
      },
      kinds: (_) => const [],
    );

    await service.syncAll();
    await service.syncAll();
    expect(created, hasLength(1), reason: '同一個空間連續兩次用同一個 store');

    await prefs.setString('sync.webdav.url', 'https://two.example/dav');
    await service.syncAll();
    expect(created, hasLength(2), reason: '換了同步空間就換一個');

    await prefs.setString('sync.webdav.password', 'new-secret');
    await service.syncAll();
    expect(created, hasLength(3), reason: '帳號密碼變了也要重新連線');

    await prefs.setString('sync.space', 'none');
    await service.syncAll();
    expect(created, hasLength(4), reason: '停用後不再用上一個空間的 store');
    await prefs.setString('sync.space', 'webdav');
    await service.syncAll();
    expect(created, hasLength(5), reason: '停用後再打開，重新建一個');
  });
}
