import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/dao/bookmark_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/features/reader/chapter/reader_content.dart';
import 'package:night_reader/features/reader/text_view/core/text_view_types.dart';
import 'package:night_reader/features/reader/text_view/overlay/selection_service.dart';
import 'package:night_reader/features/reader/text_view/reader_text_view.dart';

import '../../support/app_harness.dart';
import '../../support/navigation_budget.dart';

/// 閱讀器「更多」的「書籤」：在畫面頂端那一句的開頭留一個，和在那裡選字
/// 按「書籤」存的是同一筆（章、章內位置、錨點、摘錄都一樣）。
void main() {
  testWidgets('「更多 → 書籤」留在畫面頂端那一句的開頭，和選字加的一樣', (tester) async {
    setUpPhone(tester);
    await tester.runAsync(() async {
      await setUpApp();
      await seedLibrary();
    });
    await pumpApp(tester);
    await openReader(tester);

    final reader = tester.widget<ReaderTextView>(find.byType(ReaderTextView));
    final runtime = reader.runtime;
    final top =
        runtime.captureVisibleLocation() ?? runtime.state.visibleLocation;
    final content = runtime.repository.cachedContent(top.chapterIndex)!;
    final paragraph = _paragraphAt(content, top.charOffset);
    final offset = paragraph.offset < paragraph.end
        ? paragraph.offset
        : paragraph.end - 1;

    // 在同一個位置選一個字按「書籤」，存下來的會是什麼。
    final blocks = _blocksOf(content);
    final selected = ReaderTextSelection(
      blocks: blocks,
      epoch: LayoutEpoch.initial,
      range: ChapterTextRange(offset, offset + 1),
    ).asBookmark;

    await showReaderMenu(tester);
    await tester.tap(find.byTooltip('更多').last);
    await settle(tester, const Duration(milliseconds: 600));
    await tester.tap(find.text('書籤'));
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }

    final saved = (await tester.runAsync(getIt<BookmarkDao>().getAll))!.single;
    expect(saved.chapterIndex, selected.location.chapterIndex);
    expect(saved.chapterTitle, selected.chapterTitle);
    expect(saved.charOffset, selected.location.charOffset);
    expect(saved.excerpt, selected.excerpt);
    expect(saved.anchor, jsonEncode(selected.location.toJson()));
    expect(find.text('已加入書籤'), findsOneWidget);
    await tearDownApp(tester);
  });
}

/// [charOffset] 落在的那一段正文：段落分隔與章名上算下一段開頭。
({int start, int end, int offset}) _paragraphAt(
  ReaderContent content,
  int charOffset,
) {
  var start = content.bodyStartOffset;
  for (final text in content.paragraphs) {
    final end = start + text.length;
    if (charOffset < end) {
      return (
        start: start,
        end: end,
        offset: charOffset < start ? start : charOffset,
      );
    }
    start = end + 2;
  }
  final end = content.displayText.length;
  return (start: end - content.paragraphs.last.length, end: end, offset: end);
}

/// 和閱讀器排出來的一樣：標題一塊，每段正文一塊（插圖不影響段落範圍）。
ChapterBlocks _blocksOf(ReaderContent content) {
  final blocks = <ChapterBlock>[];
  if (content.title.isNotEmpty) {
    blocks.add(
      ChapterBlock(
        key: BlockKey(chapterIndex: content.chapterIndex, blockIndex: 0),
        text: content.title,
        charRange: ChapterTextRange(0, content.title.length),
        sourceParagraphIndex: -1,
        isTitle: true,
      ),
    );
  }
  var start = content.bodyStartOffset;
  for (var i = 0; i < content.paragraphs.length; i++) {
    final paragraph = content.paragraphs[i];
    blocks.add(
      ChapterBlock(
        key: BlockKey(
          chapterIndex: content.chapterIndex,
          blockIndex: blocks.length,
        ),
        text: paragraph,
        charRange: ChapterTextRange(start, start + paragraph.length),
        sourceParagraphIndex: i,
      ),
    );
    start += paragraph.length + 2;
  }
  return ChapterBlocks(
    chapterIndex: content.chapterIndex,
    title: content.title,
    displayText: content.displayText,
    contentHash: content.contentHash,
    blocks: blocks,
  );
}
