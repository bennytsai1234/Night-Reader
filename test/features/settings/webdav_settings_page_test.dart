import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/sync/sync_base_storage.dart';
import 'package:night_reader/core/sync/sync_kind.dart';
import 'package:night_reader/core/sync/sync_records.dart';
import 'package:night_reader/core/sync/sync_service.dart';
import 'package:night_reader/core/sync/sync_settings.dart';
import 'package:night_reader/core/sync/sync_store.dart';
import 'package:night_reader/features/settings/webdav_settings_page.dart';
import 'package:night_reader/features/settings/sync_space_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Store implements SyncStore {
  _Store({this.fail, this.beforeRead, this.readError});

  final String? fail;
  final Future<void>? beforeRead;
  final String? readError;

  @override
  Future<void> check() async {
    if (fail != null) throw SyncStoreException(fail!);
  }

  @override
  Future<SyncFile?> read(String name) async {
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

void main() {
  late Directory bases;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    bases = Directory.systemTemp.createTempSync('nr-webdav-page');
    addTearDown(() => bases.delete(recursive: true));
  });

  Future<SyncService> pump(
    WidgetTester tester,
    _Store store, {
    List<SyncKind> Function(SyncService)? kinds,
    bool inSpace = false,
  }) async {
    final sync = SyncService(
      storeFactory: (space, _, _) => space == SyncSpace.none ? null : store,
      bases: SyncBaseStorage(directory: () async => bases),
      kinds: kinds,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: inSpace
            ? SyncSpacePage(sync: sync)
            : WebDavSettingsPage(sync: sync),
      ),
    );
    await tester.pumpAndSettle();
    return sync;
  }

  Future<void> waitForStatus(
    WidgetTester tester,
    SyncService sync,
    bool Function(SyncStatus) matches,
  ) async {
    final ready = Completer<void>();
    void onChange() {
      if (matches(sync.status.value) && !ready.isCompleted) ready.complete();
    }

    sync.status.addListener(onChange);
    try {
      onChange();
      await tester.runAsync(
        () => ready.future.timeout(const Duration(seconds: 5)),
      );
    } finally {
      sync.status.removeListener(onChange);
    }
    await tester.pumpAndSettle();
  }

  testWidgets('a wrong password is shown and nothing is saved', (tester) async {
    await pump(tester, _Store(fail: '帳號或密碼不對'));
    await tester.enterText(find.byType(TextField).at(0), 'https://dav.example');
    await tester.tap(find.text('連線並開始同步'));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();

    expect(find.text('帳號或密碼不對'), findsOneWidget);
    expect(await SyncSettings().space(), SyncSpace.none);
  });

  testWidgets('WebDAV returns to sync space before the data sync completes', (
    tester,
  ) async {
    final gate = Completer<void>();
    final sync = await pump(
      tester,
      _Store(beforeRead: gate.future),
      kinds: (_) => [_SourceKind()],
      inSpace: true,
    );

    await tester.tap(find.text('WebDAV'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'https://dav.example');
    await tester.tap(find.text('連線並開始同步'));
    await waitForStatus(
      tester,
      sync,
      (status) => status.progress != null || status.error != null,
    );

    expect(sync.status.value.error, isNull);
    expect(await SyncSettings().space(), SyncSpace.webdav);
    expect(sync.status.value.running, isTrue);
    expect(find.text('同步中（1/1）：書源'), findsOneWidget);

    gate.complete();
    await waitForStatus(
      tester,
      sync,
      (status) => !status.running && status.lastSyncAt != null,
    );
    expect(find.textContaining('上次同步：'), findsOneWidget);
  });

  testWidgets(
    'WebDAV error appears on the sync space page without reentering',
    (tester) async {
      final gate = Completer<void>();
      final sync = await pump(
        tester,
        _Store(beforeRead: gate.future, readError: 'WebDAV 讀取失敗'),
        kinds: (_) => [_SourceKind()],
        inSpace: true,
      );

      await tester.tap(find.text('WebDAV'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField).at(0),
        'https://dav.example',
      );
      await tester.tap(find.text('連線並開始同步'));
      await waitForStatus(
        tester,
        sync,
        (status) => status.progress != null || status.error != null,
      );
      expect(sync.status.value.error, isNull);
      expect(sync.status.value.running, isTrue);

      gate.complete();
      await waitForStatus(
        tester,
        sync,
        (status) => !status.running && status.error != null,
      );
      expect(find.text('上次同步失敗：WebDAV 讀取失敗'), findsOneWidget);
    },
  );

  testWidgets('an empty address asks for one first', (tester) async {
    await pump(tester, _Store());
    await tester.tap(find.text('連線並開始同步'));
    await tester.pumpAndSettle();
    expect(find.text('先填 WebDAV 的網址'), findsOneWidget);
  });
}
