import '../js_extensions_base.dart';

/// 注入 rule JS 可見的全域物件：`java` / `cookie` / `cache` / `source`
///
/// 設計上分兩類方法：
///
/// **A. 同步方法** — Dart 端 onMessage handler 必須同步回傳值，JS 端直接拿到
/// 字串/物件結果。例如 `md5Encode` / `base64Encode` / `hexEncode` / `put` 系列等。
///
/// **B. 非同步方法** — 透過 `__asyncCall(channel, payload)` 回傳一個 Promise：
///   - JS 分配 id 並在 `__lr.pendingResolvers[id]` 存放 resolver
///   - `sendMessage(channel, JSON.stringify([id, payload]))` 同步送往 Dart
///   - Dart handler 接到 `[id, payload]`，執行 async 工作後透過
///     `resolveJsPending(id, result)` / `rejectJsPending(id, err)` 重入 JS
///     resolve 該 Promise
///
/// 配合 [AnalyzeRule.evalJSAsync] 將使用者 rule JS 包在 async IIFE 內執行，
/// 並由 [AsyncJsRewriter] 自動在 `java.ajax(...)` 等呼叫前注入 `await`。
///
/// 白名單必須與 `lib/core/engine/js/async_js_rewriter.dart`
/// 的 `asyncMethodsByOwner` 保持同步。
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
        if (typeof value.toString === 'function') {
          var text = String(value.toString());
          if (/<[a-z][\s\S]*>/i.test(text)) {
            return { __html: text };
          }
        }
        return value;
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
        function buildRawResponse() {
          return {
            request: function() { return buildRawRequest(); },
            url: function() { return responseUrl(); },
            headers: function() { return res && res.headers ? res.headers : {}; },
            code: function() { return responseCode(); },
            message: function() { return responseMessage(); },
            isSuccessful: function() { return isSuccessfulStatus(); },
            toString: function() { return responseUrl(); }
          };
        }
        return {
          body: function() { return res.body; },
          url: function() { return responseUrl(); },
          code: function() { return responseCode(); },
          statusCode: function() { return responseCode(); },
          message: function() { return responseMessage(); },
          isSuccessful: function() { return isSuccessfulStatus(); },
          headers: function() { return res.headers; },
          header: function(name) { return getHeader(name); },
          raw: function() { return buildRawResponse(); },
          toString: function() { return responseUrl(); }
        };
      }

      var java = {
        // ─── async: HTTP ─────────────────────────────────────────
        ajax: function(url) { return __asyncCall('ajax', url); },
        ajaxAll: function(urlList) { return __asyncCall('ajaxAll', urlList); },
        cacheFile: function(url, saveTime) { return __asyncCall('cacheTextFile', [url, saveTime || 0]); },
        connect: function(url, header) {
          return __asyncCall(
            'connect',
            arguments.length > 1 ? [url, header || null] : url
          ).then(buildHttpResponse);
        },
        get: function(url, headers) {
          if (arguments.length <= 1) {
            return sendMessage('scopeGet', JSON.stringify(url));
          }
          return __asyncCall('get', [url, headers || {}]).then(buildHttpResponse);
        },
        post: function(url, body, headers) {
          return __asyncCall('post', [url, body, headers || {}]).then(buildHttpResponse);
        },
        head: function(url, headers) {
          return __asyncCall('head', [url, headers || {}]).then(buildHttpResponse);
        },

        // ─── async: WebView / I/O ────────────────────────────────
        webView: function(html, url, js) { return __asyncCall('webView', [html, url, js]); },
        webViewGetSource: function(html, url, js, sourceRegex) {
          return __asyncCall('webViewGetSource', [html, url, js, sourceRegex]);
        },
        webViewGetOverrideUrl: function(html, url, js, overrideUrlRegex) {
          return __asyncCall('webViewGetOverrideUrl', [html, url, js, overrideUrlRegex]);
        },
        startBrowserAwait: function(url, title) { return __asyncCall('startBrowserAwait', [url, title]); },
        getVerificationCode: function(imageUrl) { return __asyncCall('getVerificationCode', imageUrl); },
        downloadFile: function(url) { return __asyncCall('downloadFile', url); },
        importScript: function(path) { return __asyncCall('importScript', path); },
        readFile: function(path) { return __asyncCall('readFile', path); },
        readTxtFile: function(path, charset) { return __asyncCall('readTxtFile', [path, charset]); },
        getZipByteArrayContent: function(url, innerPath) { return __asyncCall('getZipByteArrayContent', [url, innerPath]); },
        unArchiveFile: function(zipPath) { return __asyncCall('unArchiveFile', zipPath); },
        getTxtInFolder: function(relPath) { return __asyncCall('getTxtInFolder', relPath); },

        // ─── sync: crypto / encoding ─────────────────────────────
        createSymmetricCrypto: function(transformation, key, iv) {
          return {
            decrypt: function(data) { return sendMessage('symmetricCrypto', JSON.stringify(['decrypt', transformation, key, iv, data, 'bytes'])); },
            decryptStr: function(data) { return sendMessage('symmetricCrypto', JSON.stringify(['decrypt', transformation, key, iv, data, 'string'])); },
            encrypt: function(data) { return sendMessage('symmetricCrypto', JSON.stringify(['encrypt', transformation, key, iv, data, 'bytes'])); },
            encryptBase64: function(data) { return sendMessage('symmetricCrypto', JSON.stringify(['encrypt', transformation, key, iv, data, 'base64'])); },
            encryptHex: function(data) { return sendMessage('symmetricCrypto', JSON.stringify(['encrypt', transformation, key, iv, data, 'hex'])); }
          };
        },
        md5Encode: function(str) { return new JavaString(sendMessage('_md5Encode', JSON.stringify(str))); },
        md5Encode16: function(str) { return new JavaString(sendMessage('_md5Encode16', JSON.stringify(str))); },
        digestHex: function(str, algorithm) {
          return new JavaString(sendMessage('_digest', JSON.stringify([str, algorithm, true])));
        },
        base64Encode: function(str) { return sendMessage('_base64Encode', JSON.stringify(str)); },
        base64Decode: function(str) { return sendMessage('_base64Decode', JSON.stringify(str)); },
        base64DecodeToByteArray: function(str) {
          return normalizeByteArray(
            sendMessage('_base64DecodeToBytes', JSON.stringify(str))
          );
        },
        hexEncodeToString: function(str) { return sendMessage('_hexEncode', JSON.stringify(str)); },
        hexDecodeToString: function(hex) { return sendMessage('_hexDecode', JSON.stringify(hex)); },
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
        toNumChapter: function(text) { return sendMessage('_toNumChapter', JSON.stringify(text)); },
        t2s: function(text) { return sendMessage('t2s', JSON.stringify(text)); },
        s2t: function(text) { return sendMessage('s2t', JSON.stringify(text)); },
        encodeURI: function(value) {
          return encodeURIComponent(String(value == null ? '' : value));
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
        aesBase64DecodeToString: function(data, key, transformation, iv) {
          return sendMessage('symmetricCrypto', JSON.stringify(['decrypt', transformation, key, iv, data, 'string']));
        },
        HMacHex: function(data, algorithm, key) {
          return new JavaString(
            sendMessage('_hmacHex', JSON.stringify([data, algorithm, key]))
          );
        },
        desEncodeToBase64String: function(data, key, transformation, iv) {
          return new JavaString(
            sendMessage(
              '_desEncodeToBase64String',
              JSON.stringify([data, key, transformation, iv])
            )
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
        toast: function(msg) { sendMessage('toast', JSON.stringify(msg)); },
        put: function(key, value) {
          var normalized = value == null ? '' : String(value);
          sendMessage('scopePut', JSON.stringify([key, normalized]));
          return normalized;
        },
        getString: function(rule) { return sendMessage('ruleGetString', JSON.stringify(rule)); },
        getStringList: function(rule) {
          return __lrJavaList(
            sendMessage('ruleGetStringList', JSON.stringify(rule))
          );
        },
        getElement: function(rule) { return sendMessage('ruleGetElement', JSON.stringify(rule)); },
        getElements: function(rule) { return sendMessage('ruleGetElements', JSON.stringify(rule)); },
        setContent: function(content, baseUrl) {
          sendMessage('ruleSetContent', JSON.stringify([content, baseUrl || null]));
          return null;
        },

        // ─── sync: TTF query/replace (sync helpers) ──────────────
        queryTTF: function(data, useCache) {
          var ttfId = sendMessage('queryTTF', JSON.stringify([data, useCache === undefined ? true : useCache]));
          return ttfId ? { _ttfId: ttfId } : null;
        },
        replaceFont: function(text, errTTF, correctTTF) {
          return sendMessage('replaceFont', JSON.stringify([text, errTTF ? errTTF._ttfId : null, correctTTF ? correctTTF._ttfId : null]));
        }
      };

      // ─── async: java.getCookie → 獨立 channel ─────────────────
      //
      // 提醒：rule JS 裡的 `java.getCookie(tag, key)` 與 `cookie.get(url)`
      // 走不同 Dart handler。前者是站點 Cookie 字串查詢，後者是單一 cookie。
      java.getCookie = function(tag, key) { return __asyncCall('getCookie', [tag, key || null]); };

      // ─── cookie / cache / source 全域物件 ────────────────────
      var cookie = {
        get: function(url) { return __asyncCall('cookieGet', url); },
        getCookie: function(url) { return __asyncCall('cookieGet', url); },
        set: function(url, value) { sendMessage('setCookie', JSON.stringify([url, value])); },
        setCookie: function(url, value) { sendMessage('setCookie', JSON.stringify([url, value])); },
        remove: function(url) { sendMessage('removeCookie', JSON.stringify(url)); },
        removeCookie: function(url) { sendMessage('removeCookie', JSON.stringify(url)); },
        all: function() { return __asyncCall('allCookies', ''); }
      };

      var cache = {
        get: function(key) { return __asyncCall('getCache', key); },
        getFile: function(key) { return __asyncCall('getCache', key); },
        put: function(key, value, time) { sendMessage('putCache', JSON.stringify([key, value, time || 0])); },
        putFile: function(key, value, time) { sendMessage('putCache', JSON.stringify([key, value, time || 0])); },
        delete: function(key) { sendMessage('deleteCache', JSON.stringify(key)); }
      };

      var source = source || {};
      source.getKey = function() { return String(source.key || ''); };
      source.getTag = function() {
        return String(source.tag || source.bookSourceName || '');
      };
      source.getVariable = function() { return __asyncCall('sourceGetVariable', ''); };
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
      source.getLoginInfo = function() { return __asyncCall('sourceGetLoginInfo', ''); };
      source.putLoginInfo = function(info) { sendMessage('sourcePutLoginInfo', JSON.stringify(info)); };
      source.getLoginInfoMap = function() {
        return source.getLoginInfo().then(function(info) {
          try { return JSON.parse(info); } catch(e) { return {}; }
        });
      };
      source.put = function(key, value) { sendMessage('sourcePut', JSON.stringify([key, value])); };
      source.get = function(key) { return __asyncCall('sourceGet', key); };

      function importClass(clazz) { return clazz; }

      function JavaImporter() {
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

      function CipherInstance(transformation) {
        this._transformation = transformation || 'AES/CBC/PKCS5Padding';
        this._mode = 2;
        this._key = [];
        this._iv = [];
      }
      CipherInstance.prototype.init = function(mode, key, iv) {
        this._mode = mode;
        this._key = key && key.bytes ? normalizeByteArray(key.bytes) : normalizeByteArray(key);
        this._iv = iv && iv.bytes ? normalizeByteArray(iv.bytes) : normalizeByteArray(iv);
      };
      CipherInstance.prototype.doFinal = function(data) {
        var crypto = java.createSymmetricCrypto(
          this._transformation,
          this._key,
          this._iv
        );
        if (this._mode === 1) {
          return normalizeByteArray(crypto.encrypt(data));
        }
        if (Array.isArray(data) || (data && typeof data === 'object' && typeof data.length === 'number')) {
          return crypto.decryptStr(java.base64Encode(normalizeByteArray(data)));
        }
        return crypto.decryptStr(data);
      };

      var Cipher = {
        getInstance: function(transformation) {
          return new CipherInstance(transformation);
        }
      };

      var Jsoup = {
        parse: function(html) {
          function createSelection(docRef, selector) {
            return {
              text: function() {
                return sendMessage('htmlSelectText', JSON.stringify([docRef.__html, selector]));
              },
              html: function() {
                return sendMessage('htmlSelectHtml', JSON.stringify([docRef.__html, selector]));
              },
              data: function() {
                return sendMessage('htmlSelectData', JSON.stringify([docRef.__html, selector]));
              },
              attr: function(name) {
                return sendMessage('htmlSelectAttr', JSON.stringify([docRef.__html, selector, name]));
              },
              attributes: function() {
                return __lrJavaList(
                  sendMessage(
                    'htmlSelectAttributes',
                    JSON.stringify([docRef.__html, selector])
                  )
                );
              },
              size: function() {
                return Number(
                  sendMessage('htmlSelectCount', JSON.stringify([docRef.__html, selector]))
                ) || 0;
              },
              eachText: function() {
                return __lrJavaList(
                  sendMessage('htmlSelectTextList', JSON.stringify([docRef.__html, selector]))
                );
              },
              select: function(childSelector) {
                return createSelection(
                  docRef,
                  selector + ' ' + String(childSelector || '')
                );
              },
              selectFirst: function(childSelector) {
                return Jsoup.parse(
                  sendMessage(
                    'htmlSelectHtml',
                    JSON.stringify([docRef.__html, selector + ' ' + childSelector + ':eq(0)'])
                  )
                );
              },
              remove: function() {
                docRef.__html = sendMessage('htmlRemove', JSON.stringify([docRef.__html, selector]));
                return docRef;
              },
              first: function() {
                return Jsoup.parse(
                  sendMessage('htmlSelectHtml', JSON.stringify([docRef.__html, selector + ':eq(0)']))
                );
              },
              get: function(index) {
                return Jsoup.parse(
                  sendMessage('htmlSelectHtml', JSON.stringify([docRef.__html, selector + ':eq(' + index + ')']))
                );
              },
              toArray: function() {
                var items = [];
                var count = this.size();
                for (var i = 0; i < count; i++) {
                  items.push(this.get(i));
                }
                return items;
              },
              toString: function() {
                return this.html();
              }
            };
          }
          var doc = {
            __html: String(html || ''),
            select: function(selector) {
              return createSelection(this, selector);
            },
            selectFirst: function(selector) {
              return Jsoup.parse(
                sendMessage('htmlSelectHtml', JSON.stringify([this.__html, selector + ':eq(0)']))
              );
            },
            text: function() {
              return sendMessage('htmlSelectText', JSON.stringify([this.__html, 'html']));
            },
            data: function() {
              return sendMessage('htmlSelectData', JSON.stringify([this.__html, 'html']));
            },
            attr: function(name) {
              return sendMessage(
                'htmlSelectAttr',
                JSON.stringify([this.__html, 'body > *:eq(0)', name])
              );
            },
            attributes: function() {
              return sendMessage(
                'htmlSelectAttributes',
                JSON.stringify([this.__html, 'body > *:eq(0)'])
              );
            },
            html: function() {
              return this.__html;
            },
            toString: function() {
              return this.__html;
            }
          };
          return doc;
        }
      };

      var org = org || {};
      org.jsoup = org.jsoup || {};
      org.jsoup.Jsoup = Jsoup;

      var Packages = {
        java: {
          lang: {
            String: function(value) { return new JavaString(value); },
            Integer: Integer
          },
          io: {
            ByteArrayOutputStream: ByteArrayOutputStream,
            ByteArrayInputStream: ByteArrayInputStream
          },
          util: {
            Arrays: Arrays,
            Base64: Base64,
            zip: {
              GZIPInputStream: GZIPInputStream
            }
          }
        },
        javax: {
          crypto: {
            Cipher: Cipher,
            spec: {
              SecretKeySpec: SecretKeySpec,
              IvParameterSpec: IvParameterSpec
            }
          }
        }
      };
    ''');
  }
}
