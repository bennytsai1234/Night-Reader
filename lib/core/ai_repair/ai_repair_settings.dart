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

/// 常用服務：選了填好服務網址。[model] 是夜讀實測過的模型（ADR 0054），
/// 選了一併填上；沒有的讓使用者從服務列出的模型選。
typedef AiServicePreset = ({String name, String baseUrl, String? model});

const List<AiServicePreset> aiServicePresets = [
  (
    name: 'OpenCode Go',
    baseUrl: 'https://opencode.ai/inference/go/openai/v1',
    model: 'deepseek-v4.1-flash',
  ),
  (name: 'DeepSeek', baseUrl: 'https://api.deepseek.com', model: null),
  (name: 'OpenRouter', baseUrl: 'https://openrouter.ai/api/v1', model: null),
  (name: 'OpenAI', baseUrl: 'https://api.openai.com/v1', model: null),
  (name: 'Ollama（本機）', baseUrl: 'http://localhost:11434/v1', model: null),
];

String _trimSlash(String url) {
  var value = url.trim();
  while (value.endsWith('/')) {
    value = value.substring(0, value.length - 1);
  }
  return value;
}

/// 網址是哪個常用服務；自己填的是 null。
AiServicePreset? aiServicePresetOf(String baseUrl) {
  final url = _trimSlash(baseUrl);
  for (final preset in aiServicePresets) {
    if (_trimSlash(preset.baseUrl) == url) return preset;
  }
  return null;
}

/// 這個服務的這個模型夜讀實測過（工具呼叫、思考放回對話都驗過）。
bool aiModelTested(String baseUrl, String model) =>
    aiServicePresetOf(baseUrl)?.model == model;

/// 整批修復同時交給 AI 修幾個網站：讀者接的服務能同時接幾個請求不一定，
/// 預設取保守的值，在 AI 服務頁可以調（使用者 2026-11-14 要的）。
const List<int> aiConcurrencyChoices = [1, 2, 3, 4, 6, 8];
const int aiDefaultConcurrency = 3;

/// AI 修書源的設定，存在偏好設定裡：備份帶著（備份收全部偏好設定），同步也
/// 帶著（`SettingsSync.keys`），和書源的登入資料一樣（ADR 0054）。
///
/// 網址、金鑰與模型存成一筆：分開存的話同步各自比新舊，兩台一台換了服務、
/// 一台換了金鑰時，會拼成「新服務的網址配舊服務的金鑰」，把金鑰送到別家。
class AiRepairSettings {
  AiRepairSettings([this._prefs]);

  static const serviceKey = 'ai_repair.service';
  static const concurrencyKey = 'ai_repair.concurrency';

  /// 同步的設定（`SettingsSync`）。
  static const Set<String> syncedKeys = {serviceKey, concurrencyKey};

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

  /// AI 找書用的服務（ADR 0060）：網址、金鑰、思考程度同修書源，模型是
  /// 「找書的模型」，留空就用修書源的模型。沒填好是 null。
  Future<AiService?> findService() async {
    final saved = await service();
    if (saved == null) return null;
    final model = await findModel();
    return model.isEmpty
        ? saved
        : (
            baseUrl: saved.baseUrl,
            apiKey: saved.apiKey,
            model: model,
            effort: saved.effort,
          );
  }

  /// 「找書的模型」；空字串是同修書源的模型。
  Future<String> findModel() async => _field(await _json(), 'findModel');

  Future<Map<String, dynamic>> _json() async {
    final raw = (await _ensure()).getString(serviceKey);
    if (raw == null) return const {};
    try {
      if (jsonDecode(raw) case final Map<String, dynamic> decoded) {
        return decoded;
      }
    } on FormatException {
      // 讀不懂就當作沒填。
    }
    return const {};
  }

  static String _field(Map<String, dynamic> json, String name) =>
      switch (json[name]) {
        final String value => value.trim(),
        _ => '',
      };

  /// 畫面上填的內容，沒填的是空字串。
  Future<AiService> read() async {
    final json = await _json();
    String field(String name) => _field(json, name);
    final effort = field('effort');
    return (
      baseUrl: field('baseUrl'),
      apiKey: field('apiKey'),
      model: field('model'),
      effort: aiEfforts.containsKey(effort) ? effort : '',
    );
  }

  /// 存服務；[findModel] 沒給時留著原本的「找書的模型」。兩個模型和網址、
  /// 金鑰存在同一筆（理由見類別說明）。
  Future<void> save(AiService service, {String? findModel}) async {
    final prefs = await _ensure();
    final value = (
      baseUrl: service.baseUrl.trim(),
      apiKey: service.apiKey.trim(),
      model: service.model.trim(),
      effort: service.effort,
    );
    final find = (findModel ?? await this.findModel()).trim();
    if (value.baseUrl.isEmpty &&
        value.apiKey.isEmpty &&
        value.model.isEmpty &&
        find.isEmpty) {
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
        if (find.isNotEmpty) 'findModel': find,
      }),
    );
  }

  /// 同時交給 AI 修幾個網站（[aiConcurrencyChoices] 之一）。
  Future<int> concurrency() async {
    final saved = (await _ensure()).getInt(concurrencyKey);
    return aiConcurrencyChoices.contains(saved) ? saved! : aiDefaultConcurrency;
  }

  Future<void> saveConcurrency(int value) async {
    final prefs = await _ensure();
    if (value == aiDefaultConcurrency) {
      await prefs.remove(concurrencyKey);
    } else {
      await prefs.setInt(concurrencyKey, value);
    }
  }
}
