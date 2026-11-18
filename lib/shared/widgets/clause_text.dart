import 'package:flutter/material.dart';
import 'package:night_reader/core/services/ui_language.dart';

/// 多行說明照子句換行：一行排不下時，若斷點前 [_reach] 個字內有逗號、
/// 句號這類標點，改在標點後斷，不把一個詞拆在兩行；找不到標點、最後一行
/// 又只剩一兩個字時，往前多帶兩個字下去，不留孤字。
///
/// 中文沒有空白可斷，照最大寬度排會在詞中間斷開（「書源得重／新驗證」），
/// 也常把最後一兩個字擠到下一行。
class ClauseText extends StatelessWidget {
  const ClauseText(
    this.text, {
    super.key,
    this.style,
    this.textAlign = TextAlign.start,
    this.translate = true,
  });

  final String text;
  final TextStyle? style;
  final TextAlign textAlign;

  /// 整段是資料（書源名稱、書源傳來的訊息）時給 false，不跟介面語言
  /// 轉換（ADR 0066）。
  final bool translate;

  static const _reach = 8;
  static const _breakAfter = '，。；：、！？,.;:!?';
  static const _closing = '」』）》〉】”’)';

  @override
  Widget build(BuildContext context) {
    final effective = DefaultTextStyle.of(context).style.merge(style);
    final displayed = translate ? UiLanguageText.convert(context, text) : text;
    return LayoutBuilder(
      builder: (context, constraints) {
        final wrapped = constraints.maxWidth.isFinite
            ? wrapClauses(
                displayed,
                TextPainter(
                  textDirection: Directionality.of(context),
                  textScaler: MediaQuery.textScalerOf(context),
                  locale: Localizations.maybeLocaleOf(context),
                ),
                effective,
                constraints.maxWidth,
              )
            : displayed;
        return Text(wrapped, style: effective, textAlign: textAlign);
      },
    );
  }

  /// 回傳插好換行的文字；[painter] 用完會釋放。
  @visibleForTesting
  static String wrapClauses(
    String text,
    TextPainter painter,
    TextStyle style,
    double maxWidth,
  ) {
    final out = StringBuffer();
    final paragraphs = text.split('\n');
    for (var p = 0; p < paragraphs.length; p++) {
      if (p > 0) out.write('\n');
      var rest = paragraphs[p];
      while (rest.isNotEmpty) {
        painter
          ..text = TextSpan(text: rest, style: style)
          ..layout(maxWidth: maxWidth);
        final end = painter.getLineBoundary(const TextPosition(offset: 0)).end;
        if (end <= 0 || end >= rest.length) {
          out.write(rest);
          break;
        }
        final cut = _cutAt(rest, end);
        out
          ..write(rest.substring(0, cut).trimRight())
          ..write('\n');
        rest = rest.substring(cut).trimLeft();
      }
    }
    painter.dispose();
    return out.toString();
  }

  static int _cutAt(String line, int end) {
    if (_breakAfter.contains(line[end - 1]) ||
        _closing.contains(line[end - 1])) {
      return end;
    }
    for (var i = end - 2; i >= end - _reach && i > 0; i--) {
      if (_breakAfter.contains(line[i])) {
        var cut = i + 1;
        while (cut < end && _closing.contains(line[cut])) {
          cut++;
        }
        return cut;
      }
    }
    // 沒有標點可斷：剩下的只有一兩個字時往前多帶兩個，不留孤字。只動
    // 漢字，英文單字照原本的斷點。
    final remaining = line.length - end;
    if (remaining <= 2 && end > 4 && _isCjk(line, end - 2, end)) {
      return end - 2;
    }
    return end;
  }

  static bool _isCjk(String s, int from, int to) {
    for (var i = from; i < to; i++) {
      if (s.codeUnitAt(i) < 0x2E80) return false;
    }
    return true;
  }
}
