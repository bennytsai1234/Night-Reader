import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
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

  /// 這次開 App 用過的字型，與其中這次已經量過的。存著的表是上次開 App 量的
  /// （系統字型可能換過、可能是別台的備份），先拿來用，這次用到就再量一次。
  static final Set<String> _used = {};
  static final Set<String> _measuredThisRun = {};
  static final Map<String, TextStyle> _styles = {};
  static SharedPreferences? _prefs;
  static bool _settled = false;

  /// 量測結果每換一次加一；照字畫的骨架據此知道要重算。
  static int _revision = 0;

  /// 等畫面靜止去量的那一次；量完才排下一次。
  static Future<void>? _pending;

  /// 記憶體裡的表還沒成功寫進偏好設定（寫入失敗時，下次量完再寫）。
  static bool _unsaved = false;

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

  /// 開 App 的進場播完、畫面靜止了：量這次用過的字型。之後才用到的字型等
  /// 下一次畫面靜止再量（[_measureWhenStill]）。
  static Future<void> onLaunchSettled() async {
    if (!_measureEnabled) return;
    _settled = true;
    await _measure(_used.toList());
  }

  /// [style]（已合併預設字樣）的 [mark] 那一格空著的比例；還沒量過時 null。
  static PunctuationBlank? _blankOf(TextStyle style, String mark) {
    final key = _keyOf(style);
    if (_used.add(key)) _styles[key] = style;
    if (_settled && !_measuredThisRun.contains(key)) _measureWhenStill();
    return _tables[key]?[mark];
  }

  /// 這次用到、還沒量過的字型，等畫面靜止（沒有動畫、沒有要畫的幀）再量：
  /// 排字與掃像素在主執行緒，不和動畫擠同一幀（ADR 0037「等靜止再放」）。
  static void _measureWhenStill() {
    _pending ??= () async {
      final scheduler = SchedulerBinding.instance;
      var stillSince = DateTime.now();
      while (true) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        if (scheduler.hasScheduledFrame ||
            scheduler.transientCallbackCount > 0) {
          stillSince = DateTime.now();
        } else if (DateTime.now().difference(stillSince) >=
            const Duration(milliseconds: 400)) {
          break;
        }
      }
      await _measure([
        for (final key in _used)
          if (!_measuredThisRun.contains(key)) key,
      ]);
      _pending = null;
    }();
  }

  static String _keyOf(TextStyle style) => [
    style.fontFamily ?? '',
    ...?style.fontFamilyFallback,
    if ((style.fontWeight ?? FontWeight.w400).value >= 600) 'bold',
    if (style.locale case final locale?) locale.toLanguageTag(),
  ].join('|');

  static Future<void> _measure(List<String> keys) async {
    for (final key in keys) {
      final style = _styles[key];
      if (style == null) continue;
      _measuredThisRun.add(key);
      try {
        final table = await measure(style);
        if (!_sameTable(_tables[key], table)) {
          _tables[key] = table;
          _revision++;
          _unsaved = true;
        }
      } catch (error, stackTrace) {
        AppLog.e('量標點筆畫位置失敗: $error', error: error, stackTrace: stackTrace);
      }
    }
    await _save();
  }

  /// 量測結果只是讓骨架更準的快取：寫不進去只記一筆，記憶體裡照用，下次
  /// 量完再寫。
  static Future<void> _save() async {
    final prefs = _prefs;
    if (!_unsaved || prefs == null) return;
    try {
      final saved = await prefs.setString(
        _prefsKey,
        jsonEncode({
          for (final MapEntry(key: font, value: table) in _tables.entries)
            font: {
              for (final MapEntry(key: mark, value: blank) in table.entries)
                mark: blank.toJson(),
            },
        }),
      );
      if (saved) {
        _unsaved = false;
      } else {
        AppLog.w('標點筆畫位置沒有寫進偏好設定，下次量完再寫');
      }
    } catch (error) {
      AppLog.w('標點筆畫位置寫入失敗，下次量完再寫: $error');
    }
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
    _measuredThisRun.clear();
    _styles.clear();
    _prefs = null;
    _settled = false;
    _measureEnabled = measure;
    _pending = null;
    _unsaved = false;
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
/// 含「…」；行首、行尾的全形標點扣掉那一格空著的部分（[PunctuationInk]），
/// 每個字照它自己那一段的字樣（一段字裡可以有不同字級、字型）。
List<Rect> skeletonTextLines(TextPainter painter) {
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
  final last = lines.length - 1;
  return [
    for (final (index, line) in lines.indexed)
      _trimPunctuation(
        painter,
        text,
        line,
        lastVisible: painter.didExceedMaxLines && index == last,
      ),
  ];
}

Rect _trimPunctuation(
  TextPainter painter,
  String text,
  Rect line, {
  required bool lastVisible,
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
  // 超過最大行數的最後一行，後面接的不是換行就是放不下被截斷：收在「…」上，
  // 「…」的寬度併在最後一個看得見的字的格子裡，行尾不扣。後面接換行時這一行
  // 是完整的，照常扣。
  final ellipsized = lastVisible && (end >= text.length || text[end] != '\n');
  SkeletonGlyph? glyph(int offset) {
    final mark = text[offset];
    // 只有標點要看字框；其他字不扣，省下查字框。
    if (!PunctuationInk.marks.contains(mark)) return null;
    final boxes = painter.getBoxesForSelection(
      TextSelection(baseOffset: offset, extentOffset: offset + 1),
    );
    if (boxes.isEmpty) return null;
    final box = boxes.first.toRect();
    final style = _styleAt(painter.text!, offset);
    if (style == null) return null;
    return SkeletonGlyph(
      mark,
      box,
      style: style,
      fontSize: painter.textScaler.scale(style.fontSize ?? 14),
    );
  }

  return skeletonInkLine(
    line,
    first: glyph(start),
    last: ellipsized ? null : glyph(end - 1),
  );
}

/// 照 [Text] 的方式組出要排的字：疊在頁面的預設字樣上（[style] 不繼承時
/// 除外），套用系統的粗體與字距、字間距、行高覆寫。骨架量字都經過這裡，
/// 才會和換上來的 [Text] 排得一樣（[text] 是字，[child] 是 [Text.rich] 的那段）。
TextSpan skeletonTextSpan(
  BuildContext context, {
  String? text,
  InlineSpan? child,
  TextStyle? style,
}) {
  final defaults = DefaultTextStyle.of(context);
  var effective = style == null || style.inherit
      ? defaults.style.merge(style)
      : style;
  if (MediaQuery.boldTextOf(context)) {
    effective = effective.merge(const TextStyle(fontWeight: FontWeight.bold));
  }
  final span = TextSpan(
    style: effective,
    text: text,
    children: child == null ? null : [child],
  );
  final height = MediaQuery.maybeLineHeightScaleFactorOverrideOf(context);
  final letterSpacing = MediaQuery.maybeLetterSpacingOverrideOf(context);
  final wordSpacing = MediaQuery.maybeWordSpacingOverrideOf(context);
  if (height == null && letterSpacing == null && wordSpacing == null) {
    return span;
  }
  final override = TextStyle(
    height: height,
    letterSpacing: letterSpacing,
    wordSpacing: wordSpacing,
  );
  TextSpan apply(TextSpan span) => TextSpan(
    text: span.text,
    style: span.style?.merge(override) ?? override,
    locale: span.locale,
    children: [
      for (final child in span.children ?? const <InlineSpan>[])
        child is TextSpan && child.runtimeType == TextSpan
            ? apply(child)
            : child,
    ],
  );
  return apply(span);
}

/// [root] 裡第 [offset] 個字（UTF-16，佔位符算一個）照繼承合併後的字樣。
TextStyle? _styleAt(InlineSpan root, int offset) {
  var cursor = 0;
  TextStyle? visit(InlineSpan span, TextStyle? inherited) {
    final style = inherited?.merge(span.style) ?? span.style;
    switch (span) {
      case TextSpan(:final text, :final children):
        if (text != null) {
          if (offset < cursor + text.length) return style;
          cursor += text.length;
        }
        for (final child in children ?? const <InlineSpan>[]) {
          if (visit(child, style) case final found?) return found;
        }
      case PlaceholderSpan():
        if (offset == cursor) return style;
        cursor += 1;
    }
    return null;
  }

  return visit(root, null);
}

/// 一行頭尾的一個字：那個字、它的字框，和它照繼承合併後的字樣與縮放後的字級。
@immutable
final class SkeletonGlyph {
  const SkeletonGlyph(
    this.mark,
    this.box, {
    required this.style,
    required this.fontSize,
  });

  final String mark;
  final Rect box;
  final TextStyle style;
  final double fontSize;
}

/// 一行字的骨架長條 [line]，照行首、行尾的字縮到筆畫上：[first]、[last]
/// 是那一行第一個與最後一個字（字框和 [line] 同座標）。不是全形標點、那個字
/// 的字型還沒量過、或那一格被擠窄時不縮。筆畫的位置從字框左緣算，字距攤在
/// 字後面的空白（正文避頭尾）不算進長條。
Rect skeletonInkLine(Rect line, {SkeletonGlyph? first, SkeletonGlyph? last}) {
  ({double cell, PunctuationBlank blank})? measured(SkeletonGlyph? glyph) {
    if (glyph == null || glyph.fontSize <= 0) return null;
    if (!PunctuationInk.marks.contains(glyph.mark)) return null;
    final blank = PunctuationInk._blankOf(glyph.style, glyph.mark);
    if (blank == null) return null;
    final cell = blank.advance * glyph.fontSize;
    if (glyph.box.width < cell - 0.12 * glyph.fontSize) return null;
    return (cell: cell, blank: blank);
  }

  var left = line.left;
  var right = line.right;
  if (measured(first) case final m?) {
    left = math.max(left, first!.box.left + m.blank.left * m.cell);
  }
  if (measured(last) case final m?) {
    right = math.min(right, last!.box.left + (1 - m.blank.right) * m.cell);
  }
  // 只有一個標點時至少留半個字。
  final minimum = math.min(first?.fontSize ?? 14, last?.fontSize ?? 14) / 2;
  if (right - left < minimum) return line;
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
    this.style,
    this.maxLines,
    this.color,
  });

  final String text;

  /// 疊在頁面預設字樣上的字樣；null 時就是預設字樣（同 [Text]）。
  final TextStyle? style;

  /// 最多幾行；null 時照頁面預設字樣的（同 [Text]）。
  final int? maxLines;

  /// 長條的底色；null 時照骨架的樣子（[SkeletonBox]）。
  final Color? color;

  @override
  State<SkeletonText> createState() => _SkeletonTextState();
}

class _SkeletonTextState extends State<SkeletonText> {
  List<Object?>? _key;
  ({Size size, List<Rect> lines})? _laidOut;

  ({Size size, List<Rect> lines}) _layout(
    TextSpan span,
    TextScaler textScaler,
    DefaultTextStyle defaults,
    double maxWidth,
  ) {
    final locale = Localizations.maybeLocaleOf(context);
    final direction = Directionality.of(context);
    final maxLines = widget.maxLines ?? defaults.maxLines;
    final key = [
      span,
      textScaler,
      defaults.textHeightBehavior,
      defaults.textWidthBasis,
      locale,
      direction,
      maxLines,
      maxWidth,
      PunctuationInk._revision,
    ];
    final cached = _laidOut;
    if (cached != null && listEquals(_key, key)) return cached;
    final painter = TextPainter(
      text: span,
      textDirection: direction,
      textScaler: textScaler,
      textHeightBehavior: defaults.textHeightBehavior,
      textWidthBasis: defaults.textWidthBasis,
      locale: locale,
      maxLines: maxLines,
      ellipsis: maxLines == null ? null : '…',
    )..layout(maxWidth: maxWidth);
    // 和 Text 一樣大：一行放得下時是那一行的寬，換行或截斷時撐滿（頁面的
    // 預設字樣指定照最長一行算時照它）。長條的左右照筆畫，上下置中在那一行
    // 畫出來的字上：取那一行最寬的那一段字的字框中線。一行混了兩種字型時
    // （閱讀器資訊列先用標點字型、中文退到系統字型），行框的中線和字不在
    // 同一高度，差多少看這台手機的字型；刪節號這種窄的一小段來自另一個字型，
    // 不拿來定中線。
    final metrics = painter.computeLineMetrics();
    final ink = skeletonTextLines(painter);
    double bottomOf(int index) => index >= metrics.length - 1
        ? painter.height
        : metrics[index].baseline + metrics[index].descent;
    final widest = <int, Rect>{};
    for (final box in painter.getBoxesForSelection(
      TextSelection(baseOffset: 0, extentOffset: span.toPlainText().length),
    )) {
      final rect = box.toRect();
      if (rect.top >= painter.height || rect.width <= 0) continue;
      final index = metrics.indexWhere(
        (line) => rect.center.dy < line.baseline + line.descent,
      );
      if (index < 0) continue;
      final current = widest[index];
      if (current == null || rect.width > current.width) widest[index] = rect;
    }
    final result = (
      size: Size(painter.width, painter.height),
      lines: [
        for (final (index, line) in ink.indexed)
          switch (widest[index]) {
            final glyphs? => Rect.fromLTRB(
              line.left,
              glyphs.top,
              line.right,
              glyphs.bottom,
            ),
            null => Rect.fromLTRB(
              line.left,
              index == 0 ? 0 : bottomOf(index - 1),
              line.right,
              bottomOf(index),
            ),
          },
      ],
    );
    painter.dispose();
    _key = key;
    return _laidOut = result;
  }

  @override
  Widget build(BuildContext context) {
    final defaults = DefaultTextStyle.of(context);
    final span = skeletonTextSpan(
      context,
      text: widget.text,
      style: widget.style,
    );
    final textScaler = MediaQuery.textScalerOf(context);
    final barHeight =
        textScaler.scale(span.style?.fontSize ?? 14) * Skeleton.barHeightFactor;
    return LayoutBuilder(
      builder: (context, constraints) {
        final (:size, :lines) = _layout(
          span,
          textScaler,
          defaults,
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
                  child: SkeletonBox(
                    width: line.width,
                    height: barHeight,
                    color: widget.color,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
