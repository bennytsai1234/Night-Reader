import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:night_reader/features/reader/features/tts/reader_tts_segmenter.dart';

import 'package:night_reader/features/reader/text_view/core/text_view_types.dart';
import 'package:night_reader/features/reader/session/reader_location.dart';

enum SelectionEdge { start, end }

/// 選取落在某一段正文裡的那部分：第幾段正文（`ReaderContent.paragraphs` 的
/// 序號）、那一段的字，與選到的部分在段內的位置。
typedef ParagraphPiece = ({
  int paragraphIndex,
  String paragraph,
  int start,
  int end,
});

/// 選取照正文段落切開（見 [ReaderTextSelection.inParagraphs]），交給上層
/// 對回原文。[contentHash] 是選取時畫面上那份正文的身分；[pieces] 照先後
/// 排、段落序號相連；[crossesIllustration] 是選取中間夾著插圖。
typedef ParagraphSelection = ({
  int chapterIndex,
  String contentHash,
  List<ParagraphPiece> pieces,
  bool crossesIllustration,
});

/// 在選取開頭留書籤要的東西（見 [ReaderTextSelection.asBookmark]）：位置
/// 已綁好那一章正文的錨點。
typedef SelectionBookmark = ({
  ReaderLocation location,
  String chapterTitle,
  String excerpt,
});

/// 把選到的字畫上標註要的東西（見 [ReaderTextSelection.asHighlight]）：
/// 開頭的位置已綁好那一章正文的錨點，[quote] 是畫到的字。
typedef SelectionHighlight = ({
  ReaderLocation location,
  String chapterTitle,
  String quote,
});

/// 選取在 viewport 上要畫的東西：看得到的那一段的字形框（每條視覺行一個）、
/// 開頭與結尾那個字的行框（不在畫面上或那一段還沒排好時是 null），以及這一
/// 章正文的頂端還在 viewport 上緣上面多遠、底端還在下緣下面多遠（0 或負的
/// 是已經整個露出來；還沒排到時是 null）：自動捲動最多捲到這裡。
typedef SelectionPaint = ({
  List<LineBox> boxes,
  LineBox? startBox,
  LineBox? endBox,
  double? chapterStartAbove,
  double? chapterEndBelow,
});

/// 正文上的一段選取。offset 是章內 displayText 的 UTF-16 位置；可以跨段，
/// 不出這一章的正文（章名不算）。兩端都停在字上：開頭不是段落分隔，結尾
/// 前一個不是段落分隔。
final class ReaderTextSelection {
  ReaderTextSelection({
    required this.blocks,
    required this.epoch,
    required this.range,
  }) : assert(!range.isEmpty),
       assert(blocks.displayText.codeUnitAt(range.start) != _lineFeed),
       assert(blocks.displayText.codeUnitAt(range.end - 1) != _lineFeed);

  /// 建立選取時的章節內容；章節重新切分或換內容後，這份參照就不再是
  /// 目前的 ChapterBlocks，選取隨之失效。
  final ChapterBlocks blocks;
  final LayoutEpoch epoch;
  final ChapterTextRange range;

  static const int _lineFeed = 0x0A;

  int get chapterIndex => blocks.chapterIndex;

  /// 選到的字，照正文原樣（段落之間空一行）。
  String get text => blocks.displayText.substring(range.start, range.end);

  /// 選取能延伸到的範圍：這一章第一段正文的開頭到最後一段的結尾。拖把手
  /// 時每一下都要用，同一份章節內容只算一次。
  ChapterTextRange get bounds => _bodies[blocks] ??= bodyRangeOf(blocks);

  static final Expando<ChapterTextRange> _bodies = Expando();

  /// [blocks] 的正文（章名、插圖不算）從第一段開頭到最後一段結尾；沒有
  /// 正文時是空範圍。
  static ChapterTextRange bodyRangeOf(ChapterBlocks blocks) {
    int? start;
    var end = 0;
    for (final block in blocks.blocks) {
      if (block.isTitle || block.isIllustration) continue;
      start ??= block.charRange.start;
      end = block.charRange.end;
    }
    return start == null
        ? const ChapterTextRange(0, 0)
        : ChapterTextRange(start, end);
  }

  /// 選取中間夾著插圖（插圖在選到的兩個字之間）。
  bool get crossesIllustration => blocks.blocks.any(
    (block) =>
        block.isIllustration &&
        range.start < block.charRange.start &&
        block.charRange.start < range.end,
  );

  /// 選取照正文段落切開，每段選到的部分各一份；交給上層對回原文。
  ParagraphSelection get inParagraphs {
    final pieces = <ParagraphPiece>[];
    int? paragraphIndex;
    ChapterTextRange? paragraph;
    void flush() {
      final current = paragraph;
      if (paragraphIndex == null || current == null) return;
      final start = math.max(range.start, current.start);
      final end = math.min(range.end, current.end);
      if (end > start) {
        pieces.add((
          paragraphIndex: paragraphIndex,
          paragraph: blocks.displayText.substring(current.start, current.end),
          start: start - current.start,
          end: end - current.start,
        ));
      }
    }

    for (final block in blocks.blocks) {
      if (block.isIllustration ||
          block.isTitle ||
          block.sourceParagraphIndex < 0) {
        continue;
      }
      if (block.sourceParagraphIndex != paragraphIndex) {
        flush();
        paragraphIndex = block.sourceParagraphIndex;
        paragraph = block.charRange;
      } else {
        paragraph = ChapterTextRange(paragraph!.start, block.charRange.end);
      }
    }
    flush();
    return (
      chapterIndex: chapterIndex,
      contentHash: blocks.contentHash,
      pieces: pieces,
      crossesIllustration: crossesIllustration,
    );
  }

  /// 在選取開頭那一句留書籤：書籤記在那一句的開頭（跳回時從整句讀起），
  /// 清單上從那一句開頭顯示到選取結尾（選得比一句短時顯示整句）。句子照
  /// 朗讀的分句、在開頭所在的那一段裡切。位置和閱讀進度同一套（章內第幾
  /// 個字，綁上這一章正文的身分與前後原文）。
  SelectionBookmark get asBookmark {
    final sentence = _sentenceAtStart;
    final start = sentence.start;
    final end = math.max(range.end, sentence.end);
    return (
      location: ReaderLocation(chapterIndex: chapterIndex, charOffset: start)
          .withContentIdentity(
            contentHash: blocks.contentHash,
            displayText: blocks.displayText,
          ),
      chapterTitle: blocks.title,
      excerpt: blocks.displayText.substring(start, end).trim(),
    );
  }

  /// 選字「朗讀」的起點：選取開頭那一句的句首。分句與書籤 [asBookmark]
  /// 同一套（朗讀的分句，在開頭所在的那一段裡切）。
  ReaderLocation get asSpeechStart {
    final sentence = _sentenceAtStart;
    return ReaderLocation(
      chapterIndex: chapterIndex,
      charOffset: sentence.start,
    ).withContentIdentity(
      contentHash: blocks.contentHash,
      displayText: blocks.displayText,
    );
  }

  /// 選取開頭所在那一句在 displayText 的範圍；開頭那一句切不出來時是空的
  /// 選取範圍。
  ChapterTextRange get _sentenceAtStart {
    final paragraph =
        blocks.sourceParagraphRange(
          blocks.blockForCharOffset(range.start).key,
        ) ??
        range;
    final paragraphText = blocks.displayText.substring(
      paragraph.start,
      paragraph.end,
    );
    final local = range.start - paragraph.start;
    for (final sentence in const ReaderTtsSegmenter().segment(
      text: paragraphText,
      chapterIndex: chapterIndex,
      startOffset: local,
    )) {
      if (sentence.startCharOffset > local) break;
      if (local < sentence.endCharOffset) {
        return ChapterTextRange(
          paragraph.start + sentence.startCharOffset,
          paragraph.start + sentence.endCharOffset,
        );
      }
    }
    return ChapterTextRange(range.start, range.start);
  }

  /// 把選到的字畫上標註：從選取開頭畫到結尾，頭尾的空白不算（全是空白時
  /// [SelectionHighlight.quote] 是空的）；跨段時段落分隔照正文原樣記。位置
  /// 和書籤同一套（[asBookmark]）。
  SelectionHighlight get asHighlight {
    final text = blocks.displayText;
    var start = range.start;
    var end = range.end;
    while (start < end && _isBlank(text.codeUnitAt(start))) {
      start++;
    }
    while (end > start && _isBlank(text.codeUnitAt(end - 1))) {
      end--;
    }
    // 選到的全是空白時 [quote] 是空的，不畫。
    return (
      location: ReaderLocation(
        chapterIndex: chapterIndex,
        charOffset: start,
      ).withContentIdentity(contentHash: blocks.contentHash, displayText: text),
      chapterTitle: blocks.title,
      quote: text.substring(start, end),
    );
  }

  /// 半形與全形空白、換行。
  static bool _isBlank(int unit) =>
      unit == 0x20 || unit == 0x3000 || unit == _lineFeed || unit == 0x09;

  /// 把 [edge] 拖到 [offset]。夾在這一章的正文裡，落在段落分隔上時往字
  /// 那邊靠；越過另一端時兩端互換，且至少保留一個字（不拆開一個字的兩半）。
  /// 回傳新選取與目前拖動中的那一端。
  ({ReaderTextSelection selection, SelectionEdge edge}) moveEdge(
    SelectionEdge edge,
    int offset,
  ) {
    final text = blocks.displayText;
    final limits = bounds;
    final clamped = offset.clamp(limits.start, limits.end).toInt();
    final anchor = edge == SelectionEdge.start ? range.end : range.start;
    var start = math.min(clamped, anchor);
    var end = math.max(clamped, anchor);
    final moving = clamped < anchor
        ? SelectionEdge.start
        : clamped > anchor
        ? SelectionEdge.end
        : edge;
    while (start < end && text.codeUnitAt(start) == _lineFeed) {
      start++;
    }
    while (end > start && text.codeUnitAt(end - 1) == _lineFeed) {
      end--;
    }
    if (start >= end) {
      // 拖到另一端上（或兩端之間只剩段落分隔）：保留拖動那一側離另一端最近
      // 的一個字（段落分隔不算），不讓選取消失；那一側沒有字時取另一側的。
      var before = anchor;
      while (before > limits.start &&
          text.codeUnitAt(before - 1) == _lineFeed) {
        before--;
      }
      var after = anchor;
      while (after < limits.end && text.codeUnitAt(after) == _lineFeed) {
        after++;
      }
      final takeBefore = moving == SelectionEdge.start
          ? before > limits.start
          : after >= limits.end;
      if (takeBefore) {
        end = before;
        start = _isLowSurrogate(text, before - 1) ? before - 2 : before - 1;
      } else {
        start = after;
        end = _isHighSurrogate(text, after) ? after + 2 : after + 1;
      }
    }
    return (
      selection: ReaderTextSelection(
        blocks: blocks,
        epoch: epoch,
        range: ChapterTextRange(start, end),
      ),
      edge: moving,
    );
  }

  static bool _isHighSurrogate(String text, int index) =>
      index + 1 < text.length &&
      (text.codeUnitAt(index) & 0xFC00) == 0xD800 &&
      (text.codeUnitAt(index + 1) & 0xFC00) == 0xDC00;

  static bool _isLowSurrogate(String text, int index) =>
      index >= 1 &&
      (text.codeUnitAt(index) & 0xFC00) == 0xDC00 &&
      (text.codeUnitAt(index - 1) & 0xFC00) == 0xD800;
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
