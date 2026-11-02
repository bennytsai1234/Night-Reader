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
        list.isEmpty = function() { return this.length === 0; };
        list.contains = function(value) {
          for (var i = 0; i < this.length; i++) {
            if (__lrJavaEquals(this[i], value)) return true;
          }
          return false;
        };
        list.iterator = function() { return __lrJavaIterator(this); };
        list.subList = function(from, to) { return __lrSubList(this, from, to); };
        return list;
      }

      /// Java 的 equals：有 equals 方法的物件照它比，其餘照值比。
      function __lrJavaEquals(a, b) {
        if (a == null || b == null) return a == b;
        if (typeof a === 'object' && typeof a.equals === 'function') return !!a.equals(b);
        return a === b;
      }

      /// List.subList：原清單 [from, to) 那一段，讀寫、清空都落在原清單上
      /// （書源寫 `list.subList(1, i).clear()` 刪掉原清單那幾項）。
      function __lrSubList(parent, from, to) {
        if (from < 0 || to > parent.length) {
          throw new Error('java.lang.IndexOutOfBoundsException: fromIndex: ' + from + ', toIndex: ' + to);
        }
        if (from > to) {
          throw new Error('java.lang.IllegalArgumentException: fromIndex(' + from + ') > toIndex(' + to + ')');
        }
        var view = __lrJavaList(parent.slice(from, to));
        var size = to - from;
        view.size = function() { return size; };
        view.get = function(i) {
          if (i < 0 || i >= size) throw new Error('java.lang.IndexOutOfBoundsException');
          return parent[from + i];
        };
        view.set = function(i, value) {
          var old = view.get(i);
          parent[from + i] = value;
          view[i] = value;
          return old;
        };
        view.clear = function() {
          parent.splice(from, size);
          view.length = 0;
          size = 0;
        };
        return view;
      }

      /// java.util.Iterator：書源照 Java 寫
      /// `var it = map.keySet().iterator(); while (it.hasNext()) it.next()`。
      function __lrJavaIterator(items) {
        var index = 0;
        return {
          hasNext: function() { return index < items.length; },
          next: function() {
            if (index >= items.length) {
              throw new Error('java.util.NoSuchElementException');
            }
            return items[index++];
          }
        };
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
              return __lrJavaMap(map);
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
            // OkHttp：轉址前的那一個回應（它的 Location 指向下一站）；沒有轉址
            // 時是 null。
            priorResponse: function() { return buildPriorResponse(); },
            toString: function() { return responseUrl(); }
          };
        }
        function buildPriorResponse() {
          var hops = res && Array.isArray(res.redirects) ? res.redirects : [];
          if (!hops.length) return null;
          var from = hops.length > 1 ? String(hops[hops.length - 2]) : String(res.requestUrl || '');
          var to = String(hops[hops.length - 1]);
          var priorHeaders = { location: to };
          return {
            request: function() {
              return { url: function() { return from; }, toString: function() { return from; } };
            },
            url: function() { return from; },
            code: function() { return 302; },
            isRedirect: function() { return true; },
            header: function(name) { return String(name).toLowerCase() === 'location' ? to : null; },
            headers: function() {
              var h = {};
              Object.defineProperty(h, 'get', { value: function(n) { return priorHeaders[String(n).toLowerCase()] || null; } });
              h.location = to;
              return h;
            },
            priorResponse: function() { return null; },
            toString: function() { return from; }
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
            return __lrJavaMap(map);
          },
          cookie: function(name) {
            var value = response.cookies().get(name);
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
        // 檔案函式的路徑都相對快取資料夾（同 Legado，見 js_file_extensions）。
        downloadFile: function(a, b) {
          return __lrWait('downloadFile', b === undefined ? [String(a)] : [String(a), String(b)]);
        },
        importScript: function(path) { return __lrWait('importScript', path); },
        getFile: function(path) {
          return new Packages.java.io.File(__lrWait('getFile', String(path)));
        },
        readFile: function(path) { return __lrWait('readFile', String(path)); },
        readTxtFile: function(path, charset) {
          return __lrWait('readTxtFile', charset == null ? [String(path)] : [String(path), String(charset)]);
        },
        deleteFile: function(path) { return __lrWait('deleteFile', String(path)); },
        getZipByteArrayContent: function(url, innerPath) {
          return __lrWait('getZipByteArrayContent', [String(url), String(innerPath)]);
        },
        getZipStringContent: function(url, innerPath, charset) {
          var args = [String(url), String(innerPath)];
          if (charset != null) args.push(String(charset));
          return __lrWait('getZipStringContent', args);
        },
        unzipFile: function(zipPath) { return __lrWait('unzipFile', String(zipPath)); },
        unArchiveFile: function(zipPath) { return __lrWait('unArchiveFile', String(zipPath)); },
        getTxtInFolder: function(relPath) { return __lrWait('getTxtInFolder', String(relPath)); },

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
          if (str == null) return null;
          var arg = { d: __lrCryptoArg(str) };
          if (typeof charsetOrFlags === 'number') arg.f = charsetOrFlags;
          else if (charsetOrFlags != null) arg.c = String(charsetOrFlags);
          return __lrWait('_base64Decode', arg);
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
          if (rule == null || String(rule) === '') return null;
          return __lrJavaList(sendMessage('ruleGetStringList', JSON.stringify(
            [String(rule), __lrContentArg(content), !!isUrl]
          )));
        },
        getElement: function(rule) { return __lrJsoupDecode(sendMessage('ruleGetElement', JSON.stringify(String(rule)))); },
        getElements: function(rule) {
          var found = __lrJsoupDecode(sendMessage('ruleGetElements', JSON.stringify(String(rule))));
          return Array.isArray(found) ? __lrJsoupElements(found) : found;
        },
        // Legado 的 setContent、setBaseUrl 傳回規則解析器本身，可以接著呼叫；
        // setRedirectUrl 傳回改完的網址（java.net.URL），data: 或不是網址時
        // 不改。
        setContent: function(content, baseUrl) {
          sendMessage('ruleSetContent', JSON.stringify([content, baseUrl || null]));
          return java;
        },
        setBaseUrl: function(url) {
          if (url != null) sendMessage('ruleSetUrl', JSON.stringify(['base', String(url)]));
          return java;
        },
        setRedirectUrl: function(url) {
          var current = sendMessage('ruleSetUrl', JSON.stringify(['redirect', url == null ? null : String(url)]));
          return current ? new Packages.java.net.URL(current) : null;
        },
        // AnalyzeRule.evalJS(js, result)：跑一段 JS，result 是給的值。
        evalJS: function(js, result) {
          return (function(result) { return eval(String(js)); })(result);
        },
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
        // Legado JsURL：host、origin、pathname 與解碼後的 searchParams（Map）。
        toURL: function(url, baseUrl) {
          var parts = sendMessage('toURL', JSON.stringify([String(url), baseUrl == null ? null : String(baseUrl)]));
          if (!parts || !parts.protocol) throw new Error('java.net.MalformedURLException: ' + url);
          return {
            host: parts.host,
            origin: parts.origin,
            pathname: parts.pathname,
            searchParams: parts.searchParams == null ? null : __lrJavaMap(parts.searchParams)
          };
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
        // Legado CookieStore：「a=1; b=2」與 Map 互轉，空值的項目略過。傳回
        // Java 的 Map（get、put、keySet 都能用，也能照屬性讀）。
        cookieToMap: function(text) {
          return __lrJavaMap(sendMessage('cookieToMap', JSON.stringify(String(text == null ? '' : text))));
        },
        mapToCookie: function(map) {
          if (map == null) return null;
          var plain = map.__lrMap ? map.toJSON() : map;
          if (!Object.keys(plain).length) return null;
          return sendMessage('mapToCookie', JSON.stringify(plain));
        },
        // 這個網站的 Cookie 裡 key 那一項的值，沒有時是空字串。
        getKey: function(url, key) {
          var value = cookie.cookieToMap(cookie.getCookie(url)).get(key);
          return value == null ? '' : value;
        },
        // 合併進原本的 Cookie：同名的換成新的，其他留著。同 Legado 在回傳前
        // 合併好，緊接著讀就是新的。
        replaceCookie: function(url, value) {
          if (!url || !value) return;
          var old = cookie.getCookie(url);
          if (!old) {
            cookie.setCookie(url, value);
            return;
          }
          var merged = cookie.cookieToMap(old);
          merged.putAll(cookie.cookieToMap(value));
          cookie.setCookie(url, cookie.mapToCookie(merged));
        },
        // 清掉夜讀存的所有網站的 Cookie。
        clear: function() { sendMessage('clearCookies', '""'); }
      };

      /// Legado CacheManager。get／put 是資料庫的文字快取；putFile／getFile／
      /// getByteArray 是另一處的檔案快取（Legado 的 ACache），兩邊同名的鍵互不
      /// 相干；put 給位元組陣列時也存進檔案快取。夜讀的檔案快取存在同一個資料庫
      /// 的另一組鍵，內容存成 Base64。
      var __lrFileKey = function(key) { return '__lrFile_' + key; };
      var __lrIsBytes = function(v) {
        return Array.isArray(v) && v.length > 0 && v.every(function(b) { return typeof b === 'number'; });
      };
      /// 放進記憶體快取的物件本身：同一個 JS 環境裡取回的就是同一個物件（同
      /// Legado 的 LruCache）；別的環境取回的是 Dart 那邊存的內容。
      var __lrMemoryObjects = new Map();
      var cache = {
        get: function(key) { return __lrWait('getCache', key); },
        put: function(key, value, time) {
          if (__lrIsBytes(value)) {
            sendMessage('putCache', JSON.stringify([__lrFileKey(key), java.base64Encode(value), time || 0]));
            return;
          }
          sendMessage('putCache', JSON.stringify([key, String(value), time || 0]));
        },
        putFile: function(key, value, time) {
          sendMessage('putCache', JSON.stringify([__lrFileKey(key), java.base64Encode(String(value)), time || 0]));
        },
        getFile: function(key) {
          var stored = __lrWait('getCache', __lrFileKey(key));
          return stored ? java.base64Decode(stored) : null;
        },
        getByteArray: function(key) {
          var stored = __lrWait('getCache', __lrFileKey(key));
          return stored ? java.base64DecodeToByteArray(stored) : null;
        },
        delete: function(key) {
          sendMessage('deleteCache', JSON.stringify(key));
          sendMessage('deleteCache', JSON.stringify(__lrFileKey(key)));
          cache.deleteMemory(key);
        },
        // Kotlin 的 toIntOrNull／toLongOrNull／toDoubleOrNull／toFloatOrNull：
        // 超出範圍或不是那種數字時是 null。
        getInt: function(key) {
          var text = cache.get(key);
          if (!/^[+-]?\d+$/.test(String(text))) return null;
          var v = Number(text);
          return v >= -2147483648 && v <= 2147483647 ? v : null;
        },
        getLong: function(key) {
          var text = cache.get(key);
          if (!/^[+-]?\d+$/.test(String(text))) return null;
          var v = Number(text);
          return Math.abs(v) <= 9223372036854775807 ? v : null;
        },
        getDouble: function(key) {
          var text = cache.get(key);
          var match = /^\s*([+-]?(?:NaN|Infinity|(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?))[fFdD]?\s*$/.exec(String(text));
          return match ? Number(match[1]) : null;
        },
        getFloat: function(key) {
          var v = cache.getDouble(key);
          return v == null ? null : Math.fround(v);
        },
        putMemory: function(key, value) {
          __lrMemoryObjects.set(String(key), value);
          sendMessage('cachePutMemory', JSON.stringify([String(key), __lrNormalizeRuleResult(value)]));
        },
        getFromMemory: function(key) {
          if (__lrMemoryObjects.has(String(key))) return __lrMemoryObjects.get(String(key));
          var value = sendMessage('cacheGetMemory', JSON.stringify(String(key)));
          return value === undefined ? null : value;
        },
        deleteMemory: function(key) {
          __lrMemoryObjects.delete(String(key));
          sendMessage('cacheDeleteMemory', JSON.stringify(String(key)));
        }
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
      // Legado 預設不含登入標頭（getHeaderMap(hasLoginHeader = false)）；
      // 傳回 Java 的 Map。
      source.getHeaderMap = function(hasLoginHeader) {
        var headerMap = sendMessage('sourceGetHeaderMap', JSON.stringify(hasLoginHeader === true));
        if (typeof headerMap === 'string') {
          try { headerMap = JSON.parse(headerMap); } catch (e) { headerMap = {}; }
        }
        return __lrJavaMap(headerMap || {});
      };
      /// 登入資料、登入標頭讀成 Map；沒有或讀不成 JSON 時是 null，同 Legado。
      function __lrJsonMap(text) {
        if (text == null || text === '') return null;
        try {
          var value = JSON.parse(text);
          return value && typeof value === 'object' && !Array.isArray(value) ? __lrJavaMap(value) : null;
        } catch (e) { return null; }
      }
      source.getLoginInfo = function() { return __lrWait('sourceGetLoginInfo', ''); };
      source.putLoginInfo = function(info) {
        sendMessage('sourcePutLoginInfo', JSON.stringify(info));
        return true;
      };
      source.getLoginInfoMap = function() { return __lrJsonMap(source.getLoginInfo()); };
      source.removeLoginInfo = function() { sendMessage('sourceRemoveLoginInfo', '""'); };
      source.getLoginHeader = function() { return __lrWait('sourceGetLoginHeader', ''); };
      source.getLoginHeaderMap = function() { return __lrJsonMap(source.getLoginHeader()); };
      source.putLoginHeader = function(header) {
        sendMessage('sourcePutLoginHeader', JSON.stringify(String(header)));
      };
      source.removeLoginHeader = function() { sendMessage('sourceRemoveLoginHeader', '""'); };
      source.put = function(key, value) {
        sendMessage('sourcePut', JSON.stringify([key, value]));
        return value;
      };
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
      // Legado BaseSource.evalJS：java 與 source 都是書源、baseUrl 是書源網址，
      // 每次有自己的範圍，宣告的變數與函式不留到別次。
      function __lrSourceEval(js) {
        return (function(java, source, baseUrl) { return eval(String(js)); })(source, source, source.getKey());
      }
      // 書源程式自己呼叫登入：跑登入網址裡的程式，再呼叫它的 login()。要使用者
      // 操作的步驟在登入頁以外照樣立刻失敗（ADR 0038）。
      source.login = function() {
        var js = source.getLoginJs();
        if (!js || !String(js).trim()) return;
        __lrSourceEval(js + "\nif (typeof login == 'function') { login.apply(this); }" +
          " else { throw ('Function login not implements!!!'); }");
      };
      source.evalJS = function(js) { return __lrSourceEval(js); };
      source.getSource = function() { return source; };
      // BaseSource 實作 JsExtensions：source.ajax、source.encodeURI 這類也能用，
      // 和 java 的同一份。規則解析器專有的（getString 這類）不給。
      (function() {
        var ruleOnly = ['getString', 'getStringList', 'getElement', 'getElements', 'setContent',
          'setBaseUrl', 'setRedirectUrl', 'refreshTocUrl', 'reGetBook', 'evalJS'];
        Object.keys(java).forEach(function(name) {
          if (ruleOnly.indexOf(name) >= 0 || source[name] !== undefined) return;
          Object.defineProperty(source, name, { value: java[name], enumerable: false, configurable: true, writable: true });
        });
      })();
      // 每次執行規則前重設成這幾個物件（JsEngine）：Legado 每次執行給新的
      // java、cookie、cache、source，規則把它們拿去存別的值（`cookie = …`）
      // 也不影響下一次。
      var __lrBindings = { java: java, cookie: cookie, cache: cache, source: source };
      function __lrRestoreBindings() {
        java = __lrBindings.java;
        cookie = __lrBindings.cookie;
        cache = __lrBindings.cache;
        source = __lrBindings.source;
      }

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

      /// java.util.Arrays：書源用到的複製與比較（照源倉庫 2026-11-01 的書源）。
      /// 複製超過原陣列的部分照 Java 補預設值：位元組、數字陣列補 0，字串或
      /// 物件陣列補 null；檢查順序同 JDK（起訖顛倒先於越界）。
      var Arrays = {
        copyOfRange: function(value, start, end) {
          if (value == null) throw new Error('java.lang.NullPointerException');
          if (start > end) {
            throw new Error('java.lang.IllegalArgumentException: ' + start + ' > ' + end);
          }
          var items = normalizeByteArray(value);
          if (start < 0 || start > items.length) {
            throw new Error('java.lang.ArrayIndexOutOfBoundsException');
          }
          var numeric = items.every(function(item) { return typeof item === 'number'; });
          var out = items.slice(start, end);
          while (out.length < end - start) out.push(numeric ? 0 : null);
          return out;
        },
        copyOf: function(value, length) {
          if (value == null) throw new Error('java.lang.NullPointerException');
          if (length < 0) throw new Error('java.lang.NegativeArraySizeException');
          return Arrays.copyOfRange(value, 0, length);
        },
        /// 元素有 equals（BigInteger、Java 字串）時照它比，其餘照值比。
        equals: function(a, b) {
          if (a == null || b == null) return a == b;
          if (a.length !== b.length) return false;
          for (var i = 0; i < a.length; i++) {
            if (!__lrJavaEquals(a[i], b[i])) return false;
          }
          return true;
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

    ''');
  }
}
