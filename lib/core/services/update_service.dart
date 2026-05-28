import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:reader/core/services/app_log_service.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'http_client.dart';

/// AppUpdateService - 查 GitHub Release 的最新版本資訊。
///
/// 只負責 HTTP + 版本比對。SharedPreferences、UI、下載安裝都在他處。
class AppUpdateService {
  AppUpdateService({Dio? dio, Future<String> Function()? currentVersionLoader})
    : _dio = dio ?? HttpClient().client,
      _currentVersionLoader = currentVersionLoader ?? _defaultCurrentVersion;

  static const _latestReleaseUrl =
      'https://api.github.com/repos/bennytsai1234/night-reader/releases/latest';

  final Dio _dio;
  final Future<String> Function() _currentVersionLoader;

  static Future<String> _defaultCurrentVersion() async {
    final info = await PackageInfo.fromPlatform();
    return info.version;
  }

  /// 取得最新 release。回 `null` 表示沒新版、沒可安裝的 APK，或失敗。
  Future<UpdateInfo?> checkLatest() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(_latestReleaseUrl);
      if (response.statusCode != 200 || response.data == null) return null;

      final data = response.data!;
      final tagName = data['tag_name'] as String?;
      final body = (data['body'] as String?) ?? '';
      final assets = (data['assets'] as List?) ?? const [];
      final htmlUrl = (data['html_url'] as String?) ?? '';
      if (tagName == null || tagName.isEmpty) return null;

      final apkAsset = assets.cast<Map<String, dynamic>?>().firstWhere(
        (a) => a != null && (a['name'] as String?)?.endsWith('.apk') == true,
        orElse: () => null,
      );
      if (apkAsset == null) return null;

      final current = await _currentVersionLoader();
      if (!isNewer(tagName, current)) return null;

      return UpdateInfo(
        versionName: _stripV(tagName),
        tagName: tagName,
        updateLog: body,
        downloadUrl: apkAsset['browser_download_url'] as String? ?? '',
        assetSize: (apkAsset['size'] as num?)?.toInt() ?? 0,
        releasePageUrl: htmlUrl,
      );
    } catch (e, stack) {
      AppLog.e('Check update failed: $e', error: e, stackTrace: stack);
      return null;
    }
  }

  /// 版本比對 — 拆 semver 逐段比，無法解析的視為非新版。
  ///
  /// 公開供測試。
  @visibleForTesting
  static bool isNewer(String tagName, String current) {
    final newParts = _parseSemver(_stripV(tagName));
    final curParts = _parseSemver(_stripV(current));
    if (newParts == null || curParts == null) return false;
    for (var i = 0; i < 3; i++) {
      if (newParts[i] > curParts[i]) return true;
      if (newParts[i] < curParts[i]) return false;
    }
    return false;
  }

  static String _stripV(String v) =>
      v.startsWith('v') || v.startsWith('V') ? v.substring(1) : v;

  static List<int>? _parseSemver(String s) {
    final parts = s.split('.');
    if (parts.length < 3) return null;
    final ints = <int>[];
    for (var i = 0; i < 3; i++) {
      final n = int.tryParse(parts[i]);
      if (n == null) return null;
      ints.add(n);
    }
    return ints;
  }
}

/// UpdateInfo - GitHub Release 的精簡視圖。
class UpdateInfo {
  const UpdateInfo({
    required this.versionName,
    required this.tagName,
    required this.updateLog,
    required this.downloadUrl,
    required this.assetSize,
    required this.releasePageUrl,
  });

  /// 去掉 `v` 前綴的版本字串，例如 `0.2.72`。
  final String versionName;

  /// 原始 tag，例如 `v0.2.72`。用於 `UpdateIgnoreStore` 的 key。
  final String tagName;

  /// Release body（純文字 / Markdown，UI 直接顯示文字）。
  final String updateLog;

  /// APK 下載 URL。
  final String downloadUrl;

  /// APK 預期大小（bytes），用於同版本下載快取比對。
  final int assetSize;

  /// GitHub Release 頁 URL，下載失敗時 fallback 到瀏覽器。
  final String releasePageUrl;
}
