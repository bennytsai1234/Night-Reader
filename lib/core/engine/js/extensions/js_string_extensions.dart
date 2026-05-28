import 'dart:convert';
import 'package:html/parser.dart' as html_parser;
import 'package:fast_gbk/fast_gbk.dart';
import '../js_extensions.dart';
import 'package:reader/core/services/chinese_utils.dart';

extension JsStringExtensions on JsExtensions {
  void injectStringExtensions() {
    runtime.evaluate(r'''
      (function() {
        var __lrNativeStringMatch = String.prototype.match;

        function __lrJavaRegex(pattern, globalMode) {
          if (pattern instanceof RegExp) {
            var flags = pattern.flags || '';
            if (globalMode && flags.indexOf('g') === -1) {
              flags += 'g';
            }
            if (!globalMode) {
              flags = flags.replace(/g/g, '');
            }
            return new RegExp(pattern.source, flags);
          }
          return new RegExp(String(pattern), globalMode ? 'g' : '');
        }

        globalThis.__lrJavaReplaceAll = function(value, pattern, replacement) {
          var input = String(value == null ? '' : value);
          try {
            return input.replace(__lrJavaRegex(pattern, true), replacement);
          } catch (e) {
            return input.split(String(pattern)).join(String(replacement));
          }
        };

        globalThis.__lrJavaReplaceFirst = function(value, pattern, replacement) {
          var input = String(value == null ? '' : value);
          try {
            return input.replace(__lrJavaRegex(pattern, false), replacement);
          } catch (e) {
            return input.replace(String(pattern), String(replacement));
          }
        };

        globalThis.__lrJavaMatch = function(value, pattern) {
          var input = String(value == null ? '' : value);
          if (pattern instanceof RegExp) {
            return __lrNativeStringMatch.call(input, pattern);
          }
          try {
            return __lrNativeStringMatch.call(input, new RegExp(String(pattern)));
          } catch (e) {
            var text = String(pattern);
            return input.indexOf(text) !== -1 ? [text] : null;
          }
        };

        String.prototype.replaceAll = function(pattern, replacement) {
          return globalThis.__lrJavaReplaceAll(this, pattern, replacement);
        };

        String.prototype.match = function(pattern) {
          return globalThis.__lrJavaMatch(this, pattern);
        };

        if (typeof String.prototype.replaceFirst !== 'function') {
          String.prototype.replaceFirst = function(pattern, replacement) {
            return globalThis.__lrJavaReplaceFirst(this, pattern, replacement);
          };
        }

        if (typeof String.prototype.contains !== 'function') {
          String.prototype.contains = function(value) {
            return String(this).indexOf(String(value)) !== -1;
          };
        }

        if (typeof globalThis.unpack !== 'function') {
          globalThis.unpack = function(p, a, c, k, e, d) {
            e = function(index) {
              return (index < a ? '' : e(parseInt(index / a))) +
                ((index = index % a) > 35
                  ? String.fromCharCode(index + 29)
                  : index.toString(36));
            };
            d = d || {};
            for (var i = c - 1; i >= 0; i--) {
              if (k[i]) {
                d[e(i)] = k[i];
              }
            }
            return String(p).replace(/\b\w+\b/g, function(token) {
              return Object.prototype.hasOwnProperty.call(d, token)
                ? d[token]
                : token;
            });
          };
        }
      })();
    ''');

    // 實作 java.strToBytes
    runtime.onMessage('strToBytes', (dynamic args) {
      final payload = _decodeArgs(args);
      final str =
          payload is List && payload.isNotEmpty
              ? payload[0].toString()
              : payload.toString();
      final charset =
          payload is List && payload.length > 1
              ? payload[1].toString()
              : 'UTF-8';
      if (charset.toUpperCase().contains('GBK') ||
          charset.toUpperCase().contains('GB2312')) {
        return jsonEncode(gbk.encode(str));
      }
      return jsonEncode(utf8.encode(str));
    });

    // 實作 java.bytesToStr
    runtime.onMessage('bytesToStr', (dynamic args) {
      final payload = _decodeArgs(args);
      final bytesSource =
          payload is List && payload.isNotEmpty ? payload[0] : payload;
      final bytes = List<int>.from(bytesSource as List);
      final charset =
          payload is List && payload.length > 1
              ? payload[1].toString()
              : 'UTF-8';
      if (charset.toUpperCase().contains('GBK') ||
          charset.toUpperCase().contains('GB2312')) {
        return gbk.decode(bytes);
      }
      return utf8.decode(bytes);
    });

    runtime.onMessage('_timeFormat', (dynamic args) {
      final time = args;
      final t = time is int ? time : int.tryParse(time.toString()) ?? 0;
      return DateTime.fromMillisecondsSinceEpoch(t).toIso8601String();
    });

    runtime.onMessage('_htmlFormat', (dynamic args) {
      final doc = html_parser.parse(args.toString());
      return doc.body?.text ?? '';
    });

    runtime.onMessage(
      't2s',
      (dynamic args) => ChineseUtils.t2s(args.toString()),
    );
    runtime.onMessage(
      's2t',
      (dynamic args) => ChineseUtils.s2t(args.toString()),
    );

    // 實作 java.toNumChapter ((原 Android ))
    runtime.onMessage('_toNumChapter', (dynamic args) {
      final s = args.toString();
      final regex = RegExp(r'(.*?)([〇零一二三四五六七八九十百千萬億壹貳叁肆伍陸柒捌玖拾佰仟]+)(.*)');
      final match = regex.firstMatch(s);
      if (match != null) {
        final intStr = chineseNumToInt(match.group(2)!);
        return '${match.group(1)}$intStr${match.group(3)}';
      }
      return s;
    });
  }

  dynamic _decodeArgs(dynamic args) {
    if (args is String) {
      try {
        return jsonDecode(args);
      } catch (_) {
        return args;
      }
    }
    return args;
  }

  /// 中文數字轉整數 (深度還原 Android chineseNumToInt)
  int chineseNumToInt(String chNum) {
    final chnMap = {
      '零': 0,
      '〇': 0,
      '一': 1,
      '二': 2,
      '两': 2,
      '三': 3,
      '四': 4,
      '五': 5,
      '六': 6,
      '七': 7,
      '八': 8,
      '九': 9,
      '十': 10,
      '壹': 1,
      '貳': 2,
      '叁': 3,
      '肆': 4,
      '伍': 5,
      '陸': 6,
      '柒': 7,
      '捌': 8,
      '玖': 9,
      '拾': 10,
      '百': 100,
      '佰': 100,
      '千': 1000,
      '仟': 1000,
      '萬': 10000,
      '億': 100000000,
    };

    if (chNum.length > 1 &&
        RegExp(r'^[〇零一二三四五六七八九壹貳叁肆伍陸柒捌玖]+$').hasMatch(chNum)) {
      var res = '';
      for (var i = 0; i < chNum.length; i++) {
        res += (chnMap[chNum[i]] ?? 0).toString();
      }
      return int.tryParse(res) ?? -1;
    }

    var result = 0;
    var tmp = 0;
    var billion = 0;

    try {
      for (var i = 0; i < chNum.length; i++) {
        final val = chnMap[chNum[i]] ?? 0;
        if (val == 100000000) {
          result += tmp;
          result *= val;
          billion = billion * 100000000 + result;
          result = 0;
          tmp = 0;
        } else if (val == 10000) {
          result += tmp;
          result *= val;
          tmp = 0;
        } else if (val >= 10) {
          if (tmp == 0) tmp = 1;
          result += val * tmp;
          tmp = 0;
        } else {
          tmp =
              (i >= 2 &&
                      i == chNum.length - 1 &&
                      (chnMap[chNum[i - 1]] ?? 0) > 10)
                  ? val * (chnMap[chNum[i - 1]] ?? 0) ~/ 10
                  : tmp * 10 + val;
        }
      }
      return result + tmp + billion;
    } catch (_) {
      return -1;
    }
  }
}
