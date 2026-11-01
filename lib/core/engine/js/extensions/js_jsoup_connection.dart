/// 規則 JS 的 `org.jsoup.Jsoup.connect(url)`（Jsoup 1.16.2 的 Connection、
/// Request、Response、KeyVal、Connection.Method），在 [JsJsoupExtensions]
/// 之前注入。
///
/// 連線設定與這個連線收過的 Cookie 都在 JS 這邊記著，`execute()` 時整包
/// 交給網路 isolate 照 Jsoup 自己的方式發（不帶 App 的 Cookie 與標識，
/// `jsoupExecute`），發完把 Jsoup 執行時改掉的設定寫回來（表單接進網址後
/// 清空、跳轉後改成 GET）。和 Jsoup 一樣：狀態碼不是 2xx、3xx 時丟出錯誤，
/// 除非 `ignoreHttpErrors(true)`；回應不是文字或 XML 時丟出錯誤，除非
/// `ignoreContentType(true)`。
const String jsoupConnectionJs = r'''
(function(global) {
  // Jsoup HttpConnection.DEFAULT_UA。
  var DEFAULT_UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 ' +
    '(KHTML, like Gecko) Chrome/79.0.3945.130 Safari/537.36';

  var Method = {};
  [['GET', false], ['POST', true], ['PUT', true], ['DELETE', true], ['PATCH', true],
   ['HEAD', false], ['OPTIONS', false], ['TRACE', false]].forEach(function(entry, index) {
    var name = entry[0], hasBody = entry[1];
    Method[name] = {
      name: function() { return name; },
      ordinal: function() { return index; },
      hasBody: function() { return hasBody; },
      toString: function() { return name; }
    };
  });
  var methodNames = Object.keys(Method);
  Method.values = function() { return methodNames.map(function(n) { return Method[n]; }); };
  Method.valueOf = function(name) {
    var found = Method[String(name)];
    if (!found) throw new Error('No enum constant org.jsoup.Connection.Method.' + name);
    return found;
  };
  global.__lrJsoupMethod = Method;

  function methodOf(value) { return Method.valueOf(String(value)); }
  function lower(name) { return String(name).toLowerCase(); }
  function entriesOf(map) {
    if (map == null) return [];
    if (typeof map.entrySet === 'function') {
      return map.entrySet().toArray().map(function(e) { return [e.getKey(), e.getValue()]; });
    }
    return Object.keys(map).map(function(k) { return [k, map[k]]; });
  }
  /// Java 的 Map：JS 物件，多了 get、size、keySet 這類常用的方法。
  function javaMap(pairs) {
    var map = {};
    pairs.forEach(function(p) { map[p[0]] = p[1]; });
    function hide(name, fn) { Object.defineProperty(map, name, { value: fn, enumerable: false }); }
    hide('get', function(k) { return Object.prototype.hasOwnProperty.call(map, k) ? map[k] : null; });
    hide('containsKey', function(k) { return Object.prototype.hasOwnProperty.call(map, k); });
    hide('size', function() { return Object.keys(map).length; });
    hide('isEmpty', function() { return Object.keys(map).length === 0; });
    hide('keySet', function() { return Object.keys(map); });
    hide('values', function() { return Object.keys(map).map(function(k) { return map[k]; }); });
    return map;
  }
  /// Java 的 Collection（Request.data()）：陣列的複本，多了 size、get 這類。
  function javaCollection(items) {
    var list = items.slice();
    function hide(name, fn) { Object.defineProperty(list, name, { value: fn, enumerable: false }); }
    hide('size', function() { return list.length; });
    hide('isEmpty', function() { return list.length === 0; });
    hide('get', function(i) { return list[i]; });
    hide('toArray', function() { return list.slice(); });
    return list;
  }

  /// Connection.Base：請求與回應共用的網址、方法、標頭與 Cookie。標頭名稱
  /// 不分大小寫，同一個名稱可以有好幾個值。
  function base(target, state) {
    target.url = function(url) {
      if (arguments.length === 0) return state.url;
      state.url = String(url);
      return target;
    };
    target.method = function(method) {
      if (arguments.length === 0) return state.method;
      state.method = methodOf(method);
      return target;
    };
    function values(name) {
      return state.headers.filter(function(h) { return lower(h[0]) === lower(name); })
        .map(function(h) { return h[1]; });
    }
    target.header = function(name, value) {
      if (arguments.length < 2) {
        var found = values(name);
        return found.length ? found.join(', ') : null;
      }
      target.removeHeader(name);
      return target.addHeader(name, value);
    };
    target.addHeader = function(name, value) {
      state.headers.push([String(name), value == null ? '' : String(value)]);
      return target;
    };
    target.hasHeader = function(name) { return values(name).length > 0; };
    target.hasHeaderWithValue = function(name, value) {
      return values(name).some(function(v) { return lower(v) === lower(value); });
    };
    target.removeHeader = function(name) {
      state.headers = state.headers.filter(function(h) { return lower(h[0]) !== lower(name); });
      return target;
    };
    target.multiHeaders = function() {
      var map = {};
      state.headers.forEach(function(h) { (map[h[0]] = map[h[0]] || []).push(h[1]); });
      return javaMap(Object.keys(map).map(function(k) { return [k, map[k]]; }));
    };
    target.cookie = function(name, value) {
      if (arguments.length < 2) {
        return Object.prototype.hasOwnProperty.call(state.cookies, name) ? state.cookies[name] : null;
      }
      state.cookies[String(name)] = String(value);
      return target;
    };
    target.hasCookie = function(name) {
      return Object.prototype.hasOwnProperty.call(state.cookies, name);
    };
    target.removeCookie = function(name) { delete state.cookies[name]; return target; };
    // headers()／cookies()：讀（Map）；Connection 的 headers(map)／cookies(map)：寫。
    target.headers = function(arg) {
      if (arguments.length === 0) {
        var seen = {}, pairs = [];
        state.headers.forEach(function(h) {
          if (!seen[lower(h[0])]) { seen[lower(h[0])] = true; pairs.push(h); }
        });
        return javaMap(pairs);
      }
      if (typeof arg === 'string') return values(arg);
      entriesOf(arg).forEach(function(e) { target.header(e[0], e[1]); });
      return target;
    };
    target.cookies = function(map) {
      if (arguments.length === 0) return javaMap(entriesOf(state.cookies));
      entriesOf(map).forEach(function(e) { state.cookies[String(e[0])] = String(e[1]); });
      return target;
    };
    return target;
  }

  /// Connection.KeyVal：表單的一個欄位。檔案上傳（inputStream）不支援。
  function keyVal(key, value) {
    var self = {
      key: function(k) { if (arguments.length === 0) return key; key = String(k); return self; },
      value: function(v) { if (arguments.length === 0) return value; value = String(v); return self; },
      contentType: function(c) {
        if (arguments.length === 0) return self.__type || null;
        self.__type = String(c);
        return self;
      },
      hasInputStream: function() { return false; },
      inputStream: function() { throw new Error('夜讀的 Jsoup 不支援上傳檔案'); },
      toString: function() { return key + '=' + value; }
    };
    return self;
  }

  /// 一個 Request 的設定。cookieStore 是這個連線收過的 Set-Cookie（網址、
  /// 原文），newRequest() 出來的連線共用同一份（Jsoup 的 CookieManager）。
  function newState(url) {
    return {
      url: url == null ? null : String(url), method: Method.GET,
      headers: [['Accept-Encoding', 'gzip'], ['User-Agent', DEFAULT_UA]],
      cookies: {}, data: [], body: null, timeout: 30000, maxBodySize: 2 * 1024 * 1024,
      followRedirects: true, ignoreHttpErrors: false, ignoreContentType: false,
      postDataCharset: 'UTF-8', cookieStore: { entries: [] }
    };
  }
  /// Jsoup Request(Request copy)：表單與內文不複製，Cookie 罐共用。
  function copyState(state) {
    return {
      url: state.url, method: state.method,
      headers: state.headers.map(function(h) { return h.slice(); }),
      cookies: JSON.parse(JSON.stringify(state.cookies)), data: [], body: null,
      timeout: state.timeout, maxBodySize: state.maxBodySize,
      followRedirects: state.followRedirects, ignoreHttpErrors: state.ignoreHttpErrors,
      ignoreContentType: state.ignoreContentType, postDataCharset: state.postDataCharset,
      cookieStore: state.cookieStore
    };
  }

  /// Connection.Request：連線的設定，讀寫同一份。
  function request(state) {
    var self = base({}, state);
    function option(name, convert) {
      self[name] = function(value) {
        if (arguments.length === 0) return state[name];
        state[name] = convert(value);
        return self;
      };
    }
    function atLeastZero(message) {
      return function(value) {
        var n = Number(value);
        if (!(n >= 0)) throw new Error(message);
        return n;
      };
    }
    option('timeout', atLeastZero('Timeout milliseconds must be 0 (infinite) or greater'));
    option('maxBodySize', atLeastZero('maxSize must be 0 (unlimited) or larger'));
    option('followRedirects', Boolean);
    option('ignoreHttpErrors', Boolean);
    option('ignoreContentType', Boolean);
    option('postDataCharset', String);
    self.requestBody = function(body) {
      if (arguments.length === 0) return state.body;
      state.body = body == null ? null : String(body);
      return self;
    };
    self.data = function(kv) {
      if (arguments.length === 0) return javaCollection(state.data);
      state.data.push(kv);
      return self;
    };
    self.__state = state;
    return self;
  }

  /// Jsoup 讀得了的回應類型（Dart 的 isJsoupTextType）。
  function isTextType(contentType) {
    return contentType.indexOf('text/') === 0 ||
      /^(application|text)\/\w*\+?xml/.test(contentType);
  }

  /// Connection.Response。Cookie 是這次（含跳轉途中）收到的。
  function response(reply) {
    var rstate = { url: reply.url, method: Method.valueOf(reply.method), headers: [], cookies: {} };
    Object.keys(reply.headers || {}).forEach(function(name) {
      [].concat(reply.headers[name]).forEach(function(value) {
        rstate.headers.push([name, value]);
      });
    });
    (reply.cookies || []).forEach(function(c) { rstate.cookies[c[0]] = c[1]; });
    var self = base({}, rstate);
    // 沒有的欄位 Dart 那邊不傳，Java 這裡是 null。
    var contentType = reply.contentType == null ? null : reply.contentType;
    var charset = reply.charset == null ? null : reply.charset, body = reply.body;
    self.statusCode = function() { return reply.code; };
    self.statusMessage = function() { return reply.message; };
    self.contentType = function() { return contentType; };
    self.body = function() { return body; };
    self.bodyAsBytes = function() { return java.base64DecodeToByteArray(reply.bytes); };
    self.bufferUp = function() { return self; };
    // parse()：沒用 charset(…) 指定時，字元集照網頁認出的（BOM、回應標頭、
    // <meta>，都沒有是 UTF-8），之後 charset() 傳回它。XML 回應也照 HTML
    // 解析：夜讀沒有 Jsoup 的 XML parser（parser 列在刻意不做的）。
    var charsetSet = false;
    self.charset = function(name) {
      if (arguments.length === 0) return charset;
      charset = String(name);
      charsetSet = true;
      body = java.bytesToStr(self.bodyAsBytes(), charset);
      return self;
    };
    self.parse = function() {
      if (!charsetSet) {
        charset = reply.htmlCharset;
        if (reply.htmlBody != null) body = reply.htmlBody;
      }
      return global.org.jsoup.Jsoup.parse(body, reply.url);
    };
    return self;
  }

  function execute(state) {
    if (state.url == null) throw new Error('URL must be specified to connect');
    if (!state.method.hasBody() && state.body != null) {
      throw new Error('Cannot set a request body for HTTP method ' + state.method.name());
    }
    var reply = __lrWait('jsoupExecute', {
      url: state.url, method: state.method.name(),
      headers: state.headers, cookies: state.cookies,
      data: state.data.map(function(kv) { return [kv.key(), kv.value()]; }),
      body: state.body, charset: state.postDataCharset, timeout: state.timeout,
      maxBodySize: state.maxBodySize, followRedirects: state.followRedirects,
      ignoreHttpErrors: state.ignoreHttpErrors, ignoreContentType: state.ignoreContentType,
      cookieStore: state.cookieStore.entries
    });
    // Jsoup 執行時改掉的設定：表單接進網址就清空，跳轉後改成 GET、拿掉內文
    // 與 Content-Type，沒寫 Content-Type 的表單補上。
    var changed = reply.request;
    state.url = changed.url;
    state.method = Method.valueOf(changed.method);
    if (changed.dataCleared) state.data = [];
    state.body = changed.body == null ? null : changed.body;
    state.headers = changed.headers;
    state.cookieStore.entries = reply.cookieStore;
    if (!state.ignoreHttpErrors && (reply.code < 200 || reply.code >= 400)) {
      throw new Error('HTTP error fetching URL. Status=' + reply.code + ', URL=[' + reply.url + ']');
    }
    if (!state.ignoreContentType && reply.contentType != null && !isTextType(reply.contentType)) {
      throw new Error('Unhandled content type. Must be text/*, application/xml, or ' +
        'application/*+xml');
    }
    return response(reply);
  }

  var baseMethods = ['url', 'method', 'header', 'addHeader', 'hasHeader', 'hasHeaderWithValue',
    'removeHeader', 'multiHeaders', 'cookie', 'hasCookie', 'removeCookie', 'headers', 'cookies',
    'timeout', 'maxBodySize', 'followRedirects', 'ignoreHttpErrors', 'ignoreContentType',
    'postDataCharset', 'requestBody'];

  /// org.jsoup.Connection：設定都在它目前的 Request 上；request(另一個) 之後
  /// 改用那一個，兩邊讀寫的是同一份。
  function connection(url, initial) {
    var req = initial || request(newState(url));
    var last = null;
    var self = {};
    function state() { return req.__state; }
    baseMethods.forEach(function(name) {
      self[name] = function() {
        var result = req[name].apply(req, arguments);
        return result === req ? self : result;
      };
    });
    self.userAgent = function(ua) { return self.header('User-Agent', ua); };
    self.referrer = function(referrer) { return self.header('Referer', referrer); };
    /// data(key, value)、data(Map)、data(Collection<KeyVal>)、data(k1, v1, k2, v2…)；
    /// data(key) 讀出那個欄位。
    self.data = function() {
      var args = Array.prototype.slice.call(arguments);
      var data = state().data;
      if (args.length === 1 && typeof args[0] === 'string') {
        var key = args[0];
        for (var i = 0; i < data.length; i++) {
          if (data[i].key() === key) return data[i];
        }
        return null;
      }
      if (args.length === 1) {
        var items = typeof args[0].toArray === 'function' ? args[0].toArray() : args[0];
        if (Array.isArray(items)) {
          items.forEach(function(kv) { data.push(keyVal(kv.key(), kv.value())); });
        } else {
          entriesOf(args[0]).forEach(function(e) { data.push(keyVal(String(e[0]), String(e[1]))); });
        }
        return self;
      }
      if ((args.length === 3 || args.length === 4) && typeof args[2] === 'object' && args[2] != null) {
        throw new Error('夜讀的 Jsoup 不支援上傳檔案');
      }
      if (args.length % 2 !== 0) throw new Error('Must supply an even number of key value pairs');
      for (var j = 0; j < args.length; j += 2) {
        data.push(keyVal(String(args[j]), String(args[j + 1])));
      }
      return self;
    };
    self.get = function() { state().method = Method.GET; return self.execute().parse(); };
    self.post = function() { state().method = Method.POST; return self.execute().parse(); };
    self.execute = function() { last = execute(state()); return last; };
    self.request = function(other) {
      if (arguments.length === 0) return req;
      req = other;
      return self;
    };
    self.response = function(other) {
      if (arguments.length === 0) return last;
      last = other;
      return self;
    };
    self.newRequest = function() { return connection(null, request(copyState(state()))); };
    return self;
  }
  global.__lrJsoupConnection = connection;
})(globalThis);
''';
