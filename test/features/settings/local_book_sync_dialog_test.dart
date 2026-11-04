import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/sync/local_book_sync.dart';
import 'package:night_reader/core/sync/sync_base_storage.dart';
import 'package:night_reader/core/sync/sync_merge.dart';
import 'package:night_reader/core/sync/sync_records.dart';
import 'package:night_reader/core/sync/sync_service.dart';
import 'package:night_reader/core/sync/sync_store.dart';
import 'package:night_reader/features/settings/backup_sync_page.dart';
import 'package:night_reader/features/settings/local_book_sync_dialog.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/sync_store_blobs.dart';

/// 雲端有一本另一台傳的書；上傳原檔時停住，等 [gate] 放行（模擬網路慢）。
class _Store with SyncStoreBlobs implements SyncStore {
  final Map<String, String> files = {
    LocalBookSync.fileName: SyncDocument({
      'theirs': const SyncRecord(
        time: 1,
        data: {'name': '霧', 'author': '某人', 'ext': 'epub', 'size': 3145728},
      ),
    }).encode(),
  };
  final Completer<void> gate = Completer<void>();

  @override
  Future<void> check() async {}

  @override
  Future<SyncFile?> read(String name) async =>
      files[name] == null ? null : SyncFile(files[name]!);

  @override
  Future<String?> version(String name) async => null;

  @override
  Future<void> write(
    String name,
    String content, {
    String? ifVersion,
    bool ifAbsent = false,
  }) async => files[name] = content;

  @override
  Future<void> writeBytes(String name, Uint8List bytes) async {
    await gate.future;
    await super.writeBytes(name, bytes);
  }
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
  late AppDatabase db;
  final previous = SyncService.instance;
  tearDown(() => SyncService.instance = previous);

  /// 這台書架上有一本 TXT（[size] 位元組），雲端沒有。
  Future<void> pump(WidgetTester tester, {int size = 2 * 1024 * 1024}) async {
    SharedPreferences.setMockInitialValues({
      'sync.space': 'webdav',
      'sync.webdav.url': 'https://dav.example/',
    });
    store = _Store();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final books = BookDao(db);
    await tester.runAsync(() async {
      final dir = await Directory.systemTemp.createTemp('nr-local-dialog');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/夜航.txt')
        ..writeAsBytesSync(Uint8List(size));
      await books.upsert(
        Book(
          bookUrl: 'local://${file.path}',
          origin: 'local',
          name: '夜航',
          author: '本地',
          isInBookshelf: true,
          fileFingerprint: 'mine',
        ),
      );
    });
    SyncService.instance = SyncService(
      runner: runSyncWorkInline,
      storeFactory: (_, _, _) => store,
      bases: _MemoryBases(),
      bookDao: books,
      chapterDao: ChapterDao(db),
      kinds: (_) => [],
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(AppStyle.paper, Brightness.light),
        home: const BackupSyncPage(),
      ),
    );
    await settle(tester);
  }

  testWidgets('the button shows what will be sent and received before '
      'anything starts', (tester) async {
    await pump(tester);

    await tester.tap(find.text('同步本地書'));
    await settle(tester);

    expect(find.text('同步本地書？'), findsOneWidget);
    expect(find.textContaining('上傳 1 本，共 2.0 MB'), findsOneWidget);
    expect(find.textContaining('下載 1 本，共 3.0 MB'), findsOneWidget);
    expect(find.textContaining('行動數據'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await settle(tester);
    expect(find.text('同步本地書？'), findsNothing);
    expect(store.blobs, isEmpty);
  });

  testWidgets('once started it covers the app book by book; back does not '
      'close it', (tester) async {
    await pump(tester);
    // 只留上傳：雲端那本這台已經有了。
    store.files.remove(LocalBookSync.fileName);

    await tester.tap(find.text('同步本地書'));
    await settle(tester);
    await tester.tap(find.text('開始同步'));
    await settle(tester);

    expect(find.text('同步本地書中'), findsOneWidget);
    expect(find.text('第 1／1 本：上傳《夜航》（2.0 MB）'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await settle(tester);
    expect(find.text('同步本地書中'), findsOneWidget, reason: '按返回關不掉');

    store.gate.complete();
    await settle(tester);
    expect(find.text('同步本地書中'), findsNothing);
    expect(find.text('本地書同步完成'), findsOneWidget);
    expect(store.blobs.keys, [LocalBookSync.originalName('mine', 'txt')]);
  });

  test('sizes read as megabytes', () {
    expect(formatMegabytes(0), '0.0 MB');
    expect(formatMegabytes(500), '0.1 MB');
    expect(formatMegabytes(12 * 1024 * 1024 + 300 * 1024), '12.3 MB');
  });
}

/// 比對中的進度條一直在跑，等不到畫面靜止：讓檔案讀寫跑完，再推過對話框的
/// 進出場動畫。
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 400));
  }
}
