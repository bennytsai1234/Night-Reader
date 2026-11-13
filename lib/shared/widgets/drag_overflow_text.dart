import 'package:flutter/material.dart';

/// A text label that retains its normal line layout when it fits, but lets the
/// reader drag horizontally to reveal the entire label when it would be
/// truncated. Scrolling is always manual; there is no marquee or timer.
///
/// Keep the original [Text] so multi-line labels remain unchanged unless the
/// actual available width and text scale would produce an ellipsis.
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
