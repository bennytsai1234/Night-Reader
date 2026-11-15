// AI 修復的評估表（agent-harness 技能 references/evaluation.md「評估模組」）：把
// 完整修復紀錄裡每一件的統計那一行（NR-AI-REPAIR-STATS）整理成一件一列的
// Markdown 表，最後一行是總計。比的是回合數、耗時、快取命中率；用量
// 只拿來算命中率（命中快取的輸入 ÷ 全部輸入）。
//
//   dart run tool/ai_repair_table.dart <紀錄資料夾或檔案…> [--out 表.md]
//
// 紀錄是手機「分享完整紀錄」的檔，或 test/live/source_repair_batch_live_test.dart
// 跑完留在暫存資料夾 ai-repair/ 下的檔。每次跑的表存下來，跟上一次比。
import 'dart:convert';
import 'dart:io';

const _marker = 'NR-AI-REPAIR-STATS ';

void main(List<String> args) {
  String? out;
  final inputs = <String>[];
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--out' && i + 1 < args.length) {
      out = args[++i];
    } else {
      inputs.add(args[i]);
    }
  }
  if (inputs.isEmpty) {
    stderr.writeln(
      '用法：dart run tool/ai_repair_table.dart <紀錄資料夾或檔案…> [--out 表.md]',
    );
    exitCode = 64;
    return;
  }
  final rows = <Map<String, dynamic>>[];
  for (final input in inputs) {
    final files = FileSystemEntity.isDirectorySync(input)
        ? [
            for (final entity in Directory(input).listSync())
              if (entity is File && entity.path.endsWith('.txt')) entity,
          ]
        : [File(input)];
    files.sort((a, b) => a.path.compareTo(b.path));
    for (final file in files) {
      for (final line in file.readAsLinesSync()) {
        if (!line.startsWith(_marker)) continue;
        rows.add(
          (jsonDecode(line.substring(_marker.length)) as Map<String, dynamic>)
            ..['file'] = file.uri.pathSegments.last,
        );
      }
    }
  }
  final table = _table(rows);
  if (out == null) {
    stdout.write(table);
  } else {
    File(out).writeAsStringSync(table);
    stdout.writeln('${rows.length} 件寫進 $out');
  }
}

/// 交件被收下、判定修好了。
bool _succeeded(Map<String, dynamic> row) => row['outcome'] == 'repaired';

int _int(Map<String, dynamic> row, String key) =>
    (row[key] as num? ?? 0).toInt();

/// 交件內容：修好、修不好（放棄原因），或沒有交件就結束。
String _verdict(Map<String, dynamic> row) {
  if (_succeeded(row)) return '修好';
  if (row['unfixable'] == true) {
    final why = row['why'];
    return why == null ? '修不好' : '修不好：$why';
  }
  return '沒交件';
}

/// 命中快取的輸入 ÷ 全部輸入；沒有輸入時是空的。
String _hitRate(int cached, int prompt) =>
    prompt == 0 ? '' : '${(cached * 100 / prompt).toStringAsFixed(0)}%';

String _seconds(int ms) => (ms / 1000).toStringAsFixed(0);

String _table(List<Map<String, dynamic>> rows) {
  int sum(String key) => rows.fold(0, (total, row) => total + _int(row, key));
  final buffer = StringBuffer()
    ..writeln(
      '| 書源 | 交件 | 結束 | 輪 | 等 AI 秒 | 工具秒 | 其他秒 | 快取命中 '
      '| 讀不懂 | 沒指令 | 卡住 | 交出被退 | 跑幾次 |',
    )
    ..writeln('|${' --- |' * 13}');
  for (final row in rows) {
    final cells = [
      row['source'],
      _verdict(row),
      '${row['end']}：${row['reason']}',
      row['rounds'],
      _seconds(_int(row, 'modelMs')),
      _seconds(_int(row, 'toolsMs')),
      _seconds(_int(row, 'otherMs')),
      _hitRate(_int(row, 'cached'), _int(row, 'prompt')),
      row['badCommands'],
      row['noCommands'],
      row['stalls'],
      row['rejections'],
      row['attempts'],
    ];
    buffer.writeln(
      '| ${cells.map((cell) => '$cell'.replaceAll('|', '／')).join(' | ')} |',
    );
  }
  final succeeded = rows.where(_succeeded).length;
  final versions = {for (final row in rows) row['promptVersion']}.join('、');
  final rounds = rows.isEmpty
      ? '0'
      : (sum('rounds') / rows.length).toStringAsFixed(1);
  buffer
    ..writeln()
    ..writeln(
      '共 ${rows.length} 件（成功 $succeeded、失敗 ${rows.length - succeeded}）；'
      '平均 $rounds 輪；等 AI ${_seconds(sum('modelMs'))} 秒、'
      '工具 ${_seconds(sum('toolsMs'))} 秒、其他 ${_seconds(sum('otherMs'))} 秒；'
      '快取命中 ${_hitRate(sum('cached'), sum('prompt'))}；提示詞 $versions。',
    );
  return buffer.toString();
}
