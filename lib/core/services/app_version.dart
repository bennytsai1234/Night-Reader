import 'package:package_info_plus/package_info_plus.dart';

/// Single source of truth for app version info.
/// Wraps package_info_plus so callers never hardcode version strings.
class AppVersion {
  final String versionName;
  final int buildNumber;

  const AppVersion._({required this.versionName, required this.buildNumber});

  static AppVersion? _cached;

  /// Returns the cached version, or fetches it if not yet loaded.
  static Future<AppVersion> current() async {
    if (_cached != null) return _cached!;
    final info = await PackageInfo.fromPlatform();
    _cached = AppVersion._(
      versionName: info.version,
      buildNumber: int.tryParse(info.buildNumber) ?? 0,
    );
    return _cached!;
  }
}
