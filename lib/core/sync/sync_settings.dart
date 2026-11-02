import 'package:shared_preferences/shared_preferences.dart';

/// 這台手機選的同步空間（ADR 0039）。
enum SyncSpace { none, webdav }

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

  SharedPreferences? _prefs;

  Future<SharedPreferences> _ensure() async =>
      _prefs ??= await SharedPreferences.getInstance();

  Future<SyncSpace> space() async {
    final prefs = await _ensure();
    return switch (prefs.getString(_spaceKey)) {
      'webdav' => SyncSpace.webdav,
      _ => SyncSpace.none,
    };
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

  Future<void> useWebDav(WebDavAccount account) async {
    final prefs = await _ensure();
    await prefs.setString(_urlKey, account.url);
    await prefs.setString(_userKey, account.user);
    await prefs.setString(_passwordKey, account.password);
    await prefs.setString(_spaceKey, 'webdav');
    await prefs.remove(_lastSyncKey);
  }

  /// 停用同步；WebDAV 的帳號留著，再打開時不用重填。
  Future<void> disable() async {
    final prefs = await _ensure();
    await prefs.setString(_spaceKey, 'none');
    await prefs.remove(_lastSyncKey);
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
