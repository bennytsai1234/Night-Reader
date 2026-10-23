import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/reader_v2/hybrid/core/hybrid_types.dart';
import 'package:night_reader/features/reader_v2/hybrid/overlay/selection_service.dart';
import 'package:night_reader/features/reader_v2/hybrid/overlay/text_selection_overlay.dart';
import 'package:night_reader/features/reader_v2/hybrid/text/word_segmenter.dart';

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
    charRange: HybridTextRange(start, start + text.length),
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
    ReaderTextSelection selection() {
      final chapter = _chapter();
      final paragraph = chapter.sourceParagraphRange(
        const BlockKey(chapterIndex: 0, blockIndex: 1),
      )!;
      // 選「城門」。
      final start = chapter.displayText.indexOf('城門');
      return ReaderTextSelection(
        blocks: chapter,
        epoch: LayoutEpoch.initial,
        paragraph: paragraph,
        range: HybridTextRange(start, start + 2),
      );
    }

    test('拖動一端延伸選取，複製取 displayText', () {
      final base = selection();
      final moved = base.moveEdge(SelectionEdge.end, base.range.end + 2);
      expect(moved.selection.text, '城門即將');
      expect(moved.edge, SelectionEdge.end);
    });

    test('拖出段落時夾在段落邊界', () {
      final base = selection();
      final before = base.moveEdge(SelectionEdge.start, 0);
      expect(before.selection.range.start, base.paragraph.start);
      final after = base.moveEdge(SelectionEdge.end, 1 << 20);
      expect(after.selection.range.end, base.paragraph.end);
      expect(after.selection.text, '城門即將關閉。');
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
      expect(word, const HybridTextRange(2, 4));
    });

    test('原生端沒給詞或結果不含長按位置時退回單一字元', () async {
      messenger.setMockMethodCallHandler(channel, (call) async => null);
      expect(
        await const WordSegmenter().wordAt('天色漸暗', 1),
        const HybridTextRange(1, 2),
      );
      messenger.setMockMethodCallHandler(channel, (call) async => <int>[0, 1]);
      expect(
        await const WordSegmenter().wordAt('天色漸暗', 3),
        const HybridTextRange(3, 4),
      );
    });

    test('原生端不存在時退回單一字元，surrogate pair 不拆開', () async {
      const text = 'a😀b';
      expect(
        await const WordSegmenter().wordAt(text, 2),
        const HybridTextRange(1, 3),
      );
      expect(WordSegmenter.characterAt(text, 1), const HybridTextRange(1, 3));
      expect(WordSegmenter.characterAt(text, 3), const HybridTextRange(3, 4));
    });
  });

  group('選字選單', () {
    Future<SelectionService> pumpSelected(
      WidgetTester tester, {
      ValueChanged<ReaderTextSelection>? onHide,
    }) async {
      final chapter = _chapter();
      final start = chapter.displayText.indexOf('城門');
      final service = SelectionService()
        ..select(
          ReaderTextSelection(
            blocks: chapter,
            epoch: LayoutEpoch.initial,
            paragraph: chapter.sourceParagraphRange(
              const BlockKey(chapterIndex: 0, blockIndex: 1),
            )!,
            range: HybridTextRange(start, start + 2),
          ),
        );
      addTearDown(service.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: ReaderTextSelectionLayer(
            selection: service,
            repaint: service,
            boxesFor: (_) => const <HybridLineBox>[
              HybridLineBox(left: 100, top: 300, right: 140, bottom: 320),
            ],
            caretAt: (_, _) => null,
            onHide: onHide,
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
          paragraph: current.paragraph,
          range: HybridTextRange(current.range.start, current.range.end - 1),
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

    testWidgets('手機上沒有文字處理 App 時不顯示「⋮」', (tester) async {
      await pumpSelected(tester, onHide: (_) {});
      await tester.pump();

      expect(find.text('隱藏'), findsOneWidget);
      expect(find.byIcon(Icons.more_vert), findsNothing);
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
      expect(hidden?.inParagraph, (
        chapterIndex: 0,
        paragraphIndex: 0,
        paragraph: '天色漸暗，城門即將關閉。',
        start: 5,
        end: 7,
      ));
      expect(service.active, isFalse);
    });

    testWidgets('沒有接上隱藏時不顯示這個按鈕', (tester) async {
      await pumpSelected(tester);

      expect(find.text('複製'), findsOneWidget);
      expect(find.text('隱藏'), findsNothing);
    });
  });
}
