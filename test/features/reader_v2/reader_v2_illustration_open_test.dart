import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/constant/prefer_key.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/database/dao/reader_chapter_content_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/services/book_illustration_storage.dart';
import 'package:night_reader/core/services/reader_chapter_content_store.dart';
import 'package:night_reader/features/reader_v2/hybrid/illustration/illustration_images.dart';

import '../../support/app_harness.dart';

/// 1200×800 的 PNG。
Future<List<int>> _png() async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawColor(const Color(0xFF336699), BlendMode.src);
  final image = await recorder.endRecording().toImage(1200, 800);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

// 整個 App 一個檔案只開一次（setUpApp）。
void main() {
  testWidgets('開著「顯示插圖」打開正文有插圖的章：圖解碼好、紙掀開；關掉再開一次也一樣', (tester) async {
    setUpPhone(tester);
    late String imagePath;
    await tester.runAsync(() async {
      await setUpApp();
      await seedLibrary();
      const src = 'https://www.example.com/img/1.png';
      final book = (await getIt<BookDao>().getByUrl(kBookUrl))!;
      imagePath = BookIllustrationStorage.pathFor(
        await BookIllustrationStorage.dirFor(book),
        src,
      );
      await File(imagePath).create(recursive: true);
      await File(imagePath).writeAsBytes(await _png());
      // 書架上這本書停在第三章開頭：第二段後面夾一張圖。
      await ReaderChapterContentStore(
        chapterDao: getIt<ChapterDao>(),
        contentDao: getIt<ReaderChapterContentDao>(),
      ).saveRawContent(
        book: book,
        chapter: BookChapter(
          url: '${kBookUrl}c2.html',
          title: kChapterTitles[2],
          bookUrl: kBookUrl,
          index: 2,
        ),
        content: [
          kParagraphs[0],
          kParagraphs[1],
          '<img src="$src">',
          ...kParagraphs.skip(2),
        ].join('\n'),
        saveChapterMetadata: false,
      );
    });

    // 第二次打開（換成深色）時圖已經解碼好留著。
    for (final (round, mode) in ['light', 'dark'].indexed) {
      await tester.runAsync(
        () => resetPrefs({
          'themeMode': mode,
          PreferKey.readerShowIllustrations: true,
        }),
      );
      await pumpApp(tester);
      await openReader(tester);
      // 欄寬 369、像素密度 3：1200 像素寬的圖縮到欄寬，照 1107 像素解碼。
      expect(
        IllustrationImages.instance.peek(imagePath, 1107),
        isNotNull,
        reason: '第 ${round + 1} 次打開',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await settle(tester, const Duration(milliseconds: 300));
    }
    await tester.pump(const Duration(minutes: 1));
  });
}
