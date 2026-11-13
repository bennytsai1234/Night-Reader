import 'package:flutter/material.dart';

/// 文字未超出欄寬時保留原本的行數與排版；真的放不下時，讀者可以左右
/// 拖動查看完整文字，不會自動跑馬燈，也不把卡片撐寬。
///
/// 以實際欄寬與字級量測 [Text]，避免原本可正常換行的文字被改成單行。
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
        final painter = TextPainter(
          text: TextSpan(
            style: defaults.style.merge(child.style),
            children: [child.textSpan ?? TextSpan(text: child.data)],
          ),
          textAlign: child.textAlign ?? defaults.textAlign ?? TextAlign.start,
          textDirection: child.textDirection ?? Directionality.of(context),
          textScaler: child.textScaler ?? MediaQuery.textScalerOf(context),
          locale: child.locale ?? Localizations.maybeLocaleOf(context),
          strutStyle: child.strutStyle,
          textHeightBehavior:
              child.textHeightBehavior ?? defaults.textHeightBehavior,
          textWidthBasis: child.textWidthBasis ?? defaults.textWidthBasis,
          maxLines: child.maxLines ?? defaults.maxLines,
          ellipsis: '…',
        )..layout(maxWidth: constraints.maxWidth);
        final exceeds = painter.didExceedMaxLines;
        painter.dispose();

        if (!exceeds) return child;

        return SingleChildScrollView(
          // 清單重用卡片時，新書名不沿用上一個書名的橫向位置。
          key: ValueKey(child.textSpan?.toPlainText() ?? child.data),
          scrollDirection: Axis.horizontal,
          physics: const ClampingScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: Text.rich(
              child.textSpan ?? TextSpan(text: child.data),
              style: child.style,
              strutStyle: child.strutStyle,
              textAlign: child.textAlign,
              textDirection: child.textDirection,
              locale: child.locale,
              softWrap: false,
              overflow: TextOverflow.visible,
              textScaler: child.textScaler,
              semanticsLabel: child.semanticsLabel,
              textWidthBasis: child.textWidthBasis,
              textHeightBehavior: child.textHeightBehavior,
              selectionColor: child.selectionColor,
            ),
          ),
        );
      },
    );
  }
}
