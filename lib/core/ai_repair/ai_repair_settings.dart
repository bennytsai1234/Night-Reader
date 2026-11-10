import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 使用者自己的 AI 服務（ADR 0054）：OpenAI 相容的服務網址、金鑰、模型名稱
/// 與思考程度（[aiEfforts] 的值，空字串是服務預設、不送）。
typedef AiService = ({
  String baseUrl,
  String apiKey,
  String model,
  String effort,
});

/// 思考程度：送給服務的 `reasoning_effort` 與畫面上的名稱。空字串是不送、
/// 由服務決定（有的服務不認得這個參數，送了會報錯）。
const Map<String, String> aiEfforts = {
  '': '服務預設',
  'low': '低',
  'medium': '中',
  'high': '高',
};

/// AI 修書源的設定，存在偏好設定裡：備份帶著（備份收全部偏好設定），同步也
/// 帶著（`SettingsSync.keys`），和書源的登入資料一樣（ADR 0054）。
///
/// 網址、金鑰與模型存成一筆：分開存的話同步各自比新舊，兩台一台換了服務、
/// 一台換了金鑰時，會拼成「新服務的網址配舊服務的金鑰」，把金鑰送到別家。
class AiRepairSettings {
  AiRepairSettings([this._prefs]);

  static const serviceKey = 'ai_repair.service';

  /// 同步的設定（`SettingsSync`）。
  static const Set<String> syncedKeys = {serviceKey};

  SharedPreferences? _prefs;

  Future<SharedPreferences> _ensure() async =>
      _prefs ??= await SharedPreferences.getInstance();

  /// 填好的服務；網址或模型沒填就是 null。本機的服務（Ollama 這類）不用
  /// 金鑰，金鑰可以空著。
  Future<AiService?> service() async {
    final saved = await read();
    if (saved.baseUrl.isEmpty || saved.model.isEmpty) return null;
    return saved;
  }

  /// 畫面上填的內容，沒填的是空字串。
  Future<AiService> read() async {
    final raw = (await _ensure()).getString(serviceKey);
    Map<String, dynamic> json = const {};
    if (raw != null) {
      try {
        if (jsonDecode(raw) case final Map<String, dynamic> decoded) {
          json = decoded;
        }
      } on FormatException {
        // 讀不懂就當作沒填。
      }
    }
    String field(String name) => switch (json[name]) {
      final String value => value.trim(),
      _ => '',
    };
    final effort = field('effort');
    return (
      baseUrl: field('baseUrl'),
      apiKey: field('apiKey'),
      model: field('model'),
      effort: aiEfforts.containsKey(effort) ? effort : '',
    );
  }

  Future<void> save(AiService service) async {
    final prefs = await _ensure();
    final value = (
      baseUrl: service.baseUrl.trim(),
      apiKey: service.apiKey.trim(),
      model: service.model.trim(),
      effort: service.effort,
    );
    if (value.baseUrl.isEmpty && value.apiKey.isEmpty && value.model.isEmpty) {
      await prefs.remove(serviceKey);
      return;
    }
    await prefs.setString(
      serviceKey,
      jsonEncode({
        'baseUrl': value.baseUrl,
        'apiKey': value.apiKey,
        'model': value.model,
        if (value.effort.isNotEmpty) 'effort': value.effort,
      }),
    );
  }
}
