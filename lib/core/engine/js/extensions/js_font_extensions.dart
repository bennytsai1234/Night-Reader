import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:reader/core/services/app_log_service.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import '../js_extensions_base.dart';
import '../query_ttf.dart';
import 'package:reader/core/services/http_client.dart';

/// JsExtensions 的字體處理擴展
extension JsFontExtensions on JsExtensionsBase {
  void injectFontExtensions() {
    runtime.onMessage('queryTTF', (dynamic args) async {
      try {
        final dataStr = args[0].toString();
        final useCache = args.length > 1 ? args[1] as bool : true;
        final key =
            useCache ? md5.convert(utf8.encode(dataStr)).toString() : '';
        if (useCache && JsExtensionsBase.ttfCache.containsKey(key)) return key;

        Uint8List? buffer;
        if (dataStr.startsWith('http')) {
          final response = await HttpClient().client.get<List<int>>(
            dataStr,
            options: Options(responseType: ResponseType.bytes),
          );
          buffer =
              response.data != null ? Uint8List.fromList(response.data!) : null;
        } else {
          buffer = base64Decode(dataStr);
        }

        if (buffer != null) {
          final qTTF = QueryTTF(buffer);
          final cacheKey =
              key.isNotEmpty ? key : md5.convert(buffer).toString();
          JsExtensionsBase.ttfCache[cacheKey] = qTTF;
          return cacheKey;
        }
      } catch (e) {
        AppLog.e('queryTTF error: $e', error: e);
      }
      return null;
    });

    runtime.onMessage('replaceFont', (dynamic args) {
      try {
        final text = args[0]?.toString() ?? '';
        final errorKey = args[1]?.toString();
        final correctKey = args[2]?.toString();
        final cacheKey = '${errorKey}_${correctKey}_${text.hashCode}';
        if (JsExtensionsBase.fontReplaceCache.containsKey(cacheKey))
          return JsExtensionsBase.fontReplaceCache[cacheKey];

        final errorTTF =
            errorKey != null ? JsExtensionsBase.ttfCache[errorKey] : null;
        final correctTTF =
            correctKey != null ? JsExtensionsBase.ttfCache[correctKey] : null;
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
            result.writeCharCode(codePoint);
            continue;
          }
          final newCode = correctTTF.getUnicodeByGlyf(glyf);
          result.writeCharCode(newCode != 0 ? newCode : codePoint);
        }
        final finalResult = result.toString();
        if (JsExtensionsBase.fontReplaceCache.length > 500)
          JsExtensionsBase.fontReplaceCache.clear();
        JsExtensionsBase.fontReplaceCache[cacheKey] = finalResult;
        return finalResult;
      } catch (e) {
        AppLog.e('replaceFont error: $e', error: e);
        return args[0]?.toString() ?? '';
      }
    });
  }
}
