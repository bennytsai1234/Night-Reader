// 從發現進一個分類：換頁、書單出現，接著清單上的書陸續補到封面與字數
// （封面淡入）的每一幀成本（ADR 0018）。用法見 `test/support/frame_budget.dart`；
// 帶 `frame_budget` 標籤，平常的全套測試跳過。
//
// 書單與書籍詳情直接從記憶體給（App 裡在書源 isolate 解析，主執行緒只收
// 結果）；封面是暫存區裡真的 PNG 檔，解碼與淡入照實際的路徑走。另跑一次
// 書籍詳情一直不回來的對照，看補資料本身多了什麼。
@Tags(['frame_budget'])
library;

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/search_book.dart';
import 'package:night_reader/core/services/bookshelf_state_tracker.dart';
import 'package:night_reader/features/explore/explore_book_details.dart';
import 'package:night_reader/features/explore/explore_show_page.dart';
import 'package:night_reader/features/explore/explore_show_provider.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';
import 'package:provider/provider.dart';

import '../support/frame_budget.dart';
import '../support/screenshot.dart';

const _origin = 'https://s.example';

class _FakeSourceDao extends Fake implements BookSourceDao {
  @override
  Future<BookSource?> getByUrl(String url) async =>
      BookSource(bookSourceUrl: _origin, bookSourceName: '書源');
}

class _FakeBookDao extends Fake implements BookDao {
  @override
  Future<List<Book>> getInBookshelf() async => const [];
}

/// 一張 156×210 的 PNG（封面在手機上的解碼尺寸）。
Future<File> _coverFile(Directory dir, int i) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 156, 210),
    Paint()..color = Color(0xFF203040 + i * 0x0A0B0C),
  );
  canvas.drawCircle(const Offset(78, 80), 40, Paint()..color = Colors.amber);
  final image = await recorder.endRecording().toImage(156, 210);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  final file = File('${dir.path}${Platform.pathSeparator}cover_$i.png');
  await file.writeAsBytes(bytes!.buffer.asUint8List());
  return file;
}

void main() {
  setUpAll(loadScreenshotFonts);

  testWidgets('entering a category while covers and word counts arrive', (
    tester,
  ) async {
    setUpScreenshot(tester);
    if (getIt.isRegistered<BookSourceDao>()) getIt.unregister<BookSourceDao>();
    getIt.registerSingleton<BookSourceDao>(_FakeSourceDao());
    addTearDown(() => getIt.unregister<BookSourceDao>());

    const bookCount = 30;
    final covers = await tester.runAsync(() async {
      final dir = await Directory.systemTemp.createTemp('explore_covers');
      return [for (var i = 0; i < bookCount * 3; i++) await _coverFile(dir, i)];
    });
    addTearDown(() => covers!.first.parent.deleteSync(recursive: true));

    SearchBook listed(int i) => SearchBook(
      bookUrl: '$_origin/book/$i',
      name: '第$i本書的書名，有時候很長很長',
      author: '作者$i',
      kind: '玄幻,連載',
      latestChapterTitle: '第${300 + i}章 夜深了',
      origin: _origin,
    );

    // 補資料時書籍詳情 0.2–0.65 秒後陸續回來；對照組一直不回來。第一輪含
    // debug 模式第一次執行程式的編譯成本（手機上的正式版沒有），只暖機。
    // 封面檔每一輪換一批，不吃上一輪的圖片快取。
    var round = 0;
    for (final (label, answers) in [
      ('暖機（含編譯）', true),
      ('進分類、不補（對照）', false),
      ('進分類、補封面與字數', true),
    ]) {
      final offset = bookCount * round++;
      var answered = 0;
      var asked = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(AppStyle.paper, Brightness.light),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ChangeNotifierProvider(
                        create: (_) => ExploreShowProvider(
                          sourceUrl: _origin,
                          exploreUrl: '$_origin/category/1',
                          exploreName: '玄幻',
                          // 書單本來就晚 0.3 秒才到，進場不另外等。
                          entrance: Future<void>.value(),
                          bookshelfTracker: BookshelfStateTracker(
                            bookDao: _FakeBookDao(),
                          ),
                          exploreLoader: (source, url, {page, cancelToken}) =>
                              Future.delayed(
                                const Duration(milliseconds: 300),
                                () => page == 1
                                    ? [
                                        for (var i = 0; i < bookCount; i++)
                                          listed(i),
                                      ]
                                    : <SearchBook>[],
                              ),
                          extrasLoader: (source, book, {cancelToken}) {
                            final i = int.parse(book.bookUrl.split('/').last);
                            asked++;
                            if (!answers) {
                              return Completer<ExploreBookExtras>().future;
                            }
                            return Future.delayed(
                              Duration(milliseconds: 200 + (i % 4) * 150),
                              () {
                                answered++;
                                return (
                                  coverUrl: Uri.file(covers![offset + i].path)
                                      .toString(),
                                  wordCount: '${12 + i}.3萬字',
                                );
                              },
                            );
                          },
                        ),
                        child: const ExploreShowView(exploreName: '玄幻'),
                      ),
                    ),
                  ),
                  child: const Text('玄幻'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('玄幻'));
      var settledAt = -1;
      var askedAt = -1;
      var frame = 0;
      final costs = await recordFrames(
        tester,
        realAsync: true,
        // 畫出來的書都問過、也都回來了（對照組：問過）之後，再看封面淡入播完。
        until: () {
          if (asked > 0 && askedAt < 0) askedAt = frame;
          frame++;
          final done = asked > 0 && (answers ? answered == asked : true);
          if (done && settledAt < 0) settledAt = frame;
          return done && frame - settledAt > 30;
        },
        tailFrames: 30,
      );
      // 第一本書籍詳情最快 0.2 秒（約 12 幀）後回來，從那裡分成兩段。
      final split = (askedAt + 12).clamp(0, costs.length);
      // ignore: avoid_print
      print(
        '${describeFrames('$label：換頁與書單出現', costs.sublist(0, split))}\n'
        '${describeFrames('$label：之後（補資料陸續回來）', costs.sublist(split))}\n'
        '  問了 $asked 本，回來 $answered 本',
      );
      expect(asked, greaterThan(0));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    }
  });
}
