import 'package:shared_preferences/shared_preferences.dart';

/// 使用者自己的 AI 服務（ADR 0054）：OpenAI 相容的服務網址、金鑰與模型名稱。
typedef AiService = ({String baseUrl, String apiKey, String model});

/// AI 修書源的設定，存在偏好設定裡：備份帶著（備份收全部偏好設定），同步也
/// 帶著（`SettingsSync.keys`），和書源的登入資料一樣（ADR 0054）。
class AiRepairSettings {
  AiRepairSettings([this._prefs]);

  static const baseUrlKey = 'ai_repair.base_url';
  static const apiKeyKey = 'ai_repair.api_key';
  static const modelKey = 'ai_repair.model';

  /// 同步的設定（`SettingsSync`）。
  static const Set<String> syncedKeys = {baseUrlKey, apiKeyKey, modelKey};

  SharedPreferences? _prefs;

  Future<SharedPreferences> _ensure() async =>
      _prefs ??= await SharedPreferences.getInstance();

  /// 填好的服務；網址、金鑰或模型有一個沒填就是 null。本機的服務（Ollama
  /// 這類）不用金鑰，金鑰可以空著。
  Future<AiService?> service() async {
    final saved = await read();
    if (saved.baseUrl.isEmpty || saved.model.isEmpty) return null;
    return saved;
  }

  /// 畫面上填的內容，沒填的是空字串。
  Future<AiService> read() async {
    final prefs = await _ensure();
    return (
      baseUrl: prefs.getString(baseUrlKey)?.trim() ?? '',
      apiKey: prefs.getString(apiKeyKey)?.trim() ?? '',
      model: prefs.getString(modelKey)?.trim() ?? '',
    );
  }

  Future<void> save(AiService service) async {
    final prefs = await _ensure();
    Future<void> put(String key, String value) => value.trim().isEmpty
        ? prefs.remove(key)
        : prefs.setString(key, value.trim());
    await put(baseUrlKey, service.baseUrl);
    await put(apiKeyKey, service.apiKey);
    await put(modelKey, service.model);
  }
}
