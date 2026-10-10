import 'package:dio/dio.dart';
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

  /// 取得最新 release。回 `null` 表示確定沒新版或沒可安裝的 APK；
  /// 連線失敗或 API 回應異常時丟出例外，呼叫端才分得出「已是最新」與「檢查失敗」。
  Future<UpdateInfo?> checkLatest() async {
    final response = await _dio.get<Map<String, dynamic>>(_latestReleaseUrl);
    if (response.statusCode != 200 || response.data == null) {
      throw StateError('Release API 回應異常：${response.statusCode}');
    }
    final data = response.data!;
    final tagName = data['tag_name'] as String?;
    final body = (data['body'] as String?) ?? '';
    final assets = (data['assets'] as List?) ?? const [];
    final htmlUrl = (data['html_url'] as String?) ?? '';
    if (tagName == null || tagName.isEmpty) return null;

    Map<String, dynamic>? apkAsset;
    String? apkDownloadUrl;
    for (final rawAsset in assets) {
      if (rawAsset is! Map<String, dynamic>) continue;
      final name = rawAsset['name'];
      final downloadUrl = rawAsset['browser_download_url'];
      final normalizedDownloadUrl = downloadUrl is String
          ? downloadUrl.trim()
          : null;
      if (name is! String ||
          !name.toLowerCase().endsWith('.apk') ||
          normalizedDownloadUrl == null ||
          !_isHttpUrl(normalizedDownloadUrl)) {
        continue;
      }
      apkAsset = rawAsset;
      apkDownloadUrl = normalizedDownloadUrl;
      break;
    }
    if (apkAsset == null) return null;

    final current = await _currentVersionLoader();
    if (!_isNewer(tagName, current)) return null;

    return UpdateInfo(
      versionName: _stripV(tagName),
      tagName: tagName,
      updateLog: body,
      downloadUrl: apkDownloadUrl!,
      assetSize: (apkAsset['size'] as num?)?.toInt() ?? 0,
      releasePageUrl: htmlUrl,
    );
  }

  /// 版本比對 — 拆 semver 逐段比，無法解析的視為非新版。
  static bool _isNewer(String tagName, String current) {
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

  static bool _isHttpUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
  }
}

/// 把 GitHub 自動產生的發布說明（`--generate-notes`）整理成給使用者看的純文字：
/// 每個「* 標題 by @作者 in 連結」只留標題、前面加「•」；去掉「What's
/// Changed」標題、Full Changelog 連結、發版本身的提交與其他 Markdown 符號。
String releaseNotesForDisplay(String markdown) {
  final lines = <String>[];
  for (final raw in markdown.split('\n')) {
    var line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    if (line.contains('Full Changelog')) continue;
    if (line.startsWith('* ') || line.startsWith('- ')) {
      line = line.substring(2);
      line = line.replaceFirst(RegExp(r'\s+by @\S+\s+in\s+\S+$'), '');
      if (line.startsWith('release:')) continue;
      line = '• $line';
    }
    lines.add(line.replaceAll('**', '').replaceAll('`', ''));
  }
  return lines.join('\n');
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

  /// APK 預期大小（bytes），用於確認下載完整；0 表示 Release 沒標示。
  final int assetSize;

  /// GitHub Release 頁 URL，下載失敗時 fallback 到瀏覽器。
  final String releasePageUrl;
}
