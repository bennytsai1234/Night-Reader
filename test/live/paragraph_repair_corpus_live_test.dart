/// 拿 `chapter_text_live_test.dart` 從真網站抓回的正文，列出段落修復
/// （[SemanticParagraphFormatter]）在每一章合併了哪些行、各是哪條規則合的，
/// 給人逐條看有沒有誤合併。不連網。
///
/// ```sh
/// NR_RAW_DIR=<抓回正文的資料夾> NR_REPORT=<輸出 JSON> \
///   tool/flutter_test.sh --run-skipped -t live test/live/paragraph_repair_corpus_live_test.dart
/// ```
///
/// 正文照 App 轉換時的順序處理：插圖換成記號、每行去掉頭尾空白（替換規則
/// 開著時 `_applyRules` 做的），再修復段落。報告每一筆是一個被合併的接縫：
/// 規則、上一行結尾、下一行開頭。
@Tags(['live'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/utils/illustration_markers.dart';
import 'package:night_reader/features/reader_v2/chapter/semantic_paragraph_formatter.dart';

void main() {
  final env = Platform.environment;
  final rawDir = env['NR_RAW_DIR'];
  final reportPath = env['NR_REPORT'];
  if (rawDir == null || reportPath == null) {
    test('NR_RAW_DIR', () => fail('用 NR_RAW_DIR 指定正文資料夾、NR_REPORT 指定輸出'));
    return;
  }

  test('段落修復合併了哪些行', () {
    final entries = File('$rawDir/index.jsonl')
        .readAsLinesSync()
        .where((line) => line.trim().isNotEmpty)
        .map((line) => jsonDecode(line) as Map<String, dynamic>)
        .toList();
    final chapters = <Map<String, Object?>>[];
    final ruleCounts = <String, int>{};
    var linesBefore = 0;
    var linesAfter = 0;
    for (final entry in entries) {
      final raw = File('$rawDir/${entry['file']}').readAsStringSync();
      final text = IllustrationMarkers.extract(raw).text
          .replaceAll('\r\n', '\n')
          .replaceAll('\r', '\n')
          .split('\n')
          .map((line) => line.trim())
          .join('\n');
      final input = text.split('\n');
      final output = SemanticParagraphFormatter.repair(text).split('\n');
      final joins = _joins(input, output);
      for (final join in joins) {
        ruleCounts.update(join['rule']!, (n) => n + 1, ifAbsent: () => 1);
      }
      final before = input.where((line) => line.isNotEmpty).length;
      final after = output.where((line) => line.isNotEmpty).length;
      linesBefore += before;
      linesAfter += after;
      chapters.add({
        ...entry,
        'paragraphsBefore': before,
        'paragraphsAfter': after,
        'joins': joins,
      });
    }
    File(reportPath).writeAsStringSync(
      const JsonEncoder.withIndent(' ').convert({
        'chapters': chapters.length,
        'paragraphsBefore': linesBefore,
        'paragraphsAfter': linesAfter,
        'rules': ruleCounts,
        'detail': chapters,
      }),
    );
    debugPrint(
      '##### ${chapters.length} 章，段落 $linesBefore → $linesAfter，'
      '合併 ${linesBefore - linesAfter} 處：$ruleCounts',
    );
  });
}

/// 對照修復前後的行，找出被接起來的相鄰兩行。修復只刪換行與接縫兩側的
/// 空白，所以照順序一行一行吃就對得上。
List<Map<String, String>> _joins(List<String> input, List<String> output) {
  final joins = <Map<String, String>>[];
  var i = 0;
  for (final line in output) {
    var built = input[i];
    i++;
    while (built != line && i < input.length) {
      final left = built;
      final right = input[i];
      joins.add({
        'rule': _ruleOf(left, right),
        'left': _tail(left),
        'right': _head(right),
      });
      built = left.trimRight() + right.trimLeft();
      i++;
    }
  }
  return joins;
}

String _ruleOf(String left, String right) {
  final l = left.replaceAll(RegExp('[-]'), '').trimRight();
  final r = right.replaceAll(RegExp('[-]'), '').trimLeft();
  if (r.isNotEmpty && '，。、；：！？」』）】》〉〕｝”’'.contains(r[0])) {
    return 'closing-start';
  }
  if (l.isNotEmpty && '「『（【《〈〔｛“‘'.contains(l[l.length - 1])) {
    return 'opening-end';
  }
  if ((l.endsWith('…') && r.startsWith('…')) ||
      (l.endsWith('—') && r.startsWith('—'))) {
    return 'split-pair';
  }
  return 'fixed-width';
}

String _tail(String text) =>
    text.length <= 24 ? text : text.substring(text.length - 24);

String _head(String text) => text.length <= 24 ? text : text.substring(0, 24);
