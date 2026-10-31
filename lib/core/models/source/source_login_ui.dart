import 'package:night_reader/core/models/source/lenient_json.dart';

/// 書源登入表單（`loginUi`）的一列，同 Legado 的 `RowUi`：輸入框
/// （[SourceLoginRowType.text]、[SourceLoginRowType.password]）或按鈕
/// （[SourceLoginRowType.button]）。Legado 不認得的種類（一些改版 App 的
/// `toggle`、`select`）和 Legado 一樣不顯示。
final class SourceLoginRow {
  const SourceLoginRow({
    required this.name,
    required this.type,
    this.action,
    this.style = SourceLoginRowStyle.defaults,
  });

  /// 輸入框的標題、按鈕上的字；也是表單內容（`result`、登入資訊）的鍵。
  final String name;
  final SourceLoginRowType type;

  /// 按鈕按下時執行的書源 JS，或用手機瀏覽器打開的網址。
  final String? action;
  final SourceLoginRowStyle style;

  bool get isField => type != SourceLoginRowType.button;

  /// 讀一列；不是物件或種類不認得時傳回 null。
  static SourceLoginRow? fromJson(Object? json) {
    if (json is! Map) return null;
    final type = switch ('${json['type'] ?? 'text'}') {
      'text' => SourceLoginRowType.text,
      'password' => SourceLoginRowType.password,
      'button' => SourceLoginRowType.button,
      _ => null,
    };
    if (type == null) return null;
    final action = json['action'];
    return SourceLoginRow(
      name: '${json['name'] ?? ''}',
      type: type,
      action: action == null ? null : '$action',
      style: SourceLoginRowStyle.fromJson(json['style']),
    );
  }
}

enum SourceLoginRowType { text, password, button }

/// 按鈕在一列裡怎麼排，同 Legado 的 `FlexChildStyle`（Android FlexboxLayout
/// 的子元件參數）。
final class SourceLoginRowStyle {
  const SourceLoginRowStyle({
    this.grow = 0,
    this.shrink = 1,
    this.basisPercent = -1,
    this.wrapBefore = false,
  });

  static const defaults = SourceLoginRowStyle();

  /// 同一列排完還有剩的寬度，照這個比例分給按鈕。
  final double grow;

  /// 同一列放不下時，照這個比例從按鈕身上扣寬度。
  final double shrink;

  /// 佔整列寬度的比例（0–1）；負數時照字的寬度。
  final double basisPercent;

  /// 一定從新的一列開始。
  final bool wrapBefore;

  static SourceLoginRowStyle fromJson(Object? json) {
    if (json is! Map) return defaults;
    double read(String key, double fallback) => switch (json[key]) {
      final num n => n.toDouble(),
      final String s => double.tryParse(s) ?? fallback,
      _ => fallback,
    };
    return SourceLoginRowStyle(
      grow: read('layout_flexGrow', 0),
      shrink: read('layout_flexShrink', 1),
      basisPercent: read('layout_flexBasisPercent', -1),
      wrapBefore: switch (json['layout_wrapBefore']) {
        final bool b => b,
        final String s => s == 'true',
        _ => false,
      },
    );
  }
}

/// `loginUi` 的三種情況。
sealed class SourceLoginUi {
  const SourceLoginUi();

  /// 讀書源的 `loginUi`。空的時候是 null（沒有表單，登入用網頁）。
  static SourceLoginUi? parse(String? raw) {
    final text = raw?.trim();
    if (text == null || text.isEmpty) return null;
    if (scriptOf(text) case final script?) return SourceLoginUiScript(script);
    try {
      return SourceLoginUiRows(rowsFromJson(decodeLenientJson(text)));
    } on FormatException catch (error) {
      return SourceLoginUiBroken(error.message);
    }
  }

  /// `@js:` 或 `<js>…</js>` 開頭時，取出裡面的程式。
  static String? scriptOf(String text) {
    if (text.startsWith('@js:')) return text.substring(4);
    if (text.toLowerCase().startsWith('<js>')) {
      final end = text.toLowerCase().lastIndexOf('</js>');
      return end > 4 ? text.substring(4, end) : text.substring(4);
    }
    return null;
  }

  /// 讀出表單的每一列；不是陣列時丟出 [FormatException]。
  static List<SourceLoginRow> rowsFromJson(Object? json) {
    if (json is! List) throw const FormatException('登入表單不是一串欄位');
    return [for (final item in json) ?SourceLoginRow.fromJson(item)];
  }
}

/// 寫好的表單。
final class SourceLoginUiRows extends SourceLoginUi {
  const SourceLoginUiRows(this.rows);
  final List<SourceLoginRow> rows;
}

/// 要執行書源的程式才拿得到的表單（一些改版 App 的寫法）：程式傳回表單的
/// JSON 字串或陣列。
final class SourceLoginUiScript extends SourceLoginUi {
  const SourceLoginUiScript(this.script);
  final String script;
}

/// 讀不懂的表單；[reason] 寫進日誌。
final class SourceLoginUiBroken extends SourceLoginUi {
  const SourceLoginUiBroken(this.reason);
  final String reason;
}
