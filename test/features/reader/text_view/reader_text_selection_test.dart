import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/chinese/chinese_utils.dart';
import 'package:night_reader/features/reader/chapter/reader_illustration.dart';
import 'package:night_reader/core/models/reading/highlight.dart';
import 'package:night_reader/features/reader/session/reader_location.dart';
import 'package:night_reader/features/reader/text_view/overlay/highlight_marks.dart';
import 'package:night_reader/features/reader/text_view/overlay/reader_mark_layers.dart';
import 'package:night_reader/features/reader/text_view/core/text_view_types.dart';
import 'package:night_reader/features/reader/text_view/overlay/selection_service.dart';
import 'package:night_reader/features/reader/text_view/overlay/reader_text_selection_layer.dart';
import 'package:night_reader/features/reader/text_view/text/word_segmenter.dart';

Future<void> _ignoreShare(String text) async {}

ChapterBlock _block(
  int index,
  String text,
  int start, {
  int paragraph = 0,
  bool isTitle = false,
  bool isContinuation = false,
  bool layoutBreakBefore = false,
}) {
  return ChapterBlock(
    key: BlockKey(chapterIndex: 0, blockIndex: index),
    text: text,
    charRange: ChapterTextRange(start, start + text.length),
    sourceParagraphIndex: paragraph,
    isTitle: isTitle,
    isContinuation: isContinuation,
    layoutBreakBefore: layoutBreakBefore,
  );
}

/// 標題、兩段正文；第一段被排版切成兩個 group（同一來源段落）。
ChapterBlocks _chapter() {
  const title = '第一章';
  const first = '天色漸暗，城門';
  const firstTail = '即將關閉。';
  const second = '他快步走過長街。';
  const display = '$title\n\n$first$firstTail\n\n$second';
  var offset = 0;
  final blocks = <ChapterBlock>[];
  blocks.add(_block(0, title, offset, paragraph: -1, isTitle: true));
  offset += title.length + 2;
  blocks.add(_block(1, first, offset));
  offset += first.length;
  blocks.add(
    _block(2, firstTail, offset, isContinuation: true, layoutBreakBefore: true),
  );
  offset += firstTail.length + 2;
  blocks.add(_block(3, second, offset, paragraph: 1));
  return ChapterBlocks(
    chapterIndex: 0,
    title: title,
    displayText: display,
    contentHash: 'hash',
    blocks: blocks,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ParagraphTextMap.paragraphRangeForSourceRange', () {
    const source = '一二三四五六七八九十';
    final map = ParagraphTextMap(
      sourceLength: source.length,
      indentLength: 2,
      visualLineBreakOffsets: const <int>[3, 7],
      spacers: const <LineSpacer>[LineSpacer(5, 4), LineSpacer(8, 2.5)],
    );
    // 插入的換行照樣是換行，縮排與補白寫成 placeholder 的 U+FFFC。
    const placeholder = '￼';
    bool isInsertedUnit(String unit) => unit == '\n' || unit == placeholder;
    final laidOut = [
      placeholder * map.indentLength,
      for (final piece in map.pieces(source)) piece.text ?? placeholder,
    ].join();

    test('排版文字的長度與換算表一致', () {
      expect(laidOut.length, map.paragraphLength);
    });

    test('任何來源範圍換算後，在排版文字中取到的都是同一段字', () {
      for (var start = 0; start < source.length; start += 1) {
        for (var end = start + 1; end <= source.length; end += 1) {
          final range = map.paragraphRangeForSourceRange(start, end);
          final slice = laidOut.substring(range.start, range.end);
          expect(
            slice.replaceAll('\n', '').replaceAll(placeholder, ''),
            source.substring(start, end),
            reason: '[$start, $end)',
          );
          expect(
            isInsertedUnit(slice[0]),
            isFalse,
            reason: '範圍開頭不得是插入的換行或補白 [$start, $end)',
          );
          expect(
            isInsertedUnit(slice[slice.length - 1]),
            isFalse,
            reason: '範圍結尾不得包進插入的換行或補白 [$start, $end)',
          );
        }
      }
    });

    test('每個來源字換回來都是自己，插入的位置都認得出來', () {
      for (var offset = 0; offset < source.length; offset += 1) {
        final paragraphOffset = map.paragraphOffsetForSourceOffset(offset);
        expect(laidOut[paragraphOffset], source[offset]);
        expect(map.sourceOffsetForParagraphOffset(paragraphOffset), offset);
        expect(map.isInsertedParagraphOffset(paragraphOffset), isFalse);
      }
      for (var p = 0; p < laidOut.length; p += 1) {
        final isInserted = isInsertedUnit(laidOut[p]);
        expect(map.isInsertedParagraphOffset(p), isInserted, reason: '$p');
      }
    });

    test('補白不能落在換行處或行首行尾', () {
      expect(
        () => ParagraphTextMap(
          sourceLength: source.length,
          indentLength: 0,
          visualLineBreakOffsets: const <int>[3],
          spacers: const <LineSpacer>[LineSpacer(3, 4)],
        ),
        throwsStateError,
      );
      expect(
        () => ParagraphTextMap(
          sourceLength: source.length,
          indentLength: 0,
          spacers: const <LineSpacer>[LineSpacer(0, 4)],
        ),
        throwsStateError,
      );
    });
  });

  group('ChapterBlocks.sourceParagraphRange', () {
    test('被切成多個 group 的長段落回傳整段', () {
      final chapter = _chapter();
      final range = chapter.sourceParagraphRange(
        const BlockKey(chapterIndex: 0, blockIndex: 2),
      )!;
      expect(
        chapter.displayText.substring(range.start, range.end),
        '天色漸暗，城門即將關閉。',
      );
      expect(
        chapter.sourceParagraphRange(
          const BlockKey(chapterIndex: 0, blockIndex: 1),
        ),
        range,
      );
    });

    test('不跨到下一段，標題不可選', () {
      final chapter = _chapter();
      final range = chapter.sourceParagraphRange(
        const BlockKey(chapterIndex: 0, blockIndex: 3),
      )!;
      expect(chapter.displayText.substring(range.start, range.end), '他快步走過長街。');
      expect(
        chapter.sourceParagraphRange(
          const BlockKey(chapterIndex: 0, blockIndex: 0),
        ),
        isNull,
      );
    });
  });

  group('ReaderTextSelection.moveEdge', () {
    ReaderTextSelection select(String text, {ChapterBlocks? blocks}) {
      final chapter = blocks ?? _chapter();
      final start = chapter.displayText.indexOf(text);
      return ReaderTextSelection(
        blocks: chapter,
        epoch: LayoutEpoch.initial,
        range: ChapterTextRange(start, start + text.length),
      );
    }

    // 選「城門」。
    ReaderTextSelection selection() => select('城門');

    test('拖動一端延伸選取，複製取 displayText', () {
      final base = selection();
      final moved = base.moveEdge(SelectionEdge.end, base.range.end + 2);
      expect(moved.selection.text, '城門即將');
      expect(moved.edge, SelectionEdge.end);
    });

    test('可以拖到別段，到這一章正文的頭尾停住，章名不算', () {
      final base = selection();
      final display = base.blocks.displayText;
      final before = base.moveEdge(SelectionEdge.start, 0);
      expect(before.selection.range.start, display.indexOf('天色'));
      final after = base.moveEdge(SelectionEdge.end, 1 << 20);
      expect(after.selection.range.end, display.length);
      expect(after.selection.text, '城門即將關閉。\n\n他快步走過長街。');
    });

    test('落在段落分隔上時往字那邊靠', () {
      final base = selection();
      final display = base.blocks.displayText;
      // 結尾拖到下一段的開頭：停在上一段的最後一個字後面。
      final end = base.moveEdge(SelectionEdge.end, display.indexOf('他快步'));
      expect(end.selection.text, '城門即將關閉。');
      // 開頭拖到上一段的結尾後面：從下一段的第一個字開始。
      final second = select('長街');
      final start = second.moveEdge(
        SelectionEdge.start,
        display.indexOf('關閉。') + 3,
      );
      expect(start.selection.text, '他快步走過長街');
    });

    test('兩端之間只剩段落分隔時，留下拖動那一側最近的一個字', () {
      final display = _chapter().displayText;
      final first = select('他');
      // 結尾往上拖到上一段的結尾：越過開頭、成為開頭，留上一段最後一個字。
      final up = first.moveEdge(SelectionEdge.end, display.indexOf('關閉。') + 3);
      expect(up.selection.text, '。');
      expect(up.edge, SelectionEdge.start);
      final last = select('。', blocks: _chapter());
      // 開頭往下拖到下一段的開頭：越過結尾、成為結尾，留下一段第一個字。
      final down = last.moveEdge(SelectionEdge.start, display.indexOf('他'));
      expect(down.selection.text, '他');
      expect(down.edge, SelectionEdge.end);
    });

    test('留一個字時不拆開兩個單位的字', () {
      const title = '章';
      const body = '甲😀乙';
      const display = '$title\n\n$body';
      final chapter = ChapterBlocks(
        chapterIndex: 0,
        title: title,
        displayText: display,
        contentHash: 'emoji',
        blocks: [
          _block(0, title, 0, paragraph: -1, isTitle: true),
          _block(1, body, title.length + 2),
        ],
      );
      final emoji = display.indexOf('😀');
      final base = ReaderTextSelection(
        blocks: chapter,
        epoch: LayoutEpoch.initial,
        range: ChapterTextRange(emoji, emoji + 2),
      );
      expect(
        base.moveEdge(SelectionEdge.start, emoji + 2).selection.text,
        '😀',
      );
      expect(base.moveEdge(SelectionEdge.end, emoji).selection.text, '😀');
    });

    test('照段落切開交給隱藏與替換，跨過插圖時標出來', () {
      final cross = select('城門').moveEdge(SelectionEdge.end, 1 << 20);
      final parts = cross.selection.inParagraphs;
      expect(parts.chapterIndex, 0);
      expect(parts.crossesIllustration, isFalse);
      expect(parts.pieces, [
        (paragraphIndex: 0, paragraph: '天色漸暗，城門即將關閉。', start: 5, end: 12),
        (paragraphIndex: 1, paragraph: '他快步走過長街。', start: 0, end: 8),
      ]);

      final chapter = _chapter();
      final second = chapter.displayText.indexOf('他快步');
      final withPicture = ChapterBlocks(
        chapterIndex: 0,
        title: chapter.title,
        displayText: chapter.displayText,
        contentHash: chapter.contentHash,
        blocks: [
          for (final block in chapter.blocks)
            if (block.blockIndex < 3) block,
          ChapterBlock(
            key: const BlockKey(chapterIndex: 0, blockIndex: 3),
            text: '',
            charRange: ChapterTextRange(second, second),
            sourceParagraphIndex: 1,
            illustration: const ReaderIllustration(
              offset: 0,
              src: 'a.png',
              path: 'a.png',
              pixelWidth: 10,
              pixelHeight: 10,
            ),
          ),
          _block(4, '他快步走過長街。', second, paragraph: 1),
        ],
      );
      expect(select('城門', blocks: withPicture).crossesIllustration, isFalse);
      final across = select(
        '城門',
        blocks: withPicture,
      ).moveEdge(SelectionEdge.end, 1 << 20).selection;
      expect(across.crossesIllustration, isTrue);
      expect(across.inParagraphs.pieces, hasLength(2));
    });

    test('越過另一端時兩端互換，拖動中的一端跟著換', () {
      final base = selection();
      final moved = base.moveEdge(SelectionEdge.end, base.range.start - 2);
      // 原起點「城」成為新的結尾。
      expect(moved.selection.text, '暗，');
      expect(moved.edge, SelectionEdge.start);
    });

    test('拖到另一端上至少保留一個字', () {
      final base = selection();
      final collapsedFromEnd = base.moveEdge(
        SelectionEdge.end,
        base.range.start,
      );
      expect(collapsedFromEnd.selection.text, '城');
      final collapsedFromStart = base.moveEdge(
        SelectionEdge.start,
        base.range.end,
      );
      expect(collapsedFromStart.selection.text, '門');
    });
  });

  group('WordSegmenter', () {
    const channel = MethodChannel('com.inkpage.reader/word_segmenter');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    test('採用原生斷詞結果', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'wordAt');
        return <int>[2, 4];
      });
      final word = await const WordSegmenter().wordAt('天色漸暗', 3);
      expect(word, const ChapterTextRange(2, 4));
    });

    test('原生端沒給詞或結果不含長按位置時退回單一字元', () async {
      messenger.setMockMethodCallHandler(channel, (call) async => null);
      expect(
        await const WordSegmenter().wordAt('天色漸暗', 1),
        const ChapterTextRange(1, 2),
      );
      messenger.setMockMethodCallHandler(channel, (call) async => <int>[0, 1]);
      expect(
        await const WordSegmenter().wordAt('天色漸暗', 3),
        const ChapterTextRange(3, 4),
      );
    });

    test('原生端不存在時退回單一字元，surrogate pair 不拆開', () async {
      const text = 'a😀b';
      expect(
        await const WordSegmenter().wordAt(text, 2),
        const ChapterTextRange(1, 3),
      );
      expect(WordSegmenter.characterAt(text, 1), const ChapterTextRange(1, 3));
      expect(WordSegmenter.characterAt(text, 3), const ChapterTextRange(3, 4));
    });
  });

  group('選字選單', () {
    Future<SelectionService> pumpSelected(
      WidgetTester tester, {
      ValueChanged<ReaderTextSelection>? onHide,
      ValueChanged<ReaderTextSelection>? onReplace,
      ValueChanged<ReaderTextSelection>? onBookmark,
      ValueChanged<ReaderTextSelection>? onHighlight,
      ValueChanged<ReaderLocation>? onReadAloud,
      Future<void> Function(String text) shareText = _ignoreShare,
      LineBox box = const LineBox(left: 100, top: 300, right: 140, bottom: 320),
    }) async {
      final chapter = _chapter();
      final start = chapter.displayText.indexOf('城門');
      final service = SelectionService()
        ..select(
          ReaderTextSelection(
            blocks: chapter,
            epoch: LayoutEpoch.initial,
            range: ChapterTextRange(start, start + 2),
          ),
        );
      addTearDown(service.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: ReaderTextSelectionLayer(
            selection: service,
            repaint: service,
            paintFor: (_, _) => (
              boxes: <LineBox>[box],
              startBox: box,
              endBox: box,
              chapterStartAbove: null,
              chapterEndBelow: null,
            ),
            caretAt: (_, _) => null,
            onHide: onHide,
            onReplace: onReplace,
            onBookmark: onBookmark,
            onHighlight: onHighlight,
            onReadAloud: onReadAloud,
            shareText: shareText,
            highlightColor: Colors.amber,
            child: const SizedBox.expand(),
          ),
        ),
      );
      return service;
    }

    testWidgets('列上只有複製、搜尋與隱藏，系統的文字處理 App 收在「⋮」裡', (tester) async {
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.processText,
        (call) async {
          calls.add(call);
          return switch (call.method) {
            'ProcessText.queryTextActions' => <String, String>{
              'translate': '翻譯',
              'dict': '字典',
            },
            _ => null,
          };
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.processText,
          null,
        ),
      );

      final service = await pumpSelected(tester, onHide: (_) {});
      await tester.pump();

      expect(find.text('複製'), findsOneWidget);
      expect(find.text('搜尋'), findsOneWidget);
      expect(find.text('隱藏'), findsOneWidget);
      expect(find.text('翻譯'), findsNothing);
      expect(find.text('字典'), findsNothing);

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      expect(find.text('複製'), findsNothing);
      expect(find.text('翻譯'), findsOneWidget);
      expect(find.text('字典'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      expect(find.text('複製'), findsOneWidget);
      expect(find.text('翻譯'), findsNothing);

      // 展開後改選別的字，選單回到收起的樣子。
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      final current = service.selection!;
      service.select(
        ReaderTextSelection(
          blocks: current.blocks,
          epoch: current.epoch,
          range: ChapterTextRange(current.range.start, current.range.end - 1),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('複製'), findsOneWidget);
      expect(find.text('翻譯'), findsNothing);
      service.select(current);
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('翻譯'));
      await tester.pump();

      expect(calls.last.method, 'ProcessText.processTextAction');
      expect(calls.last.arguments, <Object>['translate', '城門', true]);
      expect(service.active, isFalse);
    });

    void mockApps(WidgetTester tester, Map<String, String> apps) {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.processText,
        (call) async =>
            call.method == 'ProcessText.queryTextActions' ? apps : null,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.processText,
          null,
        ),
      );
    }

    void setView(WidgetTester tester, Size size) {
      tester.view
        ..physicalSize = size
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }

    testWidgets('窄視窗與放大字級時整排縮小，「⋮」仍在畫面內按得到', (tester) async {
      mockApps(tester, const {'translate': '翻譯'});
      setView(tester, const Size(200, 600));
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await pumpSelected(
        tester,
        onHide: (_) {},
        box: const LineBox(left: 80, top: 300, right: 120, bottom: 320),
      );
      await tester.pumpAndSettle();

      final more = tester.getRect(find.byIcon(Icons.more_vert));
      expect(more.right, lessThanOrEqualTo(200));
      expect(more.left, greaterThanOrEqualTo(0));
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      expect(find.text('翻譯'), findsOneWidget);
    });

    testWidgets('App 多到放不下時清單捲動，最後一個與返回鍵都按得到', (tester) async {
      mockApps(tester, {for (var i = 0; i < 10; i++) 'app$i': 'App $i'});
      setView(tester, const Size(393, 300));
      for (final (top, label) in const [(180.0, '選單在字上方'), (20.0, '選單在字下方')]) {
        await pumpSelected(
          tester,
          onHide: (_) {},
          box: LineBox(left: 100, top: top, right: 140, bottom: top + 20),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byIcon(Icons.more_vert));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull, reason: label);
        final back = tester.getRect(find.byIcon(Icons.arrow_back));
        expect(back.top, greaterThanOrEqualTo(0), reason: label);
        expect(back.bottom, lessThanOrEqualTo(300), reason: label);
        await tester.scrollUntilVisible(
          find.text('App 9'),
          40,
          scrollable: find.byType(Scrollable).last,
        );
        final last = tester.getRect(find.text('App 9'));
        expect(last.bottom, lessThanOrEqualTo(300), reason: label);
        await tester.tap(find.byIcon(Icons.arrow_back));
        await tester.pumpAndSettle();
        expect(find.text('複製'), findsOneWidget, reason: label);
      }
    });

    testWidgets('展開後比收起時窄的選單靠尾端對齊，「⋮」那一側不動', (tester) async {
      mockApps(tester, const {'a': '譯'});
      setView(tester, const Size(393, 852));
      // 工具列的外框：圓角是工具列高的一半。
      final toolbar = find.byWidgetPredicate(
        (widget) =>
            widget is Material &&
            widget.borderRadius == const BorderRadius.all(Radius.circular(22)),
      );
      await pumpSelected(tester, onHide: (_) {});
      await tester.pumpAndSettle();
      final closed = tester.getRect(toolbar);

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      final open = tester.getRect(toolbar);
      expect(open.width, lessThan(closed.width));
      expect(open.right, moreOrLessEquals(closed.right));
    });

    testWidgets('手機上沒有文字處理 App 時，「⋮」裡仍有分享', (tester) async {
      await pumpSelected(tester, onHide: (_) {});
      await tester.pump();

      expect(find.text('隱藏'), findsOneWidget);
      expect(find.byIcon(Icons.more_vert), findsOneWidget);
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      expect(find.text('分享'), findsOneWidget);
    });

    testWidgets('按「隱藏」交出選到的字並收起選取', (tester) async {
      ReaderTextSelection? hidden;
      final service = await pumpSelected(
        tester,
        onHide: (selection) => hidden = selection,
      );

      await tester.tap(find.text('隱藏'));
      await tester.pump();

      expect(hidden?.text, '城門');
      expect(hidden?.inParagraphs.crossesIllustration, isFalse);
      expect(hidden?.inParagraphs.pieces, [
        (paragraphIndex: 0, paragraph: '天色漸暗，城門即將關閉。', start: 5, end: 7),
      ]);
      expect(service.active, isFalse);
    });

    testWidgets('沒有接上隱藏、替換與書籤時不顯示這幾個按鈕', (tester) async {
      await pumpSelected(tester);

      expect(find.text('複製'), findsOneWidget);
      expect(find.text('隱藏'), findsNothing);
      expect(find.text('替換'), findsNothing);
      expect(find.text('書籤'), findsNothing);
    });

    testWidgets('列上依序是複製、搜尋、隱藏、替換、書籤；按「替換」交出選到的字'
        '並收起選取', (tester) async {
      ReaderTextSelection? replaced;
      final service = await pumpSelected(
        tester,
        onHide: (_) {},
        onReplace: (selection) => replaced = selection,
        onBookmark: (_) {},
        onHighlight: (_) {},
      );
      await tester.pump();
      final order = ['複製', '搜尋', '隱藏', '替換', '書籤'];
      final xs = [
        for (final label in order) tester.getTopLeft(find.text(label)).dx,
      ];
      for (var i = 1; i < xs.length; i++) {
        expect(xs[i], greaterThan(xs[i - 1]), reason: order[i]);
      }

      await tester.tap(find.text('替換'));
      await tester.pump();
      expect(service.active, isFalse);
      final piece = replaced?.inParagraphs.pieces.single;
      expect(piece?.paragraph, '天色漸暗，城門即將關閉。');
      expect(piece?.start, 5);
      expect(piece?.end, 7);
    });

    testWidgets('「書籤」排在隱藏後面，按下在選到的字開頭留書籤並收起選取', (tester) async {
      ReaderTextSelection? marked;
      final service = await pumpSelected(
        tester,
        onHide: (_) {},
        onBookmark: (selection) => marked = selection,
      );

      expect(
        tester.getTopLeft(find.text('書籤')).dx,
        greaterThan(tester.getTopLeft(find.text('隱藏')).dx),
      );
      await tester.tap(find.text('書籤'));
      await tester.pump();

      expect(service.active, isFalse);
      // 書籤記在選到的字那一句的開頭，清單顯示整句。
      final bookmark = marked!.asBookmark;
      final chapter = _chapter();
      expect(bookmark.excerpt, '天色漸暗，城門即將關閉。');
      expect(bookmark.chapterTitle, '第一章');
      expect(bookmark.location.chapterIndex, 0);
      expect(bookmark.location.charOffset, chapter.displayText.indexOf('天色漸暗'));
      expect(bookmark.location.contentHash, 'hash');
      expect(bookmark.location.anchorAfter, startsWith('天色漸暗，城門'));
    });

    testWidgets('「標註」收在「⋮」裡（手機上沒有文字處理 App 也有「⋮」），排在'
        '文字處理 App 前面；按下畫上選到的字並收起選取', (tester) async {
      mockApps(tester, const {'a': '譯'});
      ReaderTextSelection? painted;
      final service = await pumpSelected(
        tester,
        onHide: (_) {},
        onBookmark: (_) {},
        onHighlight: (selection) => painted = selection,
      );
      await tester.pumpAndSettle();
      expect(find.text('標註'), findsNothing);

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.text('標註')).dy,
        lessThan(tester.getTopLeft(find.text('譯')).dy),
      );
      await tester.tap(find.text('標註'));
      await tester.pump();

      expect(service.active, isFalse);
      final highlight = painted!.asHighlight;
      expect(highlight.quote, '城門');
      expect(highlight.chapterTitle, '第一章');
      expect(
        highlight.location.charOffset,
        _chapter().displayText.indexOf('城門'),
      );
      expect(highlight.location.anchorAfter, startsWith('城門即將關閉'));
    });

    testWidgets('沒有文字處理 App 時，「⋮」裡有朗讀、標註與分享', (tester) async {
      await pumpSelected(tester, onHighlight: (_) {}, onReadAloud: (_) {});
      await tester.pump();
      expect(find.byIcon(Icons.more_vert), findsOneWidget);
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      expect(find.text('朗讀'), findsOneWidget);
      expect(find.text('標註'), findsOneWidget);
      expect(find.text('分享'), findsOneWidget);
    });

    testWidgets('「⋮」裡的「朗讀」交出選取開頭那一句的句首並收起選取', (tester) async {
      ReaderLocation? start;
      final service = await pumpSelected(
        tester,
        onReadAloud: (location) => start = location,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('朗讀'));
      await tester.pump();

      expect(service.active, isFalse);
      final display = _chapter().displayText;
      expect(start?.chapterIndex, 0);
      expect(start?.charOffset, display.indexOf('天色漸暗'));
    });

    testWidgets('「⋮」裡的「分享」交出選到的字，段落之間只換一行', (tester) async {
      final shared = <String>[];
      final service = await pumpSelected(
        tester,
        onHide: (_) {},
        shareText: (text) async => shared.add(text),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('分享'));
      await tester.pump();

      expect(shared, ['城門']);
      expect(service.active, isFalse);
    });

    test('a highlight drops the blanks at either end of the selection', () {
      const title = '第二章';
      const body = '　　雨停了。 ';
      const display = '$title\n\n$body';
      final start = title.length + 2;
      final chapter = ChapterBlocks(
        chapterIndex: 0,
        title: title,
        displayText: display,
        contentHash: 'h3',
        blocks: [
          _block(0, title, 0, paragraph: -1, isTitle: true),
          _block(1, body, start),
        ],
      );
      final highlight = ReaderTextSelection(
        blocks: chapter,
        epoch: LayoutEpoch.initial,
        range: ChapterTextRange(start, start + body.length),
      ).asHighlight;
      expect(highlight.quote, '雨停了。');
      expect(highlight.location.charOffset, display.indexOf('雨停了'));

      final blank = ReaderTextSelection(
        blocks: chapter,
        epoch: LayoutEpoch.initial,
        range: ChapterTextRange(start, start + 2),
      ).asHighlight;
      expect(blank.quote, isEmpty, reason: '全是空白不畫');
    });

    test('a bookmark covers the sentence the selection starts in, or the '
        'whole selection when it is longer', () {
      const title = '第二章';
      const body = '雨停了。他快步走過長街，回到書鋪。燈還亮著。';
      const display = '$title\n\n$body';
      final start = title.length + 2;
      final chapter = ChapterBlocks(
        chapterIndex: 0,
        title: title,
        displayText: display,
        contentHash: 'h2',
        blocks: [
          _block(0, title, 0, paragraph: -1, isTitle: true),
          _block(1, body, start),
        ],
      );
      ReaderTextSelection select(String from, String to) => ReaderTextSelection(
        blocks: chapter,
        epoch: LayoutEpoch.initial,
        range: ChapterTextRange(
          display.indexOf(from),
          display.indexOf(to) + to.length,
        ),
      );

      final word = select('長街', '長街').asBookmark;
      expect(word.excerpt, '他快步走過長街，回到書鋪。');
      expect(word.location.charOffset, display.indexOf('他快步'));

      final long = select('長街', '燈還').asBookmark;
      expect(long.excerpt, '他快步走過長街，回到書鋪。燈還');
    });

    test('朗讀從選取開頭那一句的句首開始', () {
      const title = '第二章';
      const body = '雨停了。他快步走過長街，回到書鋪。燈還亮著。';
      const display = '$title\n\n$body';
      final start = title.length + 2;
      final chapter = ChapterBlocks(
        chapterIndex: 0,
        title: title,
        displayText: display,
        contentHash: 'h4',
        blocks: [
          _block(0, title, 0, paragraph: -1, isTitle: true),
          _block(1, body, start),
        ],
      );
      final selection = ReaderTextSelection(
        blocks: chapter,
        epoch: LayoutEpoch.initial,
        range: ChapterTextRange(
          display.indexOf('長街'),
          display.indexOf('長街') + 2,
        ),
      );
      final location = selection.asSpeechStart;
      expect(location.chapterIndex, 0);
      expect(location.charOffset, display.indexOf('他快步'));
      expect(location.contentHash, 'h4');
    });
  });

  group('跨段的標註', () {
    ReaderHighlightMark mark(int start, String quote, {bool anchored = true}) =>
        (
          id: 1,
          location: ReaderLocation(chapterIndex: 0, charOffset: start),
          length: quote.replaceAll('\n', '').length,
          unanchoredQuote: anchored ? null : quote,
          color: HighlightColor.amber,
          style: HighlightStyle.fill,
        );

    ChapterBlocks chapterOf(List<String> paragraphs) {
      const title = '章';
      final display = '$title\n\n${paragraphs.join('\n\n')}';
      var offset = title.length + 2;
      return ChapterBlocks(
        chapterIndex: 0,
        title: title,
        displayText: display,
        contentHash: 'h',
        blocks: [
          _block(0, title, 0, paragraph: -1, isTitle: true),
          for (var i = 0; i < paragraphs.length; i++)
            _block(
              i + 1,
              paragraphs[i],
              (offset += i == 0 ? 0 : paragraphs[i - 1].length + 2),
              paragraph: i,
            ),
        ],
      );
    }

    test('正文沒變時畫到記下的那段字的結尾', () {
      final blocks = chapterOf(['甲乙丙', '丁戊']);
      final display = blocks.displayText;
      final start = display.indexOf('乙');
      final range = ReaderMarkGeometry.highlightRangeIn(
        mark(start, '乙丙\n\n丁'),
        blocks,
      )!;
      expect(display.substring(range.start, range.end), '乙丙\n\n丁');
    });

    test('分段和畫的時候不同時，段落分隔不算，仍畫到同一段字的結尾', () {
      final start = '章\n\n'.length + 1;
      // 畫的時候是兩段，現在接成一段。
      final joined = chapterOf(['甲乙丙丁戊']);
      final range = ReaderMarkGeometry.highlightRangeIn(
        mark(start, '乙丙\n\n丁'),
        joined,
      )!;
      expect(joined.displayText.substring(range.start, range.end), '乙丙丁');
      // 畫的時候是一段，現在切成三段。
      final split = chapterOf(['甲乙', '丙', '丁戊']);
      final again = ReaderMarkGeometry.highlightRangeIn(
        mark(start, '乙丙丁'),
        split,
      )!;
      expect(
        split.displayText.substring(again.start, again.end),
        '乙\n\n丙\n\n丁',
      );
    });

    // 從 Legado 備份轉來的標註沒有錨點：記下的位置照 Legado 的算法（算進章名
    // 與段首縮排），原文可能被讀者在 Legado 改過。
    group('沒有錨點的（從 Legado 轉來的）', () {
      test('記下的位置上就是原文時照它畫', () {
        final blocks = chapterOf(['甲乙丙', '丁戊']);
        final display = blocks.displayText;
        final range = ReaderMarkGeometry.highlightRangeIn(
          mark(display.indexOf('乙'), '乙丙', anchored: false),
          blocks,
        )!;
        expect(display.substring(range.start, range.end), '乙丙');
      });

      test('位置偏了時畫在附近同一段字上，段首縮排與換行不算', () {
        final blocks = chapterOf(['甲乙丙', '丁戊己庚', '辛壬']);
        final display = blocks.displayText;
        // Legado 的位置多算了章名與每段的縮排，落在後面幾個字。
        final range = ReaderMarkGeometry.highlightRangeIn(
          mark(display.indexOf('己'), '丙\n　　丁戊', anchored: false),
          blocks,
        )!;
        expect(display.substring(range.start, range.end), '丙\n\n丁戊');
      });

      test('同一段字出現好幾次時畫在離記下的位置最近的那一處', () {
        final blocks = chapterOf(['甲乙', '丙甲乙', '丁戊甲乙']);
        final display = blocks.displayText;
        final near = display.indexOf('丁');
        final range = ReaderMarkGeometry.highlightRangeIn(
          mark(near, '甲乙', anchored: false),
          blocks,
        )!;
        expect(range.start, display.lastIndexOf('甲乙'));
      });

      test('原文和畫面上的繁簡不同時照轉換後的寫法找', () {
        ChineseUtils.initializeFromDictionaryData([
          for (final path in ChineseUtils.dictionaryAssetPaths)
            File(path).readAsStringSync(),
        ]);
        // 預設簡轉繁：正文顯示成繁體，Legado 備份裡的原文是簡體。
        final traditional = chapterOf(['她的頭髮亂了', '風很大']);
        final shown = traditional.displayText;
        final range = ReaderMarkGeometry.highlightRangeIn(
          mark(shown.indexOf('頭'), '头发乱了', anchored: false),
          traditional,
        )!;
        expect(shown.substring(range.start, range.end), '頭髮亂了');
        // 讀者改成繁轉簡：正文是簡體，原文是繁體。
        final simplified = chapterOf(['她的头发乱了', '风很大']);
        final again = ReaderMarkGeometry.highlightRangeIn(
          mark(3, '頭髮亂了\n　　風', anchored: false),
          simplified,
        )!;
        expect(
          simplified.displayText.substring(again.start, again.end),
          '头发乱了\n\n风',
        );
      });

      test('那一章找不到這段字時不畫', () {
        final blocks = chapterOf(['甲乙丙', '丁戊']);
        expect(
          ReaderMarkGeometry.highlightRangeIn(
            mark(3, '讀者改過的字', anchored: false),
            blocks,
          ),
          isNull,
        );
      });
    });
  });

  group('跨段選取', () {
    const box = LineBox(left: 100, top: 500, right: 140, bottom: 520);

    Future<SelectionService> pumpLayer(
      WidgetTester tester, {
      ChapterBlocks? blocks,
      String from = '城門',
      String to = '城門',
      SelectionPaint Function()? paint,
      int? Function(Offset point)? caretAt,
      Future<bool> Function(double delta, bool Function() isWanted)?
      autoScrollBy,
      VoidCallback? onAutoScrollEnd,
      ValueChanged<ReaderTextSelection>? onHide,
      ValueChanged<ReaderTextSelection>? onReplace,
      Future<void> Function(String text) shareText = _ignoreShare,
    }) async {
      final chapter = blocks ?? _chapter();
      final display = chapter.displayText;
      final service = SelectionService()
        ..select(
          ReaderTextSelection(
            blocks: chapter,
            epoch: LayoutEpoch.initial,
            range: ChapterTextRange(
              display.indexOf(from),
              display.indexOf(to) + to.length,
            ),
          ),
        );
      addTearDown(service.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: ReaderTextSelectionLayer(
            selection: service,
            repaint: service,
            paintFor: (_, _) =>
                paint?.call() ??
                (
                  boxes: const <LineBox>[box],
                  startBox: box,
                  endBox: box,
                  chapterStartAbove: null,
                  chapterEndBelow: null,
                ),
            caretAt: (_, point) => caretAt?.call(point),
            autoScrollBy: autoScrollBy,
            onAutoScrollEnd: onAutoScrollEnd,
            onHide: onHide,
            onReplace: onReplace,
            shareText: shareText,
            highlightColor: Colors.amber,
            child: const SizedBox.expand(),
          ),
        ),
      );
      return service;
    }

    /// 按住結尾的把手（在那一行下緣右邊）、越過觸控門檻開始拖。
    Future<TestGesture> grabEnd(WidgetTester tester) async {
      final gesture = await tester.startGesture(
        Offset(box.right + 8, box.bottom + 12),
      );
      await gesture.moveBy(const Offset(0, 20));
      await tester.pump();
      return gesture;
    }

    testWidgets('兩端都在畫面外、反白佔滿畫面時，選單仍在畫面裡', (tester) async {
      await pumpLayer(
        tester,
        paint: () => (
          boxes: [
            for (var top = 0.0; top < 600; top += 20)
              LineBox(left: 10, top: top, right: 390, bottom: top + 20),
          ],
          startBox: null,
          endBox: null,
          chapterStartAbove: null,
          chapterEndBelow: null,
        ),
      );
      final screen = tester.getRect(find.byType(ReaderTextSelectionLayer));
      final copy = tester.getRect(find.text('複製'));
      expect(screen.contains(copy.topLeft), isTrue, reason: '$copy');
      expect(screen.contains(copy.bottomRight), isTrue, reason: '$copy');
      for (final edge in SelectionEdge.values) {
        expect(
          find.byKey(ValueKey<SelectionEdge>(edge)),
          findsNothing,
          reason: '兩端都不畫把手',
        );
      }
    });

    testWidgets('複製時段落之間只換一行', (tester) async {
      final copied = <Object?>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') copied.add(call.arguments);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await pumpLayer(tester, to: '長街');
      await tester.tap(find.text('複製'));
      await tester.pump();
      expect(copied, [
        {'text': '城門即將關閉。\n他快步走過長街'},
      ]);
    });

    testWidgets('分享時段落之間只換一行', (tester) async {
      final shared = <String>[];
      final service = await pumpLayer(
        tester,
        to: '長街',
        shareText: (text) async => shared.add(text),
      );
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('分享'));
      await tester.pump();

      expect(shared, ['城門即將關閉。\n他快步走過長街']);
      expect(service.active, isFalse);
    });

    testWidgets('跨過插圖時「隱藏」「替換」灰掉，按了不收掉選取', (tester) async {
      final chapter = _chapter();
      final second = chapter.displayText.indexOf('他快步');
      final withPicture = ChapterBlocks(
        chapterIndex: 0,
        title: chapter.title,
        displayText: chapter.displayText,
        contentHash: chapter.contentHash,
        blocks: [
          for (final block in chapter.blocks)
            if (block.blockIndex < 3) block,
          ChapterBlock(
            key: const BlockKey(chapterIndex: 0, blockIndex: 3),
            text: '',
            charRange: ChapterTextRange(second, second),
            sourceParagraphIndex: 1,
            illustration: const ReaderIllustration(
              offset: 0,
              src: 'a.png',
              path: 'a.png',
              pixelWidth: 10,
              pixelHeight: 10,
            ),
          ),
          _block(4, '他快步走過長街。', second, paragraph: 1),
        ],
      );
      var calls = 0;
      final service = await pumpLayer(
        tester,
        blocks: withPicture,
        to: '長街',
        onHide: (_) => calls++,
        onReplace: (_) => calls++,
      );
      await tester.tap(find.text('隱藏'));
      await tester.tap(find.text('替換'));
      await tester.pump();
      expect(calls, 0);
      expect(service.active, isTrue);
    });

    testWidgets('把手拖到正文區下緣往裡 40 以內時正文往下捲，越靠邊越快，放開就停並記下位置', (tester) async {
      final deltas = <double>[];
      var settled = 0;
      final display = _chapter().displayText;
      await pumpLayer(
        tester,
        caretAt: (_) => display.indexOf('關閉'),
        autoScrollBy: (delta, _) async {
          deltas.add(delta);
          return true;
        },
        onAutoScrollEnd: () => settled++,
      );
      final height = tester
          .getSize(find.byType(ReaderTextSelectionLayer))
          .height;
      final gesture = await grabEnd(tester);
      expect(deltas, isEmpty, reason: '離下緣還遠，不捲');

      await gesture.moveTo(Offset(box.right + 8, height - 30));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(deltas, isNotEmpty);
      final slow = deltas.last;
      expect(slow, greaterThan(0));
      // 進到往裡 40 那條線之後 10：推進 10 × 20 / 40 = 5，每秒 5 × 30。
      expect(slow, closeTo(5 * 30 * 0.016, 0.01));

      await gesture.moveTo(Offset(box.right + 8, height + 200));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      // 拖出正文區也最多算到 20。
      expect(deltas.last, closeTo(20 * 30 * 0.016, 0.01));

      await gesture.up();
      await tester.pump(const Duration(milliseconds: 16));
      final count = deltas.length;
      await tester.pump(const Duration(milliseconds: 100));
      expect(deltas, hasLength(count), reason: '放開就停');
      expect(settled, 1);
    });

    testWidgets('捲到這一章最後一行整行露出為止，不多捲', (tester) async {
      final deltas = <double>[];
      await pumpLayer(
        tester,
        paint: () => (
          boxes: const <LineBox>[box],
          startBox: box,
          endBox: box,
          chapterStartAbove: null,
          chapterEndBelow: 2,
        ),
        caretAt: (_) => null,
        autoScrollBy: (delta, _) async {
          deltas.add(delta);
          return true;
        },
      );
      final height = tester
          .getSize(find.byType(ReaderTextSelectionLayer))
          .height;
      final gesture = await grabEnd(tester);
      await gesture.moveTo(Offset(box.right + 8, height + 10));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(deltas, isNotEmpty);
      expect(deltas.every((delta) => delta <= 2), isTrue, reason: '$deltas');
      await gesture.up();
    });

    testWidgets('放開時還在排隊的那一下捲動作廢，做完才記閱讀位置', (tester) async {
      final pending = <Completer<bool>>[];
      final wanted = <bool Function()>[];
      var settled = 0;
      await pumpLayer(
        tester,
        caretAt: (_) => null,
        autoScrollBy: (delta, isWanted) {
          wanted.add(isWanted);
          final done = Completer<bool>();
          pending.add(done);
          return done.future;
        },
        onAutoScrollEnd: () => settled++,
      );
      final height = tester
          .getSize(find.byType(ReaderTextSelectionLayer))
          .height;
      final gesture = await grabEnd(tester);
      await gesture.moveTo(Offset(box.right + 8, height));
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));
      expect(pending, hasLength(1), reason: '一次只排一下');
      expect(wanted.single(), isTrue);
      pending.single.complete(true);
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));
      expect(pending, hasLength(2));

      await gesture.up();
      await tester.pump();
      expect(wanted.last(), isFalse, reason: '放開後排隊的那一下不捲');
      expect(settled, 0, reason: '最後一下還沒做完');
      pending.last.complete(false);
      await tester.pump();
      expect(settled, 1);
    });

    testWidgets('拖到正文區上緣往裡 40 以內時正文往上捲', (tester) async {
      final deltas = <double>[];
      final display = _chapter().displayText;
      await pumpLayer(
        tester,
        caretAt: (_) => display.indexOf('天色'),
        autoScrollBy: (delta, _) async {
          deltas.add(delta);
          return true;
        },
      );
      final gesture = await grabEnd(tester);
      await gesture.moveTo(Offset(box.right + 8, 0));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(deltas, isNotEmpty);
      expect(deltas.last, closeTo(-20 * 30 * 0.016, 0.01));
      await gesture.up();
    });

    testWidgets('這一章的最後一行整行在畫面上時就不再捲', (tester) async {
      final deltas = <double>[];
      final service = await pumpLayer(
        tester,
        paint: () => (
          boxes: const <LineBox>[box],
          startBox: box,
          endBox: box,
          chapterStartAbove: null,
          chapterEndBelow: 0,
        ),
        caretAt: (_) => 1 << 20,
        autoScrollBy: (delta, _) async {
          deltas.add(delta);
          return true;
        },
      );
      final height = tester
          .getSize(find.byType(ReaderTextSelectionLayer))
          .height;
      final gesture = await grabEnd(tester);
      await gesture.moveTo(Offset(box.right + 8, height + 10));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(service.selection!.range.end, _chapter().displayText.length);
      expect(deltas, isEmpty);
      await gesture.up();
    });

    testWidgets('拖著的那一端一時沒有框（還沒排好、捲出畫面）時拖曳不中斷', (tester) async {
      var hideEnd = false;
      var caret = 0;
      final display = _chapter().displayText;
      final service = await pumpLayer(
        tester,
        paint: () => (
          boxes: const <LineBox>[box],
          startBox: box,
          endBox: hideEnd ? null : box,
          chapterStartAbove: null,
          chapterEndBelow: null,
        ),
        caretAt: (_) => display.indexOf('即將') + caret,
      );
      final gesture = await grabEnd(tester);
      hideEnd = true;
      caret = 1;
      await gesture.moveBy(const Offset(0, 10));
      await tester.pump();
      caret = 3;
      await gesture.moveBy(const Offset(0, 10));
      await tester.pump();
      expect(service.selection!.text, '城門即將關');
      await gesture.up();
      await tester.pump();
    });
  });
}
