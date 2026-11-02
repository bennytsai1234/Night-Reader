import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// 這台手機選的同步空間（ADR 0039）。
enum SyncSpace { none, webdav, googleDrive }

/// WebDAV 的網址、帳號、密碼。
typedef WebDavAccount = ({String url, String user, String password});

/// 同步的設定與上次同步的結果，存在這台手機的偏好設定裡。
class SyncSettings {
  SyncSettings([this._prefs]);

  static const _spaceKey = 'sync.space';
  static const _urlKey = 'sync.webdav.url';
  static const _userKey = 'sync.webdav.user';
  static const _passwordKey = 'sync.webdav.password';
  static const _lastSyncKey = 'sync.last_success_at';

  /// 用 Google 雲端硬碟時登入的帳號（電子郵件），給畫面顯示與分辨換了帳號。
  static const _googleAccountKey = 'sync.google.account';

  /// 這台手機在同步裡的名字。只屬於這台：備份不帶（`BackupService`），
  /// 不然還原到另一台時兩台同名，閱讀統計會互相蓋掉。
  static const deviceIdKey = 'sync.device_id';

  SharedPreferences? _prefs;

  Future<SharedPreferences> _ensure() async =>
      _prefs ??= await SharedPreferences.getInstance();

  Future<SyncSpace> space() async {
    final prefs = await _ensure();
    return switch (prefs.getString(_spaceKey)) {
      'webdav' => SyncSpace.webdav,
      'google_drive' => SyncSpace.googleDrive,
      _ => SyncSpace.none,
    };
  }

  Future<String?> googleAccount() async =>
      (await _ensure()).getString(_googleAccountKey);

  Future<void> useGoogleDrive(String account) async {
    final prefs = await _ensure();
    await prefs.setString(_googleAccountKey, account);
    await prefs.setString(_spaceKey, 'google_drive');
    await prefs.remove(_lastSyncKey);
  }

  Future<WebDavAccount?> webDavAccount() async {
    final prefs = await _ensure();
    final url = prefs.getString(_urlKey);
    if (url == null || url.isEmpty) return null;
    return (
      url: url,
      user: prefs.getString(_userKey) ?? '',
      password: prefs.getString(_passwordKey) ?? '',
    );
  }

  /// 目前同步到哪裡（種類、網址、帳號）；沒有同步空間時是 null。上次同步
  /// 的紀錄屬於這個空間，換了（包括還原備份改掉設定）就作廢。
  Future<String?> identity() async {
    switch (await space()) {
      case SyncSpace.none:
        return null;
      case SyncSpace.webdav:
        final account = await webDavAccount();
        if (account == null) return null;
        return 'webdav\t${account.url.trim()}\t${account.user}';
      case SyncSpace.googleDrive:
        final account = await googleAccount();
        return account == null ? null : 'google_drive\t$account';
    }
  }

  Future<void> useWebDav(WebDavAccount account) async {
    final prefs = await _ensure();
    await prefs.setString(_urlKey, account.url);
    await prefs.setString(_userKey, account.user);
    await prefs.setString(_passwordKey, account.password);
    await prefs.setString(_spaceKey, 'webdav');
    await prefs.remove(_lastSyncKey);
  }

  /// 停用同步；WebDAV 的帳號留著，再打開時不用重填（Google 帳號由
  /// `SyncService.disable` 登出）。
  Future<void> disable() async {
    final prefs = await _ensure();
    await prefs.setString(_spaceKey, 'none');
    await prefs.remove(_lastSyncKey);
  }

  /// 這台手機的名字，第一次用到時隨機產生。
  Future<String> deviceId() async {
    final prefs = await _ensure();
    final saved = prefs.getString(deviceIdKey);
    if (saved != null && saved.isNotEmpty) return saved;
    final random = Random.secure();
    final id = [
      for (var i = 0; i < 16; i++)
        random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ].join();
    await prefs.setString(deviceIdKey, id);
    return id;
  }

  Future<DateTime?> lastSyncAt() async {
    final prefs = await _ensure();
    final millis = prefs.getInt(_lastSyncKey);
    return millis == null ? null : DateTime.fromMillisecondsSinceEpoch(millis);
  }

  Future<void> setLastSyncAt(DateTime time) async {
    final prefs = await _ensure();
    await prefs.setInt(_lastSyncKey, time.millisecondsSinceEpoch);
  }
}
