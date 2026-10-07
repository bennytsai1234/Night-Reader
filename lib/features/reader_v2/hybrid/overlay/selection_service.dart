import 'package:flutter/foundation.dart';

import 'package:night_reader/features/reader_v2/hybrid/core/hybrid_types.dart';

enum SelectionEdge { start, end }

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
