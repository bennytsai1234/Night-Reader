import '../js_extensions_base.dart';

/// 注入 rule JS 可見的全域物件：`java` / `cookie` / `cache` / `source`。
///
/// 每個方法都同步拿到結果，和 Legado 一樣：`sendMessage` 直接回傳；要等
/// 網路、資料庫的經 `__lrWait`（[JsExtensionsBase.onBlocking]），在書源
/// isolate 停住等（ADR 0034）。
extension JsJavaObject on JsExtensionsBase {
  void injectJavaObjectJs() {
    runtime.evaluate(r'''
      function __lrJavaList(items) {
        var list = Array.isArray(items) ? items.slice() : [];
        list.size = function() { return this.length; };
        list.get = function(index) { return this[index]; };
        list.first = function() { return this.length ? this[0] : null; };
        list.last = function() {
          return this.length ? this[this.length - 1] : null;
        };
        return list;
      }

      function __lrNormalizeRuleResult(value) {
        if (value == null) return value;
        if (Array.isArray(value)) {
          return value.map(__lrNormalizeRuleResult);
        }
        var type = typeof value;
        if (type !== 'object') {
          return value;
        }
        // 規則在回應物件上加了自己的欄位（`r.name = …`）時，要的是那些欄位，
        // 照一般物件交回。
        if (value.__lrResponse && Object.keys(value).every(function(key) {
          return typeof value[key] === 'function';
        })) {
          return { __lrResponse: value.__lrResponse };
        }
        // java.util.HashMap 有 size／get，但交回的是物件，不是清單。
        if (value.__lrMap) {
          var normalizedMap = {};
          value.keySet().forEach(function(key) {
            normalizedMap[key] = __lrNormalizeRuleResult(value.get(key));
          });
          return normalizedMap;
        }
        if (typeof value.size === 'function' && typeof value.get === 'function') {
          var normalizedItems = [];
          var size = Number(value.size()) || 0;
          for (var i = 0; i < size; i++) {
            normalizedItems.push(__lrNormalizeRuleResult(value.get(i)));
          }
          return normalizedItems;
        }
        if (typeof value.__lrElementId === 'number') {
          return {
            __lrElementId: value.__lrElementId,
            outerHtml: typeof value.outerHtml === 'function'
              ? String(value.outerHtml() || '')
              : ''
          };
        }
        if (typeof value.outerHtml === 'function') {
          return { __html: String(value.outerHtml() || '') };
        }
        if (typeof value.html === 'function' && typeof value.select === 'function') {
          return { __html: String(value.html() || '') };
        }
        if (Object.getPrototypeOf(value) === Object.prototype &&
            value.toString === Object.prototype.toString) {
          var normalizedObject = {};
          Object.keys(value).forEach(function(key) {
            normalizedObject[key] = __lrNormalizeRuleResult(value[key]);
          });
          return normalizedObject;
        }
        if (typeof value.toString === 'function') {
          var text = String(value.toString());
          if (/<[a-z][\s\S]*>/i.test(text)) {
            return { __html: text };
          }
        }
        return value;
      }

      /// 交給 Dart 解析的內容：元素、清單與一般物件照 [__lrNormalizeRuleResult]，
      /// JavaString 這類自訂物件轉成文字（JSON 會把它們變成空物件）。
      function __lrContentArg(value) {
        if (value == null) return null;
        if (typeof value === 'object' && !Array.isArray(value) &&
            value.__lrElementId === undefined &&
            typeof value.size !== 'function' &&
            Object.getPrototypeOf(value) !== Object.prototype) {
          return String(value);
        }
        return __lrNormalizeRuleResult(value);
      }

      function buildHttpResponse(res) {
        function normalizeResponseUrl(value) {
          var normalized = String(value == null ? '' : value);
          if (!normalized) return '';
          if (/^https?:\/\/[^\/?#]+$/i.test(normalized)) {
            return normalized + '/';
          }
          return normalized;
        }
        function responseUrl() {
          if (!res) return '';
          return normalizeResponseUrl(res.url || res.requestUrl || '');
        }
        function responseCode() {
          if (!res || res.code == null) return 0;
          return Number(res.code) || 0;
        }
        function responseMessage() {
          if (!res || res.message == null) return '';
          return String(res.message);
        }
        function isSuccessfulStatus() {
          var code = responseCode();
          return code >= 200 && code < 300;
        }
        function normalizeLocationValue(value) {
          var normalized = String(value == null ? '' : value);
          if (!normalized) return '';
          if (normalized.indexOf('?') !== -1 && !/[?&]$/.test(normalized)) {
            return normalized + '&';
          }
          return normalized;
        }
        function getHeader(name) {
          if (!res || !name) return '';
          var target = String(name).toLowerCase();
          if (target === 'location' && Array.isArray(res.redirects) && res.redirects.length > 0) {
            var lastRedirect = res.redirects[res.redirects.length - 1];
            if (lastRedirect != null) {
              var redirectValue = String(lastRedirect);
              if (/^https?:\/\//i.test(redirectValue) && res.requestUrl) {
                try {
                  function splitUrl(rawUrl) {
                    var match = String(rawUrl).match(/^(https?:\/\/[^\/]+)(\/[^?#]*)?(\?[^#]*)?/i);
                    if (!match) return null;
                    return {
                      origin: match[1],
                      path: match[2] || '/',
                      query: match[3] || ''
                    };
                  }
                  var requestUrl = splitUrl(res.requestUrl);
                  var redirectUrl = splitUrl(redirectValue);
                  if (requestUrl && redirectUrl && requestUrl.origin === redirectUrl.origin) {
                    var requestDir = requestUrl.path.replace(/[^/]*$/, '');
                    var relativePath = redirectUrl.path.indexOf(requestDir) === 0
                      ? redirectUrl.path.substring(requestDir.length)
                      : redirectUrl.path.replace(/^\//, '');
                    return normalizeLocationValue(relativePath + (redirectUrl.query || ''));
                  }
                } catch (e) {}
              }
              return normalizeLocationValue(redirectValue);
            }
          }
          if (!res.headers) return '';
          for (var key in res.headers) {
            if (!Object.prototype.hasOwnProperty.call(res.headers, key)) continue;
            if (String(key).toLowerCase() !== target) continue;
            var value = res.headers[key];
            if (Array.isArray(value)) {
              return value.length > 0
                ? (target === 'location'
                    ? normalizeLocationValue(value[0])
                    : String(value[0]))
                : '';
            }
            if (value == null) return '';
            return target === 'location'
              ? normalizeLocationValue(value)
              : String(value);
          }
          if (target === 'location' && res.url && res.requestUrl && res.url !== res.requestUrl) {
            try {
              function splitUrl(rawUrl) {
                var match = String(rawUrl).match(/^(https?:\/\/[^\/]+)(\/[^?#]*)?(\?[^#]*)?/i);
                if (!match) return null;
                return {
                  origin: match[1],
                  path: match[2] || '/',
                  query: match[3] || ''
                };
              }
              var requestUrl = splitUrl(res.requestUrl);
              var finalUrl = splitUrl(res.url);
              if (requestUrl && finalUrl && requestUrl.origin === finalUrl.origin) {
                var requestDir = requestUrl.path.replace(/[^/]*$/, '');
                var finalPath = finalUrl.path;
                var relativePath = finalPath.indexOf(requestDir) === 0
                  ? finalPath.substring(requestDir.length)
                  : finalPath.replace(/^\//, '');
                var query = finalUrl.query || '';
                return normalizeLocationValue(relativePath + query);
              }
            } catch (e) {}
          }
          return '';
        }
        function buildRawRequest() {
          return {
            url: function() { return responseUrl(); },
            toString: function() { return responseUrl(); }
          };
        }
        // 同 OkHttp 的 Headers（Legado 的 `headers()`）：`get` 不分大小寫、
        // 取最後一個值。原本的 `headers()['content-type']` 寫法照用。
        var headers = null;
        function buildHeaders() {
          if (headers) return headers;
          var source = res && res.headers ? res.headers : {};
          headers = {};
          Object.keys(source).forEach(function(key) { headers[key] = source[key]; });
          function valuesOf(name) {
            var target = String(name).toLowerCase();
            var found = [];
            Object.keys(source).forEach(function(key) {
              if (String(key).toLowerCase() !== target) return;
              var value = source[key];
              (Array.isArray(value) ? value : [value]).forEach(function(item) {
                if (item != null) found.push(String(item));
              });
            });
            return found;
          }
          var methods = {
            get: function(name) {
              var found = valuesOf(name);
              return found.length ? found[found.length - 1] : null;
            },
            values: function(name) { return __lrJavaList(valuesOf(name)); },
            names: function() {
              return __lrJavaList(Object.keys(source).map(function(key) {
                return String(key).toLowerCase();
              }));
            },
            size: function() {
              return Object.keys(source).reduce(function(count, key) {
                return count + valuesOf(key).length;
              }, 0);
            },
            toMultimap: function() {
              var map = {};
              Object.keys(source).forEach(function(key) {
                map[String(key).toLowerCase()] = valuesOf(key);
              });
              return map;
            }
          };
          Object.keys(methods).forEach(function(name) {
            Object.defineProperty(headers, name, { value: methods[name], enumerable: false });
          });
          return headers;
        }
        function buildRawResponse() {
          return {
            request: function() { return buildRawRequest(); },
            url: function() { return responseUrl(); },
            headers: function() { return buildHeaders(); },
            code: function() { return responseCode(); },
            message: function() { return responseMessage(); },
            isSuccessful: function() { return isSuccessfulStatus(); },
            toString: function() { return responseUrl(); }
          };
        }
        var response = {
          body: function() { return res.body; },
          url: function() { return responseUrl(); },
          code: function() { return responseCode(); },
          statusCode: function() { return responseCode(); },
          message: function() { return responseMessage(); },
          isSuccessful: function() { return isSuccessfulStatus(); },
          // OkHttp 的 headers()；給名稱時是 Jsoup Response 的 headers(name)：
          // 那個標頭的每個值（java.get／post／head 回傳的是 Jsoup Response）。
          headers: function(name) {
            if (name === undefined) return buildHeaders();
            return buildHeaders().values(name);
          },
          header: function(name) { return getHeader(name); },
          // 以下是 Jsoup Connection.Response 的方法。
          hasHeader: function(name) { return buildHeaders().values(name).length > 0; },
          statusMessage: function() { return responseMessage(); },
          contentType: function() { return buildHeaders().get('content-type'); },
          charset: function() {
            var type = buildHeaders().get('content-type') || '';
            var match = /charset=([^;]+)/i.exec(type);
            return match ? match[1].trim() : null;
          },
          cookies: function() {
            var map = {};
            buildHeaders().values('set-cookie').forEach(function(line) {
              var pair = String(line).split(';')[0];
              var eq = pair.indexOf('=');
              if (eq > 0) map[pair.substring(0, eq).trim()] = pair.substring(eq + 1).trim();
            });
            return map;
          },
          cookie: function(name) {
            var value = response.cookies()[name];
            return value == null ? null : value;
          },
          bodyAsBytes: function() { return java.strToBytes(String(res && res.body != null ? res.body : ''), 'UTF-8'); },
          parse: function() { return org.jsoup.Jsoup.parse(String(res && res.body != null ? res.body : ''), responseUrl()); },
          // Legado 只在請求失敗時有 errorBody（內文放在這裡，不在 body）。
          errorBody: function() {
            if (isSuccessfulStatus()) return null;
            var text = String(res && res.body != null ? res.body : '');
            return {
              string: function() { return text; },
              toString: function() { return text; }
            };
          },
          raw: function() { return buildRawResponse(); },
          toString: function() { return responseUrl(); }
        };
        // 規則原樣傳回回應物件時（例如登入檢查），交回 Dart 換成 StrResponse。
        Object.defineProperty(response, '__lrResponse', {
          value: res || {},
          enumerable: false
        });
        return response;
      }

      var java = {
        // ─── 要等的：HTTP ────────────────────────────────────────
        ajax: function(url) { return __lrWait('ajax', url); },
        // Legado 傳回 StrResponse 陣列：每一個都是回應物件。
        ajaxAll: function(urlList) {
          var list = __lrWait('ajaxAll', urlList) || [];
          var result = [];
          for (var i = 0; i < list.length; i++) {
            result.push(buildHttpResponse(list[i]));
          }
          return result;
        },
        cacheFile: function(url, saveTime) { return __lrWait('cacheTextFile', [url, saveTime || 0]); },
        connect: function(url, header) {
          return buildHttpResponse(__lrWait(
            'connect',
            arguments.length > 1 ? [url, header || null] : url
          ));
        },
        get: function(url, headers) {
          if (arguments.length <= 1) {
            return sendMessage('scopeGet', JSON.stringify(url));
          }
          return buildHttpResponse(__lrWait('get', [url, headers || {}]));
        },
        post: function(url, body, headers) {
          return buildHttpResponse(__lrWait('post', [url, body, headers || {}]));
        },
        head: function(url, headers) {
          return buildHttpResponse(__lrWait('head', [url, headers || {}]));
        },

        // ─── 要等的：WebView / I/O ───────────────────────────────
        webView: function(html, url, js) { return __lrWait('webView', [html, url, js]); },
        webViewGetSource: function(html, url, js, sourceRegex) {
          return __lrWait('webViewGetSource', [html, url, js, sourceRegex]);
        },
        webViewGetOverrideUrl: function(html, url, js, overrideUrlRegex) {
          return __lrWait('webViewGetOverrideUrl', [html, url, js, overrideUrlRegex]);
        },
        startBrowser: function(url, title) { __lrWait('startBrowser', [url, title]); },
        startBrowserAwait: function(url, title, refetchAfterSuccess) {
          return buildHttpResponse(
            __lrWait('startBrowserAwait', [url, title, refetchAfterSuccess !== false])
          );
        },
        getVerificationCode: function(imageUrl) { return __lrWait('getVerificationCode', imageUrl); },
        downloadFile: function(url) { return __lrWait('downloadFile', url); },
        importScript: function(path) { return __lrWait('importScript', path); },
        readFile: function(path) { return __lrWait('readFile', path); },
        readTxtFile: function(path, charset) { return __lrWait('readTxtFile', [path, charset]); },
        getZipByteArrayContent: function(url, innerPath) { return __lrWait('getZipByteArrayContent', [url, innerPath]); },
        unArchiveFile: function(zipPath) { return __lrWait('unArchiveFile', zipPath); },
        getTxtInFolder: function(relPath) { return __lrWait('getTxtInFolder', relPath); },

        // ─── sync: crypto / encoding ─────────────────────────────
        createSymmetricCrypto: function(transformation, key, iv) {
          return __lrSymmetricCrypto(transformation, key, iv);
        },
        // Legado help/crypto/AsymmetricCrypto.kt：第二個參數 true（預設）用
        // 公鑰，false 用私鑰。
        createAsymmetricCrypto: function(transformation) {
          var state = __lrKeyPairState();
          function call(encrypt, data, usePublicKey, format) {
            state.ensure();
            return sendMessage('asymmetricCrypto', JSON.stringify([
              String(transformation), encrypt, usePublicKey !== false,
              state.publicKey, state.privateKey, __lrCryptoArg(data), format
            ]));
          }
          var crypto = state.accessors({
            setPublicKey: function(key) { state.publicKey = __lrCryptoArg(key); return crypto; },
            setPrivateKey: function(key) { state.privateKey = __lrCryptoArg(key); return crypto; },
            decrypt: function(data, usePublicKey) { return normalizeByteArray(call(false, data, usePublicKey, 'bytes')); },
            decryptStr: function(data, usePublicKey) { return call(false, data, usePublicKey, 'string'); },
            encrypt: function(data, usePublicKey) { return normalizeByteArray(call(true, data, usePublicKey, 'bytes')); },
            encryptHex: function(data, usePublicKey) { return call(true, data, usePublicKey, 'hex'); },
            encryptBase64: function(data, usePublicKey) { return call(true, data, usePublicKey, 'base64'); }
          });
          return crypto;
        },
        createSign: function(algorithm) {
          var state = __lrKeyPairState();
          function call(action, data, signature, format) {
            state.ensure();
            return sendMessage('rsaSign', JSON.stringify([
              String(algorithm), action, state.publicKey, state.privateKey,
              __lrCryptoArg(data), __lrCryptoArg(signature), format
            ]));
          }
          var signer = state.accessors({
            setPublicKey: function(key) { state.publicKey = __lrCryptoArg(key); return signer; },
            setPrivateKey: function(key) { state.privateKey = __lrCryptoArg(key); return signer; },
            sign: function(data) { return normalizeByteArray(call('sign', data, null, 'bytes')); },
            signHex: function(data) { return call('sign', data, null, 'hex'); },
            signBase64: function(data) { return call('sign', data, null, 'base64'); },
            verify: function(data, signature) { return call('verify', data, signature, '') === true; }
          });
          return signer;
        },
        // 舊的加解密函式，照 Legado JsEncodeUtils.kt 一個一個對應過來，連它
        // 的怪處也照做（例如 aesEncodeToString 其實是解密）。
        aesDecodeToByteArray: function(str, key, transformation, iv) {
          return __lrSymmetricCrypto(transformation, key, iv).decrypt(str);
        },
        aesDecodeToString: function(str, key, transformation, iv) {
          return __lrSymmetricCrypto(transformation, key, iv).decryptStr(str);
        },
        aesDecodeArgsBase64Str: function(data, key, mode, padding, iv) {
          return __lrSymmetricCrypto(
            'AES/' + mode + '/' + padding,
            java.base64DecodeToByteArray(key),
            java.base64DecodeToByteArray(iv)
          ).decryptStr(data);
        },
        aesBase64DecodeToByteArray: function(str, key, transformation, iv) {
          return __lrSymmetricCrypto(transformation, key, iv).decrypt(str);
        },
        aesBase64DecodeToString: function(str, key, transformation, iv) {
          return __lrSymmetricCrypto(transformation, key, iv).decryptStr(str);
        },
        aesEncodeToByteArray: function(data, key, transformation, iv) {
          return __lrSymmetricCrypto(transformation, key, iv).encrypt(data);
        },
        aesEncodeToString: function(data, key, transformation, iv) {
          return __lrSymmetricCrypto(transformation, key, iv).decryptStr(data);
        },
        aesEncodeToBase64ByteArray: function(data, key, transformation, iv) {
          return java.strToBytes(
            __lrSymmetricCrypto(transformation, key, iv).encryptBase64(data)
          );
        },
        aesEncodeToBase64String: function(data, key, transformation, iv) {
          return __lrSymmetricCrypto(transformation, key, iv).encryptBase64(data);
        },
        aesEncodeArgsBase64Str: function(data, key, mode, padding, iv) {
          return __lrSymmetricCrypto('AES/' + mode + '/' + padding, key, iv)
            .encryptBase64(data);
        },
        desDecodeToString: function(data, key, transformation, iv) {
          return __lrSymmetricCrypto(transformation, key, iv).decryptStr(data);
        },
        desBase64DecodeToString: function(data, key, transformation, iv) {
          return __lrSymmetricCrypto(transformation, key, iv).decryptStr(data);
        },
        desEncodeToString: function(data, key, transformation, iv) {
          return java.bytesToStr(
            __lrSymmetricCrypto(transformation, key, iv).encrypt(data),
            'UTF-8'
          );
        },
        desEncodeToBase64String: function(data, key, transformation, iv) {
          return __lrSymmetricCrypto(transformation, key, iv).encryptBase64(data);
        },
        tripleDESDecodeStr: function(data, key, mode, padding, iv) {
          return __lrSymmetricCrypto('DESede/' + mode + '/' + padding, key, iv)
            .decryptStr(data);
        },
        tripleDESDecodeArgsBase64Str: function(data, key, mode, padding, iv) {
          return __lrSymmetricCrypto(
            'DESede/' + mode + '/' + padding,
            java.base64DecodeToByteArray(key),
            iv
          ).decryptStr(data);
        },
        tripleDESEncodeBase64Str: function(data, key, mode, padding, iv) {
          return __lrSymmetricCrypto('DESede/' + mode + '/' + padding, key, iv)
            .encryptBase64(data);
        },
        tripleDESEncodeArgsBase64Str: function(data, key, mode, padding, iv) {
          return __lrSymmetricCrypto(
            'DESede/' + mode + '/' + padding,
            java.base64DecodeToByteArray(key),
            iv
          ).encryptBase64(data);
        },
        digestBase64Str: function(str, algorithm) {
          return new JavaString(sendMessage('_digest', JSON.stringify([__lrCryptoArg(str), __lrCryptoArg(algorithm), false])));
        },
        HMacBase64: function(data, algorithm, key) {
          return new JavaString(
            sendMessage('_hmacBase64', JSON.stringify([__lrCryptoArg(data), __lrCryptoArg(algorithm), __lrCryptoArg(key)]))
          );
        },
        md5Encode: function(str) { return new JavaString(sendMessage('_md5Encode', JSON.stringify(__lrCryptoArg(str)))); },
        md5Encode16: function(str) { return new JavaString(sendMessage('_md5Encode16', JSON.stringify(__lrCryptoArg(str)))); },
        digestHex: function(str, algorithm) {
          return new JavaString(sendMessage('_digest', JSON.stringify([__lrCryptoArg(str), __lrCryptoArg(algorithm), true])));
        },
        // Legado：base64Encode(str[, flags])、base64Decode(str[, charset])、
        // base64Decode(str, flags)、base64DecodeToByteArray(str[, flags])；
        // flags 照 Android Base64（URL_SAFE 8、NO_WRAP 2、NO_PADDING 1）。
        base64Encode: function(str, flags) {
          return sendMessage('_base64Encode', JSON.stringify(
            { d: __lrCryptoArg(str), f: flags == null ? null : Number(flags) }
          ));
        },
        base64Decode: function(str, charsetOrFlags) {
          var arg = { d: __lrCryptoArg(str) };
          if (typeof charsetOrFlags === 'number') arg.f = charsetOrFlags;
          else if (charsetOrFlags != null) arg.c = String(charsetOrFlags);
          return sendMessage('_base64Decode', JSON.stringify(arg));
        },
        base64DecodeToByteArray: function(str, flags) {
          if (str == null || String(str).trim() === '') return null;
          return normalizeByteArray(sendMessage('_base64DecodeToBytes', JSON.stringify(
            { d: __lrCryptoArg(str), f: flags == null ? null : Number(flags) }
          )));
        },
        hexEncodeToString: function(str) { return sendMessage('_hexEncode', JSON.stringify(__lrCryptoArg(str))); },
        hexDecodeToString: function(hex) { return sendMessage('_hexDecode', JSON.stringify(__lrCryptoArg(hex))); },
        hexDecodeToByteArray: function(hex) {
          return normalizeByteArray(
            sendMessage('_hexDecodeToBytes', JSON.stringify(String(hex)))
          );
        },
        randomUUID: function() {
          if (
            typeof globalThis.crypto === 'object' &&
            globalThis.crypto !== null &&
            typeof globalThis.crypto.randomUUID === 'function'
          ) {
            return globalThis.crypto.randomUUID();
          }
          return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function(ch) {
            var rand = Math.random() * 16 | 0;
            var value = ch === 'x' ? rand : ((rand & 0x3) | 0x8);
            return value.toString(16);
          });
        },
        timeFormat: function(time) { return sendMessage('_timeFormat', JSON.stringify(time)); },
        timeFormatUTC: function(time, format, sh) { return sendMessage('timeFormatUTC', JSON.stringify([time, format, sh])); },
        getWebViewUA: function() { return String(sendMessage('getWebViewUA', '""')); },
        toNumChapter: function(text) { return sendMessage('_toNumChapter', JSON.stringify(text)); },
        t2s: function(text) { return sendMessage('t2s', JSON.stringify(text)); },
        s2t: function(text) { return sendMessage('s2t', JSON.stringify(text)); },
        // Legado 用 Java 的 URLEncoder：空白變 +、!'()~ 也編碼；enc 預設 UTF-8。
        encodeURI: function(value, enc) {
          return sendMessage('_urlEncode', JSON.stringify(
            [String(value == null ? '' : value), enc == null ? null : String(enc)]
          ));
        },
        decodeURI: function(value) {
          return decodeURIComponent(String(value == null ? '' : value));
        },
        encodeURIComponent: function(value) {
          return encodeURIComponent(String(value == null ? '' : value));
        },
        decodeURIComponent: function(value) {
          return decodeURIComponent(String(value == null ? '' : value));
        },
        strToBytes: function(str, charset) {
          return normalizeByteArray(
            sendMessage('strToBytes', JSON.stringify([str, charset]))
          );
        },
        bytesToStr: function(bytes, charset) {
          return sendMessage(
            'bytesToStr',
            JSON.stringify([normalizeByteArray(bytes), charset])
          );
        },
        HMacHex: function(data, algorithm, key) {
          return new JavaString(
            sendMessage('_hmacHex', JSON.stringify([__lrCryptoArg(data), __lrCryptoArg(algorithm), __lrCryptoArg(key)]))
          );
        },
        gzipToString: function(bytes, charset) {
          var decoded = normalizeByteArray(
            sendMessage('_gunzipBytes', JSON.stringify(bytes))
          );
          return this.bytesToStr(decoded, charset || 'UTF-8');
        },

        // ─── sync helpers ────────────────────────────────────────
        // legado 的 java.log / java.put 會回傳原值，部分書源會把它們當成
        // branch completion value 來傳回正文或中間結果。
        log: function(msg) { return sendMessage('log', JSON.stringify(msg)); },
        toast: function(msg) { sendMessage('toast', JSON.stringify(String(msg))); },
        longToast: function(msg) { sendMessage('longToast', JSON.stringify(String(msg))); },
        put: function(key, value) {
          var normalized = value == null ? '' : String(value);
          sendMessage('scopePut', JSON.stringify([key, normalized]));
          return normalized;
        },
        // Legado：getString(rule[, mContent, isUrl])、getString(rule, unescape)；
        // 有 mContent 時解析它，不是目前內容。
        getString: function(rule, content, isUrl) {
          if (arguments.length === 2 && typeof content === 'boolean') {
            return sendMessage('ruleGetString', JSON.stringify([String(rule), null, false, content]));
          }
          return sendMessage('ruleGetString', JSON.stringify(
            [String(rule), __lrContentArg(content), !!isUrl, true]
          ));
        },
        getStringList: function(rule, content, isUrl) {
          return __lrJavaList(sendMessage('ruleGetStringList', JSON.stringify(
            [String(rule), __lrContentArg(content), !!isUrl]
          )));
        },
        getElement: function(rule) { return __lrJsoupDecode(sendMessage('ruleGetElement', JSON.stringify(String(rule)))); },
        getElements: function(rule) {
          var found = __lrJsoupDecode(sendMessage('ruleGetElements', JSON.stringify(String(rule))));
          return Array.isArray(found) ? __lrJsoupElements(found) : found;
        },
        setContent: function(content, baseUrl) {
          sendMessage('ruleSetContent', JSON.stringify([content, baseUrl || null]));
          return null;
        },
        setBaseUrl: function(url) { sendMessage('ruleSetUrl', JSON.stringify(['base', url == null ? null : String(url)])); },
        setRedirectUrl: function(url) { sendMessage('ruleSetUrl', JSON.stringify(['redirect', url == null ? null : String(url)])); },
        refreshTocUrl: function() { __lrWait('ruleRefreshTocUrl', null); },
        reGetBook: function() {
          throw new Error('夜讀還不支援 java.reGetBook()（換成搜尋到的同名書再讀詳情）');
        },

        // ─── sync: TTF query/replace (sync helpers) ──────────────
        queryTTF: function(data, useCache) {
          var ttfId = sendMessage('queryTTF', JSON.stringify([data, useCache === undefined ? true : useCache]));
          return ttfId ? { _ttfId: ttfId } : null;
        },
        // 第四個參數 filter：錯誤字型裡沒有輪廓的字刪掉（Legado）。
        replaceFont: function(text, errTTF, correctTTF, filter) {
          return sendMessage('replaceFont', JSON.stringify(
            [text, errTTF ? errTTF._ttfId : null, correctTTF ? correctTTF._ttfId : null, filter === true]
          ));
        },
        // Legado 已標成過時、改叫 queryTTF 的舊名字。
        queryBase64TTF: function(data) { return java.queryTTF(data); },

        // ─── sync: 其他 Legado JsExtensions ─────────────────────
        htmlFormat: function(str) { return sendMessage('htmlFormat', JSON.stringify(String(str == null ? '' : str))); },
        toURL: function(url, baseUrl) {
          return sendMessage('toURL', JSON.stringify([String(url), baseUrl == null ? null : String(baseUrl)]));
        },
        // Legado 記下 Java 的類別名稱；這裡記 JS 的型別。
        logType: function(value) {
          java.log(value == null ? 'null'
            : (Array.isArray(value) ? 'Array' : (value.constructor && value.constructor.name) || typeof value));
        },
        // 手機編號：Legado 是 Android 的 ANDROID_ID（16 個十六進位字）。夜讀
        // 第一次用到時產生一組存在快取裡，之後都是同一組。
        androidId: function() {
          var id = cache.get('__nightReaderAndroidId');
          if (!id) {
            id = String(java.randomUUID()).replace(/-/g, '').substring(0, 16);
            cache.put('__nightReaderAndroidId', id);
          }
          return String(id);
        },
        // Legado 開外部 App 前先問使用者；夜讀和 startBrowser 一樣只在登入頁
        // 打開，其他地方記在日誌（ADR 0038）。
        openUrl: function(url) { java.startBrowser(String(url), ''); },
        getSource: function() { return source; },
        get7zByteArrayContent: function() { throw new Error('夜讀不支援 7z 壓縮檔'); },
        get7zStringContent: function() { throw new Error('夜讀不支援 7z 壓縮檔'); },
        un7zFile: function() { throw new Error('夜讀不支援 7z 壓縮檔'); },
        getRarByteArrayContent: function() { throw new Error('夜讀不支援 rar 壓縮檔'); },
        getRarStringContent: function() { throw new Error('夜讀不支援 rar 壓縮檔'); },
        unrarFile: function() { throw new Error('夜讀不支援 rar 壓縮檔'); }
      };

      // ─── java.getCookie → 獨立 channel ───────────────────────
      //
      // 提醒：rule JS 裡的 `java.getCookie(tag, key)` 與 `cookie.get(url)`
      // 走不同 Dart handler。前者可以只取其中一個 Cookie 的值。
      java.getCookie = function(tag, key) { return __lrWait('getCookie', [tag, key || null]); };

      // ─── cookie / cache / source 全域物件 ────────────────────
      var cookie = {
        get: function(url) { return __lrWait('cookieGet', url); },
        getCookie: function(url) { return __lrWait('cookieGet', url); },
        set: function(url, value) { sendMessage('setCookie', JSON.stringify([url, value])); },
        setCookie: function(url, value) { sendMessage('setCookie', JSON.stringify([url, value])); },
        remove: function(url) { sendMessage('removeCookie', JSON.stringify(url)); },
        removeCookie: function(url) { sendMessage('removeCookie', JSON.stringify(url)); },
        all: function() { return __lrWait('allCookies', ''); },
        // Legado CookieStore：「a=1; b=2」與物件互轉，空值的項目略過。
        cookieToMap: function(text) {
          return sendMessage('cookieToMap', JSON.stringify(String(text == null ? '' : text)));
        },
        mapToCookie: function(map) {
          if (map == null || !Object.keys(map).length) return null;
          return sendMessage('mapToCookie', JSON.stringify(map));
        },
        // 這個網站的 Cookie 裡 key 那一項的值，沒有時是空字串。
        getKey: function(url, key) {
          var value = cookie.cookieToMap(cookie.getCookie(url))[key];
          return value == null ? '' : value;
        },
        // 合併進原本的 Cookie：同名的換成新的，其他留著。
        replaceCookie: function(url, value) {
          if (!url || !value) return;
          sendMessage('replaceCookie', JSON.stringify([String(url), String(value)]));
        },
        // 清掉夜讀存的所有網站的 Cookie。
        clear: function() { sendMessage('clearCookies', '""'); }
      };

      var cache = {
        get: function(key) { return __lrWait('getCache', key); },
        getFile: function(key) { return __lrWait('getCache', key); },
        put: function(key, value, time) { sendMessage('putCache', JSON.stringify([key, value, time || 0])); },
        putFile: function(key, value, time) { sendMessage('putCache', JSON.stringify([key, value, time || 0])); },
        delete: function(key) {
          sendMessage('deleteCache', JSON.stringify(key));
          cache.deleteMemory(key);
        },
        // Legado CacheManager 的數字讀法：讀不成數字時是 null。
        getInt: function(key) {
          var text = cache.get(key);
          return /^[+-]?\d+$/.test(String(text)) ? Number(text) : null;
        },
        getLong: function(key) { return cache.getInt(key); },
        getDouble: function(key) {
          var text = cache.get(key);
          if (text == null || String(text).trim() === '') return null;
          var value = Number(text);
          return isNaN(value) ? null : value;
        },
        getFloat: function(key) { return cache.getDouble(key); },
        // 只在記憶體、App 關掉就沒了的快取。
        putMemory: function(key, value) {
          sendMessage('cachePutMemory', JSON.stringify([String(key), __lrNormalizeRuleResult(value)]));
        },
        getFromMemory: function(key) {
          var value = sendMessage('cacheGetMemory', JSON.stringify(String(key)));
          return value === undefined ? null : value;
        },
        deleteMemory: function(key) { sendMessage('cacheDeleteMemory', JSON.stringify(String(key))); }
      };

      var source = source || {};
      source.getKey = function() { return String(source.key || ''); };
      source.getTag = function() {
        return String(source.tag || source.bookSourceName || '');
      };
      source.getVariable = function() { return __lrWait('sourceGetVariable', ''); };
      source.setVariable = function(value) {
        sendMessage('sourceSetVariable', JSON.stringify(value == null ? null : String(value)));
        return value;
      };
      source.getHeaderMap = function(hasLoginHeader) {
        var includeLoginHeader = hasLoginHeader === undefined ? true : !!hasLoginHeader;
        var headerMap = sendMessage('sourceGetHeaderMap', JSON.stringify(includeLoginHeader));
        if (headerMap == null || headerMap === '') return {};
        if (typeof headerMap === 'string') {
          try { return JSON.parse(headerMap); } catch (e) { return {}; }
        }
        return headerMap;
      };
      source.getLoginInfo = function() { return __lrWait('sourceGetLoginInfo', ''); };
      source.putLoginInfo = function(info) { sendMessage('sourcePutLoginInfo', JSON.stringify(info)); };
      source.getLoginInfoMap = function() {
        try { return JSON.parse(source.getLoginInfo()); } catch(e) { return {}; }
      };
      source.removeLoginInfo = function() { sendMessage('sourceRemoveLoginInfo', '""'); };
      source.getLoginHeader = function() { return __lrWait('sourceGetLoginHeader', ''); };
      source.getLoginHeaderMap = function() {
        try { return JSON.parse(source.getLoginHeader()); } catch(e) { return {}; }
      };
      source.putLoginHeader = function(header) {
        sendMessage('sourcePutLoginHeader', JSON.stringify(String(header)));
      };
      source.removeLoginHeader = function() { sendMessage('sourceRemoveLoginHeader', '""'); };
      source.put = function(key, value) { sendMessage('sourcePut', JSON.stringify([key, value])); };
      source.get = function(key) { return __lrWait('sourceGet', key); };
      // Legado BaseSource：登入網址裡的程式（去掉 @js: 或 <js></js>）。
      source.getLoginJs = function() {
        var js = source.loginUrl;
        if (js == null) return null;
        js = String(js);
        if (js.indexOf('@js:') === 0) return js.substring(4);
        if (js.indexOf('<js>') === 0) return js.substring(4, js.lastIndexOf('<'));
        return js;
      };
      // 書源程式自己呼叫登入：跑登入網址裡的程式，再呼叫它的 login()。要使用者
      // 操作的步驟在登入頁以外照樣立刻失敗（ADR 0038）。
      source.login = function() {
        var js = source.getLoginJs();
        if (!js || !String(js).trim()) return;
        (0, eval)(js + "\nif (typeof login == 'function') { login.apply(this); }" +
          " else { throw ('Function login not implements!!!'); }");
      };
      source.evalJS = function(js) { return (0, eval)(String(js)); };
      source.getSource = function() { return source; };

      /// Rhino 的 importClass／importPackage：把類別照名稱放進全域。
      function importClass(clazz) {
        if (clazz == null) return clazz;
        var name = clazz.__lrClassName || (typeof clazz === 'function' ? clazz.name : null);
        if (name) globalThis[name] = clazz;
        return clazz;
      }
      function importPackage(pkg) {
        for (var i = 0; i < arguments.length; i++) {
          var current = arguments[i] || {};
          for (var key in current) {
            if (Object.prototype.hasOwnProperty.call(current, key)) {
              globalThis[key] = current[key];
            }
          }
        }
      }

      /// Rhino 的 `new JavaImporter(類別或套件, …)`：傳入的類別照名稱、套件照
      /// 裡面的成員放進這個物件，給 `with (importer) {…}` 用。
      function JavaImporter() {
        for (var i = 0; i < arguments.length; i++) {
          var item = arguments[i];
          if (item == null) continue;
          var name = item.__lrClassName || (typeof item === 'function' ? item.name : null);
          if (name) {
            this[name] = item;
          } else if (typeof item === 'object') {
            for (var key in item) {
              if (Object.prototype.hasOwnProperty.call(item, key)) this[key] = item[key];
            }
          }
        }
        this.importClass = function(clazz) {
          var name = clazz && (clazz.__lrClassName || (typeof clazz === 'function' ? clazz.name : null));
          if (name) this[name] = clazz;
          return clazz;
        };
        this.importPackage = function() {
          for (var i = 0; i < arguments.length; i++) {
            var pkg = arguments[i] || {};
            for (var key in pkg) {
              if (Object.prototype.hasOwnProperty.call(pkg, key)) {
                this[key] = pkg[key];
              }
            }
          }
          return this;
        };
      }

      function normalizeByteArray(value) {
        if (value == null) return [];
        if (Array.isArray(value)) return value;
        if (typeof value === 'string') {
          try {
            var parsed = JSON.parse(value);
            if (Array.isArray(parsed)) return parsed;
          } catch (e) {}
          return [];
        }
        if (typeof value === 'object') {
          if (typeof value.length === 'number') {
            var arr = [];
            for (var i = 0; i < value.length; i++) {
              arr.push(value[i]);
            }
            return arr;
          }
          var keys = Object.keys(value).filter(function(key) {
            return /^[0-9]+$/.test(key);
          }).sort(function(a, b) {
            return Number(a) - Number(b);
          });
          if (keys.length > 0) {
            return keys.map(function(key) {
              return value[key];
            });
          }
        }
        return [];
      }

      function JavaString(value) {
        if (value != null && (Array.isArray(value) || (typeof value === 'object' && typeof value.length === 'number'))) {
          this._value = java.bytesToStr(normalizeByteArray(value), 'UTF-8');
        } else {
          this._value = globalThis.String(value == null ? '' : value);
        }
      }
      JavaString.prototype.getBytes = function(charset) {
        return java.strToBytes(this._value, charset || 'UTF-8');
      };
      JavaString.prototype.length = function() {
        return this._value.length;
      };
      JavaString.prototype.substring = function(start, end) {
        return this._value.substring(start, end);
      };
      JavaString.prototype.charAt = function(index) {
        return this._value.charAt(index);
      };
      JavaString.prototype.indexOf = function(value) {
        return this._value.indexOf(value);
      };
      JavaString.prototype.startsWith = function(value) {
        return this._value.startsWith(value);
      };
      JavaString.prototype.endsWith = function(value) {
        return this._value.endsWith(value);
      };
      JavaString.prototype.split = function(separator) {
        return this._value.split(separator);
      };
      JavaString.prototype.replace = function(pattern, replacement) {
        return this._value.replace(pattern, replacement);
      };
      JavaString.prototype.replaceAll = function(pattern, replacement) {
        if (typeof globalThis.__lrJavaReplaceAll === 'function') {
          return globalThis.__lrJavaReplaceAll(this._value, pattern, replacement);
        }
        return this._value.replace(pattern, replacement);
      };
      JavaString.prototype.replaceFirst = function(pattern, replacement) {
        if (typeof globalThis.__lrJavaReplaceFirst === 'function') {
          return globalThis.__lrJavaReplaceFirst(this._value, pattern, replacement);
        }
        return this._value.replace(pattern, replacement);
      };
      JavaString.prototype.match = function(pattern) {
        if (typeof globalThis.__lrJavaMatch === 'function') {
          return globalThis.__lrJavaMatch(this._value, pattern);
        }
        return this._value.match(pattern);
      };
      JavaString.prototype.contains = function(value) {
        return this._value.indexOf(value) !== -1;
      };
      JavaString.prototype.toUpperCase = function() {
        return this._value.toUpperCase();
      };
      JavaString.prototype.toLowerCase = function() {
        return this._value.toLowerCase();
      };
      JavaString.prototype.trim = function() {
        return this._value.trim();
      };
      JavaString.prototype.toString = function() {
        return this._value;
      };
      JavaString.prototype.valueOf = function() {
        return this._value;
      };

      function ByteArrayOutputStream() {
        this._bytes = [];
      }
      ByteArrayOutputStream.prototype.write = function(bytes, offset, len) {
        // write(int)：寫一個位元組，同 Java。
        if (typeof bytes === 'number') {
          this._bytes.push(bytes & 0xFF);
          return;
        }
        bytes = normalizeByteArray(bytes);
        var start = offset || 0;
        var end = len == null ? bytes.length : start + len;
        for (var i = start; i < end && i < bytes.length; i++) {
          this._bytes.push(bytes[i]);
        }
      };
      ByteArrayOutputStream.prototype.toString = function(charset) {
        return java.bytesToStr(this._bytes, charset || 'UTF-8');
      };
      ByteArrayOutputStream.prototype.close = function() {};

      function ByteArrayInputStream(bytes) {
        this._bytes = normalizeByteArray(bytes);
      }
      ByteArrayInputStream.prototype.close = function() {};
      ByteArrayOutputStream.prototype.toByteArray = function() { return this._bytes.slice(); };
      ByteArrayOutputStream.prototype.size = function() { return this._bytes.length; };
      ByteArrayOutputStream.prototype.reset = function() { this._bytes = []; };
      ByteArrayInputStream.prototype._pos = 0;
      // read()：一個位元組，讀完是 -1；read(buffer[, off, len])：讀進 buffer，
      // 傳回讀了幾個。
      ByteArrayInputStream.prototype.read = function(buffer, off, len) {
        if (buffer === undefined) {
          return this._pos < this._bytes.length ? this._bytes[this._pos++] : -1;
        }
        if (this._pos >= this._bytes.length) return -1;
        var start = off || 0;
        var count = Math.min(len == null ? buffer.length - start : len, this._bytes.length - this._pos);
        for (var i = 0; i < count; i++) buffer[start + i] = this._bytes[this._pos++];
        return count;
      };
      ByteArrayInputStream.prototype.available = function() { return this._bytes.length - this._pos; };

      function GZIPInputStream(inputStream) {
        this._bytes = normalizeByteArray(
          sendMessage('_gunzipBytes', JSON.stringify(inputStream._bytes || []))
        );
        this._pos = 0;
      }
      GZIPInputStream.prototype.read = function(buffer) {
        if (this._pos >= this._bytes.length) {
          return -1;
        }
        var count = Math.min(buffer.length, this._bytes.length - this._pos);
        for (var i = 0; i < count; i++) {
          buffer[i] = this._bytes[this._pos++];
        }
        return count;
      };
      GZIPInputStream.prototype.close = function() {};

      var Base64 = {
        getDecoder: function() {
          return {
            decode: function(value) {
              return normalizeByteArray(
                sendMessage(
                  '_base64DecodeToBytes',
                  JSON.stringify(value == null ? '' : value.toString())
                )
              );
            }
          };
        }
      };

      var Arrays = {
        copyOfRange: function(value, start, end) {
          return normalizeByteArray(value).slice(start, end);
        }
      };

      var Integer = {
        parseInt: function(value, radix) {
          return globalThis.parseInt(value, radix == null ? 10 : radix);
        }
      };

      function SecretKeySpec(bytes, algorithm) {
        if (!(this instanceof SecretKeySpec)) {
          return new SecretKeySpec(bytes, algorithm);
        }
        this.bytes = normalizeByteArray(bytes);
        this.algorithm = algorithm || '';
      }

      function IvParameterSpec(bytes) {
        if (!(this instanceof IvParameterSpec)) {
          return new IvParameterSpec(bytes);
        }
        this.bytes = normalizeByteArray(bytes);
      }

      function GCMParameterSpec(tagBits, iv) {
        if (!(this instanceof GCMParameterSpec)) {
          return new GCMParameterSpec(tagBits, iv);
        }
        this.tagBits = Number(tagBits);
        this.bytes = normalizeByteArray(iv);
      }
      GCMParameterSpec.prototype.getTLen = function() { return this.tagBits; };
      GCMParameterSpec.prototype.getIV = function() { return this.bytes; };

      /// 規則 JS 的加解密參數：位元組陣列照原樣，其他（含 java.lang.String）
      /// 轉成字串，由 Dart 照 UTF-8 轉成位元組。
      function __lrCryptoArg(value) {
        if (value == null) return null;
        if (typeof value === 'string') return value;
        if (Array.isArray(value) ||
            (typeof value === 'object' && typeof value.length === 'number')) {
          return normalizeByteArray(value);
        }
        return String(value);
      }

      /// 空字串與空陣列當成沒給（Legado 不設空的 IV）。
      function __lrEmptyToNull(value) {
        if (value == null) return null;
        if ((typeof value === 'string' || Array.isArray(value)) && value.length === 0) {
          return null;
        }
        return value;
      }

      /// RSA 與簽章物件的金鑰：兩個都沒設定時照 Hutool 產生一組 1024 位元
      /// 的金鑰（第一次用到時才產生）。
      function __lrKeyPairState() {
        var state = {
          publicKey: null,
          privateKey: null,
          ensure: function() {
            if (state.publicKey != null || state.privateKey != null) return;
            var pair = JSON.parse(sendMessage('rsaGenerateKeyPair', JSON.stringify(1024)));
            state.publicKey = pair.publicKey;
            state.privateKey = pair.privateKey;
          },
          accessors: function(target) {
            function bytes(key) {
              return typeof key === 'string' ? java.base64DecodeToByteArray(key) : key;
            }
            target.getPublicKeyBase64 = function() { state.ensure(); return java.base64Encode(bytes(state.publicKey)); };
            target.getPrivateKeyBase64 = function() { state.ensure(); return java.base64Encode(bytes(state.privateKey)); };
            target.getPublicKey = function() { state.ensure(); var b = bytes(state.publicKey); return { getEncoded: function() { return b; } }; };
            target.getPrivateKey = function() { state.ensure(); var b = bytes(state.privateKey); return { getEncoded: function() { return b; } }; };
            return target;
          }
        };
        return state;
      }

      function __lrRandomBytes(count) {
        return normalizeByteArray(sendMessage('_randomBytes', JSON.stringify(count)));
      }

      /// Hutool 的 SymmetricCrypto（java.createSymmetricCrypto 傳回的物件）。
      /// 和 Java 一樣：沒給金鑰時產生隨機金鑰；需要 IV 的模式加密時沒給 IV，
      /// 產生隨機 IV 並留著（getIV 取得），解密沒有 IV 則丟錯。
      function __lrSymmetricCrypto(transformation, key, iv, tagBits) {
        var parts = String(transformation).split('/');
        var algorithm = parts[0].trim().toUpperCase();
        var mode = (parts[1] || 'ECB').trim().toUpperCase().replace(/\d+$/, '');
        var blockSize = algorithm === 'AES' ? 16 : 8;
        var state = {
          transformation: String(transformation),
          key: __lrEmptyToNull(__lrCryptoArg(key)),
          iv: __lrEmptyToNull(__lrCryptoArg(iv)),
          tagBits: tagBits || 128
        };
        if (state.key == null) {
          state.key = __lrRandomBytes(
            algorithm === 'AES' ? 16 : algorithm === 'DES' ? 8 : 24
          );
        }
        function call(action, data, format, charset) {
          if (action === 'encrypt' && state.iv == null && mode !== 'ECB') {
            state.iv = __lrRandomBytes(mode === 'GCM' ? 12 : blockSize);
          }
          return sendMessage('symmetricCrypto', JSON.stringify([
            action, state.transformation, state.key, state.iv,
            __lrCryptoArg(data), format, charset ? String(charset) : 'UTF-8',
            state.tagBits
          ]));
        }
        var crypto = {
          setIv: function(value) { state.iv = __lrEmptyToNull(__lrCryptoArg(value)); return crypto; },
          getIV: function() { return state.iv; },
          getSecretKey: function() {
            return {
              getEncoded: function() {
                return typeof state.key === 'string' ? java.strToBytes(state.key) : state.key;
              },
              getAlgorithm: function() { return algorithm; }
            };
          },
          decrypt: function(data) { return normalizeByteArray(call('decrypt', data, 'bytes')); },
          decryptStr: function(data, charset) { return call('decrypt', data, 'string', charset); },
          encrypt: function(data, charset) { return normalizeByteArray(call('encrypt', data, 'bytes', charset)); },
          encryptBase64: function(data, charset) { return call('encrypt', data, 'base64', charset); },
          encryptHex: function(data, charset) { return call('encrypt', data, 'hex', charset); }
        };
        return crypto;
      }

      /// javax.crypto.Cipher：輸入輸出都是位元組，和 Java 一樣。
      function CipherInstance(transformation) {
        this._transformation = transformation || 'AES/ECB/PKCS5Padding';
        this._mode = 1;
        this._crypto = null;
        this._buffer = [];
      }
      CipherInstance.prototype.init = function(mode, key, spec) {
        this._mode = mode;
        this._crypto = __lrSymmetricCrypto(
          this._transformation,
          key && key.bytes ? key.bytes : key,
          spec && spec.bytes ? spec.bytes : null,
          spec && spec.tagBits ? spec.tagBits : 128
        );
        this._buffer = [];
      };
      CipherInstance.prototype.update = function(data) {
        var bytes = typeof data === 'string' ? java.strToBytes(data) : normalizeByteArray(data);
        for (var i = 0; i < bytes.length; i++) this._buffer.push(bytes[i]);
        return [];
      };
      CipherInstance.prototype.doFinal = function(data) {
        if (data != null) this.update(data);
        var input = this._buffer;
        this._buffer = [];
        return this._mode === 1 ? this._crypto.encrypt(input) : this._crypto.decrypt(input);
      };
      CipherInstance.prototype.getIV = function() {
        return this._crypto ? this._crypto.getIV() : null;
      };

      var Cipher = {
        ENCRYPT_MODE: 1,
        DECRYPT_MODE: 2,
        getInstance: function(transformation) {
          return new CipherInstance(transformation);
        }
      };

      // ─── 書源常用的其他 Java 類別（Rhino 讓規則 JS 直接用整個 Java）──
      function __lrNamed(name, value) {
        Object.defineProperty(value, '__lrClassName', { value: name, enumerable: false });
        return value;
      }
      function __lrHide(target, name, fn) {
        Object.defineProperty(target, name, { value: fn, enumerable: false, configurable: true, writable: true });
      }

      var Thread = __lrNamed('Thread', {
        sleep: function(ms) { sendMessage('_sleep', JSON.stringify(Number(ms) || 0)); }
      });
      var LockSupport = __lrNamed('LockSupport', {
        parkNanos: function(blockerOrNanos, nanos) {
          var n = nanos === undefined ? blockerOrNanos : nanos;
          sendMessage('_sleep', JSON.stringify(Math.floor((Number(n) || 0) / 1e6)));
        }
      });
      var JavaSystem = __lrNamed('System', {
        currentTimeMillis: function() { return __lrJsDate.now(); },
        nanoTime: function() { return __lrJsDate.now() * 1e6; },
        arraycopy: function(src, srcPos, dest, destPos, length) {
          for (var i = 0; i < length; i++) dest[destPos + i] = src[srcPos + i];
        }
      });

      function StringBuilder(init) { this._s = init == null || typeof init === 'number' ? '' : String(init); }
      StringBuilder.prototype.append = function(v) { this._s += String(v); return this; };
      StringBuilder.prototype.insert = function(i, v) { this._s = this._s.substring(0, i) + String(v) + this._s.substring(i); return this; };
      StringBuilder.prototype.length = function() { return this._s.length; };
      StringBuilder.prototype.charAt = function(i) { return this._s.charAt(i); };
      StringBuilder.prototype.reverse = function() { this._s = this._s.split('').reverse().join(''); return this; };
      StringBuilder.prototype.setLength = function(n) { this._s = this._s.substring(0, n); };
      StringBuilder.prototype.deleteCharAt = function(i) { this._s = this._s.substring(0, i) + this._s.substring(i + 1); return this; };
      StringBuilder.prototype.toString = function() { return this._s; };

      /// java.util.HashMap／LinkedHashMap：照放進去的順序；交回 Dart 時是一般
      /// 物件（[__lrNormalizeRuleResult] 看 __lrMap）。
      function HashMap(init) {
        Object.defineProperty(this, '_d', { value: {}, writable: true });
        Object.defineProperty(this, '_k', { value: [], writable: true });
        if (init != null && typeof init === 'object') this.putAll(init);
      }
      HashMap.prototype.__lrMap = true;
      HashMap.prototype.put = function(k, v) {
        var key = String(k);
        var old = Object.prototype.hasOwnProperty.call(this._d, key) ? this._d[key] : null;
        if (old === null && !Object.prototype.hasOwnProperty.call(this._d, key)) this._k.push(key);
        this._d[key] = v;
        return old;
      };
      HashMap.prototype.get = function(k) {
        var key = String(k);
        return Object.prototype.hasOwnProperty.call(this._d, key) ? this._d[key] : null;
      };
      HashMap.prototype.getOrDefault = function(k, d) { return this.containsKey(k) ? this.get(k) : d; };
      HashMap.prototype.containsKey = function(k) { return Object.prototype.hasOwnProperty.call(this._d, String(k)); };
      HashMap.prototype.containsValue = function(v) { var d = this._d; return this._k.some(function(k) { return d[k] === v; }); };
      HashMap.prototype.remove = function(k) {
        var key = String(k);
        if (!this.containsKey(key)) return null;
        var old = this._d[key];
        delete this._d[key];
        this._k.splice(this._k.indexOf(key), 1);
        return old;
      };
      HashMap.prototype.size = function() { return this._k.length; };
      HashMap.prototype.isEmpty = function() { return this._k.length === 0; };
      HashMap.prototype.clear = function() { this._d = {}; this._k = []; };
      HashMap.prototype.keySet = function() { return __lrJavaList(this._k); };
      HashMap.prototype.values = function() { var d = this._d; return __lrJavaList(this._k.map(function(k) { return d[k]; })); };
      HashMap.prototype.entrySet = function() {
        var d = this._d;
        return __lrJavaList(this._k.map(function(k) {
          return { key: k, value: d[k], getKey: function() { return k; }, getValue: function() { return d[k]; } };
        }));
      };
      HashMap.prototype.putAll = function(map) {
        var self = this;
        if (map && map.__lrMap) map._k.forEach(function(k) { self.put(k, map._d[k]); });
        else for (var k in map) if (Object.prototype.hasOwnProperty.call(map, k)) self.put(k, map[k]);
      };
      HashMap.prototype.forEach = function(fn) { var d = this._d; this._k.forEach(function(k) { fn(k, d[k]); }); };
      HashMap.prototype.toJSON = function() { var o = {}, d = this._d; this._k.forEach(function(k) { o[k] = d[k]; }); return o; };
      HashMap.prototype.toString = function() {
        var d = this._d;
        return '{' + this._k.map(function(k) { return k + '=' + d[k]; }).join(', ') + '}';
      };
      var LinkedHashMap = __lrNamed('LinkedHashMap', function(init) { return new HashMap(init); });
      var TreeMap = __lrNamed('TreeMap', function(init) { return new HashMap(init); });

      /// java.util.ArrayList／LinkedList：JS 陣列加上 Java List 的方法。
      function ArrayList(init) {
        var list = [];
        if (init != null && typeof init === 'object') {
          var items = typeof init.toArray === 'function' ? init.toArray() : init;
          for (var i = 0; i < items.length; i++) list.push(items[i]);
        }
        __lrHide(list, 'add', function(a, b) {
          if (b === undefined) { list.push(a); return true; }
          list.splice(a, 0, b);
        });
        __lrHide(list, 'get', function(i) { return list[i]; });
        __lrHide(list, 'set', function(i, v) { var old = list[i]; list[i] = v; return old; });
        __lrHide(list, 'size', function() { return list.length; });
        __lrHide(list, 'isEmpty', function() { return list.length === 0; });
        __lrHide(list, 'contains', function(v) { return list.indexOf(v) >= 0; });
        __lrHide(list, 'remove', function(v) {
          if (typeof v === 'number') return list.splice(v, 1)[0];
          var i = list.indexOf(v);
          if (i < 0) return false;
          list.splice(i, 1);
          return true;
        });
        __lrHide(list, 'addAll', function(more) {
          var items = typeof more.toArray === 'function' ? more.toArray() : more;
          for (var j = 0; j < items.length; j++) list.push(items[j]);
          return true;
        });
        __lrHide(list, 'clear', function() { list.length = 0; });
        __lrHide(list, 'toArray', function() { return list.slice(); });
        return list;
      }
      var LinkedList = __lrNamed('LinkedList', function(init) { return new ArrayList(init); });
      function HashSet(init) {
        var set = new ArrayList();
        __lrHide(set, 'add', function(v) { if (set.indexOf(v) >= 0) return false; set.push(v); return true; });
        __lrHide(set, 'addAll', function(more) {
          var items = typeof more.toArray === 'function' ? more.toArray() : more;
          var changed = false;
          for (var j = 0; j < items.length; j++) changed = set.add(items[j]) || changed;
          return changed;
        });
        if (init != null) set.addAll(init);
        return set;
      }

      var UUID = __lrNamed('UUID', {
        randomUUID: function() {
          var id = String(java.randomUUID());
          return { toString: function() { return id; } };
        }
      });
      // importClass(java.util.Date) 會像 Rhino 一樣蓋掉 JS 的 Date，這裡用原本的。
      var __lrJsDate = Date;
      function JavaDate(ms) { this._t = ms == null ? __lrJsDate.now() : Number(ms); }
      JavaDate.prototype.getTime = function() { return this._t; };
      JavaDate.prototype.toString = function() { return new __lrJsDate(this._t).toString(); };
      __lrNamed('Date', JavaDate);
      /// java.text.SimpleDateFormat：format 支援 y M d H h m s S a 與 '文字'。
      function SimpleDateFormat(pattern) { this._p = String(pattern || 'yyyy-MM-dd HH:mm:ss'); }
      SimpleDateFormat.prototype.format = function(date) {
        var t = date == null ? __lrJsDate.now() : (typeof date.getTime === 'function' ? date.getTime() : Number(date));
        var d = new __lrJsDate(t);
        function pad(n, w) { n = String(n); while (n.length < w) n = '0' + n; return n; }
        return this._p.replace(/'([^']*)'|y+|M+|d+|H+|h+|m+|s+|S+|a/g, function(token, literal) {
          if (literal !== undefined) return literal;
          var w = token.length;
          switch (token.charAt(0)) {
            case 'y': return w === 2 ? pad(d.getFullYear() % 100, 2) : pad(d.getFullYear(), w);
            case 'M': return pad(d.getMonth() + 1, w);
            case 'd': return pad(d.getDate(), w);
            case 'H': return pad(d.getHours(), w);
            case 'h': return pad(d.getHours() % 12 || 12, w);
            case 'm': return pad(d.getMinutes(), w);
            case 's': return pad(d.getSeconds(), w);
            case 'S': return pad(d.getMilliseconds(), w);
            case 'a': return d.getHours() < 12 ? 'AM' : 'PM';
          }
          return token;
        });
      };

      /// java.security.MessageDigest：update 累積位元組，digest 傳回位元組。
      var MessageDigest = __lrNamed('MessageDigest', {
        getInstance: function(algorithm) {
          var buffer = [];
          function bytesOf(v) {
            return typeof v === 'string' || v instanceof JavaString ? java.strToBytes(String(v), 'UTF-8') : normalizeByteArray(v);
          }
          return {
            update: function(v, off, len) {
              var b = bytesOf(v);
              var start = off || 0;
              buffer = buffer.concat(b.slice(start, len == null ? b.length : start + len));
            },
            digest: function(v) {
              if (v !== undefined) this.update(v);
              var out = normalizeByteArray(sendMessage('_digestBytes', JSON.stringify([buffer, String(algorithm)])));
              buffer = [];
              return out;
            },
            reset: function() { buffer = []; },
            getAlgorithm: function() { return String(algorithm); }
          };
        }
      });

      /// javax.crypto.Mac：init 給 SecretKeySpec，doFinal 傳回位元組。
      var Mac = __lrNamed('Mac', {
        getInstance: function(algorithm) {
          var key = [], buffer = [];
          function bytesOf(v) {
            return typeof v === 'string' || v instanceof JavaString ? java.strToBytes(String(v), 'UTF-8') : normalizeByteArray(v);
          }
          return {
            init: function(spec) { key = normalizeByteArray(spec && spec.bytes !== undefined ? spec.bytes : spec); },
            update: function(v) { buffer = buffer.concat(bytesOf(v)); },
            doFinal: function(v) {
              if (v !== undefined) buffer = buffer.concat(bytesOf(v));
              var out = normalizeByteArray(sendMessage('_hmacBytes', JSON.stringify([buffer, String(algorithm), key])));
              buffer = [];
              return out;
            },
            reset: function() { buffer = []; },
            getAlgorithm: function() { return String(algorithm); }
          };
        }
      });
      /// java.security.SecureRandom。
      function SecureRandom() {}
      SecureRandom.prototype.nextBytes = function(bytes) {
        var random = normalizeByteArray(sendMessage('_randomBytes', JSON.stringify(bytes.length)));
        for (var i = 0; i < bytes.length; i++) bytes[i] = random[i];
      };
      SecureRandom.prototype.generateSeed = function(n) {
        return normalizeByteArray(sendMessage('_randomBytes', JSON.stringify(Number(n))));
      };
      SecureRandom.prototype.nextInt = function(bound) {
        var b = normalizeByteArray(sendMessage('_randomBytes', JSON.stringify(4)));
        var v = ((b[0] << 24) | (b[1] << 16) | (b[2] << 8) | b[3]) >>> 0;
        return bound == null ? (v | 0) : v % Number(bound);
      };

      /// java.nio.ByteBuffer：大端序寫入。
      var ByteBuffer = __lrNamed('ByteBuffer', {
        allocate: function(size) {
          var bytes = [];
          for (var i = 0; i < size; i++) bytes.push(0);
          var pos = 0;
          function putBytes(list) { for (var j = 0; j < list.length; j++) bytes[pos++] = list[j] & 0xFF; }
          return {
            put: function(v) { putBytes(typeof v === 'number' ? [v] : normalizeByteArray(v)); return this; },
            putInt: function(v) { putBytes([(v >>> 24) & 0xFF, (v >>> 16) & 0xFF, (v >>> 8) & 0xFF, v & 0xFF]); return this; },
            putShort: function(v) { putBytes([(v >>> 8) & 0xFF, v & 0xFF]); return this; },
            array: function() { return bytes.slice(); },
            position: function() { return pos; }
          };
        }
      });

      /// java.net.URL：和 java.toURL 用同一個拆網址。
      function JavaURL(a, b) {
        var spec = b === undefined ? String(a) : String(b);
        var base = b === undefined ? null : String(a);
        var parts = sendMessage('toURL', JSON.stringify([spec, base]));
        this._p = parts;
      }
      JavaURL.prototype.getHost = function() { return this._p.host; };
      JavaURL.prototype.getPort = function() { return this._p.port; };
      JavaURL.prototype.getProtocol = function() { return this._p.protocol; };
      JavaURL.prototype.getPath = function() { return this._p.pathname; };
      JavaURL.prototype.getQuery = function() { return this._p.query; };
      JavaURL.prototype.getRef = function() { return this._p.ref; };
      JavaURL.prototype.getFile = function() { return this._p.pathname + (this._p.query != null ? '?' + this._p.query : ''); };
      JavaURL.prototype.getAuthority = function() { return this._p.host + (this._p.port > 0 ? ':' + this._p.port : ''); };
      JavaURL.prototype.toString = function() { return this._p.href; };
      JavaURL.prototype.toExternalForm = JavaURL.prototype.toString;
      __lrNamed('URL', JavaURL);
      var URLEncoder = __lrNamed('URLEncoder', {
        encode: function(s, enc) { return java.encodeURI(s, enc || 'UTF-8'); }
      });
      /// java.net.URLDecoder：+ 變空白，連續的 %XX 照字元集解成文字。
      var URLDecoder = __lrNamed('URLDecoder', {
        decode: function(s, enc) {
          var text = String(s == null ? '' : s).replace(/\+/g, ' ');
          return text.replace(/(%[0-9a-fA-F]{2})+/g, function(run) {
            var bytes = run.substring(1).split('%').map(function(h) { return parseInt(h, 16); });
            return java.bytesToStr(bytes, enc || 'UTF-8');
          });
        }
      });
      function __lrNoSocket() { throw new Error('夜讀不支援規則 JS 直接開網路連線（java.net.Socket）'); }

      /// android.util.Base64：flags 照 Android（DEFAULT 每 76 字換行）。
      var AndroidBase64 = __lrNamed('Base64', {
        DEFAULT: 0, NO_PADDING: 1, NO_WRAP: 2, CRLF: 4, URL_SAFE: 8, NO_CLOSE: 16,
        encodeToString: function(data, flags) { return java.base64Encode(data, flags == null ? 0 : flags); },
        encode: function(data, flags) {
          return java.strToBytes(java.base64Encode(data, flags == null ? 0 : flags), 'US-ASCII');
        },
        decode: function(data, flags) {
          var text = typeof data === 'string' || data instanceof JavaString ? String(data) : java.bytesToStr(normalizeByteArray(data), 'US-ASCII');
          return java.base64DecodeToByteArray(text, flags == null ? 0 : flags) || [];
        }
      });
      Base64.getEncoder = function() {
        return {
          encodeToString: function(data) { return java.base64Encode(data, 2); },
          encode: function(data) { return java.strToBytes(java.base64Encode(data, 2), 'US-ASCII'); }
        };
      };
      Base64.getUrlEncoder = function() {
        return {
          encodeToString: function(data) { return java.base64Encode(data, 10); },
          encode: function(data) { return java.strToBytes(java.base64Encode(data, 10), 'US-ASCII'); }
        };
      };
      Base64.getUrlDecoder = Base64.getDecoder;
      Base64.getMimeDecoder = Base64.getDecoder;
      __lrNamed('Base64', Base64);

      /// com.jayway.jsonpath.JsonPath。
      var JsonPath = __lrNamed('JsonPath', {
        read: function(json, path) {
          var text = typeof json === 'string' || json instanceof JavaString ? String(json) : JSON.stringify(__lrNormalizeRuleResult(json));
          return sendMessage('_jsonPathRead', JSON.stringify([text, String(path)]));
        },
        parse: function(json) { return { read: function(path) { return JsonPath.read(json, path); } }; }
      });

      /// java.util.zip.Inflater／InflaterInputStream（zlib；nowrap 是沒有標頭的
      /// deflate），讀法和 GZIPInputStream 一樣。
      function Inflater(nowrap) { this._nowrap = !!nowrap; }
      Inflater.prototype.end = function() {};
      function InflaterInputStream(inputStream, inflater) {
        this._bytes = normalizeByteArray(sendMessage('_inflateBytes', JSON.stringify(
          [inputStream._bytes || [], !!(inflater && inflater._nowrap)]
        )));
        this._pos = 0;
      }
      InflaterInputStream.prototype.read = GZIPInputStream.prototype.read;
      InflaterInputStream.prototype.close = function() {};

      /// okhttp3.HttpUrl：書源拿來拆網址。
      var HttpUrl = __lrNamed('HttpUrl', {
        parse: function(url) {
          var u = new JavaURL(url);
          return {
            host: function() { return u.getHost(); },
            scheme: function() { return u.getProtocol(); },
            port: function() { return u.getPort() > 0 ? u.getPort() : (u.getProtocol() === 'https' ? 443 : 80); },
            encodedPath: function() { return u.getPath(); },
            query: function() { return u.getQuery(); },
            queryParameter: function(name) {
              var params = java.toURL(String(url)).searchParams || {};
              return params[name] == null ? null : params[name];
            },
            toString: function() { return u.toString(); }
          };
        }
      });
      HttpUrl.get = HttpUrl.parse;

      var Packages = {
        org: globalThis.org,
        java: {
          lang: {
            String: function(value) { return new JavaString(value); },
            Integer: Integer,
            Thread: Thread,
            System: JavaSystem,
            StringBuilder: StringBuilder
          },
          io: {
            ByteArrayOutputStream: ByteArrayOutputStream,
            ByteArrayInputStream: ByteArrayInputStream
          },
          util: {
            Arrays: Arrays,
            Base64: Base64,
            HashMap: HashMap,
            LinkedHashMap: LinkedHashMap,
            TreeMap: TreeMap,
            ArrayList: ArrayList,
            LinkedList: LinkedList,
            HashSet: HashSet,
            UUID: UUID,
            Date: JavaDate,
            zip: {
              GZIPInputStream: GZIPInputStream,
              Inflater: Inflater,
              InflaterInputStream: InflaterInputStream
            },
            concurrent: { locks: { LockSupport: LockSupport } }
          },
          text: { SimpleDateFormat: SimpleDateFormat },
          security: { MessageDigest: MessageDigest, SecureRandom: SecureRandom },
          nio: { ByteBuffer: ByteBuffer },
          net: {
            URL: JavaURL,
            URLEncoder: URLEncoder,
            URLDecoder: URLDecoder,
            Socket: __lrNoSocket,
            InetAddress: { getByName: __lrNoSocket },
            InetSocketAddress: __lrNoSocket
          }
        },
        javax: {
          crypto: {
            Cipher: Cipher,
            Mac: Mac,
            spec: {
              SecretKeySpec: SecretKeySpec,
              IvParameterSpec: IvParameterSpec,
              GCMParameterSpec: GCMParameterSpec
            }
          }
        },
        android: { util: { Base64: AndroidBase64 } },
        com: { jayway: { jsonpath: { JsonPath: JsonPath } } },
        okhttp3: { HttpUrl: HttpUrl }
      };
      // Rhino 的頂層套件名稱；`java` 被 Legado 的 java 物件佔走，同 Legado
      // 要寫 Packages.java。
      globalThis.android = Packages.android;
      globalThis.javax = Packages.javax;
      globalThis.com = Packages.com;
      globalThis.okhttp3 = Packages.okhttp3;
    ''');
  }
}
