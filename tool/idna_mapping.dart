// 重新產生 lib/core/utils/idna_mapping_table.dart：
//
//   dart run tool/idna_mapping.dart
//
// 從 unicode.org 抓最新的 UTS #46 對應表（IdnaMappingTable.txt）。書源網址的
// 中文網域照它換成 punycode，同 Legado 用的 OkHttp（它內建同一份表）。
import 'dart:convert';
import 'dart:io';

const _source =
    'https://www.unicode.org/Public/idna/latest/IdnaMappingTable.txt';
const _output = 'lib/core/utils/idna_mapping_table.dart';

/// 和 lib/core/utils/idna.dart 的 [IdnaStatus] 順序相同。
const _kinds = ['valid', 'ignored', 'mapped', 'deviation', 'disallowed'];

Future<void> main() async {
  final client = HttpClient();
  final response = await (await client.getUrl(Uri.parse(_source))).close();
  if (response.statusCode != 200) {
    stderr.writeln('抓 UTS #46 對應表失敗：HTTP ${response.statusCode}');
    exit(1);
  }
  final text = await response.transform(utf8.decoder).join();
  client.close();

  final version = RegExp(
    r'^# Version: (\S+)',
    multiLine: true,
  ).firstMatch(text)?.group(1);
  // 每一段：起點、狀態、對應的字（只有 mapped 有；表裡一個範圍整段對應到
  // 同一個字）。相鄰、狀態與對應字都相同的段落合併。
  final starts = <int>[];
  final kinds = <int>[];
  final mappings = <String>[];
  var next = 0;
  for (final line in LineSplitter.split(text)) {
    final body = line.split('#').first.trim();
    if (body.isEmpty) continue;
    final fields = body.split(';').map((f) => f.trim()).toList();
    final range = fields[0].split('..');
    final first = int.parse(range.first, radix: 16);
    final last = int.parse(range.last, radix: 16);
    final kind = _kinds.indexOf(fields[1]);
    if (kind < 0) {
      stderr.writeln('不認得的狀態：${fields[1]}（$line）');
      exit(1);
    }
    if (first != next) {
      stderr.writeln('碼位沒有接續：預期 ${next.toRadixString(16)}，是 $line');
      exit(1);
    }
    next = last + 1;
    final mapped = kind == 2
        ? String.fromCharCodes([
            for (final cp in fields[2].split(' ')) int.parse(cp, radix: 16),
          ])
        : '';
    if (kinds.isNotEmpty && kinds.last == kind && mappings.last == mapped) {
      continue;
    }
    starts.add(first);
    kinds.add(kind);
    mappings.add(mapped);
  }
  if (next != 0x110000 || starts.length < 3000) {
    stderr.writeln('表不完整：到 ${next.toRadixString(16)}、${starts.length} 段');
    exit(1);
  }

  String literal(String s) {
    final buffer = StringBuffer("'");
    for (final rune in s.runes) {
      final printable =
          rune >= 0x20 &&
          rune < 0x7f &&
          rune != 0x27 &&
          rune != 0x5c &&
          rune != 0x24;
      buffer.write(
        printable
            ? String.fromCharCode(rune)
            : '\\u{${rune.toRadixString(16)}}',
      );
    }
    return (buffer..write("'")).toString();
  }

  final date = DateTime.now().toIso8601String().substring(0, 10);
  final out = StringBuffer()
    ..writeln('// 由 tool/idna_mapping.dart 產生，不要手改；$date 抓自 $_source')
    ..writeln('// （UTS #46 第 $version 版）')
    ..writeln('//')
    ..writeln('// Unicode 資料依 Unicode License v3 授權：')
    ..writeln('// https://www.unicode.org/license.txt')
    ..writeln()
    ..writeln('/// 每一段的起點碼位，照大小排好；一個碼位的狀態是起點不大於它的最後')
    ..writeln('/// 一段（二分搜尋）。')
    ..writeln('const idnaRangeStarts = <int>[');
  for (var i = 0; i < starts.length; i += 12) {
    out.writeln(
      '  ${starts.skip(i).take(12).map((s) => '0x${s.toRadixString(16)}').join(', ')},',
    );
  }
  out
    ..writeln('];')
    ..writeln()
    ..writeln('/// 各段的狀態：0 valid、1 ignored、2 mapped、3 deviation、4 disallowed。')
    ..writeln('const idnaRangeKinds = <int>[');
  for (var i = 0; i < kinds.length; i += 40) {
    out.writeln('  ${kinds.skip(i).take(40).join(', ')},');
  }
  out
    ..writeln('];')
    ..writeln()
    ..writeln('/// mapped 段換成的字；其他狀態是空字串。')
    ..writeln('const idnaRangeMappings = <String>[');
  for (final m in mappings) {
    out.writeln('  ${literal(m)},');
  }
  out.writeln('];');
  File(_output).writeAsStringSync(out.toString());
  // 排成 dart format 的樣子，重新產生時只有內容的差異。
  final format = Process.runSync('dart', ['format', _output], runInShell: true);
  if (format.exitCode != 0) {
    stderr.writeln('dart format 失敗：${format.stderr}');
    exit(1);
  }
  stdout.writeln('寫入 $_output：UTS #46 第 $version 版，${starts.length} 段');
}
