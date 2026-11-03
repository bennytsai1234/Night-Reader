// 開 App 後馬上從書架開書，同時開 App 的那次同步正在跑：同步空間裡有幾十個書源，
// 另一台改過其中一個，每次讀寫雲端都要等網路。和同一次開 App 裡、同步跑完之後的
// 第二次開書比，看第一次開書多掉的幀是不是同步佔了主執行緒。用法見
// `test/support/frame_budget.dart`；帶 `frame_budget` 標籤，平常的全套測試跳過。
@Tags(['frame_budget'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/sync/sync_base_storage.dart';
import 'package:night_reader/core/sync/sync_service.dart';
import 'package:night_reader/core/sync/sync_store.dart';
import 'package:night_reader/features/bookshelf/bookshelf_page.dart';
import 'package:night_reader/features/reader_v2/hybrid/overlay/loading_veil.dart';
import 'package:night_reader/features/reader_v2/screen/reader_v2_page.dart';

import '../support/app_harness.dart';
import '../support/navigation_budget.dart';
import '../support/screenshot.dart';

/// 記在記憶體裡的同步空間，每次讀寫等 [latency]（假時鐘，跟著測試推進）。
class _SlowStore implements SyncStore {
  final Map<String, (String, int)> files = {};
  Duration latency = Duration.zero;

  Future<void> _wait() =>
      latency == Duration.zero ? Future.value() : Future.delayed(latency);

  @override
  Future<void> check() async {}

  @override
  Future<SyncFile?> read(String name) async {
    await _wait();
    final file = files[name];
    return file == null ? null : SyncFile(file.$1, version: '${file.$2}');
  }

  @override
  Future<String?> version(String name) async {
    await _wait();
    final file = files[name];
    return file == null ? null : '${file.$2}';
  }

  @override
  Future<void> write(
    String name,
    String content, {
    String? ifVersion,
    bool ifAbsent = false,
  }) async {
    await _wait();
    final current = files[name];
    if (ifAbsent && current != null) throw const SyncConflict();
    if (ifVersion != null && '${current?.$2}' != ifVersion) {
      throw const SyncConflict();
    }
    files[name] = (content, (current?.$2 ?? 0) + 1);
  }
}

/// 一個規則寫得像真的書源（搜尋、詳情、目錄、正文都有規則）。
BookSource _source(int i) => BookSource.fromJson({
  'bookSourceUrl': 'https://source$i.test',
  'bookSourceName': '書源 $i',
  'bookSourceGroup': i.isEven ? '常用' : '備用',
  'bookSourceComment': '第 $i 個書源的說明。' * 20,
  'searchUrl': 'https://source$i.test/search?q={{key}}&page={{page}}',
  'header': '{"User-Agent":"Mozilla/5.0 (Linux; Android 14) Mobile"}',
  'ruleSearch': {
    'bookList': 'class.result-list@tag.li',
    'name': 'class.title@text',
    'author': 'class.author@text##作者：',
    'kind': 'class.tags@tag.span@text',
    'lastChapter': 'class.update@tag.a@text',
    'intro': 'class.intro@text',
    'coverUrl': 'tag.img@data-src',
    'bookUrl': 'class.title@tag.a@href',
  },
  'ruleBookInfo': {
    'init': '@js:var d = JSON.parse(result); d.data',
    'name': 'h1@text',
    'author': 'class.info@tag.p.0@text##作者：',
    'intro': 'id.intro@html',
    'coverUrl': 'id.fmimg@tag.img@src',
    'tocUrl': 'class.btn-toc@href',
  },
  'ruleToc': {
    'chapterList': 'id.list@tag.dd',
    'chapterName': 'tag.a@text',
    'chapterUrl': 'tag.a@href',
    'nextTocUrl': 'text.下一頁@href',
  },
  'ruleContent': {
    'content': 'id.content@html',
    'nextContentUrl': 'text.下一章@href',
    'replaceRegex': '##本章未完.*|請收藏.*',
  },
});

bool _veilCovering() => find
    .byType(LoadingVeil)
    .evaluate()
    .any((e) => (e.widget as LoadingVeil).controller.isVisible);

bool _readerShown() =>
    pageSettled(find.byType(ReaderV2Page)) && !_veilCovering();

void main() {
  setUpAll(loadScreenshotFonts);

  testWidgets('opening a book right after launch while syncing', (
    tester,
  ) async {
    setUpPhone(tester);
    final store = _SlowStore();
    late Directory bases;
    SyncService phone() => SyncService(
      storeFactory: (_, _, _) => store,
      bases: SyncBaseStorage(directory: () async => bases),
    );
    await tester.runAsync(() async {
      await setUpApp();
      await seedLibrary();
      await installFakeSite();
      await getIt<BookSourceDao>().upsertAll([
        for (var i = 0; i < 60; i++) _source(i),
      ]);
      bases = await Directory.systemTemp.createTemp('nr-sync-budget');
      // 這台之前同步過：雲端與上次同步的紀錄都有，兩邊一樣。
      await phone().syncNow();
      // 之後另一台改了一個書源。
      final (content, version) = store.files['sources.json']!;
      final json = jsonDecode(content) as Map<String, dynamic>;
      final record =
          (json['records'] as Map<String, dynamic>)['https://source7.test']
              as Map<String, dynamic>;
      record['time'] = DateTime.now().millisecondsSinceEpoch;
      (record['data'] as Map<String, dynamic>)['bookSourceName'] = '另一台改的名字';
      store.files['sources.json'] = (jsonEncode(json), version + 1);
    });
    // 暖身：電腦上的測試第一次跑到閱讀器要先編譯，第一次開書因此特別重；
    // 手機上的正式版事先編譯好，沒有這段。先開關一次書、關掉 App，下面重開
    // App 量的才是同步的影響。
    await pumpApp(tester);
    await openReader(tester);
    await goBack(tester);
    await rest(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    await settle(tester);

    // 對照組：NR_SYNC_OFF=1 時不設同步空間，量到的是和同步無關的部分。
    if (Platform.environment['NR_SYNC_OFF'] != '1') {
      SyncService.instance = phone();
    }
    // 雲端硬碟一次讀寫約 0.3 秒。
    store.latency = const Duration(milliseconds: 300);

    await pumpApp(tester);
    // 每一幀時同步跑到哪一種資料，印在量測結果後面，對得上是哪幾幀被同步佔住。
    final syncing = <String, List<int>>{};
    await measureNavigation(
      tester,
      '第一次 書架點書→閱讀器（同步進行中）',
      action: () => tester.tap(find.text('夜雨聽書').first),
      settled: _readerShown,
      onFrame: (frame) async {
        final kind = SyncService.instance.status.value.progress?.kind;
        if (kind != null) (syncing[kind] ??= []).add(frame);
      },
    );
    debugPrint(
      '同步跑到的資料（第幾幀）：${syncing.isEmpty ? '開書時同步沒在跑' : [for (final MapEntry(:key, :value) in syncing.entries) '$key ${value.first}–${value.last}'].join('、')}',
    );
    await rest(tester);
    await measureNavigation(
      tester,
      '第一次 閱讀器返回書架',
      action: () => goBack(tester),
      page: find.byType(BookshelfPage),
    );
    // 等同步整輪跑完再開第二次。
    while (SyncService.instance.status.value.running) {
      await rest(tester);
    }
    await rest(tester);
    await measureNavigation(
      tester,
      '第二次 書架點書→閱讀器（同步已完成）',
      action: () => tester.tap(find.text('夜雨聽書').first),
      settled: _readerShown,
    );
    await rest(tester);
    expect(
      SyncService.instance.status.value.error,
      isNull,
      reason: '同步要真的跑完，量到的才是同步的成本',
    );

    await tearDownApp(tester);
    // 上次同步的紀錄檔可能還被開著，刪不掉就留給系統清暫存。
    await tester.runAsync(
      () => bases.delete(recursive: true).then((_) {}, onError: (_) {}),
    );
  });
}
