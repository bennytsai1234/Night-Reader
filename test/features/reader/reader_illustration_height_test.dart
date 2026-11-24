import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/constant/prefer_key.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/database/dao/reader_chapter_content_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/models/book/book_chapter.dart';
import 'package:night_reader/core/storage/book_illustration_storage.dart';
import 'package:night_reader/core/storage/reader_chapter_content_store.dart';
import 'package:night_reader/features/reader/chapter/reader_illustration.dart';
import 'package:night_reader/features/reader/layout/reader_layout_spec.dart';
import 'package:night_reader/features/reader/text_view/illustration/illustration_images.dart';
import 'package:night_reader/features/reader/text_view/reader_text_view.dart';

import '../../support/app_harness.dart';

/// 300×3000 的 PNG：比正文區高，要等比縮到正文區高。
Future<List<int>> _tallPng() async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawColor(const Color(0xFF336699), BlendMode.src);
  final image = await recorder.endRecording().toImage(300, 3000);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

/// 正文區變矮（狀態列、頁首頁尾的設定改了）：比正文區高的插圖照新的高度
/// 縮，一屏看得到整張（docs/design/reader.md「插圖」）。
void main() {
  testWidgets('正文區變矮後，很高的插圖照新的正文區高縮', (tester) async {
    setUpPhone(tester);
    late String imagePath;
    await tester.runAsync(() async {
      await setUpApp();
      await seedLibrary();
      const src = 'https://www.example.com/img/tall.png';
      final book = (await getIt<BookDao>().getByUrl(kBookUrl))!;
      imagePath = BookIllustrationStorage.pathFor(
        await BookIllustrationStorage.dirFor(book),
        src,
      );
      await File(imagePath).create(recursive: true);
      await File(imagePath).writeAsBytes(await _tallPng());
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
          '<img src="$src">',
          ...kParagraphs.skip(1),
        ].join('\n'),
        replaceStored: true,
        saveChapterMetadata: false,
      );
      await resetPrefs({PreferKey.readerShowIllustrations: true});
    });
    await pumpApp(tester);
    await openReader(tester);

    int decodeWidthFor(ReaderLayoutSpec spec) => IllustrationBox.layout(
      const ReaderIllustration(
        offset: 0,
        src: '',
        path: '',
        pixelWidth: 300,
        pixelHeight: 3000,
      ),
      contentWidth: spec.textLayoutFrame.width,
      maxHeight: spec.contentHeight,
      devicePixelRatio: 3,
      gap: 0,
    ).decodeWidth;
    final runtime = tester
        .widget<ReaderTextView>(find.byType(ReaderTextView))
        .runtime;
    final before = runtime.state.layoutSpec;
    expect(
      IllustrationImages.instance.peek(imagePath, decodeWidthFor(before)),
      isNotNull,
    );

    // 上方的系統區變高（例如關掉「隱藏狀態列」）：正文區矮了 100。
    const padding = FakeViewPadding(top: 432, bottom: 72);
    tester.view.padding = padding;
    tester.view.viewPadding = padding;
    await settle(tester, const Duration(milliseconds: 600));
    await waitForText(tester);

    final after = runtime.state.layoutSpec;
    expect(after.contentHeight, lessThan(before.contentHeight));
    expect(
      IllustrationImages.instance.peek(imagePath, decodeWidthFor(after)),
      isNotNull,
      reason: '插圖照新的正文區高排過',
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(minutes: 1));
  });
}
