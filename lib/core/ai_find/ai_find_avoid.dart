import 'package:shared_preferences/shared_preferences.dart';

/// AI 找書「不想看的」清單：使用者不要 AI 推薦的類型（例如女頻、後宮），
/// 每次找書都送給 AI。一項一筆字串，跟著設定同步（`SettingsSync.keys`）。
abstract final class AiFindAvoid {
  static const String key = 'ai_find.avoid';

  static List<String> read(SharedPreferences prefs) =>
      prefs.getStringList(key) ?? const [];

  /// 清單空了就移除，同步照「回到預設值」處理。
  static Future<void> write(SharedPreferences prefs, List<String> items) =>
      items.isEmpty ? prefs.remove(key) : prefs.setStringList(key, items);

  /// 輸入框打的一段字拆成幾項：頓號、逗號、分號、斜線、換行都算分隔，
  /// 一次貼「女頻、後宮」是兩項；去掉空白與重複（含已在 [existing] 的）。
  static List<String> split(
    String text, {
    Iterable<String> existing = const [],
  }) {
    final seen = {...existing};
    return [
      for (final part in text.split(RegExp(r'[、,，;；/\n]')))
        if (part.trim() case final item when item.isNotEmpty && seen.add(item))
          item,
    ];
  }
}
