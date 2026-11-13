import 'package:flutter/material.dart';

/// 文字放得下時照原本的行數與排版；放不下時前幾行照常換行，最後一行接著排
/// 剩下的字，讀者可以左右拖動看完，不會自動跑馬燈，也不把卡片撐寬
/// （docs/design/components.md「放不下的文字」）。
///
/// 以實際欄寬與字級量測 [Text]：沒有限制行數的文字照常換行，不會被改成可拖。
/// 混合字樣的 [Text.rich] 放不下時整段排成一行拖。骨架照同一套排法畫
/// （[dragOverflowCut]）。
class DragOverflowText extends StatelessWidget {
  const DragOverflowText({super.key, required this.child});

  final Text child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!constraints.hasBoundedWidth || constraints.maxWidth <= 0) {
          return child;
        }

        final defaults = DefaultTextStyle.of(context);
        final maxLines = child.maxLines ?? defaults.maxLines;
        if (maxLines == null) return child;
        final textAlign =
            child.textAlign ?? defaults.textAlign ?? TextAlign.start;
        final painter = TextPainter(
          text: TextSpan(
            style: defaults.style.merge(child.style),
            children: [child.textSpan ?? TextSpan(text: child.data)],
          ),
          textAlign: textAlign,
          textDirection: child.textDirection ?? Directionality.of(context),
          textScaler: child.textScaler ?? MediaQuery.textScalerOf(context),
          locale: child.locale ?? Localizations.maybeLocaleOf(context),
          strutStyle: child.strutStyle,
          textHeightBehavior:
              child.textHeightBehavior ?? defaults.textHeightBehavior,
          textWidthBasis: child.textWidthBasis ?? defaults.textWidthBasis,
          maxLines: maxLines,
          ellipsis: '…',
        )..layout(maxWidth: constraints.maxWidth);
        final exceeds = painter.didExceedMaxLines;
        final height = painter.height;
        final data = child.data;
        final cut = exceeds && data != null ? dragOverflowCut(painter) : 0;
        painter.dispose();
        if (!exceeds) return child;

        Text text(InlineSpan span, {int? maxLines, bool softWrap = true}) =>
            Text.rich(
              span,
              style: child.style,
              strutStyle: child.strutStyle,
              textAlign: child.textAlign,
              textDirection: child.textDirection,
              locale: child.locale,
              softWrap: softWrap,
              overflow: TextOverflow.clip,
              textScaler: child.textScaler,
              maxLines: maxLines,
              textWidthBasis: child.textWidthBasis,
              textHeightBehavior: child.textHeightBehavior,
              selectionColor: child.selectionColor,
            );

        final tail = data == null
            ? child.textSpan!
            : TextSpan(text: dragOverflowTail(data.substring(cut)));
        // 高度維持原本幾行的高，書卡、分組清單與漫畫換章分隔的上下內容
        // 不移位；行高取整差的零點幾像素裁掉。
        return Semantics(
          label: child.semanticsLabel ?? data ?? child.textSpan!.toPlainText(),
          excludeSemantics: true,
          child: SizedBox(
            height: height,
            child: ClipRect(
              child: OverflowBox(
                alignment: AlignmentDirectional.topStart,
                maxHeight: double.infinity,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (cut > 0)
                      text(
                        TextSpan(text: _trimBreak(data!.substring(0, cut))),
                        maxLines: maxLines - 1,
                      ),
                    SingleChildScrollView(
                      // 清單重用卡片時，新的字不沿用上一段的橫向位置。
                      key: ValueKey(tail.toPlainText()),
                      scrollDirection: Axis.horizontal,
                      physics: const ClampingScrollPhysics(),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minWidth: constraints.maxWidth,
                        ),
                        child: text(tail, softWrap: false),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// [painter]（照 [Text] 的行數上限排好、放不下）最後一行從第幾個字開始：
/// 那一行起的字都排在可拖的那一行。只有一行時是 0。
int dragOverflowCut(TextPainter painter) {
  final lines = painter.computeLineMetrics();
  if (lines.length <= 1) return 0;
  final last = lines.last;
  return painter
      .getLineBoundary(
        painter.getPositionForOffset(
          Offset(0, last.baseline - last.ascent + last.height / 2),
        ),
      )
      .start;
}

/// 可拖的那一行要排的字：換行符號換成空白，整段排在同一行。
String dragOverflowTail(String text) => text.replaceAll('\n', ' ');

/// 前幾行結尾的換行已經由分行表示，留著會多排一個空行。
String _trimBreak(String head) =>
    head.endsWith('\n') ? head.substring(0, head.length - 1) : head;
