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

  static const _releasesUrl =
      'https://api.github.com/repos/bennytsai1234/night-reader/releases';

  final Dio _dio;
  final Future<String> Function() _currentVersionLoader;

  static Future<String> _defaultCurrentVersion() async {
    final info = await PackageInfo.fromPlatform();
    return info.version;
  }

  /// 取得比目前版本新、且附 APK 的 release。回 `null` 表示確定沒新版；
  /// 連線失敗或 API 回應異常時丟出例外，呼叫端才分得出「已是最新」與「檢查失敗」。
  ///
  /// [includeBeta] 為 false 時只看最新正式版（`/releases/latest` 不含預發布版）；
  /// 為 true 時從最近的 release 清單（含測試版）挑版本最高的一個。
  Future<UpdateInfo?> checkLatest({bool includeBeta = false}) async {
    final releases = includeBeta
        ? await _fetch<List<dynamic>>('$_releasesUrl?per_page=30')
        : [await _fetch<Map<String, dynamic>>('$_releasesUrl/latest')];
    final current = ReleaseVersion.tryParse(await _currentVersionLoader());
    if (current == null) return null;

    UpdateInfo? best;
    ReleaseVersion? bestVersion;
    for (final data in releases) {
      if (data is! Map<String, dynamic> || data['draft'] == true) continue;
      final info = _parseRelease(data);
      if (info == null) continue;
      final version = ReleaseVersion.tryParse(info.tagName);
      if (version == null || version.compareTo(current) <= 0) continue;
      if (bestVersion == null || version.compareTo(bestVersion) > 0) {
        best = info;
        bestVersion = version;
      }
    }
    return best;
  }

  Future<T> _fetch<T>(String url) async {
    final response = await _dio.get<T>(url);
    final data = response.data;
    if (response.statusCode != 200 || data == null) {
      throw StateError('Release API 回應異常：${response.statusCode}');
    }
    return data;
  }

  /// 把一筆 release 轉成 [UpdateInfo]；沒有 tag 或沒有可安裝的 APK 時回 `null`。
  static UpdateInfo? _parseRelease(Map<String, dynamic> data) {
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

    return UpdateInfo(
      versionName: tagName.replaceFirst(RegExp('^[vV]'), ''),
      tagName: tagName,
      updateLog: body,
      downloadUrl: apkDownloadUrl!,
      assetSize: (apkAsset['size'] as num?)?.toInt() ?? 0,
      releasePageUrl: htmlUrl,
    );
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

/// 發布版號：正式版 `0.3.3`，或 CI 每次合併到 `main` 發的測試版 `0.3.4-beta.2`。
///
/// 同一個 `x.y.z` 的測試版排在正式版之前，測試版之間依序號比。
class ReleaseVersion implements Comparable<ReleaseVersion> {
  const ReleaseVersion(this.major, this.minor, this.patch, {this.beta});

  static final _pattern = RegExp(
    r'^[vV]?(\d+)\.(\d+)\.(\d+)(?:-beta\.(\d+))?$',
  );

  final int major;
  final int minor;
  final int patch;

  /// 測試版序號；正式版為 `null`。
  final int? beta;

  /// 解析 tag 或 App 版號；認不得的格式（含其他預發布標記）回 `null`。
  static ReleaseVersion? tryParse(String value) {
    final match = _pattern.firstMatch(value.trim());
    if (match == null) return null;
    final beta = match.group(4);
    return ReleaseVersion(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
      beta: beta == null ? null : int.parse(beta),
    );
  }

  @override
  int compareTo(ReleaseVersion other) {
    for (final (a, b) in [
      (major, other.major),
      (minor, other.minor),
      (patch, other.patch),
    ]) {
      if (a != b) return a.compareTo(b);
    }
    if (beta == other.beta) return 0;
    if (beta == null) return 1;
    if (other.beta == null) return -1;
    return beta!.compareTo(other.beta!);
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

  /// 去掉 `v` 前綴的版本字串，例如 `0.2.72` 或 `0.3.4-beta.2`。
  final String versionName;

  /// 原始 tag，例如 `v0.2.72`。用於 `UpdatePreferences` 記住忽略的版本。
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
