import 'package:night_reader/features/reader_v2/layout/reader_v2_style.dart';
import 'package:night_reader/features/reader_v2/viewport/reader_v2_visible_page_calculator.dart';

class ScrollReaderV2VisibleLine {
  const ScrollReaderV2VisibleLine({
    required this.worldTop,
    required this.worldBottom,
  });

  final double worldTop;
  final double worldBottom;
}

class ScrollReaderV2VisibleLineCalculator {
  const ScrollReaderV2VisibleLineCalculator();

  List<ScrollReaderV2VisibleLine> visibleTextLines({
    required ReaderV2VisiblePageCalculator visiblePages,
    required double readingY,
    required double viewportHeight,
    required ReaderV2Style renderStyle,
  }) {
    final visibleTop = readingY;
    final visibleBottom = readingY + viewportHeight;
    final lines = <ScrollReaderV2VisibleLine>[];
    for (final placement in visiblePages.visiblePages(
      readingY: readingY,
      viewportHeight: viewportHeight,
    )) {
      for (final line in placement.page.lines) {
        if (line.text.isEmpty) continue;
        final worldTop = placement.worldTop + renderStyle.paddingTop + line.top;
        final worldBottom =
            placement.worldTop + renderStyle.paddingTop + line.bottom;
        if (worldBottom <= visibleTop + 0.5 ||
            worldTop >= visibleBottom - 0.5) {
          continue;
        }
        lines.add(
          ScrollReaderV2VisibleLine(
            worldTop: worldTop,
            worldBottom: worldBottom,
          ),
        );
      }
    }
    lines.sort((a, b) => a.worldTop.compareTo(b.worldTop));
    return lines;
  }
}
