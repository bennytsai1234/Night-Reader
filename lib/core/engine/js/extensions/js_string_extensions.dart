import 'dart:convert';

import 'package:html/parser.dart' as html_parser;

import '../encode/charsets.dart';
import '../js_extensions.dart';

import 'package:night_reader/core/services/chinese_utils.dart';
import 'package:night_reader/core/utils/string_utils.dart';

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
      final payload = args;
      final str = payload is List && payload.isNotEmpty
          ? payload[0].toString()
          : payload.toString();
      final charset = payload is List && payload.length > 1
          ? payload[1]?.toString()
          : null;
      return jsonEncode(Charsets.encode(str, charset).toList());
    });

    // 實作 java.bytesToStr
    runtime.onMessage('bytesToStr', (dynamic args) {
      final payload = args;
      final bytesSource = payload is List && payload.isNotEmpty
          ? payload[0]
          : payload;
      final bytes = List<int>.from(bytesSource as List);
      final charset = payload is List && payload.length > 1
          ? payload[1]?.toString()
          : null;
      return Charsets.decode(bytes, charset);
    });

    // java.encodeURI(str[, enc])：Java 的 URLEncoder（空白變 +）；字元集
    // 不認得時傳回空字串，同 Legado。
    runtime.onMessage('_urlEncode', (dynamic args) {
      final payload = args is List ? args : [args];
      try {
        return Charsets.urlEncode(
          payload[0]?.toString() ?? '',
          payload.length > 1 ? payload[1]?.toString() : null,
        );
      } on UnsupportedError {
        return '';
      }
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

    // java.toNumChapter：章名裡第一段中文數字換成阿拉伯數字，認得的字與
    // 換算都照 [StringUtils]，簡體、繁體與大寫數字一樣。
    runtime.onMessage('_toNumChapter', (dynamic args) {
      final s = args.toString();
      final match = StringUtils.chineseNumberRun.firstMatch(s);
      if (match == null) return s;
      final number = StringUtils.chineseNumToInt(match.group(0)!);
      if (number < 0) return s;
      return s.replaceRange(match.start, match.end, '$number');
    });
  }
}
