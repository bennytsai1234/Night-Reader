import 'package:shared_preferences/shared_preferences.dart';

/// App 更新的使用者選擇：按過「忽略此版」的版本，以及是否接收測試版。
class UpdatePreferences {
  UpdatePreferences({this._prefs});

  static const _ignoredKey = 'update.ignored_version';
  static const _betaKey = 'update.beta_channel';

  SharedPreferences? _prefs;

  Future<SharedPreferences> _ensure() async {
    return _prefs ??= await SharedPreferences.getInstance();
  }

  Future<bool> isIgnored(String version) async {
    final prefs = await _ensure();
    return prefs.getString(_ignoredKey) == version;
  }

  Future<void> ignore(String version) async {
    final prefs = await _ensure();
    await prefs.setString(_ignoredKey, version);
  }

  /// 是否接收測試版（GitHub 預發布版）更新，預設只收正式版。
  Future<bool> betaChannel() async {
    final prefs = await _ensure();
    return prefs.getBool(_betaKey) ?? false;
  }

  Future<void> setBetaChannel(bool enabled) async {
    final prefs = await _ensure();
    await prefs.setBool(_betaKey, enabled);
  }
}
