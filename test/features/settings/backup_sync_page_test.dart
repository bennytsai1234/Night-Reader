import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/sync_store_blobs.dart';

import 'package:night_reader/core/sync/sync_base_storage.dart';
import 'package:night_reader/core/sync/sync_kind.dart';
import 'package:night_reader/core/sync/sync_records.dart';
import 'package:night_reader/core/sync/sync_merge.dart';
import 'package:night_reader/core/sync/sync_service.dart';
import 'package:night_reader/core/sync/sync_store.dart';
import 'package:night_reader/features/settings/backup_sync_page.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 讀到 [gated] 那份檔時停住，等 [gate] 放行（模擬網路慢）。
class _Store with SyncStoreBlobs implements SyncStore {
  _Store(this.gated);

  final String gated;
  final Completer<void> gate = Completer<void>();
  final List<String> reads = [];

  /// 讀這幾份檔時雲端拒絕（只有這一份失敗，其他照常）。
  final Set<String> refused = {};

  @override
  Future<void> check() async {}

  @override
  Future<SyncFile?> read(String name) async {
    reads.add(name);
    if (name == gated) await gate.future;
    if (refused.contains(name)) {
      throw const SyncStoreException.file('拒絕存取');
    }
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

  /// 設了就讓下一次讀紀錄停在這裡（每一輪開始都讀，用來卡住日常的進度同步）。
  Completer<void>? gate;

  /// 讀不到同步空間的歸屬（每一輪開始時讀），那一輪失敗。
  bool failOwner = false;

  @override
  Future<Map<String, Object?>> readJson(String name) async {
    final waiting = gate;
    gate = null;
    if (waiting != null) await waiting.future;
    if (failOwner && name == 'owner') throw StateError('讀不到紀錄');
    return Map.of(files[name] ?? const {});
  }

  @override
  Future<void> writeJson(String name, Map<String, Object?> json) async =>
      files[name] = Map.of(json);

  @override
  Future<void> clear() async => files.clear();
}

void main() {
  late _Store store;
  late _MemoryBases bases;
  final previous = SyncService.instance;
  tearDown(() => SyncService.instance = previous);

  Future<void> pump(
    WidgetTester tester, {
    String gated = 'sources.json',
  }) async {
    SharedPreferences.setMockInitialValues({
      'sync.space': 'webdav',
      'sync.webdav.url': 'https://dav.example/',
    });
    store = _Store(gated);
    SyncService.instance = SyncService(
      runner: runSyncWorkInline,
      storeFactory: (_, _, _) => store,
      bases: bases = _MemoryBases(),
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

  testWidgets('全面同步做完時進度框上面疊著別的畫面：只收自己的進度框', (tester) async {
    await pump(tester);

    await tester.tap(find.text('立即全面同步'));
    await settle(tester);
    // 例如途中點了加入書架的連結，開了書籍詳情。
    unawaited(
      Navigator.of(
        tester.element(find.byType(BackupSyncPage)),
        rootNavigator: true,
      ).push(MaterialPageRoute<void>(builder: (_) => const Text('上面的頁'))),
    );
    await tester.pumpAndSettle();

    store.gate.complete();
    await settle(tester);
    expect(find.text('上面的頁'), findsOneWidget);
    expect(find.text('全面同步中', skipOffstage: false), findsNothing);
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

  testWidgets('cancelling a full sync still waiting behind the daily sync '
      'closes at once; the full round never runs', (tester) async {
    await pump(tester);
    // 日常的進度同步卡住時按「立即全面同步」，全面同步排在它後面。
    final daily = Completer<void>();
    bases.gate = daily;
    SyncService.instance.syncProgress();
    await tester.tap(find.text('立即全面同步'));
    // 日常那一輪還沒寫出進度，進度條來回跑，等不到畫面靜止。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('全面同步中'), findsOneWidget);

    // 全面同步還沒開始，取消了就沒有要等的：進度框馬上收，日常那一輪照跑。
    await tester.tap(find.text('取消'));
    await settle(tester);
    expect(find.text('全面同步中'), findsNothing);
    expect(find.text('已停下，同步好的資料留著'), findsOneWidget);

    daily.complete();
    await settle(tester);
    expect(store.reads, isEmpty, reason: '排著的全面同步沒有跑');
  });

  group(
    'the line after the full sync closes tells how that full round ended',
    () {
      testWidgets('cancelling while the last kind syncs: everything was done', (
        tester,
      ) async {
        await pump(tester, gated: 'settings.json');

        await tester.tap(find.text('立即全面同步'));
        await settle(tester);
        await tester.tap(find.text('取消'));
        await tester.pump();
        store.gate.complete();
        await settle(tester);

        expect(find.textContaining('上次全面同步：'), findsOneWidget);
        expect(find.text('全面同步完成'), findsOneWidget);
      });

      testWidgets('a refused file fails the full round even when a progress '
          'round asked for during it succeeds', (tester) async {
        await pump(tester);
        store.refused.add('settings.json');

        await tester.tap(find.text('立即全面同步'));
        await settle(tester);
        SyncService.instance.syncProgress();
        store.gate.complete();
        await settle(tester);

        expect(find.text('全面同步失敗：拒絕存取'), findsOneWidget);
      });

      testWidgets('a progress round asked for during it that fails does not '
          'fail the full round', (tester) async {
        await pump(tester);

        await tester.tap(find.text('立即全面同步'));
        await settle(tester);
        SyncService.instance.syncProgress();
        // 全面那一輪已經讀過同步空間的歸屬；下一輪開始時讀不到。
        bases.failOwner = true;
        store.gate.complete();
        await settle(tester);

        expect(find.text('全面同步完成'), findsOneWidget);
      });

      testWidgets(
        'an older failure is not reported for a cancelled full sync',
        (tester) async {
          await pump(tester);
          bases.failOwner = true;
          SyncService.instance.syncProgress();
          await settle(tester);
          bases.failOwner = false;
          expect(SyncService.instance.status.value.error, isNotNull);

          await tester.tap(find.text('立即全面同步'));
          await settle(tester);
          await tester.tap(find.text('取消'));
          await tester.pump();
          store.gate.complete();
          await settle(tester);

          expect(find.text('已停下，同步好的資料留著'), findsOneWidget);
        },
      );
    },
  );
}
