import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:night_reader/core/services/app_log_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'skeleton.dart';

/// 全形標點的筆畫只佔那一格的一部分：開頭的括號與引號靠右、結尾的靠左，
/// 句讀依字型靠左或置中。骨架的長條要和換上來的字一樣長，行首與行尾落在
/// 標點上時要扣掉這段空白（DESIGN.md「骨架是真實畫面的影子」）。
///
/// 每個字型的位置都不一樣（2026-11-05 量：vivo 的系統字型「（」從 0.68 格
/// 才有筆畫、「，」靠左；Noto Sans CJK 繁中「，」置中；微軟正黑體的括號只空
/// 0.4 格），介面字型又是使用者選的，所以照這台手機實際的字型量：開 App
/// 進場播完、畫面靜止時，把每個標點畫一次、掃出筆畫的左右，存在這台手機
/// （不同步，備份照常帶著，到另一台下次開 App 會重量）。還沒量過的字型
/// 不扣，長條照字的格子畫。
final class PunctuationInk {
  PunctuationInk._();

  /// 量的標點：會出現在行首的開頭括號、引號，與會出現在行尾的結尾括號、
  /// 引號與句讀。
  static const String marks = '（「『《〈【〔［｛“‘）」』》〉】〕］｝”’，。、：；！？';

  static const String _prefsKey = 'skeleton_punctuation_ink';

  /// 字型 → 標點 → 那一格左右空著的比例與那一格的寬（都以字級為單位）。
  static final Map<String, Map<String, PunctuationBlank>> _tables = {};

  /// 測試用：直接放進一個字型的量測結果。
  @visibleForTesting
  static void setTableForTest(
    TextStyle style,
    Map<String, PunctuationBlank> table,
  ) {
    _tables[_keyOf(style)] = table;
    _revision++;
  }

  /// 這次開 App 用過的字型；進場播完後重量一次（系統字型可能換過）。
  static final Set<String> _used = {};
  static final Map<String, TextStyle> _styles = {};
  static SharedPreferences? _prefs;
  static bool _settled = false;

  /// 量測結果每換一次加一；照字畫的骨架據此知道要重算。
  static int _revision = 0;
  static Timer? _pending;

  /// 讀回存在這台手機的量測結果。開 App 讀完偏好設定後呼叫。
  static void restore(SharedPreferences prefs) {
    _prefs = prefs;
    final saved = prefs.getString(_prefsKey);
    if (saved == null) return;
    try {
      final json = jsonDecode(saved) as Map<String, dynamic>;
      for (final MapEntry(key: font, value: table) in json.entries) {
        _tables[font] = {
          for (final MapEntry(key: mark, value: values)
              in (table as Map<String, dynamic>).entries)
            mark: PunctuationBlank.fromJson(values as List<dynamic>),
        };
      }
    } catch (error) {
      AppLog.w('標點筆畫位置的紀錄讀不懂，重新量: $error');
      _tables.clear();
    }
  }

  /// 開 App 的進場播完、畫面靜止了：量這次用過的字型。之後才用到的新字型
  /// 隔一下再量。
  static Future<void> onLaunchSettled() async {
    if (!_measureEnabled) return;
    _settled = true;
    await _measure(_used.toList());
  }

  /// [style]（已合併預設字樣）的 [mark] 那一格空著的比例；還沒量過時 null。
  static PunctuationBlank? _blankOf(TextStyle style, String mark) {
    final key = _keyOf(style);
    if (_used.add(key)) _styles[key] = style;
    final table = _tables[key];
    if (table == null) {
      if (_settled) {
        _pending ??= Timer(const Duration(seconds: 2), () {
          _pending = null;
          unawaited(
            _measure([
              for (final k in _used)
                if (!_tables.containsKey(k)) k,
            ]),
          );
        });
      }
      return null;
    }
    return table[mark];
  }

  static String _keyOf(TextStyle style) => [
    style.fontFamily ?? '',
    ...?style.fontFamilyFallback,
    if ((style.fontWeight ?? FontWeight.w400).value >= 600) 'bold',
    if (style.locale case final locale?) locale.toLanguageTag(),
  ].join('|');

  static Future<void> _measure(List<String> keys) async {
    var changed = false;
    for (final key in keys) {
      final style = _styles[key];
      if (style == null) continue;
      try {
        final table = await measure(style);
        if (!_sameTable(_tables[key], table)) {
          _tables[key] = table;
          _revision++;
          changed = true;
        }
      } catch (error, stackTrace) {
        AppLog.e('量標點筆畫位置失敗: $error', error: error, stackTrace: stackTrace);
      }
    }
    final prefs = _prefs;
    if (!changed || prefs == null) return;
    await prefs.setString(
      _prefsKey,
      jsonEncode({
        for (final MapEntry(key: font, value: table) in _tables.entries)
          font: {
            for (final MapEntry(key: mark, value: blank) in table.entries)
              mark: blank.toJson(),
          },
      }),
    );
  }

  static bool _sameTable(
    Map<String, PunctuationBlank>? a,
    Map<String, PunctuationBlank> b,
  ) =>
      a != null &&
      a.length == b.length &&
      b.entries.every((entry) => a[entry.key] == entry.value);

  /// 照 [style] 的字族與粗細，把每個標點畫在一張圖上，掃出每一格有筆畫的
  /// 左右。測試直接呼叫。
  @visibleForTesting
  static Future<Map<String, PunctuationBlank>> measure(TextStyle style) async {
    const size = 48.0;
    const cell = size * 2;
    final paintStyle = TextStyle(
      fontFamily: style.fontFamily,
      fontFamilyFallback: style.fontFamilyFallback,
      fontWeight: style.fontWeight,
      fontStyle: style.fontStyle,
      // 正文指定繁中語系與全形字寬，Noto Sans CJK 依此選字形。
      locale: style.locale,
      fontFeatures: style.fontFeatures,
      fontSize: size,
      height: 1.25,
      color: const Color(0xFF000000),
    );
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final advances = <double>[];
    final chars = marks.split('');
    for (final (index, mark) in chars.indexed) {
      final painter = TextPainter(
        text: TextSpan(text: mark, style: paintStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      advances.add(painter.width);
      painter.paint(canvas, Offset(index * cell, 0));
      painter.dispose();
    }
    final width = (chars.length * cell).ceil();
    const height = (size * 1.25) ~/ 1 + 2;
    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);
    picture.dispose();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    if (bytes == null) return const {};
    final table = <String, PunctuationBlank>{};
    for (final (index, mark) in chars.indexed) {
      final x0 = (index * cell).round();
      var left = -1;
      var right = -1;
      for (var x = x0; x < x0 + cell; x++) {
        for (var y = 0; y < height; y++) {
          if (bytes.getUint8((y * width + x) * 4 + 3) > 40) {
            if (left < 0) left = x;
            right = x + 1;
            break;
          }
        }
      }
      final advance = advances[index];
      if (left < 0 || advance <= 0) continue;
      table[mark] = PunctuationBlank(
        left: (math.max(0, left - x0) / advance),
        right: (math.max(0, x0 + advance - right) / advance),
        advance: advance / size,
      );
    }
    return table;
  }

  /// 清掉量測結果與這次開 App 用過的字型。[measure] 為 false 時之後不量：
  /// 整個 App 的測試用測試字型，量出來的和手機無關，骨架照字的格子畫，
  /// 和照格子量內容的比對（`test/support/skeleton_match.dart`）對得上。
  @visibleForTesting
  static void resetForTest({bool measure = true}) {
    _tables.clear();
    _used.clear();
    _styles.clear();
    _prefs = null;
    _settled = false;
    _measureEnabled = measure;
    _pending?.cancel();
    _pending = null;
    _revision++;
  }

  static bool _measureEnabled = true;
}

/// 一個標點那一格左右空著的比例（以那一格的寬為單位），和量的時候那一格
/// 有多寬（以字級為單位）。
@immutable
final class PunctuationBlank {
  const PunctuationBlank({
    required this.left,
    required this.right,
    required this.advance,
  });

  factory PunctuationBlank.fromJson(List<dynamic> values) => PunctuationBlank(
    left: (values[0] as num).toDouble(),
    right: (values[1] as num).toDouble(),
    advance: (values[2] as num).toDouble(),
  );

  final double left;
  final double right;
  final double advance;

  List<double> toJson() => [
    for (final value in [left, right, advance])
      (value * 1000).roundToDouble() / 1000,
  ];

  @override
  bool operator ==(Object other) =>
      other is PunctuationBlank &&
      (other.left - left).abs() < 0.01 &&
      (other.right - right).abs() < 0.01 &&
      (other.advance - advance).abs() < 0.01;

  @override
  int get hashCode => Object.hash(left, right, advance);
}

/// [painter] 排好的字，每一行在骨架上的長條範圍（painter 座標，上下是那一行
/// 字形的高度）：從那一行第一個字的筆畫到最後一個字的筆畫。被刪節的那一行
/// 含「…」；行首、行尾的全形標點扣掉那一格空著的部分（[PunctuationInk]）。
/// [style] 是排版用的字樣（已合併預設字樣）。
List<Rect> skeletonTextLines(TextPainter painter, TextStyle style) {
  final text = painter.plainText;
  if (text.trim().isEmpty) return const [];
  // 逐字的框含被刪節那一行的「…」；`computeLineMetrics` 的行寬不含。
  final lines = <Rect>[];
  for (final box in painter.getBoxesForSelection(
    TextSelection(baseOffset: 0, extentOffset: text.length),
  )) {
    final rect = box.toRect();
    if (rect.top >= painter.height || rect.width <= 0) continue;
    final index = lines.indexWhere(
      (line) => (line.center.dy - rect.center.dy).abs() < rect.height / 2,
    );
    if (index < 0) {
      lines.add(rect);
    } else {
      lines[index] = lines[index].expandToInclude(rect);
    }
  }
  final fontSize = painter.textScaler.scale(style.fontSize ?? 14);
  if (fontSize <= 0) return lines;
  final lastLine = lines.length - 1;
  return [
    for (final (index, line) in lines.indexed)
      _trimPunctuation(
        painter,
        style,
        text,
        line,
        fontSize,
        // 被刪節的最後一行收在「…」上，不看原本那一行最後的字。
        trimEnd: !(painter.didExceedMaxLines && index == lastLine),
      ),
  ];
}

Rect _trimPunctuation(
  TextPainter painter,
  TextStyle style,
  String text,
  Rect line,
  double fontSize, {
  required bool trimEnd,
}) {
  final range = painter.getLineBoundary(
    painter.getPositionForOffset(line.center),
  );
  var start = range.start;
  var end = range.end;
  while (start < end && text[start].trim().isEmpty) {
    start++;
  }
  while (end > start && text[end - 1].trim().isEmpty) {
    end--;
  }
  if (end <= start) return line;
  (String, Rect)? glyph(int offset) {
    final mark = text[offset];
    // 只有標點要看字框；其他字不扣，省下查字框。
    if (!PunctuationInk.marks.contains(mark)) return null;
    final boxes = painter.getBoxesForSelection(
      TextSelection(baseOffset: offset, extentOffset: offset + 1),
    );
    return boxes.isEmpty ? null : (mark, boxes.first.toRect());
  }

  return skeletonInkLine(
    line,
    style: style,
    fontSize: fontSize,
    first: glyph(start),
    last: trimEnd ? glyph(end - 1) : null,
  );
}

/// 一行字的骨架長條 [line]，照行首、行尾的字縮到筆畫上：[first]、[last]
/// 是那一行第一個與最後一個字和它的字框（同 [line] 的座標）。不是全形標點、
/// 這個字型（[style]，已合併預設字樣）還沒量過、或那一格被擠窄時不縮。
/// 筆畫的位置從字框左緣算，字距攤在字後面的空白（正文避頭尾）不算進長條。
Rect skeletonInkLine(
  Rect line, {
  required TextStyle style,
  required double fontSize,
  (String, Rect)? first,
  (String, Rect)? last,
}) {
  ({double cell, PunctuationBlank blank})? measured((String, Rect)? glyph) {
    if (glyph == null || fontSize <= 0) return null;
    final (mark, box) = glyph;
    if (!PunctuationInk.marks.contains(mark)) return null;
    final blank = PunctuationInk._blankOf(style, mark);
    if (blank == null) return null;
    final cell = blank.advance * fontSize;
    if (box.width < cell - 0.12 * fontSize) return null;
    return (cell: cell, blank: blank);
  }

  var left = line.left;
  var right = line.right;
  if (measured(first) case final m?) {
    left = math.max(left, first!.$2.left + m.blank.left * m.cell);
  }
  if (measured(last) case final m?) {
    right = math.min(right, last!.$2.left + (1 - m.blank.right) * m.cell);
  }
  // 只有一個標點時至少留半個字。
  if (right - left < fontSize / 2) return line;
  return Rect.fromLTRB(left, line.top, right, line.bottom);
}

/// 一段字的骨架：照 [text] 以 [style] 在可用寬度裡排（[maxLines] 有給時
/// 照 [Text] 一樣截斷加「…」），每一行在那一行字的位置畫一條和字一樣高的
/// 圓角條，左右落在筆畫上（[skeletonTextLines]）；總高度與那段字相同，
/// 換成字時版面不動。空字串時只留一行的高度。
///
/// 和 [Text] 一樣，字、字樣、寬度與標點的量測都沒變時重建不重新排字：
/// 內容在骨架底下一幀建一段時，骨架跟著重建好幾次。
class SkeletonText extends StatefulWidget {
  const SkeletonText(
    this.text, {
    super.key,
    required this.style,
    this.maxLines,
  });

  final String text;
  final TextStyle style;
  final int? maxLines;

  @override
  State<SkeletonText> createState() => _SkeletonTextState();
}

class _SkeletonTextState extends State<SkeletonText> {
  List<Object?>? _key;
  ({Size size, List<Rect> lines})? _laidOut;

  ({Size size, List<Rect> lines}) _layout(
    TextStyle merged,
    TextScaler textScaler,
    TextHeightBehavior? heightBehavior,
    double maxWidth,
  ) {
    final locale = Localizations.maybeLocaleOf(context);
    final direction = Directionality.of(context);
    final key = [
      widget.text,
      merged,
      textScaler,
      heightBehavior,
      locale,
      direction,
      widget.maxLines,
      maxWidth,
      PunctuationInk._revision,
    ];
    final cached = _laidOut;
    if (cached != null && listEquals(_key, key)) return cached;
    final painter = TextPainter(
      text: TextSpan(text: widget.text, style: merged),
      textDirection: direction,
      textScaler: textScaler,
      textHeightBehavior: heightBehavior,
      locale: locale,
      maxLines: widget.maxLines,
      ellipsis: widget.maxLines == null ? null : '…',
    )..layout(maxWidth: maxWidth);
    // 和 Text 一樣大：一行放得下時是那一行的寬，換行或截斷時撐滿。
    final result = (
      size: Size(painter.width, painter.height),
      lines: skeletonTextLines(painter, merged),
    );
    painter.dispose();
    _key = key;
    return _laidOut = result;
  }

  @override
  Widget build(BuildContext context) {
    // 與 Text 相同：先合併頁面的預設字樣（字族、字距），再照系統字級放大。
    final defaults = DefaultTextStyle.of(context);
    final merged = defaults.style.merge(widget.style);
    final textScaler = MediaQuery.textScalerOf(context);
    final barHeight =
        textScaler.scale(merged.fontSize ?? 14) * Skeleton.barHeightFactor;
    return LayoutBuilder(
      builder: (context, constraints) {
        final (:size, :lines) = _layout(
          merged,
          textScaler,
          defaults.textHeightBehavior,
          constraints.maxWidth,
        );
        return SizedBox(
          width: size.width,
          height: size.height,
          child: Stack(
            children: [
              for (final line in lines)
                Positioned(
                  left: line.left,
                  top: line.center.dy - barHeight / 2,
                  child: SkeletonBox(width: line.width, height: barHeight),
                ),
            ],
          ),
        );
      },
    );
  }
}
