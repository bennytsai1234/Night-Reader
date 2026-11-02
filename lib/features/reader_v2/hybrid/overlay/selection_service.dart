import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:night_reader/features/reader_v2/features/tts/reader_v2_tts_segmenter.dart';

import 'package:night_reader/features/reader_v2/hybrid/core/hybrid_types.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_location.dart';

enum SelectionEdge { start, end }

/// 一段選取在它所在正文段落裡的位置（見 [ReaderTextSelection.inParagraph]）。
typedef ParagraphSelection = ({
  int chapterIndex,
  int paragraphIndex,
  String paragraph,
  int start,
  int end,
});

/// 在選取開頭留書籤要的東西（見 [ReaderTextSelection.asBookmark]）：位置
/// 已綁好那一章正文的錨點。
typedef SelectionBookmark = ({
  ReaderV2Location location,
  String chapterTitle,
  String excerpt,
});

/// 正文上的一段選取。offset 是章內 displayText 的 UTF-16 位置，範圍不會
/// 超出長按時那個來源段落 [paragraph]。
final class ReaderTextSelection {
  ReaderTextSelection({
    required this.blocks,
    required this.epoch,
    required this.paragraph,
    required this.range,
  }) : assert(range.start >= paragraph.start && range.end <= paragraph.end),
       assert(!range.isEmpty);

  /// 建立選取時的章節內容；章節重新切分或換內容後，這份參照就不再是
  /// 目前的 ChapterBlocks，選取隨之失效。
  final ChapterBlocks blocks;
  final LayoutEpoch epoch;
  final HybridTextRange paragraph;
  final HybridTextRange range;

  int get chapterIndex => blocks.chapterIndex;

  String get text => blocks.displayText.substring(range.start, range.end);

  /// 選取落在第幾段正文（`ReaderV2Content.paragraphs` 的序號）、那一段的字，
  /// 與選取在段內的位置；交給上層對回原文。
  ParagraphSelection get inParagraph => (
    chapterIndex: chapterIndex,
    paragraphIndex: blocks.blocks
        .firstWhere((block) => block.charRange.start == paragraph.start)
        .sourceParagraphIndex,
    paragraph: blocks.displayText.substring(paragraph.start, paragraph.end),
    start: range.start - paragraph.start,
    end: range.end - paragraph.start,
  );

  /// 在選取開頭那一句留書籤：書籤記在那一句的開頭（跳回時從整句讀起），
  /// 清單上顯示整句，選得比一句長時顯示選到的全部。句子照朗讀的分句切，
  /// 不跨出這一段。位置和閱讀進度同一套（章內第幾個字，綁上這一章正文的
  /// 身分與前後原文）。
  SelectionBookmark get asBookmark {
    final paragraphText = blocks.displayText.substring(
      paragraph.start,
      paragraph.end,
    );
    final local = range.start - paragraph.start;
    var start = range.start;
    var end = range.end;
    for (final sentence in const ReaderV2TtsSegmenter().segment(
      text: paragraphText,
      chapterIndex: chapterIndex,
      startOffset: local,
    )) {
      if (sentence.startCharOffset > local) break;
      if (local < sentence.endCharOffset) {
        start = paragraph.start + sentence.startCharOffset;
        end = math.max(end, paragraph.start + sentence.endCharOffset);
        break;
      }
    }
    return (
      location: ReaderV2Location(chapterIndex: chapterIndex, charOffset: start)
          .withContentIdentity(
            contentHash: blocks.contentHash,
            displayText: blocks.displayText,
          ),
      chapterTitle: blocks.title,
      excerpt: blocks.displayText.substring(start, end).trim(),
    );
  }

  /// 把 [edge] 拖到 [offset]。夾在段落內；越過另一端時兩端互換，且至少
  /// 保留一個字。回傳新選取與目前拖動中的那一端。
  ({ReaderTextSelection selection, SelectionEdge edge}) moveEdge(
    SelectionEdge edge,
    int offset,
  ) {
    final clamped = offset.clamp(paragraph.start, paragraph.end).toInt();
    final anchor = edge == SelectionEdge.start ? range.end : range.start;
    int start;
    int end;
    SelectionEdge moving;
    if (clamped == anchor) {
      // 拖到另一端上：保留一個字，不讓選取消失。原選取非空，所以
      // anchor 往拖動那一側一定還有一個字。
      if (edge == SelectionEdge.start) {
        start = anchor - 1;
        end = anchor;
      } else {
        start = anchor;
        end = anchor + 1;
      }
      moving = edge;
    } else if (clamped < anchor) {
      start = clamped;
      end = anchor;
      moving = SelectionEdge.start;
    } else {
      start = anchor;
      end = clamped;
      moving = SelectionEdge.end;
    }
    return (
      selection: ReaderTextSelection(
        blocks: blocks,
        epoch: epoch,
        paragraph: paragraph,
        range: HybridTextRange(start, end),
      ),
      edge: moving,
    );
  }
}

final class SelectionService extends ChangeNotifier {
  ReaderTextSelection? _selection;

  ReaderTextSelection? get selection => _selection;

  bool get active => _selection != null;

  void select(ReaderTextSelection selection) {
    _selection = selection;
    notifyListeners();
  }

  void clear() {
    if (_selection == null) return;
    _selection = null;
    notifyListeners();
  }
}
