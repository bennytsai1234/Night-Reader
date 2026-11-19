import 'dart:async';

import 'package:flutter/material.dart';

import 'package:night_reader/features/reader/features/illustration/reader_illustration_viewer.dart';

import '../core/text_view_types.dart';
import '../measure/document_index.dart';
import '../paragraph/paragraph_cache.dart' show IllustrationPaint;
import '../pipeline/layout_pipeline.dart';
import '../text/word_segmenter.dart';
import 'highlight_marks.dart';
import 'reader_mark_layers.dart';
import 'selection_service.dart';

/// 正文上的點擊、長按與選字：點正文時先取消選取、點到已畫的標註就打開它，
/// 長按插圖打開大圖、長按字選一個詞，拖選取的把手。
///
/// 正文層（`ReaderTextView`）把手勢接過來（[handleTapUp]、
/// [handleLongPressStart]），選字圖層照 [selection]、[boxesFor]、[caretAt]
/// 畫；跳章、蓋紙、開始拖動時正文層呼叫 [clear]。排版與捲動位置透過建構時
/// 給的查詢讀。
final class ReaderTextTouch {
  ReaderTextTouch({
    required this._pipeline,
    required this._documentIndex,
    required this._marks,
    required this._scrollOffset,
    required this._context,
    required this._mounted,
    required this._selectionAllowed,
    required this._highlights,
    required this._onHighlightTap,
    required this._onContentTapUp,
  });

  final LayoutPipeline Function() _pipeline;
  final DocumentIndex _documentIndex;
  final ReaderMarkGeometry _marks;

  /// 目前的捲動位置；捲動還沒接上時是還原要停的位置，兩者都沒有時是 null。
  final double? Function() _scrollOffset;

  /// 長按的觸感回饋與打開插圖大圖用。
  final BuildContext Function() _context;
  final bool Function() _mounted;

  /// 現在可以選字：開著選字、閱讀選單沒開。斷詞回來時再看一次。
  final bool Function() _selectionAllowed;
  final List<ReaderHighlightMark>? Function() _highlights;
  final ValueChanged<int>? Function() _onHighlightTap;
  final GestureTapUpCallback? Function() _onContentTapUp;

  /// 正文上的選取。
  final SelectionService selection = SelectionService();
  final WordSegmenter _wordSegmenter = const WordSegmenter();

  /// 每次長按或取消都換號；選詞要等原生斷詞回來，期間若已取消或又長按
  /// 別處，舊結果作廢。
  int _selectionRequest = 0;

  /// 拖把手時 viewport 座標 [point] 在選取段落內最近的游標位置。
  int? caretAt(ReaderTextSelection selection, Offset point) {
    final scrollOffset = _scrollOffset();
    if (scrollOffset == null) return null;
    return _pipeline().geometry.caretAt(
      selection,
      point.translate(0, scrollOffset),
    );
  }

  /// 選取在 viewport 上的字形框，每條視覺行一個。
  List<LineBox> boxesFor(ReaderTextSelection selection) {
    if (!_pipeline().geometry.isSelectionCurrent(selection)) {
      // 章節重新切分、換內容或樣式換代後，舊 offset 不再對應畫面。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_mounted() && identical(this.selection.selection, selection)) {
          clear();
        }
      });
      return const <LineBox>[];
    }
    return _marks.lineBoxes(
      selection.chapterIndex,
      selection.range.start,
      selection.range.end,
    );
  }

  /// 文件座標 [point] 上的插圖（落在圖上才算）；沒有時回傳 null。
  IllustrationPaint? _illustrationAt(Offset point) {
    final key = _documentIndex.blockAtOffset(point.dy);
    if (key == null) return null;
    final pipeline = _pipeline();
    final blocks = pipeline.blocksOf(key.chapterIndex);
    if (blocks == null ||
        key.blockIndex >= blocks.blocks.length ||
        !blocks.blocks[key.blockIndex].isIllustration) {
      return null;
    }
    final top = _documentIndex.topOf(key);
    final paint = pipeline.paragraphCache
        .acquireEntry(key, pipeline.epoch)
        ?.illustration;
    if (top == null || paint == null) return null;
    final rect = paint.box.rect.shift(
      Offset(pipeline.layoutSpec.textPaddingLeft, top),
    );
    return rect.contains(point) ? paint : null;
  }

  Future<void> handleLongPressStart(LongPressStartDetails details) async {
    final request = ++_selectionRequest;
    final scrollOffset = _scrollOffset();
    // 長按插圖打開大圖，不選字（ADR 0050）。
    final illustration = scrollOffset == null
        ? null
        : _illustrationAt(details.localPosition.translate(0, scrollOffset));
    if (illustration != null) {
      selection.clear();
      final context = _context();
      unawaited(Feedback.forLongPress(context));
      unawaited(
        Navigator.of(context)
            .push(ReaderIllustrationViewer.route(illustration.path)),
      );
      return;
    }
    final hit = scrollOffset == null
        ? null
        : _pipeline().geometry.glyphAt(
            details.localPosition.translate(0, scrollOffset),
          );
    if (hit == null) {
      selection.clear();
      return;
    }
    unawaited(Feedback.forLongPress(_context()));
    final epoch = _pipeline().epoch;
    final paragraphText = hit.blocks.displayText.substring(
      hit.paragraph.start,
      hit.paragraph.end,
    );
    final word = await _wordSegmenter.wordAt(
      paragraphText,
      hit.offset - hit.paragraph.start,
    );
    if (!_mounted() ||
        request != _selectionRequest ||
        !_selectionAllowed() ||
        epoch != _pipeline().epoch ||
        !identical(_pipeline().blocksOf(hit.blocks.chapterIndex), hit.blocks)) {
      return;
    }
    selection.select(
      ReaderTextSelection(
        blocks: hit.blocks,
        epoch: epoch,
        paragraph: hit.paragraph,
        range: ChapterTextRange(
          hit.paragraph.start + word.start,
          hit.paragraph.start + word.end,
        ),
      ),
    );
  }

  /// 取消選取，等著斷詞的那一次長按也作廢。
  void clear() {
    _selectionRequest += 1;
    selection.clear();
  }

  /// 有選取時取消它並回傳 true（返回鍵先收起選取）。
  bool dismiss() {
    if (!selection.active) return false;
    clear();
    return true;
  }

  void handleTapUp(TapUpDetails details) {
    // 選取中點正文只取消選取，不觸發翻頁或叫出選單。
    if (selection.active) {
      clear();
      return;
    }
    // 點到已畫的標註：打開那個標註，不翻頁、不叫選單。
    if (_onHighlightTap() case final onHighlightTap?) {
      final id = _marks.highlightAt(_highlights(), details.localPosition);
      if (id != null) {
        onHighlightTap(id);
        return;
      }
    }
    _onContentTapUp()?.call(details);
  }

  void dispose() => selection.dispose();
}
