// AI 修復的評估表（agent-harness 技能「評估模組」）：把完整修復紀錄裡每一件
// 的統計那一行（NR-AI-REPAIR-STATS）整理成一件一列的 Markdown 表。
//
//   dart run tool/ai_repair_table.dart <紀錄資料夾或檔案…> [--out 表.md]
//
// 紀錄是手機「分享完整紀錄」的檔，或 test/live/source_repair_batch_live_test.dart
// 跑完留在暫存資料夾 ai-repair/ 下的檔。每次跑的表存下來，跟上一次比；同一份
// 輸入重跑幾次再下結論。
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

String _table(List<Map<String, dynamic>> rows) {
  String seconds(Object? ms) => ((ms as num? ?? 0) / 1000).toStringAsFixed(0);
  int sum(String key) =>
      rows.fold(0, (total, row) => total + ((row[key] as num?) ?? 0).toInt());
  final buffer = StringBuffer()
    ..writeln(
      '| 書源 | 結束 | 結果 | 跑幾次 | 輪 | 指令 | 交出被退 | 讀不懂 | 沒指令 | 卡住 '
      '| 送出 token | 快取 | 回覆 | 思考 | 等 AI 秒 | 工具秒 | 其他秒 | 提示詞 | 原因 |',
    )
    ..writeln('|${' --- |' * 19}');
  for (final row in rows) {
    final cells = [
      row['source'],
      row['end'],
      row['outcome'] ?? '',
      row['attempts'],
      row['rounds'],
      row['toolCalls'],
      row['rejections'],
      row['badCommands'],
      row['noCommands'],
      row['stalls'],
      row['prompt'],
      row['cached'],
      row['completion'],
      row['reasoning'],
      seconds(row['modelMs']),
      seconds(row['toolsMs']),
      seconds(row['otherMs']),
      row['promptVersion'],
      '${row['reason']}'.replaceAll('|', '／'),
    ];
    buffer.writeln('| ${cells.join(' | ')} |');
  }
  final ends = <String, int>{};
  for (final row in rows) {
    ends.update('${row['end']}', (n) => n + 1, ifAbsent: () => 1);
  }
  buffer
    ..writeln()
    ..writeln(
      '共 ${rows.length} 件（${ends.entries.map((e) => '${e.key} ${e.value}').join('、')}）；'
      '送出 ${sum('prompt')} token（快取 ${sum('cached')}）、回覆 ${sum('completion')}'
      '（思考 ${sum('reasoning')}）；等 AI ${seconds(sum('modelMs'))} 秒、'
      '工具 ${seconds(sum('toolsMs'))} 秒。',
    );
  return buffer.toString();
}
