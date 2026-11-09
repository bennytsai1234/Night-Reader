import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 使用者自己的 AI 服務（ADR 0054）：OpenAI 相容的服務網址、金鑰與模型名稱。
typedef AiService = ({String baseUrl, String apiKey, String model});

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
    return (
      baseUrl: field('baseUrl'),
      apiKey: field('apiKey'),
      model: field('model'),
    );
  }

  Future<void> save(AiService service) async {
    final prefs = await _ensure();
    final value = (
      baseUrl: service.baseUrl.trim(),
      apiKey: service.apiKey.trim(),
      model: service.model.trim(),
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
      }),
    );
  }
}
