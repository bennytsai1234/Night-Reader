import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

const Set<String> kSupportedLocalBookExtensions = {'txt', 'epub'};

bool isSupportedLocalBookExtension(String ext) {
  final normalized = ext.startsWith('.') ? ext.substring(1) : ext;
  return kSupportedLocalBookExtensions.contains(normalized.toLowerCase());
}

String localBookExtensionFromPath(String path) {
  final filePath = path.startsWith('local://')
      ? path.substring('local://'.length)
      : path;
  return p.extension(filePath).replaceFirst('.', '').toLowerCase();
}

bool isSupportedLocalBookPath(String path) {
  final extension = localBookExtensionFromPath(path);
  return extension.isNotEmpty && isSupportedLocalBookExtension(extension);
}

/// 本地書一章在檔案裡的位元組範圍（TXT 是原檔，EPUB 是轉好的文字）；
/// [isVolume] 是分卷（目錄裡的卷名列，同 Legado）。
typedef LocalChapterRange = ({String title, int start, int end, bool isVolume});

/// 書的資料夾裡記下的章節範圍（EPUB 的 `epub-chapters.json`、TXT 的
/// `txt-chapters.json`）：`{version, chapters: [[章名, start, end, 是不是分卷], …]}`。
/// 沒有、[version] 不對或壞了時回傳 null。同步讀檔，在背景 isolate 呼叫。
List<LocalChapterRange>? readChapterRanges(String path, int version) {
  try {
    final json = jsonDecode(File(path).readAsStringSync());
    if (json is! Map<String, Object?> || json['version'] != version) {
      return null;
    }
    return [
      for (final value in json['chapters'] as List<Object?>)
        if (value case [
          final String title,
          final int start,
          final int end,
          final bool isVolume,
        ])
          (title: title, start: start, end: end, isVolume: isVolume)
        else
          throw const FormatException('Malformed local chapter range.'),
    ];
  } on FileSystemException {
    return null;
  } on FormatException {
    return null;
  } on TypeError {
    return null;
  }
}

/// 把 [ranges] 照 [version] 寫進 [path]（格式見 [readChapterRanges]）：先寫
/// 旁邊的暫存檔再換上，寫到一半被關掉也不留半份。同步寫檔。
void writeChapterRanges(
  String path,
  int version,
  List<LocalChapterRange> ranges,
) {
  final temp = File(
    '$path.${DateTime.now().microsecondsSinceEpoch}.'
    '${identityHashCode(ranges)}.tmp',
  );
  temp.parent.createSync(recursive: true);
  try {
    temp.writeAsStringSync(
      jsonEncode({
        'version': version,
        'chapters': [
          for (final range in ranges)
            [range.title, range.start, range.end, range.isVolume],
        ],
      }),
      flush: true,
    );
    temp.renameSync(path);
  } catch (_) {
    try {
      if (temp.existsSync()) temp.deleteSync();
    } on FileSystemException {
      // 清除失敗不蓋掉原本的寫入錯誤。
    }
    rethrow;
  }
}
