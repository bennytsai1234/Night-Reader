// 重新產生 lib/core/utils/public_suffix_rules.dart：
//
//   dart run tool/public_suffix.dart
//
// 從 publicsuffix.org 抓最新的公共字尾表，ICANN 與私人網域兩段都收（同 OkHttp
// 的 PublicSuffixDatabase，Legado 用它算 Cookie 的網域）。
import 'dart:convert';
import 'dart:io';

const _source = 'https://publicsuffix.org/list/public_suffix_list.dat';
const _output = 'lib/core/utils/public_suffix_rules.dart';

Future<void> main() async {
  final client = HttpClient();
  final response = await (await client.getUrl(Uri.parse(_source))).close();
  if (response.statusCode != 200) {
    stderr.writeln('抓公共字尾表失敗：HTTP ${response.statusCode}');
    exit(1);
  }
  final text = await response.transform(utf8.decoder).join();
  client.close();

  final rules = <String>{};
  for (final line in LineSplitter.split(text)) {
    // 規則是一行開頭到第一個空白為止，`//` 開頭的是註解。
    final rule = line.trim().split(RegExp(r'\s')).first.toLowerCase();
    if (rule.isEmpty || rule.startsWith('//')) continue;
    if (rule.contains(RegExp(r"['\\$]"))) {
      stderr.writeln('規則含有不能直接放進字串的字元：$rule');
      exit(1);
    }
    rules.add(rule);
  }
  if (rules.length < 5000) {
    stderr.writeln('只抓到 ${rules.length} 條規則，表可能不完整');
    exit(1);
  }

  final date = DateTime.now().toIso8601String().substring(0, 10);
  final out = StringBuffer()
    ..writeln('// 由 tool/public_suffix.dart 產生，不要手改；$date 抓自 $_source')
    ..writeln('//')
    ..writeln('// 公共字尾表依 Mozilla Public License 2.0 授權：')
    ..writeln('// https://mozilla.org/MPL/2.0/')
    ..writeln()
    ..writeln('/// 公共字尾表的規則：`*.` 開頭是萬用、`!` 開頭是例外。照')
    ..writeln('/// [String.compareTo] 排好，用二分搜尋找；不用 Set 是因為常數 Set')
    ..writeln('/// 第一次查時才建一萬筆的雜湊索引，那一幀會多花幾毫秒。')
    ..writeln('const publicSuffixRules = <String>[');
  for (final rule in rules.toList()..sort()) {
    out.writeln("  '$rule',");
  }
  out.writeln('];');
  File(_output).writeAsStringSync(out.toString());
  stdout.writeln('寫入 $_output：${rules.length} 條規則');
}
