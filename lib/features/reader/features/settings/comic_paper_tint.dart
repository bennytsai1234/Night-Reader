import 'package:flutter/painting.dart';

/// 漫畫閱讀器深色時的紙色（`docs/design/comics.md`「紙色」）：漫畫圖的每個點
/// 乘上這個顏色，白底變成它、黑線條照樣黑。淺色時一律照原色。
enum ComicPaperTint {
  original('原色', null),
  warmGray('暖灰', Color(0xFFC9C1B3)),
  xuan('宣紙', Color(0xFFD8CCAE)),
  deepGray('深灰', Color(0xFFA39C90));

  const ComicPaperTint(this.label, this.color);

  final String label;

  /// 乘上去的顏色；原色是 null，圖照原樣畫。
  final Color? color;

  static ComicPaperTint parse(String? name) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return original;
  }
}
