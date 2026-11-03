import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/sync/sync_base_storage.dart';
import 'package:night_reader/core/sync/sync_kind.dart';
import 'package:night_reader/core/sync/sync_records.dart';
import 'package:night_reader/core/sync/sync_service.dart';
import 'package:night_reader/core/sync/sync_store.dart';
import 'package:night_reader/features/settings/backup_sync_page.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 讀到 [gated] 那份檔時停住，等 [gate] 放行（模擬網路慢）。
class _Store implements SyncStore {
  _Store(this.gated);

  final String gated;
  final Completer<void> gate = Completer<void>();
  final List<String> reads = [];

  @override
  Future<void> check() async {}

  @override
  Future<SyncFile?> read(String name) async {
    reads.add(name);
    if (name == gated) await gate.future;
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

class _Kind extends SyncKind {
  _Kind(this.name);

  @override
  final String name;

  @override
  Future<Map<String, SyncRecord>> local() async => {};

  @override
  Future<Map<String, SyncRecord>> apply(Map<String, SyncRecord> remote) async =>
      {};
}

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
  late _Store store;
  final previous = SyncService.instance;
  tearDown(() => SyncService.instance = previous);

  Future<void> pump(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      'sync.space': 'webdav',
      'sync.webdav.url': 'https://dav.example/',
    });
    store = _Store('sources.json');
    SyncService.instance = SyncService(
      storeFactory: (_, _, _) => store,
      bases: _MemoryBases(),
      kinds: (_) => [_Kind('sources'), _Kind('settings')],
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(AppStyle.paper, Brightness.light),
        home: const BackupSyncPage(),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
  }

  testWidgets('a full sync covers the app until it is done; back does not '
      'close it', (tester) async {
    await pump(tester);

    await tester.tap(find.text('立即全面同步'));
    await settle(tester);
    expect(find.text('全面同步中'), findsOneWidget);
    expect(find.text('書源（1/2）'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('全面同步中'), findsOneWidget, reason: '按返回關不掉');

    store.gate.complete();
    await settle(tester);
    expect(find.text('全面同步中'), findsNothing);
    expect(find.text('全面同步完成'), findsOneWidget);
    expect(store.reads, ['sources.json', 'settings.json']);
    expect(find.textContaining('上次全面同步：'), findsOneWidget);
  });

  testWidgets('cancelling stops before the next kind', (tester) async {
    await pump(tester);

    await tester.tap(find.text('立即全面同步'));
    await settle(tester);
    await tester.tap(find.text('取消'));
    await tester.pump();
    expect(find.text('正在停下…'), findsOneWidget);

    store.gate.complete();
    await settle(tester);
    expect(find.text('全面同步中'), findsNothing);
    expect(find.text('已停下，同步好的資料留著'), findsOneWidget);
    expect(store.reads, ['sources.json']);
  });
}
