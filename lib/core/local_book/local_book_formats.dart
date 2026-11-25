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
