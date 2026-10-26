import 'dart:convert';

import 'package:night_reader/core/engine/analyze_rule.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/source/explore_kind.dart';
import 'package:night_reader/core/services/app_log_service.dart';
import 'package:night_reader/core/storage/app_cache.dart';
import 'package:night_reader/core/utils/encoder_utils.dart';

/// ExploreUrlParser - 發現規則解析器 (對標 Android BookSource.getExploreKinds)
class ExploreUrlParser {
  static const String _cacheName = 'explore';

  /// 解析發現規則，不讀寫快取。
  static List<ExploreKind> parse(String? exploreUrl, {BookSource? source}) {
    if (exploreUrl == null || exploreUrl.isEmpty) return [];

    try {
      final resolved = _resolveSync(exploreUrl, source: source);
      return _parseResolvedValue(resolved);
    } catch (e) {
      AppLog.e('ExploreUrl 解析失敗: $e', error: e);
      return [ExploreKind(title: 'ERROR:${e.toString()}', url: e.toString())];
    }
  }

  /// 解析發現規則；JS 規則算出的分類存進快取，下次直接用（對標 Legado
  /// 的 exploreKinds 快取）。
  static Future<List<ExploreKind>> parseAsync(
    String? exploreUrl, {
    BookSource? source,
  }) async {
    if (exploreUrl == null || exploreUrl.isEmpty) return [];

    final normalizedExploreUrl = exploreUrl.trim();
    final useJsRuntime = _isJsExploreUrl(normalizedExploreUrl);
    final cachedResolved = useJsRuntime
        ? await _readCachedResolved(source, normalizedExploreUrl)
        : null;
    final cachedKinds = _parseCachedKinds(cachedResolved);
    if (cachedKinds.isNotEmpty) {
      return cachedKinds;
    }

    try {
      final resolved = _resolveSync(normalizedExploreUrl, source: source);
      if (_looksLikeJsError(resolved)) {
        return _buildErrorKinds(resolved.toString());
      }

      final kinds = _parseResolvedValue(resolved);
      if (useJsRuntime && _canPersistResolvedValue(resolved, kinds)) {
        await _writeCachedResolved(source, normalizedExploreUrl, resolved);
      }
      return kinds;
    } catch (e) {
      AppLog.e('ExploreUrl 解析失敗: $e', error: e);
      return _buildErrorKinds(e.toString());
    }
  }

  static Future<void> clearCache(
    BookSource source, {
    String? exploreUrl,
  }) async {
    final targetExploreUrl = exploreUrl ?? source.exploreUrl;
    final cacheKey = _cacheKey(source, targetExploreUrl);
    final legacyCacheKey = _legacyCacheKey(source, targetExploreUrl);
    if (cacheKey == null && legacyCacheKey == null) return;
    final cache = await AppCache.get(cacheName: _cacheName);
    if (cacheKey != null) await cache.remove(cacheKey);
    if (legacyCacheKey != null && legacyCacheKey != cacheKey) {
      await cache.remove(legacyCacheKey);
    }
  }

  static dynamic _resolveSync(String exploreUrl, {BookSource? source}) {
    if (!_isJsExploreUrl(exploreUrl)) {
      return exploreUrl;
    }
    if (source == null) {
      return '';
    }

    final rule = AnalyzeRule(source: source);
    try {
      return rule.evalJS(_extractJsBody(exploreUrl), null);
    } finally {
      rule.dispose();
    }
  }

  static bool _isJsExploreUrl(String exploreUrl) {
    final trimmed = exploreUrl.trimLeft();
    return trimmed.startsWith('<js>') || trimmed.startsWith('@js:');
  }

  static String _extractJsBody(String exploreUrl) {
    final trimmed = exploreUrl.trim();
    if (trimmed.startsWith('@js:')) {
      return trimmed.substring(4).trim();
    }

    var body = trimmed.substring(4);
    if (body.endsWith('</js>')) {
      body = body.substring(0, body.length - 5);
    }
    return body.trim();
  }

  static List<ExploreKind> _parseResolvedValue(dynamic value) {
    if (value == null) return [];
    if (value is List) {
      final kinds = <ExploreKind>[];
      for (final item in value) {
        if (item is Map) {
          kinds.add(ExploreKind.fromJson(Map<String, dynamic>.from(item)));
          continue;
        }
        kinds.addAll(_parseResolvedValue(item));
      }
      return kinds;
    }
    if (value is Map) {
      return [ExploreKind.fromJson(Map<String, dynamic>.from(value))];
    }

    final urlStr = value.toString().trim();
    if (urlStr.isEmpty) return [];
    if (_looksLikeJsError(urlStr)) {
      return _buildErrorKinds(urlStr);
    }
    if (_isJsonArray(urlStr)) {
      return _parseJsonArray(urlStr);
    }
    if (_isJsonObject(urlStr)) {
      return _parseJsonObject(urlStr);
    }
    return _parseStatic(urlStr);
  }

  /// 檢查是否為 JSON 陣列
  static bool _isJsonArray(String str) {
    final trimmed = str.trim();
    return trimmed.startsWith('[') && trimmed.endsWith(']');
  }

  static bool _isJsonObject(String str) {
    final trimmed = str.trim();
    return trimmed.startsWith('{') && trimmed.endsWith('}');
  }

  /// 解析 JSON 陣列格式的 exploreUrl
  static List<ExploreKind> _parseJsonArray(String jsonStr) {
    try {
      final decoded = jsonDecode(_sanitizeRelaxedJson(jsonStr));
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map((item) => ExploreKind.fromJson(Map<String, dynamic>.from(item)))
          .toList();
    } catch (e) {
      AppLog.e('ExploreUrl JSON 解析失敗: $e', error: e);
      return [ExploreKind(title: 'ERROR:${e.toString()}', url: e.toString())];
    }
  }

  static List<ExploreKind> _parseJsonObject(String jsonStr) {
    try {
      final decoded = jsonDecode(_sanitizeRelaxedJson(jsonStr));
      if (decoded is! Map) return [];
      return [ExploreKind.fromJson(Map<String, dynamic>.from(decoded))];
    } catch (e) {
      AppLog.e('ExploreUrl JSON object 解析失敗: $e', error: e);
      return [ExploreKind(title: 'ERROR:${e.toString()}', url: e.toString())];
    }
  }

  /// 解析靜態格式的 exploreUrl (對標 Android `&&` 和 `\n` 分隔)
  static List<ExploreKind> _parseStatic(String exploreUrl) {
    final kinds = <ExploreKind>[];

    try {
      final items = exploreUrl.split(RegExp(r'(&&|\n)+'));
      for (final item in items) {
        final trimmed = item.trim();
        if (trimmed.isEmpty) continue;

        final parts = trimmed.split('::');
        kinds.add(
          ExploreKind(
            title: parts.first.trim(),
            url: parts.length >= 2 ? parts.sublist(1).join('::').trim() : null,
          ),
        );
      }
    } catch (e) {
      AppLog.e('ExploreUrl 解析失敗: $e', error: e);
      kinds.add(ExploreKind(title: 'ERROR:${e.toString()}', url: e.toString()));
    }

    return kinds;
  }

  static bool _looksLikeJsError(dynamic value) {
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty) return false;
    return text.startsWith('JS_ERROR:') || text.startsWith('ERROR:');
  }

  static List<ExploreKind> _buildErrorKinds(String message) {
    final trimmed = message.trim();
    if (trimmed.isEmpty) return const <ExploreKind>[];
    final title = trimmed.startsWith('ERROR:')
        ? trimmed
        : trimmed.startsWith('JS_ERROR:')
        ? 'ERROR:${trimmed.substring('JS_ERROR:'.length).trim()}'
        : 'ERROR:$trimmed';
    return <ExploreKind>[ExploreKind(title: title, url: trimmed)];
  }

  static String _sanitizeRelaxedJson(String raw) {
    return raw.replaceAllMapped(RegExp(r',(?=\s*[\]}])'), (_) => '');
  }

  static bool _canPersistResolvedValue(dynamic value, List<ExploreKind> kinds) {
    if (kinds.isEmpty || _looksLikeJsError(value)) {
      return false;
    }
    return (_serializeResolvedValue(value)?.trim().isNotEmpty ?? false);
  }

  static List<ExploreKind> _parseCachedKinds(String? cachedResolved) {
    if (cachedResolved == null || cachedResolved.trim().isEmpty) {
      return const <ExploreKind>[];
    }
    final kinds = _parseResolvedValue(cachedResolved);
    return kinds.where((kind) => !kind.title.startsWith('ERROR:')).toList();
  }

  static Future<String?> _readCachedResolved(
    BookSource? source,
    String exploreUrl,
  ) async {
    final cacheKey = _cacheKey(source, exploreUrl);
    if (cacheKey == null) return null;
    final cache = await AppCache.get(cacheName: _cacheName);
    return cache.getAsString(cacheKey);
  }

  static Future<void> _writeCachedResolved(
    BookSource? source,
    String exploreUrl,
    dynamic value,
  ) async {
    final cacheKey = _cacheKey(source, exploreUrl);
    final serialized = _serializeResolvedValue(value)?.trim();
    if (cacheKey == null || serialized == null || serialized.isEmpty) {
      return;
    }
    final cache = await AppCache.get(cacheName: _cacheName);
    await cache.put(cacheKey, serialized);
  }

  static String? _cacheKey(BookSource? source, String? exploreUrl) {
    final normalized = exploreUrl?.trim();
    if (source == null || normalized == null || normalized.isEmpty) {
      return null;
    }
    return EncoderUtils.md5Encode(
      jsonEncode(<String>[source.bookSourceUrl, normalized]),
    );
  }

  static String? _legacyCacheKey(BookSource? source, String? exploreUrl) {
    final normalized = exploreUrl?.trim();
    if (source == null || normalized == null || normalized.isEmpty) {
      return null;
    }
    return EncoderUtils.md5Encode('${source.bookSourceUrl}$normalized');
  }

  static String? _serializeResolvedValue(dynamic value) {
    if (value == null) return null;
    if (value is String) {
      return value;
    }
    if (value is Map || value is List) {
      try {
        return jsonEncode(value);
      } catch (_) {
        return value.toString();
      }
    }
    return value.toString();
  }
}
