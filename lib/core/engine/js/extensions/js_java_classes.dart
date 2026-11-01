import '../js_extensions_base.dart';

/// 書源直接用的 Java 類別（Rhino 讓規則 JS 直接用整個 Java）：照書源實際的
/// 用法挑，行為照 JDK 與 Android。全部收在一個閉包裡，只放出 `Packages` 與
/// Rhino 的頂層套件名稱（`android`、`javax`、`com`、`cn`、`okhttp3`）；書源
/// 的 jsLib 宣告同名的全域變數也不會蓋掉這裡互相用到的類別。`java` 被 Legado
/// 的 java 物件佔走，同 Legado 要寫 `Packages.java`。
///
/// 要在 [JsJavaObject.injectJavaObjectJs] 之後注入：用到那裡的 `java`、
/// `JavaString`、加解密類別與 `buildHttpResponse`。
extension JsJavaClasses on JsExtensionsBase {
  void injectJavaClasses() {
    runtime.evaluate(r'''
(function(global) {
  var java = global.java;
  var JavaString = global.JavaString;
  var normalizeByteArray = global.normalizeByteArray;
  var javaList = global.__lrJavaList;
  var normalizeRuleResult = global.__lrNormalizeRuleResult;
  var buildHttpResponse = global.buildHttpResponse;
  var JsDate = global.Date;
  var JsMap = global.Map;
  var send = global.sendMessage;

  function named(name, value) {
    Object.defineProperty(value, '__lrClassName', { value: name, enumerable: false });
    return value;
  }
  function hide(target, name, fn) {
    Object.defineProperty(target, name, { value: fn, enumerable: false, configurable: true, writable: true });
  }
  function javaError(type, message) {
    var e = new Error(type + (message ? ': ' + message : ''));
    e.javaClass = type;
    return e;
  }
  function isText(v) { return typeof v === 'string' || v instanceof JavaString; }
  function bytesOf(v) { return isText(v) ? java.strToBytes(String(v), 'UTF-8') : normalizeByteArray(v); }
  /// byte[] 的 (陣列, 起點, 長度) 切片，照 Java 檢查界線。
  function slice(bytes, off, len) {
    var start = off == null ? 0 : off;
    var count = len == null ? bytes.length - start : len;
    if (start < 0 || count < 0 || start + count > bytes.length) {
      throw javaError('java.lang.IndexOutOfBoundsException');
    }
    return bytes.slice(start, start + count);
  }
  function toByte(v) { return v & 0xFF; }

  // ─── java.lang ─────────────────────────────────────────────
  var Thread = named('Thread', {
    // 停住這條書源 isolate，同 Java；畫面那條 isolate 不能停，直接丟錯誤
    // （ADR 0034）。
    sleep: function(ms) {
      if (Number(ms) < 0) throw javaError('java.lang.IllegalArgumentException', 'timeout value is negative');
      global.__lrWait('_sleep', Number(ms) || 0);
    }
  });
  var LockSupport = named('LockSupport', {
    parkNanos: function(blockerOrNanos, nanos) {
      var n = nanos === undefined ? blockerOrNanos : nanos;
      if (Number(n) > 0) global.__lrWait('_sleep', Math.floor(Number(n) / 1e6));
    }
  });
  var JavaSystem = named('System', {
    currentTimeMillis: function() { return JsDate.now(); },
    nanoTime: function() { return JsDate.now() * 1e6; },
    // 先複製來源那一段：來源與目的是同一個陣列、區段重疊時同 Java。
    arraycopy: function(src, srcPos, dest, destPos, length) {
      if (srcPos < 0 || destPos < 0 || length < 0 ||
          srcPos + length > src.length || destPos + length > dest.length) {
        throw javaError('java.lang.ArrayIndexOutOfBoundsException');
      }
      var part = Array.prototype.slice.call(src, srcPos, srcPos + length);
      for (var i = 0; i < length; i++) dest[destPos + i] = part[i];
    }
  });

  function StringBuilder(init) { this._s = init == null || typeof init === 'number' ? '' : String(init); }
  StringBuilder.prototype.append = function(v, off, len) {
    if (Array.isArray(v)) v = v.slice(off || 0, len == null ? v.length : (off || 0) + len).join('');
    this._s += String(v);
    return this;
  };
  StringBuilder.prototype.insert = function(i, v) { this._s = this._s.substring(0, i) + String(v) + this._s.substring(i); return this; };
  StringBuilder.prototype.length = function() { return this._s.length; };
  StringBuilder.prototype.charAt = function(i) { return this._s.charAt(i); };
  // 照 Java：代理對（emoji 這類）整個字倒過來，不拆開。
  StringBuilder.prototype.reverse = function() { this._s = Array.from(this._s).reverse().join(''); return this; };
  StringBuilder.prototype.setLength = function(n) {
    if (n < 0) throw javaError('java.lang.StringIndexOutOfBoundsException');
    while (this._s.length < n) this._s += '\u0000';
    this._s = this._s.substring(0, n);
  };
  StringBuilder.prototype.deleteCharAt = function(i) { this._s = this._s.substring(0, i) + this._s.substring(i + 1); return this; };
  StringBuilder.prototype.indexOf = function(s) { return this._s.indexOf(String(s)); };
  StringBuilder.prototype.toString = function() { return this._s; };
  named('StringBuilder', StringBuilder);

  function atomic(name, initial) {
    function Atomic(v) { this._v = v === undefined ? initial : v; }
    Atomic.prototype.get = function() { return this._v; };
    Atomic.prototype.set = function(v) { this._v = v; };
    Atomic.prototype.getAndSet = function(v) { var old = this._v; this._v = v; return old; };
    Atomic.prototype.incrementAndGet = function() { return ++this._v; };
    Atomic.prototype.decrementAndGet = function() { return --this._v; };
    Atomic.prototype.getAndIncrement = function() { return this._v++; };
    Atomic.prototype.getAndDecrement = function() { return this._v--; };
    Atomic.prototype.addAndGet = function(d) { this._v += d; return this._v; };
    Atomic.prototype.getAndAdd = function(d) { var old = this._v; this._v += d; return old; };
    Atomic.prototype.compareAndSet = function(e, v) { if (this._v === e) { this._v = v; return true; } return false; };
    Atomic.prototype.toString = function() { return String(this._v); };
    return named(name, Atomic);
  }

  // ─── java.util 集合 ────────────────────────────────────────
  /// java.util.HashMap／LinkedHashMap：照放進去的順序；鍵照 Java 分型別（數字
  /// 1 和文字 "1" 是兩個鍵）。文字鍵也照屬性讀得到（map.key、map["key"]），和
  /// Legado 交給書源的 Map 一樣；交回 Dart 時是一般物件。
  function JavaMap(init) {
    hide(this, '_m', new JsMap());
    if (init != null && typeof init === 'object') this.putAll(init);
  }
  JavaMap.prototype.__lrMap = true;
  JavaMap.prototype._order = function() { return Array.from(this._m.keys()); };
  JavaMap.prototype._mirror = function(k, v, present) {
    if (typeof k !== 'string' || k in JavaMap.prototype) return;
    if (present) Object.defineProperty(this, k, { value: v, enumerable: true, configurable: true, writable: true });
    else delete this[k];
  };
  JavaMap.prototype.put = function(k, v) {
    var old = this._m.has(k) ? this._m.get(k) : null;
    this._m.set(k, v);
    this._mirror(k, v, true);
    return old;
  };
  JavaMap.prototype.get = function(k) { return this._m.has(k) ? this._m.get(k) : null; };
  JavaMap.prototype.getOrDefault = function(k, d) { return this._m.has(k) ? this._m.get(k) : d; };
  JavaMap.prototype.containsKey = function(k) { return this._m.has(k); };
  JavaMap.prototype.containsValue = function(v) { return Array.from(this._m.values()).indexOf(v) >= 0; };
  JavaMap.prototype.remove = function(k) {
    if (!this._m.has(k)) return null;
    var old = this._m.get(k);
    this._m.delete(k);
    this._mirror(k, null, false);
    return old;
  };
  JavaMap.prototype.size = function() { return this._m.size; };
  JavaMap.prototype.isEmpty = function() { return this._m.size === 0; };
  JavaMap.prototype.clear = function() {
    var self = this;
    this._order().forEach(function(k) { self._mirror(k, null, false); });
    this._m.clear();
  };
  JavaMap.prototype.keySet = function() { return javaList(this._order()); };
  JavaMap.prototype.values = function() { var m = this._m; return javaList(this._order().map(function(k) { return m.get(k); })); };
  JavaMap.prototype.entrySet = function() {
    var m = this._m;
    return javaList(this._order().map(function(k) {
      return { key: k, value: m.get(k), getKey: function() { return k; }, getValue: function() { return m.get(k); } };
    }));
  };
  JavaMap.prototype.putAll = function(map) {
    var self = this;
    if (map && map.__lrMap) map._order().forEach(function(k) { self.put(k, map._m.get(k)); });
    else Object.keys(map).forEach(function(k) { self.put(k, map[k]); });
  };
  JavaMap.prototype.forEach = function(fn) { var m = this._m; this._order().forEach(function(k) { fn(k, m.get(k)); }); };
  JavaMap.prototype.toJSON = function() {
    var o = {}, m = this._m;
    this._order().forEach(function(k) { o[String(k)] = m.get(k); });
    return o;
  };
  JavaMap.prototype.toString = function() {
    var m = this._m;
    return '{' + this._order().map(function(k) { return k + '=' + m.get(k); }).join(', ') + '}';
  };
  function HashMap(init) { JavaMap.call(this, init); }
  HashMap.prototype = Object.create(JavaMap.prototype);
  HashMap.prototype.constructor = HashMap;
  named('HashMap', HashMap);
  function LinkedHashMap(init) { JavaMap.call(this, init); }
  LinkedHashMap.prototype = Object.create(JavaMap.prototype);
  named('LinkedHashMap', LinkedHashMap);
  /// java.util.TreeMap：鍵照自然順序（數字照大小、文字照 Java 的 compareTo），
  /// 或照給的 comparator。
  function TreeMap(arg) {
    var comparator = typeof arg === 'function' ? arg : (arg && typeof arg.compare === 'function' ? function(a, b) { return arg.compare(a, b); } : null);
    hide(this, '_cmp', comparator);
    JavaMap.call(this, typeof arg === 'object' && !comparator ? arg : null);
  }
  TreeMap.prototype = Object.create(JavaMap.prototype);
  TreeMap.prototype._order = function() {
    var cmp = this._cmp || function(a, b) { return a < b ? -1 : (a > b ? 1 : 0); };
    return Array.from(this._m.keys()).sort(cmp);
  };
  TreeMap.prototype.firstKey = function() { return this._order()[0]; };
  TreeMap.prototype.lastKey = function() { var o = this._order(); return o[o.length - 1]; };
  named('TreeMap', TreeMap);
  /// Legado 交給書源的 Map（登入資料、Cookie、網址參數這類），從一般物件做成。
  function wrapMap(obj) {
    if (obj == null) return null;
    var map = new LinkedHashMap();
    Object.keys(obj).forEach(function(k) { map.put(k, obj[k]); });
    return map;
  }

  /// java.util.ArrayList／LinkedList：JS 陣列加上 Java List 的方法。
  function ArrayList(init) {
    var list = [];
    if (init != null && typeof init === 'object') {
      var items = typeof init.toArray === 'function' ? init.toArray() : init;
      for (var i = 0; i < items.length; i++) list.push(items[i]);
    }
    hide(list, 'add', function(a, b) {
      if (b === undefined) { list.push(a); return true; }
      list.splice(a, 0, b);
    });
    hide(list, 'get', function(i) {
      if (i < 0 || i >= list.length) throw javaError('java.lang.IndexOutOfBoundsException', 'Index: ' + i + ', Size: ' + list.length);
      return list[i];
    });
    hide(list, 'set', function(i, v) { var old = list[i]; list[i] = v; return old; });
    hide(list, 'size', function() { return list.length; });
    hide(list, 'isEmpty', function() { return list.length === 0; });
    hide(list, 'contains', function(v) { return list.indexOf(v) >= 0; });
    hide(list, 'remove', function(v) {
      if (typeof v === 'number') return list.splice(v, 1)[0];
      var i = list.indexOf(v);
      if (i < 0) return false;
      list.splice(i, 1);
      return true;
    });
    hide(list, 'addAll', function(more) {
      var items = typeof more.toArray === 'function' ? more.toArray() : more;
      for (var j = 0; j < items.length; j++) list.push(items[j]);
      return items.length > 0;
    });
    hide(list, 'clear', function() { list.length = 0; });
    hide(list, 'toArray', function() { return list.slice(); });
    return list;
  }
  named('ArrayList', ArrayList);
  var LinkedList = named('LinkedList', function(init) { return new ArrayList(init); });
  /// java.util.HashSet：remove 照值刪除、傳回有沒有刪。
  function HashSet(init) {
    var set = new ArrayList();
    hide(set, 'add', function(v) { if (set.indexOf(v) >= 0) return false; set.push(v); return true; });
    hide(set, 'remove', function(v) {
      var i = set.indexOf(v);
      if (i < 0) return false;
      set.splice(i, 1);
      return true;
    });
    hide(set, 'addAll', function(more) {
      var items = typeof more.toArray === 'function' ? more.toArray() : more;
      var changed = false;
      for (var j = 0; j < items.length; j++) changed = set.add(items[j]) || changed;
      return changed;
    });
    if (init != null) set.addAll(init);
    return set;
  }
  named('HashSet', HashSet);

  var UUID = named('UUID', {
    randomUUID: function() {
      var id = String(java.randomUUID());
      return { toString: function() { return id; } };
    }
  });

  // ─── 日期 ───────────────────────────────────────────────────
  function JavaDate(ms) { this._t = ms == null ? JsDate.now() : Number(ms); }
  JavaDate.prototype.getTime = function() { return this._t; };
  JavaDate.prototype.toString = function() { return new JsDate(this._t).toString(); };
  named('Date', JavaDate);
  /// java.util.TimeZone：分鐘數的位移；認得 GMT±h[:mm]、UTC 與幾個常用地區。
  var ZONES = { 'UTC': 0, 'GMT': 0, 'Asia/Shanghai': 480, 'PRC': 480, 'Asia/Taipei': 480,
    'Asia/Hong_Kong': 480, 'Asia/Tokyo': 540, 'Asia/Seoul': 540 };
  var TimeZone = named('TimeZone', {
    getTimeZone: function(id) {
      id = String(id);
      var m = /^(?:GMT|UTC)([+-])(\d{1,2})(?::?(\d{2}))?$/.exec(id);
      var offset = m ? (m[1] === '-' ? -1 : 1) * (Number(m[2]) * 60 + Number(m[3] || 0))
        : (ZONES.hasOwnProperty(id) ? ZONES[id] : null);
      return { _offset: offset, getID: function() { return id; } };
    },
    getDefault: function() { return { _offset: null, getID: function() { return 'default'; } }; }
  });
  var WEEK_SHORT = ['週日', '週一', '週二', '週三', '週四', '週五', '週六'];
  var WEEK_LONG = ['星期日', '星期一', '星期二', '星期三', '星期四', '星期五', '星期六'];
  function pad(n, w) { n = String(Math.abs(n)); while (n.length < w) n = '0' + n; return n; }
  /// java.text.SimpleDateFormat：手機語言是中文時的寫法（月份「1月」、星期
  /// 「週四」、上午／下午）；時區預設手機的，可以 setTimeZone。
  function SimpleDateFormat(pattern) {
    this._p = String(pattern || 'yyyy-MM-dd HH:mm:ss');
    this._zone = null;
  }
  SimpleDateFormat.prototype.setTimeZone = function(zone) { this._zone = zone && zone._offset != null ? zone._offset : null; };
  SimpleDateFormat.prototype._fields = function(t) {
    var offset = this._zone != null ? this._zone : -new JsDate(t).getTimezoneOffset();
    var d = new JsDate(t + offset * 60000);
    return { y: d.getUTCFullYear(), M: d.getUTCMonth() + 1, d: d.getUTCDate(), H: d.getUTCHours(),
      m: d.getUTCMinutes(), s: d.getUTCSeconds(), S: d.getUTCMilliseconds(), E: d.getUTCDay(), offset: offset };
  };
  SimpleDateFormat.prototype.format = function(date) {
    var t = date == null ? JsDate.now() : (typeof date.getTime === 'function' ? date.getTime() : Number(date));
    var f = this._fields(t);
    return this._p.replace(/'([^']*)'|y+|M+|d+|H+|h+|k+|K+|m+|s+|S+|E+|a+|Z+|X+|u+/g, function(token, literal) {
      if (literal !== undefined) return literal === '' ? "'" : literal;
      var w = token.length;
      switch (token.charAt(0)) {
        case 'y': return w === 2 ? pad(f.y % 100, 2) : pad(f.y, w);
        case 'M': return w >= 3 ? f.M + '月' : pad(f.M, w);
        case 'd': return pad(f.d, w);
        case 'H': return pad(f.H, w);
        case 'k': return pad(f.H || 24, w);
        case 'K': return pad(f.H % 12, w);
        case 'h': return pad(f.H % 12 || 12, w);
        case 'm': return pad(f.m, w);
        case 's': return pad(f.s, w);
        case 'S': return pad(f.S, w);
        case 'E': return w >= 4 ? WEEK_LONG[f.E] : WEEK_SHORT[f.E];
        case 'u': return String(f.E || 7);
        case 'a': return f.H < 12 ? '上午' : '下午';
        case 'Z': return (f.offset < 0 ? '-' : '+') + pad(Math.floor(Math.abs(f.offset) / 60), 2) + pad(Math.abs(f.offset) % 60, 2);
        case 'X':
          if (f.offset === 0) return 'Z';
          var h = (f.offset < 0 ? '-' : '+') + pad(Math.floor(Math.abs(f.offset) / 60), 2);
          return w === 1 ? h : h + (w === 3 ? ':' : '') + pad(Math.abs(f.offset) % 60, 2);
      }
      return token;
    });
  };
  /// parse：數字欄位（y M d H m s S）照格式讀回日期。
  SimpleDateFormat.prototype.parse = function(text) {
    var order = [];
    var source = this._p.replace(/[.*+?^${}()|[\]\\]/g, '\\$&').replace(/y+|M+|d+|H+|m+|s+|S+/g, function(token) {
      order.push(token.charAt(0));
      return '(\\d{1,' + Math.max(token.length, token.charAt(0) === 'y' ? 4 : 2) + '})';
    });
    var match = new RegExp('^' + source).exec(String(text));
    if (!match) throw javaError('java.text.ParseException', 'Unparseable date: "' + text + '"');
    var v = { y: 1970, M: 1, d: 1, H: 0, m: 0, s: 0, S: 0 };
    order.forEach(function(k, i) { v[k] = Number(match[i + 1]); });
    var utc = JsDate.UTC(v.y, v.M - 1, v.d, v.H, v.m, v.s, v.S);
    var offset = this._zone != null ? this._zone : -new JsDate(utc).getTimezoneOffset();
    return new JavaDate(utc - offset * 60000);
  };
  named('SimpleDateFormat', SimpleDateFormat);

  // ─── java.io 與 java.util.zip ──────────────────────────────
  function ByteArrayOutputStream() { this._bytes = []; }
  ByteArrayOutputStream.prototype.write = function(bytes, off, len) {
    if (typeof bytes === 'number') { this._bytes.push(toByte(bytes)); return; }
    var part = slice(normalizeByteArray(bytes), off, len);
    for (var i = 0; i < part.length; i++) this._bytes.push(toByte(part[i]));
  };
  ByteArrayOutputStream.prototype.toByteArray = function() { return this._bytes.slice(); };
  ByteArrayOutputStream.prototype.size = function() { return this._bytes.length; };
  ByteArrayOutputStream.prototype.reset = function() { this._bytes = []; };
  ByteArrayOutputStream.prototype.toString = function(charset) { return java.bytesToStr(this._bytes, charset || 'UTF-8'); };
  ByteArrayOutputStream.prototype.close = function() {};
  named('ByteArrayOutputStream', ByteArrayOutputStream);

  /// 讀位元組的共同做法：read() 傳回 0～255、讀完是 -1；read(buf[, off, len])
  /// 讀進 buf、傳回讀了幾個。
  function readerOf(Type) {
    Type.prototype.read = function(buffer, off, len) {
      var end = this._end;
      if (buffer === undefined) return this._pos < end ? toByte(this._bytes[this._pos++]) : -1;
      var start = off == null ? 0 : off;
      var want = len == null ? buffer.length - start : len;
      if (start < 0 || want < 0 || start + want > buffer.length) throw javaError('java.lang.IndexOutOfBoundsException');
      if (want === 0) return 0;
      if (this._pos >= end) return -1;
      var count = Math.min(want, end - this._pos);
      for (var i = 0; i < count; i++) buffer[start + i] = this._bytes[this._pos++];
      return count;
    };
    Type.prototype.available = function() { return this._end - this._pos; };
    Type.prototype.close = function() {};
    return Type;
  }
  /// (陣列[, 起點, 長度])：只讀那一段，同 Java。
  function ByteArrayInputStream(bytes, off, len) {
    this._bytes = normalizeByteArray(bytes);
    this._pos = off || 0;
    this._end = len == null ? this._bytes.length : Math.min(this._bytes.length, this._pos + len);
  }
  readerOf(named('ByteArrayInputStream', ByteArrayInputStream));
  /// 從 InputStream 讀出還沒讀的位元組（解壓串流用）。
  function remaining(input) {
    if (input == null) return [];
    if (input._bytes !== undefined) return input._bytes.slice(input._pos || 0, input._end == null ? input._bytes.length : input._end);
    return normalizeByteArray(input);
  }
  function GZIPInputStream(input) {
    this._bytes = normalizeByteArray(send('_gunzipBytes', JSON.stringify(remaining(input))));
    this._pos = 0;
    this._end = this._bytes.length;
  }
  readerOf(named('GZIPInputStream', GZIPInputStream));
  /// java.util.zip.Inflater：setInput 後 inflate(buf) 解出位元組；nowrap 是沒有
  /// zlib 標頭的 deflate。
  function Inflater(nowrap) { this._nowrap = !!nowrap; this._out = null; this._pos = 0; }
  Inflater.prototype.setInput = function(bytes, off, len) {
    this._out = normalizeByteArray(send('_inflateBytes', JSON.stringify([slice(normalizeByteArray(bytes), off, len), this._nowrap])));
    this._pos = 0;
  };
  Inflater.prototype.inflate = function(buffer, off, len) {
    if (!this._out) return 0;
    var start = off || 0, want = len == null ? buffer.length - start : len;
    var count = Math.min(want, this._out.length - this._pos);
    for (var i = 0; i < count; i++) buffer[start + i] = this._out[this._pos++];
    return count;
  };
  Inflater.prototype.finished = function() { return !!this._out && this._pos >= this._out.length; };
  Inflater.prototype.needsInput = function() { return !this._out; };
  Inflater.prototype.getRemaining = function() { return 0; };
  Inflater.prototype.end = function() {};
  Inflater.prototype.reset = function() { this._out = null; this._pos = 0; };
  named('Inflater', Inflater);
  function InflaterInputStream(input, inflater) {
    this._bytes = normalizeByteArray(send('_inflateBytes', JSON.stringify([remaining(input), !!(inflater && inflater._nowrap)])));
    this._pos = 0;
    this._end = this._bytes.length;
  }
  readerOf(named('InflaterInputStream', InflaterInputStream));

  // ─── java.security、javax.crypto、java.nio ─────────────────
  /// update 的參數版本照 Java：一個位元組、整個陣列、陣列的一段。
  function digester(feed) {
    return function(v, off, len) {
      if (typeof v === 'number' && off === undefined) feed([toByte(v)]);
      else feed(slice(bytesOf(v), off, len));
    };
  }
  var MessageDigest = named('MessageDigest', {
    getInstance: function(algorithm) {
      var buffer = [];
      var md = {
        update: digester(function(b) { buffer = buffer.concat(b); }),
        digest: function(v, off, len) {
          if (v !== undefined) md.update(v, off, len);
          var out = normalizeByteArray(send('_digestBytes', JSON.stringify([buffer, String(algorithm)])));
          buffer = [];
          return out;
        },
        reset: function() { buffer = []; },
        getAlgorithm: function() { return String(algorithm); }
      };
      return md;
    }
  });
  var Mac = named('Mac', {
    getInstance: function(algorithm) {
      var key = null, buffer = [];
      var mac = {
        init: function(spec) {
          key = normalizeByteArray(spec && spec.bytes !== undefined ? spec.bytes : spec);
          buffer = [];
        },
        update: digester(function(b) { buffer = buffer.concat(b); }),
        doFinal: function(v, off) {
          if (key == null) throw javaError('java.lang.IllegalStateException', 'MAC not initialized');
          if (v !== undefined && typeof off !== 'number') mac.update(v);
          var out = normalizeByteArray(send('_hmacBytes', JSON.stringify([buffer, String(algorithm), key])));
          buffer = [];
          // doFinal(output, outOffset)：寫進給的陣列。
          if (v !== undefined && typeof off === 'number') {
            for (var i = 0; i < out.length; i++) v[off + i] = out[i];
            return undefined;
          }
          return out;
        },
        reset: function() { buffer = []; },
        getAlgorithm: function() { return String(algorithm); },
        getMacLength: function() { return /512/.test(algorithm) ? 64 : /384/.test(algorithm) ? 48 : /256/.test(algorithm) ? 32 : /SHA1|SHA$/i.test(algorithm) ? 20 : 16; }
      };
      return mac;
    }
  });
  function SecureRandom() {}
  SecureRandom.prototype.nextBytes = function(bytes) {
    var random = normalizeByteArray(send('_randomBytes', JSON.stringify(bytes.length)));
    for (var i = 0; i < bytes.length; i++) bytes[i] = random[i];
  };
  SecureRandom.prototype.generateSeed = function(n) {
    return normalizeByteArray(send('_randomBytes', JSON.stringify(Number(n))));
  };
  SecureRandom.prototype.nextInt = function(bound) {
    var b = normalizeByteArray(send('_randomBytes', JSON.stringify(4)));
    var v = ((b[0] << 24) | (b[1] << 16) | (b[2] << 8) | b[3]) >>> 0;
    return bound == null ? (v | 0) : v % Number(bound);
  };
  named('SecureRandom', SecureRandom);

  /// java.nio.ByteBuffer：固定容量、大端序；put 有相對與絕對位置兩種，超過
  /// 容量丟 BufferOverflowException；array() 是同一個陣列。
  var ByteBuffer = named('ByteBuffer', {
    allocate: function(capacity) { return makeBuffer(new Array(capacity).fill(0)); },
    wrap: function(bytes) { return makeBuffer(normalizeByteArray(bytes)); }
  });
  function makeBuffer(bytes) {
    var pos = 0;
    function write(at, list) {
      var index = at == null ? pos : at;
      if (index < 0 || index + list.length > bytes.length) {
        throw javaError(at == null ? 'java.nio.BufferOverflowException' : 'java.lang.IndexOutOfBoundsException');
      }
      for (var j = 0; j < list.length; j++) bytes[index + j] = toByte(list[j]);
      if (at == null) pos += list.length;
    }
    function int32(v) { return [(v >>> 24) & 0xFF, (v >>> 16) & 0xFF, (v >>> 8) & 0xFF, v & 0xFF]; }
    var buf = {
      put: function(a, b, c) {
        if (typeof a === 'number' && b !== undefined && c === undefined) write(a, [b]);
        else if (typeof a === 'number') write(null, [a]);
        else write(null, slice(normalizeByteArray(a), b, c));
        return buf;
      },
      putInt: function(a, b) { if (b === undefined) write(null, int32(a)); else write(a, int32(b)); return buf; },
      putShort: function(a, b) {
        var s = function(v) { return [(v >>> 8) & 0xFF, v & 0xFF]; };
        if (b === undefined) write(null, s(a)); else write(a, s(b));
        return buf;
      },
      get: function(i) { return i === undefined ? bytes[pos++] : bytes[i]; },
      array: function() { return bytes; },
      position: function(p) { if (p === undefined) return pos; pos = p; return buf; },
      capacity: function() { return bytes.length; },
      remaining: function() { return bytes.length - pos; }
    };
    return buf;
  }

  // ─── 網址 ───────────────────────────────────────────────────
  /// java.net.URL：保存原本的網址，getQuery 是原樣（不解碼）。
  function JavaURL(a, b) {
    var spec = b === undefined ? String(a) : String(b);
    var base = b === undefined ? null : String(a);
    var parts = send('toURL', JSON.stringify([spec, base]));
    if (!parts || !parts.protocol) throw javaError('java.net.MalformedURLException', 'no protocol: ' + spec);
    this._p = parts;
  }
  JavaURL.prototype.getHost = function() { return this._p.host; };
  JavaURL.prototype.getPort = function() { return this._p.port; };
  JavaURL.prototype.getDefaultPort = function() { return this._p.protocol === 'https' ? 443 : (this._p.protocol === 'http' ? 80 : -1); };
  JavaURL.prototype.getProtocol = function() { return this._p.protocol; };
  JavaURL.prototype.getPath = function() { return this._p.pathname; };
  JavaURL.prototype.getQuery = function() { return this._p.query; };
  JavaURL.prototype.getRef = function() { return this._p.ref; };
  JavaURL.prototype.getUserInfo = function() { return this._p.userInfo || null; };
  JavaURL.prototype.getFile = function() { return this._p.pathname + (this._p.query != null ? '?' + this._p.query : ''); };
  JavaURL.prototype.getAuthority = function() {
    return (this._p.userInfo ? this._p.userInfo + '@' : '') + this._p.host + (this._p.port > 0 ? ':' + this._p.port : '');
  };
  JavaURL.prototype.toString = function() { return this._p.href; };
  JavaURL.prototype.toExternalForm = JavaURL.prototype.toString;
  named('URL', JavaURL);
  var URLEncoder = named('URLEncoder', {
    encode: function(s, enc) { return java.encodeURI(s, enc || 'UTF-8'); }
  });
  /// java.net.URLDecoder：+ 變空白，連續的 %XX 照字元集解成文字；不完整的
  /// % 丟 IllegalArgumentException，同 Java。
  var URLDecoder = named('URLDecoder', {
    decode: function(s, enc) {
      var text = String(s == null ? '' : s);
      if (/%(?![0-9a-fA-F]{2})/.test(text)) {
        throw javaError('java.lang.IllegalArgumentException', 'URLDecoder: Illegal hex characters in escape (%) pattern');
      }
      return text.replace(/\+/g, ' ').replace(/(%[0-9a-fA-F]{2})+/g, function(run) {
        var bytes = run.substring(1).split('%').map(function(h) { return parseInt(h, 16); });
        return java.bytesToStr(bytes, enc || 'UTF-8');
      });
    }
  });
  function noSocket() { throw javaError('java.lang.UnsupportedOperationException', '夜讀不支援規則 JS 直接開網路連線（java.net.Socket）'); }
  /// okhttp3.HttpUrl：只收 http／https，parse 失敗傳回 null；queryParameter
  /// 取第一個值。
  var HttpUrl = named('HttpUrl', {
    parse: function(url) {
      var u;
      try { u = new JavaURL(url); } catch (e) { return null; }
      if (u.getProtocol() !== 'http' && u.getProtocol() !== 'https') return null;
      return {
        host: function() { return u.getHost(); },
        scheme: function() { return u.getProtocol(); },
        port: function() { return u.getPort() > 0 ? u.getPort() : u.getDefaultPort(); },
        encodedPath: function() { return u.getPath(); },
        query: function() { return u.getQuery() == null ? null : URLDecoder.decode(u.getQuery().replace(/\+/g, '%2B'), 'UTF-8'); },
        encodedQuery: function() { return u.getQuery(); },
        queryParameter: function(name) {
          var q = u.getQuery();
          if (q == null) return null;
          var pairs = q.split('&');
          for (var i = 0; i < pairs.length; i++) {
            var eq = pairs[i].indexOf('=');
            var key = eq < 0 ? pairs[i] : pairs[i].substring(0, eq);
            if (URLDecoder.decode(key, 'UTF-8') === name) return eq < 0 ? null : URLDecoder.decode(pairs[i].substring(eq + 1), 'UTF-8');
          }
          return null;
        },
        toString: function() { return u.toString(); }
      };
    }
  });
  HttpUrl.get = function(url) {
    var u = HttpUrl.parse(url);
    if (u == null) throw javaError('java.lang.IllegalArgumentException', 'Expected URL scheme http or https: ' + url);
    return u;
  };

  // ─── Base64 ────────────────────────────────────────────────
  /// android.util.Base64：flags 照 Android（DEFAULT 每 76 字換行）；
  /// (陣列, 起點, 長度, flags) 的版本只用那一段。
  function androidArgs(data, a, b, c) {
    if (c !== undefined) return { data: slice(bytesOf(data), a, b), flags: c };
    return { data: data, flags: a == null ? 0 : a };
  }
  var AndroidBase64 = named('Base64', {
    DEFAULT: 0, NO_PADDING: 1, NO_WRAP: 2, CRLF: 4, URL_SAFE: 8, NO_CLOSE: 16,
    encodeToString: function(data, a, b, c) { var x = androidArgs(data, a, b, c); return java.base64Encode(x.data, x.flags); },
    encode: function(data, a, b, c) {
      var x = androidArgs(data, a, b, c);
      return java.strToBytes(java.base64Encode(x.data, x.flags), 'US-ASCII');
    },
    decode: function(data, a, b, c) {
      var x = androidArgs(data, a, b, c);
      var text = isText(x.data) ? String(x.data) : java.bytesToStr(normalizeByteArray(x.data), 'US-ASCII');
      return java.base64DecodeToByteArray(text, x.flags) || [];
    }
  });
  /// java.util.Base64：decoder 收文字或位元組。
  function jdkDecoder() {
    return {
      decode: function(value) {
        var text = isText(value) ? String(value) : java.bytesToStr(normalizeByteArray(value), 'US-ASCII');
        return java.base64DecodeToByteArray(text) || [];
      }
    };
  }
  function jdkEncoder(flags) {
    return {
      encodeToString: function(data) { return java.base64Encode(data, flags); },
      encode: function(data) { return java.strToBytes(java.base64Encode(data, flags), 'US-ASCII'); },
      withoutPadding: function() { return jdkEncoder(flags | 1); }
    };
  }
  var JdkBase64 = named('Base64', {
    getDecoder: jdkDecoder, getUrlDecoder: jdkDecoder, getMimeDecoder: jdkDecoder,
    getEncoder: function() { return jdkEncoder(2); },
    getUrlEncoder: function() { return jdkEncoder(10); }
  });

  // ─── 其他函式庫 ─────────────────────────────────────────────
  /// com.jayway.jsonpath.JsonPath。
  var JsonPath = named('JsonPath', {
    read: function(json, path) {
      var text = isText(json) ? String(json) : JSON.stringify(normalizeRuleResult(json));
      return send('_jsonPathRead', JSON.stringify([text, String(path)]));
    },
    parse: function(json) { return { read: function(path) { return JsonPath.read(json, path); } }; }
  });
  /// cn.hutool（Legado 內建）的雜湊。
  function hutoolDigest(algorithm) {
    return function(v) {
      var out = normalizeByteArray(send('_digestBytes', JSON.stringify([bytesOf(v), algorithm])));
      return out.map(function(b) { return (toByte(b) + 0x100).toString(16).substring(1); }).join('');
    };
  }
  var DigestUtil = named('DigestUtil', {
    md5Hex: hutoolDigest('MD5'), sha1Hex: hutoolDigest('SHA-1'),
    sha256Hex: hutoolDigest('SHA-256'), sha512Hex: hutoolDigest('SHA-512'),
    md5Hex16: function(v) { return hutoolDigest('MD5')(v).substring(8, 24); }
  });
  var SecureUtil = named('SecureUtil', { md5: hutoolDigest('MD5'), sha1: hutoolDigest('SHA-1'), sha256: hutoolDigest('SHA-256') });
  /// Legado 的 StrResponse(網址, 內文)：登入檢查拿它換掉抓到的回應。
  var StrResponse = named('StrResponse', function(url, body) {
    return buildHttpResponse({ url: String(url), requestUrl: String(url), body: body == null ? '' : String(body), code: 200, message: 'OK', headers: {} });
  });

  var Packages = {
    org: global.org,
    java: {
      lang: {
        String: function(value) { return new JavaString(value); },
        Integer: global.Integer,
        Thread: Thread,
        System: JavaSystem,
        StringBuilder: StringBuilder
      },
      io: { ByteArrayOutputStream: ByteArrayOutputStream, ByteArrayInputStream: ByteArrayInputStream },
      util: {
        Arrays: global.Arrays,
        Base64: JdkBase64,
        HashMap: HashMap,
        LinkedHashMap: LinkedHashMap,
        TreeMap: TreeMap,
        ArrayList: ArrayList,
        LinkedList: LinkedList,
        HashSet: HashSet,
        UUID: UUID,
        Date: JavaDate,
        TimeZone: TimeZone,
        zip: { GZIPInputStream: GZIPInputStream, Inflater: Inflater, InflaterInputStream: InflaterInputStream },
        concurrent: {
          locks: { LockSupport: LockSupport },
          atomic: { AtomicLong: atomic('AtomicLong', 0), AtomicInteger: atomic('AtomicInteger', 0), AtomicBoolean: atomic('AtomicBoolean', false) }
        }
      },
      text: { SimpleDateFormat: SimpleDateFormat },
      security: { MessageDigest: MessageDigest, SecureRandom: SecureRandom },
      nio: { ByteBuffer: ByteBuffer },
      net: {
        URL: JavaURL, URLEncoder: URLEncoder, URLDecoder: URLDecoder,
        Socket: noSocket, InetAddress: { getByName: noSocket }, InetSocketAddress: noSocket
      }
    },
    javax: {
      crypto: {
        Cipher: global.Cipher,
        Mac: Mac,
        spec: {
          SecretKeySpec: global.SecretKeySpec,
          IvParameterSpec: global.IvParameterSpec,
          GCMParameterSpec: global.GCMParameterSpec
        }
      }
    },
    android: { util: { Base64: AndroidBase64 } },
    com: { jayway: { jsonpath: { JsonPath: JsonPath } } },
    cn: { hutool: { crypto: { digest: { DigestUtil: DigestUtil }, SecureUtil: SecureUtil } } },
    io: { legado: { app: { help: { http: { StrResponse: StrResponse } } } } },
    okhttp3: { HttpUrl: HttpUrl }
  };
  global.Packages = Packages;
  global.android = Packages.android;
  global.javax = Packages.javax;
  global.com = Packages.com;
  global.cn = Packages.cn;
  global.okhttp3 = Packages.okhttp3;
  // 給書源 JS 外的橋接用：Legado 交給書源的 Map。
  global.__lrJavaMap = wrapMap;
})(globalThis);
''');
  }
}
