// 有聲書（ADR 0055）：開播放器（換頁、集數清單骨架換成清單），返回書架後
// 圓鈕從右緣滑進來，每一幀的成本。用法見 `test/support/frame_budget.dart`；
// 帶 `frame_budget` 標籤，平常的全套測試跳過。音訊引擎與書源是測試替身，
// 資料庫是整個 App 的那一個（`app_harness.dart`）。
@Tags(['frame_budget'])
library;

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/constant/source_type.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/features/audiobook/audiobook_mini_button.dart';
import 'package:night_reader/features/audiobook/audiobook_page.dart';
import 'package:night_reader/features/audiobook/audiobook_player.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';

import '../features/audiobook/audiobook_test_doubles.dart';
import '../support/app_harness.dart';
import '../support/navigation_budget.dart';
import '../support/screenshot.dart';

final _book = Book(
  bookUrl: 'https://audio.test/book/frame-budget',
  origin: 'https://audio.test',
  name: '長夜將盡',
  author: '沈墨',
  type: SourceType.audio,
  chapterIndex: 30,
  totalChapterNum: 60,
  isInBookshelf: true,
);

void main() {
  setUpAll(loadScreenshotFonts);

  testWidgets('audiobook', (tester) async {
    setUpPhone(tester);
    late AudiobookPlayer player;
    await tester.runAsync(() async {
      await setUpApp();
      await getIt<BookSourceDao>().upsert(
        BookSource(
          bookSourceUrl: 'https://audio.test',
          bookSourceName: '夜雨聽書',
          bookSourceType: SourceType.audio,
        ),
      );
      await getIt<BookDao>().upsert(_book);
      await getIt<ChapterDao>().insertChapters([
        for (var i = 0; i < 60; i++)
          BookChapter(
            url: 'https://audio.test/ep$i',
            title: '第 ${i + 1} 集 雨夜來客',
            bookUrl: _book.bookUrl,
            index: i,
          ),
      ]);
      final engine = FakeAudioEngine();
      player = AudiobookPlayer(
        engine: () => engine,
        bookDao: getIt<BookDao>(),
        chapterDao: getIt<ChapterDao>(),
        sourceDao: getIt<BookSourceDao>(),
        sourceService: FakeAudioSourceService(),
        sync: FakeSync(),
        playback: RecordingPlayback(),
        random: Random(1),
      );
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(AppStyle.paper, Brightness.dark),
        home: Builder(
          builder: (context) => Scaffold(
            body: Stack(
              children: [
                Center(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            AudiobookPage(book: _book, player: player),
                      ),
                    ),
                    child: const Text('打開有聲書'),
                  ),
                ),
                Positioned(
                  right: 16,
                  bottom: 120,
                  child: AudiobookMiniButton(player: player),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await measureNavigation(
      tester,
      '開播放器',
      action: () => tester.tap(find.text('打開有聲書')),
      page: find.byType(AudiobookPage),
    );
    await rest(tester);

    final mini = find.bySemanticsLabel('有聲書：長夜將盡');
    await measureNavigation(
      tester,
      '返回、圓鈕滑進來',
      action: () async {
        Navigator.of(tester.element(find.byType(AudiobookPage))).pop();
        await tester.pump();
      },
      settled: () =>
          find.byType(AudiobookPage).evaluate().isEmpty &&
          mini.hitTestable().evaluate().isNotEmpty,
    );

    await rest(tester);

    // 再開一次：第一次含 debug 模式第一次跑到這些程式的編譯。
    await measureNavigation(
      tester,
      '再開一次播放器',
      action: () => tester.tap(find.text('打開有聲書')),
      page: find.byType(AudiobookPage),
    );
    await rest(tester);

    Navigator.of(tester.element(find.byType(AudiobookPage))).pop();
    await rest(tester);
    // 收聽時間的寫入排在測試的假時鐘裡：照假時鐘推進，不從真實時間等它。
    unawaited(player.stop());
    await rest(tester);
    await tester.pumpWidget(const SizedBox());
  });
}
