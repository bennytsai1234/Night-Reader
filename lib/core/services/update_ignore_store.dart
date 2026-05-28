import 'package:shared_preferences/shared_preferences.dart';

/// 記住使用者按過「忽略此版」的版本，避免同版本重複彈窗。
class UpdateIgnoreStore {
  UpdateIgnoreStore({SharedPreferences? prefs}) : _prefs = prefs;

  static const _key = 'update.ignored_version';

  SharedPreferences? _prefs;

  Future<SharedPreferences> _ensure() async {
    return _prefs ??= await SharedPreferences.getInstance();
  }

  Future<bool> isIgnored(String version) async {
    final prefs = await _ensure();
    return prefs.getString(_key) == version;
  }

  Future<void> ignore(String version) async {
    final prefs = await _ensure();
    await prefs.setString(_key, version);
  }

  Future<void> clear() async {
    final prefs = await _ensure();
    await prefs.remove(_key);
  }
}
