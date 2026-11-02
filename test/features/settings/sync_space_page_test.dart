import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/sync/google_drive_auth.dart';
import 'package:night_reader/core/sync/sync_base_storage.dart';
import 'package:night_reader/core/sync/sync_service.dart';
import 'package:night_reader/core/sync/sync_settings.dart';
import 'package:night_reader/core/sync/sync_store.dart';
import 'package:night_reader/features/settings/sync_space_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Store implements SyncStore {
  @override
  Future<void> check() async {}

  @override
  Future<SyncFile?> read(String name) async => null;

  @override
  Future<String?> version(String name) async => null;

  @override
  Future<void> write(
    String name,
    String content, {
    String? ifVersion,
    bool ifAbsent = false,
  }) async {}
}

class _Auth implements GoogleDriveAuth {
  _Auth({this.fail});

  final String? fail;
  bool signedOut = false;

  @override
  Future<String> signIn() async {
    if (fail != null) throw SyncStoreException(fail!);
    return 'reader@gmail.com';
  }

  @override
  Future<String> token() async => 'token';

  @override
  Future<void> forget(String token) async {}

  @override
  Future<void> signOut() async => signedOut = true;
}

/// 上次同步的紀錄放在記憶體，不碰檔案。
class _MemoryBases extends SyncBaseStorage {
  final Map<String, Map<String, Object?>> files = {};

  @override
  Future<Map<String, Object?>> readJson(String name) async =>
      Map.of(files[name] ?? const {});

  @override
  Future<void> writeJson(String name, Map<String, Object?> json) async =>
      files[name] = Map.of(json);

  @override
  Future<void> clear() async => files.clear();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pump(WidgetTester tester, _Auth auth) async {
    final sync = SyncService(
      storeFactory: (space, _) => space == SyncSpace.none ? null : _Store(),
      bases: _MemoryBases(),
      googleAuth: auth,
      kinds: (_) => const [],
    );
    await tester.pumpWidget(MaterialApp(home: SyncSpacePage(sync: sync)));
    await tester.pumpAndSettle();
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
  }

  testWidgets('signing in to Google picks Google Drive and shows the account; '
      'turning sync off signs out', (tester) async {
    final auth = _Auth();
    await pump(tester, auth);
    expect(find.text('停用同步'), findsNothing);

    await tester.tap(find.text('Google 雲端硬碟'));
    await settle(tester);

    expect(find.text('登入中…'), findsNothing);
    expect(await SyncSettings().space(), SyncSpace.googleDrive);
    expect(find.text('reader@gmail.com'), findsOneWidget);

    await tester.tap(find.text('停用同步'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('停用'));
    await settle(tester);

    expect(await SyncSettings().space(), SyncSpace.none);
    expect(auth.signedOut, isTrue);
    expect(find.text('reader@gmail.com'), findsNothing);
  });

  testWidgets('a cancelled Google sign-in changes nothing', (tester) async {
    await pump(tester, _Auth(fail: '沒有登入 Google 帳號'));
    await tester.tap(find.text('Google 雲端硬碟'));
    await settle(tester);

    expect(find.text('沒有登入 Google 帳號'), findsOneWidget);
    expect(await SyncSettings().space(), SyncSpace.none);
  });

  testWidgets('WebDAV opens its own page', (tester) async {
    await pump(tester, _Auth());
    await tester.tap(find.text('WebDAV'));
    await tester.pumpAndSettle();
    expect(find.text('網址'), findsOneWidget);
  });
}
