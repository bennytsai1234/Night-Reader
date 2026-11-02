import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/sync/google_drive_auth.dart';
import 'package:night_reader/core/sync/sync_kind.dart';
import 'package:night_reader/core/sync/sync_records.dart';
import 'package:night_reader/core/sync/sync_base_storage.dart';
import 'package:night_reader/core/sync/sync_service.dart';
import 'package:night_reader/core/sync/sync_settings.dart';
import 'package:night_reader/core/sync/sync_store.dart';
import 'package:night_reader/features/settings/sync_space_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Store implements SyncStore {
  _Store({this.beforeRead, this.readError});

  final Future<void>? beforeRead;
  final String? readError;
  int reads = 0;

  @override
  Future<void> check() async {}

  @override
  Future<SyncFile?> read(String name) async {
    reads++;
    if (beforeRead != null) await beforeRead;
    if (readError != null) throw SyncStoreException(readError!);
    return null;
  }

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

class _SourceKind extends SyncKind {
  @override
  String get name => 'sources';

  @override
  Future<Map<String, SyncRecord>> local() async => {};

  @override
  Future<Map<String, SyncRecord>> apply(Map<String, SyncRecord> remote) async {
    return {};
  }
}

class _Auth implements GoogleDriveAuth {
  _Auth({this.fail, this.signInGate});

  final String? fail;
  final Future<void>? signInGate;
  bool signedOut = false;
  int signIns = 0;

  /// 下一次登入選的帳號。
  String account = 'reader@gmail.com';

  @override
  Future<String> signIn() async {
    if (fail != null) throw SyncStoreException(fail!);
    signIns++;
    if (signInGate != null) await signInGate;
    return account;
  }

  @override
  Future<String> token(String account) async => 'token';

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

  Future<SyncService> pump(
    WidgetTester tester,
    _Auth auth, {
    _MemoryBases? bases,
    _Store? store,
    List<SyncKind> Function(SyncService)? kinds,
  }) async {
    final sync = SyncService(
      storeFactory: (space, _, _) =>
          space == SyncSpace.none ? null : store ?? _Store(),
      bases: bases ?? _MemoryBases(),
      googleAuth: auth,
      kinds: kinds ?? (_) => const [],
    );
    await tester.pumpWidget(MaterialApp(home: SyncSpacePage(sync: sync)));
    await tester.pumpAndSettle();
    return sync;
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

  testWidgets('Google can be signed in again after it is picked: the same '
      'account keeps the last sync, another account starts over', (
    tester,
  ) async {
    final auth = _Auth();
    final bases = _MemoryBases();
    await pump(tester, auth, bases: bases);
    await tester.tap(find.text('Google 雲端硬碟'));
    await settle(tester);
    bases.files['progress'] = {'kept': true};

    await tester.tap(find.text('Google 雲端硬碟'));
    await settle(tester);
    expect(auth.signIns, 2);
    expect(bases.files['progress'], {'kept': true});

    auth.account = 'other@gmail.com';
    await tester.tap(find.text('Google 雲端硬碟'));
    await settle(tester);
    expect(find.text('other@gmail.com'), findsOneWidget);
    expect(bases.files['progress'], isNull);
  });

  testWidgets('Google selection updates before the initial sync finishes', (
    tester,
  ) async {
    final gate = Completer<void>();
    final sync = await pump(
      tester,
      _Auth(),
      store: _Store(beforeRead: gate.future),
      kinds: (_) => [_SourceKind()],
    );

    await tester.tap(find.text('Google 雲端硬碟'));
    await settle(tester);

    expect(find.text('reader@gmail.com'), findsOneWidget);
    expect(find.text('登入中…'), findsNothing);
    expect(find.text('同步中（1/1）：書源'), findsOneWidget);
    expect(sync.status.value.running, isTrue);

    gate.complete();
    await settle(tester);

    expect(sync.status.value.running, isFalse);
    expect(find.textContaining('上次同步：'), findsOneWidget);
  });

  testWidgets('Google sync error replaces the progress on the same page', (
    tester,
  ) async {
    final gate = Completer<void>();
    final sync = await pump(
      tester,
      _Auth(),
      store: _Store(beforeRead: gate.future, readError: '書源暫時不可用'),
      kinds: (_) => [_SourceKind()],
    );

    await tester.tap(find.text('Google 雲端硬碟'));
    await settle(tester);
    expect(find.text('同步中（1/1）：書源'), findsOneWidget);

    gate.complete();
    await settle(tester);

    expect(sync.status.value.running, isFalse);
    expect(find.text('上次同步失敗：書源暫時不可用'), findsOneWidget);
  });

  testWidgets('Google authorization does not schedule lifecycle sync passes', (
    tester,
  ) async {
    // 重新授權既有的 Google 帳號：跳出系統畫面會讓 App 暫停、恢復。
    await SyncSettings().useGoogleDrive('reader@gmail.com');
    final gate = Completer<void>();
    final auth = _Auth(signInGate: gate.future);
    final store = _Store();
    final sync = await pump(
      tester,
      auth,
      store: store,
      kinds: (_) => [_SourceKind()],
    );

    await tester.tap(find.text('Google 雲端硬碟'));
    await tester.pump();
    sync.syncBeforeBackground();
    sync.syncAfterResume();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));

    expect(store.reads, 0);
    expect(sync.progressReady, isNull);
    gate.complete();
    await settle(tester);

    expect(auth.signIns, 1);
    expect(store.reads, 1);
    expect(find.textContaining('上次同步：'), findsOneWidget);
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
