import '../js_extensions_base.dart';

/// 規則 JS 的 Java Stream：`list.stream().map(…).filter(…).toList()`。
///
/// Legado 的規則 JS 跑在 Rhino 上，Java 的 `List`、`ArrayList`、Jsoup
/// `Elements` 都有 `stream()`，lambda 直接傳 JS 函式。夜讀的清單都是 JS 陣列
/// （規則交回的清單、`new ArrayList()`、`HashSet`、`Map.keySet()`、`Elements`、
/// 交給規則的 `result`），所以 `stream()` 放在 `Array.prototype`（不可列舉），
/// 每一種清單一次就都有。
///
/// 和 Java 一樣是惰性的：沒有最後一步（`toList`、`count`、`forEach` 這類）就
/// 什麼都不跑，`limit` 之後不再往上游拿；一條 Stream 只能接一次，再接丟
/// `IllegalStateException`。`toList()` 交回夜讀的 `ArrayList`，能接著當 Java
/// 清單用。
extension JsJavaStream on JsExtensionsBase {
  void injectJavaStream() {
    runtime.evaluate(r'''
(function(global) {
  var JavaString = global.JavaString;
  var Packages = global.Packages;
  var END = { end: true };

  function javaError(type, message) {
    var e = new Error(type + (message ? ': ' + message : ''));
    e.javaClass = type;
    return e;
  }
  function named(name, value) {
    Object.defineProperty(value, '__lrClassName', { value: name, enumerable: false });
    return value;
  }
  function hide(target, name, fn) {
    Object.defineProperty(target, name, { value: fn, enumerable: false, configurable: true, writable: true });
  }
  function isText(v) { return typeof v === 'string' || v instanceof JavaString; }
  function npe() { return javaError('java.lang.NullPointerException'); }
  function newList(items) {
    var list = new Packages.java.util.ArrayList();
    for (var i = 0; i < items.length; i++) list.push(items[i]);
    return list;
  }

  /// lambda：照 Rhino，JS 函式直接當 Java 的函式介面，或有那個方法的物件
  /// （`{apply: …}`、`{test: …}`、`{compare: …}`）。
  function lambda(f, methods) {
    if (typeof f === 'function') return f;
    if (f == null) throw npe();
    for (var i = 0; i < methods.length; i++) {
      if (typeof f[methods[i]] === 'function') return f[methods[i]].bind(f);
    }
    throw javaError('java.lang.ClassCastException', 'not a function: ' + f);
  }
  var APPLY = ['apply', 'applyAsInt', 'applyAsLong', 'applyAsDouble', 'get', 'call'];
  var TEST = ['test'];
  var ACCEPT = ['accept'];
  var COMPARE = ['compare'];
  var BINARY = ['apply', 'applyAsInt', 'applyAsLong', 'applyAsDouble'];
  /// 交回 undefined 當 null（Java 沒有 undefined）。
  function nul(v) { return v === undefined ? null : v; }

  /// Comparable 的自然順序：數字照大小、文字照 UTF-16 順序，有 compareTo 的
  /// 物件（BigInteger）照它比；其他物件和 null 與 Java 一樣丟例外。
  function compareNatural(a, b) {
    if (a == null || b == null) throw npe();
    if (typeof a === 'object' && !(a instanceof JavaString) && typeof a.compareTo === 'function') {
      return Number(a.compareTo(b));
    }
    var x = isText(a) ? String(a) : a;
    var y = isText(b) ? String(b) : b;
    var type = typeof x;
    if (type !== typeof y || (type !== 'number' && type !== 'string' && type !== 'boolean')) {
      throw javaError('java.lang.ClassCastException', 'cannot be cast to java.lang.Comparable');
    }
    return x < y ? -1 : (x > y ? 1 : 0);
  }
  function comparatorOf(c) {
    if (c == null) return compareNatural;
    var f = lambda(c, COMPARE);
    return function(a, b) { return Number(f(a, b)); };
  }

  // ─── Optional ───────────────────────────────────────────────
  function Optional(present, value, kind) {
    hide(this, '_present', present);
    hide(this, '_value', value);
    hide(this, '_kind', kind || 'Optional');
  }
  var EMPTY = new Optional(false, null);
  var OP = Optional.prototype;
  OP.isPresent = function() { return this._present; };
  OP.isEmpty = function() { return !this._present; };
  OP.get = function() {
    if (!this._present) throw javaError('java.util.NoSuchElementException', 'No value present');
    return this._value;
  };
  OP.getAsInt = OP.get;
  OP.getAsLong = OP.get;
  OP.getAsDouble = OP.get;
  OP.orElseThrow = function(supplier) {
    if (this._present) return this._value;
    if (supplier == null) throw javaError('java.util.NoSuchElementException', 'No value present');
    throw lambda(supplier, APPLY)();
  };
  OP.orElse = function(other) { return this._present ? this._value : other; };
  OP.orElseGet = function(supplier) {
    return this._present ? this._value : nul(lambda(supplier, APPLY)());
  };
  OP.ifPresent = function(consumer) {
    var f = lambda(consumer, ACCEPT);
    if (this._present) f(this._value);
  };
  OP.ifPresentOrElse = function(consumer, otherwise) {
    var f = lambda(consumer, ACCEPT);
    var g = lambda(otherwise, ['run', 'call']);
    if (this._present) f(this._value); else g();
  };
  OP.map = function(mapper) {
    var f = lambda(mapper, APPLY);
    return this._present ? Optional.ofNullable(f(this._value)) : EMPTY;
  };
  OP.flatMap = function(mapper) {
    var f = lambda(mapper, APPLY);
    if (!this._present) return EMPTY;
    var r = f(this._value);
    if (r == null) throw npe();
    return r;
  };
  OP.filter = function(predicate) {
    var f = lambda(predicate, TEST);
    return this._present && !f(this._value) ? EMPTY : this;
  };
  OP.or = function(supplier) {
    return this._present ? this : lambda(supplier, APPLY)();
  };
  OP.stream = function() { return fromArray(this._present ? [this._value] : [], 'obj'); };
  OP.equals = function(other) {
    return other instanceof Optional && other._present === this._present &&
      (!this._present || global.__lrJavaEquals(this._value, other._value));
  };
  OP.toString = function() {
    return this._present ? this._kind + '[' + this._value + ']' : this._kind + '.empty';
  };
  Optional.of = function(value) {
    if (value == null) throw npe();
    return new Optional(true, value);
  };
  Optional.ofNullable = function(value) {
    return value == null ? EMPTY : new Optional(true, value);
  };
  Optional.empty = function() { return EMPTY; };
  named('Optional', Optional);

  /// 基本型別 Stream 的結果：OptionalInt、OptionalLong、OptionalDouble。
  var PRIMITIVE_OPTIONAL = { int: 'OptionalInt', long: 'OptionalLong', double: 'OptionalDouble' };
  function optionalOf(present, value, kind) {
    var label = PRIMITIVE_OPTIONAL[kind] || 'Optional';
    return new Optional(present, present ? value : null, label);
  }

  // ─── Stream ─────────────────────────────────────────────────
  /// [pull] 每次交回下一個元素，沒有了交回 END。[kind] 是 obj／int／long／
  /// double（Stream、IntStream、LongStream、DoubleStream）。
  function Stream(pull, kind) {
    hide(this, '_pull', pull);
    hide(this, '_kind', kind || 'obj');
    hide(this, '_linked', false);
    hide(this, '_onClose', []);
  }
  var SP = Stream.prototype;

  /// 一條 Stream 只能往下接一次，和 Java 一樣。
  function take(stream) {
    if (stream._linked) {
      throw javaError('java.lang.IllegalStateException', 'stream has already been operated upon or closed');
    }
    stream._linked = true;
    return stream._pull;
  }
  function chain(stream, kind, make) {
    var next = new Stream(make(take(stream)), kind == null ? stream._kind : kind);
    next._onClose = stream._onClose;
    return next;
  }
  function fromArray(items, kind) {
    var i = 0;
    return new Stream(function() { return i < items.length ? items[i++] : END; }, kind);
  }
  function drain(pull) {
    var out = [], v;
    while ((v = pull()) !== END) out.push(v);
    return out;
  }
  function iteratorPull(it) {
    return function() { return it.hasNext() ? it.next() : END; };
  }
  /// 基本型別 Stream 的元素轉成 Java 的型別（int 溢位、long 取整）。
  function coerce(kind, v) {
    if (kind === 'int') return Number(v) | 0;
    if (kind === 'long') return Math.trunc(Number(v));
    if (kind === 'double') return Number(v);
    return nul(v);
  }

  SP.filter = function(predicate) {
    var test = lambda(predicate, TEST);
    return chain(this, null, function(up) {
      return function() {
        var v;
        while ((v = up()) !== END) if (test(v)) return v;
        return END;
      };
    });
  };
  function mapper(kind) {
    return function(fn) {
      var f = lambda(fn, APPLY);
      return chain(this, kind, function(up) {
        return function() {
          var v = up();
          return v === END ? END : coerce(kind, f(v));
        };
      });
    };
  }
  SP.map = function(fn) { return mapper(this._kind).call(this, fn); };
  SP.mapToObj = mapper('obj');
  SP.mapToInt = mapper('int');
  SP.mapToLong = mapper('long');
  SP.mapToDouble = mapper('double');
  SP.boxed = function() { return chain(this, 'obj', function(up) { return up; }); };
  SP.asLongStream = function() { return chain(this, 'long', function(up) { return up; }); };
  SP.asDoubleStream = function() { return chain(this, 'double', function(up) { return up; }); };
  function flatMapper(kind) {
    return function(fn) {
      var f = lambda(fn, APPLY);
      return chain(this, kind == null ? this._kind : kind, function(up) {
        var inner = null;
        return function() {
          for (;;) {
            if (inner !== null) {
              var x = inner();
              if (x !== END) return x;
              inner = null;
            }
            var v = up();
            if (v === END) return END;
            var produced = f(v);
            // 交回 null 當空的 Stream；清單照 Stream 展開。
            if (produced == null) continue;
            inner = produced instanceof Stream ? take(produced) : fromArray(produced, 'obj')._pull;
          }
        };
      });
    };
  }
  SP.flatMap = flatMapper(null);
  SP.flatMapToInt = flatMapper('int');
  SP.flatMapToLong = flatMapper('long');
  SP.flatMapToDouble = flatMapper('double');
  SP.peek = function(consumer) {
    var f = lambda(consumer, ACCEPT);
    return chain(this, null, function(up) {
      return function() {
        var v = up();
        if (v !== END) f(v);
        return v;
      };
    });
  };
  /// distinct：文字、數字、布林照值（分型別，1 和 "1" 不同），有 equals 的
  /// 物件（BigInteger）照它比，其他物件照是不是同一個。
  SP.distinct = function() {
    return chain(this, null, function(up) {
      var seen = new Set(), withEquals = [];
      return function() {
        var v;
        while ((v = up()) !== END) {
          var key = null;
          if (v == null) key = 'null';
          else if (isText(v)) key = 's:' + String(v);
          else if (typeof v !== 'object') key = typeof v + ':' + String(v);
          if (key === null && typeof v.equals === 'function') {
            if (withEquals.some(function(o) { return global.__lrJavaEquals(o, v); })) continue;
            withEquals.push(v);
            return v;
          }
          var id = key === null ? v : key;
          if (seen.has(id)) continue;
          seen.add(id);
          return v;
        }
        return END;
      };
    });
  };
  /// sorted：照 Java 是穩定排序（比較結果相同的維持原本順序）。
  SP.sorted = function(comparator) {
    var cmp = comparatorOf(comparator);
    return chain(this, null, function(up) {
      var sorted = null, i = 0;
      return function() {
        if (sorted === null) {
          sorted = drain(up).map(function(v, index) { return { v: v, i: index }; });
          sorted.sort(function(a, b) { return cmp(a.v, b.v) || a.i - b.i; });
        }
        return i < sorted.length ? sorted[i++].v : END;
      };
    });
  };
  SP.limit = function(n) {
    n = Number(n);
    if (n < 0) throw javaError('java.lang.IllegalArgumentException', String(n));
    return chain(this, null, function(up) {
      var left = n;
      return function() {
        if (left <= 0) return END;
        left--;
        return up();
      };
    });
  };
  SP.skip = function(n) {
    n = Number(n);
    if (n < 0) throw javaError('java.lang.IllegalArgumentException', String(n));
    return chain(this, null, function(up) {
      var left = n;
      return function() {
        while (left > 0) {
          left--;
          if (up() === END) return END;
        }
        return up();
      };
    });
  };
  SP.takeWhile = function(predicate) {
    var test = lambda(predicate, TEST);
    return chain(this, null, function(up) {
      var done = false;
      return function() {
        if (done) return END;
        var v = up();
        if (v === END || !test(v)) { done = true; return END; }
        return v;
      };
    });
  };
  SP.dropWhile = function(predicate) {
    var test = lambda(predicate, TEST);
    return chain(this, null, function(up) {
      var dropping = true;
      return function() {
        var v;
        while ((v = up()) !== END) {
          if (dropping && test(v)) continue;
          dropping = false;
          return v;
        }
        return END;
      };
    });
  };
  // 一律依序在這個執行緒跑，平行、順序與無序都不改變結果。
  SP.parallel = function() { return this; };
  SP.sequential = function() { return this; };
  SP.unordered = function() { return this; };
  SP.isParallel = function() { return false; };
  SP.onClose = function(handler) {
    this._onClose.push(lambda(handler, ['run', 'call']));
    return this;
  };
  SP.close = function() {
    var handlers = this._onClose.splice(0);
    this._linked = true;
    handlers.forEach(function(h) { h(); });
  };

  // 最後一步
  SP.forEach = function(consumer) {
    var f = lambda(consumer, ACCEPT), up = take(this), v;
    while ((v = up()) !== END) f(v);
  };
  SP.forEachOrdered = SP.forEach;
  SP.toList = function() { return newList(drain(take(this))); };
  SP.toArray = function(generator) {
    if (generator != null) lambda(generator, APPLY);
    return drain(take(this));
  };
  SP.count = function() {
    var up = take(this), n = 0;
    while (up() !== END) n++;
    return n;
  };
  SP.findFirst = function() {
    var v = take(this)();
    if (v === END) return EMPTY;
    // Java 的 Optional 不收 null：第一個元素是 null 丟 NullPointerException。
    if (v == null) throw npe();
    return optionalOf(true, v, this._kind);
  };
  SP.findAny = SP.findFirst;
  SP.anyMatch = function(predicate) {
    var test = lambda(predicate, TEST), up = take(this), v;
    while ((v = up()) !== END) if (test(v)) return true;
    return false;
  };
  SP.allMatch = function(predicate) {
    var test = lambda(predicate, TEST), up = take(this), v;
    while ((v = up()) !== END) if (!test(v)) return false;
    return true;
  };
  SP.noneMatch = function(predicate) {
    var test = lambda(predicate, TEST), up = take(this), v;
    while ((v = up()) !== END) if (test(v)) return false;
    return true;
  };
  SP.reduce = function(identity, accumulator, combiner) {
    var kind = this._kind;
    if (arguments.length === 1) {
      var f1 = lambda(identity, BINARY), up1 = take(this);
      var acc = up1();
      if (acc === END) return optionalOf(false, null, kind);
      var v1;
      while ((v1 = up1()) !== END) acc = coerce(kind, f1(acc, v1));
      if (acc == null) throw npe();
      return optionalOf(true, acc, kind);
    }
    var f = lambda(accumulator, BINARY), up = take(this), value = identity, v;
    while ((v = up()) !== END) value = coerce(kind, f(value, v));
    return value;
  };
  function extreme(sign) {
    return function(comparator) {
      var cmp = comparatorOf(comparator), up = take(this), best = up(), v;
      if (best === END) return optionalOf(false, null, this._kind);
      while ((v = up()) !== END) if (sign * cmp(v, best) > 0) best = v;
      if (best == null) throw npe();
      return optionalOf(true, best, this._kind);
    };
  }
  SP.max = extreme(1);
  SP.min = extreme(-1);
  SP.sum = function() {
    var kind = this._kind, up = take(this), total = 0, v;
    while ((v = up()) !== END) total = kind === 'int' ? (total + v) | 0 : total + v;
    return total;
  };
  SP.average = function() {
    var up = take(this), total = 0, n = 0, v;
    while ((v = up()) !== END) { total += v; n++; }
    return optionalOf(n > 0, total / n, 'double');
  };
  SP.summaryStatistics = function() {
    var kind = this._kind, items = drain(take(this));
    var sum = items.reduce(function(a, b) { return a + b; }, 0);
    var stats = {
      getCount: function() { return items.length; },
      getSum: function() { return sum; },
      getMin: function() { return items.length ? Math.min.apply(null, items) : (kind === 'double' ? Infinity : 2147483647); },
      getMax: function() { return items.length ? Math.max.apply(null, items) : (kind === 'double' ? -Infinity : -2147483648); },
      getAverage: function() { return items.length ? sum / items.length : 0; }
    };
    return stats;
  };
  SP.iterator = function() {
    var up = take(this), next = null, has = false, ready = false;
    function peek() {
      if (!ready) { next = up(); has = next !== END; ready = true; }
    }
    return {
      hasNext: function() { peek(); return has; },
      next: function() {
        peek();
        if (!has) throw javaError('java.util.NoSuchElementException');
        ready = false;
        return next;
      }
    };
  };
  SP.collect = function(a, b, c) {
    var up = take(this), v;
    if (arguments.length >= 2) {
      // collect(supplier, accumulator, combiner)
      var container = lambda(a, APPLY)(), add = lambda(b, ['accept']);
      while ((v = up()) !== END) add(container, v);
      return container;
    }
    if (a == null || !a.__lrCollector) throw javaError('java.lang.ClassCastException', 'not a Collector');
    var c0 = a.__lrCollector, state = c0.init();
    while ((v = up()) !== END) state = c0.add(state, v);
    return c0.done(state);
  };
  named('Stream', Stream);

  // ─── Collectors ─────────────────────────────────────────────
  /// 收集器：init 開一個狀態，add 放一個元素（交回新的狀態），done 交出結果。
  function collector(init, add, done) {
    return { __lrCollector: { init: init, add: add, done: done || function(s) { return s; } } };
  }
  function intoList() {
    return collector(function() { return []; }, function(s, v) { s.push(v); return s; }, newList);
  }
  function asCollector(c) {
    if (c == null || !c.__lrCollector) throw javaError('java.lang.ClassCastException', 'not a Collector');
    return c.__lrCollector;
  }
  function newMap(factory) {
    if (factory == null) return new Packages.java.util.HashMap();
    var f = lambda(factory, APPLY);
    return f();
  }
  var Collectors = named('Collectors', {
    toList: intoList,
    toUnmodifiableList: intoList,
    toSet: function() {
      return collector(function() { return new Packages.java.util.HashSet(); },
        function(s, v) { s.add(v); return s; });
    },
    toCollection: function(supplier) {
      var f = lambda(supplier, APPLY);
      return collector(f, function(s, v) { s.add(v); return s; });
    },
    joining: function(separator, prefix, suffix) {
      var sep = separator == null ? '' : String(separator);
      return collector(function() { return []; },
        function(s, v) { s.push(String(v)); return s; },
        function(s) {
          return (prefix == null ? '' : String(prefix)) + s.join(sep) + (suffix == null ? '' : String(suffix));
        });
    },
    counting: function() {
      return collector(function() { return 0; }, function(s) { return s + 1; });
    },
    summingInt: function(fn) {
      var f = lambda(fn, APPLY);
      return collector(function() { return 0; }, function(s, v) { return (s + Number(f(v))) | 0; });
    },
    summingLong: function(fn) {
      var f = lambda(fn, APPLY);
      return collector(function() { return 0; }, function(s, v) { return s + Math.trunc(Number(f(v))); });
    },
    summingDouble: function(fn) {
      var f = lambda(fn, APPLY);
      return collector(function() { return 0; }, function(s, v) { return s + Number(f(v)); });
    },
    averagingInt: function(fn) { return averaging(fn); },
    averagingLong: function(fn) { return averaging(fn); },
    averagingDouble: function(fn) { return averaging(fn); },
    mapping: function(fn, downstream) {
      var f = lambda(fn, APPLY), d = asCollector(downstream);
      return collector(d.init, function(s, v) { return d.add(s, nul(f(v))); }, d.done);
    },
    filtering: function(predicate, downstream) {
      var test = lambda(predicate, TEST), d = asCollector(downstream);
      return collector(d.init, function(s, v) { return test(v) ? d.add(s, v) : s; }, d.done);
    },
    toMap: function(keyFn, valueFn, merge, factory) {
      var kf = lambda(keyFn, APPLY), vf = lambda(valueFn, APPLY);
      var mf = merge == null ? null : lambda(merge, BINARY);
      return collector(function() { return newMap(factory); }, function(map, item) {
        var k = nul(kf(item)), v = nul(vf(item));
        if (v == null) throw npe();
        if (map.containsKey(k)) {
          if (mf === null) {
            throw javaError('java.lang.IllegalStateException',
              'Duplicate key ' + k + ' (attempted merging values ' + map.get(k) + ' and ' + v + ')');
          }
          v = nul(mf(map.get(k), v));
        }
        if (v == null) map.remove(k); else map.put(k, v);
        return map;
      });
    },
    groupingBy: function(classifier, a, b) {
      var cf = lambda(classifier, APPLY);
      // groupingBy(分類) | groupingBy(分類, 下游) | groupingBy(分類, 容器, 下游)
      var factory = b === undefined ? null : a;
      var d = asCollector(b === undefined ? (a === undefined ? intoList() : a) : b);
      return collector(function() { return newMap(factory); }, function(map, item) {
        var k = cf(item);
        if (k == null) throw javaError('java.lang.NullPointerException', 'element cannot be mapped to a null key');
        map.put(k, d.add(map.containsKey(k) ? map.get(k) : d.init(), item));
        return map;
      }, function(map) {
        map.keySet().forEach(function(k) { map.put(k, d.done(map.get(k))); });
        return map;
      });
    },
    partitioningBy: function(predicate, downstream) {
      var test = lambda(predicate, TEST);
      var d = asCollector(downstream === undefined ? intoList() : downstream);
      return collector(function() { return { no: d.init(), yes: d.init() }; }, function(s, item) {
        if (test(item)) s.yes = d.add(s.yes, item); else s.no = d.add(s.no, item);
        return s;
      }, function(s) {
        var map = new Packages.java.util.LinkedHashMap();
        map.put(false, d.done(s.no));
        map.put(true, d.done(s.yes));
        return map;
      });
    }
  });
  function averaging(fn) {
    var f = lambda(fn, APPLY);
    return collector(function() { return { sum: 0, n: 0 }; }, function(s, v) {
      s.sum += Number(f(v));
      s.n++;
      return s;
    }, function(s) { return s.n ? s.sum / s.n : 0; });
  }

  // ─── 取得 Stream 的方法 ──────────────────────────────────────
  function varargs(args) {
    // Stream.of(陣列) 是那個陣列的元素，Stream.of(a, b) 是這幾個。
    return args.length === 1 && Array.isArray(args[0]) ? args[0] : Array.prototype.slice.call(args);
  }
  function generate(kind) {
    return {
      of: function() { return fromArray(varargs(arguments), kind); },
      empty: function() { return fromArray([], kind); },
      ofNullable: function(v) { return fromArray(v == null ? [] : [v], kind); },
      concat: function(a, b) {
        var first = take(a), second = take(b), onFirst = true;
        return new Stream(function() {
          if (onFirst) {
            var v = first();
            if (v !== END) return v;
            onFirst = false;
          }
          return second();
        }, kind);
      },
      generate: function(supplier) {
        var f = lambda(supplier, APPLY);
        return new Stream(function() { return coerce(kind, f()); }, kind);
      },
      // iterate(種子, 下一個) 沒有盡頭，iterate(種子, 還有嗎, 下一個) 到條件不成立為止。
      iterate: function(seed, hasNextOrNext, maybeNext) {
        var hasNext = maybeNext === undefined ? null : lambda(hasNextOrNext, TEST);
        var next = lambda(maybeNext === undefined ? hasNextOrNext : maybeNext, APPLY);
        var current = seed, started = false, finished = false;
        return new Stream(function() {
          if (finished) return END;
          if (started) current = coerce(kind, next(current));
          started = true;
          if (hasNext !== null && !hasNext(current)) { finished = true; return END; }
          return current;
        }, kind);
      }
    };
  }
  var StreamClass = Object.assign(Stream, generate('obj'));
  function primitive(kind) {
    var cls = generate(kind);
    cls.range = function(from, to) {
      var i = Number(from);
      return new Stream(function() { return i < to ? i++ : END; }, kind);
    };
    cls.rangeClosed = function(from, to) {
      var i = Number(from);
      return new Stream(function() { return i <= to ? i++ : END; }, kind);
    };
    return cls;
  }
  var IntStream = named('IntStream', primitive('int'));
  var LongStream = named('LongStream', primitive('long'));
  var DoubleStream = named('DoubleStream', primitive('double'));

  /// Arrays.stream(陣列[, 起, 訖])：數字陣列是 IntStream（有小數是 DoubleStream）。
  global.Arrays.stream = function(array, from, to) {
    if (array == null) throw npe();
    var items = Array.prototype.slice.call(array);
    if (from !== undefined) {
      if (from < 0 || to > items.length || from > to) throw javaError('java.lang.ArrayIndexOutOfBoundsException');
      items = items.slice(from, to);
    }
    var numeric = items.length > 0 && items.every(function(x) { return typeof x === 'number'; });
    var kind = numeric ? (items.every(function(x) { return Number.isInteger(x); }) ? 'int' : 'double') : 'obj';
    return fromArray(items, kind);
  };

  // 每一種 Java 清單（ArrayList、HashSet、規則交回的清單、Elements、Map.keySet()…）
  // 都是 JS 陣列，stream() 放在 Array.prototype，不可列舉。
  hide(Array.prototype, 'stream', function() { return fromArray(this, 'obj'); });
  hide(Array.prototype, 'parallelStream', function() { return fromArray(this, 'obj'); });

  var util = Packages.java.util;
  util.Optional = Optional;
  util.OptionalInt = Optional;
  util.OptionalLong = Optional;
  util.OptionalDouble = Optional;
  util.stream = {
    Stream: StreamClass,
    IntStream: IntStream,
    LongStream: LongStream,
    DoubleStream: DoubleStream,
    Collectors: Collectors
  };
  global.__lrJavaStream = fromArray;
})(globalThis);
''');
  }
}
