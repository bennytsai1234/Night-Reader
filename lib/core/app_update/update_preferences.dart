import 'package:shared_preferences/shared_preferences.dart';

/// App 更新的使用者選擇：按過「忽略此版」的版本、「稍後提醒」的時間、
/// 是否接收測試版、是否自動檢查，以及是否在不計流量的網路下先下載好新版。
class UpdatePreferences {
  UpdatePreferences({this._prefs, DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  static const _ignoredKey = 'update.ignored_version';
  static const _betaKey = 'update.beta_channel';
  static const _autoCheckKey = 'update.auto_check';
  static const _autoDownloadKey = 'update.auto_download_unmetered';
  static const _remindLaterKey = 'update.remind_later_at';

  /// 「在 Wi-Fi 下自動下載更新」沒設定過時的值。
  static const defaultAutoDownload = true;

  /// 按「稍後提醒」後，自動檢查多久內不再跳更新視窗。
  static const remindLaterCooldown = Duration(days: 7);

  SharedPreferences? _prefs;
  final DateTime Function() _clock;

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

  /// 記下按「稍後提醒」的時間，之後 [remindLaterCooldown] 內自動檢查不跳視窗。
  Future<void> remindLater() async {
    final prefs = await _ensure();
    await prefs.setInt(_remindLaterKey, _clock().millisecondsSinceEpoch);
  }

  /// 是否還在「稍後提醒」的冷卻期內。記下的時間晚於現在（調過系統時間）時
  /// 視為已過期，免得更新提示被無限期壓住。
  Future<bool> inRemindLaterCooldown() async {
    final prefs = await _ensure();
    final millis = prefs.getInt(_remindLaterKey);
    if (millis == null) return false;
    final elapsed = _clock().difference(
      DateTime.fromMillisecondsSinceEpoch(millis),
    );
    return !elapsed.isNegative && elapsed < remindLaterCooldown;
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

  /// 開啟 App 時是否自動檢查更新，預設開啟；手動檢查不受影響。
  Future<bool> autoCheck() async {
    final prefs = await _ensure();
    return prefs.getBool(_autoCheckKey) ?? true;
  }

  Future<void> setAutoCheck(bool enabled) async {
    final prefs = await _ensure();
    await prefs.setBool(_autoCheckKey, enabled);
  }

  /// 自動檢查發現新版時，是否在不計流量的網路下先在背景下載好。
  Future<bool> autoDownload() async {
    final prefs = await _ensure();
    return prefs.getBool(_autoDownloadKey) ?? defaultAutoDownload;
  }

  Future<void> setAutoDownload(bool enabled) async {
    final prefs = await _ensure();
    await prefs.setBool(_autoDownloadKey, enabled);
  }
}
