import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:night_reader/core/diagnostics/app_log_service.dart';
import 'package:crypto/crypto.dart';

import '../js_extensions_base.dart';
import '../query_ttf.dart';
import 'js_blocking_tasks.dart';
import '../encode/encode_utils_base64.dart';

import 'package:night_reader/core/engine/source_isolate/source_isolate.dart';

/// JsExtensions 的字體處理擴展
extension JsFontExtensions on JsExtensionsBase {
  void injectFontExtensions() {
    // 網址的字型停住交給網路 isolate 下載（[BlockingCall]）；原本這裡傳回
    // Future，JS 拿到的是還沒完成的結果。
    runtime.onMessage('queryTTF', (dynamic args) {
      try {
        final data = args[0];
        final useCache = args.length > 1 ? args[1] as bool : true;
        // 位元組（Legado 的 ByteArray）直接當字型；文字是網址或 Base64。
        final bytes = data is List
            ? Uint8List.fromList([
                for (final b in data) (b as num).toInt() & 0xFF,
              ])
            : null;
        final dataStr = bytes == null ? data.toString() : '';
        final key = !useCache
            ? ''
            : bytes != null
            ? md5.convert(bytes).toString()
            : md5.convert(utf8.encode(dataStr)).toString();
        if (useCache && JsExtensionsBase.ttfCache.containsKey(key)) return key;

        final buffer =
            bytes ??
            (dataStr.startsWith('http')
                ? BlockingCall.run(
                    plainBytes(
                      dataStr,
                      cookieJar: source?.enabledCookieJar == true,
                    ),
                  ) as Uint8List
                : EncodeUtilsBase64.decodeAndroid(dataStr));
        final qTTF = QueryTTF(buffer);
        final cacheKey = key.isNotEmpty ? key : md5.convert(buffer).toString();
        JsExtensionsBase.ttfCache[cacheKey] = qTTF;
        return cacheKey;
      } catch (e) {
        AppLog.e('queryTTF error: $e', error: e);
      }
      return null;
    });

    // queryTTF 交回的字型物件的查詢方法（Legado 的 QueryTTF 公開方法）。
    runtime.onMessage('_ttfCall', (dynamic args) {
      final ttf = JsExtensionsBase.ttfCache[args[0]?.toString()];
      final arg = args[2];
      final Object? result = switch (args[1]) {
        _ when ttf == null => null,
        'getGlyfIdByUnicode' => ttf.getGlyfIdByUnicode((arg as num).toInt()),
        'getGlyfByUnicode' => ttf.getGlyfByUnicode((arg as num).toInt()),
        'getGlyfById' => ttf.getGlyfById((arg as num).toInt()),
        'getUnicodeByGlyf' => ttf.getUnicodeByGlyf(arg as String?),
        'isBlankUnicode' => ttf.isBlankUnicode((arg as num).toInt()),
        _ => null,
      };
      return jsonEncode(result);
    });

    runtime.onMessage('replaceFont', (dynamic args) {
      try {
        final text = args[0]?.toString() ?? '';
        final errorKey = args[1]?.toString();
        final correctKey = args[2]?.toString();
        // 第四個參數 filter（同 Legado）：錯誤字型裡沒有輪廓的字刪掉。
        final filter = args.length > 3 && args[3] == true;
        final cacheKey = '${errorKey}_${correctKey}_${filter}_${text.hashCode}';
        if (JsExtensionsBase.fontReplaceCache.containsKey(cacheKey)) {
          return JsExtensionsBase.fontReplaceCache[cacheKey];
        }

        final errorTTF = errorKey != null
            ? JsExtensionsBase.ttfCache[errorKey]
            : null;
        final correctTTF = correctKey != null
            ? JsExtensionsBase.ttfCache[correctKey]
            : null;
        if (errorTTF == null || correctTTF == null) return text;

        final result = StringBuffer();
        for (final codePoint in text.runes) {
          if (errorTTF.isBlankUnicode(codePoint)) {
            result.writeCharCode(codePoint);
            continue;
          }
          var glyf = errorTTF.getGlyfByUnicode(codePoint);
          if (errorTTF.getGlyfIdByUnicode(codePoint) == 0) glyf = null;
          if (glyf == null) {
            if (!filter) result.writeCharCode(codePoint);
            continue;
          }
          final newCode = correctTTF.getUnicodeByGlyf(glyf);
          result.writeCharCode(newCode != 0 ? newCode : codePoint);
        }
        final finalResult = result.toString();
        if (JsExtensionsBase.fontReplaceCache.length > 500) {
          JsExtensionsBase.fontReplaceCache.clear();
        }
        JsExtensionsBase.fontReplaceCache[cacheKey] = finalResult;
        return finalResult;
      } catch (e) {
        AppLog.e('replaceFont error: $e', error: e);
        return args[0]?.toString() ?? '';
      }
    });
  }
}
